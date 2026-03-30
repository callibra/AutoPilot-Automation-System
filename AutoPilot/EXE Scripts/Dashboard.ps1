Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
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

# ===================== Dashboard Flag =====================
$flagFile = Join-Path $AppRoot "Autopilot_Data\Dashboard.flag"
function Remove-DashboardFlag {
    if (Test-Path $flagFile) {
        Remove-Item $flagFile -Force -ErrorAction SilentlyContinue
    }
}

# ===================== WARNING POP UP =====================
function Show-DarkWarning {
    param(
        [string]$Message,
        [string]$Title = "Warning"
    )
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Width="520"
        Height="235"
        Background="#1E1E1E"
        Title="$Title"
        WindowStyle="None"
        AllowsTransparency="True"
        ShowInTaskbar="False">
    <Border Background="#2D2D30"
            CornerRadius="14"
            Padding="25"
            BorderBrush="#3C3C3C"
            BorderThickness="2">
        <StackPanel Width="460">
            <TextBlock Text="$Title" FontSize="24" FontWeight="Bold" Foreground="#E6E6E6" Margin="0,0,0,15" HorizontalAlignment="Center"/>
            <TextBlock Text="$Message" TextWrapping="Wrap" FontSize="16" Foreground="#DADADA" Margin="0,0,0,25" TextAlignment="Center"/>
            <Button Content="OK" Width="140" Height="42" HorizontalAlignment="Center" Foreground="White" FontWeight="SemiBold" BorderThickness="0" Cursor="Hand">
				<Button.Template>
					<ControlTemplate TargetType="Button">
						<Border x:Name="border" Background="#007ACC" CornerRadius="4">
							<ContentPresenter HorizontalAlignment="Center"  VerticalAlignment="Center"/>
						</Border>
						<ControlTemplate.Triggers>
							<Trigger Property="IsMouseOver" Value="True">
								<Setter TargetName="border" Property="Background" Value="#3399FF"/>
							</Trigger>
							<Trigger Property="IsPressed" Value="True">
								<Setter TargetName="border" Property="Background" Value="#005999"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Button.Template>
			</Button>
        </StackPanel>
    </Border>
</Window>
"@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $win = [Windows.Markup.XamlReader]::Load($reader)
    $btn = $win.Content.Child.Children[2]
    $btn.Add_Click({ $win.Close() })
    $win.ShowDialog() | Out-Null
}

# ===================== Password File =====================
$PasswordFile = Join-Path $AppRoot "Autopilot_Data\password.json"

# ===================== REGISTRY BACKUP/RESTORE =====================
$RegistryPath = "HKCU:\Software\MicrosoftKeySecurity"
$RegistryValueName = "ProgramValueKey"

function Backup-PasswordToRegistry {
    if (Test-Path $PasswordFile) {
        $jsonContent = Get-Content $PasswordFile -Raw
        if (-not (Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force | Out-Null
        }
        Set-ItemProperty -Path $RegistryPath -Name $RegistryValueName -Value $jsonContent
    }
}

function Restore-PasswordFromRegistry {
    if (-not (Test-Path $PasswordFile) -and (Test-Path $RegistryPath)) {
        try {
            $jsonContent = Get-ItemPropertyValue -Path $RegistryPath -Name $RegistryValueName
            $dir = Split-Path $PasswordFile -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $jsonContent | Set-Content -Path $PasswordFile -Encoding UTF8
        } catch {
            # Write-Warning "Cannot restore password.json from Registry"
        }
    }
}

# ===================== VERIFY JSON VS REGISTRY =====================
function Verify-PasswordIntegrity {
    if (-not (Test-Path $PasswordFile)) { return }
    if (-not (Test-Path $RegistryPath)) { return }
    try {
        $jsonFile = Get-Content $PasswordFile -Raw
        $jsonRegistry = Get-ItemPropertyValue -Path $RegistryPath -Name $RegistryValueName -ErrorAction SilentlyContinue
        if (-not $jsonRegistry) { return }
        if ($jsonFile.Trim() -ne $jsonRegistry.Trim()) {
            $jsonRegistry | Set-Content -Path $PasswordFile -Encoding UTF8
        }
    }
    catch {
        # Write-Warning "Cannot verify the integrity of password.json."
    }
}

# ===================== EXECUTE RESTORE =====================
Restore-PasswordFromRegistry

# ===================== VERIFY FILE INTEGRITY =====================
Verify-PasswordIntegrity

# ===================== CREATE DEFAULT PASSWORD FILE IF MISSING =====================
if (-not (Test-Path $PasswordFile)) {
    $initialData = @{
        Password = ""
        Key = ""
        IV = ""
        Enabled = $false
    }
    $dir = Split-Path $PasswordFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $initialData | ConvertTo-Json | Set-Content -Path $PasswordFile -Encoding UTF8
	
    # ==== AUTOMATIC BACKUP TO REGISTRY AFTER CREATION ====
    Backup-PasswordToRegistry
}

# ===================== SAVE / LOAD PASSWORD =====================
function Save-Password {
    param ([string]$PlainText, [bool]$Enabled)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.GenerateKey()
    $aes.GenerateIV()
    $encryptor = $aes.CreateEncryptor()
    $cipherBytes = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
    $data = @{
        Password = [Convert]::ToBase64String($cipherBytes)
        Key = [Convert]::ToBase64String($aes.Key)
        IV = [Convert]::ToBase64String($aes.IV)
        Enabled = $Enabled
    }
    $data | ConvertTo-Json | Set-Content -Path $PasswordFile -Encoding UTF8
    # ==== AUTOMATIC BACKUP TO REGISTRY AFTER SAVE ====
    Backup-PasswordToRegistry
}

function Load-Password {
    if (-not (Test-Path $PasswordFile)) { return $null }
    $data = Get-Content $PasswordFile | ConvertFrom-Json
    if (-not $data.Enabled) { return $null }
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = [Convert]::FromBase64String($data.Key)
    $aes.IV = [Convert]::FromBase64String($data.IV)
    $cipherBytes = [Convert]::FromBase64String($data.Password)
    $decryptor = $aes.CreateDecryptor()
    $plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
    return [System.Text.Encoding]::UTF8.GetString($plainBytes)
}

# ===================== CHECK PASSWORD =====================
if (-not (Test-Path $PasswordFile)) {
    Show-DarkWarning -Title "🔒 AutoPilot Dashboard Lock" -Message "Password File ($PasswordFile) not found! AutoPilot cannot Start."
    exit
}
$Password = Load-Password
if ($Password) {
    $LockExePath = Join-Path $AppRoot "Lock.exe"
    if (Test-Path $LockExePath) {
        $proc = Start-Process -FilePath $LockExePath -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Show-DarkWarning -Title "🔒 AutoPilot Dashboard Lock" -Message "AutoPilot cannot Start without the Correct Password."
            exit
        }
    } else {
        Show-DarkWarning -Title "🔒 AutoPilot Dashboard Lock" -Message "Lock.exe not found in $AppRoot."
        exit
    }
} <#else {
    Write-Host "AutoPilot Startuva bex Lozinka."
} #>

# CREATE FLAG ON START
$flagDir = Split-Path $flagFile -Parent
if (-not (Test-Path $flagDir)) {
    New-Item -ItemType Directory -Path $flagDir -Force | Out-Null
}
"RUNNING" | Set-Content $flagFile -Force -Encoding UTF8

$Global:pauseFlagPath = "$AppRoot\Autopilot_Data\pause.flag"

# ===================== AUTO START UPDATER =====================
$UpdaterPath = Join-Path $AppRoot "Updater.exe"

# Ensure Update_Logs folder exists
$updateLogsDir = Join-Path $AppRoot "Autopilot_Data\Update_Logs"
if (-not (Test-Path $updateLogsDir)) {
    New-Item -ItemType Directory -Path $updateLogsDir -Force | Out-Null
}

$LogPath = Join-Path $updateLogsDir "Updater.log"

function Write-Log {
    param ([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
}

# Start updater once after 10 seconds
if (Test-Path $UpdaterPath) {
    Start-Process "powershell.exe" -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Start-Sleep -Seconds 10; Start-Process -FilePath '$UpdaterPath'`""
    Write-Log "Updater scheduled to start after 10 seconds."
} else {
    Write-Log "Updater.exe not found at path: $UpdaterPath"
}

# Load modules
. "$AppRoot\System.ps1"
. "$AppRoot\Graphs.ps1"
. "$AppRoot\NetTrafficTable.ps1"
. "$AppRoot\Media.ps1"

# Load WPF
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

# ===================== COMMAND MAP =====================
$ManualCommands = @{
    # System commands
    "/system_status"      = @{ Cmd = "System-Status" }
    "/ping"               = @{ Cmd = "Get-NetworkStatus" }
    "/temp"               = @{ Cmd = "Get-Temperatures" }
	"/total_load"         = @{ Cmd = "Get-LoadOnlyHardwareData" }
    "/total_stat"         = @{ Cmd = "Get-NonLoadHardwareData" }
	"/screen"             = @{ Cmd = "Take-Screenshot" }
	"/net_monitor"        = @{ Cmd = "Show-LiveTraffic" }
	"/system_monitor"     = @{ Cmd = "Show-SystemMonitor" }
	"/data"               = @{ Cmd = "Data-Folder" }
	"/media"              = @{ Cmd = "Media" }
	"/camera"             = @{ Cmd = "Camera" }
	"/start-autopilot"    = @{ Cmd = "Start-AutoPilot" }
	"/stop-autopilot"     = @{ Cmd = "Stop-AutoPilot" }
	"/refresh"            = @{ Cmd = "Restart-AutoPilotWithLog" }
	"/task-add"           = @{ Cmd = "Task-Add" }
	"/task-del"           = @{ Cmd = "Task-Del" }
	"/task-show"          = @{ Cmd = "Task-Show" }
	"/show_cmd"           = @{ Cmd = "Show-CMDWindow" }
	"/hide_cmd"           = @{ Cmd = "Hide-CMDWindow" }
    # Graph Load commands
    "/load_day"           = @{ Cmd = "Generate-LoadGraph-Day" }
    "/load_week"          = @{ Cmd = "Generate-LoadGraph-Week" }
    "/load_month"         = @{ Cmd = "Generate-LoadGraph-Month" }
    "/load_year"          = @{ Cmd = "Generate-LoadGraph-Year" }
    "/load_all"           = @{ Cmd = "Generate-LoadGraph-All" }
	"/load_archive"       = @{ Cmd = "Load-Archive" }
    # Graph Temperature commands
    "/temp_day"           = @{ Cmd = "Generate-TempGraph-Day" }
    "/temp_week"          = @{ Cmd = "Generate-TempGraph-Week" }
    "/temp_month"         = @{ Cmd = "Generate-TempGraph-Month" }
    "/temp_year"          = @{ Cmd = "Generate-TempGraph-Year" }
    "/temp_all"           = @{ Cmd = "Generate-TempGraph-All" }
	"/temp_archive"       = @{ Cmd = "Temp-Archive" }
    # Graph Disk Load commands
    "/disk_day"           = @{ Cmd = "Generate-DiskGraph-Day" }
    "/disk_week"          = @{ Cmd = "Generate-DiskGraph-Week" }
    "/disk_month"         = @{ Cmd = "Generate-DiskGraph-Month" }
    "/disk_year"          = @{ Cmd = "Generate-DiskGraph-Year" }
    "/disk_all"           = @{ Cmd = "Generate-DiskGraph-All" }
	"/disk_archive"       = @{ Cmd = "Disk-Archive" }
    # Table Net Traffic commands
    "/table_day"          = @{ Cmd = "Generate-TableGraph-Day" }
    "/table_week"         = @{ Cmd = "Generate-TableGraph-Week" }
    "/table_month"        = @{ Cmd = "Generate-TableGraph-Month" }
    "/table_year"         = @{ Cmd = "Generate-TableGraph-Year" }
    "/table_all"          = @{ Cmd = "Generate-TableGraph-All" }
	"/table_archive"      = @{ Cmd = "Table-Archive" }
	# Log File/Archive commands
    "/autopilot_log"      = @{ Cmd = "AutoPilot-Log" }
    "/system_log"         = @{ Cmd = "System-Monitoring-Log" }
    "/traffic_log"        = @{ Cmd = "Traffic-Monitoring-Log" }
    "/data_log"           = @{ Cmd = "Data-Log" }
    "/network_log"        = @{ Cmd = "Network-Log" }
	"/update_log"         = @{ Cmd = "Update-Log" }
	# System Monitoring commands
	"/monitoring_start"   = @{ Cmd = "Start-Monitoring" }
    "/monitoring_stop"    = @{ Cmd = "Stop-Monitoring" }
    "/monitoring_status"  = @{ Cmd = "Get-MonitoringStatus" }
	"/stop_worker"        = @{ Cmd = "Stop-Workers" }
}
# Hash Table to PNG
$LoadGraphPaths = @{
    # ScreenShot
	"Take-Screenshot"           = "$AppRoot\Screenshot\screenshot.png"
	# Load
    "Generate-LoadGraph-Day"    = "$AppRoot\Data\load_1d.png"
    "Generate-LoadGraph-Week"   = "$AppRoot\Data\load_7d.png"
    "Generate-LoadGraph-Month"  = "$AppRoot\Data\load_30d.png"
    "Generate-LoadGraph-Year"   = "$AppRoot\Data\load_365d.png"
    "Generate-LoadGraph-All"    = "$AppRoot\Data\load_Alld.png"
    # Temperature
    "Generate-TempGraph-Day"    = "$AppRoot\Data\temperature_1d.png"
    "Generate-TempGraph-Week"   = "$AppRoot\Data\temperature_7d.png"
    "Generate-TempGraph-Month"  = "$AppRoot\Data\temperature_30d.png"
    "Generate-TempGraph-Year"   = "$AppRoot\Data\temperature_365d.png"
    "Generate-TempGraph-All"    = "$AppRoot\Data\temperature_Alld.png"
    # Disk
    "Generate-DiskGraph-Day"    = "$AppRoot\Data\disk_1d.png"
    "Generate-DiskGraph-Week"   = "$AppRoot\Data\disk_7d.png"
    "Generate-DiskGraph-Month"  = "$AppRoot\Data\disk_30d.png"
    "Generate-DiskGraph-Year"   = "$AppRoot\Data\disk_365d.png"
    "Generate-DiskGraph-All"    = "$AppRoot\Data\disk_Alld.png"
    # Table
    "Generate-TableGraph-Day"   = "$AppRoot\Data\table_1d.png"
    "Generate-TableGraph-Week"  = "$AppRoot\Data\table_7d.png"
    "Generate-TableGraph-Month" = "$AppRoot\Data\table_30d.png"
    "Generate-TableGraph-Year"  = "$AppRoot\Data\table_365d.png"
    "Generate-TableGraph-All"   = "$AppRoot\Data\table_Alld.png"
}

# Invoke Manual Command
function Invoke-ManualCommand {
    param([string]$Command)
    if (-not $ManualCommands.ContainsKey($Command)) {
        [System.Windows.MessageBox]::Show("Unknown command: $Command")
        return
    }
    $cmdName = $ManualCommands[$Command].Cmd
    if (-not (Get-Command $cmdName -CommandType Function -ErrorAction SilentlyContinue)) {
        [System.Windows.MessageBox]::Show("Komanda $cmdName not defined in the current session")
        return
    }
    try {
		# Show temporary "Loading" popup
		$loadingWindow = Show-LoadingPopup
		$loadingWindow.Show()
		# Pause 3–4 seconds
		Start-Sleep -Seconds 3.5
		# Close loading popup
		$loadingWindow.Close()
        # Execute command
        $result = & $cmdName
        # Handle result: PNG or text
        if ($LoadGraphPaths.ContainsKey($cmdName)) {
            $path = $LoadGraphPaths[$cmdName]
            $elapsed = 0
            $timeout = 5
            while (-not (Test-Path $path) -and $elapsed -lt $timeout) {
                Start-Sleep -Milliseconds 500
                $elapsed += 0.5
            }
            if (Test-Path $path) {
                Show-ImagePopup $path
            } else {
                Show-StatusPopup "Error" "Image cannot be found: $path" $false
            }
				} else {
			if ($null -eq $result) {
				return
			}
			if ($result -is [string]) {
				# VIDEO file
				if ($result -match '\.(mp4|avi|mov|wmv)$' -and (Test-Path $result)) {
					Start-Process $result
					return
				}
				# TEXT
				Show-StatusPopup "System Status" $result
			} else {
			  #	Show-StatusPopup "Error" "Nepoznat tip na rezultat: $($result.GetType().FullName)" $false
			}
		}
    } catch {
        Show-StatusPopup "Error" "Error executing command `$Command`: $_" $false
    }
}

# LOADING .....
function Show-LoadingPopup {
    param(
        [string]$Message="Loading...",
        [string]$ImagePath="$AppRoot\media\loading.png"  
    )
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Please wait"
        Width="400"
        Height="150"
        WindowStartupLocation="CenterScreen"
        Background="Transparent"
        FontFamily="Segoe UI"
        ResizeMode="NoResize"
        WindowStyle="None"
        AllowsTransparency="True">
    <Border CornerRadius="12"
            Padding="15"
            BorderThickness="1"
            BorderBrush="#555">
        <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                <GradientStop Color="#FF1E1E1E" Offset="0"/>
                <GradientStop Color="#FF2D2D30" Offset="1"/>
            </LinearGradientBrush>
        </Border.Background>
        <Grid>
            <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                <!-- PNG image -->
                <Image Name="imgLoading" Width="80" Height="80" Margin="0,0,0,10"/>
                <TextBlock Text="$Message"
                           Foreground="#E0E0E0"
                           FontSize="20"
                           FontWeight="SemiBold"
                           HorizontalAlignment="Center"
                           VerticalAlignment="Center"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    # Load PNG 
    if (Test-Path $ImagePath) {
        $imgControl = $window.FindName("imgLoading")
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.UriSource = [Uri]::new($ImagePath, [UriKind]::Absolute)
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.EndInit()
        $imgControl.Source = $bitmap
    }
    return $window
}

# STATUS POP-UP
function Show-StatusPopup {
    param(
        [string]$Title = "Status",
        [string]$Message,
        [bool]$EnableSave = $true
    )
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title"
        Width="777"
        SizeToContent="Height"
        MaxHeight="$($Global:statusMaxHeight)"
        WindowStartupLocation="CenterScreen"
        Background="#2D2D30"
        FontFamily="Segoe UI"
        ResizeMode="NoResize"
        WindowStyle="SingleBorderWindow">
    <Grid Margin="10">
        <Border CornerRadius="10" Background="#1E1E1E" BorderBrush="#444" BorderThickness="2" Padding="15">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="60"/>
                </Grid.RowDefinitions>
                <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <TextBlock Name="txtMessage" TextWrapping="Wrap" Foreground="White" FontSize="18"/>
                </ScrollViewer>
                <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Center">
					<Button Name="btnSave" Content="Save" Width="80" Height="30" Margin="0,0,10,0" Foreground="White" FontWeight="Bold">
					<Button.Template>
						<ControlTemplate TargetType="Button">
							<Border x:Name="border" Background="#7938F2" CornerRadius="3">
								<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
							</Border>
							<ControlTemplate.Triggers>
								<Trigger Property="IsMouseOver" Value="True">
									<Setter TargetName="border" Property="Background" Value="#A260F7"/>
								</Trigger>
								<Trigger Property="IsPressed" Value="True">
									<Setter TargetName="border" Property="Background" Value="#7030C0"/>
								</Trigger>
							</ControlTemplate.Triggers>
						</ControlTemplate>
					</Button.Template>
					</Button>
					<Button Name="btnOk" Content="OK" Width="80" Height="30" Foreground="White" FontWeight="Bold">
					<Button.Template>
					<ControlTemplate TargetType="Button">
						<Border x:Name="border" Background="#007ACC" CornerRadius="3">
							<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
						</Border>
						<ControlTemplate.Triggers>
							<Trigger Property="IsMouseOver" Value="True">
								<Setter TargetName="border" Property="Background" Value="#3399FF"/>
							</Trigger>
							<Trigger Property="IsPressed" Value="True">
								<Setter TargetName="border" Property="Background" Value="#005999"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
					</Button.Template>
					</Button>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    # Message
    $txtMessage = $window.FindName("txtMessage")
    $txtMessage.Text = $Message
    # OK Button
    $btnOk = $window.FindName("btnOk")
    $btnOk.Add_Click({ $window.Close() })
    # Save Button
    $btnSave = $window.FindName("btnSave")
    # Save Disabled 
    if (-not $EnableSave) {
        $btnSave.Visibility = "Collapsed"
    }
    else {
        $btnSave.Add_Click({
            try {
                $archiveDir = Join-Path $AppRoot "Archive\File"

                if (-not (Test-Path $archiveDir)) {
                    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
                }
                $fileName = "{0}_{1}.txt" -f `
                    ($Title -replace '[^\w\-]', '_'),
                    (Get-Date -Format "yyyyMMdd_HHmmss")
                $filePath = Join-Path $archiveDir $fileName
                $Message | Out-File -FilePath $filePath -Encoding UTF8
                # Save here is disabled
                Show-StatusPopup "Saved" "The result has been saved in:`n$filePath" $false
            }
            catch {
                Show-StatusPopup "Error" "Failed to save:`n$_" $false
            }
        })
    }
    $window.ShowDialog() | Out-Null
}

