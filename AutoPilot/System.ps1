# === GLOBAL VARIABLES ===
$Global:WorkerPath = "$PSScriptRoot\SystemMonitorWorker.ps1"

# 🟩 INICIJALIZACIJA NA LOGOVI ZA MONITORING Function ***
$Global:monitoringDate = Get-Date -Format 'yyyy-MM-dd'
$Global:monitoringLogsFolder = "$PSScriptRoot\Autopilot_Data\Monitoring_Logs"
if (-not (Test-Path $Global:monitoringLogsFolder)) {
    New-Item -Path $Global:monitoringLogsFolder -ItemType Directory | Out-Null
}
# 📄 Дневен лог фајл za MONITORING
$Global:LogFile = "$Global:monitoringLogsFolder\monitoring_$Global:monitoringDate.txt"

# Load WPF
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

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

# ===================== ABORT POP UP =====================
function Show-AbortWarning {
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
            <Grid>
                <StackPanel Width="460">
                    <TextBlock Text="$Title" FontSize="24" FontWeight="Bold" Foreground="#E4E4E7" Margin="0,0,0,15" HorizontalAlignment="Center"/>
                    <TextBlock Text="$Message" TextWrapping="Wrap" FontSize="16" Foreground="#D4D4D8" Margin="0,0,0,25" TextAlignment="Center"/>
                    <Button x:Name="btnOK" Content="OK" Width="140" Height="42" HorizontalAlignment="Center" Foreground="White" FontWeight="SemiBold" FontSize="15" BorderThickness="0" Cursor="Hand">
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
                <!-- CLOSE X BUTTON -->
                <Button x:Name="btnClose"
                        Content="×"
                        Width="42"
                        Height="42"
                        HorizontalAlignment="Right"
                        VerticalAlignment="Top"
                        Margin="0,-20,-20,0"
                        Background="Transparent"
                        Foreground="#F87171"
                        FontSize="34"
                        FontWeight="Bold"
                        BorderThickness="0"
                        Cursor="Hand"
                        Focusable="False"
                        ToolTipService.InitialShowDelay="250"
                        ToolTipService.ShowDuration="6000">
                    <!-- MODERN DARK TOOLTIP -->
                    <Button.ToolTip>
                        <ToolTip Placement="Mouse" HasDropShadow="True" Background="Transparent" Foreground="#E4E4E7" BorderThickness="0" Padding="0">
                            <ToolTip.Template>
                                <ControlTemplate TargetType="ToolTip">
                                    <Border Background="#F222252C" BorderBrush="#444954" BorderThickness="1" CornerRadius="3" Padding="14,10">
                                        <Border.Effect>
                                            <DropShadowEffect Color="Black" BlurRadius="14" ShadowDepth="3" Opacity="0.45"/>
                                        </Border.Effect>
                                        <StackPanel>
                                            <TextBlock Text="Abort Action" FontSize="15" FontWeight="Bold" Foreground="#F87171" Margin="0,0,0,5"/>
                                            <TextBlock Text="Click X to Abort." FontSize="13" Foreground="#E4E4E7"/>
                                            <TextBlock Text="The Restart will Not Be Executed." FontSize="13" Foreground="#A1A1AA" Margin="0,3,0,0"/>
                                        </StackPanel>
                                    </Border>
                                </ControlTemplate>
                            </ToolTip.Template>
                        </ToolTip>
                    </Button.ToolTip>
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="border" Background="#2A2D35" BorderBrush="#444954" BorderThickness="1" CornerRadius="10" RenderTransformOrigin="0.5,0.5">
                                <Border.RenderTransform>
                                    <RotateTransform x:Name="rotation" Angle="0"/>
                                </Border.RenderTransform>
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="border" Property="Background" Value="#4A2C32"/>
                                    <Setter TargetName="border" Property="BorderBrush" Value="#7A4A52"/>
                                    <Trigger.EnterActions>
                                        <BeginStoryboard>
                                            <Storyboard>
                                                <DoubleAnimation Storyboard.TargetName="rotation" Storyboard.TargetProperty="Angle" To="12" Duration="0:0:0.15"/>
                                            </Storyboard>
                                        </BeginStoryboard>
                                    </Trigger.EnterActions>
                                    <Trigger.ExitActions>
                                        <BeginStoryboard>
                                            <Storyboard>
                                                <DoubleAnimation Storyboard.TargetName="rotation" Storyboard.TargetProperty="Angle" To="0" Duration="0:0:0.15"/>
                                            </Storyboard>
                                        </BeginStoryboard>
                                    </Trigger.ExitActions>
                                </Trigger>
                                <Trigger Property="IsPressed" Value="True">
                                    <Setter TargetName="border" Property="Background" Value="#3A2328"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </Grid>
        </Border>
</Window>
"@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $win = [Windows.Markup.XamlReader]::Load($reader)
    # Default: Cancel
    $win.Tag = $false
    $btnOK = $win.FindName("btnOK")
    $btnClose = $win.FindName("btnClose")
    # OK = Continue
    $btnOK.Add_Click({
        $win.Tag = $true
        $win.Close()
    })
    # X = Cancel
    $btnClose.Add_Click({
        $win.Tag = $false
        $win.Close()
    })
    $win.ShowDialog() | Out-Null
    return [bool]$win.Tag
}

# STOP ALL FFMPEG.EXE PROCESSES
function Stop-FfmpegExe {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
	# STOP ALL FFMPEG.EXE PROCESSES
	$ffmpegStopped = @()
	$ffmpegErrors  = @()
	try {
		$ffmpegProcesses = @(Get-Process -Name "ffmpeg" -ErrorAction SilentlyContinue)
		foreach ($ff in $ffmpegProcesses) {
			$ffmpegPID = $ff.Id
			try {
				Stop-Process -Id $ffmpegPID -Force -ErrorAction Stop
				$ffmpegStopped += "🎬 PID $ffmpegPID stopped by AutoPilot."
			} catch {
				$ffmpegErrors += "⚠️ PID $ffmpegPID could not be stopped: $($_.Exception.Message)"
			}
		}
	} catch {
		$ffmpegErrors += "⚠️ FFMPEG process enumeration error: $($_.Exception.Message)"
	}
	# LOG FFMPEG.EXE PROCESSES
	$ffmpegMessageLines = @()
	if ($ffmpegStopped.Count -gt 0) {
		$ffmpegMessageLines += "⛔ AutoPilot Stop/Restart: stopped $($ffmpegStopped.Count) ffmpeg.exe process(es)."
		$ffmpegMessageLines += $ffmpegStopped
	}
	if ($ffmpegErrors.Count -gt 0) {
		$ffmpegMessageLines += $ffmpegErrors
	}
	if ($ffmpegMessageLines.Count -gt 0) {
		foreach ($line in $ffmpegMessageLines) {
			try { Write-Log $line } catch {}
		}
	}
}

