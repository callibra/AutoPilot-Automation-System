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
        ForEach-Object { "$($_.DeviceID): $([math]::Round($_.FreeSpace/1GB,2))GB free of $([math]::Round($_.Size/1GB,2))GB" }
    ) -join "`n"
    # Network adapters
    $networkStatsString = (Get-CimInstance Win32_NetworkAdapter |
        Where-Object NetEnabled -eq $true |
        ForEach-Object { "$($_.Description): Status - $($_.NetConnectionStatus)" }
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
        $gpuLoad = "GPU Load: Not Available"
    }
    # Compose output
    $status = @"
System Status:
CPU Usage: $cpu %
RAM: $usedRAM GB / $totalRAM GB ($ramPercent%)

Disk:
$diskInfoString

Network Statistics:
$networkStatsString

Uptime: $uptimeHours hours
Processes: $((Get-Process).Count)

$gpuLoad
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
[$hostname] Internet: OK
Local IP        : $localIP
Gateway         : $gateway
DNS Servers     : $dnsServers
Ping to 8.8.8.8 : $time ms ($ip)
Wi-Fi SSID      : $wifiSSID
Active Adapter  : $adapterName

"@
        # Adapters
        $allAdapters | ForEach-Object {
            $output += "`n* Adapter: $($_.Name)
  Status   : $($_.Status)
  Type     : $($_.Type)
  MAC      : $($_.MAC)
  IPs      : $($_.IPs)
  Gateway  : $($_.Gateway)
  Speed    : $($_.SpeedMbps) Mbps
  -------------------------------------"
}
        $output += "`n* Download        : $downloadMbps Mbps