# IMAGE POP-UP
function Show-ImagePopup {
    param([string]$ImagePath, [string]$Title="Graph")
    if (-not (Test-Path $ImagePath)) {
        Show-StatusPopup "Error" "The image does not exist: $ImagePath"
        return
    }
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title"
        Width="1200"
        SizeToContent="Height"
        MaxHeight="$($Global:popupMaxHeight)"
        WindowStartupLocation="CenterScreen"
        Background="#2D2D30"
        FontFamily="Segoe UI"
        ResizeMode="NoResize"
        WindowStyle="SingleBorderWindow">
    <Border Margin="10" CornerRadius="10" Background="#1E1E1E" BorderBrush="#444" BorderThickness="2" Padding="10">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="60"/>
                </Grid.RowDefinitions>
                <Image Name="imgControl" Stretch="None" Margin="0,0,0,10"/>
                <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Center">
				<Button Name="btnSave" Content="Save" Width="80" Height="30" Margin="0,0,10,0" Foreground="White" FontWeight="Bold">
					<Button.Template>
						<ControlTemplate TargetType="Button">
							<Border x:Name="border" Background="#7938F2" CornerRadius="3">
								<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
							</Border>
							<ControlTemplate.Triggers>
								<Trigger Property="IsMouseOver" Value="True">
									<Setter TargetName="border" Property="Background" Value="#A260F7"/>
								</Trigger>
								<Trigger Property="IsPressed" Value="True">
									<Setter TargetName="border" Property="Background" Value="#7030C0"/>
								</Trigger>
							</ControlTemplate.Triggers>
						</ControlTemplate>
					</Button.Template>
				</Button>
				<Button Name="btnOk" Content="OK" Width="80" Height="30" Foreground="White" FontWeight="Bold">
					<Button.Template>
						<ControlTemplate TargetType="Button">
							<Border x:Name="border" Background="#007ACC" CornerRadius="3">
								<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
							</Border>
							<ControlTemplate.Triggers>
								<Trigger Property="IsMouseOver" Value="True">
									<Setter TargetName="border" Property="Background" Value="#3399FF"/>
								</Trigger>
								<Trigger Property="IsPressed" Value="True">
									<Setter TargetName="border" Property="Background" Value="#005999"/>
								</Trigger>
							</ControlTemplate.Triggers>
						</ControlTemplate>
					</Button.Template>
				</Button>
                </StackPanel>
            </Grid>
        </ScrollViewer>
    </Border>
</Window>
"@
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    # Load fresh image from disk to avoid caching old PNG
	$bytes = [System.IO.File]::ReadAllBytes($ImagePath)
	$stream = [System.IO.MemoryStream]::new($bytes)
	$bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
	$bitmap.BeginInit()
	$bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
	$bitmap.StreamSource = $stream
	$bitmap.EndInit()
	$bitmap.Freeze()
    # Set Image Source
    $imgControl = $window.FindName("imgControl")
    $imgControl.Source = $bitmap
    # OK Button
    $btnOk = $window.FindName("btnOk")
    $btnOk.Add_Click({ $window.Close() })
    # SAVE Button
    $btnSave = $window.FindName("btnSave")
    $btnSave.Add_Click({
        try {
            # Archive Folder
            $baseArchive = Join-Path $AppRoot "Archive"
            # SubFolder
            $fileLower = [IO.Path]::GetFileName($ImagePath).ToLower()
            switch -Regex ($fileLower) {
                '^load_'        { $subFolder = 'Load' }
                '^temperature_' { $subFolder = 'Temperature' }
                '^table_'       { $subFolder = 'Table' }
                '^disk_'        { $subFolder = 'Disk' }
                '^screenshot'   { $subFolder = 'ScreenShot' }
                default         { $subFolder = 'Other' }
            }
            $archiveDir = Join-Path $baseArchive $subFolder
            if (-not (Test-Path $archiveDir)) {
                New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
            }
            # File Name
            $fileName = "{0}_{1}.png" -f `
                ([IO.Path]::GetFileNameWithoutExtension($ImagePath)),
                (Get-Date -Format "yyyyMMdd_HHmmss")
            $destPath = Join-Path $archiveDir $fileName
            Copy-Item -Path $ImagePath -Destination $destPath -Force
            Show-StatusPopup "Saved" "The image has been saved in:`n$destPath" $false
        }
        catch {
            Show-StatusPopup "Error" "Failed to save the image:`n$_" $false
        }
    })
    $window.ShowDialog() | Out-Null
}