# 💻 Status na sistemot (CPU, RAM, Disk)
function System-Status {
    # CPU
    $cpu = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue, 2)
    # RAM
    $ram = Get-CimInstance Win32_OperatingSystem
    $usedRAM = [math]::Round(($ram.TotalVisibleMemorySize - $ram.FreePhysicalMemory)/1MB, 2)
    $totalRAM = [math]::Round($ram.TotalVisibleMemorySize/1MB, 2)
    $ramPercent = [math]::Round(($usedRAM / $totalRAM) * 100, 2)
    # Disks
    $diskInfoString = (Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        ForEach-Object { "$($_.DeviceID) $([math]::Round($_.FreeSpace/1GB,2))GB free of $([math]::Round($_.Size/1GB,2))GB" }
    ) -join "`n"
    # Network adapters (+ connection type: Wi-Fi SSID / Ethernet / Virtual Machine)
    $currentSsid = $null
    try {
        $ssidLine = netsh wlan show interfaces 2>$null | Select-String 'SSID' | Where-Object { $_ -notmatch 'BSSID' } | Select-Object -First 1
        if ($ssidLine) { $currentSsid = ($ssidLine.ToString() -split ':', 2)[1].Trim() }
    } catch {}
    $networkStatsString = (Get-CimInstance Win32_NetworkAdapter |
        Where-Object NetEnabled -eq $true |
        ForEach-Object {
            $adapterText = "$($_.Name) $($_.NetConnectionID)"
            $connType = if ($_.PhysicalAdapter -eq $false -or $adapterText -match 'vEthernet|WSL|Hyper-V|Virtual|VMware|VirtualBox|VPN|TAP') {
                "🖥️ Virtual Machine"
            } elseif ($adapterText -match 'Wi-?Fi|Wireless|WLAN|802\.11') {
                if ($_.NetConnectionStatus -eq 2 -and $currentSsid) { "📶 Wi-Fi: $currentSsid" } else { "📶 Wi-Fi: not connected" }
            } else {
                "🔌 Ethernet"
            }
            "$($_.Description): Status - $($_.NetConnectionStatus) | $connType"
        }
    ) -join "`n"
    # Uptime
    $uptimeHours = [math]::Round(((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalHours, 2)
    # GPU load
    try {
        $gpus = Get-WmiObject Win32_VideoController
        $counter = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop
        $gpuLoad = ($gpus | ForEach-Object {
            $name = $_.Name
            $sum = ($counter.CounterSamples |
                Where-Object { $_.InstanceName -like "*$name*" } |
                Measure-Object CookedValue -Sum).Sum
            "$name Load: $([math]::Round(($sum),2))%"
        }) -join "`n"
    } catch {
        $gpuLoad = "ℹ️ GPU Load: Not Available"
    }
    # AutoPilot Status (all values are read here directly from the JSON files)
    $sepLine = "-------------------------------------"
    try {
        $jsonDir = Join-Path $PSScriptRoot "JSON"
        $cfg = Get-Content -LiteralPath (Join-Path $jsonDir "settings.json") -Raw -ErrorAction Stop | ConvertFrom-Json
        $cfgNames = $cfg.PSObject.Properties.Name
        $st = $null
        try { $st = Get-Content -LiteralPath (Join-Path $jsonDir "autopilot_state.json") -Raw -ErrorAction Stop | ConvertFrom-Json } catch {}
        # --- settings.json (same defaults as the script) ---
        $jsMaxRuns = 1
        $tmpInt = 0
        if ($cfgNames -contains "MAX_RUNS" -and [int]::TryParse([string]$cfg.MAX_RUNS, [ref]$tmpInt)) { $jsMaxRuns = $tmpInt }
        $jsAllowedDays = if ($cfgNames -contains "ALLOWED_DAYS" -and $cfg.ALLOWED_DAYS) { @($cfg.ALLOWED_DAYS) } else { @("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday") }
        $jsEnableRestart  = if ($cfgNames -contains "ENABLE_RESTART")  { [bool]$cfg.ENABLE_RESTART }  else { $false }
        $jsEnableShutdown = if ($cfgNames -contains "ENABLE_SHUTDOWN") { [bool]$cfg.ENABLE_SHUTDOWN } else { $false }
        $jsAutoStartSysMon = if ($cfgNames -contains "AUTO_START_MONITORING")      { [bool]$cfg.AUTO_START_MONITORING }      else { $false }
        $jsAutoStartTraffic = if ($cfgNames -contains "TRAFFIC_MONITOR_AUTO_START") { [bool]$cfg.TRAFFIC_MONITOR_AUTO_START } else { $false }
        $jsFixedNoBlock = if ($cfgNames -contains "FIXED_NO_BLOCK_CYCLE") { [bool]$cfg.FIXED_NO_BLOCK_CYCLE } else { $false }
        # --- autopilot_state.json (current repetition and when it started) ---
        $apCycle = if ($st -and $null -ne $st.cycle) { $st.cycle } else { "N/A" }
        $apRepStart = "N/A"
        if ($st -and $st.reason -eq "ActiveCycle" -and $st.timestamp) {
            $tsObj = if ($st.timestamp -is [datetime]) { $st.timestamp } else { [datetime]::ParseExact([string]$st.timestamp, "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture) }
            $apRepStart = "📆 $($tsObj.ToString('yyyy-MM-dd')) 🕒 $($tsObj.ToString('HH:mm:ss'))"
        }
        $apModeText = if ($jsMaxRuns -eq 1) { "Single (1 Repeat)" } elseif ($jsMaxRuns -gt 1) { "Limited ($jsMaxRuns Repetitions)" } else { "Infinite (Loop)" }
        $apWindowText = if ((Get-Process -Id $PID).MainWindowHandle -eq 0) { "🔴 Hidden" } else { "🟢 Visible" }
        # Start time of the AutoPilot.ps1 process
		$apPs1Proc = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
			Where-Object { $_.Name -match '^(powershell|pwsh)\.exe$' -and $_.CommandLine -like "*Autopilot.ps1*" } |
			Sort-Object CreationDate |
			Select-Object -First 1
		$apStartText = if ($apPs1Proc) {
			$apPs1Proc.CreationDate.ToString("📆 yyyy-MM-dd 🕒 HH:mm:ss")
		} else {
			(Get-Process -Id $PID).StartTime.ToString("📆 yyyy-MM-dd 🕒 HH:mm:ss")
		}
        $allDayNames = @("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")
        $apDayList = @($jsAllowedDays | ForEach-Object { [string]$_ })
        $apDays = if (@($allDayNames | Where-Object { $apDayList -notcontains $_ }).Count -eq 0) { "All Days" } else { "$($apDayList.Count) days: $($apDayList -join ', ')" }
        $apRepText = if ($jsMaxRuns -eq 0) { "Loop (run #$apCycle)" } else { "$apCycle of $jsMaxRuns" }
        $apFixedText = if ($jsFixedNoBlock) { "🟣 Off (Repetition does not wait for 📆 Fixed Commands)" } else { "🟢 In (Repetition waits for 📆 Fixed Commands)" }
        # Alarm Limits mode from settings.json
        $apAlarmText = if ($jsEnableRestart -and $jsEnableShutdown) {
            "🔵 PRO"
        } elseif (-not $jsEnableRestart -and -not $jsEnableShutdown) {
            "🟢 TEST"
        } else {
            "⚠️ MIXED (Restart: $(if ($jsEnableRestart) { 'true' } else { 'false' }), Shutdown: $(if ($jsEnableShutdown) { 'true' } else { 'false' }))"
        }
        $apSysMonText = if ($jsAutoStartSysMon) { "🟢 On" } else { "🔴 Off" }
        $apTrafficText = if ($jsAutoStartTraffic) { "🟢 On" } else { "🔴 Off" }
        $apStatus = "🔰 AutoPilot Status:`n$sepLine`n" +
                    "✅ Started: $apStartText`n" +
                    "🔢 Mode: $apModeText`n" +
                    "⚛️ Cmd: $apWindowText`n" +
                    "📆 Allowed days: $apDays`n`n" +
                    "🔂 Repetition: $apRepText`n" +
                    "🏁 Started: $apRepStart`n`n" +
                    "🔁 Loop: $apFixedText`n`n" +
                    "📢 Alarm Limits Mode: $apAlarmText`n" +
                    "📊 AutoStart System Monitor: $apSysMonText`n" +
                    "🌍 AutoStart Traffic Monitor: $apTrafficText"
    } catch {
        $apStatus = "ℹ️ AutoPilot Status: Not Available"
    }
    # Compose output
    $status = @"
⚙️ System Status:
$sepLine
🔲 CPU Usage: $cpu %
💾 RAM: $usedRAM GB / $totalRAM GB ($ramPercent%)

📀 Disk:
$diskInfoString

📶 Network Statistics:
$networkStatsString

🕢 Uptime: $uptimeHours hours
🔁 Processes: $((Get-Process).Count)

🏿 $gpuLoad


$apStatus
"@
    # String 
    return $status.Trim()
}

# 💻 Status na NETWORK  (PING)
function Get-NetworkStatus {
    try {
        $hostname = $env:COMPUTERNAME
        # --- PING ---
        $pingResult = Test-Connection -ComputerName 8.8.8.8 -Count 1 -ErrorAction Stop
        $ip = $pingResult.Address.IPAddressToString
        $time = $pingResult.ResponseTime
        # --- LOCAL IP ---
        $local = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.InterfaceAlias -notlike "Loopback*" -and $_.IPAddress -notlike "169.*" } |
                 Select-Object -First 1
        $localIP = if ($local) { $local.IPAddress } else { "N/A" }
        # --- GATEWAY ---
        $gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
                    Sort-Object RouteMetric |
                    Select-Object -First 1).NextHop
        if (-not $gateway) { $gateway = "N/A" }
        # --- DNS ---
        $dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                       Select-Object -ExpandProperty ServerAddresses) -join ", "
        if (-not $dnsServers) { $dnsServers = "N/A" }
        # --- ACTIVE ADAPTER ---
        $activeAdapter = Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1
        $adapterName = if ($activeAdapter) { $activeAdapter.Name } else { "N/A" }
        $adapterType = if ($activeAdapter) { $activeAdapter.MediaType } else { "N/A" }
        # --- WIFI SSID ---
        $wifiSSID = try { 
            (netsh wlan show interfaces | Select-String '^ *SSID *: (.+)$').Matches.Groups[1].Value 
        } catch { "" }
        if (-not $wifiSSID) { $wifiSSID = "N/A" }
        # --- ALL NETWORK ADAPTERS INFO ---
		$allAdapters = Get-NetAdapter | ForEach-Object {
			$ipAddresses = (Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
							Select-Object -ExpandProperty IPAddress) -join ", "
			$gw = (Get-NetRoute -InterfaceIndex $_.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
				   Select-Object -First 1 -ExpandProperty NextHop)
			if (-not $gw) { $gw = "N/A" }
			# Adapters Virual
			$virtualRegex = 'vEthernet|WSL|Hyper-V|Virtual|VMware|VPN'
            $isVirtual = ($_.Virtual -eq $true) -or
             ($_.Name -match $virtualRegex) -or
             ($_.InterfaceDescription -match $virtualRegex)

			[PSCustomObject]@{
				Name       = $_.Name
				Status     = $_.Status
				Type       = $_.MediaType
				MAC        = $_.MacAddress
				IPs        = if ($ipAddresses) { $ipAddresses } else { "N/A" }
				Gateway    = $gw
				SpeedMbps  = if ($isVirtual) { "N/A" } else { if ($_.Speed) { [math]::Round($_.Speed / 1MB, 0) } else { "N/A" } }
			}
		}
        # --- SPEED TEST ---
        $rx = (Get-Counter '\Network Interface(*)\Bytes Received/sec').CounterSamples |
              Sort-Object CookedValue -Descending |
              Select-Object -First 1 -ExpandProperty CookedValue
        $tx = (Get-Counter '\Network Interface(*)\Bytes Sent/sec').CounterSamples |
              Sort-Object CookedValue -Descending |
              Select-Object -First 1 -ExpandProperty CookedValue

        $downloadMbps = [math]::Round(($rx * 8) / 1MB, 2)
        $uploadMbps   = [math]::Round(($tx * 8) / 1MB, 2)
        # --- OUTPUT ---
        $output = @"
🖥️ $hostname  Internet: OK
Local IP        : $localIP
Gateway         : $gateway
DNS Servers     : $dnsServers
Ping to 8.8.8.8 : $time ms ($ip)
Wi-Fi SSID      : $wifiSSID
Active Adapter  : $adapterName

"@
        # Додавање на сите адаптери
        $allAdapters | ForEach-Object {
            $output += "`n📶 Adapter: $($_.Name)
  Status   : $($_.Status)
  Type     : $($_.Type)
  MAC      : $($_.MAC)
  IPs      : $($_.IPs)
  Gateway  : $($_.Gateway)
  Speed    : $($_.SpeedMbps) Mbps
  -------------------------------------"
}
        $output += "`n🔽 Download        : $downloadMbps Mbps
🔼 Upload          : $uploadMbps Mbps`n"

        return $output
    }
    catch {
        return "⚠️ Internet: NOT WORKING!"
    }
}

# Temperatura CPU GPU MB DISK 
function Get-Temperatures {
    param(
        [string]$DllPath = "$PSScriptRoot\Dll\LibreHardwareMonitorLib.dll"
    )
    if (-not ("LibreHardwareMonitor.Hardware.Computer" -as [type])) {
        try {
            Add-Type -Path $DllPath
        } catch {
            return "⚠️ Error: Cannot load the DLL file at the specified path $DllPath."
        }
    }
	
    $computer = New-Object LibreHardwareMonitor.Hardware.Computer
    $computer.IsCpuEnabled = $true
    $computer.IsMotherboardEnabled = $true
    $computer.IsStorageEnabled = $true
    $computer.IsGpuEnabled = $true
    $computer.Open()

    $result = [System.Collections.ArrayList]::new()
    $failures = [System.Collections.ArrayList]::new()
    $motherboardTempFound = $false
    $gpuTempFound = $false

    foreach ($hardware in $computer.Hardware) {
        $hardware.Update()
        $hwTypeStr = $hardware.HardwareType.ToString()

        foreach ($sensor in $hardware.Sensors) {
            if ($sensor.SensorType -eq [LibreHardwareMonitor.Hardware.SensorType]::Temperature) {
                if (-not $sensor.Value -or $sensor.Name -match "Distance to TjMax") {
                    if (-not $sensor.Value) {
                        $null = $failures.Add("$($hardware.Name) - $($sensor.Name)")
                    }
                    continue
                }

                if ($hwTypeStr -eq "Motherboard") { $motherboardTempFound = $true }
                if ($hwTypeStr -eq "GpuAmd" -or $hwTypeStr -eq "GpuNvidia") { $gpuTempFound = $true }

                $obj = [PSCustomObject]@{
                    HardwareType = $hwTypeStr
                    HardwareName = $hardware.Name
                    Sensor       = $sensor.Name
                    TemperatureC = $sensor.Value
                }
                $null = $result.Add($obj)
            }
        }
    }
    $computer.Close()

    $output = ""
    $displayOrder = @("Cpu", "GpuAmd", "GpuNvidia", "Motherboard", "Storage")

    foreach ($type in $displayOrder) {
        $items = $result | Where-Object { $_.HardwareType -eq $type }
        if ($items.Count -gt 0) {
            switch ($type) {
                "Cpu"         { $output += "`n🔲 CPU Temp:`n" }
                "GpuAmd"      { $output += "`n🏼 GPU Temp AMD:`n" }
                "GpuNvidia"   { $output += "`n🏼 GPU Temp NVIDIA:`n" }
                "Motherboard" { $output += "`n🏿 Motherboard Temp:`n" }
                "Storage"     { $output += "`n💾 Disk Temp:`n" }
                default       { $output += "`n[$type]`n" }
            }

            foreach ($item in $items) {
            if ($type -eq "Storage") {
                $name = "● $($item.HardwareName)"
                $output += " $name - $($item.Sensor): $([math]::Round($item.TemperatureC, 2)) °C`n"
            } else {
                $output += " $($item.HardwareName) - $($item.Sensor): $([math]::Round($item.TemperatureC, 2)) °C`n"
            }
        }
    }
}
    if (-not $motherboardTempFound) {
        $output += "`nℹ️ Status: Cannot measure motherboard temperature.`n"
    }
    if (-not $gpuTempFound) {
        $output += "`nℹ️ Status: GPU temperature not found (possibly no graphics card or sensor).`n"
    }

    if ($failures.Count -gt 0) {
        $output += "`nℹ️ Some sensors could not be measured:`n"
        foreach ($fail in $failures) {
            $output += " - $fail`n"
        }
    }

    return $output.Trim()
}

