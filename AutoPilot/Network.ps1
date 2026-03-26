param (
    [string[]]$AutoRunOps = @(),
    [switch]$Silent
)

# === Proverka dali e startuvana kako Administrator ===
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "The script must be run as Administrator!"
    if (-not $Silent) { Pause }
    Exit
}

# ==== Load settings from JSON ====
$jsonPath = "$PSScriptRoot\JSON\settings_scripts.json"

$wifi1 = $null
$wifi2 = $null
$TendaToBeniTime = $null
$BeniToTendaTime = $null

if (Test-Path $jsonPath) {
    try {
        $settings = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
        # Wi-Fi SSID
        $wifi1 = if ($settings.wifi1) { $settings.wifi1 } else { $null }
        $wifi2 = if ($settings.wifi2) { $settings.wifi2 } else { $null }
        # Times: проверка дали се валидни HH:MM формати
        if ($settings.TendaToBeniTime -and $settings.TendaToBeniTime -match '^\d{2}:\d{2}$') {
            $TendaToBeniTime = $settings.TendaToBeniTime
        }
        if ($settings.BeniToTendaTime -and $settings.BeniToTendaTime -match '^\d{2}:\d{2}$') {
            $BeniToTendaTime = $settings.BeniToTendaTime
        }
    }
    catch {
        Write-Warning "Failed to read the JSON file $jsonPath. Default values will be set to null."
    }
}
else {
    Write-Warning "JSON file does not exist: $jsonPath. Default values will be set to null."
}

# --- Definiranje dali mozat da se kreiraat taskovi ---
$canCreateTendaToBeni = ($wifi1 -and $wifi2 -and $TendaToBeniTime)
$canCreateBeniToTenda = ($wifi1 -and $wifi2 -and $BeniToTendaTime)
$canCreateTasks = $canCreateTendaToBeni -or $canCreateBeniToTenda

# === Task Prefiks ===
$ourTaskPrefix = "WiFiSwitch_"

# Network log folder and file
$Global:networkLogFolder = "$PSScriptRoot\Autopilot_Data\Network_Logs"
if (-not (Test-Path $Global:networkLogFolder)) {
    New-Item -Path $Global:networkLogFolder -ItemType Directory | Out-Null
}
$currentDate = Get-Date -Format 'yyyy-MM-dd'
$Global:networkLogFile = "$Global:networkLogFolder\network_$currentDate.txt"
if (-not (Test-Path $Global:networkLogFile)) {
    New-Item -Path $Global:networkLogFile -ItemType File | Out-Null
}

# --- NETWORK LOG FUNCTION ---
function Write-Log {
    param (
        [string]$Message,
        [ConsoleColor]$Color = 'White',
        [switch]$NoDisplay
    )

    # Timestamped log line
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] $Message"
    Add-Content -Path $Global:networkLogFile -Value $logLine

    if (-not $NoDisplay) {
        Write-Host $logLine -ForegroundColor $Color
    }

    # Remove network logs older than 30 days
    Get-ChildItem -Path $Global:networkLogFolder -Filter "network_*.txt" |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force
}

# === Momentalna WiFi SSID Function ===
function Get-CurrentWifi {
    $wifiLine = netsh wlan show interfaces | Select-String 'SSID' | Where-Object { $_ -notmatch 'BSSID' }
    if ($wifiLine) {
        return $wifiLine.ToString().Split(':')[1].Trim()
    }
    else {
        return $null
    }
}