# ===================== SCRIPT LAUNCHER BUTTONS - SHORTCUTS =====================
function Start-Shortcut {
    param([string]$ShortcutName)

    $shortcutPath = Join-Path $AppRoot "Shortcuts\$ShortcutName.lnk"
    if (Test-Path $shortcutPath) {
        Start-Process $shortcutPath -Verb RunAs
    }
    else {
        [System.Windows.MessageBox]::Show(
            "Shortcut '$ShortcutName' not found!",
            "ERROR",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}

# ===================== WARNING POP UP YES & NO =====================
function Show-DarkConfirm {
    param([string]$Message, [string]$Title = "Confirm")
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStartupLocation='CenterScreen'
        ResizeMode='NoResize'
        SizeToContent='WidthAndHeight'
        Background='#1E1E1E'
        WindowStyle='None'
        AllowsTransparency='True'>
    <Border Background='#2D2D30' CornerRadius='12' Padding='20'>
        <StackPanel Width="520">
            <TextBlock Text='$Title' FontSize="24" FontWeight='Bold' Foreground='White' Margin='0,0,0,10' HorizontalAlignment='Center'/>
            <TextBlock Text='$Message' TextWrapping='Wrap' FontSize="16" Foreground='White' Margin='0,0,0,20'/>
            <StackPanel Orientation='Horizontal' HorizontalAlignment='Center'>
                <Button Name='btnYes' Content='Yes' Width='100' Height='35' Margin='5' Foreground='White'>
					<Button.Template>
						<ControlTemplate TargetType='Button'>
							<Border x:Name='border' Background='Green' CornerRadius='3'>
								<ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
							</Border>
							<ControlTemplate.Triggers>
								<Trigger Property='IsMouseOver' Value='True'>
									<Setter TargetName='border' Property='Background' Value='#00CC00'/>
								</Trigger>
								<Trigger Property='IsPressed' Value='True'>
									<Setter TargetName='border' Property='Background' Value='#009900'/>
								</Trigger>
							</ControlTemplate.Triggers>
						</ControlTemplate>
					</Button.Template>
				</Button>
				<Button Name='btnNo' Content='No' Width='100' Height='35' Margin='5' Foreground='White'>
					<Button.Template>
						<ControlTemplate TargetType='Button'>
							<Border x:Name='border' Background='Red' CornerRadius='3'>
								<ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
							</Border>
							<ControlTemplate.Triggers>
								<Trigger Property='IsMouseOver' Value='True'>
									<Setter TargetName='border' Property='Background' Value='#FF3333'/>
								</Trigger>
								<Trigger Property='IsPressed' Value='True'>
									<Setter TargetName='border' Property='Background' Value='#CC0000'/>
								</Trigger>
							</ControlTemplate.Triggers>
						</ControlTemplate>
					</Button.Template>
				</Button>
            </StackPanel>
        </StackPanel>
    </Border>
</Window>
"@
    $reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
    $win = [Windows.Markup.XamlReader]::Load($reader)
    $btnYes = $win.FindName("btnYes")
    $btnNo  = $win.FindName("btnNo")
    $btnYes.Add_Click({ $win.DialogResult = $true })
    $btnNo.Add_Click({ $win.DialogResult = $false })
    $result = $win.ShowDialog()
    return [bool]$result
}

# ===================== EXE EDITOR Start =====================
function Start-SingleInstanceExe {
    param (
        [string]$ExePath,
        [string]$ProcessName,
        [string]$DisplayName
    )
    $running = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($running) {
        Show-DarkWarning `
            -Title "Information" `
            -Message "$DisplayName already open."
        return
    }
    if (Test-Path $ExePath) {
        Start-Process -FilePath $ExePath -WindowStyle Normal
    }
    else {
        Show-DarkWarning `
            -Title "Error" `
            -Message "$DisplayName not found!`nPath=`"$ExePath`""
    }
}

# ===================== UPTIME TIMER =====================
$script:UptimeStartTime = $null
$script:UptimeTimer = $null

function Start-UptimeTimer {
    param ([System.Windows.Window]$Window)
    $txtUptime = $Window.FindName("txtUptime")
    if (-not $txtUptime) { return }  # Safety check
    # Stop existing timer if running
    if ($script:UptimeTimer) { Stop-UptimeTimer }
    $script:UptimeStartTime = Get-Date
    $script:UptimeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:UptimeTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:UptimeTimer.Add_Tick({
        try {
            $elapsed = (Get-Date) - $script:UptimeStartTime
            $days    = $elapsed.Days
            $hours   = $elapsed.Hours
            $minutes = $elapsed.Minutes
            $seconds = $elapsed.Seconds
            if ($days -gt 0) {
                $txtUptime.Text = "{0}d {1:D2}:{2:D2}:{3:D2}" -f $days, $hours, $minutes, $seconds
            }
            elseif ($hours -gt 0) {
                $txtUptime.Text = "{0:D2}:{1:D2}:{2:D2}" -f $hours, $minutes, $seconds
            }
            else {
                $txtUptime.Text = "{0:D2}:{1:D2}" -f $minutes, $seconds
            }
        } catch {
            # Silent fail, можно log ако треба
        }
    })
    $script:UptimeTimer.Start()
}
function Stop-UptimeTimer {
    if ($script:UptimeTimer) {
        $script:UptimeTimer.Stop()
        $script:UptimeTimer = $null
    }
}

# ===================== XAML =====================
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AutoPilot Dashboard" Width="1700" Height="900"
        FontFamily="Segoe UI" WindowStartupLocation="CenterScreen">
    <Window.Background>
    <DrawingBrush Stretch="None" TileMode="None" AlignmentX="Center" AlignmentY="Center" Opacity="0.38">
        <DrawingBrush.Drawing>
            <ImageDrawing Rect="0,0,555,555" ImageSource="$AppRoot\media\autopilot.ico"/>
        </DrawingBrush.Drawing>
    </DrawingBrush>
    </Window.Background>
    <Window.Resources>
        <!-- Modern button style -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="#2D2D30"/>
            <Setter Property="Padding" Value="20"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="FontSize" Value="20"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderBrush" Value="#444"/>
            <Setter Property="BorderThickness" Value="2"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="5"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#3E3E42"/>
                                <Setter Property="Foreground" Value="#4EC9B0"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#565658"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <ScrollViewer VerticalScrollBarVisibility="Auto">
	<StackPanel Margin="15">
    
	<!-- AUTO PILOT HEADER -->
	<Grid Margin="0,0,0,20">
		<Grid.ColumnDefinitions>
			<ColumnDefinition Width="*"/>       <!-- Logo + Title -->
			<ColumnDefinition Width="Auto"/>    <!-- Buttons -->
			<ColumnDefinition Width="Auto"/>    <!-- Panels + Clock -->
		</Grid.ColumnDefinitions>
		<!-- Left: Logo + Dashboard Title -->
		<StackPanel Grid.Column="0" Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
			<Image Source="$AppRoot\media\autopilot.ico" Width="50" Height="50" VerticalAlignment="Center"/>
			<TextBlock Text="AutoPilot" FontSize="25" FontWeight="Bold" Foreground="#F0F0F0" VerticalAlignment="Center" Margin="5,0,0,0"/>
		</StackPanel>
		<!-- Center: Start/Stop/Refresh Buttons -->
		<StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
			<!-- Start Button -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Button x:Name="btnStartAutoPilot" Content="Start ▶️" Style="{StaticResource ModernButton}" Width="100" Height="45" FontSize="16"/>
				<TextBlock Text="Start AutoPilot" FontSize="10" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
			</StackPanel>
			<!-- Stop Button -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Button x:Name="btnStopAutoPilot" Content="Stop ⏹️" Style="{StaticResource ModernButton}" Width="100" Height="45" FontSize="16"/>
				<TextBlock Text="Stop AutoPilot" FontSize="10" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
			</StackPanel>
			<!-- Refresh Button -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Button x:Name="btnRefresh" Content="Refresh 🔄" Style="{StaticResource ModernButton}" Width="100" Height="45" FontSize="16"/>
				<TextBlock Text="Refresh AutoPilot" FontSize="10" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
			</StackPanel>
			<!-- Pause Button -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
                <Button x:Name="btnPauseAutoPilot" Style="{StaticResource ModernButton}" Width="100" Height="45">
                <TextBlock x:Name="txtPauseButton" Text="Pause ⏸️" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Button>
			<!-- STATUS TEXT with COLOR -->
			<TextBlock x:Name="txtPauseStatus" FontSize="10" HorizontalAlignment="Center" Margin="0,2,0,0">
				<Run Text="Status: " Foreground="White"/>
				<Run x:Name="txtPauseState" Text="RUNNING" Foreground="LightGreen"/>
			</TextBlock>
		</StackPanel>
		</StackPanel>
		<!-- Right: Panels + Clock -->
		<StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
			<!-- AutoPilot Panel -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderAutoPilotStatus" CornerRadius="10" Height="45" Width="100" Background="Gray" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtAutoPilotStatus" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="AutoPilot Status" FontSize="10" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
			</StackPanel>
			<!-- System Panel -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderSystemStatus" CornerRadius="10" Height="45" Width="100" Background="Gray" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtSystemStatus" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="System Monitoring" FontSize="10" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
			</StackPanel>
			<!-- Traffic Panel -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderTrafficStatus" CornerRadius="10" Height="45" Width="100" Background="Gray" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtTrafficStatus" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="Traffic Monitoring" FontSize="10" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
			</StackPanel>
			<!-- AutoPilot Bot Panel -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderAutoPilotBot" CornerRadius="10" Height="45" Width="100" Background="Gray" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtAutoPilotBot" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="AutoPilot Bot" FontSize="10" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
			</StackPanel>
			<!-- Media Bot Panel -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderMediaBot" CornerRadius="10" Height="45" Width="100" Background="Gray" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtMediaBot" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="Media Bot" FontSize="10" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
			</StackPanel>
			<!-- Limits Mode Panel -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderMode" CornerRadius="10" Height="45" Width="100" Background="Gray" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtMode" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="AutoPilot Mode" FontSize="10" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
			</StackPanel>
			<!-- Uptime Panel -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderUptime" CornerRadius="10" Height="45" Width="120" Background="#36918C" Padding="5" Margin="0,0,20,0">
					<TextBlock x:Name="txtUptime" Text="Start..." FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="Uptime" FontSize="10" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
			</StackPanel>
			<!-- Clock -->
			<StackPanel x:Name="rightClockContainer" Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Center" Margin="10,0,0,0">
            <StackPanel x:Name="clockElement" Orientation="Horizontal">
                <Image Source="$AppRoot\media\clock.png" Width="28" Height="28" Margin="0,0,6,0"/>
                <TextBlock x:Name="txtClock" FontSize="20" FontWeight="Bold" Foreground="#00FF00"/>
            </StackPanel>
			</StackPanel>
		</StackPanel>
	</Grid>
	
	<!-- LIVE TIMELINE -->
    <Border Background="#AA2D2D30" CornerRadius="15" Padding="10" BorderBrush="#444" BorderThickness="2" Margin="0,0,0,5">
    <StackPanel Orientation="Vertical" VerticalAlignment="Center">
        <!-- TITLE -->
        <TextBlock FontSize="23" FontWeight="SemiBold" Foreground="#4BD6DE" Margin="0,0,0,5">
            Commands Timeline
            <InlineUIContainer BaselineAlignment="Center">
                <Image Source="$AppRoot\media\list.png" Width="25" Height="25" Margin="6,0,0,0"/>
            </InlineUIContainer>
        </TextBlock>
		<!-- Center Clock Placeholder -->
        <StackPanel x:Name="centerClockContainer" Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,15"/>
        <!-- Timeline Grid -->
        <Grid x:Name="headerGrid" Margin="0,0,0,5">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="Auto" />
            </Grid.ColumnDefinitions>
            <!-- LIVE TIMELINE COMMANDS -->
            <StackPanel x:Name="liveTimelineStack" Orientation="Vertical" HorizontalAlignment="Center" Margin="5">
                <!-- PREV -->
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,2">
                    <TextBlock Text="⏮️ Prev  " Foreground="#9E9E9E" FontSize="17" VerticalAlignment="Center"/>
                    <TextBlock x:Name="txtPrev" Foreground="#D6A8ED" FontSize="17" Margin="0,0,10,0" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
                <!-- CURRENT -->
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,2">
                    <TextBlock Text="🔁 Last  " Foreground="#9E9E9E" FontSize="18" VerticalAlignment="Center"/>
                    <TextBlock x:Name="txtCurrent" Foreground="#00FF00" FontSize="18" FontWeight="Bold" Margin="0,0,10,0" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
                <!-- NEXT -->
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,2">
                    <TextBlock Text="⏭ Next  " Foreground="#9E9E9E" FontSize="17" VerticalAlignment="Center"/>
                    <TextBlock x:Name="txtNext" Foreground="#3399FF" FontSize="17" Margin="0,0,10,0" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
            </StackPanel>
            <!-- STATUS MESSAGE -->
            <TextBlock x:Name="txtLiveTimelineMessage" Visibility="Collapsed" Foreground="Gray" FontSize="28" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="27"/>
        </Grid>
       <!-- Bottom Row -->
       <Grid Margin="0,5,0,0" VerticalAlignment="Center">
		<Grid.ColumnDefinitions>
			<ColumnDefinition Width="*" />     <!-- Countdown (left stretch) -->
			<ColumnDefinition Width="Auto" />  <!-- Status Image (center) -->
			<ColumnDefinition Width="*" />     <!-- Spacer to push button right -->
			<ColumnDefinition Width="Auto" />  <!-- Button (right) -->
		</Grid.ColumnDefinitions>
		<!-- COUNTDOWN IMAGE + TEXT -->
		<StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Left">
		<!-- CUSTOM IMAGE -->
		<Image x:Name="imgAutoPilotStatus" Width="25" Height="25" VerticalAlignment="Center" HorizontalAlignment="Center" Margin="0,0,5,0"/>
		<!-- COUNTDOWN TEXT -->
		<TextBlock x:Name="txtCountdown" Foreground="#FFD700" FontSize="17" VerticalAlignment="Center" HorizontalAlignment="Left"/>
		</StackPanel>
		<!-- MODERN TEXT WATERMARK -->
		<TextBlock Grid.Column="1" Text="©️ 𝘼𝙪𝙩𝙤𝙋𝙞𝙡𝙤𝙩 𝘼𝙪𝙩𝙤𝙢𝙖𝙩𝙞𝙤𝙣 𝙎𝙮𝙨𝙩𝙚𝙢" FontSize="30" FontWeight="Bold" Foreground="#33FFFFFF"   VerticalAlignment="Center" HorizontalAlignment="Center" TextAlignment="Center" Opacity="0.3"/>            
		<!-- BUTTON RIGHT -->
		<Button x:Name="btnTimelineList" Grid.Column="2" Content="📜 List All" Style="{StaticResource ModernButton}" VerticalAlignment="Center" HorizontalAlignment="Right"/>
		<Button x:Name="btnAction" Content="❶ Mode" Style="{StaticResource ModernButton}" Grid.Column="3" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0" Padding="10,4">
			<!-- ToolTip Notification -->
			<Button.ToolTip>
				<ToolTip Background="#FF2D2D30"  Foreground="White" Padding="13" Placement="Top" HasDropShadow="True">
					<TextBlock Text="Use Mode 2 or 3 for Smallers Display" TextWrapping="Wrap" FontSize="17"/>
				</ToolTip>
			</Button.ToolTip>
		</Button>
		</Grid>
			</StackPanel>
		</Border>

        <!-- SCRIPT LAUNCHER -->
		<Border Background="#AA2D2D30" CornerRadius="15" Padding="10" BorderBrush="#444" BorderThickness="2" Margin="0,0,0,5">
			<StackPanel>
				<TextBlock FontSize="23" FontWeight="SemiBold" Foreground="#FFD700" Margin="0,0,0,5">
					 Script Launcher
					<InlineUIContainer BaselineAlignment="Center">
						<Image Source="$AppRoot\media\power.png" Width="25" Height="25" Margin="6,0,0,0"/>
					</InlineUIContainer>
				</TextBlock>
				<WrapPanel x:Name="wpDashboard" Orientation="Horizontal" HorizontalAlignment="Center" ItemWidth="180" ItemHeight="70">
					<Button x:Name="btnS1" Content="🛡️ Defender" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnS2" Content="🛠️ Pi" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnS3" Content="⚙️ Docker" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnS4" Content="🧹 Cleaner" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnS5" Content="📶 Network" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnS6" Content="🌐 NetTraffic" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnS7" Content="⚙️ SetDocker" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnS8" Content="⚡ PowerPlan" Style="{StaticResource ModernButton}"/>
				</WrapPanel>
			</StackPanel>
		</Border>

        <!-- SYSTEM COMMANDS -->
        <Border Background="#AA2D2D30" CornerRadius="15" Padding="15" BorderBrush="#444" BorderThickness="2" Margin="0,0,0,15">
            <StackPanel>
                <TextBlock FontSize="23" FontWeight="SemiBold" Foreground="#4EC9B0" Margin="0,0,0,5">
					 System Unit
					<InlineUIContainer BaselineAlignment="Center">
						<Image Source="$AppRoot\media\system.png" Width="25" Height="25" Margin="6,0,0,0"/>
					</InlineUIContainer>
				</TextBlock>
                <WrapPanel>
                    <Button x:Name="btnSys" Content="💻 System Status" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnPing" Content="📶 Network Status" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTemp" Content="🌡️ Temperatures" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnLoad" Content="🖥️ Hardware Info 1" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnStat" Content="🖥️ Hardware Info 2" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnScreen" Content="🔳 Screenshot" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnNetMon" Content="🌏 Net Monitor" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnSysMon" Content="📈 System Monitor" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnTask_add" Content="🏁 Auto Start" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnTask_del" Content="🗑️ Stop Auto Start" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnTask_show" Content="📑 Status" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnMedia" Content="🗂️ Media" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnCamera" Content="🎥 Camera" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnData" Content="📂 Data Folder" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnScripts_Editor" Content="✏️ Scripts Edit" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnCommands_Editor" Content="✏️ Commands Edit" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnSettings" Content="⚙️ AutoPilot Settings" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnSettingsScripts" Content="⚙️ Scripts Settings" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnHideCmd" Content="⛔ Hide Cmd" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnShowCmd" Content="🗔 Show Cmd" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnLock" Content="🔒 Lock Dashboard" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnOpenFolder" Content="🖱️ SetUp" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnAbout" Content="ℹ️ AboutUs" Style="{StaticResource ModernButton}"/>
                </WrapPanel>
            </StackPanel>
        </Border>

        <!-- GRAPH LOAD COMMANDS -->
        <Border Background="#AA2D2D30" CornerRadius="15" Padding="15" BorderBrush="#444" BorderThickness="2" Margin="0,0,0,15">
            <StackPanel>
                <TextBlock FontSize="23" FontWeight="SemiBold" Foreground="#FFD700" Margin="0,0,0,5">
			         Graph Load Unit
					<InlineUIContainer BaselineAlignment="Center">
						<Image Source="$AppRoot\media\graph.png" Width="25" Height="25" Margin="6,0,0,0"/>
					</InlineUIContainer>
				</TextBlock>
                <WrapPanel>
                    <Button x:Name="btnLoadDay" Content="📉 Load Day" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnLoadWeek" Content="📉 Load Week" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnLoadMonth" Content="📉 Load Month" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnLoadYear" Content="📉 Load Year" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnLoadAll" Content="📉 Load All" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnLoadArchive" Content="📂️ Load Archive" Style="{StaticResource ModernButton}"/>
                </WrapPanel>
            </StackPanel>
        </Border>

        <!-- GRAPH TEMP COMMANDS -->
        <Border Background="#AA2D2D30" CornerRadius="15" Padding="15" BorderBrush="#444" BorderThickness="2" Margin="0,0,0,15">
            <StackPanel>
                <TextBlock FontSize="23" FontWeight="SemiBold" Foreground="#FF6F61" Margin="0,0,0,5">
					 Graph Temperature Unit
					<InlineUIContainer BaselineAlignment="Center">
						<Image Source="$AppRoot\media\graph.png" Width="25" Height="25" Margin="6,0,0,0"/>
					</InlineUIContainer>
				</TextBlock>
                <WrapPanel>
                    <Button x:Name="btnTempDay" Content="🌡️ Temp Day" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTempWeek" Content="🌡️ Temp Week" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTempMonth" Content="🌡️ Temp Month" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTempYear" Content="🌡️ Temp Year" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTempAll" Content="🌡️ Temp All" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnTempArchive" Content="📂 Temp Archive" Style="{StaticResource ModernButton}"/>
                </WrapPanel>
            </StackPanel>
        </Border>

        <!-- GRAPH DISK COMMANDS -->
       <Border Background="#AA2D2D30" CornerRadius="15" Padding="15" BorderBrush="#444" BorderThickness="2" Margin="0,0,0,15">
            <StackPanel>
                <TextBlock FontSize="23" FontWeight="SemiBold" Foreground="#4FC1FF" Margin="0,0,0,5">
					 Graph Disk Unit
					<InlineUIContainer BaselineAlignment="Center">
						<Image Source="$AppRoot\media\graph.png" Width="25" Height="25" Margin="6,0,0,0"/>
					</InlineUIContainer>
				</TextBlock>
                <WrapPanel>
                    <Button x:Name="btnDiskDay" Content="💾 Disk Day" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnDiskWeek" Content="💾 Disk Week" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnDiskMonth" Content="💾 Disk Month" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnDiskYear" Content="💾 Disk Year" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnDiskAll" Content="💾 Disk All" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnDiskArchive" Content="📂 Disk Archive" Style="{StaticResource ModernButton}"/>
                </WrapPanel>
            </StackPanel>
        </Border>

        <!-- TABLE NET TRAFFIC COMMANDS -->
        <Border Background="#AA2D2D30" CornerRadius="15" Padding="15" BorderBrush="#444" BorderThickness="2" Margin="0,0,0,15">
            <StackPanel>
               <TextBlock FontSize="23" FontWeight="SemiBold" Foreground="#6A5ACD" Margin="0,0,0,5">
					 Net Traffic Unit
					<InlineUIContainer BaselineAlignment="Center">
						<Image Source="$AppRoot\media\net.png" Width="25" Height="25" Margin="6,0,0,0"/>
					</InlineUIContainer>
				</TextBlock>
                <WrapPanel>
                    <Button x:Name="btnTableDay" Content="📆 Table Day" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTableWeek" Content="📆 Table Week" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTableMonth" Content="📆 Table Month" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTableYear" Content="📆 Table Year" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTableAll" Content="📆 Table All" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnTableArchive" Content="📂 Table Archive" Style="{StaticResource ModernButton}"/>
                </WrapPanel>
            </StackPanel>
        </Border>
		
		<!-- LOG FILE COMMANDS -->
        <Border Background="#AA2D2D30" CornerRadius="15" Padding="15" BorderBrush="#444" BorderThickness="2" Margin="0,0,0,15">
            <StackPanel>
               <TextBlock FontSize="23" FontWeight="SemiBold" Foreground="#3DFFB2" Margin="0,0,0,5">
					 Log File Unit
					<InlineUIContainer BaselineAlignment="Center">
						<Image Source="$AppRoot\media\log.png" Width="25" Height="25" Margin="6,0,0,0"/>
					</InlineUIContainer>
				</TextBlock>
                <WrapPanel>
                    <Button x:Name="btnAutoPilot_Log" Content="🗃️ AutoPilot Log" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnMonitoring_Log" Content="🗃️ System Monitorin Log" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTraffic_Log" Content="🗃️ Traffic Monitoring Log" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnData_Log" Content="🗃️ Data Log" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnNetwork_Log" Content="🗃️ Net Log" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnUpdate_Log" Content="🗃️ Update Log" Style="{StaticResource ModernButton}"/>
                </WrapPanel>
            </StackPanel>
        </Border>
		
		<!-- MONITORING COMMANDS -->
        <Border Background="#AA2D2D30" CornerRadius="15" Padding="15" BorderBrush="#444" BorderThickness="2" Margin="0,0,0,15">
            <StackPanel>
               <TextBlock FontSize="23" FontWeight="SemiBold" Foreground="#E8511A" Margin="0,0,0,5">
					 Monitoring Unit
					<InlineUIContainer BaselineAlignment="Center">
						<Image Source="$AppRoot\media\monitoring.png" Width="25" Height="25" Margin="6,0,0,0"/>
					</InlineUIContainer>
				</TextBlock>
                <WrapPanel>
                    <Button x:Name="btnSysMon_Start" Content="💻 System Monitoring Start" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnSysMon_Stop" Content="💻 System Monitoring Stop" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnSysMon_Status" Content="💻 System Monitoring Status" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnTrafficMonitoring" Content="🌏 Traffic Monitoring" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnStopWorkers" Content="⏹️ STOP All" Style="{StaticResource ModernButton}"/>
                </WrapPanel>
            </StackPanel>
        </Border>
		<!-- WATERMARK -->
		<Border Margin="0,0,0,0" Background="Transparent">
        <Grid VerticalAlignment="Center">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <!-- CENTER (logo + text) -->
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Center"  Grid.Column="1">
            <Image Source="$AppRoot\media\autopilot.ico" Width="28" Height="28" Margin="0,0,6,0"/>
            <TextBlock Text=" AutoPilot Automation System by Ivance" FontSize="15" FontWeight="Bold" VerticalAlignment="Center" Opacity="0.8" Foreground="#F0F0F0"/>
        </StackPanel>
        <!-- RIGHT BUTTON -->
		<TextBlock Text=" © All Rights Reserved" FontSize="15" FontWeight="Bold" Grid.Column="2" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0" Opacity="0.8" Foreground="#F0F0F0"/>
       </Grid>
      </Border>
    </StackPanel>
   </ScrollViewer>
</Window>
"@

# ===================== LOAD =====================
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
try {
    $window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Error "XAML Load failed: $_"
    return
}

# Hook Closed event
$window.Add_Closed({ Remove-DashboardFlag })

# ===================== TIME AND DATE =====================
$txtClock = $window.FindName("txtClock")
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    # Se koristi tekoven datum + vreme
    $txtClock.Text = (Get-Date).ToString("dddd, dd.MM.yyyy HH:mm:ss")
})
$timer.Start()
# Кога прозорецот ќе се вчита
$window.Add_Loaded({
    Start-UptimeTimer -Window $window
})
# Кога прозорецот се затвора
$window.Add_Closing({
    Stop-UptimeTimer
})

# ===================== BUTTON OPEN =====================
$btnOpenFolder = $window.FindName("btnOpenFolder")
$btnOpenFolder.Add_Click({
    $folder = "$AppRoot\media\SetUp.pdf"
    if (Test-Path $folder) {
        Get-ChildItem -Path $folder -Filter *.txt | ForEach-Object { ii $_.FullName }
    } else {
        Show-DarkWarning -Title "SetUP" -Message "The folder does not exist: $folder"
    }
})

# ===================== BUTTON REFRESH =====================
$btnRefresh = $window.FindName("btnRefresh")
$btnRefresh.Add_Click({
    $msg = @"
Warning: With a *REFRESH* of AutoPilot, all processes will be STOPPED and Restarted!
Are you SURE you want to REFRESH the System?
"@
    $title = "Refresh AutoPilot and Monitoring!"
    $userChoice = Show-DarkConfirm -Message $msg -Title $title
    if ($userChoice) {
        Invoke-ManualCommand "/refresh"
    } else {
        Show-DarkWarning -Title "Refresh AutoPilot" -Message "AutoPilot refresh has been canceled by the user."
    }
})

# ===================== Control ==================================
$txtAutoPilotStatus    = $window.FindName("txtAutoPilotStatus")
$borderAutoPilotStatus = $window.FindName("borderAutoPilotStatus")
$btnStartAutoPilot     = $window.FindName("btnStartAutoPilot")
$btnStopAutoPilot      = $window.FindName("btnStopAutoPilot")
$txtSystemStatus       = $window.FindName("txtSystemStatus")
$borderSystemStatus    = $window.FindName("borderSystemStatus")
$txtTrafficStatus      = $window.FindName("txtTrafficStatus")
$borderTrafficStatus   = $window.FindName("borderTrafficStatus")
$txtUptime             = $window.FindName("txtUptime") 
$btnPauseAutoPilot     = $window.FindName("btnPauseAutoPilot")
$txtPauseButton        = $window.FindName("txtPauseButton")
$txtPauseStatus        = $window.FindName("txtPauseStatus")
$btnScripts_Editor     = $window.FindName("btnScripts_Editor")
$btnCommands_Editor    = $window.FindName("btnCommands_Editor")
# ===================== Control - New Bot Panels =================
$txtAutoPilotBot       = $window.FindName("txtAutoPilotBot")
$borderAutoPilotBot    = $window.FindName("borderAutoPilotBot")
$txtMediaBot           = $window.FindName("txtMediaBot")
$borderMediaBot        = $window.FindName("borderMediaBot")
# ===================== Control - Mode Panel =====================
$txtMode               = $window.FindName("txtMode")
$borderMode            = $window.FindName("borderMode")
# ===================== Timeline Display =====================
$txtPrev   = $window.FindName("txtPrev")
$txtCurrent  = $window.FindName("txtCurrent")
$txtNext   = $window.FindName("txtNext")
$txtCountdown = $window.FindName("txtCountdown")
$imgStatus = $window.FindName("imgAutoPilotStatus")
# ===================== Mode Batton =====================
$btnAction = $window.FindName("btnAction")
$headerGrid = $window.FindName("headerGrid")
$clockElement = $window.FindName("clockElement")
$rightClockContainer = $window.FindName("rightClockContainer")
$centerClockContainer = $window.FindName("centerClockContainer")
$borderUptime = $Window.FindName("borderUptime")
$wpDashboard = $window.FindName("wpDashboard")

# Проверка на сите TextBlock-и
if(-not ($txtPrev -and $txtCurrent -and $txtNext -and $txtCountdown)) {
    Write-Host "ERROR: Some Timeline TextBlocks not found!"
    return
}

# ===================== Function Update UI - AutoPilot =====================
function Update-AutoPilotStatusUI {
    $autoPilotRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\AutoPilot.ps1")
    }
    if ($autoPilotRunning) {
        $txtAutoPilotStatus.Text = "ACTIVE"
        $borderAutoPilotStatus.Background = [System.Windows.Media.Brushes]::Green
    } else {
        $txtAutoPilotStatus.Text = "STOPPED"
        $borderAutoPilotStatus.Background = [System.Windows.Media.Brushes]::Red
    }
}

# ===================== Button Start =====================
$btnStartAutoPilot.Add_Click({
    $editorRunning = Get-Process -Name "ScriptsEditor","CommandsEditor" -ErrorAction SilentlyContinue
    if ($editorRunning) {
        Show-DarkWarning -Title "Editor Active!" -Message "To start AutoPilot, the EDIT block must be Closed first (Commands, Scripts)!"
        return
    }
    Invoke-ManualCommand "/start-autopilot"
    Update-AutoPilotStatusUI
})

# ===================== Button Stop =====================
$btnStopAutoPilot.Add_Click({
    $msg = "Warning: *AutoPilot* At the moment it may be RUNNING! Are you SURE you want to STOP the AutoPilot process?"
    $title = "Stopping AutoPilot!"
    $userChoice = Show-DarkConfirm -Message $msg -Title $title
    if ($userChoice) {
        Invoke-ManualCommand "/stop-autopilot"
        Update-AutoPilotStatusUI
    } else {
        Show-DarkWarning -Title "AutoPilot STOP" -Message "Stopping AutoPilot has been canceled by the user."
    }
})

# ===================== Function Status - System =====================
function Get-SystemStatus {
    $systemRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\SystemMonitorWorker.ps1")
    }
    if ($systemRunning) { return "ACTIVE" } else { return "STOPPED" }
}

# ===================== Function Status - Traffic =====================
function Get-TrafficStatus {
    $trafficRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\TrafficMonitorWorker.ps1")
    }
    if ($trafficRunning) { return "ACTIVE" } else { return "STOPPED" }
}

# ===================== Function Update UI - System =====================
function Update-SystemStatusUI {
    $systemRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\SystemMonitorWorker.ps1")
    }
    if ($systemRunning) {
        $txtSystemStatus.Text = "ACTIVE"
        $borderSystemStatus.Background = [System.Windows.Media.Brushes]::Green
    } else {
        $txtSystemStatus.Text = "STOPPED"
        $borderSystemStatus.Background = [System.Windows.Media.Brushes]::Red
    }
}

# ===================== Function Update UI - Traffic =====================
function Update-TrafficStatusUI {
    $trafficRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\TrafficMonitorWorker.ps1")
    }
    if ($trafficRunning) {
        $txtTrafficStatus.Text = "ACTIVE"
        $borderTrafficStatus.Background = [System.Windows.Media.Brushes]::Green
    } else {
        $txtTrafficStatus.Text = "STOPPED"
        $borderTrafficStatus.Background = [System.Windows.Media.Brushes]::Red
    }
}

# ===================== *AutoPilot Pause - STOP =====================
function Get-AutoPilotRunning {
    $autoPilotRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\AutoPilot.ps1")
    }
    return $autoPilotRunning -ne $null
}

# ===================== *AutoPilot Pause - BUTTON =====================
$btnPauseAutoPilot.Add_Click({
    if (-not (Get-AutoPilotRunning)) {
        $txtPauseState.Text = "STOPPED"
        $txtPauseButton.Text = "Pause ⏸️"
        $btnPauseAutoPilot.Background = [System.Windows.Media.Brushes]::Gray
        return
    }
    if (Test-Path $Global:pauseFlagPath) {
        Resume-AutopilotGUI
    } else {
        Show-DarkWarning -Title "Warning!" `
                         -Message "Using *PAUSE* will stop all AUTOMATIC processes in AutoPilot!"
        Pause-AutopilotGUI
    }
    Update-PauseUI
})

# ===================== *AutoPilot Pause - FUNCTION =====================
function Pause-AutopilotGUI {
    New-Item -Path $Global:pauseFlagPath -ItemType File -Force | Out-Null
}

# ===================== *AutoPilot Resume - FUNCTION =====================
function Resume-AutopilotGUI {
    if (Test-Path $Global:pauseFlagPath) {
        Remove-Item -Path $Global:pauseFlagPath -Force
    }
    Invoke-ManualCommand "/refresh" # Plus in the code
}

$txtPauseState = $window.FindName("txtPauseState")

# ===================== *AutoPilot Pause - UI =====================
function Update-PauseUI {
    if (-not (Get-AutoPilotRunning)) {
        $txtPauseState.Text = "STOPPED"
		$txtPauseState.Foreground = [System.Windows.Media.Brushes]::Red 
        $txtPauseButton.Text = "Pause ⏸️"
        $btnPauseAutoPilot.Background = [System.Windows.Media.Brushes]::Gray
        return
    }
    if (Test-Path $Global:pauseFlagPath) {
        # PAUSED
        $txtPauseButton.Text = "Resume ⏯️"
        $btnPauseAutoPilot.Background = [System.Windows.Media.Brushes]::Goldenrod
        $txtPauseState.Text = "PAUSED"
        $txtPauseState.Foreground = [System.Windows.Media.Brushes]::Goldenrod
    } else {
        # RUNNING
        $txtPauseButton.Text = "Pause ⏸️"
        $btnPauseAutoPilot.Background = [System.Windows.Media.Brushes]::Green
        $txtPauseState.Text = "RUNNING"
        $txtPauseState.Foreground = [System.Windows.Media.Brushes]::LightGreen
    }
}

# ===================== AutoPilot SCRIPTS EDITOR =====================
$btnScripts_Editor.Add_Click({
    $exeName = "ScriptsEditor.exe"
    $processName = "ScriptsEditor"   
    $autoPilotRunning = Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -like "*AutoPilot.ps1*" }
    if ($autoPilotRunning) {
        Show-DarkWarning -Title "AutoPilot is Active!" -Message "AutoPilot is currently Running! The Scripts Editor works only when AutoPilot is STOPPED."
        return
    }
    $editorPath = if ($AppRoot) {
        Join-Path $AppRoot $exeName
    } else {
        Join-Path (Get-Location) $exeName
    }
    Start-SingleInstanceExe `
        -ExePath $editorPath `
        -ProcessName $processName `
        -DisplayName "Scripts Editor"
})

# ===================== AutoPilot COMMANDS EDITOR =====================
$btnCommands_Editor.Add_Click({
    $exeName = "CommandsEditor.exe"
    $processName = "CommandsEditor"
    $autoPilotRunning = Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -like "*AutoPilot.ps1*" }
    if ($autoPilotRunning) {
        Show-DarkWarning -Title "AutoPilot is Active!" -Message "AutoPilot is currently Running! The Commands Editor works only when AutoPilot is STOPPED."
        return
    }
    $editorPath = if ($AppRoot) {
        Join-Path $AppRoot $exeName
    } else {
        Join-Path (Get-Location) $exeName
    }
    Start-SingleInstanceExe `
        -ExePath $editorPath `
        -ProcessName $processName `
        -DisplayName "Commands Editor"
})

