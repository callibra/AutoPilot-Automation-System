$global:RecordingStateFile = "$PSScriptRoot\Autopilot_Data\last_recording.json"
$global:CameraRecordingStateFile = "$PSScriptRoot\Autopilot_Data\last_camera_recording.json"
$global:CameraFolder = "$PSScriptRoot\Camera"

$configPath = "$PSScriptRoot\JSON\settings.json"

# Проверка дали JSON fajlot postoji
if (-not (Test-Path $configPath)) {
    Write-Host "SETTINGS file not found: $configPath" -ForegroundColor Red
    $global:ConfigValid = $false
} else {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $global:ConfigValid = $true
    } catch {
        Write-Host "SETTINGS file is not a valid JSON!" -ForegroundColor Red
        $global:ConfigValid = $false
    }
}

# Initialize global status variables
$global:ScreenCaptureConfigured = $false
$global:CameraCaptureConfigured = $false
$global:MediaFolderConfigured  = $false

################# FUNCTIONS Auto-Detect ffmpeg Devices #####################
# Patterns used to pick the right device when settings.json is empty or the saved device does not work
$global:LoopbackPattern = 'stereo\s*mix|stereomix|what u hear|wave out|loopback|стерео|микс'
$global:MicPattern      = 'microphone|mic\b|mikrofon|микрофон|array'
$global:MainMicPattern  = '^(microphone|mikrofon|микрофон)\b'   # standard Windows name: "Microphone (Realtek ...)"
$global:VirtualCamPattern = 'virtual|obs|droidcam|manycam|snap camera|epoccam|ndi'