* Upload          : $uploadMbps Mbps`n"

        return $output
    }
    catch {
        return "Internet: NOT WORKING!"
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
            return "Error: Cannot load the DLL file at the specified path $DllPath."
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
                "Cpu"         { $output += "`n[CPU Temp]`n" }
                "GpuAmd"      { $output += "`n[GPU Temp AMD]`n" }
                "GpuNvidia"   { $output += "`n[GPU Temp NVIDIA]`n" }
                "Motherboard" { $output += "`n[Motherboard Temp]`n" }
                "Storage"     { $output += "`n[Disk Temp]`n" }
                default       { $output += "`n[$type]`n" }
            }

            foreach ($item in $items) {
            if ($type -eq "Storage") {
                $name = "** $($item.HardwareName)"
                $output += " $name - $($item.Sensor): $([math]::Round($item.TemperatureC, 2)) °C`n"
            } else {
                $output += " $($item.HardwareName) - $($item.Sensor): $([math]::Round($item.TemperatureC, 2)) °C`n"
            }
        }
    }
}
    if (-not $motherboardTempFound) {
        $output += "`nStatus: Cannot measure motherboard temperature.`n"
    }
    if (-not $gpuTempFound) {
        $output += "`nStatus: GPU temperature not found (possibly no graphics card or sensor).`n"
    }

    if ($failures.Count -gt 0) {
        $output += "`nSome sensors could not be measured:`n"
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
    $result = "*Hardverski parametri Part 1:*`n`n"
    foreach ($hardware in $computer.Hardware) {
        $hardware.Update()
        $loadSensors = $hardware.Sensors | Where-Object { $_.SensorType -eq "Load" }
        if ($loadSensors.Count -gt 0) {
            $result += "*$($hardware.Name)* - $($hardware.HardwareType)`n"
            foreach ($sensor in $loadSensors) {
                $value = if ($sensor.Value -ne $null) { "{0:N1}%" -f $sensor.Value } else { "N/A" }
                $result += " - $($sensor.Name): $value`n"
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
    $result = "*Hardware Parameters Part 2:*`n`n"
    foreach ($hardware in $computer.Hardware) {
        $hardware.Update()
        $otherSensors = $hardware.Sensors | Where-Object { $_.SensorType -ne "Load" }
        if ($otherSensors.Count -gt 0) {
            $result += "*$($hardware.Name)* - $($hardware.HardwareType)`n"
            foreach ($sensor in $otherSensors) {
                $value = if ($sensor.Value -ne $null) { "{0:N2}" -f $sensor.Value } else { "N/A" }
                $result += " - $($sensor.SensorType): $($sensor.Name) = $value`n"
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
        Show-DarkWarning -Title "Folder Path" -Message "Folder not found:`n$Path"
    }
}
function AutoPilot-Log           { Open-Folder "$PSScriptRoot\Autopilot_Data\Autopilot_Logs" }
function System-Monitoring-Log   { Open-Folder "$PSScriptRoot\Autopilot_Data\Monitoring_Logs" }
function Traffic-Monitoring-Log  { Open-Folder "$PSScriptRoot\Autopilot_Data\Traffic_Logs" }
function Data-Log                { Open-Folder "$PSScriptRoot\Autopilot_Data\DataFolder_Logs" }
function Network-Log             { Open-Folder "$PSScriptRoot\Autopilot_Data\Network_Logs" }
function Update-Log              { Open-Folder "$PSScriptRoot\Autopilot_Data\Update_Logs" }
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
		Show-DarkWarning -Title "Live Traffic Panel" -Message ("Live Traffic Panel is already started. The process is ACTIVE!")
        return
    }
    if (Test-Path $scriptPath) {
		Show-DarkWarning -Title "Live Traffic Panel" -Message ("Starting Live Traffic Panel...")
        Start-Process `
            -FilePath "$scriptPath" `
            -WindowStyle Hidden
    }
    else {
		Show-DarkWarning -Title "Live Traffic Panel" -Message ("NetMonitor.exe not found!")
    }
}

# === System Monitor Panel (DASHBOARD) ===
function Show-SystemMonitor {
    $scriptPath = Join-Path $PSScriptRoot "SystemMonitor.exe"
    $isRunning = Get-CimInstance Win32_Process |
                 Where-Object { $_.CommandLine -like "*SystemMonitor.exe*" }
    if ($isRunning) {
		Show-DarkWarning -Title "System Monitor Panel" -Message ("System Monitor Panel is already started. The process is ACTIVE!" )
        return
    }
    if (Test-Path $scriptPath) {
		Show-DarkWarning -Title "System Monitor Panel" -Message ("Starting System Monitor Panel...")
        Start-Process `
            -FilePath "$scriptPath" `
            -WindowStyle Hidden
    }
    else {
		Show-DarkWarning -Title "System Monitor Panel" -Message ("SystemMonitor.exe not found!")
    }
}

# === System Monitor Panel (AUTOPILOT) ===
function Open-SystemMonitor {
    $scriptPath = Join-Path $PSScriptRoot "SystemMonitor.exe"
    $isRunning = Get-CimInstance Win32_Process |
                 Where-Object { $_.CommandLine -like "*SystemMonitor.exe*" }
    if ($isRunning) {
        $msg = "System Monitor Panel is already running. The process is ACTIVE!"
		Write-Host "System Monitor Panel is already running. The process is ACTIVE!" -ForegroundColor Yellow
		Send-TelegramMessage -message $msg
        return
    }
    if (Test-Path $scriptPath) {
		$msg = "Starting System Monitor Panel..."
        Write-Host "Starting System Monitor Panel..." -ForegroundColor Cyan
        Start-Process `
            -FilePath "$scriptPath" `
            -WindowStyle Hidden
    }
    else {
		$msg = "SystemMonitor.exe not found!"
        Write-Host "SystemMonitor.exe not found!" -ForegroundColor Red
    }
	Send-TelegramMessage -message $msg
}

# === EXIT System Monitor Panel (AUTOPILOT) ===
function Stop-SystemMonitor {
    $running = Get-CimInstance Win32_Process |
               Where-Object { $_.CommandLine -like "*SystemMonitor.exe*" }
    if ($running) {
		$msg = "Exit System Monitor Panel..."
        Write-Host "Exit System Monitor Panel..." -ForegroundColor Cyan
        foreach ($p in $running) {
            Stop-Process -Id $p.ProcessId -Force
        }
    }
    else {
		$msg = "System Monitor Panel is already EXIT!"
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
        $result = "Monitoring is already Started (Active process)."
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
        $result = "SystemMonitorWorker process started (PID: $($proc.Id)) in $timestamp"
    } else {
        $result = "ERROR: SystemMonitorWorker process cannot be started!"
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
        $result = "Monitoring is Stopped. SystemMonitorWorker script was closed at $timestamp."
    } else {
        if (Test-Path $monitoringStopFlag) {
            $realStopTime = Get-Content $monitoringStopFlag
        } else {
            $realStopTime = $timestamp
        }
        $result = "Monitoring is not Started. Last Stopped at $realStopTime"
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
        $result = "Monitoring is ACTIVE. Started at $startTime."
    }
    elseif (-not $workerProc -and (Test-Path $monitoringStopFlag)) {
        $stopTime = Get-Content $monitoringStopFlag
        $result = "Monitoring is STOPPED. Stopped at $stopTime."
    }
    elseif ((Test-Path $monitoringStartFlag) -and -not (Test-Path $monitoringStopFlag)) {
        $startTime = Get-Content $monitoringStartFlag
        $result = "Monitoring may be active (process not found, start flag exists) since $startTime."
    }
    else {
        $result = "Monitoring status cannot be determined (no flag files present)."
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
                        $msg = "Process $($proc.ProcessId) ($worker) successfully Closed."
                        $result += "$msg`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
                    } catch {
                        $msg = "Cannot close the process $($proc.ProcessId): $_"
                        $result += "$msg`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
                    }
                }
            } else {
                $msg = "No processes found for $worker"
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
            }
        }
        if ($foundAnyRunning) {
            $msg = "Monitoring processes are STOPPED."
        } else {
            $msg = "Monitoring processes are already STOPPED. No active monitoring processes."
        }
        [System.Windows.MessageBox]::Show($msg)
        $result += "$msg`n"
        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
    } catch {
        $msg = "Error executing Stop-Workers: $_"
        $result += "$msg`n"
        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
    }
    return $result
}

