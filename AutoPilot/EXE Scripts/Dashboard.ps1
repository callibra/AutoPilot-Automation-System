Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
# ===================== SINGLE INSTANCE =====================
$createdNew = $false
$script:InstanceLock = [System.Threading.Mutex]::new(
    $false,
    'Local\AutoPilotDashboard-6d2b7e14-9a3f-4c58-b1e0-2f7a8c4d5e93',
    [ref]$createdNew
)
if (-not $createdNew) { exit 0 }
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
        Background="Transparent"
        Title="$Title"
        WindowStyle="None"
        AllowsTransparency="True"
        ShowInTaskbar="False">
        <Border Background="#F222252C" CornerRadius="16" Padding="25" BorderBrush="#444954" BorderThickness="1">
        <StackPanel Width="460">
            <TextBlock Text="$Title" FontSize="24" FontWeight="Bold" Foreground="#E4E4E7" Margin="0,0,0,15" HorizontalAlignment="Center"/>
            <TextBlock Text="$Message" TextWrapping="Wrap" FontSize="16" Foreground="#D4D4D8" Margin="0,0,0,25" TextAlignment="Center"/>
            <Button Content="OK" Width="140" Height="42" HorizontalAlignment="Center" Foreground="White" FontWeight="SemiBold" FontSize="15" BorderThickness="0" Cursor="Hand">
				<Button.Template>
						<ControlTemplate TargetType="Button">
							<Border x:Name="border" Background="#0369A1" CornerRadius="10">
								<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
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
$RegistryPath = "HKCU:\Software\StorageFileValue"
$RegistryValueName = "ProgramValueFile"

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
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"Start-Sleep -Seconds 10; Start-Process -FilePath '$UpdaterPath'`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
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
	"/process_log"        = @{ Cmd = "Process-Log" }
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
        <Border CornerRadius="16" Padding="15" BorderThickness="1" BorderBrush="#444954" Background="#F222252C">
        <Grid>
            <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                <!-- PNG image -->
                <Image Name="imgLoading" Width="80" Height="80" Margin="0,0,0,10"/>
                <TextBlock Text="$Message" Foreground="#E4E4E7" FontSize="20" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
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
        Background="#1A1C22"
        FontFamily="Segoe UI"
        ResizeMode="NoResize"
        WindowStyle="SingleBorderWindow">
    <Window.Resources>
        <Style x:Key="ScrollThumbStyle" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border CornerRadius="4" Background="#474C58" Margin="2,0"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollPageStyle" TargetType="RepeatButton">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Border Background="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Border Background="#33000000" CornerRadius="6">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource ScrollPageStyle}" Command="ScrollBar.PageUpCommand"/>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource ScrollThumbStyle}"/>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource ScrollPageStyle}" Command="ScrollBar.PageDownCommand"/>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="10">
        <Border CornerRadius="16" Background="#262930" BorderBrush="#363A44" BorderThickness="1" Padding="15">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="60"/>
                </Grid.RowDefinitions>
                <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <TextBlock Name="txtMessage" TextWrapping="Wrap" Foreground="#E4E4E7" FontSize="18"/>
                </ScrollViewer>
				<Border Grid.Row="1" Background="#1E2026" BorderBrush="#363A44" BorderThickness="1" CornerRadius="10" Margin="0,10,0,0">
					<StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
						<Button Name="btnSave" Content="Save" Width="80" Height="30" Margin="0,0,10,0" Foreground="White" FontWeight="SemiBold" FontSize="14">
							<Button.Template>
								<ControlTemplate TargetType="Button">
									<Border x:Name="border" Background="#7C3AED" CornerRadius="10">
										<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
									</Border>
									<ControlTemplate.Triggers>
										<Trigger Property="IsMouseOver" Value="True">
											<Setter TargetName="border" Property="Background" Value="#8B5CF6"/>
										</Trigger>
										<Trigger Property="IsPressed" Value="True">
											<Setter TargetName="border" Property="Background" Value="#6D28D9"/>
										</Trigger>
									</ControlTemplate.Triggers>
								</ControlTemplate>
							</Button.Template>
						</Button>
						<Button Name="btnOk" Content="OK" Width="80" Height="30" Foreground="White" FontWeight="SemiBold" FontSize="14">
							<Button.Template>
								<ControlTemplate TargetType="Button">
									<Border x:Name="border" Background="#0369A1" CornerRadius="10">
										<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
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
							</Button.Template>
						</Button>
					</StackPanel>
				</Border>
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
        Background="#1A1C22"
        FontFamily="Segoe UI"
        ResizeMode="NoResize"
        WindowStyle="SingleBorderWindow">
    <Window.Resources>
        <Style x:Key="ScrollThumbStyle" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border CornerRadius="4" Background="#474C58" Margin="2,0"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollPageStyle" TargetType="RepeatButton">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Border Background="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Border Background="#33000000" CornerRadius="6">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource ScrollPageStyle}" Command="ScrollBar.PageUpCommand"/>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource ScrollThumbStyle}"/>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource ScrollPageStyle}" Command="ScrollBar.PageDownCommand"/>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border Margin="10" CornerRadius="16" Background="#262930" BorderBrush="#363A44" BorderThickness="1" Padding="10">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="60"/>
                </Grid.RowDefinitions>
                <Image Name="imgControl" Stretch="None" Margin="0,0,0,10"/>
				<Border Grid.Row="1" Background="#1E2026" BorderBrush="#363A44" BorderThickness="1" CornerRadius="10" Margin="0,0,0,10">
					<StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
						<Button Name="btnSave" Content="Save" Width="80" Height="30" Margin="0,0,10,0" Foreground="White" FontWeight="SemiBold" FontSize="14">
							<Button.Template>
								<ControlTemplate TargetType="Button">
									<Border x:Name="border" Background="#7C3AED" CornerRadius="10">
										<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
									</Border>
									<ControlTemplate.Triggers>
										<Trigger Property="IsMouseOver" Value="True">
											<Setter TargetName="border" Property="Background" Value="#8B5CF6"/>
										</Trigger>
										<Trigger Property="IsPressed" Value="True">
											<Setter TargetName="border" Property="Background" Value="#6D28D9"/>
										</Trigger>
									</ControlTemplate.Triggers>
								</ControlTemplate>
							</Button.Template>
						</Button>
						<Button Name="btnOk" Content="OK" Width="80" Height="30" Foreground="White" FontWeight="SemiBold" FontSize="14">
							<Button.Template>
								<ControlTemplate TargetType="Button">
									<Border x:Name="border" Background="#0369A1" CornerRadius="10">
										<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
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
							</Button.Template>
						</Button>
					</StackPanel>
				</Border>
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
        Background='Transparent'
        WindowStyle='None'
        AllowsTransparency='True'>
        <Border Background='#F222252C' CornerRadius='16' Padding='20' BorderBrush='#D16969' BorderThickness='1'>
        <StackPanel Width="520">
            <TextBlock Text='$Title' FontSize="24" FontWeight='Bold' Foreground='#E4E4E7' Margin='0,0,0,10' HorizontalAlignment='Center'/>
            <TextBlock Text='$Message' TextWrapping='Wrap' FontSize="16" Foreground='#D4D4D8' Margin='0,0,0,20'/>
            <StackPanel Orientation='Horizontal' HorizontalAlignment='Center'>
                <Button Name='btnYes' Content='Yes' Width='100' Height='35' Margin='5' Foreground='White' FontWeight='SemiBold' FontSize='15'>
					<Button.Template>
						<ControlTemplate TargetType="Button">
							<Border x:Name="border" Background="#059669" CornerRadius="10">
								<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
							</Border>
							<ControlTemplate.Triggers>
								<Trigger Property="IsMouseOver" Value="True">
									<Setter TargetName="border" Property="Background" Value="#10A37A"/>
								</Trigger>
								<Trigger Property="IsPressed" Value="True">
									<Setter TargetName="border" Property="Background" Value="#047857"/>
								</Trigger>
							</ControlTemplate.Triggers>
						</ControlTemplate>
					</Button.Template>
				</Button>
				<Button Name='btnNo' Content='No' Width='100' Height='35' Margin='5' Foreground='White' FontWeight='SemiBold' FontSize='15'>
					<Button.Template>
						<ControlTemplate TargetType="Button">
							<Border x:Name="border" Background="#DC3C4E" CornerRadius="10">
								<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
							</Border>
							<ControlTemplate.Triggers>
								<Trigger Property="IsMouseOver" Value="True">
									<Setter TargetName="border" Property="Background" Value="#E8586A"/>
								</Trigger>
								<Trigger Property="IsPressed" Value="True">
									<Setter TargetName="border" Property="Background" Value="#BE2D3F"/>
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
        [string]$DisplayName,
		[string]$StartTitle,
        [string]$StartMessage
    )
    $running = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($running) {
        Show-DarkWarning `
            -Title "ℹ️ Information" `
            -Message "⚠️ $DisplayName already open."
        return
    }
    if (Test-Path $ExePath) {
		Show-DarkWarning `
            -Title $StartTitle `
            -Message $StartMessage
        Start-Process -FilePath $ExePath -WindowStyle Normal
    }
    else {
        Show-DarkWarning `
            -Title "⚠️ Error" `
            -Message "⛔ $DisplayName not found!`nPath= $ExePath"
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
                $txtUptime.Text = "🕓 {0}d {1:D2}:{2:D2}:{3:D2}" -f $days, $hours, $minutes, $seconds
            }
            elseif ($hours -gt 0) {
                $txtUptime.Text = "🕓 {0:D2}:{1:D2}:{2:D2}" -f $hours, $minutes, $seconds
            }
            else {
                $txtUptime.Text = "🕓 {0:D2}:{1:D2}" -f $minutes, $seconds
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
		<VisualBrush>
			<VisualBrush.Visual>
				<Grid Width="1700" Height="900">
					<!-- COLOR BACKGROUND -->
					<Rectangle Fill="#1A1C22"/>
					<!-- IMAGE OVER COLOR -->
					<Rectangle Opacity="0.38">
						<Rectangle.Fill>
							<DrawingBrush Stretch="None" TileMode="None" AlignmentX="Center" AlignmentY="Center">
								<DrawingBrush.Drawing>
									<ImageDrawing Rect="0,0,555,555"
												  ImageSource="$AppRoot\media\autopilot.ico"/>
								</DrawingBrush.Drawing>
							</DrawingBrush>
						</Rectangle.Fill>
					</Rectangle>
				</Grid>
			</VisualBrush.Visual>
		</VisualBrush>
	</Window.Background>
	<Window.Resources>
		<!-- ===== Midnight Glass : button style ===== -->
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
			<Setter Property="FontSize" Value="19"/>
			<Setter Property="FontWeight" Value="SemiBold"/>
			<Setter Property="Cursor" Value="Hand"/>
			<Setter Property="BorderBrush" Value="#3B3F4A"/>
			<Setter Property="BorderThickness" Value="1"/>
			<Setter Property="SnapsToDevicePixels" Value="True"/>
			<Setter Property="FocusVisualStyle" Value="{x:Null}"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="Button">
						<Border x:Name="border"
							Background="{TemplateBinding Background}"
							BorderBrush="{TemplateBinding BorderBrush}"
							BorderThickness="{TemplateBinding BorderThickness}"
							CornerRadius="11"
							SnapsToDevicePixels="True">
						<ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="5" RecognizesAccessKey="True"/>
						</Border>
						<ControlTemplate.Triggers>
							<!-- Hover: cyan glow -->
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
							<!-- Pressed -->
							<Trigger Property="IsPressed" Value="True">
								<Setter TargetName="border" Property="Background" Value="#12222A"/>
								<Setter TargetName="border" Property="BorderBrush" Value="#E4E4E7"/>
								<Setter Property="Foreground" Value="#FFFFFF"/>
							</Trigger>
							<!-- Disabled -->
							<Trigger Property="IsEnabled" Value="False">
								<Setter TargetName="border" Property="Opacity" Value="0.4"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
		<!-- ===== Card (glass panel) ===== -->
		<Style x:Key="Card" TargetType="Border">
			<Setter Property="Background" Value="#CC22252C"/>
			<Setter Property="BorderBrush" Value="#363A44"/>
			<Setter Property="BorderThickness" Value="1"/>
			<Setter Property="CornerRadius" Value="16"/>
			<Setter Property="Padding" Value="16,12,16,14"/>
			<Setter Property="Margin" Value="0,0,0,12"/>
		</Style>
		<!-- ===== Dark thin scrollbar ===== -->
		<Style x:Key="ScrollThumbStyle" TargetType="Thumb">
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="Thumb">
						<Border CornerRadius="4" Background="#474C58" Margin="2,0"/>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
		<Style x:Key="ScrollPageStyle" TargetType="RepeatButton">
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="RepeatButton">
						<Border Background="Transparent"/>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
		<Style TargetType="ScrollBar">
			<Setter Property="Width" Value="12"/>
			<Setter Property="Template">
				<Setter.Value>
					<ControlTemplate TargetType="ScrollBar">
						<Border Background="#33000000" CornerRadius="6">
							<Track x:Name="PART_Track" IsDirectionReversed="True">
								<Track.DecreaseRepeatButton>
									<RepeatButton Style="{StaticResource ScrollPageStyle}" Command="ScrollBar.PageUpCommand"/>
								</Track.DecreaseRepeatButton>
								<Track.Thumb>
									<Thumb Style="{StaticResource ScrollThumbStyle}"/>
								</Track.Thumb>
								<Track.IncreaseRepeatButton>
									<RepeatButton Style="{StaticResource ScrollPageStyle}" Command="ScrollBar.PageDownCommand"/>
								</Track.IncreaseRepeatButton>
							</Track>
						</Border>
					</ControlTemplate>
				</Setter.Value>
			</Setter>
		</Style>
	</Window.Resources>
    <ScrollViewer VerticalScrollBarVisibility="Auto">
	<StackPanel Margin="15">
    
	<!-- AUTO PILOT HEADER -->
	<Border Style="{StaticResource Card}" Padding="16,10" Margin="0,0,0,14">
	<Grid>
		<Grid.ColumnDefinitions>
			<ColumnDefinition Width="*"/>       <!-- Logo + Title -->
			<ColumnDefinition Width="Auto"/>    <!-- Buttons -->
			<ColumnDefinition Width="Auto"/>    <!-- Panels + Clock -->
		</Grid.ColumnDefinitions>
		<!-- Left: Logo + Dashboard Title -->
		<StackPanel Grid.Column="0" Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
			<Image Source="$AppRoot\media\autopilot.ico" Width="50" Height="50" VerticalAlignment="Center"/>
			<StackPanel Orientation="Vertical" VerticalAlignment="Center" Margin="8,0,0,0">
				<TextBlock Text="AutoPilot" FontSize="25" FontWeight="Bold" Foreground="#FAFAFA"/>
				<TextBlock Text="Automation System" FontSize="11" Foreground="#22D3EE" Margin="1,-2,0,0" HorizontalAlignment="Center"/>
			</StackPanel>
		</StackPanel>
		<!-- Center: Start/Stop/Refresh/Pause Buttons -->
		<StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Button x:Name="btnStartAutoPilot" Content="Start ▶️" Style="{StaticResource ModernButton}" Width="100" Height="45" FontSize="16" BorderBrush="#2E9E73"/>
				<TextBlock Text="Start AutoPilot" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Button x:Name="btnStopAutoPilot" Content="Stop ⏹️" Style="{StaticResource ModernButton}" Width="100" Height="45" FontSize="16" BorderBrush="#B84A58"/>
				<TextBlock Text="Stop AutoPilot" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Button x:Name="btnRefresh" Content="Refresh 🔄" Style="{StaticResource ModernButton}" Width="100" Height="45" FontSize="16" BorderBrush="#D9B44A"/>
				<TextBlock Text="Refresh AutoPilot" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<!-- Pause Button -->
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Button x:Name="btnPauseAutoPilot" Style="{StaticResource ModernButton}" Width="100" Height="45">
				<TextBlock x:Name="txtPauseButton" Text="Pause ⏸️" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
				</Button>
				<!-- STATUS TEXT with COLOR -->
				<TextBlock x:Name="txtPauseStatus" FontSize="10" HorizontalAlignment="Center" Margin="0,3,0,0">
					<Run Text="Status: " Foreground="#A1A1AA"/>
					<Run x:Name="txtPauseState" Text="RUNNING" Foreground="LightGreen"/>
				</TextBlock>
			</StackPanel>
		</StackPanel>
		<!-- Right: Panels + Clock -->
		<StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderAutoPilotStatus" CornerRadius="10" Height="45" Width="100" Background="#4A4A52" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtAutoPilotStatus" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="AutoPilot Status" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderSystemStatus" CornerRadius="10" Height="45" Width="100" Background="#4A4A52" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtSystemStatus" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="System Monitoring" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderTrafficStatus" CornerRadius="10" Height="45" Width="100" Background="#4A4A52" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtTrafficStatus" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="Traffic Monitoring" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderAutoPilotBot" CornerRadius="10" Height="45" Width="100" Background="#4A4A52" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtAutoPilotBot" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="AutoPilot Bot" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderMediaBot" CornerRadius="10" Height="45" Width="100" Background="#4A4A52" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtMediaBot" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="Media Bot" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderMode" CornerRadius="10" Height="45" Width="100" Background="#4A4A52" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtMode" Text="Loading" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="AutoPilot Mode" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderInternet" CornerRadius="10" Height="45" Width="110" Background="#BE3737" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="5" Margin="0,0,8,0">
					<TextBlock x:Name="txtInternet" Text="🚫 Disconnected" FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="Network" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Border x:Name="borderUptime" CornerRadius="10" Height="45" Width="120" Background="#1D4ED8" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="5" Margin="0,0,20,0">
					<TextBlock x:Name="txtUptime" Text="Start..." FontSize="12" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" HorizontalAlignment="Center"/>
				</Border>
				<TextBlock Text="Uptime" FontSize="10" Foreground="#A1A1AA" HorizontalAlignment="Center" Margin="0,3,0,0"/>
			</StackPanel>
			<!-- Clock -->
			<!-- MaxWidth makes the text wrap into two lines (date / time) only here; in the display (modes 2-5) it stays one line -->
			<Grid x:Name="rightClockContainer" MaxWidth="288" VerticalAlignment="Center" HorizontalAlignment="Center" Margin="10,0,0,0">
			<Grid x:Name="clockElement">
				<Grid.ColumnDefinitions>
					<ColumnDefinition Width="Auto"/>
					<ColumnDefinition Width="*"/>
				</Grid.ColumnDefinitions>
				<Image Grid.Column="0" Source="$AppRoot\media\clock.png" Width="25" Height="25" Margin="0,1,6,0" VerticalAlignment="Top"/>
				<TextBlock x:Name="txtClock" Grid.Column="1" FontSize="18" FontWeight="Bold" Foreground="#65BF96" TextWrapping="Wrap" TextAlignment="Center" VerticalAlignment="Center"/>
			</Grid>
			</Grid>
		</StackPanel>
	</Grid>
	</Border>

	<!-- LIVE TIMELINE : MONITOR -->
	<StackPanel Margin="0,0,0,10">
	<!-- BEZEL -->
	<Border CornerRadius="22" Padding="14,14,14,4" BorderThickness="1.5">
		<Border.BorderBrush>
			<LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
				<GradientStop Color="#5C5C66" Offset="0.0"/>
				<GradientStop Color="#26262C" Offset="1.0"/>
			</LinearGradientBrush>
		</Border.BorderBrush>
		<Border.Background>
			<LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
				<GradientStop Color="#B33A3A42" Offset="0.0"/>
				<GradientStop Color="#B32A2A30" Offset="0.5"/>
				<GradientStop Color="#B3222226" Offset="1.0"/>
			</LinearGradientBrush>
		</Border.Background>
		<Grid>
			<Grid.RowDefinitions>
				<RowDefinition Height="*"/>
				<RowDefinition Height="Auto"/>
			</Grid.RowDefinitions>
			<!-- SCREEN -->
			<Border Grid.Row="0" CornerRadius="10" BorderThickness="3" BorderBrush="#0B0B0D">
				<Border.Background>
					<LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
						<GradientStop Color="#9E101014" Offset="0.0"/>
						<GradientStop Color="#9E17181D" Offset="1.0"/>
					</LinearGradientBrush>
				</Border.Background>
				<Grid>
				<!-- SCREEN CONTENT -->
				<StackPanel Orientation="Vertical" VerticalAlignment="Center" Margin="16,10,16,10">
				<!-- TITLE -->
				<Grid Margin="0,0,0,5">
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width="*" />     <!-- Title -->
						<ColumnDefinition Width="Auto" />  <!-- Sound button -->
						<ColumnDefinition Width="Auto" />  <!-- Refresh button -->
						<ColumnDefinition Width="Auto" />  <!-- Theme button -->
					</Grid.ColumnDefinitions>
					<!-- LEFT: TITLE -->
					<StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
						<TextBlock FontSize="19" FontWeight="SemiBold" Foreground="#99DEED" VerticalAlignment="Center">
							Commands Timeline ⫶☰
						</TextBlock>
					</StackPanel>
					<!-- MIDDLE: SOUND TOGGLE BUTTON -->
					<Button x:Name="btnRefreshTimeline" Grid.Column="1" Content=" ⭮ " Style="{StaticResource ModernButton}" VerticalAlignment="Center" HorizontalAlignment="Right" Padding="10,4">
						<!-- ToolTip Notification -->
						<Button.ToolTip>
					<ToolTip Background="#FF20232A" Foreground="#F4F4F5" BorderBrush="#FF22D3EE" Padding="13" Placement="Top" HasDropShadow="True">
						<TextBlock Text="Refresh Timeline" TextWrapping="Wrap" FontSize="17"/>
					</ToolTip>
				</Button.ToolTip>
					</Button>
					<!-- RIGHT: REFRESH BUTTON -->
					<Button x:Name="btnSound" Content="🔕" Style="{StaticResource ModernButton}" Grid.Column="2" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0" Padding="10,4"/>
					<!-- RIGHT: THEME COLOR BUTTON -->
					<Button x:Name="btnThemeColor" Grid.Column="3" Content="🎨" Style="{StaticResource ModernButton}" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0" Padding="10,4">
						<!-- ToolTip -->
						<Button.ToolTip>
					<ToolTip Background="#FF20232A" Foreground="#F4F4F5" BorderBrush="#FF22D3EE" Padding="13" Placement="Top" HasDropShadow="True">
						<TextBlock Text="Change Background Color" TextWrapping="Wrap" FontSize="17"/>
					</ToolTip>
				</Button.ToolTip>
					</Button>
				</Grid>
				<Border Height="1" Background="#444954" Margin="0,2,0,6"/>
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
							<TextBlock Text="⏮️ Prev  " FontWeight="SemiBold" Foreground="#71717A" FontSize="17" VerticalAlignment="Center"/>
							<TextBlock x:Name="txtPrev" Foreground="#C4B5FD" FontSize="17" Margin="0,0,10,0" TextTrimming="CharacterEllipsis"/>
						</StackPanel>
						<!-- CURRENT -->
						<StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,2">
							<TextBlock Text="🔁 Last  " FontWeight="SemiBold" Foreground="#71717A" FontSize="18" VerticalAlignment="Center"/>
							<TextBlock x:Name="txtCurrent" Foreground="#4ADE80" FontSize="18" FontWeight="Bold" Margin="0,0,10,0" TextTrimming="CharacterEllipsis"/>
						</StackPanel>
						<!-- NEXT -->
						<StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,2">
							<TextBlock Text="⏭ Next  " FontWeight="SemiBold" Foreground="#71717A" FontSize="17" VerticalAlignment="Center"/>
							<TextBlock x:Name="txtNext" Foreground="#60A5FA" FontSize="17" Margin="0,0,10,0" TextTrimming="CharacterEllipsis"/>
						</StackPanel>
						<TextBlock x:Name="txtStats" FontSize="20" Margin="0,10,0,0" HorizontalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center"/>
					</StackPanel>
					<!-- STATUS MESSAGE -->
					<TextBlock x:Name="txtLiveTimelineMessage" Visibility="Collapsed" Foreground="Gray" FontSize="28" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="27"/>
				</Grid>
				<Border Height="1" Background="#444954" Margin="0,4,0,6"/>
				<!-- Bottom Row -->
				<Grid Margin="0,0,0,0" VerticalAlignment="Center">
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
					<TextBlock x:Name="txtCountdown" Foreground="#FBBF24" FontSize="17" VerticalAlignment="Center" HorizontalAlignment="Left"/>
					</StackPanel>
					<!-- MODERN TEXT WATERMARK -->
					<TextBlock Grid.Column="1" Text="©️ 𝘼𝙪𝙩𝙤𝙋𝙞𝙡𝙤𝙩 𝘼𝙪𝙩𝙤𝙢𝙖𝙩𝙞𝙤𝙣 𝙎𝙮𝙨𝙩𝙚𝙢" FontSize="30" FontWeight="Bold" Foreground="#33FFFFFF"   VerticalAlignment="Center" HorizontalAlignment="Center" TextAlignment="Center" Opacity="0.3"/>
					<!-- BUTTON RIGHT -->
					<Button x:Name="btnTimelineList" Grid.Column="2" Content="📜 List" Style="{StaticResource ModernButton}" VerticalAlignment="Center" HorizontalAlignment="Right">
						<!-- ToolTip Notification -->
						<Button.ToolTip>
					<ToolTip Background="#FF20232A" Foreground="#F4F4F5" BorderBrush="#FF22D3EE" Padding="13" Placement="Top" HasDropShadow="True">
						<TextBlock Text="Timeline Commands (All Commands)" TextWrapping="Wrap" FontSize="17"/>
					</ToolTip>
				</Button.ToolTip>
					</Button>
					<Button x:Name="btnAction" Content="❶ Mod" Style="{StaticResource ModernButton}" Grid.Column="3" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0" Padding="10,4">
						<!-- ToolTip Notification -->
						<Button.ToolTip>
					<ToolTip Background="#FF20232A" Foreground="#F4F4F5" BorderBrush="#FF22D3EE" Padding="13" Placement="Top" HasDropShadow="True">
						<TextBlock Text="Use Mod 2 to 5 for Smallers Display" TextWrapping="Wrap" FontSize="17"/>
					</ToolTip>
				</Button.ToolTip>
					</Button>
				</Grid>
				</StackPanel>
				</Grid>
			</Border>
			<!-- BEZEL CHIN: brand + power LED -->
			<Grid Grid.Row="1" Height="26" Margin="8,0">
				<TextBlock Text="Dashboard Monitor" FontSize="12" FontWeight="Bold" Foreground="#71717A" HorizontalAlignment="Left" VerticalAlignment="Center"/>
				<Ellipse Width="10" Height="10" Fill="#34D399" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,6,0"/>
			</Grid>
		</Grid>
		</Border>
		</StackPanel>

        <!-- SCRIPT LAUNCHER -->
		<Border Style="{StaticResource Card}">
            <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock FontSize="19" FontWeight="SemiBold" Foreground="#C4E4A2" VerticalAlignment="Center">Script Launcher 🔰</TextBlock>
                </StackPanel>
                <Border Height="1" Background="#444954" Margin="0,0,0,8"/>
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
        <Border Style="{StaticResource Card}">
            <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock FontSize="19" FontWeight="SemiBold" Foreground="#E4BCC8" VerticalAlignment="Center">System Unit ⚙️</TextBlock>
                </StackPanel>
                <Border Height="1" Background="#444954" Margin="0,0,0,8"/>
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
					<Button x:Name="btnMedia" Content="🗂️ Archive" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnCamera" Content="🎥 Camera" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnData" Content="📂 Data Folder" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnSystem_Data" Content="🛢 System Data" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnScripts_Editor" Content="✏️ Scripts Edit" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnCommands_Editor" Content="✏️ Commands Edit" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnSettings" Content="⚙️ AutoPilot Settings" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnSettingsScripts" Content="⚙️ Scripts Settings" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnHideCmd" Content="⛔ Hide Cmd" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnShowCmd" Content="🗔 Show Cmd" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnProcessManager" Content="🛡️ Process Manager" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnVlc" Content="🎵 Vlc List" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnLock" Content="🔒 Lock Dashboard" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnOpenFolder" Content="🖱️ SetUp" Style="{StaticResource ModernButton}" />
					<Button x:Name="btnAbout" Content="ℹ️ AboutUs" Style="{StaticResource ModernButton}"/>
                </WrapPanel>
            </StackPanel>
        </Border>

        <!-- GRAPH LOAD COMMANDS -->
        <Border Style="{StaticResource Card}">
            <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock FontSize="19" FontWeight="SemiBold" Foreground="#A8E2C6" VerticalAlignment="Center">Graph Load Unit 📈</TextBlock>
                </StackPanel>
                <Border Height="1" Background="#444954" Margin="0,0,0,8"/>
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
        <Border Style="{StaticResource Card}">
            <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock FontSize="19" FontWeight="SemiBold" Foreground="#D2C4F0" VerticalAlignment="Center">Graph Temperature Unit 📈</TextBlock>
                </StackPanel>
                <Border Height="1" Background="#444954" Margin="0,0,0,8"/>
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
       <Border Style="{StaticResource Card}">
            <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock FontSize="19" FontWeight="SemiBold" Foreground="#E4D497" VerticalAlignment="Center">Graph Disk Unit 📈</TextBlock>
                </StackPanel>
                <Border Height="1" Background="#444954" Margin="0,0,0,8"/>
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
        <Border Style="{StaticResource Card}">
            <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock FontSize="19" FontWeight="SemiBold" Foreground="#E2BEDA" VerticalAlignment="Center">Net Traffic Unit 📊</TextBlock>
                </StackPanel>
                <Border Height="1" Background="#444954" Margin="0,0,0,8"/>
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
        <Border Style="{StaticResource Card}">
            <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock FontSize="19" FontWeight="SemiBold" Foreground="#94E0DA" VerticalAlignment="Center">Log File Unit 🗂️</TextBlock>
                </StackPanel>
                <Border Height="1" Background="#444954" Margin="0,0,0,8"/>
                <WrapPanel>
                    <Button x:Name="btnAutoPilot_Log" Content="🗃️ AutoPilot Log" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnMonitoring_Log" Content="🗃️ System Monitoring Log" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnTraffic_Log" Content="🗃️ Traffic Monitoring Log" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnData_Log" Content="🗃️ Data Log" Style="{StaticResource ModernButton}"/>
                    <Button x:Name="btnNetwork_Log" Content="🗃️ Net Log" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnUpdate_Log" Content="🗃️ Update Log" Style="{StaticResource ModernButton}"/>
					<Button x:Name="btnProcess_Log" Content="🗃️ Process Log" Style="{StaticResource ModernButton}"/>
                </WrapPanel>
            </StackPanel>
        </Border>
		
		<!-- MONITORING COMMANDS -->
        <Border Style="{StaticResource Card}">
            <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                    <TextBlock FontSize="19" FontWeight="SemiBold" Foreground="#E4BDC3" VerticalAlignment="Center">Monitoring Unit 🖥️</TextBlock>
                </StackPanel>
                <Border Height="1" Background="#444954" Margin="0,0,0,8"/>
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
		<Border Style="{StaticResource Card}" Margin="0,0,0,0" Padding="16,10">
		<Grid VerticalAlignment="Center">
			<Grid.ColumnDefinitions>
				<ColumnDefinition Width="Auto"/> <!-- LEFT: Version -->
				<ColumnDefinition Width="*"/>    <!-- Spacer left -->
				<ColumnDefinition Width="Auto"/> <!-- CENTER: logo + text -->
				<ColumnDefinition Width="*"/>    <!-- Spacer right -->
				<ColumnDefinition Width="Auto"/> <!-- RIGHT: All Rights -->
			</Grid.ColumnDefinitions>
			<!-- LEFT: VERSION -->
			<StackPanel Orientation="Horizontal" Grid.Column="0" HorizontalAlignment="Left" VerticalAlignment="Center">
				<TextBlock Text="⚙️ AutoPilot Dashboard" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center" Foreground="#E6E6E6"/>
			</StackPanel>
			<!-- CENTER (logo + text) -->
			<StackPanel Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Center" Grid.Column="2">
				<Image Source="$AppRoot\media\autopilot.ico" Width="28" Height="28" Margin="0,0,6,0"/>
				<TextBlock Text=" AutoPilot Automation System" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center" Foreground="#E6E6E6"/>
			</StackPanel>
			<!-- RIGHT -->
			<StackPanel Orientation="Horizontal" Grid.Column="4" HorizontalAlignment="Right" VerticalAlignment="Center">
				<TextBlock Text=" © All Rights Reserved" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center" Foreground="#E6E6E6"/>
			</StackPanel>
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
⚠️ Warning: With a REFRESH of AutoPilot, all processes will be STOPPED and Restarted!
Are you SURE you want to 🔄 REFRESH the System?
"@
    $title = "🔄 Refresh AutoPilot and Monitoring"
    $userChoice = Show-DarkConfirm -Message $msg -Title $title
    if ($userChoice) {
        Invoke-ManualCommand "/refresh"
    } else {
        Show-DarkWarning -Title "🔄 Refresh AutoPilot" -Message "AutoPilot refresh has been stopped by the user."
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
# Проверка на сите TextBlock-и
if(-not ($txtPrev -and $txtCurrent -and $txtNext -and $txtCountdown)) {
    Write-Host "ERROR: Some Timeline TextBlocks not found!"
    return
}
$imgStatus = $window.FindName("imgAutoPilotStatus")
# ===================== Mode Batton =====================
$btnAction = $window.FindName("btnAction")
$headerGrid = $window.FindName("headerGrid")
$clockElement = $window.FindName("clockElement")
$rightClockContainer = $window.FindName("rightClockContainer")
$centerClockContainer = $window.FindName("centerClockContainer")
$borderUptime = $Window.FindName("borderUptime")
$wpDashboard = $window.FindName("wpDashboard")
$txtStats = $window.FindName("txtStats")
# ===================== RefreshTimeline Batton =====================
$btnRefreshTimeline = $window.FindName("btnRefreshTimeline")
if ($btnRefreshTimeline) {
    $btnRefreshTimeline.Add_Click({
        try {
            # ================= ROTATE ANIMATION =================
            $rotateTransform = New-Object System.Windows.Media.RotateTransform
            $btnRefreshTimeline.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
            $btnRefreshTimeline.RenderTransform = $rotateTransform
            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
            $anim.From = 0
            $anim.To = 360
            $anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(400))
            $anim.AccelerationRatio = 0.3
            $anim.DecelerationRatio = 0.7
            $rotateTransform.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $anim)
            # ================= CLEANUP OLD POPUPS =================
            $parentGrid = $btnRefreshTimeline.Parent
            if ($parentGrid) {
                $oldPopups = $parentGrid.Children | Where-Object {
                    $_ -is [System.Windows.Controls.TextBlock] -and $_.Text -eq "Timeline Refreshed!"
                }
                foreach ($popup in $oldPopups) {
                    $parentGrid.Children.Remove($popup)
                }
            }
            # ================= CREATE FRESH POPUP =================
            $txtPopup = New-Object System.Windows.Controls.TextBlock
            $txtPopup.Text = "Timeline Refreshed!"
            $txtPopup.Foreground = [System.Windows.Media.Brushes]::LightGreen
            $txtPopup.FontWeight = "SemiBold"
            $txtPopup.FontSize = 28
            $txtPopup.Opacity = 1
            $txtPopup.VerticalAlignment = "Top"
            $txtPopup.HorizontalAlignment = "Center"
            $txtPopup.Margin = [System.Windows.Thickness]::new(0,10,0,0)
			# ================= CHECK AUTOPILOT STATUS =================
            if (-not (Get-AutoPilotRunning)) {
                $txtPopup.Text = "AutoPilot is STOPPED"
                $txtPopup.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(220, 120, 120)   # побледа црвена
			)
            } elseif (Test-Path $Global:pauseFlagPath) {
                $txtPopup.Text = "AutoPilot is PAUSED"
                $txtPopup.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(220, 190, 120)   # побледа жолта
			)
            } else {
                $txtPopup.Text = "Timeline Refreshed!"
                $txtPopup.Foreground = [System.Windows.Media.Brushes]::LightGreen
            }
            # Scale for zoom effect
            $scale = New-Object System.Windows.Media.ScaleTransform(0.5,0.5)
            $txtPopup.RenderTransform = $scale
            $txtPopup.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
            if ($parentGrid) { $parentGrid.Children.Add($txtPopup) }
            # ================= ANIMATIONS =================
            $moveUp = New-Object System.Windows.Media.Animation.ThicknessAnimation
            $moveUp.From = $txtPopup.Margin
            $moveUp.To   = [System.Windows.Thickness]::new(0,-55,0,0)
            $moveUp.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(1500))
            $txtPopup.BeginAnimation([System.Windows.FrameworkElement]::MarginProperty, $moveUp)

            $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
            $fade.From = 1
            $fade.To = 0
            $fade.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(600))
            $fade.BeginTime = [TimeSpan]::FromMilliseconds(600)
            $txtPopup.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)

            $zoom = New-Object System.Windows.Media.Animation.DoubleAnimation
            $zoom.From = 0.5
            $zoom.To   = 1
            $zoom.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(600))
            $txtPopup.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $zoom)
            $txtPopup.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $zoom)
            # ================= LOGIC =================
            Load-Timeline
            $window.Dispatcher.InvokeAsync({
                Update-TimelineDisplay
            }, [System.Windows.Threading.DispatcherPriority]::Render)

        } catch {
            Write-Host "Refresh error: $_"
        }
    })
}
# ===================== VLC RADIO LIST PANEL (PowerShell / WPF) =====================
$Global:VlcRadioJsonPath = Join-Path -Path $AppRoot -ChildPath "JSON\vlc_radio.json"
$Global:VlcListOwnerWindow = $window
function Set-VlcListStatus {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    $hex = switch ($Level) {
        'Success' { '#83E6A2' }
        'Warning' { '#FFC66D' }
        'Error'   { '#FF8585' }
        default   { '#D7DEE8' }
    }
    if ($Global:VlcListStatusText) {
        $Global:VlcListStatusText.Text = $Message
        $Global:VlcListStatusText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        )
    }
    if ($Level -eq 'Warning' -or $Level -eq 'Error') {
        Write-Host $Message -ForegroundColor $(if ($Level -eq 'Error') { 'Red' } else { 'Yellow' })
        try {
            if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
                Write-Log $Message
            }
            elseif (-not [string]::IsNullOrWhiteSpace($Global:logPath)) {
                $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Add-Content -LiteralPath $Global:logPath -Value "$stamp - $Message" -Encoding UTF8 -ErrorAction Stop
            }
        }
        catch {
            Write-Host "Could not write VLC panel status to log: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
}
# Test Vlc radio url
function Test-VlcRadioUrl {
    param([string]$Url)
    return (-not [string]::IsNullOrWhiteSpace($Url) -and $Url.Trim() -match '^https?://\S+$')
}
# Update the visible station numbering after add/update/delete.
function Update-VlcStationDisplayNumbers {
    if (-not $Global:VlcStationList) { return }
    for ($i = 0; $i -lt $Global:VlcStationList.Items.Count; $i++) {
        $stationItem = $Global:VlcStationList.Items[$i]
        if ($stationItem -is [System.Windows.Controls.ListBoxItem] -and $stationItem.Tag) {
            $stationTitle = [string]$stationItem.Tag.Title
            $url = [string]$stationItem.Tag.Url
            $stationItem.Content = "{0}. {1} - {2}" -f ($i + 1), $stationTitle, $url
        }
    }
}
# Load Vlc radio Json
function Load-VlcRadioJson {
    $Global:VlcStationList.Items.Clear()
    $Global:VlcJsonDamaged = $false
    $path = $Global:VlcRadioJsonPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Show-DarkWarning `
            -Title "⚠️ Error" `
            -Message "⛔ JSON file not found: $path.`nAdd stations and press Save JSON to create it."
        return
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw 'The JSON file is empty.'
        }
        $cfg = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        if ($null -eq $cfg -or $cfg -is [array]) {
            throw 'The JSON root must be an object.'
        }
        if ($cfg.PSObject.Properties.Name -notcontains 'RADIO_STATIONS') {
            throw 'The RADIO_STATIONS property is missing.'
        }
        if ($raw -match '(?is)"RADIO_STATIONS"\s*:\s*null' -or $cfg.RADIO_STATIONS -is [string]) {
            throw 'RADIO_STATIONS must be an array of URLs, not null or a single string.'
        }
        $items = @($cfg.RADIO_STATIONS)
        $titles = @()
        if ($cfg.PSObject.Properties.Name -contains 'RADIO_STATION_TITLES' -and $null -ne $cfg.RADIO_STATION_TITLES) {
            $titles = @($cfg.RADIO_STATION_TITLES)
        }
        $invalidCount = 0
        for ($sourceIndex = 0; $sourceIndex -lt $items.Count; $sourceIndex++) {
            $url = [string]$items[$sourceIndex]
            if (Test-VlcRadioUrl $url) {
                $stationNumber = $Global:VlcStationList.Items.Count + 1
                $stationTitle = ''
                if (($sourceIndex -lt $titles.Count) -and ($titles[$sourceIndex] -is [string])) {
                    $stationTitle = $titles[$sourceIndex].Trim()
                }
                if ([string]::IsNullOrWhiteSpace($stationTitle)) {
                    $stationTitle = "RadioStation $stationNumber"
                }
                $stationItem = New-Object System.Windows.Controls.ListBoxItem
                $stationItem.Tag = [PSCustomObject]@{
                    Title = $stationTitle
                    Url   = $url.Trim()
                }
                $stationItem.Content = "{0}. {1} - {2}" -f $stationNumber, $stationTitle, $url.Trim()
                [void]$Global:VlcStationList.Items.Add($stationItem)
            }
            else {
                $invalidCount++
            }
        }
        if ($invalidCount -gt 0) {
            Show-DarkWarning `
                -Title "⚠️ Warning" `
                -Message "⚠ Loaded $($Global:VlcStationList.Items.Count) valid station(s); ignored $invalidCount invalid entry/entries. Save JSON to update the file."
        }
        else {
            Show-DarkWarning `
                -Title "🎵 Vlc Play List" `
                -Message "Loaded $($Global:VlcStationList.Items.Count) station(s) from vlc_radio.json."
        }
    }
    catch {
        $Global:VlcJsonDamaged = $true
        $Global:VlcStationList.Items.Clear()
        Show-DarkWarning `
            -Title "⚠️ Error" `
            -Message "⛔ JSON file is damaged or incorrectly configured:`n$($_.Exception.Message)`nAdd the stations again and Save JSON. The original file will be backed up first."
    }
}
# Save Vlc radio json
function Save-VlcRadioJson {
    $path = $Global:VlcRadioJsonPath
    $stations = @()
    $titles = @()
    foreach ($item in $Global:VlcStationList.Items) {
        if ($item -is [System.Windows.Controls.ListBoxItem] -and $item.Tag) {
            $url = [string]$item.Tag.Url
            $stationTitle = [string]$item.Tag.Title
        }
        else {
            $url = [string]$item
            $stationTitle = ''
        }
        if (-not (Test-VlcRadioUrl $url)) {
            Set-VlcListStatus "Invalid URL found in the list. Correct it before saving." Error
            return
        }
        if ([string]::IsNullOrWhiteSpace($stationTitle)) {
            $stationTitle = "RadioStation $($stations.Count + 1)"
        }
        $stations += $url.Trim()
        $titles += $stationTitle.Trim()
    }
    try {
        $folder = Split-Path -Path $path -Parent
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $backupPath = "$path.bak"
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Copy-Item -LiteralPath $path -Destination $backupPath -Force -ErrorAction Stop
        }
        $document = [ordered]@{
            RADIO_STATIONS       = @($stations)
            RADIO_STATION_TITLES = @($titles)
        }
        $json = $document | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText(
            $path,
            ($json + [Environment]::NewLine),
            [System.Text.UTF8Encoding]::new($false)
        )
        $Global:VlcJsonDamaged = $false
        $backupNote = if (Test-Path -LiteralPath $backupPath -PathType Leaf) { ' Backup: vlc_radio.json.bak' } else { '' }
        Set-VlcListStatus "✅ Saved $($stations.Count) station(s) with titles to vlc_radio.json.$backupNote" Success
    }
    catch {
        Set-VlcListStatus "❌ Could not save vlc_radio.json: $($_.Exception.Message)" Error
    }
}
# New Vlc panel button
function New-VlcPanelButton {
    param(
        [string]$Text,
        [string]$Color = '#303A49'
    )
    $baseColor = [System.Windows.Media.Color](
        [System.Windows.Media.ColorConverter]::ConvertFromString($Color)
    )
    # Lighter hover color based on the original button color
    $hoverColor = [System.Windows.Media.Color]::FromArgb(
        255,
        [byte][Math]::Min(255, [Math]::Round($baseColor.R * 1.2)),
        [byte][Math]::Min(255, [Math]::Round($baseColor.G * 1.2)),
        [byte][Math]::Min(255, [Math]::Round($baseColor.B * 1.2))
    )
    $button = New-Object System.Windows.Controls.Button
    $button.Content = $Text
    $button.Background = [System.Windows.Media.SolidColorBrush]::new($baseColor)
    $button.Foreground = [System.Windows.Media.Brushes]::White
    $button.BorderThickness = [System.Windows.Thickness]::new(0)
    $button.Padding = [System.Windows.Thickness]::new(14, 8, 14, 8)
    $button.Margin = [System.Windows.Thickness]::new(5)
    $button.FontFamily = 'Segoe UI'
    $button.FontSize = 14
    $button.FontWeight = 'SemiBold'
    $button.MinHeight = 40
    $button.Cursor = [System.Windows.Input.Cursors]::Hand
    $button.HorizontalContentAlignment = 'Center'
    $button.VerticalContentAlignment = 'Center'
    $button.Focusable = $false
    $button.OverridesDefaultStyle = $true
    # Build a custom WPF template without XML/XAML
    $template = [System.Windows.Controls.ControlTemplate]::new(
        [System.Windows.Controls.Button]
    )
    $border = [System.Windows.FrameworkElementFactory]::new(
        [System.Windows.Controls.Border]
    )
    $border.SetValue(
        [System.Windows.Controls.Border]::CornerRadiusProperty,
        [System.Windows.CornerRadius]::new(8)
    )
    $backgroundBinding = [System.Windows.Data.Binding]::new('Background')
    $backgroundBinding.RelativeSource = [System.Windows.Data.RelativeSource]::new(
        [System.Windows.Data.RelativeSourceMode]::TemplatedParent
    )
    $border.SetBinding(
        [System.Windows.Controls.Border]::BackgroundProperty,
        $backgroundBinding
    )
    $paddingBinding = [System.Windows.Data.Binding]::new('Padding')
    $paddingBinding.RelativeSource = [System.Windows.Data.RelativeSource]::new(
        [System.Windows.Data.RelativeSourceMode]::TemplatedParent
    )
    $border.SetBinding(
        [System.Windows.Controls.Border]::PaddingProperty,
        $paddingBinding
    )
    $content = [System.Windows.FrameworkElementFactory]::new(
        [System.Windows.Controls.ContentPresenter]
    )
    $content.SetValue(
        [System.Windows.Controls.ContentPresenter]::ContentSourceProperty,
        'Content'
    )
    $content.SetValue(
        [System.Windows.FrameworkElement]::HorizontalAlignmentProperty,
        [System.Windows.HorizontalAlignment]::Center
    )
    $content.SetValue(
        [System.Windows.FrameworkElement]::VerticalAlignmentProperty,
        [System.Windows.VerticalAlignment]::Center
    )
    $border.AppendChild($content)
    $template.VisualTree = $border
    $button.Template = $template
    # Hover
    $button.Add_MouseEnter({
        param($sender, $e)
        $sender.Background = [System.Windows.Media.SolidColorBrush]::new(
            $hoverColor
        )
    }.GetNewClosure())
    # Restore original color
    $button.Add_MouseLeave({
        param($sender, $e)
        $sender.Background = [System.Windows.Media.SolidColorBrush]::new(
            $baseColor
        )
    }.GetNewClosure())
    return $button
}
# Button Vlc
$btnVlc = $window.FindName('btnVlc')
if ($btnVlc) {
    $btnVlc.Add_Click({
        # Reuse the panel if it is already open.
        if ($Global:VlcListWindow -and $Global:VlcListWindow.IsVisible) {
            if ($Global:VlcListWindow.WindowState -eq [System.Windows.WindowState]::Minimized) {
                $Global:VlcListWindow.WindowState = [System.Windows.WindowState]::Normal
            }
            $Global:VlcListWindow.Activate()
            return
        }
        $vlcWindow = New-Object System.Windows.Window
        $Global:VlcListWindow = $vlcWindow
        $vlcWindow.Title = 'VLC Radio Stations'
        $vlcWindow.Width = 980
        $vlcWindow.Height = 690
        $vlcWindow.MinWidth = 760
        $vlcWindow.MinHeight = 540
        $vlcWindow.WindowStartupLocation = 'CenterOwner'
        $vlcWindow.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb(35, 39, 46)
        )
        if ($Global:VlcListOwnerWindow) { $vlcWindow.Owner = $Global:VlcListOwnerWindow }
        $vlcWindow.Add_Closed({
            $Global:VlcListWindow = $null
            $Global:VlcStationList = $null
            $Global:VlcStationTitleBox = $null
            $Global:VlcStationUrlBox = $null
            $Global:VlcListStatusText = $null
        })
        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = [System.Windows.Thickness]::new(16)
        foreach ($height in @('Auto', 'Auto', 'Auto', '*', 'Auto')) {
            $row = New-Object System.Windows.Controls.RowDefinition
            if ($height -eq '*') {
                $row.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            }
            else {
                $row.Height = [System.Windows.GridLength]::Auto
            }
            $grid.RowDefinitions.Add($row)
        }
        # Title and description, matching the dark AutoPilot panel style.
        $header = New-Object System.Windows.Controls.StackPanel
        $header.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
        $title = New-Object System.Windows.Controls.TextBlock
        $title.Text = '🎵  VLC Radio Stations'
        $title.Foreground = [System.Windows.Media.Brushes]::White
        $title.FontSize = 27
        $title.FontWeight = 'Bold'
        $subtitle = New-Object System.Windows.Controls.TextBlock
        $subtitle.Text = 'Add unlimited station URLs and titles, select one to edit, then save the list to JSON.'
        $subtitle.Foreground = [System.Windows.Media.Brushes]::LightGray
        $subtitle.FontSize = 14
        $subtitle.Margin = [System.Windows.Thickness]::new(2, 5, 0, 0)
        $header.Children.Add($title)
        $header.Children.Add($subtitle)
        [System.Windows.Controls.Grid]::SetRow($header, 0)
        $grid.Children.Add($header)
        # Status message.
        $statusBorder = New-Object System.Windows.Controls.Border
        $statusBorder.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb(25, 27, 33)
        )
        $statusBorder.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb(54, 58, 68)
        )
        $statusBorder.BorderThickness = [System.Windows.Thickness]::new(1)
        $statusBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $statusBorder.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
        $statusBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
        $Global:VlcListStatusText = New-Object System.Windows.Controls.TextBlock
        $Global:VlcListStatusText.TextWrapping = 'Wrap'
        $Global:VlcListStatusText.FontSize = 14
        $Global:VlcListStatusText.Foreground = [System.Windows.Media.Brushes]::LightGray
        $statusBorder.Child = $Global:VlcListStatusText
        [System.Windows.Controls.Grid]::SetRow($statusBorder, 1)
        $grid.Children.Add($statusBorder)
        # Title and URL entry.
        $inputGrid = New-Object System.Windows.Controls.Grid
        $inputGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
        $labelColumn = New-Object System.Windows.Controls.ColumnDefinition
        $labelColumn.Width = [System.Windows.GridLength]::Auto
        $urlColumn = New-Object System.Windows.Controls.ColumnDefinition
        $urlColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $inputGrid.ColumnDefinitions.Add($labelColumn)
        $inputGrid.ColumnDefinitions.Add($urlColumn)
        $titleRow = New-Object System.Windows.Controls.RowDefinition
        $titleRow.Height = [System.Windows.GridLength]::Auto
        $inputGrid.RowDefinitions.Add($titleRow)
        $urlRow = New-Object System.Windows.Controls.RowDefinition
        $urlRow.Height = [System.Windows.GridLength]::Auto
        $inputGrid.RowDefinitions.Add($urlRow)
        $titleLabel = New-Object System.Windows.Controls.TextBlock
        $titleLabel.Text = 'Station Title:'
        $titleLabel.Foreground = [System.Windows.Media.Brushes]::White
        $titleLabel.FontSize = 15
        $titleLabel.VerticalAlignment = 'Center'
        $titleLabel.Margin = [System.Windows.Thickness]::new(0, 0, 12, 8)
        [System.Windows.Controls.Grid]::SetColumn($titleLabel, 0)
        [System.Windows.Controls.Grid]::SetRow($titleLabel, 0)
        $inputGrid.Children.Add($titleLabel)
        $Global:VlcStationTitleBox = New-Object System.Windows.Controls.TextBox
        $Global:VlcStationTitleBox.Height = 40
        $Global:VlcStationTitleBox.Padding = [System.Windows.Thickness]::new(10, 7, 10, 7)
        $Global:VlcStationTitleBox.FontSize = 15
        $Global:VlcStationTitleBox.FontFamily = 'Segoe UI'
        $Global:VlcStationTitleBox.Foreground = [System.Windows.Media.Brushes]::White
        $Global:VlcStationTitleBox.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb(25, 27, 33)
        )
        $Global:VlcStationTitleBox.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb(59, 63, 74)
        )
        $Global:VlcStationTitleBox.CaretBrush = [System.Windows.Media.Brushes]::White
        $Global:VlcStationTitleBox.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        [System.Windows.Controls.Grid]::SetColumn($Global:VlcStationTitleBox, 1)
        [System.Windows.Controls.Grid]::SetRow($Global:VlcStationTitleBox, 0)
        $inputGrid.Children.Add($Global:VlcStationTitleBox)
        $urlLabel = New-Object System.Windows.Controls.TextBlock
        $urlLabel.Text = 'Station URL:'
        $urlLabel.Foreground = [System.Windows.Media.Brushes]::White
        $urlLabel.FontSize = 15
        $urlLabel.VerticalAlignment = 'Center'
        $urlLabel.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
        [System.Windows.Controls.Grid]::SetColumn($urlLabel, 0)
        [System.Windows.Controls.Grid]::SetRow($urlLabel, 1)
        $inputGrid.Children.Add($urlLabel)
        $Global:VlcStationUrlBox = New-Object System.Windows.Controls.TextBox
        $Global:VlcStationUrlBox.Height = 40
        $Global:VlcStationUrlBox.Padding = [System.Windows.Thickness]::new(10, 7, 10, 7)
        $Global:VlcStationUrlBox.FontSize = 15
        $Global:VlcStationUrlBox.FontFamily = 'Segoe UI'
        $Global:VlcStationUrlBox.Foreground = [System.Windows.Media.Brushes]::White
        $Global:VlcStationUrlBox.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb(25, 27, 33)
        )
        $Global:VlcStationUrlBox.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb(59, 63, 74)
        )
        $Global:VlcStationUrlBox.CaretBrush = [System.Windows.Media.Brushes]::White
        [System.Windows.Controls.Grid]::SetColumn($Global:VlcStationUrlBox, 1)
        [System.Windows.Controls.Grid]::SetRow($Global:VlcStationUrlBox, 1)
        $inputGrid.Children.Add($Global:VlcStationUrlBox)
        [System.Windows.Controls.Grid]::SetRow($inputGrid, 2)
        $grid.Children.Add($inputGrid)
        # Station list.
        $Global:VlcStationList = New-Object System.Windows.Controls.ListBox
        $Global:VlcStationList.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb(25, 27, 33)
        )
        $Global:VlcStationList.Foreground = [System.Windows.Media.Brushes]::White
        $Global:VlcStationList.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb(54, 58, 68)
        )
        $Global:VlcStationList.BorderThickness = [System.Windows.Thickness]::new(1)
        $Global:VlcStationList.FontFamily = 'Segoe UI'
        $Global:VlcStationList.FontSize = 16
        $Global:VlcStationList.Padding = [System.Windows.Thickness]::new(5)
        $Global:VlcStationList.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
        [System.Windows.Controls.Grid]::SetRow($Global:VlcStationList, 3)
        $grid.Children.Add($Global:VlcStationList)
        # Action buttons.
        $buttonPanel = New-Object System.Windows.Controls.WrapPanel
        $buttonPanel.HorizontalAlignment = 'Center'
        $buttonPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)
        [System.Windows.Controls.Grid]::SetRow($buttonPanel, 4)
        $addButton = New-VlcPanelButton '➕ Add URL' '#18794E'
        $updateButton = New-VlcPanelButton '✏️ Update selected' '#245DA8'
        $deleteButton = New-VlcPanelButton '🗑 Delete selected' '#8C3434'
        $deleteAllButton = New-VlcPanelButton '🧹 Delete all' '#963E32'
        $saveButton = New-VlcPanelButton '💾 Save JSON' '#8C671D'
        $closeButton = New-VlcPanelButton '✖ Close' '#3A3A3A'
        foreach ($button in @($addButton, $updateButton, $deleteButton, $deleteAllButton, $saveButton, $closeButton)) {
            $buttonPanel.Children.Add($button)
        }
        $grid.Children.Add($buttonPanel)
        # Select a station to copy its title and URL into the edit fields.
        $Global:VlcStationList.Add_SelectionChanged({
            $selected = $Global:VlcStationList.SelectedItem
            if ($selected -is [System.Windows.Controls.ListBoxItem] -and $selected.Tag) {
                $Global:VlcStationTitleBox.Text = [string]$selected.Tag.Title
                $Global:VlcStationUrlBox.Text = [string]$selected.Tag.Url
            }
        })
        $addButton.Add_Click({
            $url = $Global:VlcStationUrlBox.Text.Trim()
            if (-not (Test-VlcRadioUrl $url)) {
                Set-VlcListStatus 'Enter a valid HTTP or HTTPS radio URL.' Error
                return
            }
            $stationTitle = $Global:VlcStationTitleBox.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($stationTitle)) {
                $stationTitle = "RadioStation $($Global:VlcStationList.Items.Count + 1)"
            }
            $stationItem = New-Object System.Windows.Controls.ListBoxItem
            $stationItem.Tag = [PSCustomObject]@{
                Title = $stationTitle
                Url   = $url
            }
            $stationItem.Content = "{0}. {1} - {2}" -f ($Global:VlcStationList.Items.Count + 1), $stationTitle, $url
            [void]$Global:VlcStationList.Items.Add($stationItem)
            Update-VlcStationDisplayNumbers
            $Global:VlcStationList.SelectedIndex = $Global:VlcStationList.Items.Count - 1
            Set-VlcListStatus 'Station added to the list. Press Save JSON to write your changes.' Success
        })
        $updateButton.Add_Click({
            $index = $Global:VlcStationList.SelectedIndex
            if ($index -lt 0) {
                Set-VlcListStatus 'Select a station to update first.' Warning
                return
            }
            $url = $Global:VlcStationUrlBox.Text.Trim()
            if (-not (Test-VlcRadioUrl $url)) {
                Set-VlcListStatus 'Enter a valid HTTP or HTTPS radio URL.' Error
                return
            }
            $stationTitle = $Global:VlcStationTitleBox.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($stationTitle)) {
                $stationTitle = "RadioStation $($index + 1)"
            }
            $stationItem = New-Object System.Windows.Controls.ListBoxItem
            $stationItem.Tag = [PSCustomObject]@{
                Title = $stationTitle
                Url   = $url
            }
            $stationItem.Content = "{0}. {1} - {2}" -f ($index + 1), $stationTitle, $url
            $Global:VlcStationList.Items.RemoveAt($index)
            $Global:VlcStationList.Items.Insert($index, $stationItem)
            Update-VlcStationDisplayNumbers
            $Global:VlcStationList.SelectedIndex = $index
            Set-VlcListStatus 'Selected station updated in the list. Press Save JSON to write your changes.' Success
        })
        $deleteButton.Add_Click({
            $index = $Global:VlcStationList.SelectedIndex
            if ($index -lt 0) {
                Set-VlcListStatus 'Select a station to delete first.' Warning
                return
            }
            $selected = $Global:VlcStationList.SelectedItem
            $answer = [System.Windows.MessageBox]::Show(
                $Global:VlcListWindow,
                "Delete this radio station?`n`n$($selected.Content)",
                'Delete radio station',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
                $Global:VlcStationList.Items.RemoveAt($index)
                Update-VlcStationDisplayNumbers
                $Global:VlcStationTitleBox.Clear()
                $Global:VlcStationUrlBox.Clear()
                Set-VlcListStatus 'Station removed from the list. Press Save JSON to write your changes.' Success
            }
        })
        $deleteAllButton.Add_Click({
            if ($Global:VlcStationList.Items.Count -eq 0) {
                Set-VlcListStatus 'The station list is already empty.' Info
                return
            }
            $answer = [System.Windows.MessageBox]::Show(
                $Global:VlcListWindow,
                'Delete ALL radio stations from the list?',
                'Delete all stations',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
                $Global:VlcStationList.Items.Clear()
                $Global:VlcStationTitleBox.Clear()
                $Global:VlcStationUrlBox.Clear()
                Set-VlcListStatus 'All stations removed from the list. Press Save JSON to save an empty RADIO_STATIONS array.' Warning
            }
        })
        $saveButton.Add_Click({ Save-VlcRadioJson })
        $closeButton.Add_Click({ $Global:VlcListWindow.Close() })
        $vlcWindow.Content = $grid
        Load-VlcRadioJson
        $vlcWindow.ShowDialog() | Out-Null
    })
}
else {
    Write-Host 'VLC list button btnVlc was not found in the main window.' -ForegroundColor Yellow
}
# ===================== Network Panel =====================
$txtInternet    = $window.FindName("txtInternet")
$borderInternet = $window.FindName("borderInternet")
function Update-NetworkPanel {
    try {
        $adapters = @(
            Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq "Up" }
        )
        $wifi = $adapters |
            Where-Object {
                $_.NdisPhysicalMedium -eq 9 -or
                $_.Name -match 'Wi-?Fi|Wireless|WLAN' -or
                $_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN'
            } |
            Select-Object -First 1
        $ethernet = $adapters |
            Where-Object {
                $_.NdisPhysicalMedium -eq 14 -or
                $_.Name -match 'Ethernet' -or
                $_.InterfaceDescription -match 'Ethernet'
            } |
            Select-Object -First 1
        if ($wifi) {
            $profile = Get-NetConnectionProfile `
                -InterfaceIndex $wifi.ifIndex `
                -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($profile) {
                $ssid = $profile.Name
                $txtInternet.Text = "📶 $ssid"
                $borderInternet.Background =
                [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.Color]::FromRgb(50, 173, 54)
                )
            return
            }
        }
        if ($ethernet) {
            $txtInternet.Text = "🖥️ $($ethernet.Name)"
            $borderInternet.Background =
                [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.Color]::FromRgb(11, 146, 150)
                )
            return
        }
        $txtInternet.Text = "🚫 Disconnected"
        $borderInternet.Background =
            [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromRgb(190, 55, 55)
            )
    }
    catch {
        $txtInternet.Text = "🚫 Disconnected"
        $borderInternet.Background =
            [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromRgb(190, 55, 55)
            )

        Write-Log "Network panel error: $_"
    }
}
# Initial network status
Update-NetworkPanel
# Refresh network status every 3 seconds
$networkTimer = New-Object System.Windows.Threading.DispatcherTimer
$networkTimer.Interval = [TimeSpan]::FromSeconds(55)
$networkTimer.Add_Tick({
    Update-NetworkPanel
})
$networkTimer.Start()
# Stop timer when window closes
$window.Add_Closed({
    $networkTimer.Stop()
})
# ===================== Sound ON/OFF Batton =====================
$btnSound = $window.FindName("btnSound")
# default: muted
$Global:SoundEnabled = $false
$btnSound.Content = "🔕"
# create modern dark tooltip
$tooltip = New-Object System.Windows.Controls.ToolTip
# create a solid color brush for dark background
$bgColor = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(32,35,42))
$tooltip.Background = $bgColor
$tooltip.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(34,211,238))
$tooltip.Foreground = [System.Windows.Media.Brushes]::White
$tooltip.Padding = [System.Windows.Thickness]::new(13)
$tooltip.HasDropShadow = $true
$tooltip.Placement = "Top"
# create text block for tooltip
$textBlock = New-Object System.Windows.Controls.TextBlock
$textBlock.Text = "Sound is OFF"
$textBlock.FontSize = 17
$textBlock.TextWrapping = "Wrap"
$tooltip.Content = $textBlock
$btnSound.ToolTip = $tooltip
# prepare sound player
$player = New-Object System.Media.SoundPlayer "$AppRoot\media\sound.wav"
$player.Load()
# helper function for status popup
function Show-SoundStatusPopup {
    param ([bool]$SoundOn)
    $parentGrid = $btnSound.Parent
    if (-not $parentGrid) { return }
    # remove old sound popups
    $oldPopups = $parentGrid.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] -and $_.Tag -eq "SoundPopup" }
    foreach ($popup in $oldPopups) { $parentGrid.Children.Remove($popup) }
    # create new popup
    $txtPopup = New-Object System.Windows.Controls.TextBlock
    $txtPopup.Tag = "SoundPopup"
    $txtPopup.Text = if ($SoundOn) { "Sound is ON" } else { "Sound is OFF" }
    $txtPopup.Foreground = if ($SoundOn) {
    [System.Windows.Media.Brushes]::LightGreen
	} else {
		[System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(220, 120, 120)
		)
	}
    $txtPopup.FontWeight = "SemiBold"
    $txtPopup.FontSize = 28
    $txtPopup.Opacity = 1
    $txtPopup.VerticalAlignment = "Top"
    $txtPopup.HorizontalAlignment = "Center"
    $txtPopup.Margin = [System.Windows.Thickness]::new(0,10,0,0)
    # zoom effect
    $scale = New-Object System.Windows.Media.ScaleTransform(0.5,0.5)
    $txtPopup.RenderTransform = $scale
    $txtPopup.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    $parentGrid.Children.Add($txtPopup)
    # animations
    $moveUp = New-Object System.Windows.Media.Animation.ThicknessAnimation
    $moveUp.From = $txtPopup.Margin
    $moveUp.To   = [System.Windows.Thickness]::new(0,-55,0,0)
    $moveUp.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(1500))
    $txtPopup.BeginAnimation([System.Windows.FrameworkElement]::MarginProperty, $moveUp)
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fade.From = 1
    $fade.To = 0
    $fade.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(600))
    $fade.BeginTime = [TimeSpan]::FromMilliseconds(600)
    $txtPopup.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
    $zoom = New-Object System.Windows.Media.Animation.DoubleAnimation
    $zoom.From = 0.5
    $zoom.To   = 1
    $zoom.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(600))
    $txtPopup.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $zoom)
    $txtPopup.RenderTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $zoom)
}
# button click toggle
$btnSound.Add_Click({
    if ($Global:SoundEnabled) {
        $Global:SoundEnabled = $false
        $btnSound.Content = "🔕"
        $textBlock.Text = "Sound is OFF"
    } else {
        $Global:SoundEnabled = $true
        $btnSound.Content = " 🕭 "
        $textBlock.Text = "Sound is ON"
    }
    # show status popup in color
    Show-SoundStatusPopup -SoundOn $Global:SoundEnabled
})

