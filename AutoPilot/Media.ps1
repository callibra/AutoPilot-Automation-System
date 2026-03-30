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

if ($global:ConfigValid) {
    # MEDIA_FOLDER_URL
    if ($config.MEDIA_FOLDER_URL -and $config.MEDIA_FOLDER_URL.Trim() -ne "") {
        $global:MediaFolderUrl = $config.MEDIA_FOLDER_URL
        $global:MediaFolderConfigured = $true
    } else {
        Write-Host "MEDIA_FOLDER_URL missing in AutoPilot Settings (Empty)!" -ForegroundColor Yellow
		Start-Sleep -Seconds 3
    }
    # ScreenCapture
	if ($config.ScreenCapture) {
		$ScreenIncludeAudio = [bool]$config.ScreenCapture.IncludeAudio
		$ScreenAudioDevice  = $config.ScreenCapture.AudioDevice

		if ($ScreenIncludeAudio) {
			if (-not $ScreenAudioDevice -or $ScreenAudioDevice.Trim() -eq "") {
				Write-Host "ScreenCapture audio is ON, but the *Screen Audio Device* is missing in AutoPilot Settings (Empty)!" -ForegroundColor DarkYellow
				Start-Sleep -Seconds 3
				$global:ScreenCaptureConfigured = $false
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
		Send-TelegramMessage -message "Recording is not configured properly. Recording cannot be Started."
		return
	}

    $ffmpegPath = Join-Path -Path $PSScriptRoot -ChildPath "ffmpeg\bin\ffmpeg.exe"
    if (-not (Test-Path $ffmpegPath)) {
        $msg = " FFMPEG file not found at location: $ffmpegPath`nRecording cannot start."
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
        $msg = " Recording is in progress! Start time: $($global:ScreenRecordingStartTime)`n Remaining time: $([math]::Round($remaining)) seconds"
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Yellow
        return
    }

    # Подготовка на фајл патека
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $filePath = Join-Path -Path $OutputFolder -ChildPath "recording.mp4"
    if ($ScreenIncludeAudio -and $ScreenAudioDevice) {
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

    # Се чуваат глобалните вредности
    $global:ScreenRecordingProcess = $process
    $global:ScreenRecordingFile = $filePath
    $global:ScreenRecordingStartTime = Get-Date
    $global:ScreenRecordingDuration = $Duration

    # Испрати порака дека започнало снимањето
    $msg = " Recording has started!`n Recording time: $Duration seconds`n File: $filePath"
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
        $maxWait = 10
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
            $caption = "Command: /record`nPeriod: $($startTime.ToString('dddd, dd MMMM yyyy'))`nStart: $($startTime.ToString('HH:mm:ss'))`nStop: $($stopTime.ToString('HH:mm:ss'))`nDuration: $([math]::Round($duration.TotalSeconds)) seconds`n" + ("-" * 18) + "`n* Autopilot | Start Menu - /start"
            Send-TelegramVideo -videoPath $path -caption $caption
        } else {
            Send-TelegramMessage -message " Error: Recording not found ($path)"
        }

        # Чистење на глобални вредности
        $global:ScreenRecordingProcess = $null
        $global:ScreenRecordingFile = $null
        $global:ScreenRecordingStartTime = $null
        $global:ScreenRecordingDuration = $null

        # Unregister event
        Unregister-Event -SourceIdentifier $eventId
    }
}

################# DESKTOP RECORDING ###########################

# Start Desktop Recording
function Start-Recording {
    param([string]$OutputFolder = "$PSScriptRoot\Recording")
	
	if (-not $global:ScreenCaptureConfigured) {
        Write-Host "Start Recording is not configured properly. Skipping..." -ForegroundColor Red
	    Send-TelegramMessage -message "Start Recording is not configured properly. Start Recording cannot be Started."
        return
    }
	
	$ffmpegPath = Join-Path -Path $PSScriptRoot -ChildPath "ffmpeg\bin\ffmpeg.exe"
    # === Проверка дали постои ffmpeg ===
    if (-not (Test-Path $ffmpegPath)) {
        $msg = " FFMPEG file not found at location: $ffmpegPath`nRecording cannot start."
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Red
        return
    }

    if ($global:DesktopRecordingProcess -and -not $global:DesktopRecordingProcess.HasExited) {
        $msg = "Desktop recording is already started! Start time: $($global:DesktopRecordingStartTime)`nTo stop it press: /rec_stop"
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $OutputFolder)) { New-Item -Path $OutputFolder -ItemType Directory | Out-Null }

    $filePath = Join-Path $OutputFolder "rec.mp4"
    if ($ScreenIncludeAudio -and $ScreenAudioDevice) {
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

    $global:DesktopRecordingProcess = $process
    $global:DesktopRecordingFile = $filePath
    $global:DesktopRecordingStartTime = Get-Date

    $msg = "Desktop recording is Starting! Start time: $($global:DesktopRecordingStartTime)`nTo stop it press: /rec_stop"
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
            $msg = "Desktop recording is already stopped. Last recording: $($global:LastDesktopRecordingFile)"
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Yellow
            return @{ Video=$global:LastDesktopRecordingFile; Start=$global:LastDesktopRecordingStartTime; Stop=$global:LastDesktopRecordingStopTime; Duration=$global:LastDesktopRecordingDuration }
        } else {
            $msg = "No desktop recording is in progress to stop, or the last file does not exist."
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Red
            return $null
        }
    }

    try {
        $global:DesktopRecordingProcess.StandardInput.WriteLine("q")
        $global:DesktopRecordingProcess.WaitForExit(5000)
        Write-Host "Desktop recording is stopped." -ForegroundColor Green
        Send-TelegramMessage -message "Desktop recording is stopped."
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
        $msg = "Video file does not exist: $videoPath"
        Write-Host $msg -ForegroundColor Red
        Send-TelegramMessage -message $msg
        return $null
    }

    $caption = "Command: /rec_stop`nPeriod: $($stopTime.ToString('dddd, dd MMMM yyyy'))`nStart: $($global:LastDesktopRecordingStartTime.ToString('HH:mm:ss'))`nStop: $($stopTime.ToString('HH:mm:ss'))`nDuration: $([math]::Round($duration.TotalSeconds)) seconds`n" + ("-"*18) + "`n* Autopilot | Start Menu - /start"
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
        Send-TelegramMessage -message "Camera Recording is not configured properly. Camera Recording cannot be Started."
        return
    }
	
	$ffmpegPath = Join-Path -Path $PSScriptRoot -ChildPath "ffmpeg\bin\ffmpeg.exe"
    # === Проверка дали постои ffmpeg ===
    if (-not (Test-Path $ffmpegPath)) {
        $msg = " FFMPEG file not found at location: $ffmpegPath`nRecording cannot start."
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
        $msg = " Camera device: '$cameraName' not found.`nRecording cannot start."
        Send-TelegramMessage -message $msg
        Write-Host $msg -ForegroundColor Red
        return
    }

    if ($global:RecordingProcess -and -not $global:RecordingProcess.HasExited) {
        $msg = "Camera is already started! Start time: $($global:RecordingStartTime)`nTo stop it press: /cam_stop"
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

    $global:RecordingProcess = $process
    $global:RecordingFile = $filePath
    $global:RecordingStartTime = Get-Date

    $msg = "Camera has started!`nFile: $filePath`nStart time: $global:RecordingStartTime`nTo stop it press: /cam_stop"
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
            $msg = "Camera is already stopped. Last recording: $($global:LastCameraRecordingFile)"
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Yellow
            return @{ Video=$global:LastCameraRecordingFile; Start=$global:LastCameraRecordingStartTime; Stop=$global:LastCameraRecordingStopTime; Duration=$global:LastCameraRecordingDuration }
        } else {
            $msg = "No recording in progress to stop, or the last file does not exist."
            Send-TelegramMessage -message $msg
            Write-Host $msg -ForegroundColor Red
            return $null
        }
    }

    try {
        $global:RecordingProcess.StandardInput.WriteLine("q")
        $global:RecordingProcess.WaitForExit(5000)
        Write-Host "Camera is stopped." -ForegroundColor Green
        Send-TelegramMessage -message "Camera is stopped."
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
        $msg = "Video file does not exist: $videoPath"
        Write-Host $msg -ForegroundColor Red
        Send-TelegramMessage -message $msg
        return $null
    }

    $caption = "Command: /cam_stop`nPeriod: $($stopTime.ToString('dddd, dd MMMM yyyy'))`nStart: $($global:LastCameraRecordingStartTime.ToString('HH:mm:ss'))`nStop: $($stopTime.ToString('HH:mm:ss'))`nDuration: $([math]::Round($duration.TotalSeconds)) seconds`n" + ("-"*18) + "`n* Video folder: /data`n* Autopilot | Start Menu - /start"
    Send-TelegramVideo -videoPath $videoPath -caption $caption

    return @{ Video=$videoPath; Start=$global:LastCameraRecordingStartTime; Stop=$stopTime; Duration=$duration }
}