# TOTAL_LOAD STATISTIC FROM LibreHardwareMonitiorLib.dll
function Get-LoadOnlyHardwareData {
    Add-Type -Path "$PSScriptRoot\Dll\HidSharp.dll"
    Add-Type -Path "$PSScriptRoot\Dll\LibreHardwareMonitorLib.dll"

    $computer = New-Object LibreHardwareMonitor.Hardware.Computer
    $computer.IsCpuEnabled = $true
    $computer.IsGpuEnabled = $true
    $computer.IsMemoryEnabled = $true
    $computer.IsMotherboardEnabled = $true
    $computer.IsControllerEnabled = $true
    $computer.IsNetworkEnabled = $true
    $computer.IsStorageEnabled = $true
    $computer.Open()
    $result = "⚙️ Hardverski parametri Part 1:`n`n"
    foreach ($hardware in $computer.Hardware) {
        $hardware.Update()
        $loadSensors = $hardware.Sensors | Where-Object { $_.SensorType -eq "Load" }
        if ($loadSensors.Count -gt 0) {
            $result += "🔹 $($hardware.Name) - $($hardware.HardwareType)`n"
            foreach ($sensor in $loadSensors) {
                $value = if ($sensor.Value -ne $null) { "{0:N1}%" -f $sensor.Value } else { "N/A" }
                $result += " ● $($sensor.Name): $value`n"
            }
            $result += "`n"
        }
    }
    $computer.Close()
    return $result
}

# TOTAL_STAT STATISTIC FROM LibreHardwareMonitiorLib.dll
function Get-NonLoadHardwareData {
    Add-Type -Path "$PSScriptRoot\Dll\HidSharp.dll"
    Add-Type -Path "$PSScriptRoot\Dll\LibreHardwareMonitorLib.dll"

    $computer = New-Object LibreHardwareMonitor.Hardware.Computer
    $computer.IsCpuEnabled = $true
    $computer.IsGpuEnabled = $true
    $computer.IsMemoryEnabled = $true
    $computer.IsMotherboardEnabled = $true
    $computer.IsControllerEnabled = $true
    $computer.IsNetworkEnabled = $true
    $computer.IsStorageEnabled = $true
    $computer.Open()
    $result = "⚙️ Hardware Parameters Part 2:`n`n"
    foreach ($hardware in $computer.Hardware) {
        $hardware.Update()
        $otherSensors = $hardware.Sensors | Where-Object { $_.SensorType -ne "Load" }
        if ($otherSensors.Count -gt 0) {
            $result += "🔸 $($hardware.Name) - $($hardware.HardwareType)`n"
            foreach ($sensor in $otherSensors) {
                $value = if ($sensor.Value -ne $null) { "{0:N2}" -f $sensor.Value } else { "N/A" }
                $result += " ● $($sensor.SensorType): $($sensor.Name) = $value`n"
            }
            $result += "`n"
        }
    }
    $computer.Close()
    return $result
}

# FOLDER Path
function Open-Folder {
    param([string]$Path)
    if (Test-Path $Path) {
        Start-Process explorer.exe $Path
    } else {
        Show-DarkWarning -Title "📁 Folder Path" -Message "Folder not found:`n$Path"
    }
}
function AutoPilot-Log           { Open-Folder "$PSScriptRoot\Autopilot_Data\Autopilot_Logs" }
function System-Monitoring-Log   { Open-Folder "$PSScriptRoot\Autopilot_Data\Monitoring_Logs" }
function Traffic-Monitoring-Log  { Open-Folder "$PSScriptRoot\Autopilot_Data\Traffic_Logs" }
function Data-Log                { Open-Folder "$PSScriptRoot\Autopilot_Data\DataFolder_Logs" }
function Network-Log             { Open-Folder "$PSScriptRoot\Autopilot_Data\Network_Logs" }
function Update-Log              { Open-Folder "$PSScriptRoot\Autopilot_Data\Update_Logs" }
function Process-Log             { Open-Folder "$PSScriptRoot\Autopilot_Data\Process_Logs" }
function Media                   { Open-Folder "$PSScriptRoot\Archive" } 
function Camera                  { Open-Folder "$PSScriptRoot\Camera" } 
function Data-Folder             { Open-Folder "$PSScriptRoot\Data" } 
function Load-Archive            { Open-Folder "$PSScriptRoot\Archive\Load" } 
function Temp-Archive            { Open-Folder "$PSScriptRoot\Archive\Temperature" } 
function Disk-Archive            { Open-Folder "$PSScriptRoot\Archive\Disk" } 
function Table-Archive           { Open-Folder "$PSScriptRoot\Archive\Table" } 

# === lIVE PANEL ===
function Show-LiveTraffic {
    $scriptPath = Join-Path $PSScriptRoot "NetMonitor.exe"
    $isRunning = Get-CimInstance Win32_Process |
                 Where-Object { $_.CommandLine -like "*NetMonitor.exe*" }
    if ($isRunning) {
		Show-DarkWarning -Title "🌎 Net Monitor Panel" -Message ("Net Monitor Panel is already started. The process is ✅ ACTIVE!")
        return
    }
    if (Test-Path $scriptPath) {
		Show-DarkWarning -Title "🌎 Net Monitor Panel" -Message ("Starting Net Monitor Panel...")
        Start-Process `
            -FilePath "$scriptPath" `
            -WindowStyle Hidden
    }
    else {
		Show-DarkWarning -Title "🌎 Net Monitor Panel" -Message ("NetMonitor.exe ⛔ not found!")
    }
}

# === System Monitor Panel (DASHBOARD) ===
function Show-SystemMonitor {
    $scriptPath = Join-Path $PSScriptRoot "SystemMonitor.exe"
    $isRunning = Get-CimInstance Win32_Process |
                 Where-Object { $_.CommandLine -like "*SystemMonitor.exe*" }
    if ($isRunning) {
		Show-DarkWarning -Title "📉 System Monitor Panel" -Message ("System Monitor Panel is already started. The process is ✅ ACTIVE!" )
        return
    }
    if (Test-Path $scriptPath) {
		Show-DarkWarning -Title "📉 System Monitor Panel" -Message ("Starting System Monitor Panel...")
        Start-Process `
            -FilePath "$scriptPath" `
            -WindowStyle Hidden
    }
    else {
		Show-DarkWarning -Title "📉 System Monitor Panel" -Message ("SystemMonitor.exe ⛔ not found!")
    }
}

# === System Monitor Panel (AUTOPILOT) ===
function Open-SystemMonitor {
    $scriptPath = Join-Path $PSScriptRoot "SystemMonitor.exe"
    $isRunning = Get-CimInstance Win32_Process |
                 Where-Object { $_.CommandLine -like "*SystemMonitor.exe*" }
    if ($isRunning) {
        $msg = "📉 System Monitor Panel is already running. The process is ✅ ACTIVE!"
		Write-Host "System Monitor Panel is already running. The process is ACTIVE!" -ForegroundColor Yellow
		Send-TelegramMessage -message $msg
        return
    }
    if (Test-Path $scriptPath) {
		$msg = "Starting 📉 System Monitor Panel..."
        Write-Host "Starting System Monitor Panel..." -ForegroundColor Cyan
        Start-Process `
            -FilePath "$scriptPath" `
            -WindowStyle Hidden
    }
    else {
		$msg = "SystemMonitor.exe ⛔ not found!"
        Write-Host "SystemMonitor.exe not found!" -ForegroundColor Red
    }
	Send-TelegramMessage -message $msg
}

# === EXIT System Monitor Panel (AUTOPILOT) ===
function Stop-SystemMonitor {
    $running = Get-CimInstance Win32_Process |
               Where-Object { $_.CommandLine -like "*SystemMonitor.exe*" }
    if ($running) {
		$msg = "❌ Exit from  📉 System Monitor Panel..."
        Write-Host "Exit from System Monitor Panel..." -ForegroundColor Cyan
        foreach ($p in $running) {
            Stop-Process -Id $p.ProcessId -Force
        }
    }
    else {
		$msg = "📉 System Monitor Panel is already ❌ EXIT!"
        Write-Host "System Monitor Panel is already EXIT!" -ForegroundColor Yellow
    }
	Send-TelegramMessage -message $msg
}

# === START MONITORING ===
function Start-Monitoring {
    $existing = Get-WmiObject Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match "SystemMonitorWorker\.ps1"
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $monitoringStartFlag = "$Global:monitoringLogsFolder\monitoring_start.flag"
    if ($existing) {
        $result = "📈 Monitoring is already Started ✅ (Active process)."
        return $result
    }
    Set-Content -Path $monitoringStartFlag -Value $timestamp -Encoding UTF8
    Add-Content -Path $Global:LogFile -Value "[$timestamp] Monitoring Started at $timestamp"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($Global:WorkerPath)`""
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($proc) {
        $result = "📈 SystemMonitorWorker process started (PID: $($proc.Id)) in $timestamp"
    } else {
        $result = "⚠️ ERROR: SystemMonitorWorker process cannot be started!"
    }
    return $result
}

# === STOP MONITORING ===
function Stop-Monitoring {
    $existing = Get-WmiObject Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match "SystemMonitorWorker\.ps1"
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $monitoringStopFlag = "$Global:monitoringLogsFolder\monitoring_stop.flag"
    if ($existing) {
        Set-Content -Path $monitoringStopFlag -Value $timestamp -Encoding UTF8
        foreach ($proc in $existing) {
            try { Stop-Process -Id $proc.ProcessId -Force } catch {}
        }
        Start-Sleep -Seconds 1
        $result = "📈 Monitoring is ⏹️ Stopped. SystemMonitorWorker script was ❌ closed at $timestamp."
    } else {
        if (Test-Path $monitoringStopFlag) {
            $realStopTime = Get-Content $monitoringStopFlag
        } else {
            $realStopTime = $timestamp
        }
        $result = "📈 Monitoring is not Started. Last ⏹️ Stopped at $realStopTime"
    }
    return $result
}

# === STATUS MONITORING ===
function Get-MonitoringStatus {
    $monitoringStartFlag = "$Global:monitoringLogsFolder\monitoring_start.flag"
    $monitoringStopFlag  = "$Global:monitoringLogsFolder\monitoring_stop.flag"
    $workerProc = Get-WmiObject Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match "SystemMonitorWorker\.ps1"
    }
    if ($workerProc -and (Test-Path $monitoringStartFlag)) {
        $startTime = Get-Content $monitoringStartFlag
        $result = "📈 Monitoring is ✅ ACTIVE. Started at $startTime."
    }
    elseif (-not $workerProc -and (Test-Path $monitoringStopFlag)) {
        $stopTime = Get-Content $monitoringStopFlag
        $result = "📈 Monitoring is ⏹️ STOPPED. Stopped at $stopTime."
    }
    elseif ((Test-Path $monitoringStartFlag) -and -not (Test-Path $monitoringStopFlag)) {
        $startTime = Get-Content $monitoringStartFlag
        $result = "📈 Monitoring may be active (process not found, start flag exists) since $startTime."
    }
    else {
        $result = "📈 Monitoring status cannot be determined ℹ️ (no flag files present)."
    }
    return $result
}

# === STOP WORKER SCRIPTS ===
function Stop-Workers {
    $result = ""
    $foundAnyRunning = $false 

    try {
        $workers = @(
            "SystemMonitorWorker\.ps1",
            "TrafficMonitorWorker\.ps1"
        )
        foreach ($worker in $workers) {
            $existing = Get-CimInstance Win32_Process | Where-Object {
                $_.Name -eq "powershell.exe" -and $_.CommandLine -match $worker
            }
            if ($existing) {
                $foundAnyRunning = $true  
                foreach ($proc in $existing) {
                    try {
                        Stop-Process -Id $proc.ProcessId -Force
                        $msg = "⚙️ Process $($proc.ProcessId) ($worker) successfully ✅ Closed."
                        $result += "$msg`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
                    } catch {
                        $msg = "ℹ️ Cannot close the process $($proc.ProcessId): $_"
                        $result += "$msg`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
                    }
                }
            } else {
                $msg = "ℹ️ No processes found for $worker"
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
            }
        }
        if ($foundAnyRunning) {
            $msg = "📈 Monitoring processes are ⏹️ STOPPED."
        } else {
            $msg = "📈 Monitoring processes are already ⏹️ STOPPED. No active monitoring processes."
        }
        [System.Windows.MessageBox]::Show($msg)
        $result += "$msg`n"
        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
    } catch {
        $msg = "⚠️ Error executing Stop-Workers: $_"
        $result += "$msg`n"
        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
    }
    return $result
}