# ===================== Theme Color Button =====================
$btnThemeColor = $window.FindName("btnThemeColor")
$Global:ThemeColors = @("#0F0F0F","#22304A","#2B3D34","#44355B","#552B2B","#5A4632","#244B52","#3D3D3D","#23272F","#1F2937","#283149","#4C566A","#4B3621","#22313F","#919191","#006100","#15777A","#151D7A","#9E9913","#821175","#4B1182","#A30F0F","#0F47BF","#3D6E3D","#1A1C22")
$Global:CurrentThemeColor = 0
function Set-WindowBackgroundColor {
    param([string]$HexColor)
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Width = 1700
    $grid.Height = 900
    $bgRect = New-Object System.Windows.Shapes.Rectangle
    $bgRect.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($HexColor)
    $overlayRect = New-Object System.Windows.Shapes.Rectangle
    $overlayRect.Opacity = 0.38
    $drawingBrush = New-Object System.Windows.Media.DrawingBrush
    $drawingBrush.Stretch = "None"
    $drawingBrush.TileMode = "None"
    $drawingBrush.AlignmentX = "Center"
    $drawingBrush.AlignmentY = "Center"
    $imageDrawing = New-Object System.Windows.Media.ImageDrawing
    $imageDrawing.Rect = [System.Windows.Rect]::new(0,0,555,555)
    $img = New-Object System.Windows.Media.Imaging.BitmapImage
    $img.BeginInit()
    $img.UriSource = [Uri]"$AppRoot\media\autopilot.ico"
    $img.EndInit()
    $imageDrawing.ImageSource = $img
    $drawingBrush.Drawing = $imageDrawing
    $overlayRect.Fill = $drawingBrush
    $grid.Children.Add($bgRect)
    $grid.Children.Add($overlayRect)
    $visualBrush = New-Object System.Windows.Media.VisualBrush
    $visualBrush.Visual = $grid
    $window.Background = $visualBrush
}
# popup helper
function Show-ThemePopup {
    param([string]$ColorHex)
    $parentGrid = $btnThemeColor.Parent
    if (-not $parentGrid) { return }
    $oldPopups = $parentGrid.Children | Where-Object {
        $_ -is [System.Windows.Controls.TextBlock] -and $_.Tag -eq "ThemePopup"
    }
    foreach ($popup in $oldPopups) {
        $parentGrid.Children.Remove($popup)
    }
    $txtPopup = New-Object System.Windows.Controls.TextBlock
    $txtPopup.Tag = "ThemePopup"
    $txtPopup.Text = "Theme Changed"
    $txtPopup.Foreground = [System.Windows.Media.Brushes]::LightSkyBlue
    $txtPopup.FontWeight = "SemiBold"
    $txtPopup.FontSize = 28
    $txtPopup.Opacity = 1
    $txtPopup.VerticalAlignment = "Top"
    $txtPopup.HorizontalAlignment = "Center"
    $txtPopup.Margin = [System.Windows.Thickness]::new(0,10,0,0)
    $scale = New-Object System.Windows.Media.ScaleTransform(0.5,0.5)
    $txtPopup.RenderTransform = $scale
    $txtPopup.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    $parentGrid.Children.Add($txtPopup)
    $moveUp = New-Object System.Windows.Media.Animation.ThicknessAnimation
    $moveUp.From = $txtPopup.Margin
    $moveUp.To   = [System.Windows.Thickness]::new(0,-55,0,0)
    $moveUp.Duration = [System.Windows.Duration]::new(
        [TimeSpan]::FromMilliseconds(1500)
    )
    $txtPopup.BeginAnimation(
        [System.Windows.FrameworkElement]::MarginProperty,
        $moveUp
    )
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fade.From = 1
    $fade.To = 0
    $fade.Duration = [System.Windows.Duration]::new(
        [TimeSpan]::FromMilliseconds(600)
    )
    $fade.BeginTime = [TimeSpan]::FromMilliseconds(600)
    $txtPopup.BeginAnimation(
        [System.Windows.UIElement]::OpacityProperty,
        $fade
    )
    $zoom = New-Object System.Windows.Media.Animation.DoubleAnimation
    $zoom.From = 0.5
    $zoom.To   = 1
    $zoom.Duration = [System.Windows.Duration]::new(
        [TimeSpan]::FromMilliseconds(600)
    )
    $txtPopup.RenderTransform.BeginAnimation(
        [System.Windows.Media.ScaleTransform]::ScaleXProperty,
        $zoom
    )
    $txtPopup.RenderTransform.BeginAnimation(
        [System.Windows.Media.ScaleTransform]::ScaleYProperty,
        $zoom
    )
}
# button click
$btnThemeColor.Add_Click({
    $randomColor = Get-Random -InputObject $Global:ThemeColors
    Set-WindowBackgroundColor -HexColor $randomColor
    Show-ThemePopup -ColorHex $randomColor
})