# Returns @{ Ok; Video = @(...); Audio = @(...) } from: ffmpeg -list_devices true -f dshow -i dummy
function Get-FfmpegDshowDevices {
    $result = @{ Ok = $false; Video = @(); Audio = @() }
    $ffmpegExe = Join-Path -Path $PSScriptRoot -ChildPath "ffmpeg\bin\ffmpeg.exe"
    if (-not (Test-Path $ffmpegExe)) { return $result }

    $ErrorActionPreference = 'Continue'
    $oldEnc = $null
    $lines = @()
    try {
        try { $oldEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ffmpegExe
        $psi.Arguments = '-hide_banner -list_devices true -f dshow -i dummy'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $true
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $p = [System.Diagnostics.Process]::Start($psi)
        $errTask = $p.StandardError.ReadToEndAsync()
        $outText = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        $lines = @(($errTask.Result + "`n" + $outText) -split "`r?`n")
    } catch {
        return $result
    } finally {
        if ($oldEnc) { try { [Console]::OutputEncoding = $oldEnc } catch {} }
    }

    foreach ($line in $lines) {
        if ($line -match 'Alternative name') { continue }
        if ($line -match '"([^"]+)"\s+\(([^)]*)\)') {
            $name = $matches[1]
            $type = $matches[2]
            if ($type -match 'video') { $result.Video += $name }
            if ($type -match 'audio') { $result.Audio += $name }
        }
    }
    $result.Ok = $true
    return $result
}

# Sets $Config.<Section>.<Name> = $Value (creates the section / property if missing)
function Set-SettingsValue {
    param($Config, [string]$Section, [string]$Name, $Value)
    if (-not $Config.$Section) {
        $new = [PSCustomObject]@{}
        if ($Config.PSObject.Properties[$Section]) { $Config.$Section = $new }
        else { Add-Member -InputObject $Config -NotePropertyName $Section -NotePropertyValue $new }
    }
    $sec = $Config.$Section
    if ($sec.PSObject.Properties[$Name]) { $sec.$Name = $Value }
    else { Add-Member -InputObject $sec -NotePropertyName $Name -NotePropertyValue $Value }
}

# If the devices in settings.json are empty or do not exist -> find them with ffmpeg and save them to settings.json
# If they are filled in and they exist -> nothing is changed
function Initialize-MediaDevices {
    param($Config, [string]$ConfigPath)

    $devs = Get-FfmpegDshowDevices
    if (-not $devs.Ok) { return }   # ffmpeg missing or failed -> leave settings as they are
    $videoList = @($devs.Video)
    $audioList = @($devs.Audio)
    $changed = $false
    # ---- ScreenCapture (audio device is needed only if IncludeAudio = true) ----
    $scrExists  = [bool]$Config.ScreenCapture
    $scrAudioOn = if ($scrExists) { [bool]$Config.ScreenCapture.IncludeAudio } else { $true }
    if ($scrAudioOn) {
        $cur = if ($scrExists) { "$($Config.ScreenCapture.AudioDevice)".Trim() } else { "" }
        if (-not $cur -or ($audioList -notcontains $cur)) {
            $found = $audioList | Where-Object { $_ -match $global:LoopbackPattern } | Select-Object -First 1
            if ($found) {
                if (-not $scrExists) { Set-SettingsValue -Config $Config -Section "ScreenCapture" -Name "IncludeAudio" -Value $true }
                Set-SettingsValue -Config $Config -Section "ScreenCapture" -Name "AudioDevice" -Value $found
                $changed = $true
                Write-Host "ScreenCapture AudioDevice auto-detected: $found" -ForegroundColor Cyan
            }
        }
    }
    # ---- CameraCapture: video device ----
    $camExists = [bool]$Config.CameraCapture
    $curV = if ($camExists) { "$($Config.CameraCapture.VideoDevice)".Trim() } else { "" }
    if (-not $curV -or ($videoList -notcontains $curV)) {
        $real  = @($videoList | Where-Object { $_ -notmatch $global:VirtualCamPattern })
        $found = if ($real.Count -gt 0) { $real[0] } elseif ($videoList.Count -gt 0) { $videoList[0] } else { $null }
        if ($found) {
            Set-SettingsValue -Config $Config -Section "CameraCapture" -Name "VideoDevice" -Value $found
            $changed = $true
            Write-Host "CameraCapture VideoDevice auto-detected: $found" -ForegroundColor Cyan
        }
    }
    # ---- CameraCapture: audio device (microphone) - only if a working camera exists ----
    $camVideoNow = if ([bool]$Config.CameraCapture) { "$($Config.CameraCapture.VideoDevice)".Trim() } else { "" }
    $camVideoOk  = ($camVideoNow -and ($videoList -contains $camVideoNow))
    if ($camVideoOk) {
        $curA = "$($Config.CameraCapture.AudioDevice)".Trim()
        if (-not $curA -or ($audioList -notcontains $curA)) {
            # System audio (Stereo Mix / the ScreenCapture device) is never used as a camera microphone
            $scrDev = if ([bool]$Config.ScreenCapture) { "$($Config.ScreenCapture.AudioDevice)".Trim() } else { "" }
            $mics   = @($audioList | Where-Object { $_ -notmatch $global:LoopbackPattern -and $_ -ne $scrDev })
            # Priority: standard "Microphone (...)" first, then other microphones (Headset, etc.)
            $found = $mics | Where-Object { $_ -match $global:MainMicPattern } | Select-Object -First 1
            if (-not $found) { $found = $mics | Where-Object { $_ -match $global:MicPattern } | Select-Object -First 1 }
            if ($found) {
                Set-SettingsValue -Config $Config -Section "CameraCapture" -Name "AudioDevice" -Value $found
                $changed = $true
                Write-Host "CameraCapture AudioDevice auto-detected: $found" -ForegroundColor Cyan
            }
        }
    }
    # ---- Save to settings.json only if something was found/changed ----
    if ($changed) {
        try {
            $Config | ConvertTo-Json -Depth 20 | Set-Content -Path $ConfigPath -Encoding UTF8
            Write-Host "SETTINGS updated with auto-detected devices: $ConfigPath" -ForegroundColor Green
        } catch {
            Write-Host "Cannot save auto-detected devices to SETTINGS: $_" -ForegroundColor Red
        }
    }
}

if ($global:ConfigValid) {
    # MEDIA_FOLDER_URL
    if ($config.MEDIA_FOLDER_URL -and $config.MEDIA_FOLDER_URL.Trim() -ne "") {
        $global:MediaFolderUrl = $config.MEDIA_FOLDER_URL
        $global:MediaFolderConfigured = $true
    } else {
        Write-Host "MEDIA_FOLDER_URL missing in AutoPilot Settings (Empty)!" -ForegroundColor Yellow
		Start-Sleep -Seconds 3
    }
    # Auto-detect audio/video devices (only if missing in settings.json or they do not work)
    try { Initialize-MediaDevices -Config $config -ConfigPath $configPath }
    catch { Write-Host "Auto-detect of media devices failed: $_" -ForegroundColor Yellow }
    # ScreenCapture
	if ($config.ScreenCapture) {
		$ScreenIncludeAudio = [bool]$config.ScreenCapture.IncludeAudio
		$ScreenAudioDevice  = $config.ScreenCapture.AudioDevice

		if ($ScreenIncludeAudio) {
			if (-not $ScreenAudioDevice -or $ScreenAudioDevice.Trim() -eq "") {
				Write-Host "ScreenCapture audio is ON, but the *Screen Audio Device* is missing in AutoPilot Settings (Empty)! Screen recording will be WITHOUT audio." -ForegroundColor DarkYellow
				Start-Sleep -Seconds 3
				$global:ScreenCaptureConfigured = $true
			} else {
				$global:ScreenCaptureConfigured = $true
			}
		} else {
			$global:ScreenCaptureConfigured = $true
		}
	} else {
		Write-Host "*Screen Audio Device* is missing in AutoPilot Settings (Empty)!" -ForegroundColor Yellow
		Start-Sleep -Seconds 3
		$global:ScreenCaptureConfigured = $false
	}
    # CameraCapture
    if ($config.CameraCapture) {
        $CameraVideoDevice = $config.CameraCapture.VideoDevice
        $CameraAudioDevice = $config.CameraCapture.AudioDevice
        if (-not $CameraVideoDevice -or $CameraVideoDevice.Trim() -eq "") {
            Write-Host "CameraCapture *Camera Video Device* is missing in AutoPilot Settings (Empty)!" -ForegroundColor Yellow
			Start-Sleep -Seconds 3
        }
		if (-not $CameraAudioDevice -or $CameraAudioDevice.Trim() -eq "") {
			Write-Host "CameraCapture *Camera Audio Device* is missing in AutoPilot Settings (Empty). Audio will NOT be recorded!" -ForegroundColor Yellow
			Start-Sleep -Seconds 3
		}
        $global:CameraCaptureConfigured = ($CameraVideoDevice -and $CameraVideoDevice.Trim() -ne "")
    }
}

################# FUNCTION Screen Audio Check #####################
# Returns $true if the system audio device from settings exists in ffmpeg (or if ffmpeg cannot list devices -> trust settings).
# Returns $false if it is missing -> the screen recording is then made WITHOUT audio instead of failing.
function Test-ScreenAudioAvailable {
    $devs = Get-FfmpegDshowDevices
    if (-not $devs.Ok) { return $true }
    if (@($devs.Audio) -contains "$ScreenAudioDevice".Trim()) { return $true }
    $msg = "🔇 System audio device not found: $ScreenAudioDevice`n🎦 Recording will be made WITHOUT audio."
    Write-Host $msg -ForegroundColor Yellow
    try { Send-TelegramMessage -message $msg } catch {}
    return $false
}

################# FUNCTION Screenshot #####################
function Take-Screenshot {
    param(
        [string]$caption = "",
        [bool]$isAuto = $false,
        [string]$OutputFolder = "$PSScriptRoot\Screenshot"
    )
	
    # Zavisnosti
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Kreiraj folder ako ne postoi
    if (-not (Test-Path $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory | Out-Null
    }

    # Fiksno ime na fajlot – sekogas samo edna slika
    $filePath = Join-Path -Path $OutputFolder -ChildPath "screenshot.png"

    # Napravi screenshot
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)

    # Zacuvaj slika (prepisuva postoecka)
    $bitmap.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Png)

    # Oslobodi resursi
    $graphics.Dispose()
    $bitmap.Dispose()

    # Vrati objekt kako Generate-LoadGraph
    return @{
        Screenshot = $filePath
        Caption    = $caption
        CreatedAt  = (Get-Date)
    }
}

