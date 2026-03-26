# APP ROOT
if (-not $AppRoot) {
    if ($PSCommandPath) {
        $AppRoot = Split-Path -Parent $PSCommandPath
    }
    else {
        $AppRoot = Split-Path -Parent (
            [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        )
    }
}

# ==================== PARAMETERS ====================
$appDirectory = "$AppRoot\"
$backupDirectory = "$AppRoot\backup\"
$localVersionFile = "$appDirectory\version.txt"
$lastDeclineFile = "$appDirectory\last_update_declined.txt"
$driveRoot = [System.IO.Path]::GetPathRoot($AppRoot)
$externalBackupDirectory = Join-Path $driveRoot "AutoPilot_Backup"

# ==================== ADD THIS ====================
$logDir = Join-Path $appDirectory "Autopilot_Data\Update_Logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$versionUrl = "https://raw.githubusercontent.com/callibra/AutoPilot-Automation-System/main/version.txt"
$releaseApi = "https://api.github.com/repos/callibra/AutoPilot-Automation-System/releases/latest"
$hashUrl = "https://raw.githubusercontent.com/callibra/AutoPilot-Automation-System/main/installer.sha256"
$minorManifestUrl = "https://raw.githubusercontent.com/callibra/AutoPilot-Automation-System/main/minor_manifest.json"

$installerTempPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "AutoPilot_SetUp.exe")
$installerDownloadPath = "$installerTempPath.download"

$rolloutPercentage = 88

# ==================== AutoPilot URL ====================
function Get-LatestInstallerUrl {
    $release = Invoke-RestMethod `
        -Uri $releaseApi `
        -Headers @{ "User-Agent" = "AutoPilot-Updater" }

    foreach ($asset in $release.assets) {
        if ($asset.name -eq "AutoPilot_SetUp.exe") {
            return $asset.browser_download_url
        }
    }
    return $null
}

# ==================== DARK UI CORE ====================
function New-DarkForm {
    param([string]$title, [int]$height = 220)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.Size = "450,$height"
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(28,28,28)
    $form.ForeColor = "White"
    $form.Font = New-Object System.Drawing.Font("Segoe UI",13)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    if ($Global:UpdaterIcon) {
        $form.Icon = $Global:UpdaterIcon
        $form.ShowIcon = $true
    }

    return $form
}

# ==================== DARK DIALOG ====================
function Show-DarkDialog {
    param(
        [string]$title,
        [string]$message,
        [switch]$YesNo
    )

    $form = New-DarkForm $title 200
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $message
    $label.Size = "380,70"
    $label.Location = "30,30"
    $form.Controls.Add($label)

    if ($YesNo) {
        $btnYes = New-Object System.Windows.Forms.Button
        $btnYes.Text = "Yes"
        $btnYes.Size = "110,35"
        $btnYes.Location = "90,110"
        $btnYes.BackColor = "#2D89EF"
        $btnYes.FlatStyle = "Flat"
        $btnYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $form.Controls.Add($btnYes)

        $btnNo = New-Object System.Windows.Forms.Button
        $btnNo.Text = "No"
        $btnNo.Size = "110,35"
        $btnNo.Location = "230,110"
        $btnNo.BackColor = "#3A3A3A"
        $btnNo.FlatStyle = "Flat"
        $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::No
        $form.Controls.Add($btnNo)

        $form.AcceptButton = $btnYes
        $form.CancelButton = $btnNo
        return $form.ShowDialog()
    }
    else {

        $btnOk = New-Object System.Windows.Forms.Button
        $btnOk.Text = "OK"
        $btnOk.Size = "120,35"
        $btnOk.Location = "160,110"
        $btnOk.BackColor = "#2D89EF"
        $btnOk.FlatStyle = "Flat"
        $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Controls.Add($btnOk)
        $form.AcceptButton = $btnOk
        return $form.ShowDialog()
    }
}

# ==================== ALL FUNCTION ====================

# ==================== RollOutGroup ====================
function IsUserInRolloutGroup {
    $machine = $env:COMPUTERNAME
    $hash = [math]::Abs(($machine.GetHashCode()))
    $bucket = $hash % 100
    return $bucket -lt $rolloutPercentage
}

# ==================== Parse ====================
function Parse-SemVer {
    param($version)
    if ($version -match '^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$') {
        return @{major=[int]$matches[1]; minor=[int]$matches[2]; patch=[int]$matches[3]; pre=$matches[4]}
    }
    return @{major=0; minor=0; patch=0; pre=""}
}