# ===================== Function Update UI - AutoPilot =====================
function Update-AutoPilotStatusUI {
    $autoPilotRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\AutoPilot.ps1")
    }
    if ($autoPilotRunning) {
        $txtAutoPilotStatus.Text = "▶️ ACTIVE"
        $borderAutoPilotStatus.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(56,142,104)))
    } else {
        $txtAutoPilotStatus.Text = "⏹️ STOPPED"
        $borderAutoPilotStatus.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(201,76,76)))
    }
}

# ===================== Button Start =====================
$btnStartAutoPilot.Add_Click({
    $editorRunning = Get-Process -Name "ScriptsEditor","CommandsEditor" -ErrorAction SilentlyContinue
    if ($editorRunning) {
        Show-DarkWarning -Title "⚠️ Editor Active" -Message "To start AutoPilot, the ✏️ EDIT block must be Closed first (Commands, Scripts)!"
        return
    }
    Invoke-ManualCommand "/start-autopilot"
    Update-AutoPilotStatusUI
})

# ===================== Button Stop =====================
$btnStopAutoPilot.Add_Click({
    $msg = "⚠️ Warning: AutoPilot in the moment it may be RUNNING! Are you SURE you want to ⏹️ STOP the AutoPilot process?"
    $title = "⏹️ Stopping AutoPilot"
    $userChoice = Show-DarkConfirm -Message $msg -Title $title
    if ($userChoice) {
        Invoke-ManualCommand "/stop-autopilot"
        Update-AutoPilotStatusUI
    } else {
        Show-DarkWarning -Title "⏹️ AutoPilot STOP" -Message "Stopping AutoPilot has been stopped by the user."
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
        $txtSystemStatus.Text = "▶️ ACTIVE"
        $borderSystemStatus.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(56,142,104)))
    } else {
        $txtSystemStatus.Text = "⏹️ STOPPED"
        $borderSystemStatus.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(201,76,76)))
    }
}