################# FUNCTION SCREEN RECORD #####################
function Take-ScreenRecord {
    param(
        [int]$Duration = 35,
        [string]$OutputFolder = "$PSScriptRoot\ScreenRecordings"
    )
	
	if (-not $global:ScreenCaptureConfigured) {
		Write-Host "Recording is not configured properly. Skipping..." -ForegroundColor Red
		Send-TelegramMessage -message "🎦 Recording is not configured properly.`n🎦 Recording cannot ⛔ be Started."
		return
	}

    $ffmpegPath = Join-Path -Path $PSScriptRoot -ChildPath "ffmpeg\bin\ffmpeg.exe"
    if (-not (Test-Path $ffmpegPath)) {
        $msg = "⚠️ FFMPEG file not found at location: $ffmpegPath`n🎦 Recording cannot Start."
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Red
        return
    }

    if (-not (Test-Path $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory | Out-Null
    }

    # Ако снимањето е во тек – пријави и излези
    if ($global:ScreenRecordingProcess -and -not $global:ScreenRecordingProcess.HasExited) {
        $elapsed = (Get-Date) - $global:ScreenRecordingStartTime
        $remaining = [math]::Max(0, $global:ScreenRecordingDuration - $elapsed.TotalSeconds)
        $msg = "🎦 Recording is in progress!`n🕓 Start time: $($global:ScreenRecordingStartTime)`n⏳ Remaining time: $([math]::Round($remaining)) seconds"
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Yellow
        return
    }

    # Подготовка на фајл патека
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $filePath = Join-Path -Path $OutputFolder -ChildPath "recording.mp4"
    if ($ScreenIncludeAudio -and $ScreenAudioDevice -and (Test-ScreenAudioAvailable)) {
    $args = "-y -f gdigrab -framerate 25 -i desktop -f dshow -i audio=`"$ScreenAudioDevice`" -t $Duration -vcodec libx264 -pix_fmt yuv420p `"$filePath`""
	}
	else {
		$args = "-y -f gdigrab -framerate 25 -i desktop -t $Duration -vcodec libx264 -pix_fmt yuv420p `"$filePath`""
	}
	# Bez zvuk  $args = "-y -f gdigrab -framerate 25 -i desktop -t $Duration -vcodec libx264 -pix_fmt yuv420p `"$filePath`""
	# So zvuk   $args = "-y -f gdigrab -framerate 25 -i desktop -f dshow -i audio=`"Stereo Mix (Realtek(R) Audio)`" -t $Duration -vcodec libx264 -pix_fmt yuv420p `"$filePath`""
	# C:\AutoPilot\ffmpeg\bin\ffmpeg.exe -list_devices true -f dshow -i dummy  (ffmpeg Audio Driver)

    # Старт на процесот
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ffmpegPath
    $psi.Arguments = $args
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.EnableRaisingEvents = $true
    $process.Start() | Out-Null

	# === Ako ffmpeg se zatvori vednas zaradi zvukot (Windows Privacy / zafaten / drajver) -> povtorno BEZ zvuk ===
    if ($args -match '-f dshow') {
        if ($process.WaitForExit(3000) -and $process.ExitCode -ne 0) {
            $msg = "🔇 System audio cannot be opened (Windows Privacy / in use / driver): $ScreenAudioDevice`n🎦 Recording is restarted WITHOUT audio."
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Yellow
            $psi.Arguments = "-y -f gdigrab -framerate 25 -i desktop -t $Duration -vcodec libx264 -pix_fmt yuv420p `"$filePath`""
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.EnableRaisingEvents = $true
            $process.Start() | Out-Null
        }
    }

    # Се чуваат глобалните вредности
    $global:ScreenRecordingProcess = $process
    try { Start-FfmpegWatchdog } catch {}   # on-demand watchdog: starts only if it is not already running
    $global:ScreenRecordingFile = $filePath
    $global:ScreenRecordingStartTime = Get-Date
    $global:ScreenRecordingDuration = $Duration

    # Испрати порака дека започнало снимањето
    $msg = "🎦 Recording has Started!`n🕓 Recording time: $Duration seconds`n🎬 File: $filePath"
    Send-TelegramMessage -message $msg
    Write-Host $msg -ForegroundColor Green

    # Генерирај уникатен event ID за да нема судир
    $eventId = "ScreenRecordingFinished_" + ([guid]::NewGuid().ToString())

    # Регистрирај event кога процесот ќе заврши
    Register-ObjectEvent -InputObject $process -EventName Exited -SourceIdentifier $eventId -Action {
        $path = $global:ScreenRecordingFile
        $startTime = $global:ScreenRecordingStartTime
        $stopTime = Get-Date
        $duration = New-TimeSpan -Start $startTime -End $stopTime

        # Чекај фајлот да се ослободи ако е заклучен
        $maxWait = 15
        $waited = 0
        while ($waited -lt $maxWait) {
            try {
                $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'None')
                $fs.Close()
                break
            } catch {
                Start-Sleep -Seconds 1
                $waited++
            }
        }

        if (Test-Path $path) {
            $caption = "⚙️ Command: /record`n📆 Period: $($startTime.ToString('dddd, dd MMMM yyyy'))`n🕒 Start: $($startTime.ToString('HH:mm:ss'))`n🕘 Stop: $($stopTime.ToString('HH:mm:ss'))`n⏳ Duration: $([math]::Round($duration.TotalSeconds)) seconds`n" + ("-" * 18) + "`n📁 Video Folder: /data`n🔰 AutoPilot | Start Menu - /start"
            Send-TelegramVideo -videoPath $path -caption $caption
        } else {
            Send-TelegramMessage -message "⚠️ Error: 🎦 Recording not found ($path)"
        }

        # Чистење на глобални вредности
        $global:ScreenRecordingProcess = $null
        $global:ScreenRecordingFile = $null
        $global:ScreenRecordingStartTime = $null
        $global:ScreenRecordingDuration = $null

        # Unregister event
        Unregister-Event -SourceIdentifier $eventId
    } | Out-Null
}

################# DESKTOP RECORDING ###########################

# Start Desktop Recording
function Start-Recording {
    param([string]$OutputFolder = "$PSScriptRoot\Recording")
	
	if (-not $global:ScreenCaptureConfigured) {
        Write-Host "Desktop Recording is not configured properly. Skipping..." -ForegroundColor Red
	    Send-TelegramMessage -message "🖥️ Desktop Recording is not configured properly.`n🖥️ Desktop Recording cannot ⛔ be Started."
        return
    }
	
	$ffmpegPath = Join-Path -Path $PSScriptRoot -ChildPath "ffmpeg\bin\ffmpeg.exe"
    # === Проверка дали постои ffmpeg ===
    if (-not (Test-Path $ffmpegPath)) {
        $msg = "⚠️ FFMPEG file not found at location: $ffmpegPath`n🖥️ Desktop Recording cannot Start."
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Red
        return
    }

    if ($global:DesktopRecordingProcess -and -not $global:DesktopRecordingProcess.HasExited) {
        $msg = "🖥️ Desktop recording is already Started!`n🕒 Start time: $($global:DesktopRecordingStartTime)`nTo ⏹️ Stop it press: /rec_stop"
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $OutputFolder)) { New-Item -Path $OutputFolder -ItemType Directory | Out-Null }

    $filePath = Join-Path $OutputFolder "rec.mp4"
    if ($ScreenIncludeAudio -and $ScreenAudioDevice -and (Test-ScreenAudioAvailable)) {
    $args = "-y -f gdigrab -framerate 25 -i desktop -f dshow -i audio=`"$ScreenAudioDevice`" -vcodec libx264 -pix_fmt yuv420p `"$filePath`""
	}
	else {
	$args = "-y -f gdigrab -framerate 25 -i desktop -vcodec libx264 -pix_fmt yuv420p `"$filePath`""
	}
	# Bez zvuk  $args = "-y -f gdigrab -framerate 25 -i desktop -vcodec libx264 -pix_fmt yuv420p `"$filePath`""
	# So zvuk   $args = "-y -f gdigrab -framerate 25 -i desktop -f dshow -i audio=`"Stereo Mix (Realtek(R) Audio)`" -vcodec libx264 -pix_fmt yuv420p `"$filePath`""
	# C:\AutoPilot\ffmpeg\bin\ffmpeg.exe -list_devices true -f dshow -i dummy  (ffmpeg Audio Driver)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ffmpegPath
    $psi.Arguments = $args
    $psi.RedirectStandardInput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.Start() | Out-Null
	
	# === Ako ffmpeg se zatvori vednas zaradi zvukot (Windows Privacy / zafaten / drajver) -> povtorno BEZ zvuk ===
    if ($args -match '-f dshow') {
        if ($process.WaitForExit(3000) -and $process.ExitCode -ne 0) {
            $msg = "🔇 System audio cannot be opened (Windows Privacy / in use / driver): $ScreenAudioDevice`n🖥️ Recording is restarted WITHOUT audio."
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Yellow
            $psi.Arguments = "-y -f gdigrab -framerate 25 -i desktop -vcodec libx264 -pix_fmt yuv420p `"$filePath`""
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.Start() | Out-Null
        }
    }

    $global:DesktopRecordingProcess = $process
    try { Start-FfmpegWatchdog } catch {}   # on-demand watchdog: starts only if it is not already running
    $global:DesktopRecordingFile = $filePath
    $global:DesktopRecordingStartTime = Get-Date

    $msg = "🖥️ Desktop Recording is Starting!`n🕒 Start time: $($global:DesktopRecordingStartTime)`nTo ⏹️ Stop it press: /rec_stop"
    Send-TelegramMessage -message $msg
    Write-Host $msg -ForegroundColor Green
}

# Save Desktop Recording State
function Save-DesktopRecordingState {
    if (-not $global:RecordingStateFile) { Write-Host "ERROR: RecordingStateFile not defined!" -ForegroundColor Red; return }
    $stateDir = Split-Path -Path $global:RecordingStateFile
    if (-not (Test-Path $stateDir)) { New-Item -Path $stateDir -ItemType Directory | Out-Null }
    $state = @{
        LastRecordingFile      = $global:LastDesktopRecordingFile
        LastRecordingStartTime = $global:LastDesktopRecordingStartTime.ToString("o")
        LastRecordingStopTime  = $global:LastDesktopRecordingStopTime.ToString("o")
        LastRecordingDuration  = "$($global:LastDesktopRecordingDuration)"
    }
    $state | ConvertTo-Json | Set-Content -Path $global:RecordingStateFile -Encoding UTF8
}

# Load Desktop Recording State
function Load-RecordingState {
    if (Test-Path $global:RecordingStateFile) {
        try {
            $state = Get-Content $global:RecordingStateFile | ConvertFrom-Json
            $global:LastDesktopRecordingFile = $state.LastRecordingFile
            $global:LastDesktopRecordingStartTime = ([datetime]$state.LastRecordingStartTime).ToLocalTime()
            $global:LastDesktopRecordingStopTime  = ([datetime]$state.LastRecordingStopTime).ToLocalTime()
            $global:LastDesktopRecordingDuration  = [timespan]::Parse($state.LastRecordingDuration)
        } catch { Write-Host "Cannot load the state: $_" -ForegroundColor Red }
    }
}

# Stop Desktop Recording
function Stop-Recording {
    if (-not $global:DesktopRecordingProcess -or $global:DesktopRecordingProcess.HasExited) {
        if ($global:LastDesktopRecordingFile -and (Test-Path $global:LastDesktopRecordingFile)) {
            $msg = "🖥️ Desktop Recording is already ⏹️ Stopped.`n🎬 Last recording: $($global:LastDesktopRecordingFile)"
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Yellow
            return @{ Video=$global:LastDesktopRecordingFile; Start=$global:LastDesktopRecordingStartTime; Stop=$global:LastDesktopRecordingStopTime; Duration=$global:LastDesktopRecordingDuration }
        } else {
            $msg = "No Desktop Recording 🖥️ is in progress to ⏹️ Stop, or the last 🎬 File does not Exist."
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Red
            return $null
        }
    }

    try {
        $global:DesktopRecordingProcess.StandardInput.WriteLine("q")
        $global:DesktopRecordingProcess.WaitForExit(15000)
        Write-Host "Desktop Recording is Stopped." -ForegroundColor Green
        Send-TelegramMessage -message "🖥️ Desktop Recording is ⏹️ Stopped."
    } catch { Write-Host "Error stopping: $_" -ForegroundColor Red; Send-TelegramMessage -message "Error stopping: $_" }

    $videoPath = $global:DesktopRecordingFile
    $stopTime = Get-Date
    $duration = New-TimeSpan -Start $global:DesktopRecordingStartTime -End $stopTime

    $global:LastDesktopRecordingFile = $videoPath
    $global:LastDesktopRecordingStartTime = $global:DesktopRecordingStartTime
    $global:LastDesktopRecordingStopTime = $stopTime
    $global:LastDesktopRecordingDuration = $duration

    Save-DesktopRecordingState

    $global:DesktopRecordingProcess = $null
    $global:DesktopRecordingFile = $null
    $global:DesktopRecordingStartTime = $null

    if (-not $videoPath -or -not (Test-Path $videoPath)) {
        $msg = "🎬 Video file does not exist: $videoPath"
        Write-Host $msg -ForegroundColor Red
        Send-TelegramMessage -message $msg
        return $null
    }

    $caption = "⚙️ Command: /rec_stop`n📆 Period: $($stopTime.ToString('dddd, dd MMMM yyyy'))`n🕒 Start: $($global:LastDesktopRecordingStartTime.ToString('HH:mm:ss'))`n🕘 Stop: $($stopTime.ToString('HH:mm:ss'))`n⏳ Duration: $([math]::Round($duration.TotalSeconds)) seconds`n" + ("-"*18) + "`n📁 Video Folder: /data`n🔰 AutoPilot | Start Menu - /start"
    Send-TelegramVideo -videoPath $videoPath -caption $caption

    return @{ Video=$videoPath; Start=$global:LastDesktopRecordingStartTime; Stop=$stopTime; Duration=$duration }
}

# Load Desktop State at startup
Load-RecordingState

################# CAMERA RECORDING ###########################

# Start Camera Recording
function Start-CameraRecording {
    param([string]$OutputFolder = "$PSScriptRoot\Camera")
	
	if (-not $global:CameraCaptureConfigured) {
        Write-Host "Camera Recording is not configured properly. Skipping..." -ForegroundColor Red
        Send-TelegramMessage -message "📸 Camera Recording is not configured properly.`n📸 Camera Recording cannot ⛔ be Started."
        return
    }
	
	$ffmpegPath = Join-Path -Path $PSScriptRoot -ChildPath "ffmpeg\bin\ffmpeg.exe"
    # === Проверка дали постои ffmpeg ===
    if (-not (Test-Path $ffmpegPath)) {
        $msg = "⚠️ FFMPEG file not found at location: $ffmpegPath`n📸 Recording cannot Start."
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Red
        return
    }
	
	# === Проверка дали kamerata e dostupna ===
    $cameraName  = $CameraVideoDevice
    $audioDevice = $CameraAudioDevice
    # === Проверка дали камерата постои ===
    $ffmpegOutput = & $ffmpegPath -list_devices true -f dshow -i dummy 2>&1
    $cameraFound = $ffmpegOutput | Where-Object { $_ -match "`"$cameraName`"\s+\(video\)" }
    if (-not $cameraFound) {
        $msg = "📸 Camera device: '$cameraName' not found.`n📸 Recording cannot Start."
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Red
        return
    }
	
	# === Проверка дали mikrofonot postoi - ako ne, kamerata se snima BEZ zvuk (ne se prekinuva) ===
    if ($audioDevice) {
        $audioFound = $ffmpegOutput | Where-Object { $_ -match ('"' + [regex]::Escape($audioDevice) + '"\s+\([^)]*audio[^)]*\)') }
        if (-not $audioFound) {
            $msg = "🎙️ Camera microphone not found: $audioDevice`n📸 Recording will be made WITHOUT audio."
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Yellow
            $audioDevice = $null
        }
    }

    if ($global:RecordingProcess -and -not $global:RecordingProcess.HasExited) {
        $msg = "📸 Camera is already Started!`n🕒 Start time: $($global:RecordingStartTime)`nTo ⏹️ Stop it press: /cam_stop"
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $OutputFolder)) { New-Item -Path $OutputFolder -ItemType Directory | Out-Null }

    $filePath = Join-Path $OutputFolder "rec_$(Get-Date -Format 'yyyy-MM-dd - HH-mm-ss').mp4"
    $args = "-y -f dshow -rtbufsize 64M -i video=`"$cameraName`""
	if ($audioDevice) {
		$args += " -f dshow -i audio=`"$audioDevice`""
	}
	$args += " -vcodec libx264 -b:v 1M -maxrate 1M -bufsize 2M -pix_fmt yuv420p `"$filePath`""
    # C:\AutoPilot\ffmpeg\bin\ffmpeg.exe -list_devices true -f dshow -i dummy  (ffmpeg Camera Driver)
	
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ffmpegPath
    $psi.Arguments = $args
    $psi.RedirectStandardInput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.Start() | Out-Null
	
	# === Ako ffmpeg se zatvori vednas (mikrofonot e blokiran vo Windows Privacy, zafaten ili problem so drajver) -> povtorno BEZ zvuk ===
    if ($audioDevice) {
        if ($process.WaitForExit(3000) -and $process.ExitCode -ne 0) {
            $msg = "🎙️ Camera microphone cannot be opened (Windows Privacy / in use / driver): $audioDevice`n📸 Recording is restarted WITHOUT audio."
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Yellow
            $psi.Arguments = "-y -f dshow -rtbufsize 64M -i video=`"$cameraName`" -vcodec libx264 -b:v 1M -maxrate 1M -bufsize 2M -pix_fmt yuv420p `"$filePath`""
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            $process.Start() | Out-Null
        }
    }

    $global:RecordingProcess = $process
    try { Start-FfmpegWatchdog } catch {}   # on-demand watchdog: starts only if it is not already running
    $global:RecordingFile = $filePath
    $global:RecordingStartTime = Get-Date

    $msg = "📸 Camera has Started!`n🎬 File: $filePath`n🕒 Start time: $global:RecordingStartTime`nTo ⏹️ Stop it press: /cam_stop"
    Send-TelegramMessage -message $msg
    Write-Host $msg -ForegroundColor Green
}