# ===================== AutoPilot Media Bot ENABLED / DISABLED =====================
function Update-BotStatusUI {
    try {
        $jsonPath = "$AppRoot\JSON\settings.json"
        if (-not (Test-Path $jsonPath)) { return }
        $settings = Get-Content $jsonPath | ConvertFrom-Json
        # --- AutoPilot Bot ---
        if ($settings.AUTOPILOT_TELEGRAM_ENABLED) {
            $txtAutoPilotBot.Text = "ENABLED"
            $borderAutoPilotBot.Background = [System.Windows.Media.Brushes]::Green
        } else {
            $txtAutoPilotBot.Text = "DISABLED"
            $borderAutoPilotBot.Background = [System.Windows.Media.Brushes]::Red
        }
        # --- Media Bot ---
        if ($settings.MEDIA_TELEGRAM_ENABLED) {
            $txtMediaBot.Text = "ENABLED"
            $borderMediaBot.Background = [System.Windows.Media.Brushes]::Green
        } else {
            $txtMediaBot.Text = "DISABLED"
            $borderMediaBot.Background = [System.Windows.Media.Brushes]::Red
        }
    } catch {
        Write-Host "Error updating Bot statuses: $_"
    }
}

# ===================== Mode (TEST / PRO) =====================
function Update-ModeUI {
    try {
        $jsonPath = "$AppRoot\JSON\settings.json"
        if (-not (Test-Path $jsonPath)) { return }
        $settings = Get-Content $jsonPath | ConvertFrom-Json
        $enableRestart  = [bool]$settings.ENABLE_RESTART
        $enableShutdown = [bool]$settings.ENABLE_SHUTDOWN
        if (-not $enableRestart -and -not $enableShutdown) {
            # ===== TEST MODE =====
            $txtMode.Text = "TEST MODE"
            $borderMode.Background = [System.Windows.Media.Brushes]::DarkGreen
        } else {
            # ===== PRO MODE =====
            $txtMode.Text = "PRO MODE"
            $borderMode.Background = [System.Windows.Media.Brushes]::Blue
        }
    }
    catch {
        $txtMode.Text = "ERROR"
        $borderMode.Background = [System.Windows.Media.Brushes]::Red
    }
}