# AutoPilot Path
$AutopilotFolder = "$PSScriptRoot\Autopilot_Data"
$AutoPilotScript = "$PSScriptRoot\Autopilot.ps1"

# 🟩 INICIJALIZACIJA NA LOGOVI ZA AUTOPILOT Main ***
$Global:logDate = Get-Date -Format 'yyyy-MM-dd'
$Global:logFolder = "$PSScriptRoot\Autopilot_Data\Autopilot_Logs"
if (-not (Test-Path $Global:logFolder)) {
    New-Item -Path $Global:logFolder -ItemType Directory | Out-Null
}
# 📄 Дневен лог фајл za AUTOPILOT
$Global:logPath = "$Global:logFolder\autopilot_$Global:logDate.txt"

# === START AUTOPILOT ===
function Start-AutoPilot {
    $result = ""

    try {
        if (-not (Test-Path $AutopilotFolder)) {
            New-Item -ItemType Directory -Path $AutopilotFolder | Out-Null
            $result += "Created Autopilot_Data 📁 folder.`n"
            Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - Created Autopilot_Data folder." -Encoding UTF8
        }
        $existing = Get-CimInstance Win32_Process | Where-Object {
            $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape($AutoPilotScript)
        }
        if ($existing) {
            $msg = "⚛️ AutoPilot.ps1 is already Started. The process is ✅ ACTIVE!"
            $result += "$msg`n"
            Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
        } else {
            $shortcutPath = Join-Path $PSScriptRoot "Shortcuts\AutoPilot.lnk"
            if (Test-Path $shortcutPath) {
                Start-Process $shortcutPath
                $msg = "⚛️ AutoPilot.ps1 Started successfully. AutoPilot is ✅ RUNNING."
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
            } else {
                $msg = "Shortcut AutoPilot.lnk ⛔ not found!"
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
            }
        }
    } catch {
        $msg = "⚠️ Error executing Start-AutoPilot: $_"
        $result += "$msg`n"
        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
    }
    return $result
}

# === STOP AUTOPILOT ===
function Stop-AutoPilot {
    $result = ""

	try {
		# STOP ALL FFMPEG PROCESSES
		try {
			if (Get-Command Stop-FfmpegExe -ErrorAction SilentlyContinue) {
				Stop-FfmpegExe
			}
		} catch {}

		$scriptsToStop = @(
			"$PSScriptRoot\Autopilot.ps1",
			"$PSScriptRoot\SystemMonitorWorker.ps1",
			"$PSScriptRoot\TrafficMonitorWorker.ps1"
		)
        $foundProcess = $false
        foreach ($script in $scriptsToStop) {
            $existing = Get-CimInstance Win32_Process | Where-Object {
                $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape($script)
            }
            if ($existing) {
                $foundProcess = $true
                foreach ($proc in $existing) {
                    try {
                        Stop-Process -Id $proc.ProcessId -Force
                        $result += "⚙️ Process $($proc.ProcessId) has been ❌ Closed.`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - Process $($proc.ProcessId) has been Closed." -Encoding UTF8
                        $childProcs = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.ProcessId)" |
                                      Where-Object { $_.Name -eq "powershell.exe" -and $_.CommandLine -like "*.ps1*" }
                        foreach ($child in $childProcs) {
                            try {
                                Stop-Process -Id $child.ProcessId -Force
                                $result += "🧩 Child Processs $($child.ProcessId) of parent $($proc.ProcessId) has been ❌ Closed.`n"
                                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - 🧩 Child Process $($child.ProcessId) of parent $($proc.ProcessId) has been ❌ Closed." -Encoding UTF8
                            } catch {
                                $msg = "ℹ️ Cannot close the child process $($child.ProcessId): $_"
                                $result += "$msg`n"
                                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
                            }
                        }
                    } catch {
                        $msg = "ℹ️ Cannot close the child process $($proc.ProcessId): $_"
                        $result += "$msg`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
                    }
                }
            }
        }
        # === STOP File.exe (ako postoi vo istiot folder) ===
        $cameraExePath = Join-Path $PSScriptRoot "FileStorage.exe"
        if (Test-Path $cameraExePath) {
            $cameraProcs = Get-Process -Name "FileStorage" -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $cameraExePath }
            foreach ($cam in $cameraProcs) {
                try {
                    Stop-Process -Id $cam.Id -Force
                    $foundProcess = $true
                    $result += "📸 FileStorage.exe process $($cam.Id) has been ❌ Closed.`n"
                    Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - FileStorage.exe process $($cam.Id) has been Closed." -Encoding UTF8
                } catch {
                    $msg = "ℹ️ Cannot close the FileStorage.exe process $($cam.Id): $_"
                    $result += "$msg`n"
                    Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
                }
            }
        }
        if (-not $foundProcess) {
            $msg = "⚛️ AutoPilot and 📈 Monitoring are already ⏹️ STOPPED!"
            $result += "$msg`n"
            Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
        }
    } catch {
        $msg = "⚠️ Error executing Stop-AutoPilot: $_"
        $result += "$msg`n"
        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
    }
    return $result
}

# === REFRESH AUTOPILOT ===
function Restart-AutoPilotWithLog {
    param ()
    $result = ""

	try {
		# STOP ALL FFMPEG PROCESSES
		try {
			if (Get-Command Stop-FfmpegExe -ErrorAction SilentlyContinue) {
				Stop-FfmpegExe
			}
		} catch {}

		$scriptsToStop = @(
			"$PSScriptRoot\Autopilot.ps1",
			"$PSScriptRoot\SystemMonitorWorker.ps1",
			"$PSScriptRoot\TrafficMonitorWorker.ps1"
		)
        $foundProcess = $false
        $killedProcesses = @()
        foreach ($script in $scriptsToStop) {
            $existing = Get-CimInstance Win32_Process | Where-Object {
                $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape($script)
            }
            if ($existing) {
                $foundProcess = $true
                foreach ($proc in $existing) {
                    try {
                        Stop-Process -Id $proc.ProcessId -Force
                        $msg = "⚙️ Process $($proc.ProcessId) ($script) has been ❌ Closed."
                        $result += "$msg`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
                        $killedProcesses += $msg
                    } catch {
                        $msg = "ℹ️ Cannot close the process $($proc.ProcessId) ($script): $_"
                        $result += "$msg`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
                    }
                }
            }
        }
        # === STOP File.exe (ako e startuvan, NE se startuva povtorno) ===
        $cameraExePath = Join-Path $PSScriptRoot "FileStorage.exe"
        if (Test-Path $cameraExePath) {
            $cameraProcs = Get-Process -Name "FileStorage" -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $cameraExePath }
            foreach ($cam in $cameraProcs) {
                try {
                    Stop-Process -Id $cam.Id -Force
                    $foundProcess = $true
                    $msg = "📸 FileStorage.exe process $($cam.Id) has been ❌ Closed."
                    $result += "$msg`n"
                    Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
                } catch {
                    $msg = "ℹ️ Cannot close the FileStorage.exe process $($cam.Id): $_"
                    $result += "$msg`n"
                    Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
                }
            }
        }
        if ($foundProcess) {
            if (-not (Test-Path $AutopilotFolder)) {
                New-Item -ItemType Directory -Path $AutopilotFolder | Out-Null
                $msg = "Create Autopilot_Data 📁 folder."
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
            }
            $autoPilotLnk = Join-Path $PSScriptRoot "Shortcuts\AutoPilot.lnk"
            if (Test-Path $autoPilotLnk) {
                Start-Process $autoPilotLnk
                $msg = "⚛️ AutoPilot Started ✅ Successfully."
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
            } else {
                $msg = "Shortcut AutoPilot.lnk ⛔ not found!"
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
            }
        } else {
            $msg = "⚛ AutoPilot and 📈 Monitoring are already ⏹️ STOPPED!"
            $result += "$msg`n"
            Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
        }
    } catch {
        $msg = "⚠️ Error executing Restart-AutoPilotWithLog: $_"
        $result += "$msg`n"
        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg" -Encoding UTF8
    }
    return $result
}

# === AUTOPILOT STATUS ===
function Get-AutoPilotStatus {
    $autoPilotRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$PSScriptRoot\Autopilot.ps1")
    }
    if ($autoPilotRunning) {
        return "ACTIVE"
    } else {
        return "STOPPED"
    }
}

# === SYSTEM STATUS ===
function Get-SystemStatus {
    $systemRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$PSScriptRoot\SystemMonitorWorker.ps1")
    }
    if ($systemRunning) { return "ACTIVE" } else { return "STOPPED" }
}

# === TRAFFIC STATUS ===
function Get-TrafficStatus {
    $trafficRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$PSScriptRoot\TrafficMonitorWorker.ps1")
    }
    if ($trafficRunning) { return "ACTIVE" } else { return "STOPPED" }
}

# === TASK-ADD ===
function Task-Add {
    param(
        [string]$TaskName = "AutoPilot",
        [string]$VbsPath  = "$PSScriptRoot\StartBot.vbs" 
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ([string]::IsNullOrWhiteSpace($TaskName)) {
        $result = @(
            "==============================",
            "🚩 TASK-CREATE ERROR",
            "🕒 Time: $ts",
            "➡️ TaskName is empty or null",
            "=============================="
        )
        $result -join "`n" | Add-Content -Path $Global:logPath -Encoding UTF8
        return $result -join "`n"
    }
    if (-not (Test-Path $VbsPath)) {
        $result = @(
            "==============================",
            "🚩 TASK-CREATE ERROR",
            "🕒 Time: $ts",
            "📑 VBS file does not exist: $VbsPath",
            "=============================="
        )
        $result -join "`n" | Add-Content -Path $Global:logPath -Encoding UTF8
        return $result -join "`n"
    }
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        $result = @(
            "==============================",
            "🚩 TASK-CREATE INFO",
            "🕒 Time: $ts",
            "➡️ TaskName: $TaskName has already been Created",
            "✅ Auto-Start is already ENABLED",
            "=============================="
        )
        $result -join "`n" | Add-Content -Path $Global:logPath -Encoding UTF8
        return $result -join "`n"
    }
    try {
        $action  = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$VbsPath`""
        $trigger = New-ScheduledTaskTrigger -AtLogOn # -AtStartup -AtLogOn
        Register-ScheduledTask -TaskName $TaskName `
                               -Action $action `
                               -Trigger $trigger `
                               -Description "AutoPilot startup task (StartBot.vbs)" `
                               -RunLevel Highest `
                               -Force | Out-Null
        $result = @(
            "==============================",
            "🚩 TASK-CREATE OK",
            "🕒 Time: $ts",
            "➡️ TaskName: $TaskName",
            "📑 VBS fajl: $VbsPath",
            "⚡ Trigger: AtLogOn",
            "✅ Auto-Start is ENABLED",
            "=============================="
        )
    }
    catch {
        $result = @(
            "==============================",
            "🚩 TASK-CREATE ERROR",
            "🕒 Time: $ts",
            "➡️ TaskName: $TaskName",
            "⚠️ Error: $_",
            "=============================="
        )
    }
    $result -join "`n" | Add-Content -Path $Global:logPath -Encoding UTF8
    return $result -join "`n"
}