# ===================== Function Update UI - Traffic =====================
function Update-TrafficStatusUI {
    $trafficRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\TrafficMonitorWorker.ps1")
    }
    if ($trafficRunning) {
        $txtTrafficStatus.Text = "▶️ ACTIVE"
        $borderTrafficStatus.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(56,142,104)))
    } else {
        $txtTrafficStatus.Text = "⏹️ STOPPED"
        $borderTrafficStatus.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(201,76,76)))
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
	if (-not (Show-AbortWarning -Title "⚛️ AutoPilot Pause" -Message "Using ⏸️ Pause will stop all AUTOMATIC processes in AutoPilot!`nAutoPilot will 🔄 Restart when you ⏯️ Resume!")) {
		return
	}
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
		$txtPauseState.Foreground = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(201,76,76))) 
        $txtPauseButton.Text = "Pause ⏸️"
        $btnPauseAutoPilot.Background = [System.Windows.Media.Brushes]::Gray
        return
    }
    if (Test-Path $Global:pauseFlagPath) {
        # PAUSED
        $txtPauseButton.Text = "Resume ⏯️"
        $btnPauseAutoPilot.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(206,167,84)))
        $txtPauseState.Text = "PAUSED"
        $txtPauseState.Foreground = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(206,167,84)))
    } else {
        # RUNNING
        $txtPauseButton.Text = "Pause ⏸️"
        $btnPauseAutoPilot.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(56,142,104)))
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
        Show-DarkWarning -Title "⚠️ AutoPilot is Active" -Message "AutoPilot is currently Running! The Scripts Editor works only when AutoPilot is ⏹️ STOPPED."
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
		-DisplayName "Scripts Editor" `
		-StartTitle "📝 Scripts Editor Started" `
		-StartMessage "✏️ Edit Scripts Commands!"
})