# Save Camera Recording State
function Save-CameraRecordingState {
	if (-not $global:CameraRecordingStateFile) { Write-Host "ERROR: CameraRecordingStateFile not defined!" -ForegroundColor Red; return }
    $stateDir = Split-Path -Path $global:CameraRecordingStateFile
    if (-not (Test-Path $stateDir)) { New-Item -Path $stateDir -ItemType Directory | Out-Null }

    $state = @{
        LastCameraRecordingFile       = $global:LastCameraRecordingFile
        LastCameraRecordingStartTime  = $global:LastCameraRecordingStartTime.ToString("o")
        LastCameraRecordingStopTime   = $global:LastCameraRecordingStopTime.ToString("o")
        LastCameraRecordingDuration   = "$($global:LastCameraRecordingDuration)"
    }
    $state | ConvertTo-Json | Set-Content -Path $global:CameraRecordingStateFile -Encoding UTF8
}

# Load Camera Recording State
function Load-CameraRecordingState {
    if (Test-Path $global:CameraRecordingStateFile) {
        try {
            $state = Get-Content $global:CameraRecordingStateFile | ConvertFrom-Json
            $global:LastCameraRecordingFile      = $state.LastCameraRecordingFile
            $global:LastCameraRecordingStartTime = ([datetime]$state.LastCameraRecordingStartTime).ToLocalTime()
            $global:LastCameraRecordingStopTime  = ([datetime]$state.LastCameraRecordingStopTime).ToLocalTime()
            $global:LastCameraRecordingDuration  = [timespan]::Parse($state.LastCameraRecordingDuration)
        } catch { Write-Host "Cannot load the state: $_" -ForegroundColor Red }
    }
}