# === TASK-DEL ===
function Task-Del {
    param(
        [string]$TaskName = "AutoPilot"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            $result = @(
                "==============================",
                "🚩 TASK-DELETE OK",
                "🕒 Time: $ts",
                "➡️ TaskName: $TaskName delete",
				"⛔ Auto-Start is DISABLED",
                "=============================="
            )
        }
        else {
            $result = @(
                "==============================",
                "🚩 TASK-DELETE INFO",
                "🕒 Time: $ts",
                "➡️ TaskName: $TaskName does not Exist",
				"⛔ Auto-Start is DISABLED",
                "=============================="
            )
        }
    }
    catch {
        $result = @(
            "==============================",
            "🚩 TASK-DELETE ERROR",
            "🕒 Time: $ts",
            "➡️ TaskName: $TaskName",
            "⚠️ Error: $_",
            "=============================="
        )
    }
    $result -join "`n" | Add-Content -Path $Global:logPath -Encoding UTF8
    return $result -join "`n"
}

# === TASK-SHOW ===
function Task-Show {
    param(
        [string]$TaskName = "AutoPilot"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        $result = @(
            "==============================",
            "🚩 TASK-SHOW",
            "🕒 Time: $ts",
            "➡️ TaskName: $TaskName EXISTS",
			"✅ Auto-Start is ENABLED",
            "=============================="
        )
    }
    else {
        $result = @(
            "==============================",
            "🚩 TASK-SHOW",
            "🕒 Time: $ts",
            "➡️ TaskName: $TaskName NO EXISTS",
			"⛔ Auto-Start is DISABLED",
            "=============================="
        )
    }
    $result -join "`n" | Add-Content -Path $Global:logPath -Encoding UTF8
    return $result -join "`n"
}

# ⚡ Function to Shutdown
function Auto-Shutdown-System {
    param(
        [string]$Time = (Get-Date -Format "HH:mm:ss")
    )
    Write-Log "Automatic command: The System is Shutdown now at $Time."
    Send-TelegramMessage -Message "🤖 Automatic: The System will ⛔ Shutdown in $Time"
    # Shutdown the system
    Stop-Computer -Force
}

# Function to Restart
function Auto-Restart-System {
    param(
        [string]$Time = (Get-Date -Format "HH:mm:ss")
    )
    Write-Log "Automatic command: The System is Restart now at $Time."
    Send-TelegramMessage -Message "🤖 Automatic: The System will 🔄 Restart in $Time"
    # Restart the system
    Restart-Computer -Force
}

# Function to Pause AutoPilot
function Pause-AutoPilot {
    if (-not $global:scriptPaused) {
        $global:scriptPaused = $true
        # Create the pause flag
        New-Item -Path $Global:pauseFlagPath -ItemType File -Force | Out-Null
        # Telegram message
        Send-TelegramMessage -Message "🤖 Automatic: AutoPilot is ⏸️ Paused. To Resume, send /resume"
        # Log
        Write-Log "Automatic command: AutoPilot is Paused..."
    } else {
        Send-TelegramMessage -Message "🤖 Automatic: AutoPilot is already ⏸️ Paused."
    }
}

# Function to Reset AutoPilot
function Reset-AutoPilot {
    Send-TelegramMessage -message "🤖 Automatic: AutoPilot is 🔄 Restarting..."
    Write-Log "Automatic command: AutoPilot is Restarting..."
    Stop-WorkerScripts
    Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSScriptRoot\Autopilot.ps1`""
    Stop-Process -Id $PID
}

# Function Commands List ALL
function Commands-ListAll {
    param(
        [string]$AppRoot,
        [int]$TelegramMaxLength = 4000
    )
    $cmdPath = "$PSScriptRoot\JSON\commands_edit.json"
	$scrPath = "$PSScriptRoot\JSON\scripts_edit.json"
	# ===== commands_edit.json =====
	if (-not (Test-Path $cmdPath)) {
		Send-TelegramMessage -Message "⚠️ JSON file not found: $cmdPath"
	} else {
		try {
			$cmdJson = Get-Content $cmdPath -Raw | ConvertFrom-Json
			if (-not $cmdJson.AutoCommands -or $cmdJson.AutoCommands.PSObject.Properties.Count -eq 0) {
				Send-TelegramMessage -Message "⚠️ JSON Commands are empty."
			}
		} catch {
			Send-TelegramMessage -Message "⚠️ Error reading the Commands JSON."
		}
	}
	# ===== scripts_edit.json =====
	if (-not (Test-Path $scrPath)) {
		Send-TelegramMessage -Message "⚠️ JSON file not found: $scrPath"
	} else {
		try {
			$scrJson = Get-Content $scrPath -Raw | ConvertFrom-Json
			if (-not $scrJson.ScheduledScripts -or $scrJson.ScheduledScripts.Count -eq 0) {
				Send-TelegramMessage -Message "⚠️ JSON Scripts are empty."
			}
		} catch {
			Send-TelegramMessage -Message "⚠️ Error reading the Scripts JSON."
		}
	}
    $timeline = @()
	# ================= SCRIPTS =================
	$settingsPath = "$PSScriptRoot\JSON\settings.json"
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
	$statePath = "$PSScriptRoot\JSON\autopilot_state.json"
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
	# ================= BUILD SCRIPT TIMELINE =================
	foreach($scr in $scrJson.ScheduledScripts){
		for($i = 0; $i -lt $scr.Times.Count; $i++){
			$mode = $scr.Mode[$i]
			$type = "daily"
			$timeStr = $scr.Times[$i]
			$dayStr =
				if(
					$scr.Day[$i] -and
					$scr.Day[$i].Trim() -ne ""
				) {
					$scr.Day[$i]
				}
				else {
					"No Data"
				}
			# ================= TIME =================
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
			# ================= STATUS =================
			switch ($mode.ToLower()){
				"fixed" { $status = "𝐅𝐈𝐗𝐄𝐃" }
				"loop" { $status = "𝐋𝐎𝐎𝐏" }
				default { $status = "" }
			}
			# ================= COMPLETED FIXED =================
			$completedText = ""
			if(
				$mode -eq "fixed" -and
				$dt -lt (Get-Date)
			){
				$completedText = "  <<< ✅ Completed (Time's Up)"
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
						$outOfLoopText = "  <<< ⚠️ Out of Loop (Rep:$currentR/$totalR)"
					}
				}
				# BESKONECEN LOOP: oznaka samo ako FIXED ne e vo tekovniot 24h cycle.
				elseif ($stateTotal -ieq "LOOP") {
					if (-not $fixedInWindow) {
						$outOfLoopText = "  <<< ⚠️ Out of Loop (Rep:$currentR/Loop)"
					}
				}
				# Ako sostojbata ne e dostapna, zadrzi ja starata oznaka.
				else {
					$outOfLoopText = "  <<< ⚠️ Out of Loop (Skipped)"
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
                $previewStatus = "  <<< ⛔ Skipped (Rep:$currentR)"
            }
			# ================= ADD TO TIMELINE =================
			$timeline += [PSCustomObject]@{
				Time = $dt
				Mode = $mode
				Type = $type
				Text = "$status  ⚛️ SCRIPT ($([System.IO.Path]::GetFileName($scr.Path))) Command: $($scr.Commands[$i])  🕓 Time: $timeStr 🌀 Delay: $($scr.DelaySeconds[$i]) sec  🔂 Repeat: $($scr.RepeatIntervalMinutes[$i]) min 🔃 Mode: $mode 📆 Day: $dayStr$previewStatus$completedText$outOfLoopText"
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
			# ===== ИСТА ЛОГИКА КАКО Load-Timeline =====
			if($mode -eq "fixed" -and $dayStr){
				$dt = [datetime]::ParseExact("$dayStr $timeStr","yyyy-MM-dd HH:mm:ss",$null)
			} else {
				$today = Get-Date
				$timeParts = $timeStr -split ":"
				$dt = $today.Date.AddHours([int]$timeParts[0]).AddMinutes([int]$timeParts[1]).AddSeconds([int]$timeParts[2])
				switch ($type.ToLower()) {
					"weekly" {
						while($dt.DayOfWeek -ne [System.DayOfWeek]::Sunday){
							$dt = $dt.AddDays(1)
						}
					}
					"monthly" {
						$lastDay = [datetime]::DaysInMonth($dt.Year, $dt.Month)
						$dt = [datetime]::new($dt.Year,$dt.Month,$lastDay,$dt.Hour,$dt.Minute,$dt.Second)
					}
					"yearly" {
						$dt = [datetime]::new($dt.Year,12,31,$dt.Hour,$dt.Minute,$dt.Second)
					}
					default { }
				}
			}
			# ===== STATUS =====
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
				$completedText = "  <<< ✅ Completed (Time's Up)"
			}
			# ===== TYPE TEXT (исто како Load-Timeline) =====
			switch ($type.ToLower()){
				"daily"   { $typeText = "" }
				"weekly"  { $typeText = " Mode: WEEK" }
				"monthly" { $typeText = " Mode: MONTH" }
				"yearly"  { $typeText = " Mode: YEAR" }
				default   { $typeText = "" }
			}
			# ================= ADD TO TIMELINE =================
			$timeline += [PSCustomObject]@{
				Time = $dt
				Mode = $mode
				Type = $type
				Text = "$status$typeText  🅰️ AUTO COMMAND ($($cmd.Cmd))  🕓 Time: $timeStr  🔂 Repeat: $($cmd.RepeatIntervalMinutes[$i]) min  🔀 Type: $type  🔃 Mode: $mode  📆 Day: $dayStr$completedText"
			}
		}
	}
    # ================= SORT =================
    $timeline = $timeline | Sort-Object Time
	$now = Get-Date
	$pastItems = $timeline | Where-Object { $_.Time -le $now }
	$currentItem = $pastItems | Select-Object -Last 1
	$prevItem    = $pastItems | Select-Object -Last 2 | Select-Object -First 1
	$nextItem    = $timeline | Where-Object { $_.Time -gt $now } | Select-Object -First 1
	# ===================== TOTAL + EXECUTED =====================
	$todayDate = $now.Date
	$totalCommands = @($timeline).Count
	$executedCommands = @($timeline | Where-Object {
		$_.Time -le $now
	}).Count
	$leaveCommands = @($timeline | Where-Object {
		$_.Time -gt $now -and $_.Time.Date -eq $todayDate
	}).Count
    # ================= CREATE TELEGRAM MESSAGES =================
    $messages = @()
    $currentMessage = "👩🏻‍💻 Timeline Commands`n"
    $currentMessage += "📋 Total: $totalCommands  🔥 Complete: $executedCommands  🕤 Remaing: $leaveCommands`n`n"
    $counter = 1
    foreach($item in $timeline){
        $marker = ""
			if ($prevItem -and $item.Time -eq $prevItem.Time -and $item.Text -eq $prevItem.Text) {
				$marker = "🟣🟣🟣  PREV ➤  "
			}
			elseif ($currentItem -and $item.Time -eq $currentItem.Time -and $item.Text -eq $currentItem.Text) {
				$marker = "🟢🟢🟢  LAST ➤  "
			}
			elseif ($nextItem -and $item.Time -eq $nextItem.Time -and $item.Text -eq $nextItem.Text) {
				$marker = "🔵🔵🔵  NEXT ➤  "
			}
			$line = "$counter. $marker$($item.Text)`n"
        $line += "`n"  
        if (($currentMessage.Length + $line.Length) -gt $TelegramMaxLength) {
            $messages += $currentMessage
            $currentMessage = ""
        }
        $currentMessage += $line
        $counter++
    }
	$currentMessage += "📋 Total: $totalCommands  🔥 Complete: $executedCommands  🕤 Remaing: $leaveCommands`n`n"
    if ($currentMessage.Length -gt 0) { $messages += $currentMessage }
    # ================= SEND TO TELEGRAM =================
    foreach ($msg in $messages) {
        Send-TelegramMessage -Message $msg
    }
}