# AutoPilot Path
$AutopilotFolder = "$PSScriptRoot\Autopilot_Data"
$AutoPilotScript = "$PSScriptRoot\AutoPilot.ps1"

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
            $result += "Created AutoPilot_Data folder.`n"
            Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - Created AutoPilot_Data folder."
        }
        $existing = Get-CimInstance Win32_Process | Where-Object {
            $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape($AutoPilotScript)
        }
        if ($existing) {
            $msg = "AutoPilot.ps1 is already Started. The process is ACTIVE!"
            $result += "$msg`n"
            Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
        } else {
            $shortcutPath = Join-Path $PSScriptRoot "Shortcuts\AutoPilot.lnk"
            if (Test-Path $shortcutPath) {
                Start-Process $shortcutPath
                $msg = "AutoPilot.ps1 Started successfully. AutoPilot is RUNNING."
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
            } else {
                $msg = "Shortcut AutoPilot.lnk not found!"
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
            }
        }
    } catch {
        $msg = "Error executing Start-AutoPilot: $_"
        $result += "$msg`n"
        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
    }
    return $result
}

# === STOP AUTOPILOT ===
function Stop-AutoPilot {
    $result = ""

    try {
        $scriptsToStop = @(
            $AutoPilotScript,
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
                        $result += "Process $($proc.ProcessId) has been Closed.`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - Process $($proc.ProcessId) has been Closed."
                        $childProcs = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.ProcessId)" |
                                      Where-Object { $_.Name -eq "powershell.exe" -and $_.CommandLine -like "*.ps1*" }
                        foreach ($child in $childProcs) {
                            try {
                                Stop-Process -Id $child.ProcessId -Force
                                $result += "Child Processs $($child.ProcessId) na $($proc.ProcessId) has been Closed.`n"
                                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - Child Process $($child.ProcessId) na $($proc.ProcessId) has been Closed."
                            } catch {
                                $msg = "Cannot close the child process $($child.ProcessId): $_"
                                $result += "$msg`n"
                                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
                            }
                        }
                    } catch {
                        $msg = "Cannot close the child process $($proc.ProcessId): $_"
                        $result += "$msg`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
                    }
                }
            }
        }
        # === STOP Camera.exe (ako postoi vo istiot folder) ===
        $cameraExePath = Join-Path $PSScriptRoot "Camera.exe"
        if (Test-Path $cameraExePath) {
            $cameraProcs = Get-Process -Name "Camera" -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $cameraExePath }
            foreach ($cam in $cameraProcs) {
                try {
                    Stop-Process -Id $cam.Id -Force
                    $foundProcess = $true
                    $result += "Camera.exe process $($cam.Id) has been Closed.`n"
                    Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - Camera.exe process $($cam.Id) has been Closed."
                } catch {
                    $msg = "Cannot close the Camera.exe process $($cam.Id): $_"
                    $result += "$msg`n"
                    Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
                }
            }
        }
        if (-not $foundProcess) {
            $msg = "AutoPilot and Monitoring are already STOPPED!"
            $result += "$msg`n"
            Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
        }
    } catch {
        $msg = "Error executing Stop-AutoPilot: $_"
        $result += "$msg`n"
        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
    }
    return $result
}