# ===================== AutoPilot COMMANDS EDITOR =====================
$btnCommands_Editor.Add_Click({
    $exeName = "CommandsEditor.exe"
    $processName = "CommandsEditor"
    $autoPilotRunning = Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -like "*AutoPilot.ps1*" }
    if ($autoPilotRunning) {
        Show-DarkWarning -Title "⚠️ AutoPilot is Active" -Message "AutoPilot is currently Running! The Commands Editor works only when AutoPilot is ⏹️ STOPPED."
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
		-DisplayName "Commands Editor" `
		-StartTitle "📝 Commands Editor Started" `
		-StartMessage "✏️ Edit Automation Commands!"
})

# ===================== AutoPilot Media Bot ENABLED / DISABLED =====================
function Update-BotStatusUI {
    try {
        $jsonPath = "$AppRoot\JSON\settings.json"
        if (-not (Test-Path $jsonPath)) { return }
        $settings = Get-Content $jsonPath | ConvertFrom-Json
        # --- AutoPilot Bot ---
        if ($settings.AUTOPILOT_TELEGRAM_ENABLED) {
            $txtAutoPilotBot.Text = "✔️ ENABLED"
            $borderAutoPilotBot.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(56,142,104)))
        } else {
            $txtAutoPilotBot.Text = "❌ DISABLED"
            $borderAutoPilotBot.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(201,76,76)))
        }
        # --- Media Bot ---
        if ($settings.MEDIA_TELEGRAM_ENABLED) {
            $txtMediaBot.Text = "✔️ ENABLED"
            $borderMediaBot.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(56,142,104)))
        } else {
            $txtMediaBot.Text = "❌ DISABLED"
            $borderMediaBot.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(201,76,76)))
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
            $txtMode.Text = "🛡️ TEST MODE"
            $borderMode.Background = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(1, 107, 83)
			)
        } else {
            # ===== PRO MODE =====
            $txtMode.Text = "⚡ PRO MODE"
            $borderMode.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(48,94,227)))
        }
    }
    catch {
        $txtMode.Text = "⚠️ ERROR"
        $borderMode.Background = ([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(201,76,76)))
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
		$color = [System.Windows.Media.Color]::FromRgb(38,41,48)
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
        $lblTitle.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(228,228,231))
        $lblTitle.Margin = [System.Windows.Thickness]::new(0,0,0,10)
        $stack.Children.Add($lblTitle)

        # Version
		$lblVersion = New-Object System.Windows.Controls.TextBlock
		$lblVersion.FontSize = 17
		$lblVersion.Foreground = [System.Windows.Media.Brushes]::White
		$lblVersion.Margin = [System.Windows.Thickness]::new(0,0,0,5)
		# Bold Label
		$runLabel = New-Object System.Windows.Documents.Run("🏷️ Version: ")
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
		$runLabel = New-Object System.Windows.Documents.Run("✔️ Realized: ")
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
		$runLabel = New-Object System.Windows.Documents.Run("📝 Author: ")
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
		$runLabel = New-Object System.Windows.Documents.Run("🌐 GitHub Profile: ")
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
	$lblFooter.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(161,161,170))
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