# Load Camera State at startup
Load-CameraRecordingState

################### DATA FOLDER Function #######################

# Funkcija za start na Python skriptata
function Data-CameraRecording {
    param (
        [string]$ScriptPath = "$PSScriptRoot\Camera.exe"
    )
    # === Media Bot Guard ===
    if (-not (Is-MediaTelegramOperational)) {
        $statusMessage = "Media Telegram Bot is Disabled or Misconfigured, *Data* command Skipped."
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
- DATA Server $(if ($processes) {"already Started"} else {"is Started"})!

- Enter in Media Folder:* [Click here]($global:MediaFolderUrl)

- If you want to stop the DATA Server, press: /data_stop

- To restart the DATA Server, press: /data
"@
    Send-TelegramMessage -message $message
    if (-not $processes) {
        Start-Process -FilePath $ScriptPath -NoNewWindow
    }
    Write-Host "DATA Server $(if ($processes) {"already Started"} else {"is Started"})!"
}

# Funkcija za stop na Python skriptata
function Stop-DataServer {
    param (
        [string]$ScriptPath = "$PSScriptRoot\Camera.exe"
    )
    $processes = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -match [regex]::Escape($ScriptPath)
    }
    if ($processes) {
        foreach ($p in $processes) {
            Stop-Process -Id $p.ProcessId -Force
        }
        $statusMessage = " DATA Server is Stopped!"
        Send-TelegramMessage -message $statusMessage
        Write-Host " DATA Server is Stopped!"
    }
    else {
        $statusMessage = " DATA Server is not Started.."
        Send-TelegramMessage -message $statusMessage
        Write-Host " DATA Server is not Started.."
    }
}

############################################################################# Media Script End.