# ==================== New Version ====================
function Is-NewerVersion {
    param($remote, $local)
    $r = Parse-SemVer $remote
    $l = Parse-SemVer $local

    if ($r.major -ne $l.major) { return $r.major -gt $l.major }
    if ($r.minor -ne $l.minor) { return $r.minor -gt $l.minor }
    if ($r.patch -ne $l.patch) { return $r.patch -gt $l.patch }
    if ([string]::IsNullOrEmpty($r.pre) -and -not [string]::IsNullOrEmpty($l.pre)) { return $true }
    if (-not [string]::IsNullOrEmpty($r.pre) -and [string]::IsNullOrEmpty($l.pre)) { return $false }
    return $r.pre -gt $l.pre
}

# ==================== Backup ====================
function Create-Backup {
    try {
        if (Test-Path $externalBackupDirectory) {
            Remove-Item $externalBackupDirectory -Recurse -Force -ErrorAction Stop
        }
        New-Item -ItemType Directory -Path $externalBackupDirectory -ErrorAction Stop | Out-Null
        # Копирај СÈ од appDirectory
        Get-ChildItem $appDirectory -Force | ForEach-Object {
            $targetPath = Join-Path $externalBackupDirectory $_.Name
            Copy-Item $_.FullName $targetPath -Recurse -Force -ErrorAction Stop
        }
        return $true
    }
    catch {
        Show-DarkDialog -title "Backup Error" -message "Failed to create backup: $_" | Out-Null
        return $false
    }
}

# ==================== Restore ====================
function Restore-Backup {
    if (-not (Test-Path $externalBackupDirectory)) { return }
    try {
        # 1️ Избриши сè од appDirectory
        Get-ChildItem $appDirectory -Force | ForEach-Object {
            try {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                Show-DarkDialog -title "Warning" -message "Warning: Could Not Remove $($_.FullName): $_" | Out-Null
            }
        }
        # 2️ Врати од надворешниот backup
        Get-ChildItem $externalBackupDirectory -Force | ForEach-Object {
            $targetPath = Join-Path $appDirectory $_.Name
            Copy-Item $_.FullName $targetPath -Recurse -Force
        }
    } catch {
        Show-DarkDialog -title "Error" -message "Restore from Backup Failed: $_" | Out-Null
    }
}

# ==================== Verify HASH ====================
function Verify-Hash {
    param($filePath, $expectedHash)
    $actualHash = (Get-FileHash $filePath -Algorithm SHA256).Hash
    return $actualHash -eq $expectedHash
}