# ===================== FUNCTIONS FOR CMD VISIBILITY WITH FULL RESTART =====================
# Show Terminal
function Show-CMDWindow {
    $scriptPS1 = Join-Path $PSScriptRoot "Autopilot.ps1"
    $scriptLnk = Join-Path $PSScriptRoot "Shortcuts\AutoPilot.lnk"
    # Проверка дали Autopilot.ps1 е активна
    $proc = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape($scriptPS1)
    }
    if (-not $proc) {
        Show-DarkWarning -Title "ℹ️ Info" -Message "AP Terminal is not Active."
        return
    }
    # Проверка дали прозорецот е Hidden
    $isHidden = $proc | ForEach-Object { 
        (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue).MainWindowHandle 
    } | Where-Object { $_ -ne 0 } | Measure-Object | Select-Object -ExpandProperty Count
    if ($isHidden -gt 0) {
        Show-DarkWarning -Title "ℹ️ Info" -Message "AP Terminal is already in 🔄 Visible Mode."
    } else {
        if (-not (Show-AbortWarning -Title "⚛️ AutoPilot Restart" -Message "Restarting AP Terminal in 🔄 Visible Mode...")) {
			return
		}
		# STOP FFMPEG
        Stop-FfmpegExe
        # === STOP ALL RELEVANT SCRIPTS / PROCESSES ===
        $scriptsToStop = @(
            "$PSScriptRoot\Autopilot.ps1",
            "$PSScriptRoot\SystemMonitorWorker.ps1",
            "$PSScriptRoot\TrafficMonitorWorker.ps1"
        )
        foreach ($script in $scriptsToStop) {
            $existing = Get-CimInstance Win32_Process | Where-Object {
                $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape($script)
            }
            $existing | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
        }
        # Stop File.exe if running
        $cameraExePath = Join-Path $PSScriptRoot "FileStorage.exe"
        if (Test-Path $cameraExePath) {
            $cameraProcs = Get-Process -Name "FileStorage" -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $cameraExePath }
            $cameraProcs | ForEach-Object { Stop-Process -Id $_.Id -Force }
        }
        # === START Autopilot.ink VISIBLE ===
        if (Test-Path $scriptLnk) {
            Start-Process -WindowStyle Normal -FilePath $scriptLnk
        } else {
            Show-DarkWarning -Title "⚠️ Error" -Message "AutoPilot.lnk ⛔ not found!"
        }
    }
}

# Hide Terminal
function Hide-CMDWindow {
    $scriptPS1 = Join-Path $PSScriptRoot "Autopilot.ps1"
    $scriptLnk = Join-Path $PSScriptRoot "Shortcuts\AutoPilot.lnk"
    # Проверка дали Autopilot.ps1 е активna
    $proc = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape($scriptPS1)
    }
    if (-not $proc) {
        Show-DarkWarning -Title "ℹ️ Info" -Message "AP Terminal is not Active.."
        return
    }
    # Проверка дали прозорецот е Hidden
    $isHidden = $proc | ForEach-Object { 
        (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue).MainWindowHandle 
    } | Where-Object { $_ -ne 0 } | Measure-Object | Select-Object -ExpandProperty Count
    if ($isHidden -eq 0) {
        Show-DarkWarning -Title "ℹ️ Info" -Message "AP Terminal is already in 🔄 Hidden Mode."
    } else {
        if (-not (Show-AbortWarning -Title "⚛️ AutoPilot Restart" -Message "Restarting AP Terminal in 🔄 Hidden Mode...")) {
			return
		}
		# STOP FFMPEG
        Stop-FfmpegExe
        # === STOP ALL RELEVANT SCRIPTS / PROCESSES ===
        $scriptsToStop = @(
            "$PSScriptRoot\Autopilot.ps1",
            "$PSScriptRoot\SystemMonitorWorker.ps1",
            "$PSScriptRoot\TrafficMonitorWorker.ps1"
        )
        foreach ($script in $scriptsToStop) {
            $existing = Get-CimInstance Win32_Process | Where-Object {
                $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape($script)
            }
            $existing | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
        }
        # Stop File.exe if running
        $cameraExePath = Join-Path $PSScriptRoot "FileStorage.exe"
        if (Test-Path $cameraExePath) {
            $cameraProcs = Get-Process -Name "FileStorage" -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $cameraExePath }
            $cameraProcs | ForEach-Object { Stop-Process -Id $_.Id -Force }
        }
        # === START Autopilot.ink HIDDEN ===
        if (Test-Path $scriptLnk) {
            Start-Process -WindowStyle Hidden -FilePath $scriptLnk
        } else {
            Show-DarkWarning -Title "⚠️ Error" -Message "AutoPilot.lnk ⛔ not found!"
        }
    }
}

# === DASHBOARD OPEN (AUTOPILOT) ===
function Dashboard-Open {
    $scriptPath = Join-Path $PSScriptRoot "AutoPilot.exe"
    $isRunning = Get-CimInstance Win32_Process |
                 Where-Object { $_.CommandLine -like "*AutoPilot.exe*" }
    if ($isRunning) {
        $msg = "👩🏾‍💻 Dashboard is already Open. The process is ✅ ACTIVE!"
		Write-Host "Dashboard is already Open. The process is ACTIVE!" -ForegroundColor Yellow
		Send-TelegramMessage -message $msg
        return
    }
    if (Test-Path $scriptPath) {
		$msg = "Starting 👩🏾‍💻 Dashboard..."
        Write-Host "Starting Dashboard..." -ForegroundColor Cyan
        Start-Process `
            -FilePath "$scriptPath" `
            -WindowStyle Hidden
    }
    else {
		$msg = "AutoPilot.exe ⛔ not found!"
        Write-Host "AutoPilot.exe not found!" -ForegroundColor Red
    }
	Send-TelegramMessage -message $msg
}

# === DASHBOARD EXIT (AUTOPILOT) ===
function Dashboard-Stop {
    $scriptPath = Join-Path $PSScriptRoot "AutoPilot.exe"
    $running = Get-CimInstance Win32_Process |
               Where-Object { $_.CommandLine -like "*AutoPilot.exe*" }
    if ($running) {
        $msg = "❌ Exit from  👩🏾‍💻 Dashboard..."
        Write-Host "Exit from Dashboard..." -ForegroundColor Cyan
        foreach ($p in $running) {
            $hwnd = (Get-Process -Id $p.ProcessId).MainWindowHandle
            if ($hwnd -ne 0) {
                Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WindowCloser {
    [DllImport("user32.dll")]
    public static extern bool PostMessage(
        IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam
    );
}
"@ -ErrorAction SilentlyContinue
                [WindowCloser]::PostMessage(
                    $hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero
                ) | Out-Null
            }
        }
    }
    else {
        $msg = "👩🏾‍💻 Dashboard is already ❌ EXIT!"
        Write-Host "Dashboard is already EXIT!" -ForegroundColor Yellow
    }
    Send-TelegramMessage -message $msg
}

# === PROCESS MANAGER Start (AUTOPILOT) ===
function Process-Start {
    $scriptPath = Join-Path $PSScriptRoot "ProcessManager.exe"
    $jsonFolder = Join-Path $PSScriptRoot "JSON"
    $jsonPath = Join-Path $jsonFolder "AutoStart.json"
    # === CHECK AUTOSTART JSON ===
    if (-not (Test-Path -LiteralPath $jsonFolder -PathType Container)) {
        $msg = "🛡️ Process Manager ⛔ NOT STARTED!`n📂 JSON folder not found!"
        Write-Host "JSON folder not found!" -ForegroundColor Red
        Send-TelegramMessage -message $msg
        return
    }
    if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf)) {
        $msg = "🛡️ Process Manager ⛔ NOT STARTED!`n📄 AutoStart.json not found!"
        Write-Host "AutoStart.json not found!" -ForegroundColor Red
        Send-TelegramMessage -message $msg
        return
    }
    try {
        $config = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 |
                  ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $msg = "🛡️ Process Manager ⛔ NOT STARTED!`n⚠️ AutoStart.json is invalid!"
        Write-Host "AutoStart.json is invalid!" -ForegroundColor Red
        Send-TelegramMessage -message $msg
        return
    }
    # === MONITOR & PANEL TIME SETTINGS ===
    $monitorTime = "{0:D2}:{1:D2}:{2:D2}" -f `
        $config.MonitorHours,
        $config.MonitorMinutes,
        $config.MonitorSeconds
    $panelTime = "{0:D2}:{1:D2}:{2:D2}" -f `
        $config.PanelHours,
        $config.PanelMinutes,
        $config.PanelSeconds
    if ($config.Enabled -isnot [bool] -or $config.Enabled -ne $true) {
        $msg = "🛡️ Process Manager ⛔ NOT STARTED!`n⚙️ AutoStart is disabled!"
        Write-Host "Process Manager AutoStart is disabled!" -ForegroundColor Yellow
        Send-TelegramMessage -message $msg
        return
    }
    # === CHECK IF PROCESS MANAGER IS ALREADY RUNNING ===
    $isRunning = Get-CimInstance Win32_Process |
                 Where-Object {
                     $_.Name -ieq "ProcessManager.exe"
                 }

    if ($isRunning) {
        $msg = "🛡️ Process Manager is already Open. The process is ✅ ACTIVE!"
        Write-Host "Process Manager is already Open. The process is ACTIVE!" -ForegroundColor Yellow
        Send-TelegramMessage -message $msg
        return
    }
    # === START PROCESS MANAGER ===
    if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
        $msg = "🛡️ Starting Process Manager...`n" +
               "⚛️ Monitor Time: ⏳ $monitorTime`n" +
               "📱 Panel Time: ⏳ $panelTime"
        Write-Host "Starting Process Manager..." -ForegroundColor Cyan
        Start-Process -FilePath $scriptPath -WindowStyle Hidden
    }
    else {
        $msg = "🛡️ ProcessManger.exe ⛔ not found!`n📂 Path: $scriptPath"
        Write-Host "ProcessManger.exe not found!" -ForegroundColor Red
    }
    Send-TelegramMessage -message $msg
}

# === PROCESS MANAGER Stop (AUTOPILOT) ===
function Process-Stop {
    $running = Get-CimInstance Win32_Process |
               Where-Object { $_.Name -ieq "ProcessManager.exe" }
    if ($running) {
        $msg = "❌ Exit from 🛡️ Process Manager..."
        Write-Host "Exit from Process Manager..." -ForegroundColor Cyan
        foreach ($p in $running) {
            Stop-Process -Id $p.ProcessId -Force
        }
    }
    else {
        $msg = "🛡️ Process Manager is already ❌ EXIT!"
        Write-Host "Process Manager is already EXIT!" -ForegroundColor Yellow
    }
    Send-TelegramMessage -message $msg
}