# Stop Camera Recording
function Stop-CameraRecording {
    if (-not $global:RecordingProcess -or $global:RecordingProcess.HasExited) {
        if ($global:LastCameraRecordingFile -and (Test-Path $global:LastCameraRecordingFile)) {
            $msg = "📸 Camera is already ⏹️ Stopped.`n🎬 Last recording: $($global:LastCameraRecordingFile)"
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Yellow
            return @{ Video=$global:LastCameraRecordingFile; Start=$global:LastCameraRecordingStartTime; Stop=$global:LastCameraRecordingStopTime; Duration=$global:LastCameraRecordingDuration }
        } else {
            $msg = "No recording 📸 in progress to ⏹️ Stop, or the last File 🎬 does not Exist."
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Red
            return $null
        }
    }

    try {
        $global:RecordingProcess.StandardInput.WriteLine("q")
        $global:RecordingProcess.WaitForExit(15000)
        Write-Host "Camera is Stopped." -ForegroundColor Green
        Send-TelegramMessage -message "📸 Camera is ⏹️ Stopped."
    } catch { Write-Host "Error stopping: $_" -ForegroundColor Red; Send-TelegramMessage -message "Error stopping: $_" }

    $videoPath = $global:RecordingFile
    $stopTime = Get-Date
    $duration = New-TimeSpan -Start $global:RecordingStartTime -End $stopTime

    $global:LastCameraRecordingFile = $videoPath
    $global:LastCameraRecordingStartTime = $global:RecordingStartTime
    $global:LastCameraRecordingStopTime = $stopTime
    $global:LastCameraRecordingDuration = $duration

    Save-CameraRecordingState

    $global:RecordingProcess = $null
    $global:RecordingFile = $null
    $global:RecordingStartTime = $null

    if (-not $videoPath -or -not (Test-Path $videoPath)) {
        $msg = "🎬 Video file does not exist: $videoPath"
        Write-Host $msg -ForegroundColor Red
        Send-TelegramMessage -message $msg
        return $null
    }

    $caption = "⚙️ Command: /cam_stop`n📆 Period: $($stopTime.ToString('dddd, dd MMMM yyyy'))`n🕒 Start: $($global:LastCameraRecordingStartTime.ToString('HH:mm:ss'))`n🕘 Stop: $($stopTime.ToString('HH:mm:ss'))`n⏳ Duration: $([math]::Round($duration.TotalSeconds)) seconds`n" + ("-"*18) + "`n📁 Video Folder: /data`n🔰 AutoPilot | Start Menu - /start"
    Send-TelegramVideo -videoPath $videoPath -caption $caption

    return @{ Video=$videoPath; Start=$global:LastCameraRecordingStartTime; Stop=$stopTime; Duration=$duration }
}