# === Switch Network Function ===
function Connect-ToNetwork {
    param (
        [string]$targetSSID,
        [int]$maxAttempts = 3
    )
	
	if (-not $targetSSID) {
        Write-Warning "No targetSSID defined. Skipping connection."
        return $false
    }

    # Добиј тековна мрежа
    $currentWifi = Get-CurrentWifi
    if (-not $currentWifi) {
        Write-Log "No WiFi network currently connected."  -NoDisplay
        Write-Host "No WiFi network currently connected." -ForegroundColor Yellow
        $currentWifi = "<no previous network>"
    }
    else {
        Write-Log "Currently connected to: $currentWifi"  -NoDisplay
        Write-Host "Currently connected to: $currentWifi." -ForegroundColor Cyan
    }

    $attempt = 0
    $success = $false

    do {
        $attempt++
        Write-Log "Disconnecting from the current network..."  -NoDisplay
        Write-Host "Disconnecting from the current network..." -ForegroundColor Yellow
        netsh wlan disconnect | Out-Null
        Start-Sleep -Seconds 3

        Write-Log "Attempting to connect to $targetSSID (attempt $attempt from $maxAttempts)..."  -NoDisplay
        Write-Host "Attempting to connect to $targetSSID (attempt $attempt from $maxAttempts)..." -ForegroundColor White

        # Proverka dali profilot postoi
        $profileExists = netsh wlan show profiles | Select-String $targetSSID
        if (-not $profileExists) {
            Write-Log "Cannot connect to $targetSSID. Problem: SSID does not exist or a password is required!"  -NoDisplay
            Write-Host "Cannot connect to $targetSSID. Problem: SSID does not exist or a password is required!" -ForegroundColor Red
        }
        else {
            # Obid za povrzuvanje i hvatanje na detalen rezultat
            $result = netsh wlan connect name="$targetSSID" 2>&1

            # Malo cekanje da se povrze
            Start-Sleep -Seconds 5

            # Proverka na stvarnata povrzanost
            $currentAfterAttempt = Get-CurrentWifi
            if ($currentAfterAttempt -eq $targetSSID) {
                Write-Log "Successfully connected to $targetSSID!"  -NoDisplay
				Write-Host "Successfully connected to $targetSSID!" -ForegroundColor Green
                $success = $true
            }
            else {
                # Analiza na rezultatot za tocna pricina
                if ($result -match "The network requires a password|authentication|security key") {
                    Write-Log "Cannot connect to $targetSSID. Problem: Password is required or incorrect!"  -NoDisplay
                    Write-Host "Cannot connect to $targetSSID. Problem: Password is required or incorrect!" -ForegroundColor Red
                }
                elseif ($result -match "cannot find|not available|not exist|No profile") {
                    Write-Log "Cannot connect to $targetSSID. Problem: The network does not exist or is unavailable!"  -NoDisplay
                    Write-Host "Cannot connect to $targetSSID. Problem: The network does not exist or is unavailable!" -ForegroundColor Red
                }
                else {
                    Write-Log "Cannot connect to $targetSSID. Details from netsh: $result"  -NoDisplay
					Write-Host "Cannot connect to $targetSSID. Details from netsh: $result" -ForegroundColor Red
                }
            }
        }

        if (-not $success -and $attempt -lt $maxAttempts) {
            Write-Log "Retrying attempt..."  -NoDisplay
            Write-Host "Retrying attempt..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }

    } while (-not $success -and $attempt -lt $maxAttempts)

    # Ako ne uspese, obid da se vrati prethodnata mreza
    if (-not $success) {
        if ($currentWifi -and $currentWifi -ne "<no previous network>") {
            Write-Log "Failed to connect to $targetSSID after $maxAttempts attempts. Returning to the previous network: $currentWifi ..."  -NoDisplay
            Write-Host "Failed to connect to $targetSSID after $maxAttempts attempts. Returning to the previous network: $currentWifi ..." -ForegroundColor Red
            netsh wlan connect name="$currentWifi" | Out-Null
            Start-Sleep -Seconds 5
            Write-Log "Returned to the previous network: $currentWifi" -NoDisplay
            Write-Host "Returned to the previous network: $currentWifi" -ForegroundColor  Green
        }
        else {
            Write-Log "Cannot return to the previous network because there is no information about it."  -NoDisplay
            Write-Host "Cannot return to the previous network because there is no information about it." -ForegroundColor Red
        }
    }

    # Finalno reportiranje
    $newWifi = Get-CurrentWifi
    if (-not $newWifi) { $newWifi = "<no network connected>" }
    Write-Log "Previous network: $currentWifi; Currently connected to: $newWifi"  -NoDisplay
    Write-Host "Previous network: $currentWifi; Currently connected to: $newWifi" -ForegroundColor Cyan

    return $success
}

# --- Switch to BENI bez potvrda ---
function Switch-ToBeni {
    if (-not $wifi2) {
        Write-Warning "SSID for WiFi 2 is not defined. Skipping switch."
        return
    }
    $success = Connect-ToNetwork -targetSSID $wifi2 -maxAttempts 5
    if (-not $success) {
        Write-Log "Failed to connect to '$wifi2' after maximum attempts." -NoDisplay
        Write-Host "Failed to connect to '$wifi2' after maximum attempts." -ForegroundColor Yellow
    }
}

# --- Switch to TENDA bez potvrda ---
function Switch-ToTenda {
    if (-not $wifi1) {
        Write-Warning "SSID for WiFi 1 is not defined. Skipping switch."
        return
    }
    $success = Connect-ToNetwork -targetSSID $wifi1 -maxAttempts 5
    if (-not $success) {
        Write-Log "Failed to connect to '$wifi1' after maximum attempts." -NoDisplay
        Write-Host "Failed to connect to '$wifi1' after maximum attempts." -ForegroundColor Yellow
    }
}

# --- KREIRAJ TAJMER: TENDA → BENI ---
function Create-Timer-TendaToBeni {
    if (-not ($wifi1 -and $wifi2 -and $TendaToBeniTime -and $TendaToBeniTime -match '^\d{2}:\d{2}$')) {
        Write-Warning "Skipping creation of WiFi 1 to WiFi 2 switch task. SSID or timing missing."
        return
    }
	
	$taskName = "WiFiSwitch_${wifi1}To${wifi2}"
    # --- Proverka dali task veke postoi ---
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Warning "Task '$taskName' already exists. Cannot be created again."
        Write-Host "Task '$taskName' already exists. Cannot be created again." -ForegroundColor Yellow
        return
    }

    Write-Log "Creating Task Scheduler task: $wifi1 switch to $wifi2 at $TendaToBeniTime..." -NoDisplay
    Write-Host "Creating Task Scheduler task: $wifi1 switch to $wifi2 at $TendaToBeniTime..." -ForegroundColor Cyan

    $taskName = "WiFiSwitch_${wifi1}To${wifi2}"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -Command `"netsh wlan disconnect; Start-Sleep 5; netsh wlan connect name='$wifi2'; Add-Content -Path '$Global:networkLogFile' -Value ('[' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '] Automatically switched to $wifi2 (Task Scheduler)')`""
    # Sigurno parse-iranje na vreme
    $trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact($TendaToBeniTime,'HH:mm',$null))

    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Connecting Wi-Fi from $wifi1 to $wifi2" -Force

    Write-Log "The task has been successfully created ($TendaToBeniTime switch to $wifi2)." -NoDisplay
    Write-Host "The task has been successfully created ($TendaToBeniTime switch to $wifi2)." -ForegroundColor Green
}