# === REFRESH AUTOPILOT ===
function Restart-AutoPilotWithLog {
    param ()
    $result = ""

    try {
        $scriptsToStop = @(
            "$PSScriptRoot\AutoPilot.ps1",
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
                        $msg = "Process $($proc.ProcessId) ($script) has been Closed."
                        $result += "$msg`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
                        $killedProcesses += $msg
                    } catch {
                        $msg = "Cannot close the process $($proc.ProcessId) ($script): $_"
                        $result += "$msg`n"
                        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
                    }
                }
            }
        }
        # === STOP Camera.exe (ako e startuvan, NE se startuva povtorno) ===
        $cameraExePath = Join-Path $PSScriptRoot "Camera.exe"
        if (Test-Path $cameraExePath) {
            $cameraProcs = Get-Process -Name "Camera" -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $cameraExePath }
            foreach ($cam in $cameraProcs) {
                try {
                    Stop-Process -Id $cam.Id -Force
                    $foundProcess = $true
                    $msg = "Camera.exe process $($cam.Id) has been Closed."
                    $result += "$msg`n"
                    Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
                } catch {
                    $msg = "Cannot close the Camera.exe process $($cam.Id): $_"
                    $result += "$msg`n"
                    Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
                }
            }
        }
        if ($foundProcess) {
            if (-not (Test-Path $AutopilotFolder)) {
                New-Item -ItemType Directory -Path $AutopilotFolder | Out-Null
                $msg = "Create AutoPilot_Data folder."
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
            }
            $autoPilotLnk = Join-Path $PSScriptRoot "Shortcuts\AutoPilot.lnk"
            if (Test-Path $autoPilotLnk) {
                Start-Process $autoPilotLnk
                $msg = "AutoPilot Started Successfully."
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
            } else {
                $msg = "AutoPilot.lnk not found!"
                $result += "$msg`n"
                Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
            }
        } else {
            $msg = "AutoPilot and Monitoring are already STOPPED!"
            $result += "$msg`n"
            Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
        }
    } catch {
        $msg = "Error executing Restart-AutoPilotWithLog: $_"
        $result += "$msg`n"
        Add-Content -Path $Global:logPath -Value "$((Get-Date).ToString('HH:mm:ss')) - $msg"
    }
    return $result
}