# ===================== BUTTON LOCK SYSTEM =====================
$btnLock = $window.FindName("btnLock")
$btnLock.Add_Click({

    function Show-LockPopup {
        $lockWindow = New-Object System.Windows.Window
        $lockWindow.Title = "AutoPilot Dashboard Password Protect"
        $lockWindow.Width = 500
        $lockWindow.Height = 530
        $lockWindow.WindowStartupLocation = "CenterScreen"
        $lockWindow.ResizeMode = "NoResize"
        $lockWindow.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(38,41,48))

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Margin = [System.Windows.Thickness]::new(20)
        $stack.VerticalAlignment = "Top"

        # Заглавие
        $lblTitle = New-Object System.Windows.Controls.TextBlock
        $lblTitle.Text = "AutoPilot Dashboard Password Protect"
        $lblTitle.FontSize = 22
        $lblTitle.FontWeight = "Bold"
        $lblTitle.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(228,228,231))
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
        $pwdBox.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(34,37,44))
        $pwdBox.Foreground = [System.Windows.Media.Brushes]::White
        $pwdBox.Margin = [System.Windows.Thickness]::new(0,0,10,0)
        $pwdRow.Children.Add($pwdBox)

        # TextBox (прикажана лозинка)
        $txtBox = New-Object System.Windows.Controls.TextBox
        $txtBox.Width = 250
        $txtBox.FontSize = 18
        $txtBox.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(34,37,44))
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
        $lblFooter.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(161,161,170))
        $lblFooter.HorizontalAlignment = "Center"
        $lblFooter.Text = "AutoPilot Dashboard Password Protect "
        $stackBottom.Children.Add($lblFooter)
		
		# --- Додавање на две нови линии текст пред постоечкиот lblFooter ---
		$lblDescription1 = New-Object System.Windows.Controls.TextBlock
		$lblDescription1.FontSize = 13
		$lblDescription1.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(144,238,144)) # светло зелена
		$lblDescription1.HorizontalAlignment = "Left"
		$lblDescription1.Margin = [System.Windows.Thickness]::new(0,20,0,5)  # горе и долу маргина
		$lblDescription1.Text = "🔑 ON Lock: When AutoPilot Dashboard starts, a password is required!"
		$stackBottom.Children.Add($lblDescription1) | Out-Null

		$lblDescription2 = New-Object System.Windows.Controls.TextBlock
		$lblDescription2.FontSize = 13
		$lblDescription2.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(144,238,144)) # светло зелена
		$lblDescription2.HorizontalAlignment = "Left"
		$lblDescription2.Margin = [System.Windows.Thickness]::new(0,5,0,5)  # горе и долу маргина
		$lblDescription2.Text = "❌ OFF Lock: AutoPilot Dashboard starts without a password!"
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
    # ротирање 1 → 2 → 3 → 4 → 5 → 1
    $Global:mode++
    if ($Global:mode -gt 5) { $Global:mode = 1 }
    # 🔹 РЕСЕТИРАЊЕ НА СТАНДАРДНИТЕ ВРЕДНОСТИ (За Мод 1, 2 и 3)
    $txtPrev.FontSize = 17 
    $txtCurrent.FontSize = 18
    $txtNext.FontSize = 17
    $txtPrev.Margin = "0,0,10,0"
    $txtCurrent.Margin = "0,0,10,0"
    $txtNext.Margin = "0,0,10,0"
    # ===================== MODE 2 =====================
    if ($Global:mode -eq 2) {
        $btnAction.Content = "❷ Mod"
        $headerGrid.Margin = "0,0,0,5"
        $Global:popupMaxHeight = 855
        $Global:statusMaxHeight = 855
    }
    # ===================== MODE 3 =====================
    elseif ($Global:mode -eq 3) {
        $btnAction.Content = "❸ Mod"
        $headerGrid.Margin = "0,0,0,5"
        $Global:popupMaxHeight = 655
        $Global:statusMaxHeight = 655
        $Global:popupItemWidth = 155 
        $Global:popupItemHeight = 55
        $wpDashboard.ItemWidth = $Global:popupItemWidth
        $wpDashboard.ItemHeight = $Global:popupItemHeight
    }
    # ===================== MODE 4 =====================
    elseif ($Global:mode -eq 4) { 
        $btnAction.Content = "❹ Mod" 
        $headerGrid.Margin = "0,0,0,5" 
        $Global:popupMaxHeight = 655 
        $Global:statusMaxHeight = 655 
        $Global:popupItemWidth = 155 
        $Global:popupItemHeight = 55 
        $wpDashboard.ItemWidth = $Global:popupItemWidth 
        $wpDashboard.ItemHeight = $Global:popupItemHeight
        $txtPrev.FontSize = 16 
        $txtCurrent.FontSize = 16
        $txtNext.FontSize = 16
        $txtPrev.Margin = "0,1,10,0"
        $txtCurrent.Margin = "0,1,10,0"
        $txtNext.Margin = "0,1,10,0"
    }	
    # ===================== MODE 5 =====================
    elseif ($Global:mode -eq 5) { 
        $btnAction.Content = "❺ Mod" 
        $headerGrid.Margin = "0,0,0,5" 
        $Global:popupMaxHeight = 655 
        $Global:statusMaxHeight = 655 
        $Global:popupItemWidth = 155 
        $Global:popupItemHeight = 55 
        $wpDashboard.ItemWidth = $Global:popupItemWidth 
        $wpDashboard.ItemHeight = $Global:popupItemHeight
        $txtPrev.FontSize = 15 
        $txtCurrent.FontSize = 15
        $txtNext.FontSize = 15
        $txtPrev.Margin = "0,2,10,0"
        $txtCurrent.Margin = "0,2,10,0"
        $txtNext.Margin = "0,2,10,0"
    }
    # ===================== MODE 1 =====================
    else {
        $btnAction.Content = "❶ Mod"
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
# ===================== GLOBAL PATCH (ADDED) =====================
$Global:TimelineListWindow = $null
$Global:TimelineListBox = $null
$Global:TimelineRun_Total = $null
$Global:TimelineRun_Complete = $null
$Global:TimelineRun_Remaining = $null
$Global:RefreshSpinAngle = 0
# ===================== TimelineList =====================
function Update-TimelineList {
    param([System.Windows.Controls.ListBox]$listBox)
    $listBox.Items.Clear()
    $now = Get-Date
    $nowTime = Get-Date -Hour $now.Hour -Minute $now.Minute -Second $now.Second
    $index = if($global:timeline) { ($global:timeline | Where-Object { $_.Time -le $nowTime }).Count - 1 } else { -1 }
    if($index -lt 0){ $index = 0 }
	# ===== AUTOPILOT STATUS =====
	$autoPilotRunning = Get-CimInstance Win32_Process | Where-Object {
		$_.Name -eq "powershell.exe" -and
		$_.CommandLine -match [regex]::Escape("$AppRoot\AutoPilot.ps1")
	}
    $autoPilotRunning = [bool]$autoPilotRunning
	$isPaused = Test-Path $Global:pauseFlagPath
    $stuckCommand = $null
    $stuckScript = $null
    $stuckIndex = -1
    $stuckStatusPath = Join-Path $AppRoot 'JSON\autopilot_stuck_status.json'
    if ($autoPilotRunning -and (Test-Path -LiteralPath $stuckStatusPath)) {
        try {
            $stuckStatus = Get-Content -LiteralPath $stuckStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $stuckExpiry = [datetime]::Parse(
                [string]$stuckStatus.ExpiresAt,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind
            ).ToUniversalTime()
            if ($stuckExpiry -gt [datetime]::UtcNow) {
                if (-not [string]::IsNullOrWhiteSpace([string]$stuckStatus.Command) -and
                    -not [string]::IsNullOrWhiteSpace([string]$stuckStatus.Script) -and
                    $global:timeline.Count -gt 0) {
                    $stuckIndex = $index
                }
            }
        } catch {
            Write-Host "Unable to read stuck-command status for timeline list: $_"
        }
    }
    if(-not $global:timeline -or $global:timeline.Count -eq 0) {
        $lbItem = New-Object System.Windows.Controls.ListBoxItem
        $lbItem.Content = "🚫 Timeline List is Empty. Nothing to 🔄 Refresh."
        $lbItem.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(51, 153, 255))
        $lbItem.FontWeight = 'Bold'
        $listBox.Items.Add($lbItem)
        return
    }
    foreach($i in 0..($global:timeline.Count-1)){
        $itemText = "{0:D3}. {1}" -f ($i+1), $global:timeline[$i].Text
        $lbItem = New-Object System.Windows.Controls.ListBoxItem
        $lbItem.Content = $itemText
        $lbItem.Padding = [System.Windows.Thickness]::new(5)
        $isTypeBlue = $global:timeline[$i].Type -match "weekly|monthly|yearly"
        $isModeMagenta = $global:timeline[$i].Mode -eq "fixed"
        if ($i -eq $stuckIndex) {
            $lbItem.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(255, 190, 75))
            $lbItem.FontWeight = 'Bold'
            $lbItem.Content += " - ⚠️ Stuck"
        }
        # ===== AUTOPILOT STOPPED =====
		elseif (-not $autoPilotRunning) {
			if($i -lt $index){
				$lbItem.Foreground = [System.Windows.Media.Brushes]::Gray
			} 
			elseif($i -eq $index){
				$lbItem.Foreground = [System.Windows.Media.Brushes]::LightGray
				$lbItem.FontWeight = 'Bold'
				$lbItem.Content += " - ⏹️ Stopped"
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
				$lbItem.Content += " - ⏸️ Paused"
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
				$lbItem.Content += " - 🔁 Active"
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
# ===================== TimelineHeader =====================
function Update-TimelineHeader {
    if (-not $Global:TimelineRun_Total) { return }
    $totalCommands = @($global:timeline).Count
    $executedCommands = @($global:timeline | Where-Object { $_.Time -le (Get-Date) }).Count
    $leaveCommands = @($global:timeline | Where-Object {
        $_.Time -gt (Get-Date) -and $_.Time.Date -eq (Get-Date).Date
    }).Count
    $Global:TimelineRun_Total.Text = "$totalCommands"
    $Global:TimelineRun_Complete.Text = "$executedCommands"
    $Global:TimelineRun_Remaining.Text = "$leaveCommands"
}
# ===================== BUTTON TO SHOW FULL TIMELINE =====================
$btnTimelineList = $window.FindName("btnTimelineList") 
$btnTimelineList.Add_Click({
	# Ако листата е веќе отворена
    if ($Global:TimelineListWindow -and $Global:TimelineListWindow.IsVisible) {
        if ($Global:TimelineListWindow.WindowState -eq [System.Windows.WindowState]::Minimized) {
            $Global:TimelineListWindow.WindowState = [System.Windows.WindowState]::Normal
        }
        if ($Global:TimelineListBox) {
            Update-TimelineList -listBox $Global:TimelineListBox
        }
        $Global:TimelineListWindow.Activate()
        return
    }
    # ===================== Проверка дали AutoPilot работи =====================
    $autoPilotRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\AutoPilot.ps1")
    }
    # Проверка дали е PAUSED
    $isPaused = Test-Path $Global:pauseFlagPath
    # ================= Window =================
    $listWindow = New-Object System.Windows.Window
	$Global:TimelineListWindow = $listWindow
	$listWindow.Add_Closed({
		$Global:TimelineListWindow = $null
        $Global:TimelineListBox = $null
	})
    $listWindow.Title = "Automation Commands List All"
    $listWindow.Width = 1555
    $listWindow.Height = 900
    $listWindow.WindowStartupLocation = "CenterScreen"
    $listWindow.Background = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(38,42,48)))
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
	# ===== TITLE DINAMIC TEXT =====
	$totalCommands = @($global:timeline).Count
	$executedCommands = @($global:timeline | Where-Object { $_.Time -le (Get-Date) }).Count
	$now = Get-Date
	$todayDate = $now.Date
	$leaveCommands = @($global:timeline | Where-Object {
    $_.Time -gt (Get-Date) -and $_.Time.Date -eq (Get-Date).Date
    }).Count
	# ===== TITLE TEXT =====
	$titleText = New-Object System.Windows.Controls.TextBlock
	$titleText.FontSize = 25
	$titleText.FontWeight = 'Bold'
	$titleText.VerticalAlignment = "Center"
	$run1 = New-Object System.Windows.Documents.Run
	$run1.Text = "Automation Commands List  "
	$run1.Foreground = [System.Windows.Media.Brushes]::White
	$run2a = New-Object System.Windows.Documents.Run
	$run2a.Text = " 🛢️ Total: "
	$run2a.Foreground = [System.Windows.Media.Brushes]::White
	$run2b = New-Object System.Windows.Documents.Run
	$run2b.Text = "$totalCommands"
	$Global:TimelineRun_Total = $run2b
	$run2b.Foreground = [System.Windows.Media.SolidColorBrush]::new(
    [System.Windows.Media.Color]::FromRgb(51, 153, 255)
    )
	$run3 = New-Object System.Windows.Documents.Run
	$run3.Text = "  🡺  "
	$run3.Foreground = [System.Windows.Media.Brushes]::White
	$run4a = New-Object System.Windows.Documents.Run
	$run4a.Text = "🔥 Complete: "
	$run4a.Foreground = [System.Windows.Media.Brushes]::White
	$run4b = New-Object System.Windows.Documents.Run
	$run4b.Text = "$executedCommands"
	$Global:TimelineRun_Complete = $run4b
	if ($executedCommands -eq 0) {
    $run4b.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(240, 84, 84))
	}
	else {
		$run4b.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(214, 168, 237))
	}
	$run5 = New-Object System.Windows.Documents.Run
	$run5.Text = "  🡸  "
	$run5.Foreground = [System.Windows.Media.Brushes]::White
	$run6 = New-Object System.Windows.Documents.Run
	$run6.Text = "🕤 Remaing: "
	$run6.Foreground = [System.Windows.Media.Brushes]::White
	$run7 = New-Object System.Windows.Documents.Run
	$run7.Text = "$leaveCommands"
	$Global:TimelineRun_Remaining = $run7
	if ($leaveCommands -eq 0) {
    $run7.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(240, 84, 84))
	}
	else {
		$run7.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(240, 170, 84))
	}
	$titleText.Inlines.Add($run1)
	$titleText.Inlines.Add($run2a)
	$titleText.Inlines.Add($run2b)
	$titleText.Inlines.Add($run3)
	$titleText.Inlines.Add($run4a)
	$titleText.Inlines.Add($run4b)
	$titleText.Inlines.Add($run5)
	$titleText.Inlines.Add($run6)
	$titleText.Inlines.Add($run7)
	# ===== ADD TO CONTAINER =====
	$btnRefresh = New-Object System.Windows.Controls.Button
	$btnRefresh.Content = "⭮"
	$btnRefresh.FontWeight = 'Bold'
	$btnRefresh.Margin = [System.Windows.Thickness]::new(15,0,0,0)
	$btnRefresh.Style = $window.FindResource("ModernButton")
	$btnRefresh.Width = 40
	$btnRefresh.Height = 40
	$btnRefresh.Padding = 0
	$btnRefresh.HorizontalContentAlignment = "Center"
	$btnRefresh.VerticalContentAlignment = "Center"
	# ===== ROTATION TRANSFORM =====
	$Global:RefreshRotateTransform = New-Object System.Windows.Media.RotateTransform 0
	$btnRefresh.RenderTransform = $Global:RefreshRotateTransform
	$btnRefresh.RenderTransformOrigin = "0.5,0.5"
	# ===================== FIXED REFRESH (NO REOPEN) =====================
	$btnRefresh.Add_Click({
	if ($Global:TimelineListBox) {
		Update-TimelineList -listBox $Global:TimelineListBox
	}
	# ===================== RE-CALCULATE STATE (IMPORTANT FIX) =====================
    $executedCommands = @($global:timeline | Where-Object { $_.Time -le (Get-Date) }).Count
    $leaveCommands = @($global:timeline | Where-Object {
        $_.Time -gt (Get-Date) -and $_.Time.Date -eq (Get-Date).Date
    }).Count
    Update-TimelineHeader
    # ===================== COMPLETE COLOR =====================
    if ($executedCommands -eq 0) {
        $Global:TimelineRun_Complete.Foreground =
            [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromRgb(240, 84, 84)
            )
    }
    else {
        $Global:TimelineRun_Complete.Foreground =
            [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromRgb(214, 168, 237)
            )
    }
    # ===================== REMAINING COLOR =====================
    if ($leaveCommands -eq 0) {
        $Global:TimelineRun_Remaining.Foreground =
            [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromRgb(240, 84, 84)
            )
    }
    else {
        $Global:TimelineRun_Remaining.Foreground =
            [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromRgb(240, 170, 84)
            )
    }
	$Global:RefreshSpinAngle += 360
	$anim = New-Object System.Windows.Media.Animation.DoubleAnimation
	$anim.From = $Global:RefreshRotateTransform.Angle
	$anim.To = $Global:RefreshSpinAngle
	$anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(500))
	$Global:RefreshRotateTransform.BeginAnimation(
		[System.Windows.Media.RotateTransform]::AngleProperty,
		$anim
		)
	})
	$titleContainer.Children.Add($logo)
	$titleContainer.Children.Add($titleText)
	$refreshPanel = New-Object System.Windows.Controls.StackPanel
	$refreshPanel.Orientation = "Horizontal"
	$refreshPanel.VerticalAlignment = "Center"
	# TEXT BEFORE BUTTON
	$refreshText = New-Object System.Windows.Controls.TextBlock
	$refreshText.Text = "🡺  🔄 Refresh"
	$refreshText.FontWeight = 'Bold'
	$refreshText.Foreground = [System.Windows.Media.Brushes]::White
	$refreshText.FontSize = 25
	$refreshText.Margin = [System.Windows.Thickness]::new(15,0,0,0)
	$refreshText.VerticalAlignment = "Center"
	$refreshPanel.Children.Add($refreshText)
	$refreshPanel.Children.Add($btnRefresh)
	$titleContainer.Children.Add($refreshPanel)
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
	$listBox.Background = (New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(25,27,33)))
	$listBox.BorderThickness = 0
	$listBox.FontSize = 19
	$listBox.FontFamily = "Segoe UI"
	$listBox.Foreground = [System.Windows.Media.Brushes]::White
	# MODE 4,5 - намален font
	if ($Global:mode -eq 4) {
		$listBox.FontSize = 17
	}
	elseif ($Global:mode -eq 5) {
    $listBox.FontSize = 15
    }
    $Global:TimelineListBox = $listBox
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
        $lbItem.Content = "🚫 No Commands in the Timeline List."
        $lbItem.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(240, 84, 84))
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
            $lbItem.Content += " - ⏹️ Stopped"
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
            $lbItem.Content += " - ⏸️ Paused"
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
			$lbItem.Content += " - 🔁 Active"
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
    $listWindow.Show()
    Update-TimelineList -listBox $Global:TimelineListBox
})