# --- KREIRAJ TAJMER: BENI → TENDA ---
function Create-Timer-BeniToTenda {
    if (-not ($wifi1 -and $wifi2 -and $BeniToTendaTime -and $BeniToTendaTime -match '^\d{2}:\d{2}$')) {
        Write-Warning "Skipping creation of WiFi 2 to WiFi 1 switch task. SSID or timing missing."
        return
    }
	
	$taskName = "WiFiSwitch_${wifi2}To${wifi1}"
    # --- Proverka dali task veke postoi ---
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Warning "Task '$taskName' already exists. Cannot be created again."
        Write-Host "Task '$taskName' already exists. Cannot be created again." -ForegroundColor Yellow
        return
    }

    Write-Log "Creating Task Scheduler task: $wifi2 switch to $wifi1 at $BeniToTendaTime..." -NoDisplay
    Write-Host "Creating Task Scheduler task: $wifi2 switch to $wifi1 at $BeniToTendaTime..." -ForegroundColor Cyan

    $taskName = "WiFiSwitch_${wifi2}To${wifi1}"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -Command `"netsh wlan disconnect; Start-Sleep 5; netsh wlan connect name='$wifi1'; Add-Content -Path '$Global:networkLogFile' -Value ('[' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '] Automatically switched to $wifi1 (Task Scheduler)')`""
    # Sigurno parse-iranje na vreme
    $trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact($BeniToTendaTime,'HH:mm',$null))

    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Connecting Wi-Fi from $wifi2 to $wifi1" -Force

    Write-Log "The task has been successfully created ($BeniToTendaTime switch to $wifi1)." -NoDisplay
    Write-Host "The task has been successfully created ($BeniToTendaTime switch to $wifi1)." -ForegroundColor Green
}

