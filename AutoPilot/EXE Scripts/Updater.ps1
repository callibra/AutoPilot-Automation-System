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

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        SizeToContent="WidthAndHeight"
        Background="Transparent"
        WindowStyle="None"
        AllowsTransparency="True">
    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Foreground" Value="#E4E4E7"/>
            <Setter Property="Background">
                <Setter.Value>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                        <GradientStop Color="#2C3039" Offset="0.0"/>
                        <GradientStop Color="#22252C" Offset="1.0"/>
                    </LinearGradientBrush>
                </Setter.Value>
            </Setter>
            <Setter Property="Padding" Value="20,12"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderBrush" Value="#3B3F4A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="11">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="5"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background">
                                    <Setter.Value>
                                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                            <GradientStop Color="#1E3A44" Offset="0.0"/>
                                            <GradientStop Color="#172D35" Offset="1.0"/>
                                        </LinearGradientBrush>
                                    </Setter.Value>
                                </Setter>
                                <Setter TargetName="border" Property="BorderBrush" Value="#D4D4D8"/>
                                <Setter TargetName="border" Property="Effect">
                                    <Setter.Value>
                                        <DropShadowEffect Color="#D4D4D8" BlurRadius="14" ShadowDepth="0" Opacity="0.45"/>
                                    </Setter.Value>
                                </Setter>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#12222A"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#E4E4E7"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="BlueButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="#0369A1"/>
            <Setter Property="BorderBrush" Value="#0369A1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="11">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="5"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#0284C7"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#075985"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border Background="#FF22252C" CornerRadius="16" Padding="20" BorderBrush="#0369A1" BorderThickness="1">
        <StackPanel Width="520">
            <TextBlock x:Name="DialogTitle" FontSize="24" FontWeight="Bold" Foreground="#E4E4E7" Margin="0,0,0,10" HorizontalAlignment="Center"/>
            <TextBlock x:Name="DialogMessage" TextWrapping="Wrap" FontSize="16" Foreground="#D4D4D8" Margin="0,0,0,20"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                <Button x:Name="btnYes" Content="Yes" Width="100" Height="40" Style="{StaticResource ModernButton}"/>
                <Button x:Name="btnNo" Content="No" Width="100" Height="40" Style="{StaticResource ModernButton}"/>
                <Button x:Name="btnOk" Content="OK" Width="120" Height="40" Style="{StaticResource BlueButton}"/>
            </StackPanel>
        </StackPanel>
    </Border>