# ===================== BUTTON ABOUT =====================
$btnAbout = $window.FindName("btnAbout")
$btnAbout.Add_Click({

    # Функција за About popup
    function Show-AboutPopupWPF {
        $versionFile = "$AppRoot\version.txt"
        $version = "Unknown"
        $installDate = "Unknown"

        if (Test-Path $versionFile) {
            $version = (Get-Content $versionFile).Trim()
            $installDate = (Get-Item $versionFile).LastWriteTime.ToString("dd MMM yyyy HH:mm:ss")
        }

        # WPF Window за About
        $aboutWindow = New-Object System.Windows.Window
        $aboutWindow.Title = "AutoPilot Automation System"
        $aboutWindow.Width = 450
        $aboutWindow.Height = 450
        $aboutWindow.WindowStartupLocation = "CenterScreen"
        $aboutWindow.ResizeMode = "NoResize"
        # Background со RGB (30,30,30)
		$color = [System.Windows.Media.Color]::FromRgb(30,30,30)
		$aboutWindow.Background = New-Object System.Windows.Media.SolidColorBrush $color

        # StackPanel за содржина
        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Margin = [System.Windows.Thickness]::new(20)
        $stack.VerticalAlignment = "Top"

        # Title
        $lblTitle = New-Object System.Windows.Controls.TextBlock
        $lblTitle.Text = "AutoPilot Automation System"
        $lblTitle.FontSize = 22
        $lblTitle.FontWeight = "Bold"
        $lblTitle.Foreground = [System.Windows.Media.Brushes]::White
        $lblTitle.Margin = [System.Windows.Thickness]::new(0,0,0,10)
        $stack.Children.Add($lblTitle)

        # Version
		$lblVersion = New-Object System.Windows.Controls.TextBlock
		$lblVersion.FontSize = 17
		$lblVersion.Foreground = [System.Windows.Media.Brushes]::White
		$lblVersion.Margin = [System.Windows.Thickness]::new(0,0,0,5)
		# Bold Label
		$runLabel = New-Object System.Windows.Documents.Run("Version: ")
		$runLabel.FontWeight = "Bold"
		$lblVersion.Inlines.Add($runLabel)
		# Value
		$runValue = New-Object System.Windows.Documents.Run($version)
		$lblVersion.Inlines.Add($runValue)
		$stack.Children.Add($lblVersion)

		# Install date
		$lblDate = New-Object System.Windows.Controls.TextBlock
		$lblDate.FontSize = 17
		$lblDate.Foreground = [System.Windows.Media.Brushes]::White
		$lblDate.Margin = [System.Windows.Thickness]::new(0,0,0,5)
		$runLabel = New-Object System.Windows.Documents.Run("Realized: ")
		$runLabel.FontWeight = "Bold"
		$lblDate.Inlines.Add($runLabel)
		$runValue = New-Object System.Windows.Documents.Run($installDate)
		$lblDate.Inlines.Add($runValue)
		$stack.Children.Add($lblDate)

		# Author
		$lblAuthor = New-Object System.Windows.Controls.TextBlock
		$lblAuthor.FontSize = 17
		$lblAuthor.Foreground = [System.Windows.Media.Brushes]::White
		$lblAuthor.Margin = [System.Windows.Thickness]::new(0,0,0,15)
		$runLabel = New-Object System.Windows.Documents.Run("Author: ")
		$runLabel.FontWeight = "Bold"
		$lblAuthor.Inlines.Add($runLabel)
		$runValue = New-Object System.Windows.Documents.Run("Ivan Gjorcev")
		$lblAuthor.Inlines.Add($runValue)
		$stack.Children.Add($lblAuthor)

		# GitHub TextBlock со Bold за "GitHub:" и нормален линк текст
		$lblGitHub = New-Object System.Windows.Controls.TextBlock
		$lblGitHub.FontSize = 17
		$lblGitHub.Margin = [System.Windows.Thickness]::new(0,0,0,10)
		$lblGitHub.Foreground = [System.Windows.Media.Brushes]::White

		# Bold Label
		$runLabel = New-Object System.Windows.Documents.Run("GitHub Profile: ")
		$runLabel.FontWeight = "Bold"
		$lblGitHub.Inlines.Add($runLabel)

		# Value
		$runValue = New-Object System.Windows.Documents.Run("github.com/callibra")
		$lblGitHub.Inlines.Add($runValue)

		$stack.Children.Add($lblGitHub)

		# Check Update button (модерен стил, без CornerRadius)
		$btnCheck = New-Object System.Windows.Controls.Button
		$btnCheck.Content = "🔄 Check Update"
		$btnCheck.HorizontalAlignment = "Center"
		$btnCheck.Margin = [System.Windows.Thickness]::new(0,20,0,0)

		# Примени го ModernButton стилот
		$btnCheck.Style = $window.FindResource("ModernButton")

# Додади ја оригиналната логика за Click
$btnCheck.Add_Click({
    $declinedFile = "$AppRoot\last_update_declined.txt"

    if (Test-Path $declinedFile) {
        try {
            Remove-Item $declinedFile -Force
        } catch {
            try { 
                $request = [System.Net.WebRequest]::Create("http://www.google.com")
                $request.Timeout = 3000
                $response = $request.GetResponse()
                $response.Close()
                [System.Windows.MessageBox]::Show("Error deleting " + $declinedFile + ": " + $_)
            } catch { }
        }
    }

    $updaterProcess = Get-Process -Name "Updater" -ErrorAction SilentlyContinue
    if ($updaterProcess) { return }

    $updaterPath = "$AppRoot\Updater.exe"
    if (Test-Path $updaterPath) {
        try {
            $proc = Start-Process $updaterPath -PassThru
            Start-Sleep -Seconds 5
            try {
                $request = [System.Net.WebRequest]::Create("http://www.google.com")
                $request.Timeout = 3000
                $response = $request.GetResponse()
                $response.Close()
                if ($proc.HasExited) {
                    Show-DarkWarning -Title "🔄 AutoPilot Update System" -Message "No new update."
                }
            } catch { }
        } catch {
            try {
                $request = [System.Net.WebRequest]::Create("http://www.google.com")
                $request.Timeout = 3000
                $response = $request.GetResponse()
                $response.Close()
                Show-DarkWarning -Title "🔄 AutoPilot Update System" -Message ("Error launching updater: " + $_)
            } catch { }
        }
		} else {
			try {
				$request = [System.Net.WebRequest]::Create("http://www.google.com")
				$request.Timeout = 3000
				$response = $request.GetResponse()
				$response.Close()
				Show-DarkWarning -Title "🔄 AutoPilot Update System" -Message "Updater.exe not found."
			} catch { }
		}
	})

	# Додади го логото и текстот на дното
	$stackBottom = New-Object System.Windows.Controls.StackPanel
	$stackBottom.HorizontalAlignment = "Center"
	$stackBottom.VerticalAlignment = "Bottom"
	$stackBottom.Margin = [System.Windows.Thickness]::new(0,20,0,0)

	# Слика (лого)
	$imgLogo = New-Object System.Windows.Controls.Image
	$imgLogo.Width = 88
	$imgLogo.Height = 88
	$imgLogo.Margin = [System.Windows.Thickness]::new(0,0,0,10)
	# Патека до твојот PNG (пример: $AppRoot\logo.png)
	$imgLogo.Source = [System.Windows.Media.Imaging.BitmapImage]::new((New-Object System.Uri("$AppRoot\media\autopilot.ico")))

	$stackBottom.Children.Add($imgLogo)

	# Текст под логото
	$lblFooter = New-Object System.Windows.Controls.TextBlock
	$lblFooter.FontSize = 16
	$lblFooter.Foreground = [System.Windows.Media.Brushes]::White
	$lblFooter.HorizontalAlignment = "Center"

	# Автоматски ја добива тековната година
	$currentYear = (Get-Date).Year
	$lblFooter.Text = "AutoPilot Automation System © $currentYear"

	$stackBottom.Children.Add($lblFooter)

	# Додади го Check Update копчето
	$stack.Children.Add($btnCheck)

	# Додади го StackPanel-от со лого и текст на дното
	$stack.Children.Add($stackBottom)

        $aboutWindow.Content = $stack
        $aboutWindow.ShowDialog()
    }
    Show-AboutPopupWPF
})