# === PROCESS MANAGER STATUS (AUTOPILOT) ===
function Process-Status {
    $scriptPath = Join-Path $PSScriptRoot "ProcessManager.exe"
    $jsonFolder = Join-Path $PSScriptRoot "JSON"
    $jsonPath = Join-Path $jsonFolder "AutoStart.json"
	$rulesPath = Join-Path $jsonFolder "Rules.json"
    $taskName = "AutoPilot-ProcessControlCenter"
    $status = @()
    $status += "🛡️ PROCESS MANAGER STATUS"
    $status += "━━━━━━━━━━━━━━━━━━━━"
    # === CHECK EXE FILE ===
    if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
        $status += "📦 EXE File: ✅ EXISTS"
    }
    else {
        $status += "📦 EXE File: ❌ NOT FOUND"
    }
    # === CHECK JSON FOLDER ===
    if (Test-Path -LiteralPath $jsonFolder -PathType Container) {
        $status += "📂 JSON Folder: ✅ EXISTS"
    }
    else {
        $status += "📂 JSON Folder: ❌ NOT FOUND"
    }
    # === CHECK JSON FILE AND AUTOSTART ===
    $autoStartEnabled = $false
    $jsonValid = $false
    if (Test-Path -LiteralPath $jsonPath -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 |
                      ConvertFrom-Json -ErrorAction Stop
            if ($config.Enabled -is [bool]) {
                $jsonValid = $true
                $autoStartEnabled = $config.Enabled
                $status += "📄 AutoStart.json: ✅ EXISTS"
                $status += "⚙️ JSON AutoStart: $(if ($autoStartEnabled) { '🟢 ENABLED' } else { '🔴 DISABLED' })"
                # === MONITOR & PANEL TIME SETTINGS ===
                $monitorTime = $null
                $panelTime = $null
                $monitorValues = @(
                    $config.MonitorHours,
                    $config.MonitorMinutes,
                    $config.MonitorSeconds
                )
                $panelValues = @(
                    $config.PanelHours,
                    $config.PanelMinutes,
                    $config.PanelSeconds
                )
                if (
                    $null -notin $monitorValues -and
                    $monitorValues[0] -is [int] -and $monitorValues[0] -ge 0 -and $monitorValues[0] -le 99 -and
                    $monitorValues[1] -is [int] -and $monitorValues[1] -ge 0 -and $monitorValues[1] -le 59 -and
                    $monitorValues[2] -is [int] -and $monitorValues[2] -ge 0 -and $monitorValues[2] -le 59
                ) {
                    $monitorTime = "{0:D2}:{1:D2}:{2:D2}" -f `
                        $config.MonitorHours,
                        $config.MonitorMinutes,
                        $config.MonitorSeconds
                    $status += "⚛️ Monitor Time: ⏳ $monitorTime"
                }
                else {
                    $status += "⚛️ Monitor Time: ❌ NOT SET"
                }
                if (
                    $null -notin $panelValues -and
                    $panelValues[0] -is [int] -and $panelValues[0] -ge 0 -and $panelValues[0] -le 99 -and
                    $panelValues[1] -is [int] -and $panelValues[1] -ge 0 -and $panelValues[1] -le 59 -and
                    $panelValues[2] -is [int] -and $panelValues[2] -ge 0 -and $panelValues[2] -le 59
                ) {
                    $panelTime = "{0:D2}:{1:D2}:{2:D2}" -f `
                        $config.PanelHours,
                        $config.PanelMinutes,
                        $config.PanelSeconds
                    $status += "📱 Panel Time: ⏳ $panelTime"
                }
                else {
                    $status += "📱 Panel Time: ❌ NOT SET"
                }
            }
            else {
                $status += "📄 AutoStart.json: ⚠️ INVALID CONFIGURATION"
                $status += "⚙️ JSON AutoStart: ❓ UNKNOWN"
            }
        }
        catch {
            $status += "📄 AutoStart.json: ❌ INVALID JSON"
            $status += "⚙️ JSON AutoStart: ❓ UNKNOWN"
        }
    }
    else {
        $status += "📄 AutoStart.json: ❌ NOT FOUND"
        $status += "⚙️ JSON AutoStart: ❌ UNAVAILABLE"
    }
    # === CHECK EXE PROCESS ===
    $running = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq "ProcessManager.exe" }
    )
    if ($running.Count -gt 0) {
        $status += "🖥️ Process: 🟢 OPEN / RUNNING"
    }
    else {
        $status += "🖥️ Process: 🔴 CLOSED / NOT RUNNING"
    }
    # === MONITOR & PANEL SESSION TIMES (FROM JSON) ===
    if ($jsonValid) {
        $parseStamp = {
            param($value)
            if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return $null }
            if ($value -is [datetime]) { return $value }
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParseExact(
                    [string]$value,
                    'yyyy-MM-dd HH:mm:ss',
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::None,
                    [ref]$parsed)) {
                return $parsed
            }
            return $null
        }
        $formatLeft = {
            param($seconds)
            if ($seconds -lt 0) { $seconds = 0 }
            $ts = [TimeSpan]::FromSeconds([math]::Floor($seconds))
            return ('{0:00}:{1:00}:{2:00}' -f [math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds)
        }
		# === CHECK RULES.JSON (ALLOWED / BLOCKED) ===
		$status += "━━━━━━━━━━━━━━━━━━━━"
		$status += "📜 RULES"
		if (Test-Path -LiteralPath $rulesPath -PathType Leaf) {
			try {
				$rules = Get-Content -LiteralPath $rulesPath -Raw -Encoding UTF8 |
						 ConvertFrom-Json -ErrorAction Stop
				$status += "📝 Rules.json: ✅ EXISTS"
				$hasAnyRule = $false
				$ruleGroups = [ordered]@{
					'PS'    = '🟦 Power Shell'
					'Other' = '🟨 PC Other'
				}
				$firstGroup = $true
				foreach ($key in $ruleGroups.Keys) {
					$group = $ruleGroups[$key]
					$groupData = $rules.$key
					if (-not $firstGroup) { $status += "" }
					$firstGroup = $false
					$allowedList = @()
					$blockedList = @()
					if ($null -ne $groupData) {
						$allowedList = @($groupData.Allowed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
						$blockedList = @($groupData.Blocked | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
					}
					if ($allowedList.Count -gt 0) {
						$hasAnyRule = $true
						$status += "$group 🟢 Allowed ($($allowedList.Count)):"
						foreach ($item in $allowedList) { $status += " ✅ $item" }
					}
					else {
						$status += "$group 🟢 Allowed: None"
					}
					if ($blockedList.Count -gt 0) {
						$hasAnyRule = $true
						$status += "$group 🔴 Blocked ($($blockedList.Count)):"
						foreach ($item in $blockedList) { $status += " ⛔ $item" }
					}
					else {
						$status += "$group 🔴 Blocked: None"
					}
				}
				if (-not $hasAnyRule) {
					$status += "ℹ️ Rules.json exists, but no rules are set"
				}
			}
			catch {
				$status += "📝 Rules.json: ❌ INVALID JSON"
			}
		}
		else {
			$status += "📝 Rules.json: ❌ NOT FOUND"
			$status += "⚠️ No rules are set"
		}
        $monitorStart = & $parseStamp $config.MonitorStartTime
        $monitorStop  = & $parseStamp $config.MonitorStopTime
        $panelStart   = & $parseStamp $config.PanelStartTime
        $panelStop    = & $parseStamp $config.PanelStopTime
        # Total configured duration in seconds (used only to calculate the remaining time)
        $monitorTotalSeconds = $null
        $panelTotalSeconds = $null
        try {
            $monitorTotalSeconds = ([int]$config.MonitorHours * 3600) + ([int]$config.MonitorMinutes * 60) + [int]$config.MonitorSeconds
        }
        catch { $monitorTotalSeconds = $null }
        try {
            $panelTotalSeconds = ([int]$config.PanelHours * 3600) + ([int]$config.PanelMinutes * 60) + [int]$config.PanelSeconds
        }
        catch { $panelTotalSeconds = $null }
        $now = Get-Date
        # --- Monitor remaining ---
        $monitorLeftText = ' None'
        if ($monitorStart -and $monitorStop) {
            $monitorLeftText = '(Monitor ⏹️ Stopped)'
        }
        elseif ($monitorStart) {
            if ($running.Count -eq 0) {
                $monitorLeftText = '⚠️ UNKNOWN (process not running)'
            }
            elseif ($null -eq $monitorTotalSeconds -or $monitorTotalSeconds -le 0) {
                $monitorLeftText = '❓ UNKNOWN'
            }
            else {
                $monitorLeft = ($monitorStart.AddSeconds($monitorTotalSeconds) - $now).TotalSeconds
                if ($monitorLeft -le 0) { $monitorLeftText = '00:00:00 (expired)' }
                else { $monitorLeftText = & $formatLeft $monitorLeft }
            }
        }
        # --- Panel remaining ---
        $panelLeftText = ' None'
        if ($panelStart -and $panelStop) {
            $panelLeftText = '(Panel ⛔ Closed)'
        }
        elseif ($panelStart) {
            if ($running.Count -eq 0) {
                $panelLeftText = '⚠️ UNKNOWN (process not running)'
            }
            elseif ($null -eq $panelTotalSeconds -or $panelTotalSeconds -le 0) {
                $panelLeftText = '❓ UNKNOWN'
            }
            else {
                $panelLeft = ($panelStart.AddSeconds($panelTotalSeconds) - $now).TotalSeconds
                if ($panelLeft -le 0) { $panelLeftText = '00:00:00 (expired)' }
                else { $panelLeftText = & $formatLeft $panelLeft }
            }
        }
        $status += "━━━━━━━━━━━━━━━━━━━━"
        $status += "♻️ SESSION"
        $status += "🟢 Monitor Start: 🕓 $(if ($monitorStart) { $monitorStart.ToString('yyyy-MM-dd HH:mm:ss') } else { ' Not Recorder' })"
        $status += "🔴 Monitor Stop: 🕙 $(if ($monitorStop) { $monitorStop.ToString('yyyy-MM-dd HH:mm:ss') } else { ' None' })"
        $status += "🟢 Panel Start: 🕓 $(if ($panelStart) { $panelStart.ToString('yyyy-MM-dd HH:mm:ss') } else { ' Not Recorder' })"
        $status += "🔴️ Panel Closed: 🕙 $(if ($panelStop) { $panelStop.ToString('yyyy-MM-dd HH:mm:ss') } else { ' None' })"
        $status += "🔵 Monitor Remaining: ⏳ $monitorLeftText"
        $status += "🟣 Panel Remaining: ⏳ $panelLeftText"
    }
    # === CHECK WINDOWS TASK SCHEDULER ===
    $task = $null
    $taskAvailable = $false
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $taskAvailable = $true
        $status += "━━━━━━━━━━━━━━━━━━━━"
        $status += "📋 WINDOWS STARTUP TASK"
        $status += "🚩 Task Name: $taskName"
        $status += "📋 Task Exists: ✅ YES"
        if ($task.State -eq 'Disabled') {
            $status += "⚙️ Task Status: 🔴 DISABLED"
        }
        else {
            $status += "⚙️ Task Status: 🟢 ENABLED"
        }
        # Check whether a trigger starts at Windows boot or user logon
        $startupTriggers = @(
            $task.Triggers | Where-Object {
                $_.CimClass.CimClassName -in @(
                    'MSFT_TaskBootTrigger',
                    'MSFT_TaskLogonTrigger'
                )
            }
        )
        if ($startupTriggers.Count -gt 0) {
            if ($task.State -eq 'Disabled') {
                $status += "🚀 Windows Auto-Start: ⚠️ CONFIGURED, BUT TASK DISABLED"
            }
            else {
                $status += "🚀 Windows Auto-Start: ✅ CONFIGURED"
            }
        }
        else {
            $status += "🚀 Windows Auto-Start: ❌ NO BOOT/LOGON TRIGGER"
        }
    }
    catch {
        $status += "━━━━━━━━━━━━━━━━━━━━"
        $status += "📋 WINDOWS STARTUP TASK"
        $status += "🚩 Task Name: $taskName"
        $status += "📋 Task Exists: ❌ NO"
        $status += "🚀 Windows Auto-Start: ❌ NOT CONFIGURED"
    }
    # === OVERALL RESULT ===
    $status += "━━━━━━━━━━━━━━━━━━━━"
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        $status += "⚠️ RESULT: EXE FILE MISSING"
    }
    elseif (-not $jsonValid) {
        $status += "⚠️ RESULT: JSON CONFIGURATION UNAVAILABLE"
    }
    elseif (-not $autoStartEnabled) {
        $status += "⛔ RESULT: JSON AUTOSTART DISABLED"
    }
    elseif ($running.Count -eq 0) {
        $status += "🟡 RESULT: PROCESS NOT RUNNING"
    }
    else {
        $status += "✅ RESULT: PROCESS ACTIVE"
    }
    $message = $status -join "`n"
    Write-Host $message
    Send-TelegramMessage -message $message
}