# === Funkcija da gi prikaze site taskovi (so prefiks) ===
function Show-OurScheduledTasks {
    try {
        $all = Get-ScheduledTask | Where-Object { $_.TaskName -like "$ourTaskPrefix*" } 2>$null

        if (-not $all) {
            $msg = "No TASK found with the prefix '$ourTaskPrefix'."
            Write-Log $msg -Color Yellow
            Write-Host "No scheduled tasks found with the prefix '$ourTaskPrefix'." -ForegroundColor Yellow
            return
        }

        Write-Host "`n=== Created TASKs ===`n" -ForegroundColor Cyan
        $i = 1
        foreach ($t in $all) {
            $nextRun = ($t | Get-ScheduledTaskInfo).NextRunTime
            $state = ($t | Get-ScheduledTaskInfo).State
            Write-Host (" [{0}] {1}  (Next run: {2})  [Status: {3}]" -f $i, $t.TaskName, $nextRun, $state) -ForegroundColor Gray
            $i++
        }
    } catch {
        $err = "Error retrieving TASK: $_"
        Write-Log $err -Color Red
        Write-Host $err -ForegroundColor Red
    }
}

# === Remove scheduled tasks ===
function Remove-ScheduledTasks {
    Write-Log "Starting deletion of Scheduled Tasks with prefix '$ourTaskPrefix'..." -NoDisplay
	Write-Host "Starting deletion of Scheduled Tasks with prefix '$ourTaskPrefix'..." -ForegroundColor Cyan

    $all = Get-ScheduledTask | Where-Object { $_.TaskName -like "$ourTaskPrefix*" } 2>$null

    if (-not $all) {
        Write-Host "No tasks to delete with the prefix '$ourTaskPrefix'." -ForegroundColor Yellow
        Write-Log "No TASK found for deletion."  -NoDisplay
		Write-Host "No TASK found for deletion." -ForegroundColor Yellow
        return
    }

    Write-Host "`n=== TASK for deletion ===`n" -ForegroundColor Cyan
    $i = 1
    foreach ($t in $all) {
        Write-Host (" [{0}] {1}" -f $i, $t.TaskName) -ForegroundColor Gray
        $i++
    }

    # Direktno brisenje bez potvrda
    foreach ($t in $all) {
        try {
            Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false
            Write-Log "TASK '$($t.TaskName)' has been successfully deleted."  -NoDisplay
			Write-Host "TASK '$($t.TaskName)' has been successfully deleted." -ForegroundColor Green
        } catch {
            Write-Log "Cannot delete the TASK '$($t.TaskName)': $_"  -NoDisplay
			Write-Host "Cannot delete the TASK '$($t.TaskName)': $_" -ForegroundColor Red
        }
    }

    # Proverka dali site task-ovi se izbrisani
    $remaining = Get-ScheduledTask | Where-Object { $_.TaskName -like "$ourTaskPrefix*" } 2>$null
    if (-not $remaining) {
        Write-Log "All tasks with the prefix '$ourTaskPrefix' have been deleted."  -NoDisplay
		Write-Host "All tasks with the prefix '$ourTaskPrefix' have been deleted." -ForegroundColor Green
    } else {
        Write-Log "Some tasks with the prefix '$ourTaskPrefix' were not deleted:"  -NoDisplay
		Write-Host "Some tasks with the prefix '$ourTaskPrefix' were not deleted:" -ForegroundColor Red
        foreach ($t in $remaining) {
            Write-Log " - $($t.TaskName)" Red
        }
    }

    Write-Log "Scheduled Tasks deletion completed."  -NoDisplay
    Write-Host "Scheduled Tasks deletion completed." -ForegroundColor Cyan
}