$btnLock = $window.FindName("btnLock")
$btnLock.Add_Click({

    function Show-LockPopup {
        $lockWindow = New-Object System.Windows.Window
        $lockWindow.Title = "AutoPilot Dashboard Password Protect"
        $lockWindow.Width = 500
        $lockWindow.Height = 530
        $lockWindow.WindowStartupLocation = "CenterScreen"
        $lockWindow.ResizeMode = "NoResize"
        $lockWindow.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(30,30,30))

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Margin = [System.Windows.Thickness]::new(20)
        $stack.VerticalAlignment = "Top"

        # Заглавие
        $lblTitle = New-Object System.Windows.Controls.TextBlock
        $lblTitle.Text = "AutoPilot Dashboard Password Protect"
        $lblTitle.FontSize = 22
        $lblTitle.FontWeight = "Bold"
        $lblTitle.Foreground = [System.Windows.Media.Brushes]::White
        $lblTitle.Margin = [System.Windows.Thickness]::new(0,0,0,30)
        $stack.Children.Add($lblTitle)

        # StackPanel за ред со лозинка и Show/Hide
        $pwdRow = New-Object System.Windows.Controls.StackPanel
        $pwdRow.Orientation = "Horizontal"
        $pwdRow.HorizontalAlignment = "Left"
        $pwdRow.Margin = [System.Windows.Thickness]::new(0,0,0,30)  # повеќе вертикално растојание

        # PasswordBox (скриена лозинка)
        $pwdBox = New-Object System.Windows.Controls.PasswordBox
        $pwdBox.Width = 250
        $pwdBox.FontSize = 18
        $pwdBox.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(50,50,50))
        $pwdBox.Foreground = [System.Windows.Media.Brushes]::White
        $pwdBox.Margin = [System.Windows.Thickness]::new(0,0,10,0)
        $pwdRow.Children.Add($pwdBox)

        # TextBox (прикажана лозинка)
        $txtBox = New-Object System.Windows.Controls.TextBox
        $txtBox.Width = 250
        $txtBox.FontSize = 18
        $txtBox.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(50,50,50))
        $txtBox.Foreground = [System.Windows.Media.Brushes]::White
        $txtBox.Margin = [System.Windows.Thickness]::new(0,0,10,0)
        $txtBox.Visibility = "Collapsed"
        $pwdRow.Children.Add($txtBox)

        # Show/Hide Label
        $lblShow = New-Object System.Windows.Controls.TextBlock
        $lblShow.Text = " 🔑 Show Password"
        $lblShow.FontSize = 17
        $lblShow.FontWeight = "Bold"
        $lblShow.Foreground = [System.Windows.Media.Brushes]::White
        $lblShow.Cursor = "Hand"
        $lblShow.VerticalAlignment = "Center"
        $pwdRow.Children.Add($lblShow)

        # Show/Hide функционалност
        $lblShow.Add_MouseLeftButtonUp({
            if ($pwdBox.Visibility -eq "Visible") {
                $txtBox.Text = $pwdBox.Password
                $pwdBox.Visibility = "Collapsed"
                $txtBox.Visibility = "Visible"
                $lblShow.Text = " 🔑 Hide Password"
            } else {
                $pwdBox.Password = $txtBox.Text
                $pwdBox.Visibility = "Visible"
                $txtBox.Visibility = "Collapsed"
                $lblShow.Text = " 🔑 Show Password"
            }
        })

        $stack.Children.Add($pwdRow)

        # ON/OFF Lock Button
        $btnToggle = New-Object System.Windows.Controls.Button
        $btnToggle.Width = 150
        $btnToggle.HorizontalAlignment = "Center"
        $btnToggle.Style = $window.FindResource("ModernButton")
        $btnToggle.Margin = [System.Windows.Thickness]::new(0,10,0,30)  # повеќе вертикално растојание

        $PasswordData = if (Test-Path $PasswordFile) { Get-Content $PasswordFile | ConvertFrom-Json } else { @{ Enabled = $false } }
        $btnToggle.Content = if ($PasswordData.Enabled) { "🔒 ON Lock" } else { "🔓 OFF Lock" }

        $stack.Children.Add($btnToggle)

        # Toggle логика + прикажување статус на старт
        $lblStatus = New-Object System.Windows.Controls.TextBlock
        $lblStatus.FontSize = 18
        $lblStatus.FontWeight = "Bold"
        $lblStatus.Foreground = [System.Windows.Media.Brushes]::White
        $lblStatus.HorizontalAlignment = "Center"
        $stack.Children.Add($lblStatus)

        # Прикажи стартен статус
        if ($PasswordData.Enabled) { $lblStatus.Text = "AutoPilot Dashboard Lock 🔒" } else { $lblStatus.Text = "AutoPilot Dashboard Unlock 🔓" }

        $btnToggle.Add_Click({
            $enteredPwd = if ($pwdBox.Visibility -eq "Visible") { $pwdBox.Password } else { $txtBox.Text }
            if (-not $PasswordData.Enabled) {
                if ([string]::IsNullOrEmpty($enteredPwd)) {
                    Show-DarkWarning -Title "🔒 Password ON" -Message "Enter the Password to enable ON Protect!"
                    return
                }
                Save-Password -PlainText $enteredPwd -Enabled $true
                $PasswordData.Enabled = $true
                $btnToggle.Content = "🔒 ON Lock"
                $lblStatus.Text = "AutoPilot Dashboard now is Lock 🔒"
            } else {
                if ($enteredPwd -ne (Load-Password)) {
                    Show-DarkWarning -Title "🔓 Passowrd OFF" -Message "Enter the Correct Password to disable ON Protect!"
                    return
                }
                Save-Password -PlainText $enteredPwd -Enabled $false
                $PasswordData.Enabled = $false
                $btnToggle.Content = "🔓 OFF Lock"
                $lblStatus.Text = "AutoPilot Dashboard now is Unlock 🔓"
            }
        })

        # Лого и текст на дното
        $stackBottom = New-Object System.Windows.Controls.StackPanel
        $stackBottom.HorizontalAlignment = "Center"
        $stackBottom.VerticalAlignment = "Bottom"
        $stackBottom.Margin = [System.Windows.Thickness]::new(0,20,0,0)

        $imgLogo = New-Object System.Windows.Controls.Image
        $imgLogo.Width = 88
        $imgLogo.Height = 88
        $imgLogo.Margin = [System.Windows.Thickness]::new(0,0,0,30)
        $imgLogo.Source = [System.Windows.Media.Imaging.BitmapImage]::new((New-Object System.Uri("$AppRoot\media\autopilot.ico")))
        $stackBottom.Children.Add($imgLogo)

        $lblFooter = New-Object System.Windows.Controls.TextBlock
        $lblFooter.FontSize = 16
        $lblFooter.Foreground = [System.Windows.Media.Brushes]::White
        $lblFooter.HorizontalAlignment = "Center"
        $lblFooter.Text = "AutoPilot Dashboard Password Protect "
        $stackBottom.Children.Add($lblFooter)
		
		# --- Додавање на две нови линии текст пред постоечкиот lblFooter ---
		$lblDescription1 = New-Object System.Windows.Controls.TextBlock
		$lblDescription1.FontSize = 13
		$lblDescription1.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(144,238,144)) # светло зелена
		$lblDescription1.HorizontalAlignment = "Left"
		$lblDescription1.Margin = [System.Windows.Thickness]::new(0,20,0,5)  # горе и долу маргина
		$lblDescription1.Text = "*ON Lock: When AutoPilot Dashboard starts, a password is required!"
		$stackBottom.Children.Add($lblDescription1) | Out-Null

		$lblDescription2 = New-Object System.Windows.Controls.TextBlock
		$lblDescription2.FontSize = 13
		$lblDescription2.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(144,238,144)) # светло зелена
		$lblDescription2.HorizontalAlignment = "Left"
		$lblDescription2.Margin = [System.Windows.Thickness]::new(0,5,0,5)  # горе и долу маргина
		$lblDescription2.Text = "*OFF Lock: AutoPilot Dashboard starts without a password!"
		$stackBottom.Children.Add($lblDescription2) | Out-Null

        $stack.Children.Add($stackBottom)

        $lockWindow.Content = $stack
        $lockWindow.ShowDialog()
    }

    Show-LockPopup
})

# ===================== BUTTON MODE 1 2 =====================
$Global:mode = 1
$Global:defaultClockColor = $txtClock.Foreground
$Global:defaultUptimeBackground = $borderUptime.Background
$Global:popupMaxHeight = 1015
$Global:statusMaxHeight = 1000
$Global:popupItemWidth = 180 
$Global:popupItemHeight = 70

# ===================== MODE TOGGLE =====================
function Toggle-DashboardSize {
    # ротирање 1 → 2 → 3 → 1
    $Global:mode++
    if ($Global:mode -gt 3) { $Global:mode = 1 }
    # ===================== MODE 2 =====================
    if ($Global:mode -eq 2) {
        $btnAction.Content = "❷ Mode"
        $headerGrid.Margin = "0,0,0,5"
		$Global:popupMaxHeight = 855
		$Global:statusMaxHeight = 855
    }
    # ===================== MODE 3 =====================
    elseif ($Global:mode -eq 3) {
        $btnAction.Content = "❸ Mode"
        $headerGrid.Margin = "0,0,0,5"
        $Global:popupMaxHeight = 655
		$Global:statusMaxHeight = 655
        $Global:popupItemWidth = 155 
        $Global:popupItemHeight = 55
        $wpDashboard.ItemWidth = $Global:popupItemWidth
        $wpDashboard.ItemHeight = $Global:popupItemHeight
    }
    # ===================== MODE 1 =====================
    else {
        $btnAction.Content = "❶ Mode"
        $headerGrid.Margin = "0,0,0,20"
        $Global:popupMaxHeight = 1015
		$Global:statusMaxHeight = 1000
        $Global:popupItemWidth = 180 
        $Global:popupItemHeight = 70
        $wpDashboard.ItemWidth = $Global:popupItemWidth
        $wpDashboard.ItemHeight = $Global:popupItemHeight
    }
    Update-ClockPosition
}

# ===================== CLOCK + COLORS =====================
function Update-ClockPosition {
    # ===================== MODE 1 =====================
    if ($Global:mode -eq 1) {
        # clock десно
        if ($centerClockContainer.Children.Contains($clockElement)) {
            $centerClockContainer.Children.Remove($clockElement)
        }
        if (-not $rightClockContainer.Children.Contains($clockElement)) {
            $rightClockContainer.Children.Add($clockElement)
        }
        # default бои
        $txtClock.Foreground = $Global:defaultClockColor
        if ($borderUptime -ne $null) {
            $borderUptime.Background = $Global:defaultUptimeBackground
        }
    }
    # ===================== MODE 2 & 3 =====================
    else {
        # clock центар
        if ($rightClockContainer.Children.Contains($clockElement)) {
            $rightClockContainer.Children.Remove($clockElement)
        }
        if (-not $centerClockContainer.Children.Contains($clockElement)) {
            $centerClockContainer.Children.Add($clockElement)
        }
        # random бои
        $txtClock.Foreground = Get-ClockBrush
        if ($borderUptime -ne $null) {
            $borderUptime.Background = Get-UptimeBrush
        }
    }
}

# ===================== CLOCK COLOR =====================
function Get-ClockBrush {
    $rand = New-Object System.Random
    $hue = $rand.Next(0,180)
    $saturation = 0.6 + ($rand.NextDouble() * 0.4)
    $brightness = 0.7 + ($rand.NextDouble() * 0.3)
    function HSV-To-RGB($h,$s,$v) {
        $c=$v*$s; $x=$c*(1-[math]::Abs((($h/60)%2)-1)); $m=$v-$c
        if($h -lt 60){$r=$c;$g=$x;$b=0}
        elseif($h -lt 120){$r=$x;$g=$c;$b=0}
        elseif($h -lt 180){$r=0;$g=$c;$b=$x}
        elseif($h -lt 240){$r=0;$g=$x;$b=$c}
        elseif($h -lt 300){$r=$x;$g=0;$b=$c}
        else{$r=$c;$g=0;$b=$x}
        $r=[math]::Round(($r+$m)*255)
        $g=[math]::Round(($g+$m)*255)
        $b=[math]::Round(($b+$m)*255)
        return [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb($r,$g,$b)
        )
    }
    return HSV-To-RGB $hue $saturation $brightness
}

# ===================== UPTIME COLOR =====================
function Get-UptimeBrush {
    $rand = New-Object System.Random
    $hue = 180 + $rand.Next(0,180)
    $saturation = 0.5 + ($rand.NextDouble() * 0.5)
    $brightness = 0.6 + ($rand.NextDouble() * 0.4)
    function HSV-To-RGB($h,$s,$v) {
        $c=$v*$s; $x=$c*(1-[math]::Abs((($h/60)%2)-1)); $m=$v-$c
        if($h -lt 60){$r=$c;$g=$x;$b=0}
        elseif($h -lt 120){$r=$x;$g=$c;$b=0}
        elseif($h -lt 180){$r=0;$g=$c;$b=$x}
        elseif($h -lt 240){$r=0;$g=$x;$b=$c}
        elseif($h -lt 300){$r=$x;$g=0;$b=$c}
        else{$r=$c;$g=0;$b=$x}
        $r=[math]::Round(($r+$m)*255)
        $g=[math]::Round(($g+$m)*255)
        $b=[math]::Round(($b+$m)*255)
        return [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb($r,$g,$b)
        )
    }
    return HSV-To-RGB $hue $saturation $brightness
}

# ===================== INIT =====================
Update-ClockPosition

# ===================== BUTTON CLICK =====================
$btnAction.Add_Click({
    Toggle-DashboardSize
})