</Window>
"@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $window.FindName("DialogTitle").Text = $title
    $window.FindName("DialogMessage").Text = $message
    $btnYes = $window.FindName("btnYes")
    $btnNo = $window.FindName("btnNo")
    $btnOk = $window.FindName("btnOk")

    if ($YesNo) {
        $btnOk.Visibility = "Collapsed"
        $btnYes.IsDefault = $true
        $btnYes.Add_Click({ $window.DialogResult = $true })
        $btnNo.IsCancel = $true
        $btnNo.Add_Click({ $window.DialogResult = $false })
    }
    else {
        $btnYes.Visibility = "Collapsed"
        $btnNo.Visibility = "Collapsed"
        $btnOk.IsDefault = $true
        $btnOk.Add_Click({ $window.DialogResult = $true })
    }

    $dialogResult = $window.ShowDialog()
    if ($YesNo) {
        if ($dialogResult -eq $true) { return [System.Windows.Forms.DialogResult]::Yes }
        if ($dialogResult -eq $false) { return [System.Windows.Forms.DialogResult]::No }
        return [System.Windows.Forms.DialogResult]::Cancel
    }
    if ($dialogResult -eq $true) { return [System.Windows.Forms.DialogResult]::OK }
    return [System.Windows.Forms.DialogResult]::Cancel
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

    $window = New-Object System.Windows.Window
    $window.Title = "Downloading Update"
    $window.Width = 500
    $window.Height = 470
    $window.WindowStartupLocation = "CenterScreen"
    $window.ResizeMode = "NoResize"
    $window.Topmost = $true
    $window.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(30,33,40))

    $buttonStyleXaml = @"
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Style x:Key="ModernButton" TargetType="Button">
        <Setter Property="Foreground" Value="#F1F5F9"/>
        <Setter Property="Background">
            <Setter.Value>
                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop Color="#2C3039" Offset="0.0"/>
                    <GradientStop Color="#22252C" Offset="1.0"/>
                </LinearGradientBrush>
            </Setter.Value>
        </Setter>
        <Setter Property="Padding" Value="20,12"/>
        <Setter Property="FontFamily" Value="Segoe UI"/>
        <Setter Property="FontSize" Value="15"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="BorderBrush" Value="#3B3F4A"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="11">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="5"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="border" Property="Background">
                                <Setter.Value>
                                    <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                        <GradientStop Color="#1E3A44" Offset="0.0"/>
                                        <GradientStop Color="#172D35" Offset="1.0"/>
                                    </LinearGradientBrush>
                                </Setter.Value>
                            </Setter>
                            <Setter TargetName="border" Property="BorderBrush" Value="#D4D4D8"/>
                            <Setter TargetName="border" Property="Effect">
                                <Setter.Value>
                                    <DropShadowEffect Color="#D4D4D8" BlurRadius="14" ShadowDepth="0" Opacity="0.45"/>
                                </Setter.Value>
                            </Setter>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Setter TargetName="border" Property="Background" Value="#12222A"/>
                            <Setter TargetName="border" Property="BorderBrush" Value="#E4E4E7"/>
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter TargetName="border" Property="Opacity" Value="0.4"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>
"@
    $buttonStyleReader = New-Object System.Xml.XmlNodeReader ([xml]$buttonStyleXaml)
    $buttonStyle = [System.Windows.Markup.XamlReader]::Load($buttonStyleReader)
    $window.Resources.MergedDictionaries.Add($buttonStyle)

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = [System.Windows.Thickness]::new(26)

    $titleLabel = New-Object System.Windows.Controls.TextBlock
    $titleLabel.Text = "🚀 AutoPilot Update"
    $titleLabel.FontSize = 23
    $titleLabel.FontWeight = "Bold"
    $titleLabel.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(248,250,252))
    $titleLabel.Margin = [System.Windows.Thickness]::new(0,0,0,4)
    $stack.Children.Add($titleLabel) | Out-Null

    $subtitleLabel = New-Object System.Windows.Controls.TextBlock
    $subtitleLabel.Text = "Downloading your update. Please keep this window open."
    $subtitleLabel.FontSize = 16
    $subtitleLabel.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(203,213,225))
    $subtitleLabel.Margin = [System.Windows.Thickness]::new(0,0,0,22)
    $stack.Children.Add($subtitleLabel) | Out-Null

    $fileCard = New-Object System.Windows.Controls.Border
    $fileCard.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(38,42,51))
    $fileCard.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $fileCard.Padding = [System.Windows.Thickness]::new(16,12,16,12)
    $fileCard.Margin = [System.Windows.Thickness]::new(0,0,0,24)
    $fileStack = New-Object System.Windows.Controls.StackPanel

    $fileCaption = New-Object System.Windows.Controls.TextBlock
    $fileCaption.Text = "📦  UPDATE FILE"
    $fileCaption.FontSize = 13
    $fileCaption.FontWeight = "SemiBold"
    $fileCaption.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(165,180,252))
    $fileCaption.Margin = [System.Windows.Thickness]::new(0,0,0,6)
    $fileStack.Children.Add($fileCaption) | Out-Null

    $fileLabel = New-Object System.Windows.Controls.TextBlock
    $fileLabel.Text = $fileName
    $fileLabel.TextWrapping = "Wrap"
    $fileLabel.FontSize = 17
    $fileLabel.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(248,250,252))
    $fileStack.Children.Add($fileLabel) | Out-Null
    $fileCard.Child = $fileStack
    $stack.Children.Add($fileCard) | Out-Null

    $progressHeader = New-Object System.Windows.Controls.Grid
    $progressHeader.Margin = [System.Windows.Thickness]::new(0,0,0,8)
    $progressHeader.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
    $progressPercent = New-Object System.Windows.Controls.TextBlock
    $progressPercent.Text = "⏳ Preparing download..."
    $progressPercent.FontSize = 16
    $progressPercent.FontWeight = "SemiBold"
    $progressPercent.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(248,250,252))
    [System.Windows.Controls.Grid]::SetColumn($progressPercent,0)
    $progressHeader.Children.Add($progressPercent) | Out-Null
    $stack.Children.Add($progressHeader) | Out-Null

    $progressBar = New-Object System.Windows.Controls.ProgressBar
    $progressBar.Height = 10
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.IsIndeterminate = $true
    $progressBar.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(99,102,241))
    $progressBar.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(71,79,94))
    $progressBar.BorderThickness = [System.Windows.Thickness]::new(0)
    $progressBar.Margin = [System.Windows.Thickness]::new(0,0,0,18)
    $stack.Children.Add($progressBar) | Out-Null

    $downloadStatus = New-Object System.Windows.Controls.TextBlock
    $downloadStatus.Text = "📥  Downloaded: 0 MB`n⚡  Speed: -- MB/s"
    $downloadStatus.TextWrapping = "Wrap"
    $downloadStatus.FontSize = 16
    $downloadStatus.FontFamily = "Segoe UI"
    $downloadStatus.LineHeight = 29
    $downloadStatus.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(226,232,240))
    $stack.Children.Add($downloadStatus) | Out-Null

    $btnCancel = New-Object System.Windows.Controls.Button
    $btnCancel.Content = "Stop Download"
    $btnCancel.Width = 160
    $btnCancel.Height = 42
    $btnCancel.HorizontalAlignment = "Center"
    $btnCancel.Margin = [System.Windows.Thickness]::new(0,22,0,0)
    $btnCancel.Style = $window.FindResource("ModernButton")
    $stack.Children.Add($btnCancel) | Out-Null

    $btnCancel.Add_Click({
        $script:cancelDownload = $true
        $btnCancel.IsEnabled = $false
        $progressPercent.Text = "⏹  Stopping the download..."
    })
    $window.Add_Closing({
        if ($script:isDownloading) {
            $_.Cancel = $true
            $script:cancelDownload = $true
            $btnCancel.IsEnabled = $false
            $progressPercent.Text = "⏹  Stopping the download..."
        }
    })

    $window.Content = $stack
    $window.Show()
    [System.Windows.Forms.Application]::DoEvents()

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

                $mbDownloaded = [math]::Round($totalRead / 1MB,2)
                $mbTotal = [math]::Round($totalBytes / 1MB,2)
                $speed = [math]::Round(($totalRead / $sw.Elapsed.TotalSeconds) / 1MB,2)
                if ($totalBytes -gt 0) {
                    $percent = [math]::Round(($totalRead / $totalBytes) * 100,2)
                    $progressBar.IsIndeterminate = $false
                    $progressBar.Value = $percent
                    $progressPercent.Text = "⬇  Downloading  $percent%"
                    $downloadStatus.Text = "📥  Downloaded: $mbDownloaded / $mbTotal MB`n⚡  Speed: $speed MB/s"
                }
                else {
                    $downloadStatus.Text = "📥  Downloaded: $mbDownloaded MB`n⚡  Speed: $speed MB/s"
                }
                $lastUpdate = $sw.Elapsed.TotalSeconds
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        $fileStream.Close()
        $stream.Close()

        if ($script:cancelDownload) {
            if (Test-Path $dest) { Remove-Item $dest -Force }
            $script:isDownloading = $false
            $window.Close()
            return $false
        }
		Start-Sleep -Seconds 3
        $script:isDownloading = $false
        $window.Close()
        return $true
    } catch {
        if (Test-Path $dest) { Remove-Item $dest -Force }
        $script:isDownloading = $false
		Start-Sleep -Seconds 3
        $window.Close()
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
            Show-DarkDialog -title "Update Stopped" -message "Download Was Stopped." | Out-Null
			Add-Content "$AppRoot\AutoPilot_Data\Update_Logs\Updater.log" "$(Get-Date) - Download stopped for version $remoteVersion."
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
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

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