# --- PRIKAZI POSLEDNI 30 NET LOG ZAPISI ---
function Network-Log {
    if (Test-Path $Global:networkLogFile) {
        $logContent = Get-Content $Global:networkLogFile -Tail 30
        Write-Host "`n=== Last 30 Network Log entries ===`n" -ForegroundColor Cyan
        $logContent | ForEach-Object { Write-Host $_ -ForegroundColor Gray }

        if ($BotToken -and $ChatID) {
            $msg = "=== Last 30 Network Log entries ===`n" + ($logContent -join "`n")
            Start-Sleep -Seconds 5
            Send-TelegramMessage -message $msg
        }
    } else {
        $msg = "No network log file found in: $Global:networkLogFile"
        Write-Host $msg -ForegroundColor Yellow
        Write-Log -Message $msg -Color Yellow -NoDisplay

        if ($BotToken -and $ChatID) {
            Start-Sleep -Seconds 5
            Send-TelegramMessage -message $msg
        }
    }
}

# === NETWORK STATUS WITH ASCII SPEED BARS ===
function Network-Status {

    $hostname = $env:COMPUTERNAME

    try {
        # --- INTERNET CHECK ---
        $ping = try { Test-Connection -ComputerName 8.8.8.8 -Count 1 -ErrorAction Stop } catch { $null }
        $internetStatus = if ($ping) { "OK" } else { "NOT WORKING" }
        $pingTime = if ($ping) { $ping.ResponseTime } else { "N/A" }
        $pingIP   = if ($ping) { $ping.Address.IPAddressToString } else { "N/A" }

        # --- LOCAL IP ---
        $local = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.InterfaceAlias -notlike "Loopback*" -and $_.IPAddress -notlike "169.*" } |
                 Select-Object IPAddress, PrefixLength -First 1

        $localIP = if ($local) { $local.IPAddress } else { "N/A" }
        $subnet  = if ($local) { $local.PrefixLength } else { "N/A" }

        # --- GATEWAY ---
        $gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
                    Sort-Object RouteMetric |
                    Select-Object -ExpandProperty NextHop -First 1)
        if (-not $gateway) { $gateway = "N/A" }

        # --- DNS ---
        $dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        $dnsServers = if ($dnsServers) { $dnsServers -join ", " } else { "N/A" }

        # --- ACTIVE ADAPTER ---
        $adapter = Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object -First 1
        $adapterName = if ($adapter) { $adapter.Name } else { "N/A" }
        $adapterType = if ($adapter) { $adapter.MediaType } else { "N/A" }

        # --- WIFI SSID ---
        $wifiSSID = try { (Get-NetConnectionProfile -ErrorAction SilentlyContinue).Name } catch { "N/A" }
        if (-not $wifiSSID) { $wifiSSID = "N/A" }

        # --- ALL NETWORK ADAPTERS INFO ---
		$allAdapters = Get-NetAdapter | ForEach-Object {
			$ipAddresses = (Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
							Select-Object -ExpandProperty IPAddress) -join ", "
			$gw = (Get-NetRoute -InterfaceIndex $_.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
				   Select-Object -First 1 -ExpandProperty NextHop)
			if (-not $gw) { $gw = "N/A" }

			# Проверка дали адаптерот е виртуелен
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

        $downloadMbps = [math]::Round(($rx * 8) / 1MB, 1)
        $uploadMbps   = [math]::Round(($tx * 8) / 1MB, 1)

        # --- ASCII BARS ---
        $barWidth = 40
        $downBar = ("#" * [math]::Min([math]::Floor($downloadMbps), $barWidth)).PadRight($barWidth, "-")
        $upBar   = ("#" * [math]::Min([math]::Floor($uploadMbps), $barWidth)).PadRight($barWidth, "-")

        # --- COLOR ---
        $statusColor = if ($internetStatus -eq "OK") { "Green" } else { "Red" }

        # --- LOG BLOCK ---
        $logText = @"
NETWORK STATUS - $hostname
Ping: $pingTime ms  IP: $pingIP
Local IP: $localIP / $subnet
Gateway: $gateway
DNS Servers: $dnsServers
Internet Status: $internetStatus
Wi-Fi SSID: $wifiSSID
Active Adapter: $adapterName ($adapterType)
Download Speed : |$downBar| $downloadMbps Mbps
Upload Speed   : |$upBar| $uploadMbps Mbps
"@

        # --- ADD ALL ADAPTERS INFO ---
        $allAdapters | ForEach-Object {
            $logText += "`nAdapter: $($_.Name)
  Status   : $($_.Status)
  Type     : $($_.Type)
  MAC      : $($_.MAC)
  IPs      : $($_.IPs)
  Gateway  : $($_.Gateway)
  Speed    : $($_.SpeedMbps) Mbps"
        }

        # --- CONSOLE OUTPUT ---
        Write-Host ""
        Write-Host "NETWORK STATUS - $hostname" -ForegroundColor Cyan
        Write-Host "Ping: $pingTime ms  IP: $pingIP"
        Write-Host "Local IP: $localIP / $subnet"
        Write-Host "Gateway: $gateway"
        Write-Host "DNS Servers: $dnsServers"
        Write-Host ("Internet Status: $internetStatus") -ForegroundColor $statusColor
        Write-Host "Wi-Fi SSID: $wifiSSID"
        Write-Host "Active Adapter: $adapterName ($adapterType)"
		Write-Host "------------------" -ForegroundColor Yellow
        Write-Host ("*Download Speed : |$downBar| $downloadMbps Mbps") -ForegroundColor Cyan
        Write-Host ("*Upload Speed   : |$upBar| $uploadMbps Mbps") -ForegroundColor Magenta

        $allAdapters | ForEach-Object {
		# Одредување на боја според тип на адаптер
		$color = switch -Regex ($_.Name + " " + $_.Type) {
		"Wi-Fi|Wireless"                               { "Green" }  # Wi-Fi
		"vEthernet|WSL|Hyper-V|Virtual|VMware|VPN"     { "Cyan" }   # Virtual  
		"Ethernet"                                     { "Blue" }   # Ethernet
		 default                                       { "White" }
	}

    Write-Host "`nAdapter: $($_.Name)" -ForegroundColor $color
    Write-Host "  Status   : $($_.Status)" -ForegroundColor $color
    Write-Host "  Type     : $($_.Type)" -ForegroundColor $color
    Write-Host "  MAC      : $($_.MAC)" -ForegroundColor $color
    Write-Host "  IPs      : $($_.IPs)" -ForegroundColor $color
    Write-Host "  Gateway  : $($_.Gateway)" -ForegroundColor $color
    Write-Host "  Speed    : $($_.SpeedMbps) Mbps" -ForegroundColor $color
    }
	Write-Host ""

	# --- LOG WRITE ---
	Write-Log -Message $logText -Color Yellow -NoDisplay
    }
    catch {
        Write-Host "[$hostname] Internet: NOT WORKING!" -ForegroundColor Red
    }
}