# === AUTOPILOT STATUS ===
function Get-AutoPilotStatus {
    $autoPilotRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape("$PSScriptRoot\AutoPilot.ps1")
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
            "TASK-CREATE ERROR",
            "Time: $ts",
            "TaskName is empty or null",
            "=============================="
        )
        $result -join "`n" | Add-Content -Path $Global:logPath
        return $result -join "`n"
    }
    if (-not (Test-Path $VbsPath)) {
        $result = @(
            "==============================",
            "TASK-CREATE ERROR",
            "Time: $ts",
            "VBS file does not exist: $VbsPath",
            "=============================="
        )
        $result -join "`n" | Add-Content -Path $Global:logPath
        return $result -join "`n"
    }
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        $result = @(
            "==============================",
            "TASK-CREATE INFO",
            "Time: $ts",
            "TaskName: $TaskName has already been Created",
            "Auto-Start is already ENABLED",
            "=============================="
        )
        $result -join "`n" | Add-Content -Path $Global:logPath
        return $result -join "`n"
    }
    try {
        $action  = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$VbsPath`""
        $trigger = New-ScheduledTaskTrigger -AtStartup # -AtStartup -AtLogOn
        Register-ScheduledTask -TaskName $TaskName `
                               -Action $action `
                               -Trigger $trigger `
                               -Description "AutoPilot startup task (StartBot.vbs)" `
                               -RunLevel Highest `
                               -Force | Out-Null
        $result = @(
            "==============================",
            "TASK-CREATE OK",
            "Time: $ts",
            "TaskName: $TaskName",
            "VBS fajl: $VbsPath",
            "Trigger: AtStartup",
            "Auto-Start is ENABLED",
            "=============================="
        )
    }
    catch {
        $result = @(
            "==============================",
            "TASK-CREATE ERROR",
            "Time: $ts",
            "TaskName: $TaskName",
            "Error: $_",
            "=============================="
        )
    }
    $result -join "`n" | Add-Content -Path $Global:logPath
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
                "TASK-DELETE OK",
                "Time: $ts",
                "TaskName: $TaskName delete",
				"Auto-Start is DISABLED",
                "=============================="
            )
        }
        else {
            $result = @(
                "==============================",
                "TASK-DELETE INFO",
                "Time: $ts",
                "TaskName: $TaskName does not Exist",
				"Auto-Start is DISABLED",
                "=============================="
            )
        }
    }
    catch {
        $result = @(
            "==============================",
            "TASK-DELETE ERROR",
            "Time: $ts",
            "TaskName: $TaskName",
            "Error: $_",
            "=============================="
        )
    }
    $result -join "`n" | Add-Content -Path $Global:logPath
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
            "TASK-SHOW",
            "Time: $ts",
            "TaskName: $TaskName EXISTS",
			"Auto-Start is ENABLED",
            "=============================="
        )
    }
    else {
        $result = @(
            "==============================",
            "TASK-SHOW",
            "Time: $ts",
            "TaskName: $TaskName NO EXISTS",
			"Auto-Start is DISABLED",
            "=============================="
        )
    }
    $result -join "`n" | Add-Content -Path $Global:logPath
    return $result -join "`n"
}

# ⚡ Function to Shutdown
function Auto-Shutdown-System {
    param(
        [string]$Time = (Get-Date -Format "HH:mm:ss")
    )
    Write-Log "The System is Shutdown now at $Time."
    Send-TelegramMessage -Message "Automatic: The System will Shutdown in $Time"
    # Shutdown the system
    Stop-Computer -Force
}

# Function to Restart
function Auto-Restart-System {
    param(
        [string]$Time = (Get-Date -Format "HH:mm:ss")
    )
    Write-Log "The System is Restart now at $Time."
    Send-TelegramMessage -Message "Automatic: The System will Restart in $Time"
    # Restart the system
    Restart-Computer -Force
}