# ===================== LOAD TIMELINE =====================
function Load-Timeline {
    $cmdJson = Get-Content "$AppRoot\JSON\commands_edit.json" -Raw | ConvertFrom-Json
    $scrJson = Get-Content "$AppRoot\JSON\scripts_edit.json" -Raw | ConvertFrom-Json
    $timeline = @()
    # ================= SCRIPTS =================
    $settingsPath = "$AppRoot\JSON\settings.json"
    $fixedNoBlockCycle = $false
    if (Test-Path $settingsPath) {
        try {
            $config = Get-Content $settingsPath -Raw | ConvertFrom-Json
            $fixedNoBlockCycle = [bool]$config.FIXED_NO_BLOCK_CYCLE
        }
        catch {
            $fixedNoBlockCycle = $false
        }
    }
    # ================= CURRENT AUTOPILOT STATE =================
    $statePath = "$AppRoot\JSON\autopilot_state.json"
    $currentR = 1
    $state = $null
    if (Test-Path $statePath) {
        try {
            $state = Get-Content $statePath -Raw | ConvertFrom-Json
            if ($null -ne $state.cycle) {
                $currentR = [int]$state.cycle
            }
        }
        catch {
            $currentR = 1
            $state = $null
        }
    }
    # ================= CHECK FUTURE FIXED BLOCK =================
    $futureFixedExists = $false
    $nextFixedDate = $null
    if (-not $fixedNoBlockCycle) {
        foreach($checkScr in $scrJson.ScheduledScripts){
            for($j = 0; $j -lt $checkScr.Times.Count; $j++){
                $checkMode = $checkScr.Mode[$j]
                $hasDay =
                    $checkScr.Day -and
                    $checkScr.Day.Count -gt $j -and
                    -not [string]::IsNullOrWhiteSpace(
                        $checkScr.Day[$j]
                    )
                if ($checkMode -eq "fixed" -and $hasDay) {
                    $checkFixedTime = [datetime]::ParseExact(
                        "$($checkScr.Day[$j]) $($checkScr.Times[$j])",
                        "yyyy-MM-dd HH:mm:ss",
                        $null
                    )
                    if ($checkFixedTime -gt (Get-Date)) {
                        if (
                            $null -eq $nextFixedDate -or
                            $checkFixedTime -lt $nextFixedDate
                        ) {
                            $nextFixedDate = $checkFixedTime
                        }
                        $futureFixedExists = $true
                    }
                }
            }
        }
    }
    foreach($scr in $scrJson.ScheduledScripts){
        for($i=0; $i -lt $scr.Times.Count; $i++){
            $mode = $scr.Mode[$i]
            $type = "daily"
            $timeStr = $scr.Times[$i]
            $dayStr =
                if($scr.Day[$i] -and $scr.Day[$i].Trim() -ne "") {
                    $scr.Day[$i]
                }
                else {
                    "No Data"
                }
            if($mode -eq "fixed" -and $dayStr){
                $dt = [datetime]::ParseExact(
                    "$dayStr $timeStr",
                    "yyyy-MM-dd HH:mm:ss",
                    $null
                )
            }
            else {
                $today = Get-Date
                $timeParts = $timeStr -split ":"
                $dt = $today.Date.
                    AddHours([int]$timeParts[0]).
                    AddMinutes([int]$timeParts[1]).
                    AddSeconds([int]$timeParts[2])
            }
            # ================= STATUS TEXT =================
            switch ($mode.ToLower()){
                "fixed" { $status = "𝐅𝐈𝐗𝐄𝐃" }
                "loop"  { $status = "𝐋𝐎𝐎𝐏" }
                default { $status = "" }
            }
			# ================= COMPLETED FIXED =================
			$completedText = ""
			if(
				$mode -eq "fixed" -and
				$dt -lt (Get-Date)
			){
				$completedText = "  🡸 ✅ Completed (Time's Up)"
			}
			# ================= OUT OF LOOP STATUS =================
			$outOfLoopText = ""
			$hasExplicitDay = (
				-not [string]::IsNullOrWhiteSpace([string]$dayStr) -and
				$dayStr -ne "No Data"
			)
			$now = Get-Date
			if (
				$fixedNoBlockCycle -and
				($mode -eq "fixed" -or $hasExplicitDay) -and
				$hasExplicitDay -and
				$dt -ge $now
			) {
				$stateTotal = ""
				if ($null -ne $state -and $null -ne $state.total) {
					$stateTotal = ([string]$state.total).Trim()
				}
				# Is this FIXED command inside the current 24h cycle window? (start = JSON timestamp)
				$fixedInWindow = $false
				try {
					if ($null -ne $state -and $null -ne $state.timestamp) {
						$cycleStartState = if ($state.timestamp -is [datetime]) {
							$state.timestamp
						} else {
							[datetime]::ParseExact(
								[string]$state.timestamp, "yyyy-MM-dd HH:mm:ss",
								[System.Globalization.CultureInfo]::InvariantCulture
							)
						}
						$fixedInWindow = ($dt -lt $cycleStartState.AddHours(24).AddSeconds(15))
					}
				}
				catch { $fixedInWindow = $false }
				# FINITE LOOP: prikazi oznaka samo ako FIXED ne e vo tekovniot 24h cycle.
				if ($stateTotal -match '^\d+$' -and [int]$stateTotal -gt 0) {
					$totalR = [int]$stateTotal
					if (-not $fixedInWindow) {
						$outOfLoopText = "  🡸 ⚠️ Out of Loop (Rep:$currentR/$totalR)"
					}
				}
				# BESKONECEN LOOP: oznaka samo ako FIXED ne e vo tekovniot 24h cycle.
				elseif ($stateTotal -ieq "LOOP") {
					if (-not $fixedInWindow) {
						$outOfLoopText = "  🡸 ⚠️ Out of Loop (Rep:$currentR/Loop)"
					}
				}
				# Ako sostojbata ne e dostapna, zadrzi ja starata oznaka.
				else {
					$outOfLoopText = "  🡸 ⚠️ Out of Loop (Skipped)"
				}
			}
            # ================= SKIPPED REP STATUS =================
            $previewStatus = ""
            if (
                $mode -eq "loop" -and
                -not $fixedNoBlockCycle -and
                $futureFixedExists -and
                $null -ne $state -and
                $null -ne $state.timestamp -and
                (Get-Date) -ge ([datetime]$state.timestamp).AddDays(1)
            ) {
                $previewStatus = "  🡸 ⛔ Skipped (Rep:$currentR)"
            }
            $timeline += [PSCustomObject]@{
                Time = $dt
                Mode = $mode
                Type = $type
                Text = "$status  📑 SCRIPT ({0}) Command: {1}  🕓 Time: {2}  🌀 Delay: {3} sec  🔂 Repeat: {4} min  🔃 Mode: {5}  📆 Day: {6}$previewStatus$completedText$outOfLoopText" -f `
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
                "fixed" { $status = "𝐅𝐈𝐗𝐄𝐃" }
                "loop"  { $status = "𝐋𝐎𝐎𝐏" }
                default { $status = "" }
            }
			# ================= COMPLETED FIXED =================
			$completedText = ""
			if(
				$mode -eq "fixed" -and
				$dt -lt (Get-Date)
			){
				$completedText = "  🡸 ✅ Completed (Time's Up)"
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
                Text = "$status $typeText  🅰️ AUTO COMMAND ({0})  🕓 Time: {1}  🔂 Repeat: {2} min  🔀 Type: {3}  🔃 Mode: {4}  📆 Day: {5}$completedText" -f `
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
    $global:timeline = @($timeline | Sort-Object Time)
}

# ===================== UPDATE DISPLAY GLOBAL =====================
$Global:lastDate = (Get-Date).Date
$Global:lastNextText = ""

# AutoPilot Status Dot Image
function New-AutoPilotStatusDotImage {
    param([System.Windows.Media.Color]$Color)
    $dotDrawing = [System.Windows.Media.GeometryDrawing]::new()
    $dotDrawing.Brush = [System.Windows.Media.SolidColorBrush]::new($Color)
    $dotDrawing.Geometry = [System.Windows.Media.EllipseGeometry]::new(
        [System.Windows.Rect]::new(1, 1, 23, 23)
    )
    return [System.Windows.Media.DrawingImage]::new($dotDrawing)
}

# ===================== UPDATE DISPLAY =====================
function Update-TimelineDisplay {
    # ===================== UI ELEMENTS =====================
    $liveTimelinePanel   = $window.FindName("liveTimelineStack")
    $liveTimelineMessage = $window.FindName("txtLiveTimelineMessage")
    $autoPilotRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$AppRoot\AutoPilot.ps1")
    }
    $autoPilotRunning = [bool]$autoPilotRunning
    $stuckStatusPath = Join-Path $AppRoot 'JSON\autopilot_stuck_status.json'
    if ($autoPilotRunning -and $liveTimelineMessage -and (Test-Path -LiteralPath $stuckStatusPath)) {
        try {
            $stuckStatus = Get-Content -LiteralPath $stuckStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $statusExpiry = [datetime]::Parse(
                [string]$stuckStatus.ExpiresAt,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind
            ).ToUniversalTime()
            if ($statusExpiry -gt [datetime]::UtcNow -and
                -not [string]::IsNullOrWhiteSpace([string]$stuckStatus.Command) -and
                -not [string]::IsNullOrWhiteSpace([string]$stuckStatus.Script)) {
                if ($liveTimelinePanel) { $liveTimelinePanel.Visibility = 'Collapsed' }
                $liveTimelineMessage.Inlines.Clear()
                $liveTimelineMessage.FontSize = 22
                $liveTimelineMessage.Margin = [System.Windows.Thickness]::new(12)
                $stuckTitle = [System.Windows.Documents.Run]::new('⚠  Command Stuck')
                $stuckTitle.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.Color]::FromRgb(255, 190, 75)
                )
                $stuckTitle.FontWeight = [System.Windows.FontWeights]::Bold
                if ($stuckStatus.TestMode) {
                    $testModeRun = [System.Windows.Documents.Run]::new('  ·  Test Mode')
                    $testModeRun.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.Color]::FromRgb(134, 239, 172)
                    )
                    $testModeRun.FontWeight = [System.Windows.FontWeights]::Bold
                    $liveTimelineMessage.Inlines.Add($stuckTitle)
                    $liveTimelineMessage.Inlines.Add($testModeRun)
                } else {
                    $liveTimelineMessage.Inlines.Add($stuckTitle)
                }
                $stuckCommand = [System.Windows.Documents.Run]::new(
                    "Command $($stuckStatus.Command)  •  $($stuckStatus.Script)"
                )
                $stuckCommand.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.Color]::FromRgb(100, 210, 220)
                )
                $stuckCommand.FontWeight = [System.Windows.FontWeights]::SemiBold
                switch ([string]$stuckStatus.Action) {
                    'AwaitingConfirmation' {
                        $actionText = 'Waiting for your choice  ·  up to 5 min'
                        $actionColor = [System.Windows.Media.Color]::FromRgb(245, 190, 85)
                    }
                    'RestartAutoPilot' {
                        $actionText = 'Restarting AutoPilot...'
                        $actionColor = [System.Windows.Media.Color]::FromRgb(100, 190, 245)
                    }
                    'RestartPC' {
                        $actionText = 'Restarting PC...'
                        $actionColor = [System.Windows.Media.Color]::FromRgb(245, 160, 85)
                    }
                    'ShutdownPC' {
                        $actionText = 'Shutting down PC...'
                        $actionColor = [System.Windows.Media.Color]::FromRgb(235, 115, 115)
                    }
                    'CancelledRestart' {
                        $actionText = 'Restarting AutoPilot  ·  PC action cancelled'
                        $actionColor = [System.Windows.Media.Color]::FromRgb(100, 190, 245)
                    }
                    default {
                        $actionText = 'Recovery in progress...'
                        $actionColor = [System.Windows.Media.Color]::FromRgb(245, 190, 85)
                    }
                }
                $stuckAction = [System.Windows.Documents.Run]::new($actionText)
                $stuckAction.Foreground = [System.Windows.Media.SolidColorBrush]::new($actionColor)
                $liveTimelineMessage.Inlines.Add([System.Windows.Documents.LineBreak]::new())
                $liveTimelineMessage.Inlines.Add($stuckCommand)
                $liveTimelineMessage.Inlines.Add([System.Windows.Documents.LineBreak]::new())
                $liveTimelineMessage.Inlines.Add($stuckAction)
                $liveTimelineMessage.Visibility = 'Visible'
                if ($imgStatus) {
                    $imgStatus.Source = New-AutoPilotStatusDotImage (
                        [System.Windows.Media.Color]::FromRgb(100, 210, 220)
                    )
                }
                $txtCountdown.Text = "AutoPilot Recovery 🛡️"
                $txtCountdown.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.Color]::FromRgb(170, 180, 195)
                )
                $txtCountdown.FontWeight = "SemiBold"
                return
            }
        } catch {
            Write-Host "Unable to read stuck-command dashboard status: $_"
        }
    }
    if ($liveTimelineMessage) {
        $liveTimelineMessage.Inlines.Clear()
        $liveTimelineMessage.FontSize = 28
        $liveTimelineMessage.Margin = [System.Windows.Thickness]::new(27)
    }
    # ===================== CHECK AUTOPILOT =====================
    if (-not $autoPilotRunning) {
        if ($liveTimelinePanel)   { $liveTimelinePanel.Visibility = 'Collapsed' }
        if ($liveTimelineMessage) {
            $liveTimelineMessage.Text = "⏹️ AutoPilot is STOPPED"
			$liveTimelineMessage.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(220, 120, 120)
			)
            $liveTimelineMessage.Visibility = 'Visible'
        }
		if($imgStatus){
		$imgStatus.Source = New-AutoPilotStatusDotImage (
			[System.Windows.Media.Color]::FromRgb(220, 120, 120)
		)
	    }
        $txtPrev.Text     = "none"
        $txtCurrent.Text  = "none"
        $txtNext.Text     = "none"
        $txtCountdown.Text = "Auto Commands are not Running ⏹"
        $txtCountdown.Foreground = [System.Windows.Media.Brushes]::Gray
		$txtCountdown.FontWeight = "SemiBold"
        return
    }
    # ===================== CHECK PAUSE =====================
    $isPaused = Test-Path $Global:pauseFlagPath
    if ($isPaused) {
        if ($liveTimelinePanel)   { $liveTimelinePanel.Visibility = 'Collapsed' }
        if ($liveTimelineMessage) {
            $liveTimelineMessage.Text = "⏸️ AutoPilot is PAUSED"
			$liveTimelineMessage.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(220, 190, 120)
			)
            $liveTimelineMessage.Visibility = 'Visible'
        }
		if($imgStatus){
		$imgStatus.Source = New-AutoPilotStatusDotImage (
			[System.Windows.Media.Color]::FromRgb(253, 186, 116)
		)
	    }
        $txtPrev.Text     = "none"
        $txtCurrent.Text  = "none"
        $txtNext.Text     = "none"
        $txtCountdown.Text = "Auto Commands are not Running ⏸️"
        $txtCountdown.Foreground = [System.Windows.Media.Brushes]::Gray
		$txtCountdown.FontWeight = "SemiBold"
        return
    }
	# ===================== CHECK FINISHED STATE =====================
	$statePath = "$AppRoot\JSON\autopilot_state.json"
	if (Test-Path $statePath) {
		$state = Get-Content $statePath -Raw | ConvertFrom-Json
		# Ignore different run sessions
		if ($state.runId -ne $global:runId) {
			return
		}
		if ($state.status -eq "Finished") {
			if ($liveTimelinePanel) {
				$liveTimelinePanel.Visibility = 'Collapsed'
			}
			if ($liveTimelineMessage) {
				$liveTimelineMessage.Visibility = 'Visible'
				# ================= MESSAGE BUILD (DETERMINISTIC) =================
				$msg = " 🏁 AutoPilot Finished  "
				if ($state.total -eq "LOOP" -and $null -ne $state.cycle) {
					$msg += " 🔄 Loop Session: $($state.cycle)"
				}
				elseif ($null -ne $state.totalCompleted) {
					$msg += " ✅ Completed Session: $($state.totalCompleted)"
				}
				if ($null -ne $state.total -and $state.total -ne "") {
					$msg += " / $($state.total)  "
				}
				if (-not [string]::IsNullOrWhiteSpace($state.skippedDay)) {
					$msg += " 📆 Skipped Day: $($state.skippedDay)"
				}
				$liveTimelineMessage.Text = $msg
				$liveTimelineMessage.Foreground = [System.Windows.Media.SolidColorBrush]::new(
					[System.Windows.Media.Color]::FromRgb(161, 227, 150)
				)
			}
			# ================= IMAGE =================
			$imgStatus.Source = [System.Windows.Media.Imaging.BitmapImage]::new(
				[System.Uri]::new("$AppRoot\media\finish.png")
			)
			# ================= COUNTDOWN TEXT =================
			$txtCountdown.Text = " Finished  "
			if ($state.total -eq "LOOP" -and $null -ne $state.cycle) {
				$txtCountdown.Text += " 🔄 Loop Repetition: $($state.cycle)"
			}
			elseif ($null -ne $state.totalCompleted) {
				$txtCountdown.Text += " 🔄 Repetition: $($state.totalCompleted)"
			}
			if ($null -ne $state.total -and $state.total -ne "") {
				$txtCountdown.Text += " / $($state.total)"
			}
			return
		}
	}
	# ===================== NO COMMANDS =====================
	if (-not $global:timeline -or $global:timeline.Count -eq 0) {
		if ($liveTimelinePanel)   { $liveTimelinePanel.Visibility = 'Collapsed' }
		if ($liveTimelineMessage) {
			$liveTimelineMessage.Text = "📝 No commands! Set up commands in the Scripts Edit (MANDATORY)"
			$liveTimelineMessage.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(126, 172, 222)
			)
			$liveTimelineMessage.Visibility = 'Visible'
		}
		if ($imgStatus){
			$imgStatus.Source = New-AutoPilotStatusDotImage (
				[System.Windows.Media.Color]::FromRgb(147, 197, 253)
			)
		}
		$txtPrev.Text     = "none"
		$txtCurrent.Text  = "none"
		$txtNext.Text     = "none"
		$txtCountdown.Text = "No commands configured 🚫"
		$txtCountdown.Foreground = [System.Windows.Media.Brushes]::Gray
		$txtCountdown.FontWeight = "SemiBold"
		return
	}
    # ===================== SHOW TIMELINE =====================
    if ($liveTimelinePanel)   { $liveTimelinePanel.Visibility = 'Visible' }
    if ($liveTimelineMessage) { $liveTimelineMessage.Visibility = 'Collapsed' }
	if($imgStatus){
    $imgStatus.Source = New-AutoPilotStatusDotImage (
        [System.Windows.Media.Color]::FromRgb(134, 239, 172)
    )
    }
    if (-not $global:timeline) { 
        $txtPrev.Text = "none"
        $txtCurrent.Text = "none"
        $txtNext.Text = "none"
        $txtCountdown.Text = " No timeline data ℹ️"
        $txtCountdown.Foreground = [System.Windows.Media.Brushes]::Gray
		$txtCountdown.FontWeight = "SemiBold"
        return
    }
    $now   = Get-Date
    $today = $now.Date
	# ===================== MIDNIGHT AUTO REFRESH =====================
	if ($Global:lastDate -ne $today) {
		# new day detected → force refresh
		$Global:lastDate = $today
		# reload timeline data (CRITICAL FIX)
		Load-Timeline
		# reset cached values so animations trigger correctly
		$Global:lastNextText = ""
		$txtPrev.Text    = ""
		$txtCurrent.Text = ""
		$txtNext.Text    = ""
		# force immediate UI refresh (important)
		$window.Dispatcher.InvokeAsync({
			Update-TimelineDisplay
		}, [System.Windows.Threading.DispatcherPriority]::Render)
	}
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
		elseif ($_.Mode -eq "fixed" -and $_.Time.Date -eq $today -and $_.Time -ge $today) {
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
    # get the new text values
	$newPrev    = GetText($index - 1) 
	$newCurrent = GetText($index)     
	$newNext    = GetText($index + 1) 
	# ===================== TOTAL / EXECUTED DISPLAY =====================
	if ($txtStats) {
		$txtStats.Inlines.Clear()
		$totalCommands = @($global:timeline).Count
		$executedCommands = @($global:timeline | Where-Object { $_.Time -le (Get-Date) }).Count
		$now = Get-Date
		$todayDate = $now.Date
		$leaveCommands = @($global:timeline | Where-Object {
		$_.Time -gt (Get-Date) -and $_.Time.Date -eq (Get-Date).Date
		}).Count
		# ===================== LOAD SETTINGS JSON (MULTI CHECK) =====================
		$settingsPath         = "$AppRoot\JSON\settings.json"
		$commandsEditPath     = "$AppRoot\JSON\commands_edit.json"
		$scriptsEditPath      = "$AppRoot\JSON\scripts_edit.json"
		$settingsScriptsPath  = "$AppRoot\JSON\settings_scripts.json"
		$allowedDaysCount = 0
		$maxRunsDisplay   = ""
		$jsonStatus = @()
		$jsonFiles = @(
			@{ Path = $settingsPath;        Name = "settings.json" },
			@{ Path = $commandsEditPath;    Name = "commands_edit.json" },
			@{ Path = $scriptsEditPath;     Name = "scripts_edit.json" },
			@{ Path = $settingsScriptsPath; Name = "settings_scripts.json" }
		)
		foreach ($file in $jsonFiles) {
			if (-not (Test-Path $file.Path)) {
				$jsonStatus += "NOT_FOUND: $($file.Name -replace '\.json','')"
				continue
			}
			try {
				$content = Get-Content $file.Path -Raw | ConvertFrom-Json
				if ($file.Name -eq "settings.json") {
					if ($content.ALLOWED_DAYS) {
						$allowedDays = @($content.ALLOWED_DAYS)   # 🔥 first
						$allowedDaysCount = $allowedDays.Count    # 🔥 second
					}
					else {
						$allowedDays = @()
						$allowedDaysCount = 0
					}
					if ($content.MAX_RUNS -eq 0) {
						$maxRunsDisplay = "LOOP"
					} else {
						$maxRunsDisplay = "$($content.MAX_RUNS)"
					}
				}
			}
			catch {
				$jsonStatus += "DAMAGED: $($file.Name -replace '\.json','')"
				continue
			}
		}
		# ===== TITLE TEXT =====
		$run1 = New-Object System.Windows.Documents.Run
		$run1.Text = " 🛢️ Total: "
		$run1.Foreground = [System.Windows.Media.SolidColorBrush]::new(
		[System.Windows.Media.Color]::FromRgb(158, 158, 158)
		)
		$run2 = New-Object System.Windows.Documents.Run
		$run2.Text = "$totalCommands"
		$run2.Foreground = [System.Windows.Media.SolidColorBrush]::new(
		[System.Windows.Media.Color]::FromRgb(51, 153, 255)
		)
		$run3 = New-Object System.Windows.Documents.Run
		$run3.Text = "  🡺  "
		$run3.Foreground = [System.Windows.Media.SolidColorBrush]::new(
		[System.Windows.Media.Color]::FromRgb(158, 158, 158)
		)
		$run4 = New-Object System.Windows.Documents.Run
		$run4.Text = "🔥 Complete: "
		$run4.Foreground = [System.Windows.Media.SolidColorBrush]::new(
		[System.Windows.Media.Color]::FromRgb(158, 158, 158)
		)
		$run5 = New-Object System.Windows.Documents.Run
		$run5.Text = "$executedCommands"
		$run5.Foreground = [System.Windows.Media.SolidColorBrush]::new(
		[System.Windows.Media.Color]::FromRgb(214, 168, 237)
		)
		# динамичка боја (подобро UX)
		if ($executedCommands -eq 0) {
			$run5.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(240, 84, 84)
			)
		} else {
			$run5.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(214, 168, 237)
			)
		}
		$run6 = New-Object System.Windows.Documents.Run
		$run6.Text = "  🡸  "
		$run6.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(158, 158, 158)
		)
		$run7 = New-Object System.Windows.Documents.Run
		$run7.Text = "🕤 Remaing: "
		$run7.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(158, 158, 158)
		)
		$run8 = New-Object System.Windows.Documents.Run
		$run8.Text = "$leaveCommands"
		# боја (UX style)
		if ($leaveCommands -eq 0) {
			$run8.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(240, 84, 84)
			)
		} else {
			$run8.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(240, 170, 84)
			)
		}
		# ===== SEPARATOR =====
		$run9 = New-Object System.Windows.Documents.Run
		$run9.Text = "  ╰┈➤  " # ❯❯❯❯
		$run9.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(158, 158, 158)
		)
		if ($jsonStatus.Count -gt 0) {
			# ===== ERROR DISPLAY =====
			$runError = New-Object System.Windows.Documents.Run
			$runError.Text = "⛔ " + ($jsonStatus -join "  *  ")
			$runError.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(217, 113, 113)  # црвено
			)
			$txtStats.Inlines.Add($runError)
		} else {
		# ===== DAYS LABEL =====
		$run10 = New-Object System.Windows.Documents.Run
		$run10.Text = "📆 Days: "
		$run10.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(158, 158, 158)  # сиво
		)
		# ===== DAYS VALUE =====
		$run10Value = New-Object System.Windows.Documents.Run
		if ($allowedDaysCount -eq 0) {
			$run10Value.Text = "Default (All)"
			$run10Value.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(164, 222, 64)
			)
		}
		elseif ($allowedDaysCount -eq 7) {
			$run10Value.Text = "All"
			$run10Value.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(164, 222, 64)
			)
		}
		elseif ($allowedDaysCount -eq 1) {
			$run10Value.Text = $allowedDays[0]
			$run10Value.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(164, 222, 64)
			)
		}
		else {
			$run10Value.Text = "$allowedDaysCount"
			$run10Value.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(164, 222, 64)
			)
		}
		# ===== REPEAT LABEL =====
		$run11 = New-Object System.Windows.Documents.Run
		$run11.Text = "  🔄 Repeat: "
		$run11.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(158, 158, 158)
		)
		# ===================== READ CYCLE STATE =====================
		$cycleStatePath = "$AppRoot\JSON\autopilot_state.json"
		$currentRun = 1
		if (Test-Path $cycleStatePath) {
			try {
				$cycleData = Get-Content $cycleStatePath -Raw | ConvertFrom-Json
				$currentRun = $cycleData.cycle
			} catch {
				$currentRun = 1
			}
		}
		# ===================== REPEAT DISPLAY =====================
		$run12 = New-Object System.Windows.Documents.Run
		if ($maxRunsDisplay -eq "LOOP") {
			$run12.Text = "LOOP"
			$run12.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(110, 212, 210)
			)
		} else {
			$run12.Text = "$currentRun/$maxRunsDisplay"
			$run12.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(110, 212, 210)
			)
		  }
		}
		# ===================== FIXED IN LOOP DISPLAY =====================
		$run13 = New-Object System.Windows.Documents.Run
		$fixedNoBlockCycleDisplay = $false
		try {
			$settingsPath = "$AppRoot\JSON\settings.json"
			if (Test-Path $settingsPath) {
				$settingsData = Get-Content $settingsPath -Raw | ConvertFrom-Json
				if ($null -ne $settingsData.FIXED_NO_BLOCK_CYCLE) {
					$fixedNoBlockCycleDisplay = [bool]$settingsData.FIXED_NO_BLOCK_CYCLE
				}
			}
		}
		catch {
			$fixedNoBlockCycleDisplay = $false
		}
		$run13.Text = "  🡸  🔃 Fixed: "
		$run13.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(158, 158, 158)
		)
		$run13Value = New-Object System.Windows.Documents.Run
		$run13Suffix = New-Object System.Windows.Documents.Run
		if ($fixedNoBlockCycleDisplay -eq $false) {
			$run13Value.Text = "In"
			$run13Value.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(83, 201, 83)
			)
		}
		else {
			$run13Value.Text = "Out"
			$run13Value.Foreground = [System.Windows.Media.SolidColorBrush]::new(
				[System.Windows.Media.Color]::FromRgb(159, 150, 255)
			)
		}
		$txtStats.Inlines.Add($run1)
		$txtStats.Inlines.Add($run2)
		$txtStats.Inlines.Add($run3)
		$txtStats.Inlines.Add($run4)
		$txtStats.Inlines.Add($run5)
		$txtStats.Inlines.Add($run6)
		$txtStats.Inlines.Add($run7)
		$txtStats.Inlines.Add($run8)
		$txtStats.Inlines.Add($run9)
		if ($jsonStatus) {
			$txtStats.Inlines.Add($runError)
		}
		else {
			$txtStats.Inlines.Add($run10)
			$txtStats.Inlines.Add($run10Value)
			$txtStats.Inlines.Add($run11)
			$txtStats.Inlines.Add($run12)
			$txtStats.Inlines.Add($run13)
            $txtStats.Inlines.Add($run13Value)
		}
		$txtStats.FontWeight = "SemiBold"
	}
	# fade animation (modern style)
	$fadeOut = New-Object System.Windows.Media.Animation.DoubleAnimation(1, 0, [TimeSpan]::FromMilliseconds(355))
	$fadeIn  = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 1, [TimeSpan]::FromMilliseconds(355))
	# modern easing: smooth “soft” in/out, more stylish than cubic
	$fadeOut.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
	$fadeOut.EasingFunction.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseIn
	$fadeIn.EasingFunction  = New-Object System.Windows.Media.Animation.QuadraticEase
	$fadeIn.EasingFunction.EasingMode  = [System.Windows.Media.Animation.EasingMode]::EaseOut
	# PREV
	if ($txtPrev.Text -ne $newPrev) {
		$txtPrev.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
		$txtPrev.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)
		Start-Sleep -Milliseconds 120
		$txtPrev.Text = $newPrev
		$txtPrev.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
	}
	# CURRENT
	if ($txtCurrent.Text -ne $newCurrent) {
		$txtCurrent.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
		$txtCurrent.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)
		Start-Sleep -Milliseconds 120
		$txtCurrent.Text = $newCurrent
		$txtCurrent.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
    # play sound only if enabled
    if ($Global:SoundEnabled) {
        $player.Play()  # non-blocking
    }
}
	# NEXT
	if ($Global:lastNextText -ne $newNext) {
		$txtNext.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
		$txtNext.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeOut)
		Start-Sleep -Milliseconds 120
		$txtNext.Text = $newNext
		$txtNext.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
		# store last value
		$Global:lastNextText = $newNext
	}
    # ===================== NEXT COMMAND =====================
    $upcomingLines = $global:timeline | ForEach-Object {
    $lineTime = $_.Time
    $nextTime = $null
    if ($_.Mode -eq "loop") {
        # базно време за денес
        $nextTime = $_.Time
			switch ($_.Type) {
				"daily" {
					if ($nextTime -le $now) {
						$nextTime = $nextTime.AddDays(1)
					}
				}
				"weekly" {
					# најди следна недела (Sunday)
					while ($nextTime.DayOfWeek -ne [DayOfWeek]::Sunday) {
						$nextTime = $nextTime.AddDays(1)
					}
					# ако е веќе поминато → следна недела
					if ($nextTime -le $now) {
						$nextTime = $nextTime.AddDays(7)
					}
				}
				"monthly" {
					# тековен месец - последен ден
					$lastDay = [DateTime]::DaysInMonth($today.Year, $today.Month)
					$nextTime = Get-Date -Year $today.Year -Month $today.Month -Day $lastDay `
						-Hour $lineTime.Hour -Minute $lineTime.Minute -Second $lineTime.Second
					# ако поминало → следен месец
					if ($nextTime -le $now) {
						$nextMonth = $today.AddMonths(1)
						$lastDayNext = [DateTime]::DaysInMonth($nextMonth.Year, $nextMonth.Month)
						$nextTime = Get-Date -Year $nextMonth.Year -Month $nextMonth.Month -Day $lastDayNext `
							-Hour $lineTime.Hour -Minute $lineTime.Minute -Second $lineTime.Second
					}
				}
				"yearly" {
					# 31 декември
					$nextTime = Get-Date -Year $today.Year -Month 12 -Day 31 `
						-Hour $lineTime.Hour -Minute $lineTime.Minute -Second $lineTime.Second
					# ако поминало → следна година
					if ($nextTime -le $now) {
						$nextTime = $nextTime.AddYears(1)
					}
				}
				default {
					if ($nextTime -le $now) {
						$nextTime = $nextTime.AddDays(1)
					}
				}
			}
		}
		elseif ($_.Mode -eq "fixed") {
			$nextTime = $_.Time
			# ако поминало → ignore
			if ($nextTime -lt $now) {
				$nextTime = $null
			}
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
			$loopTexts = @($loopDaily | ForEach-Object { $_.Text })
            $loopIndex = $loopTexts.IndexOf($nextCmd.Line.Text)
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
			$txtCountdown.Text = " Next Auto Command In: $($parts -join ' ') 🚀"
			$txtCountdown.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(220, 120, 120)
			)
			$txtCountdown.FontWeight = "SemiBold"
		} else {
			$txtCountdown.Text = " Next Auto Command In: $($parts -join ' ') 🕓"
			$txtCountdown.Foreground = [System.Windows.Media.SolidColorBrush]::new(
			[System.Windows.Media.Color]::FromRgb(158, 158, 158)
			)
			$txtCountdown.FontWeight = "SemiBold"
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

# ===================== WATCH AUTOPILOT STATE =====================
function Setup-AutoPilotStateWatcher {
    $statePath = "$AppRoot\JSON"
    $stateFile = "autopilot_state.json"
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $statePath
    $watcher.Filter = $stateFile
    $watcher.NotifyFilter = [System.IO.NotifyFilters]'LastWrite'
    $watcher.EnableRaisingEvents = $true
    Register-ObjectEvent $watcher Changed -Action {
        Start-Sleep -Milliseconds 200
        try {
            $fullStatePath = "$AppRoot\JSON\autopilot_state.json"
            if (-not (Test-Path $fullStatePath)) {
                return
            }
            $state = Get-Content $fullStatePath -Raw | ConvertFrom-Json
            if (
                $null -ne $state.timestamp -or
                $null -ne $state.cycle
            ) {
                Load-Timeline
                Update-TimelineDisplay
            }
        }
        catch {
            Write-Host "Error reloading timeline after AutoPilot state change: $_"
        }
    }
}
# ===================== START AUTOPILOT STATE WATCHER =====================
Setup-AutoPilotStateWatcher | Out-Null

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
        -Title "⚠️ Warning" `
        -Message "Inside the DATA folder are System Files!"
    Invoke-ManualCommand "/data"
})
$window.FindName("btnTask_add").Add_Click({ 
Show-DarkWarning `
        -Title "🚩 Auto-Start AutoPilot" `
        -Message "When Auto-Start is Enabled, AutoPilot will launch automatically every time the PC Starts!"
    Invoke-ManualCommand "/task-add"
})
$window.FindName("btnTask_del").Add_Click({ 
Show-DarkWarning `
        -Title "⏹️ Stop Auto-Start" `
        -Message "When Auto-Start is Disabled, AutoPilot will launch only Manually!"
    Invoke-ManualCommand "/task-del"
})
$window.FindName("btnTask_show").Add_Click({ Invoke-ManualCommand "/task-show" })
# ===================== AutoPilot SETTINGS =====================
$window.FindName("btnSettings").Add_Click({
    $exeName = "Settings.exe"
    $processName = "Settings"
    $autoPilotRunning = Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -like "*AutoPilot.ps1*" }
    if ($autoPilotRunning) {
        Show-DarkWarning -Title "⚠️ AutoPilot is Active" -Message "AutoPilot is currently Running! The Settings works only when AutoPilot is ⏹️ STOPPED."
        return
    }
    $settingsPath = if ($AppRoot) {
        Join-Path $AppRoot $exeName
    } else {
        Join-Path (Get-Location) $exeName
    }
    Start-SingleInstanceExe `
        -ExePath $settingsPath `
        -ProcessName $processName `
        -DisplayName "AutoPilot Settings" `
        -StartTitle "⚙️ AutoPilot Settings Started" `
        -StartMessage "🛠️ Edit AutoPilot Settings!"
})
# ===================== AutoPilot SCRIPTS SETTINGS =====================
$window.FindName("btnSettingsScripts").Add_Click({
    $exeName = "SettingsScripts.exe"
    $processName = "SettingsScripts"
    $autoPilotRunning = Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -like "*AutoPilot.ps1*" }
    if ($autoPilotRunning) {
        Show-DarkWarning -Title "⚠️ AutoPilot is Active" -Message "AutoPilot is currently Running! The Scripts Settings works only when AutoPilot is ⏹️ STOPPED."
        return
    }
    $settingsScriptsPath = if ($AppRoot) {
        Join-Path $AppRoot $exeName
    } else {
        Join-Path (Get-Location) $exeName
    }
    Start-SingleInstanceExe `
        -ExePath $settingsScriptsPath `
        -ProcessName $processName `
        -DisplayName "Scripts Settings" `
        -StartTitle "📝 Scripts Settings Started" `
        -StartMessage "✏️ Edit Scripts Settings!"
})
$window.FindName("btnSystem_Data").Add_Click({
    $exePath = "$AppRoot\Data.exe"
    if (Get-Process -Name "Data" -ErrorAction SilentlyContinue) {
        Show-DarkWarning -Title "🛢️ AutoPilot Data System" -Message "⚠️ Data.exe is already running!"
        return
    }
    Show-DarkWarning -Title "🛢️ AutoPilot Data System" -Message "All Hardware and Traffic System Data!"
    if (Test-Path $exePath) {
        Start-Process $exePath
    }
    else {
        Show-DarkWarning `
            -Title "⚠️ Error" `
            -Message "⛔ Data.exe not found!`nPath: $exePath"
    }
})
$window.FindName("btnProcessManager").Add_Click({
    $exePath = "$AppRoot\ProcessManager.exe"
    if (Get-Process -Name "ProcessManager" -ErrorAction SilentlyContinue) {
        Show-DarkWarning -Title "🛡️ Process Manager" -Message "⚠️ ProcessManager.exe is already running!"
        return
    }
    Show-DarkWarning -Title "🛡️ Process Manager" -Message "Process Control Center!"
    if (Test-Path $exePath) {
        Start-Process $exePath
    }
    else {
        Show-DarkWarning `
            -Title "⚠️ Error" `
            -Message "⛔ ProcessManager.exe not found!`nPath: $exePath"
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
$window.FindName("btnProcess_Log").Add_Click({ Invoke-ManualCommand "/process_log" })

# Monitoring
$window.FindName("btnSysMon_Start").Add_Click({ Invoke-ManualCommand "/monitoring_start" })
$window.FindName("btnSysMon_Stop").Add_Click({ Invoke-ManualCommand "/monitoring_stop" })
$window.FindName("btnSysMon_Status").Add_Click({ Invoke-ManualCommand "/monitoring_status" })
$window.FindName("btnTrafficMonitoring").Add_Click({ Start-Process "$AppRoot\Shortcuts\NetTraffic.lnk" })
# Stop Workers
$btnStopWorkers = $window.FindName("btnStopWorkers")
$btnStopWorkers.Add_Click({
    $msg = "⚠️ Warning: System and Network Monitoring may currently be Running. Are you sure you want to ⏹️ STOP the Monitoring?"
    $title = "⏹️ Stopping the Monitoring"
    $userChoice = Show-DarkConfirm -Message $msg -Title $title
    if ($userChoice) {
        Invoke-ManualCommand "/stop_worker"
    } else {
        Show-DarkWarning -Title "⏹️ Monitoring STOP" -Message "Monitoring has been stopped by the user."
    }
})

$window.ShowDialog() | Out-Null

############################################################################################## End Dashboard.