# ==================== DARK DOWNLOAD ====================
function Download-File {
    param($url, $dest)
	$fileName = Split-Path $dest -Leaf
	
	# CLEAN OLD TEMP DOWNLOAD
    if (Test-Path $installerDownloadPath) {
        Remove-Item $installerDownloadPath -Force -ErrorAction SilentlyContinue
    }

    $script:isDownloading = $true
    $script:cancelDownload = $false

    $form = New-DarkForm "Downloading Update" 370
    $form.ControlBox = $false
    $form.TopMost = $true
	
    $form.Add_FormClosing({
        if ($script:isDownloading) { $_.Cancel = $true }
    })

    $label = New-Object System.Windows.Forms.Label
    $label.Size = "380,250"
    $label.Location = "30,30"
    $form.Controls.Add($label)

    # CANCEL BUTTON
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Size = "120,35"
    $btnCancel.Location = "160,290"
    $btnCancel.BackColor = "#AA3333"
    $btnCancel.FlatStyle = "Flat"
    $form.Controls.Add($btnCancel)

    $btnCancel.Add_Click({
        $script:cancelDownload = $true
        $btnCancel.Enabled = $false
        $label.Text += "`n`nCancelling..."
    })

    $form.Show()
    $form.Refresh()
	
	# Add title label above the download label
	$titleLabel = New-Object System.Windows.Forms.Label
	$titleLabel.Text = "AutoPilot Update System"
	$titleLabel.Size = "380,25"
	$titleLabel.Location = "30,5"
	$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI",14,[System.Drawing.FontStyle]::Bold)
	$titleLabel.ForeColor = "White"
	$titleLabel.BackColor = [System.Drawing.Color]::FromArgb(28,28,28)
	# Assign updater icon to label with custom size
	if ($Global:UpdaterIcon) {
	# Define custom size
	$iconWidth = 25
	$iconHeight = 25
    # Convert icon to bitmap and resize
    $bitmap = $Global:UpdaterIcon.ToBitmap().GetThumbnailImage($iconWidth, $iconHeight, $null, [IntPtr]::Zero)
    $titleLabel.Image = $bitmap
		$titleLabel.ImageAlign = 'MiddleRight'   # icon on the left of the text
		$titleLabel.TextAlign =  'MiddleLeft'   # text aligned nicely
	}
	$form.Controls.Add($titleLabel)

	# ==================== ADD THIS LINE ====================
	$label.Text = "`nDownloading: $fileName..."
	$form.Refresh()
	[System.Windows.Forms.Application]::DoEvents()
	# =======================================================

    try {
        $request = [System.Net.HttpWebRequest]::Create($url)
		# FIX FOR GITHUB RELEASE REDIRECT
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		$request.AllowAutoRedirect = $true
		
        $response = $request.GetResponse()
        $totalBytes = $response.ContentLength

        $stream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($dest)

        $buffer = New-Object byte[] 8192
        $totalRead = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $lastUpdate = 0

        while (($read = $stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            if ($script:cancelDownload) {
                break
            }
            $fileStream.Write($buffer,0,$read)
            $totalRead += $read
            if ($sw.Elapsed.TotalSeconds -ge $lastUpdate + 1) {

                $percent = [math]::Round(($totalRead / $totalBytes) * 100,2)
                $mbDownloaded = [math]::Round($totalRead / 1MB,2)
                $mbTotal = [math]::Round($totalBytes / 1MB,2)
                $speed = [math]::Round(($totalRead / $sw.Elapsed.TotalSeconds) / 1MB,2)
                $label.Text = @"

File: $fileName				
Total Size: $mbTotal MB

Downloaded: $mbDownloaded MB
Progress: $percent %

Speed: $speed MB/s
"@
                $lastUpdate = $sw.Elapsed.TotalSeconds
                $form.Refresh()
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        $fileStream.Close()
        $stream.Close()

        if ($script:cancelDownload) {
            if (Test-Path $dest) { Remove-Item $dest -Force }
            $script:isDownloading = $false
            $form.Close()
            return $false
        }
		Start-Sleep -Seconds 3
        $script:isDownloading = $false
        $form.Close()
        return $true
    } catch {
        if (Test-Path $dest) { Remove-Item $dest -Force }
        $script:isDownloading = $false
		Start-Sleep -Seconds 3
        $form.Close()
        return $false
    }
}

# ==================== Silent Update ====================
function Check-MinorUpdate {
    try {
		# Silent fetch на manifest
		$json = Invoke-RestMethod -Uri $minorManifestUrl -UseBasicParsing -ErrorAction Stop
		if (-not $json.files) {
			Show-DarkDialog -title "Update Error" -message "No Files Found in Manifest File!" | Out-Null
			Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Silent Update Error: No files found in manifest."
			return
		}
        $statusList = @()
		$updatesPerformed = $false

        foreach ($file in $json.files) {
            $name = $file.name
            $url = $file.url
            $expectedHash = $file.sha256
            $localPath = if ($file.PSObject.Properties.Match('targetPath')) {
                $file.targetPath
            } else {
                Join-Path $appDirectory $name
            }

            $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) $name
            $needDownload = $true
            if (Test-Path $localPath) {
                if (Verify-Hash $localPath $expectedHash) {
                    $needDownload = $false
                }
            }
            if (-not $needDownload) { continue }
            
			$updatesPerformed = $true
            $downloaded = Download-File $url $tempPath
            if (-not $downloaded) {
                $statusList += "${name}: FAILED (Download Error)" 
				Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Silent Update Error: Download failed for $name"
                continue
            }

            if (-not (Verify-Hash $tempPath $expectedHash)) {
                $statusList += "${name}: FAILED (Hash Mismatch)" 
				Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Silent Update Error: Hash mismatch for $name"
                continue
            }

            $directory = Split-Path $localPath
            if (-not (Test-Path $directory)) {
                New-Item -ItemType Directory -Path $directory -Force 
            }

            try {
                Copy-Item $tempPath $localPath -Force
                $statusList += "${name}: Installed Successfully." 
            } catch {
                $statusList += "${name}: FAILED to Install." 
				Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Silent Update Error: Failed to copy/install $name - $_"
            } finally {
                if (Test-Path $tempPath) { Remove-Item $tempPath -Force }
            }
        }

		if ($statusList.Count -gt 0) {
			$message = $statusList -join "`r`n"
			Show-DarkDialog -title "Silent Update Status" -message $message | Out-Null
			Add-Content "$AppRoot\Autopilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Silent Update Status:`n$message`n"
		}
		elseif ($updatesPerformed) {
			Show-DarkDialog -title "Update Finish" -message "All Files Up To Date." | Out-Null
		}
    } catch {
        Show-DarkDialog -title "Update Error" -message "Error in Check-SilentUpdate: $_" | Out-Null
		Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Silent Update Exception: $_"
    }
}

# ==================== New Version Update ====================
function Check-MajorUpdate {
    # 🧹 Clean only corrupted temp files 
    if (Test-Path $installerDownloadPath) {
        Remove-Item $installerDownloadPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $installerTempPath) {
        Remove-Item $installerTempPath -Force -ErrorAction SilentlyContinue
    }

    if (-not (IsUserInRolloutGroup)) { return }

    if (Test-Path $lastDeclineFile) {
        $lastDecline = [datetime]::Parse((Get-Content $lastDeclineFile | Out-String))
        if (((Get-Date) - $lastDecline).TotalDays -lt 5) { return }
    }

    $localVersion = if (Test-Path $localVersionFile) { (Get-Content $localVersionFile).Trim() } else { "0.0.0" }

    try {
        $remoteVersion = (Invoke-RestMethod -Uri $versionUrl).Trim()
        if (-not (Is-NewerVersion $remoteVersion $localVersion)) { return }

        $choice = Show-DarkDialog `
            -title "AutoPilot New Version Update" `
            -message "A New Version $remoteVersion is Available.`nDo You want to Update?" `
            -YesNo

        if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
            Set-Content $lastDeclineFile (Get-Date).ToString("yyyy-MM-dd")
			Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - User declined update to $remoteVersion."
            return
        }

        $realInstallerUrl = Get-LatestInstallerUrl
        if (-not $realInstallerUrl) {
            Show-DarkDialog -title "Error" -message "Installer Not Found in Release." | Out-Null
			Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Installer not found in release for version $remoteVersion."
            return
        }

        if (-not (Download-File $realInstallerUrl $installerDownloadPath)) {
            Show-DarkDialog -title "Update Cancelled" -message "Download Was Cancelled." | Out-Null
			Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Download cancelled for version $remoteVersion."
            return
        }

        $expectedHash = (Invoke-RestMethod -Uri $hashUrl).Trim()
        if (-not (Verify-Hash $installerDownloadPath $expectedHash)) {
            Show-DarkDialog -title "Error" -message "Hash Verification Failed!" | Out-Null
			Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Hash verification failed for downloaded installer of version $remoteVersion."
            return
        }

        # 🧹 Ensure old temp installer is removed (prevents rename conflict)
		if (Test-Path $installerTempPath) {
			Remove-Item $installerTempPath -Force -ErrorAction SilentlyContinue
		}

		Rename-Item $installerDownloadPath $installerTempPath -Force

        # 📦 Create recovery snapshot
        if (-not (Create-Backup)) { 
		Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Backup creation failed before installing version $remoteVersion."
		return 
		}

        # 🚀 Launch installer detached
		$proc = Start-Process -FilePath $installerTempPath -PassThru

		if ($proc) {
			Start-Sleep -Milliseconds 800
			if ($proc.HasExited) {
				# ❌ Installer crashed immediately
				Restore-Backup
				Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Installer crash detected. Backup restored."
				Show-DarkDialog -title "Update Failed" -message "Installer crashed. System restored to previous version." | Out-Null
				return
			}
			# ✅ Installer started correctly → close updater
			Stop-Process -Id $PID -Force
		}
		else {
			# ❌ Installer failed to start at all
			Restore-Backup
			Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Installer failed to start. Backup restored."
			Show-DarkDialog -title "Update Failed" -message "Installer failed to start. System restored to previous version." | Out-Null
		}
	}
	catch {
		Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Exception during Major Update to version ${remoteVersion}: $_"
		Show-DarkDialog -title "Error" -message "New Version Update Check Failed: $_" | Out-Null
	}
}

# ==================== START ====================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==================== Icon Window ====================
try {
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $Global:UpdaterIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
} catch {
    $Global:UpdaterIcon = $null
}

# ==================== Start Funkction ====================

# Funkcija za provera na internet konekcija
function Test-InternetConnection {
    try {
        $request = [System.Net.WebRequest]::Create("http://www.google.com")
        $request.Timeout = 5000
        $response = $request.GetResponse()
        $response.Close()
        return $true
    } catch {
        return $false
    }
}

# Provera i izvrsuvanje na update samo ako ima internet
if (-not (Test-InternetConnection)) {
    # Ako nema internet, pokaži popup error
    Show-DarkDialog -title "Error" -message "No Internet Connection Detected. Updates cannot be checked." | Out-Null
} else {
    Check-MinorUpdate
    Check-MajorUpdate
}

########################################################################################################## Updater End.