# Function to Pause AutoPilot
function Pause-Script {
    if (-not $global:scriptPaused) {
        $global:scriptPaused = $true
        # Create the pause flag
        New-Item -Path $Global:pauseFlagPath -ItemType File -Force | Out-Null
        # Telegram message
        Send-TelegramMessage -Message "The Script is PAUSED. To Resume, send /resume"
        # Log
        Write-Log "The Script is PAUSED"
    } else {
        Send-TelegramMessage -Message "The script is already paused."
    }
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
		Send-TelegramMessage -Message " JSON file not found: $cmdPath"
	} else {
		try {
			$cmdJson = Get-Content $cmdPath -Raw | ConvertFrom-Json
			if (-not $cmdJson.AutoCommands -or $cmdJson.AutoCommands.PSObject.Properties.Count -eq 0) {
				Send-TelegramMessage -Message " JSON Commands are empty."
			}
		} catch {
			Send-TelegramMessage -Message " Error reading the Commands JSON."
		}
	}
	# ===== scripts_edit.json =====
	if (-not (Test-Path $scrPath)) {
		Send-TelegramMessage -Message " JSON file not found: $scrPath"
	} else {
		try {
			$scrJson = Get-Content $scrPath -Raw | ConvertFrom-Json
			if (-not $scrJson.ScheduledScripts -or $scrJson.ScheduledScripts.Count -eq 0) {
				Send-TelegramMessage -Message " JSON Scripts are empty."
			}
		} catch {
			Send-TelegramMessage -Message " Error reading the Scripts JSON."
		}
	}
    $timeline = @()
    # ================= SCRIPTS =================
    foreach($scr in $scrJson.ScheduledScripts){
        for($i=0; $i -lt $scr.Times.Count; $i++){
            $mode = $scr.Mode[$i]
            $type = "daily"
            $timeStr = $scr.Times[$i]
            $dayStr = if($scr.Day[$i] -and $scr.Day[$i].Trim() -ne "") { $scr.Day[$i] } else { "No Data" }
            if($mode -eq "fixed" -and $dayStr){
                $dt = [datetime]::ParseExact("$dayStr $timeStr","yyyy-MM-dd HH:mm:ss",$null)
            } else {
                $today = Get-Date
                $timeParts = $timeStr -split ":"
                $dt = $today.Date.AddHours([int]$timeParts[0]).AddMinutes([int]$timeParts[1]).AddSeconds([int]$timeParts[2])
            }
            $status = if($mode -eq "fixed") { "FIKS" } else { "LOOP" }
            $timeline += [PSCustomObject]@{
                Time = $dt
                Text = "$status | SCRIPT ($([System.IO.Path]::GetFileName($scr.Path))) Command: $($scr.Commands[$i]) | Time: $timeStr | Delay: $($scr.DelaySeconds[$i]) sec | Repeat: $($scr.RepeatIntervalMinutes[$i]) min | Day: $dayStr"
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
            if($mode -eq "fixed" -and $dayStr){
                $dt = [datetime]::ParseExact("$dayStr $timeStr","yyyy-MM-dd HH:mm:ss",$null)
            } else {
                $today = Get-Date
                $timeParts = $timeStr -split ":"
                $dt = $today.Date.AddHours([int]$timeParts[0]).AddMinutes([int]$timeParts[1]).AddSeconds([int]$timeParts[2])
            }
            $status = if($mode -eq "fixed") { "FIKS" } else { "LOOP" }
            switch ($type.ToLower()){
                "daily"   { $typeText = "" }
                "weekly"  { $typeText = " WEEK" }
                "monthly" { $typeText = " MONTH" }
                "yearly"  { $typeText = " YEAR" }
                default   { $typeText = "" }
            }
            $timeline += [PSCustomObject]@{
                Time = $dt
                Text = "$status$typeText | AUTO COMMAND ($($cmd.Cmd)) | Time: $timeStr | Repeat: $($cmd.RepeatIntervalMinutes[$i]) min | Day: $dayStr"
            }
        }
    }
    # ================= SORT =================
    $timeline = $timeline | Sort-Object Time
    # ================= CREATE TELEGRAM MESSAGES =================
    $messages = @()
    $currentMessage = "*Timeline Commands:*`n`n"
    $counter = 1
    foreach($item in $timeline){
        $line = "$counter. $($item.Text)`n"
        $line += "`n"  
        if (($currentMessage.Length + $line.Length) -gt $TelegramMaxLength) {
            $messages += $currentMessage
            $currentMessage = ""
        }
        $currentMessage += $line
        $counter++
    }
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
    $scriptLnk = Join-Path $PSScriptRoot "Shortcuts\Autopilot.lnk"
    # Проверка дали Autopilot.ps1 е активна
    $proc = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape($scriptPS1)
    }
    if (-not $proc) {
        Show-DarkWarning -Title "Info" -Message "AP Terminal is not Active."
        return
    }
    # Проверка дали прозорецот е Hidden
    $isHidden = $proc | ForEach-Object { 
        (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue).MainWindowHandle 
    } | Where-Object { $_ -ne 0 } | Measure-Object | Select-Object -ExpandProperty Count
    if ($isHidden -gt 0) {
        Show-DarkWarning -Title "Info" -Message "AP Terminal is already in *VISIBLE* mode."
    } else {
        Show-DarkWarning -Title "AutoPilot Restart" -Message "Restarting AP Terminal in *VISIBLE* mode..."
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
        # Stop Camera.exe if running
        $cameraExePath = Join-Path $PSScriptRoot "Camera.exe"
        if (Test-Path $cameraExePath) {
            $cameraProcs = Get-Process -Name "Camera" -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $cameraExePath }
            $cameraProcs | ForEach-Object { Stop-Process -Id $_.Id -Force }
        }
        # === START Autopilot.ink VISIBLE ===
        if (Test-Path $scriptLnk) {
            Start-Process -WindowStyle Normal -FilePath $scriptLnk
        } else {
            Show-DarkWarning -Title "Error" -Message "Autopilot.lnk not found!"
        }
    }
}