# ===================== BUTTON TO SHOW FULL TIMELINE =====================
$btnTimelineList = $window.FindName("btnTimelineList") 
$btnTimelineList.Add_Click({
    # ===================== Проверка дали AutoPilot работи =====================
    $autoPilotRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\AutoPilot.ps1")
    }
    # Проверка дали е PAUSED
    $isPaused = Test-Path $Global:pauseFlagPath
    # ================= Window =================
    $listWindow = New-Object System.Windows.Window
    $listWindow.Title = "Automation Commands List All"
    $listWindow.Width = 1555
    $listWindow.Height = 900
    $listWindow.WindowStartupLocation = "CenterScreen"
    $listWindow.Background = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(15, 15, 15)))
    # ================= Grid =================
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = [System.Windows.Thickness]::new(10)
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{Height="*"}))
    # ===== TITLE CONTAINER =====
	$titleContainer = New-Object System.Windows.Controls.StackPanel
	$titleContainer.Orientation = "Horizontal"
	$titleContainer.HorizontalAlignment = "Center"
	$titleContainer.Margin = [System.Windows.Thickness]::new(0,0,0,10)
	# ===== LOGO IMAGE =====
	$logo = New-Object System.Windows.Controls.Image
	$logo.Source = [System.Windows.Media.Imaging.BitmapImage]::new(
		[System.Uri]::new("$AppRoot\media\autopilot.ico")
	)
	$logo.Width  = 55     # custom width
	$logo.Height = 55     # custom height
	$logo.Margin = [System.Windows.Thickness]::new(0,0,10,0)
	# ===== TITLE TEXT =====
	$titleText = New-Object System.Windows.Controls.TextBlock
	$titleText.Text = "Automation Commands List (All Commands)"
	$titleText.FontSize = 25
	$titleText.FontWeight = 'Bold'
	$titleText.Foreground = [System.Windows.Media.Brushes]::White
	$titleText.VerticalAlignment = "Center"
	# ===== ADD TO CONTAINER =====
	$titleContainer.Children.Add($logo)
	$titleContainer.Children.Add($titleText)
	# ===== ADD TO GRID =====
	[System.Windows.Controls.Grid]::SetRow($titleContainer,0)
	$grid.Children.Add($titleContainer)
    # ================= Legend =================
    $legendPanel = New-Object System.Windows.Controls.StackPanel
    $legendPanel.Orientation = "Horizontal"
    $legendPanel.Margin = [System.Windows.Thickness]::new(0,0,0,10)
    $legendPanel.HorizontalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetRow($legendPanel,1)
    $grid.Children.Add($legendPanel)
    function Add-LegendItem($color, $text) {
        $itemPanel = New-Object System.Windows.Controls.StackPanel
        $itemPanel.Orientation = "Horizontal"
        $itemPanel.Margin = [System.Windows.Thickness]::new(10,0,10,0)
        $colorBox = New-Object System.Windows.Controls.Border
        $colorBox.Background = $color
        $colorBox.Width = 20
        $colorBox.Height = 20
        $colorBox.CornerRadius = [System.Windows.CornerRadius]::new(3)
        $colorBox.Margin = [System.Windows.Thickness]::new(0,0,5,0)
        $textBlock = New-Object System.Windows.Controls.TextBlock
        $textBlock.Text = $text
        $textBlock.Foreground = [System.Windows.Media.Brushes]::White
        $textBlock.FontSize = 16
        $itemPanel.Children.Add($colorBox)
        $itemPanel.Children.Add($textBlock)
        $legendPanel.Children.Add($itemPanel)
    }
    Add-LegendItem ([System.Windows.Media.Brushes]::Gray)        "Prev Command"
	Add-LegendItem ([System.Windows.Media.Brushes]::Lime)        "Last Command (Current)"
	Add-LegendItem ([System.Windows.Media.Brushes]::Yellow)      "Skipped (Pause)"
	Add-LegendItem ([System.Windows.Media.Brushes]::Cyan)        "Next Command (Loop)"
	Add-LegendItem ([System.Windows.Media.Brushes]::LightGreen)  "Next Command (Week, Month, Year)"
    Add-LegendItem ([System.Windows.Media.Brushes]::Magenta)     "Next Command (Fixed)"
    # ================= ListBox =================
    $listBox = New-Object System.Windows.Controls.ListBox
    $listBox.Background = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(23, 23, 23)))
    $listBox.BorderThickness = 0
    $listBox.FontSize = 19
    $listBox.FontFamily = "Segoe UI"
    $listBox.Foreground = [System.Windows.Media.Brushes]::White
    $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
	$scrollViewer.Content = $listBox
	$scrollViewer.VerticalScrollBarVisibility = "Auto"
	$scrollViewer.HorizontalScrollBarVisibility = "Disabled"
	[System.Windows.Controls.Grid]::SetRow($scrollViewer,2)
	$grid.Children.Add($scrollViewer)
	# ================= MouseWheel Scroll Handling =================
	$scrollViewer.Add_PreviewMouseWheel({
		param($sender,$e)
		if ($sender) {
			$sender.ScrollToVerticalOffset($sender.VerticalOffset - $e.Delta)
			$e.Handled = $true
		}
	})
    # ================= Current Index =================
    $now = Get-Date
    $nowTime = Get-Date -Hour $now.Hour -Minute $now.Minute -Second $now.Second
    $index = if($global:timeline) { ($global:timeline | Where-Object { $_.Time -le $nowTime }).Count - 1 } else { -1 }
    if($index -lt 0){ $index = 0 }
    # ================= Populate List =================
    if(-not $global:timeline -or $global:timeline.Count -eq 0) {
        $lbItem = New-Object System.Windows.Controls.ListBoxItem
        $lbItem.Content = "No Auto Commands Create"
        $lbItem.Foreground = [System.Windows.Media.Brushes]::Red
        $lbItem.FontWeight = 'Bold'
        $listBox.Items.Add($lbItem)
    } else {
    foreach($i in 0..($global:timeline.Count-1)){
    $itemText = "{0:D3}. {1}" -f ($i+1), $global:timeline[$i].Text
    $lbItem = New-Object System.Windows.Controls.ListBoxItem
    $lbItem.Content = $itemText
    $lbItem.Padding = [System.Windows.Thickness]::new(5)
    # Одреди боја според Type/Mode
    $isTypeBlue = $global:timeline[$i].Type -match "weekly|monthly|yearly"
    $isModeMagenta = $global:timeline[$i].Mode -eq "fixed"
    # ===== AUTOPILOT STOPPED =====
    if (-not $autoPilotRunning) {
        if($i -lt $index){
            $lbItem.Foreground = [System.Windows.Media.Brushes]::Gray
        } 
        elseif($i -eq $index){
            $lbItem.Foreground = [System.Windows.Media.Brushes]::LightGray
            $lbItem.FontWeight = 'Bold'
            $lbItem.Content += "  (Current)"
        }
        else{
            # Следните линии
            if($isTypeBlue){ $lbItem.Foreground = [System.Windows.Media.Brushes]::LightGreen }
            elseif($isModeMagenta){ $lbItem.Foreground = [System.Windows.Media.Brushes]::Magenta }
            else{ $lbItem.Foreground = [System.Windows.Media.Brushes]::Cyan }
        }
    }
    # ===== PAUSED =====
    elseif ($isPaused) {
        if($i -eq $index){
            $lbItem.Foreground = [System.Windows.Media.Brushes]::Yellow
            $lbItem.FontWeight = 'Bold'
            $lbItem.Content += "  (Pause)"
        }
        elseif($i -lt $index){
            $lbItem.Foreground = [System.Windows.Media.Brushes]::Gray
        }
        else{
            if($isTypeBlue){ $lbItem.Foreground = [System.Windows.Media.Brushes]::LightGreen }
            elseif($isModeMagenta){ $lbItem.Foreground = [System.Windows.Media.Brushes]::Magenta }
            else{ $lbItem.Foreground = [System.Windows.Media.Brushes]::Cyan }
        }
    }
    # ===== NORMAL RUN =====
    else{
        if($i -lt $index){
            $lbItem.Foreground = [System.Windows.Media.Brushes]::Gray
        }
        elseif($i -eq $index){
            $lbItem.Foreground = [System.Windows.Media.Brushes]::Lime
            $lbItem.FontWeight = 'Bold'
        }
        else{
            if($isTypeBlue){ $lbItem.Foreground = [System.Windows.Media.Brushes]::LightGreen }
            elseif($isModeMagenta){ $lbItem.Foreground = [System.Windows.Media.Brushes]::Magenta }
            else{ $lbItem.Foreground = [System.Windows.Media.Brushes]::Cyan }
        }
    }
    $listBox.Items.Add($lbItem)
  }
}
    $listWindow.Content = $grid
    $listWindow.ShowDialog() | Out-Null
})

# ===================== LOAD TIMELINE =====================
function Load-Timeline {
    $cmdJson = Get-Content "$AppRoot\JSON\commands_edit.json" -Raw | ConvertFrom-Json
    $scrJson = Get-Content "$AppRoot\JSON\scripts_edit.json" -Raw | ConvertFrom-Json
    $timeline = @()
    # ================= SCRIPTS =================
    foreach($scr in $scrJson.ScheduledScripts){
        for($i=0; $i -lt $scr.Times.Count; $i++){
            $mode = $scr.Mode[$i]         # fixed или loop
            $type = "daily"               # за script, default daily
            $timeStr = $scr.Times[$i]
            $dayStr = if($scr.Day[$i] -and $scr.Day[$i].Trim() -ne "") { $scr.Day[$i] } else { "No Data" }
            # Време
            if($mode -eq "fixed" -and $dayStr){
                $dt = [datetime]::ParseExact("$dayStr $timeStr","yyyy-MM-dd HH:mm:ss",$null)
            } else {
                $today = Get-Date
                $timeParts = $timeStr -split ":"
                $dt = $today.Date.AddHours([int]$timeParts[0]).AddMinutes([int]$timeParts[1]).AddSeconds([int]$timeParts[2])
            }
            # ================= STATUS TEXT =================
            switch ($mode.ToLower()){
                "fixed" { $status = "Interval: FIKS" }
                "loop"  { $status = "Interval: LOOP" }
                default { $status = "" }
            }
            # за scripts секогаш Daily, така што ништо дополнително не се додава
            $timeline += [PSCustomObject]@{
                Time = $dt
                Mode = $mode
                Type = $type
                Text = "$status | SCRIPT ({0}) Command: {1} | Time: {2} | Delay: {3} sec | Repeat: {4} min | Mode: {5} | Day: {6}" -f `
                        ([System.IO.Path]::GetFileName($scr.Path)),
                        $scr.Commands[$i],
                        $scr.Times[$i],
                        $scr.DelaySeconds[$i],
                        $scr.RepeatIntervalMinutes[$i],
                        $scr.Mode[$i],
                        $dayStr
            }
        }
    }
    # ================= AUTO COMMANDS =================
    foreach($cmd in $cmdJson.AutoCommands.PSObject.Properties.Value){
        for($i=0; $i -lt $cmd.Times.Count; $i++){
            $mode = $cmd.Mode[$i]
            $type = if ($cmd.Type -is [Array]) { $cmd.Type[$i] } else { $cmd.Type } 
            $timeStr = $cmd.Times[$i]
            $dayStr = if($cmd.Day[$i] -and $cmd.Day[$i].Trim() -ne "") { $cmd.Day[$i] } else { "No Data" }
            # Време
            if($mode -eq "fixed" -and $dayStr){
                $dt = [datetime]::ParseExact("$dayStr $timeStr","yyyy-MM-dd HH:mm:ss",$null)
            } else {
                $today = Get-Date
                $timeParts = $timeStr -split ":"
                $dt = $today.Date.AddHours([int]$timeParts[0]).AddMinutes([int]$timeParts[1]).AddSeconds([int]$timeParts[2])
                switch ($type.ToLower()) {
                    "weekly" {
                        while($dt.DayOfWeek -ne [System.DayOfWeek]::Sunday){ $dt = $dt.AddDays(1) }
                    }
                    "monthly" {
                        $lastDay = [datetime]::DaysInMonth($dt.Year, $dt.Month)
                        $dt = [datetime]::new($dt.Year,$dt.Month,$lastDay,$dt.Hour,$dt.Minute,$dt.Second)
                    }
                    "yearly" {
                        $dt = [datetime]::new($dt.Year,12,31,$dt.Hour,$dt.Minute,$dt.Second)
                    }
                    default { } # daily
                }
            }
            # ================= STATUS TEXT =================
            switch ($mode.ToLower()){
                "fixed" { $status = "Interval: FIKS" }
                "loop"  { $status = "Interval: LOOP" }
                default { $status = "" }
            }
            # ================= TYPE TEXT =================
            switch ($type.ToLower()){
                "daily"   { $typeText = "" }         # оставаме истиот LOOP или FIKS
                "weekly"  { $typeText = " Mode: WEEK" } 
                "monthly" { $typeText = " Mode: MONTH" } 
                "yearly"  { $typeText = " Mode: YEAR" } 
                default   { $typeText = "" }
            }
            $timeline += [PSCustomObject]@{
                Time = $dt
                Mode = $mode
                Type = $type
                Text = "$status $typeText | AUTO COMMAND ({0}) | Time: {1} | Repeat: {2} min | Type: {3} | Mode: {4} | Day: {5}" -f `
                        $cmd.Cmd,
                        $cmd.Times[$i],
                        $cmd.RepeatIntervalMinutes[$i],
                        $type,
                        $cmd.Mode[$i],
                        $dayStr
            }
        }
    }
    # Сортирање по вистинско време
    $global:timeline = $timeline | Sort-Object Time
}