# === PROCESS MANAGER START (AUTOMATION COMMAND) ===
function ProcessManager-Start {
    $scriptPath = Join-Path $PSScriptRoot "ProcessManager.exe"
    $jsonFolder = Join-Path $PSScriptRoot "JSON"
    $jsonPath = Join-Path $jsonFolder "AutoStart.json"
	# === AUTOMATIC COMMAND INFORMATION ===
    $autoStart = "`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
    # === LOCAL AUDIT LOG FUNCTION ===
    $logFile = Join-Path $Global:processManagerLogsFolder (
        "ProcessLog_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd')
    )
    function Write-ProcessManagerAutomationLog {
        param([string]$Message)
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logEntry = "[$timestamp] [ProcessManager-Start] $Message"
        try {
            if (-not (Test-Path -LiteralPath $Global:processManagerLogsFolder -PathType Container)) {
                New-Item -Path $Global:processManagerLogsFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            Add-Content -LiteralPath $logFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Host "Failed to write Process Manager log: $($_.Exception.Message)$autoStart" -ForegroundColor Red
        }
    }
    # === CHECK AUTOSTART JSON ===
    if (-not (Test-Path -LiteralPath $jsonFolder -PathType Container)) {
        $msg = "🛡️ Process Manager ⛔ NOT STARTED!`n📂 JSON folder not found!$autoStart"
        Write-Host "JSON folder not found!$autoStart" -ForegroundColor Red
        Write-ProcessManagerAutomationLog "START FAILED - JSON folder not found: $jsonFolder$autoStart"
        Send-TelegramMessage -message $msg
        return
    }
    if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf)) {
        $msg = "🛡️ Process Manager ⛔ NOT STARTED!`n📄 AutoStart.json not found!$autoStart"
        Write-Host "AutoStart.json not found!$autoStart" -ForegroundColor Red
        Write-ProcessManagerAutomationLog "START FAILED - AutoStart.json not found: $jsonPath$autoStart"
        Send-TelegramMessage -message $msg
        return
    }
    try {
        $config = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 |
                  ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $msg = "🛡️ Process Manager ⛔ NOT STARTED!`n⚠️ AutoStart.json is invalid!$autoInfo$autoStart"
        Write-Host "AutoStart.json is invalid!$autoStart" -ForegroundColor Red
        Write-ProcessManagerAutomationLog "START FAILED - Invalid AutoStart.json. Error: $($_.Exception.Message)$autoStart"
        Send-TelegramMessage -message $msg
        return
    }
    if ($config.Enabled -isnot [bool] -or $config.Enabled -ne $true) {
        $msg = "🛡️ Process Manager ⛔ NOT STARTED!`n⚙️ AutoStart is disabled!$autoStart"
        Write-Host "Process Manager AutoStart is disabled!$autoStart" -ForegroundColor Yellow
        Write-ProcessManagerAutomationLog "START BLOCKED - AutoStart is disabled or Enabled is not a Boolean true.$autoStart"
        Send-TelegramMessage -message $msg
        return
    }
    # === CHECK IF PROCESS MANAGER IS ALREADY RUNNING ===
    try {
        $isRunning = @(
            Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object { $_.Name -ieq "ProcessManager.exe" }
        )
    }
    catch {
        $msg = "🛡️ Process Manager ⛔ NOT STARTED!`n⚠️ Could not check running processes.$autoStart"
        Write-Host "Could not check running processes!$autoStart" -ForegroundColor Red
        Write-ProcessManagerAutomationLog "START FAILED - Could not check running processes. Error: $($_.Exception.Message)$autoStart"
        Send-TelegramMessage -message $msg
        return
    }
    if ($isRunning.Count -gt 0) {
        $msg = "🛡️ Process Manager is already Open. The process is ✅ ACTIVE!$autoStart"
        Write-Host "Process Manager is already Open. The process is ACTIVE!$autoStart" -ForegroundColor Yellow
        Write-ProcessManagerAutomationLog "START SKIPPED - ProcessManager.exe is already running. PID(s): $($isRunning.ProcessId -join ', ')$autoStart"
        Send-TelegramMessage -message $msg
        return
    }
    # === START PROCESS MANAGER ===
    if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
        try {
            Write-Host "Starting Process Manager...$autoStart" -ForegroundColor Cyan
            Start-Process -FilePath $scriptPath -WindowStyle Hidden -ErrorAction Stop
            $msg = "🛡️ Starting Process Manager...$autoStart"
            Write-ProcessManagerAutomationLog "START REQUEST SENT - Executable: $scriptPath$autoStart"
        }
        catch {
            $msg = "🛡️ Process Manager ⛔ FAILED TO START!`n⚠️ $($_.Exception.Message)$autoStart"
            Write-Host "Failed to start Process Manager!$autoStart" -ForegroundColor Red
            Write-ProcessManagerAutomationLog "START FAILED - Error: $($_.Exception.Message)$autoStart"
        }
    }
    else {
        $msg = "🛡️ ProcessManager.exe ⛔ not found!`n📂 Path: $scriptPath$autoStart"
        Write-Host "ProcessManager.exe not found!$autoStart" -ForegroundColor Red
        Write-ProcessManagerAutomationLog "START FAILED - Executable not found: $scriptPath$autoStart"
    }
    Send-TelegramMessage -message $msg
}

# === PROCESS MANAGER STOP (AUTOMATION COMMAND) ===
function ProcessManager-Stop {
	# === AUTOMATIC COMMAND INFORMATION ===
    $autoStop = "`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
    $logFile = Join-Path $Global:processManagerLogsFolder (
        "ProcessLog_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd')
    )
    function Write-ProcessManagerAutomationLog {
        param([string]$Message)
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logEntry = "[$timestamp] [ProcessManager-Stop] $Message"
        try {
            if (-not (Test-Path -LiteralPath $Global:processManagerLogsFolder -PathType Container)) {
                New-Item -Path $Global:processManagerLogsFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            Add-Content -LiteralPath $logFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Host "Failed to write Process Manager log: $($_.Exception.Message)$autoStop" -ForegroundColor Red
        }
    }
    # === CHECK AND STOP PROCESS MANAGER ===
    try {
        $running = @(
            Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object { $_.Name -ieq "ProcessManager.exe" }
        )
    }
    catch {
        $msg = "🛡️ Process Manager ⚠️ Could not check running processes.$autoStop"
        Write-Host "Could not check running processes!$autoStop" -ForegroundColor Red
        Write-ProcessManagerAutomationLog "STOP FAILED - Could not check running processes. Error: $($_.Exception.Message)$autoStop"
        Send-TelegramMessage -message $msg
        return
    }
    if ($running.Count -gt 0) {
        $msg = "❌ Exit from 🛡️ Process Manager...$autoStop"
        Write-Host "Exit from Process Manager...$autoStop" -ForegroundColor Cyan
        $stoppedCount = 0
        foreach ($p in $running) {
            try {
                Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
                $stoppedCount++
                Write-ProcessManagerAutomationLog "STOP REQUEST SENT - PID: $($p.ProcessId)$autoStop"
            }
            catch {
                Write-ProcessManagerAutomationLog "STOP FAILED - PID: $($p.ProcessId). Error: $($_.Exception.Message)$autoStop"
            }
        }
        if ($stoppedCount -eq 0) {
            $msg = "🛡️ Process Manager ⚠️ FAILED TO STOP!$autoStop"
            Write-Host "Failed to stop Process Manager!$autoStop" -ForegroundColor Red
        }
        else {
            Write-ProcessManagerAutomationLog "STOP COMPLETED - Stop request sent for $stoppedCount process(es).$autoStop"
        }
    }
    else {
        $msg = "🛡️ Process Manager is already ❌ EXIT!$autoStop"
        Write-Host "Process Manager is already EXIT!$autoStop" -ForegroundColor Yellow
        Write-ProcessManagerAutomationLog "STOP SKIPPED - ProcessManager.exe is not running.$autoStop"
    }
    Send-TelegramMessage -message $msg
}

# ===================== VLC PLAYER =====================
# Play
function Play-Radio {
    if (-not (Test-Path -LiteralPath $vlcPath -PathType Leaf)) {
        $msg = "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
        Write-Log "VLC RADIO: $msg"
        Send-TelegramMessage -message $msg
        return $msg
    }
    if (-not (Test-VLCRadioStations)) {
        $msg = "⚠️ VLC radio unavailable: $($global:VlcRadioConfigProblem)`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
        Write-Log "VLC RADIO: $msg"
        Send-TelegramMessage -message $msg
        return $msg
    }
    # Close any active VLC before starting a new stream
    Get-Process vlc -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
    $index = $global:CurrentStationIndex
    $url = $global:RadioStations[$index]
    $title = "RadioStation $($index + 1)"
    $path = $vlcRadioSettingsPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $PSScriptRoot "JSON\vlc_radio.json"
    }
    try {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $cfg = Get-Content -LiteralPath $path -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            $titles = @($cfg.RADIO_STATION_TITLES)
            if (
                $index -lt $titles.Count -and
                $titles[$index] -is [string] -and
                -not [string]::IsNullOrWhiteSpace($titles[$index])
            ) {
                $title = $titles[$index].Trim()
            }
        }
    }
    catch {}
    try {
        Start-Process -FilePath $vlcPath -ArgumentList $url -ErrorAction Stop
        $msg = "🔊 Station started: $($index + 1). $title`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
        Write-Log "VLC RADIO: $msg"
        Send-TelegramMessage -message $msg
        return $msg
    }
    catch {
        $msg = "⚠️ Failed to start VLC: $($_.Exception.Message)"
        Write-Log "VLC RADIO ERROR: $msg"
        Send-TelegramMessage -message $msg
        return $msg
    }
}
# Stop
function Stop-Radio {
    if (-not (Test-Path -LiteralPath $vlcPath -PathType Leaf)) {
        $msg = "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
        Write-Log "VLC RADIO: $msg"
        Send-TelegramMessage -message $msg
        return $msg
    }
    Get-Process vlc -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
    $msg = "VLC is ❌ closed.`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
    Write-Log "VLC RADIO: $msg"
    Send-TelegramMessage -message $msg
    return $msg
}
# Next
function Next-Radio {
    if (-not (Test-Path -LiteralPath $vlcPath -PathType Leaf)) {
        $msg = "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
        Write-Log "VLC RADIO: $msg"
        Send-TelegramMessage -message $msg
        return $msg
    }
    if (-not (Test-VLCRadioStations)) {
        $msg = "⚠️ VLC radio unavailable: $($global:VlcRadioConfigProblem)`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
        Write-Log "VLC RADIO: $msg"
        Send-TelegramMessage -message $msg
        return $msg
    }
    $global:CurrentStationIndex = (
        $global:CurrentStationIndex + 1
    ) % $global:RadioStations.Count
    return Play-Radio
}
# Prev
function Prev-Radio {
    if (-not (Test-Path -LiteralPath $vlcPath -PathType Leaf)) {
        $msg = "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
        Write-Log "VLC RADIO: $msg"
        Send-TelegramMessage -message $msg
        return $msg
    }
    if (-not (Test-VLCRadioStations)) {
        $msg = "⚠️ VLC radio unavailable: $($global:VlcRadioConfigProblem)`n`n🤖 Automatic command: $commandKey`n🕒 Time: $((Get-Date).ToString('dd.MM.yyyy - HH:mm:ss'))"
        Write-Log "VLC RADIO: $msg"
        Send-TelegramMessage -message $msg
        return $msg
    }
    $global:CurrentStationIndex = $global:CurrentStationIndex - 1
    if ($global:CurrentStationIndex -lt 0) {
        $global:CurrentStationIndex = $global:RadioStations.Count - 1
    }
    return Play-Radio
}

########################################################################################################################### System End.