# === NETWORK RESTART ===
function Restart-NetworkAdapters {
    try {
        Write-Log "=== Start Restart Network Adapters ===" -NoDisplay
		Write-Host "=== Start Restart Network Adapters ===" -ForegroundColor Green

        # Naogja site mrežni adapteri so status Up
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

        if ($adapters.Count -eq 0) {
            $msg = "No active network adapters available for restart."
            Write-Log $msg -NoDisplay
            Write-Host $msg -ForegroundColor Yellow

            # Čekaj 10 sekundi da se stabilizira mrežata (ako ima internet)
            Start-Sleep -Seconds 10
            if ($BotToken -and $ChatID) { Send-TelegramMessage -message $msg }
            return
        }

        foreach ($adapter in $adapters) {
            $msgStart = "Restarting adapter: $($adapter.Name)"
            Write-Log $msgStart -NoDisplay
            Write-Host $msgStart -ForegroundColor Cyan

            try {
                Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 2
                Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop

                # Čekaj 10 sekundi da se stabilizira mrežata
                Start-Sleep -Seconds 10

                $msgEnd = "Adapter $($adapter.Name) restarted successfully "
                Write-Log $msgEnd -NoDisplay
                Write-Host $msgEnd -ForegroundColor Green

                if ($BotToken -and $ChatID) { Send-TelegramMessage -message $msgEnd }

            } catch {
                $errMsg = "Cannot restart the adapter $($adapter.Name) : $_"
                Write-Log $errMsg -NoDisplay
                Write-Host $errMsg -ForegroundColor Red

                # Čekaj 10 sekundi pred isprakjanje poraka
                Start-Sleep -Seconds 10
                if ($BotToken -and $ChatID) { Send-TelegramMessage -message $errMsg }
            }
        }

        $finalMsg = "=== Network Adapters Restart Finished ==="
        Write-Log $finalMsg -NoDisplay
		Write-Host "=== Network Adapters Restart Finished ===" -ForegroundColor Cyan
        Start-Sleep -Seconds 10
        if ($BotToken -and $ChatID) { Send-TelegramMessage -message $finalMsg }

    } catch {
        $err = "Error restarting the network: $_"
        Write-Log $err -NoDisplay
        Write-Host $err -ForegroundColor Red
        Start-Sleep -Seconds 10
        if ($BotToken -and $ChatID) { Send-TelegramMessage -message $err }
    }
}