# Hide Terminal
function Hide-CMDWindow {
    $scriptPS1 = Join-Path $PSScriptRoot "Autopilot.ps1"
    $scriptLnk = Join-Path $PSScriptRoot "Shortcuts\Autopilot.lnk"
    # Проверка дали Autopilot.ps1 е активna
    $proc = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match [regex]::Escape($scriptPS1)
    }
    if (-not $proc) {
        Show-DarkWarning -Title "Info" -Message "AP Terminal is not Active.."
        return
    }
    # Проверка дали прозорецот е Hidden
    $isHidden = $proc | ForEach-Object { 
        (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue).MainWindowHandle 
    } | Where-Object { $_ -ne 0 } | Measure-Object | Select-Object -ExpandProperty Count
    if ($isHidden -eq 0) {
        Show-DarkWarning -Title "Info" -Message "AP Terminal is already in *HIDDEN* mode."
    } else {
        Show-DarkWarning -Title "AutoPilot Restart" -Message "Restarting AP Terminal in *HIDDEN* mode..."
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
        # Stop Camera.exe if running
        $cameraExePath = Join-Path $PSScriptRoot "Camera.exe"
        if (Test-Path $cameraExePath) {
            $cameraProcs = Get-Process -Name "Camera" -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -eq $cameraExePath }
            $cameraProcs | ForEach-Object { Stop-Process -Id $_.Id -Force }
        }
        # === START Autopilot.ink HIDDEN ===
        if (Test-Path $scriptLnk) {
            Start-Process -WindowStyle Hidden -FilePath $scriptLnk
        } else {
            Show-DarkWarning -Title "Error" -Message "Autopilot.lnk not found!"
        }
    }
}

########################################################################################################################### System End.