# Load Camera State at startup
Load-CameraRecordingState

################### DATA FOLDER Function #######################

# Funkcija za start na FileStorage.exe
function Data-CameraRecording {
    param (
        [string]$ScriptPath = "$PSScriptRoot\FileStorage.exe"
    )
    # === Media Bot Guard ===
    if (-not (Is-MediaTelegramOperational)) {
        $statusMessage = "🎬 Media Telegram Bot is Disabled or Misconfigured.`n💾 Data command Skipped."
        Write-Host $statusMessage -ForegroundColor Red
        Write-Log $statusMessage
        # Only send Telegram if AutoPilot bot is enabled to avoid errors
        if (Is-AutoPilotTelegramEnabled) {
            Send-TelegramMessage -message $statusMessage
        }
        return
    }
    # === Check if process is already running ===
    $processes = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -match [regex]::Escape($ScriptPath)
    }
    $message = @"
 💾 DATA Server $(if ($processes) {"already Started"} else {"is Started"})!

 🗂️ Enter in Media Folder:* [Click here]($global:MediaFolderUrl)

 ⏹️ If you want to stop the DATA Server, press: /data_stop

 🔄 To restart the DATA Server, press: /data
"@
    Send-TelegramMessage -message $message
    if (-not $processes) {
        Start-Process -FilePath $ScriptPath -NoNewWindow
    }
    Write-Host "DATA Server $(if ($processes) {"already Started"} else {"is Started"})!"
}