# === MAPA NA OPCII ===
$FunctionMap = @{
    "1" = { Switch-ToBeni }
    "2" = { Switch-ToTenda }
    "3" = { Create-Timer-TendaToBeni }
    "4" = { Create-Timer-BeniToTenda }
    "5" = { Show-OurScheduledTasks }
    "6" = { Remove-ScheduledTasks }
	"7" = { Network-Log }
	"8" = { Network-Status }
	"9" = { Restart-NetworkAdapters }
}

# === AUTOMATSKO IZVRSUVANJE AKO IMA PARAMETRI ===
if ($AutoRunOps.Count -gt 0) {
    foreach ($op in $AutoRunOps) {
        if ($FunctionMap.ContainsKey($op)) {
            & $FunctionMap[$op]
            if (-not $Silent) { Start-Sleep -Seconds 1 }
        } else {
            Write-Log "Unknown operation: $op" Red
        }
    }
    return
}

# === MENI ===
function Show-Menu {
    do {
        Clear
        Write-Host ""
        Write-Host "============ Network Manager ============" -ForegroundColor Cyan
        Write-Host ""

        # Dinamicki SSID i vreme od JSON
        $wifi1Name = if ($wifi1) { $wifi1 } else { "(Empty SSID)" }
        $wifi2Name = if ($wifi2) { $wifi2 } else { "(Empty SSID)" }
        $TendaToBeniDisplay = if ($TendaToBeniTime) { $TendaToBeniTime } else { "(Time not Set)" }
        $BeniToTendaDisplay = if ($BeniToTendaTime) { $BeniToTendaTime } else { "(Time not Set)" }

        Write-Host " [1] Connect to $wifi2Name" -ForegroundColor Green
        Write-Host " [2] Connect to $wifi1Name" -ForegroundColor Yellow
        Write-Host " [3] Create TASK ($wifi1Name switch to $wifi2Name at $TendaToBeniDisplay)" -ForegroundColor Magenta
        Write-Host " [4] Create TASK ($wifi2Name switch to $wifi1Name at $BeniToTendaDisplay)" -ForegroundColor Blue
        Write-Host " [5] Show TASK" -ForegroundColor Yellow
        Write-Host " [6] Delete TASK" -ForegroundColor Red
        Write-Host " [7] Net Log_File" -ForegroundColor DarkCyan
        Write-Host " [8] Network Status" -ForegroundColor DarkGreen
        Write-Host " [9] Network Restart" -ForegroundColor DarkMagenta
        Write-Host ""
        Write-Host "============ Exit ============" -ForegroundColor Cyan
        Write-Host ""
        Write-Host " [10] Exit" -ForegroundColor Red
        Write-Host ""

        $selection = Read-Host "Enter a number (1-10) to select"

        if ($selection -eq "10") {
            Write-Log "Exiting..." White
            break
        }

        if ($FunctionMap.ContainsKey($selection)) {
            & $FunctionMap[$selection]
        } else {
            Write-Log "Invalid option, please try again." Red
        }

        Read-Host "Press Enter to continue..."
    } while ($true)
}

# === START NA MENI ===
Show-Menu

################################################################### Network Script End.