# ===================== UPDATE DISPLAY =====================
function Update-TimelineDisplay {
    # ===================== UI ELEMENTS =====================
    $liveTimelinePanel   = $window.FindName("liveTimelineStack")
    $liveTimelineMessage = $window.FindName("txtLiveTimelineMessage")
    # ===================== CHECK AUTOPILOT =====================
    $autoPilotRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\AutoPilot.ps1")
    }
    if (-not $autoPilotRunning) {
        if ($liveTimelinePanel)   { $liveTimelinePanel.Visibility = 'Collapsed' }
        if ($liveTimelineMessage) {
            $liveTimelineMessage.Text = "AutoPilot is STOPPED"
            $liveTimelineMessage.Visibility = 'Visible'
        }
		if($imgStatus){
		$imgStatus.Source = [System.Windows.Media.Imaging.BitmapImage]::new(
			[System.Uri]::new("$AppRoot\media\stop.png")
		)
	    }
        $txtPrev.Text     = "none"
        $txtCurrent.Text  = "none"
        $txtNext.Text     = "none"
        $txtCountdown.Text = "Auto Commands are not Running!"
        $txtCountdown.Foreground = [System.Windows.Media.Brushes]::Gray
        return
    }
    # ===================== CHECK PAUSE =====================
    $isPaused = Test-Path $Global:pauseFlagPath
    if ($isPaused) {
        if ($liveTimelinePanel)   { $liveTimelinePanel.Visibility = 'Collapsed' }
        if ($liveTimelineMessage) {
            $liveTimelineMessage.Text = "AutoPilot is PAUSED"
            $liveTimelineMessage.Visibility = 'Visible'
        }
		if($imgStatus){
		$imgStatus.Source = [System.Windows.Media.Imaging.BitmapImage]::new(
			[System.Uri]::new("$AppRoot\media\pause.png")
		)
	    }
        $txtPrev.Text     = "none"
        $txtCurrent.Text  = "none"
        $txtNext.Text     = "none"
        $txtCountdown.Text = "Auto Commands are not Running!"
        $txtCountdown.Foreground = [System.Windows.Media.Brushes]::Gray
        return
    }
    # ===================== SHOW TIMELINE =====================
    if ($liveTimelinePanel)   { $liveTimelinePanel.Visibility = 'Visible' }
    if ($liveTimelineMessage) { $liveTimelineMessage.Visibility = 'Collapsed' }
	if($imgStatus){
    $imgStatus.Source = [System.Windows.Media.Imaging.BitmapImage]::new(
        [System.Uri]::new("$AppRoot\media\play.png")
    )
    }
    if (-not $global:timeline) { 
        $txtPrev.Text = "none"
        $txtCurrent.Text = "none"
        $txtNext.Text = "none"
        $txtCountdown.Text = " No timeline data"
        $txtCountdown.Foreground = [System.Windows.Media.Brushes]::Gray
        return
    }
    $now   = Get-Date
    $today = $now.Date
    # ===================== FILTER DISPLAY LINES =====================
    $displayTimeline = $global:timeline | Where-Object {
        if ($_.Mode -eq "loop") {
            switch ($_.Type) {
                "daily"   { return $true }
                "weekly"  { return ($today.DayOfWeek -eq [DayOfWeek]::Sunday) }
                "monthly" { return ($today.Day -eq [DateTime]::DaysInMonth($today.Year, $today.Month)) }
                "yearly"  { return ($today.Month -eq 12 -and $today.Day -eq 31) }
                default   { return $true }
            }
        }
        elseif ($_.Mode -eq "fixed" -and $_.Time.Date -eq $today) {
            return $true
        }
        return $false
    }
    if (-not $displayTimeline) {
        $displayTimeline = $global:timeline | Where-Object { $_.Mode -eq "loop" -and $_.Type -eq "daily" }
    }
    # ===================== INDEX =====================
    $index = ($displayTimeline | Where-Object { $_.Time -le $now }).Count - 1
    if ($index -lt 0) { $index = 0 }
    function GetText($i){
        if ($i -lt 0 -or $i -ge $displayTimeline.Count) { return "-" }
        return "{0}. {1}" -f ($i + 1), $displayTimeline[$i].Text
    }
    $txtPrev.Text    = GetText($index - 1)
    $txtCurrent.Text = GetText($index)
    $txtNext.Text    = GetText($index + 1)
    # ===================== LINE COLORS =====================
    #$txtCurrent.Foreground = [System.Windows.Media.Brushes]::Lime
    #$txtPrev.Foreground    = [System.Windows.Media.Brushes]::Gray
    # ===================== NEXT COMMAND =====================
    $upcomingLines = $global:timeline | ForEach-Object {
        $lineTime = $_.Time
        $nextTime = $null
        if ($_.Mode -eq "loop") {
            $nextTime = $today.Date.AddHours($lineTime.Hour).AddMinutes($lineTime.Minute).AddSeconds($lineTime.Second)
            switch ($_.Type) {
                "daily"   { if ($nextTime -le $now) { $nextTime = $nextTime.AddDays(1) } }
                "weekly"  { while ($nextTime.DayOfWeek -ne [DayOfWeek]::Sunday) { $nextTime = $nextTime.AddDays(1) } }
                "monthly" { $lastDay = [DateTime]::DaysInMonth($today.Year, $today.Month)
                            if ($today.Day -lt $lastDay) { $nextTime = $today.AddDays($lastDay - $today.Day).AddHours($lineTime.Hour).AddMinutes($lineTime.Minute).AddSeconds($lineTime.Second) } 
                            elseif ($nextTime -le $now) { $nextTime = $nextTime.AddMonths(1); $nextTime = $nextTime.AddDays([DateTime]::DaysInMonth($nextTime.Year,$nextTime.Month)-$nextTime.Day) } }
                "yearly"  { $nextTime = Get-Date -Year $today.Year -Month 12 -Day 31 -Hour $lineTime.Hour -Minute $lineTime.Minute -Second $lineTime.Second
                            if ($nextTime -le $now) { $nextTime = $nextTime.AddYears(1) } }
                default   { if ($nextTime -le $now) { $nextTime = $nextTime.AddDays(1) } }
            }
        }
        elseif ($_.Mode -eq "fixed") {
            $nextTime = $_.Time
            if ($nextTime -lt $now) { $nextTime = $null } # ако поминало, игнорирај
        }
        if ($nextTime) {
            [PSCustomObject]@{
                Line = $_
                Time = $nextTime
            }
        }
    }
    $nextCmd = $upcomingLines | Sort-Object Time | Select-Object -First 1
    if ($nextCmd) {
		# ако има уште линии во displayTimeline → користи нормален display број
		if (($index + 1) -lt $displayTimeline.Count) {
			$txtNext.Text = "{0}. {1}" -f ($index + 2), $displayTimeline[$index + 1].Text
		}
		else {
			# ===== fallback: loop daily линии почнуваат од 1 =====
			$loopDaily = $global:timeline | Where-Object {
				$_.Mode -eq "loop" -and $_.Type -eq "daily"
			}
			$loopIndex = ($loopDaily | ForEach-Object { $_.Text }).IndexOf($nextCmd.Line.Text)
			if ($loopIndex -ge 0) {
				$txtNext.Text = "{0}. {1}" -f ($loopIndex + 1), $nextCmd.Line.Text
			}
			else {
				$txtNext.Text = "{0}. {1}" -f 1, $nextCmd.Line.Text
			}
		}
        $diff = $nextCmd.Time - $now
		# ===== DST FIX (ако времето отиде назад/напред) =====
		if ($diff.TotalSeconds -lt 0) {
			while ($nextCmd.Time -le $now) {
				switch ($nextCmd.Line.Type) {
					"daily"   { $nextCmd.Time = $nextCmd.Time.AddDays(1) }
					"weekly"  { $nextCmd.Time = $nextCmd.Time.AddDays(7) }
					"monthly" { $nextCmd.Time = $nextCmd.Time.AddMonths(1) }
					"yearly"  { $nextCmd.Time = $nextCmd.Time.AddYears(1) }
					default   { $nextCmd.Time = $nextCmd.Time.AddDays(1) }
				}
			}
			$diff = $nextCmd.Time - $now
		}
		$parts = @()
		if ($diff.Days -gt 0)    { $parts += "{0}d" -f $diff.Days }
		if ($diff.Hours -gt 0)   { $parts += "{0:D2}h" -f $diff.Hours }
		if ($diff.Minutes -gt 0) { $parts += "{0:D2}m" -f $diff.Minutes }
		if ($diff.Seconds -ge 0) { $parts += "{0:D2}s" -f $diff.Seconds }

		if ($diff.TotalSeconds -le 15) {
			$txtCountdown.Text = " Next Auto Command In: " + ($parts -join " ")
			$txtCountdown.Foreground = [System.Windows.Media.Brushes]::Red
		} else {
			$txtCountdown.Text = " Next Auto Command In: " + ($parts -join " ")
			$txtCountdown.Foreground = [System.Windows.Media.Brushes]::Gray
		}	
	}
}

Load-Timeline

# ===================== WATCH JSON FILES =====================
function Setup-TimelineWatcher {
    $jsonPath = "$AppRoot\JSON"
    foreach($file in @("scripts_edit.json","commands_edit.json")) {
        $watcher = New-Object System.IO.FileSystemWatcher
        $watcher.Path = $jsonPath
        $watcher.Filter = $file
        $watcher.NotifyFilter = [System.IO.NotifyFilters]'LastWrite'
        $watcher.EnableRaisingEvents = $true
        Register-ObjectEvent $watcher Changed -Action {
            Start-Sleep -Milliseconds 200 # Чекај малку за да заврши записот
            try {
                Load-Timeline 
                Update-TimelineDisplay
            } catch {
                Write-Host "Error reloading timeline: $_"
            }
        }
    }
}

# ===================== INITIAL LOAD =====================
Load-Timeline
Update-TimelineDisplay

# ===================== START WATCHERS =====================
Setup-TimelineWatcher | Out-Null

# ===================== TIMER =====================
$timerTimeline = New-Object System.Windows.Threading.DispatcherTimer
$timerTimeline.Interval = [TimeSpan]::FromSeconds(1) # секунда за live countdown
$timerTimeline.Add_Tick({ Update-TimelineDisplay })
$timerTimeline.Start()

# ===================== Timer Refresh =====================
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({ Update-AutoPilotStatusUI 
                  Update-SystemStatusUI
                  Update-TrafficStatusUI
				  Update-PauseUI 
				  Update-BotStatusUI  
				  Update-ModeUI
})
$timer.Start()

# ===================== SCRIPT LAUNCHER BUTTONS =====================
$window.FindName("btnS1").Add_Click({ Start-Shortcut "Defender" })
$window.FindName("btnS2").Add_Click({ Start-Shortcut "Pi" })
$window.FindName("btnS3").Add_Click({ Start-Shortcut "Docker" })
$window.FindName("btnS4").Add_Click({ Start-Shortcut "Cleaner" })
$window.FindName("btnS5").Add_Click({ Start-Shortcut "Network" })
$window.FindName("btnS6").Add_Click({ Start-Shortcut "NetTraffic" })
$window.FindName("btnS7").Add_Click({ Start-Shortcut "SetDocker" })
$window.FindName("btnS8").Add_Click({ Start-Shortcut "PowerPlan" })

# ===================== COMMAND BUTTONS =====================
# System Commands
$window.FindName("btnSys").Add_Click({ Invoke-ManualCommand "/system_status" })
$window.FindName("btnPing").Add_Click({ Invoke-ManualCommand "/ping" })
$window.FindName("btnTemp").Add_Click({ Invoke-ManualCommand "/temp" })
$window.FindName("btnLoad").Add_Click({ Invoke-ManualCommand "/total_load" })
$window.FindName("btnStat").Add_Click({ Invoke-ManualCommand "/total_stat" })
$window.FindName("btnScreen").Add_Click({ Invoke-ManualCommand "/screen" })
$window.FindName("btnNetMon").Add_Click({ Invoke-ManualCommand "/net_monitor" })
$window.FindName("btnSysMon").Add_Click({ Invoke-ManualCommand "/system_monitor" })
$window.FindName("btnMedia").Add_Click({ Invoke-ManualCommand "/media" })
$window.FindName("btnCamera").Add_Click({ Invoke-ManualCommand "/camera" })
$window.FindName("btnData").Add_Click({
    Show-DarkWarning `
        -Title "Warning!" `
        -Message "Inside the *DATA* folder are System Files!"
    Invoke-ManualCommand "/data"
})
$window.FindName("btnTask_add").Add_Click({ 
Show-DarkWarning `
        -Title "Auto-Start AutoPilot" `
        -Message "When *Auto-Start* is Enabled, AutoPilot will launch automatically every time the PC Starts!"
    Invoke-ManualCommand "/task-add"
})
$window.FindName("btnTask_del").Add_Click({ 
Show-DarkWarning `
        -Title "Stop Auto-Start" `
        -Message "When *Auto-Start* is Disabled, AutoPilot will launch only Manually!"
    Invoke-ManualCommand "/task-del"
})
$window.FindName("btnTask_show").Add_Click({ Invoke-ManualCommand "/task-show" })
$window.FindName("btnSettings").Add_Click({
    Show-DarkWarning -Title "AutoPilot Settings!" -Message "Changes in this *SETTINGS Block* will become active after Refreshing AutoPilot!"
    $exePath = "$AppRoot\Settings.exe"
    if (Test-Path $exePath) {
        Start-Process $exePath
    } else {
        [Windows.Forms.MessageBox]::Show("Settings.exe not found!","Error")
    }
})

$window.FindName("btnSettingsScripts").Add_Click({
    Show-DarkWarning -Title "Scripts Settings!" -Message "Changes in this *SCRIPTS SETTINGS Block* will take effect after Refreshing AutoPilot!"
    $exePath = "$AppRoot\SettingsScripts.exe"
    if (Test-Path $exePath) {
        Start-Process $exePath
    } else {
        [Windows.Forms.MessageBox]::Show("ScriptsSettings.exe not found!","Error")
    }
})
$window.FindName("btnShowCmd").Add_Click({ Invoke-ManualCommand "/show_cmd" })
$window.FindName("btnHideCmd").Add_Click({ Invoke-ManualCommand "/hide_cmd" })

# Graph Load
$window.FindName("btnLoadDay").Add_Click({ Invoke-ManualCommand "/load_day" })
$window.FindName("btnLoadWeek").Add_Click({ Invoke-ManualCommand "/load_week" })
$window.FindName("btnLoadMonth").Add_Click({ Invoke-ManualCommand "/load_month" })
$window.FindName("btnLoadYear").Add_Click({ Invoke-ManualCommand "/load_year" })
$window.FindName("btnLoadAll").Add_Click({ Invoke-ManualCommand "/load_all" })
$window.FindName("btnLoadArchive").Add_Click({ Invoke-ManualCommand "/load_archive" })

# Graph Temp
$window.FindName("btnTempDay").Add_Click({ Invoke-ManualCommand "/temp_day" })
$window.FindName("btnTempWeek").Add_Click({ Invoke-ManualCommand "/temp_week" })
$window.FindName("btnTempMonth").Add_Click({ Invoke-ManualCommand "/temp_month" })
$window.FindName("btnTempYear").Add_Click({ Invoke-ManualCommand "/temp_year" })
$window.FindName("btnTempAll").Add_Click({ Invoke-ManualCommand "/temp_all" })
$window.FindName("btnTempArchive").Add_Click({ Invoke-ManualCommand "/temp_archive" })

# Graph Disk
$window.FindName("btnDiskDay").Add_Click({ Invoke-ManualCommand "/disk_day" })
$window.FindName("btnDiskWeek").Add_Click({ Invoke-ManualCommand "/disk_week" })
$window.FindName("btnDiskMonth").Add_Click({ Invoke-ManualCommand "/disk_month" })
$window.FindName("btnDiskYear").Add_Click({ Invoke-ManualCommand "/disk_year" })
$window.FindName("btnDiskAll").Add_Click({ Invoke-ManualCommand "/disk_all" })
$window.FindName("btnDiskArchive").Add_Click({ Invoke-ManualCommand "/disk_archive" })

# Table Net Traffic
$window.FindName("btnTableDay").Add_Click({ Invoke-ManualCommand "/table_day" })
$window.FindName("btnTableWeek").Add_Click({ Invoke-ManualCommand "/table_week" })
$window.FindName("btnTableMonth").Add_Click({ Invoke-ManualCommand "/table_month" })
$window.FindName("btnTableYear").Add_Click({ Invoke-ManualCommand "/table_year" })
$window.FindName("btnTableAll").Add_Click({ Invoke-ManualCommand "/table_all" })
$window.FindName("btnTableArchive").Add_Click({ Invoke-ManualCommand "/table_archive" })

# Storage & Log File
$window.FindName("btnAutoPilot_Log").Add_Click({ Invoke-ManualCommand "/autopilot_log" })
$window.FindName("btnMonitoring_Log").Add_Click({ Invoke-ManualCommand "/system_log" })
$window.FindName("btnTraffic_Log").Add_Click({ Invoke-ManualCommand "/traffic_log" })
$window.FindName("btnData_Log").Add_Click({ Invoke-ManualCommand "/data_log" })
$window.FindName("btnNetwork_Log").Add_Click({ Invoke-ManualCommand "/network_log" })
$window.FindName("btnUpdate_Log").Add_Click({ Invoke-ManualCommand "/update_log" })

# Monitoring
$window.FindName("btnSysMon_Start").Add_Click({ Invoke-ManualCommand "/monitoring_start" })
$window.FindName("btnSysMon_Stop").Add_Click({ Invoke-ManualCommand "/monitoring_stop" })
$window.FindName("btnSysMon_Status").Add_Click({ Invoke-ManualCommand "/monitoring_status" })
$window.FindName("btnTrafficMonitoring").Add_Click({ Start-Process "$AppRoot\Shortcuts\NetTraffic.lnk" })
# Stop Workers
$btnStopWorkers = $window.FindName("btnStopWorkers")
$btnStopWorkers.Add_Click({
    $msg = "Warning: System and Network Monitoring may currently be Running. Are you sure you want to STOP the Monitoring?"
    $title = "Stopping the Monitoring!"
    $userChoice = Show-DarkConfirm -Message $msg -Title $title
    if ($userChoice) {
        Invoke-ManualCommand "/stop_worker"
    } else {
        Show-DarkWarning -Title "Monitoring STOP" -Message "Monitoring stop has been canceled by the user."
    }
})

$window.ShowDialog() | Out-Null

############################################################################################## End Dashboard.