# Funkcija za stop na FileStorage.exe
function Stop-DataServer {
    param (
        [string]$ScriptPath = "$PSScriptRoot\FileStorage.exe"
    )
    $processes = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -match [regex]::Escape($ScriptPath)
    }
    if ($processes) {
        foreach ($p in $processes) {
            Stop-Process -Id $p.ProcessId -Force
        }
        $statusMessage = "💾 DATA Server is Stopped!"
        Send-TelegramMessage -message $statusMessage
        Write-Host " DATA Server is Stopped!"
    }
    else {
        $statusMessage = "💾 DATA Server is not Started.."
        Send-TelegramMessage -message $statusMessage
        Write-Host " DATA Server is not Started.."
    }
}

################# FFMPEG WATCHDOG (on demand: started when an ffmpeg recording starts, closes ffmpeg.exe that runs too long, stops itself when no ffmpeg is left) #####################
$global:FfmpegMaxMinutes = 12      # every ffmpeg.exe running longer than this is closed
$global:FfmpegCheckSeconds = 300    # how often the watchdog checks while it is active

function Start-FfmpegWatchdog {
    param([int]$MaxMinutes = $global:FfmpegMaxMinutes, [int]$CheckSeconds = $global:FfmpegCheckSeconds)
    # Already watching -> the running watchdog covers every ffmpeg (1st, 2nd, 3rd ...), so do not start another one
    if (Get-EventSubscriber -SourceIdentifier "FfmpegWatchdog" -ErrorAction SilentlyContinue) { return }
    # Remove the leftover of a previous watchdog that stopped itself
    try { Get-Job -Name "FfmpegWatchdog" -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue } catch {}
    # Timer event: runs in the main session, so Write-Log and Write-Host work the same as everywhere else in the script
    $timer = New-Object System.Timers.Timer
    $timer.Interval  = $CheckSeconds * 1000
    $timer.AutoReset = $true
    Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier "FfmpegWatchdog" -MessageData @{ MaxMinutes = $MaxMinutes } -Action {
        $cfg = $Event.MessageData
        try {
            $closed = @()
            $alive  = 0     # ffmpeg processes that are still running after this check
            foreach ($p in [System.Diagnostics.Process]::GetProcessesByName('ffmpeg')) {
                try {
                    # Any ffmpeg.exe older than MaxMinutes
                    $procId  = $p.Id
                    $started = $p.StartTime
                    $age     = [DateTime]::Now - $started
                    if ($age.TotalMinutes -ge $cfg.MaxMinutes) {
                        $p.Kill()
                        [void]$p.WaitForExit(3000)
                        $closed += ("PID {0} (started {1}, was running {2:N1} min)" -f $procId, $started.ToString('HH:mm:ss'), $age.TotalMinutes)
                    } else {
                        $alive++
                    }
                } catch { $alive++ }   # could not be checked/closed -> keep watching it
                finally { $p.Dispose() }
            }
            # Terminal + log (Write-Log)
            if ($closed.Count -gt 0) {
                $now   = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
                $lines = @("⛔ FFMPEG watchdog: closed $($closed.Count) ffmpeg.exe process(es) running longer than $($cfg.MaxMinutes) min 🕒 at $now")
                foreach ($c in $closed) { $lines += "🎬 $c" }
				# Telegram: the same text, sent as one message
				try {
					Send-TelegramMessage -message ($lines -join "`n")
					Write-Log "✅ FFMPEG watchdog Telegram message sent."
				}
				catch {
					try {
						Write-Log "⚠️ FFMPEG watchdog Telegram error: $($_.Exception.Message)"
					} catch {}
				}
                # Terminal: UTF-8 output
                $oldEnc = $null; $oc = $null
                try {
                    $oldEnc = [Console]::OutputEncoding
                    $oc     = [Console]::ForegroundColor
                    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
                    [Console]::ForegroundColor = 'DarkYellow'
                    foreach ($l in $lines) { [Console]::WriteLine($l) }
                } catch {}
                finally {
                    try { if ($oc -ne $null)     { [Console]::ForegroundColor = $oc } } catch {}
                    try { if ($oldEnc -ne $null) { [Console]::OutputEncoding = $oldEnc } } catch {}
                }
                # Log: plain Write-Log
                foreach ($l in $lines) { try { Write-Log $l } catch {} }
            }
            # No ffmpeg left -> the watchdog is not needed any more: stop it and remove it (it is started again with the next ffmpeg)
            if ($alive -eq 0) {
                $t = $Sender
                if (-not $t) { $t = $global:FfmpegWatchdogTimer }
                try { if ($t) { $t.Stop() } } catch {}
                try { Unregister-Event -SourceIdentifier "FfmpegWatchdog" -ErrorAction SilentlyContinue } catch {}
                try { if ($t) { $t.Dispose() } } catch {}
                $global:FfmpegWatchdogTimer = $null
            }
        } catch {}
    } | Out-Null
    $timer.Start()
    $global:FfmpegWatchdogTimer = $timer   # keep a reference so the timer is not garbage collected
}
# The watchdog is not started on load. It is started by the functions that start ffmpeg (Take-ScreenRecord, Start-Recording, Start-CameraRecording).

########################################################################################################################## Media Script End.