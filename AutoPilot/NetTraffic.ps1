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

# === Flag file paths ===
$global:StartFlagFile = "$PSScriptRoot\Autopilot_Data\Traffic_Logs\TrafficMonitor_Start.flag"
$global:StopFlagFile = "$PSScriptRoot\Autopilot_Data\Traffic_Logs\TrafficMonitor_Stop.flag"
$global:StatusFlagFile = "$PSScriptRoot\Autopilot_Data\Traffic_Logs\TrafficMonitor_Status.flag"

# === TrafficMonitorWorker Global ===
$WorkerPath = "$PSScriptRoot\TrafficMonitorWorker.ps1"
$CsvPath = "$PSScriptRoot\Data\traffic.csv"

# === Global Status ===
$global:Status = "Stopped"

# Monitor log folder and file
$Global:monitorLogFolder = "$PSScriptRoot\Autopilot_Data\Traffic_Logs"
if (-not (Test-Path $Global:monitorLogFolder)) {
    New-Item -Path $Global:monitorLogFolder -ItemType Directory | Out-Null
}
$currentDate = Get-Date -Format 'yyyy-MM-dd'
$Global:monitorLogFile = "$Global:monitorLogFolder\traffic_$currentDate.txt"
if (-not (Test-Path $Global:monitorLogFile)) {
    New-Item -Path $Global:monitorLogFile -ItemType File | Out-Null
}

# --- MONITORING LOG FUNCTION ---
function Write-MonitorLog {
    param (
        [string]$Message,
        [ConsoleColor]$Color = 'White',
        [switch]$NoDisplay
    )

    # Timestamped log line
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] $Message"
    Add-Content -Path $Global:monitorLogFile -Value $logLine

    if (-not $NoDisplay) {
        Write-Host $logLine -ForegroundColor $Color
    }

    # Remove monitor logs older than 30 days
    Get-ChildItem -Path $Global:monitorLogFolder -Filter "traffic_*.txt" |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force
}

# === START MONITORING ===
function Start-Monitoring {
    param([switch]$Silent)

    $existing = Get-WmiObject Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match "TrafficMonitorWorker\.ps1"
    }

    if ($existing) {
        $msg = "Monitoring is already STARTED. -- RUNNING --"
        if ($Silent) { Write-Output $msg } else { Write-Host $msg -ForegroundColor Blue }
        Write-MonitorLog $msg -NoDisplay
        return
    }

    if (Test-Path $global:StopFlagFile) { Remove-Item $global:StopFlagFile -Force }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$global:WorkerPath`""
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute = $true

    [System.Diagnostics.Process]::Start($psi) | Out-Null
    $global:Status = "RUNNING"

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # --- Запиши го старт времето ---
    Set-Content -Path $global:StartFlagFile -Value $timestamp
    Set-Content -Path $global:StatusFlagFile -Value "RUNNING"

    $msg = "Monitoring is STARTED in: $timestamp -- RUNNING --"
    Write-MonitorLog $msg -NoDisplay
    if ($Silent) { Write-Output $msg } else { Write-Host $msg -ForegroundColor Green }
}

# === STOP MONITORING ===
function Stop-Monitoring {
    param([switch]$Silent)

    $existing = Get-WmiObject Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match "TrafficMonitorWorker\.ps1"
    }

    if ($existing) {
        if (-not (Test-Path $global:StopFlagFile)) {
            New-Item -Path $global:StopFlagFile -ItemType File -Force | Out-Null
        }

        Start-Sleep -Seconds 2

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # --- Запиши го стоп времето ---
        Set-Content -Path $global:StopFlagFile -Value $timestamp
        Set-Content -Path $global:StatusFlagFile -Value "STOPPED"

        $msg = "Monitoring is STOPPED in: $timestamp -- STOPPED --"
        Write-MonitorLog $msg -NoDisplay
        if ($Silent) { Write-Output $msg } else { Write-Host $msg -ForegroundColor Red }
    }
    else {
        $msg = "Monitoring is not started. -- NO ACTIVE PROCESS --"
        Write-MonitorLog $msg -NoDisplay
        if ($Silent) { Write-Output $msg } else { Write-Host $msg -ForegroundColor Blue }
    }
}

# === STATUS MONITORING ===
function Show-MonitoringStatus {
    param([switch]$Silent)

    $logFile = if ($global:CsvPath) { $global:CsvPath } else { "$PSScriptRoot\Data\traffic.csv" }

    # Читаме точни времиња од фајловите
    $startTime = if (Test-Path $global:StartFlagFile) { Get-Content $global:StartFlagFile } else { "N/A" }
    $stopTime  = if (Test-Path $global:StopFlagFile)  { Get-Content $global:StopFlagFile } else { "N/A" }

    $workerProc = Get-WmiObject Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match "TrafficMonitorWorker\.ps1"
    }

    $status = if ($workerProc) { "RUNNING" } else { "STOPPED" }
    $processId = if ($workerProc) { $workerProc.ProcessId -join ", " } else { "N/A" }
    $fileSize = if (Test-Path $logFile) { "{0:N2} KB" -f ((Get-Item $logFile).Length / 1KB) } else { "No file" }
    $lastUpdate = if (Test-Path $logFile) { (Get-Item $logFile).LastWriteTime } else { "N/A" }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $color = switch ($status) {
        "RUNNING" { "Green" }
        "STOPPED" { "Red" }
        default   { "White" }
    }

    if (-not $Silent) {
        Write-Host "================ MONITORING STATUS ================" -ForegroundColor Cyan
        Write-Host "Status:        $status" -ForegroundColor $color
        Write-Host "Process ID:    $processId"
        Write-Host "Started at:    $startTime"
        Write-Host "Stopped at:    $stopTime"
        Write-Host "Log File:      $logFile"
        Write-Host "File Size:     $fileSize"
        Write-Host "Last Update:   $lastUpdate"
        Write-Host "====================================================`n" -ForegroundColor Cyan
    }
    # Логирање
    Write-MonitorLog "[$timestamp] ================ MONITORING STATUS ================" -NoDisplay
	Write-MonitorLog "Status:        $status" -NoDisplay
	Write-MonitorLog "Process ID:    $processId" -NoDisplay
	Write-MonitorLog "Started at:    $startTime" -NoDisplay
	Write-MonitorLog "Stopped at:    $stopTime" -NoDisplay
	Write-MonitorLog "Log File:      $logFile" -NoDisplay
	Write-MonitorLog "File Size:     $fileSize" -NoDisplay
	Write-MonitorLog "Last Update:   $lastUpdate" -NoDisplay
	Write-MonitorLog "====================================================" -NoDisplay
}

# === FORMAT SIZE ===
function Format-Size ($bytes) {
    if ($bytes -ge 1GB) {
        return "{0:N2} GB" -f ($bytes / 1GB)
    } else {
        return "{0:N2} MB" -f ($bytes / 1MB)
    }
}

# === TRAFFIC STATISTIC  ===
function Show-TrafficStatus {
    $path = $global:CsvPath
    if (-not $path -or -not (Test-Path $path)) {
        $msg = "No data - CSV file does not exist or the path is not defined. (CsvPath=$path)"
        Write-Host $msg -ForegroundColor Yellow
        Write-MonitorLog $msg -NoDisplay
        return
    }

    try {
        $data = Import-Csv -Path $path
    } catch {
        Write-Host "Error reading the CSV file: $_" -ForegroundColor Red
        return
    }

    if (-not $data -or $data.Count -eq 0) {
        Write-Host "The CSV file is empty." -ForegroundColor Yellow
        return
    }

    # Претвори ги колоните во соодветни типови
    $data = $data | ForEach-Object {
        $bytes = $_.'Download_Bytes/Upload_Bytes/Total_Bytes' -split '/'
        [PSCustomObject]@{
            Timestamp      = [datetime]$_.Date
            Download_Bytes = [int64]$bytes[0]
            Upload_Bytes   = [int64]$bytes[1]
            Total_Bytes    = [int64]$bytes[2]
            Interface      = $_.Interface
        }
    }

    $now = Get-Date
    $ranges = @(
        @{ Name = "Current Day"; From = $now.Date },
        @{ Name = "Current Week"; From = $now.AddDays(-( [int]$now.DayOfWeek )) }, # Nedela od ponedelnik
        @{ Name = "Current Month"; From = Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0 },
        @{ Name = "Current Year"; From = Get-Date -Month 1 -Day 1 -Hour 0 -Minute 0 -Second 0 }
    )

    Write-Host "================ Traffic Statistics ================" -ForegroundColor Cyan
    Write-MonitorLog "================ Traffic Statistics ================" -NoDisplay

    Write-Host "`n--- Individual interfaces ---`n" -ForegroundColor Cyan
    Write-MonitorLog "--- Individual interfaces ---" -NoDisplay

	# --- PERSISTENT COLOR MAPPING ---
	$colorFile = "$PSScriptRoot\Autopilot_Data\Traffic_Logs\interfaceColors.json"

	# Ako fajlot postoi, vnesi go vo hashtable, inače kreiraj nov
	if (Test-Path $colorFile) {
		$json = Get-Content $colorFile | ConvertFrom-Json
		$interfaceColors = @{}
		foreach ($k in $json.PSObject.Properties.Name) {
			$interfaceColors[$k] = $json.$k
		}
	} else {
		$interfaceColors = @{}
	}

	# Funkcija za random boja
	function Get-RandomColor {
		$colors = @('Red','Green','Yellow','Blue','Magenta','Cyan','White')
		return $colors | Get-Random
	}

	# Lista na validni ConsoleColor vrednosti
	$validColors = [Enum]::GetNames([System.ConsoleColor])

	foreach ($r in $ranges) {
		$subset = $data | Where-Object { $_.Timestamp -ge $r.From }

		if (-not $subset -or $subset.Count -eq 0) { continue }

		$interfaces = $subset | Select-Object -ExpandProperty Interface | Sort-Object -Unique

		foreach ($ifaceName in $interfaces) {
			# Ako interfejsot nema boja, dodeli nova i cuvaj
			if (-not $interfaceColors.ContainsKey($ifaceName)) {
				$interfaceColors[$ifaceName] = Get-RandomColor
				$interfaceColors | ConvertTo-Json | Set-Content $colorFile
			}

			# Proveri dali boja e validna, inače default Blue
			$ifaceColor = if ($validColors -contains $interfaceColors[$ifaceName]) { 
				$interfaceColors[$ifaceName] 
			} else { 
				'Blue' 
			}

			$ifaceData = $subset | Where-Object { $_.Interface -eq $ifaceName }

			$dTotal = ($ifaceData | Measure-Object Download_Bytes -Sum).Sum
			$uTotal = ($ifaceData | Measure-Object Upload_Bytes -Sum).Sum
			$tTotal = ($ifaceData | Measure-Object Total_Bytes -Sum).Sum

			switch ($r.Name) {
		"Current Day" { 
			$periodText = "Current Day"
			$restText = ": $($now.DayOfWeek), $($now.ToString('dd.MM.yyyy'))"
		}
		"Current Week" { 
			$weekNum = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
				$now,
				[System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
				[DayOfWeek]::Monday
			)
			$periodText = "Current Week"
			$restText = ": $weekNum"
		}
		"Current Month" { 
			$periodText = "Current Month"
			$restText = ": " + (Get-Culture).DateTimeFormat.GetMonthName($now.Month) + " $($now.Year)"
		}
		"Current Year" { 
			$periodText = "Current Year"
			$restText = ": $($now.Year)"
		}
	}

	# Prikaz na header so boja samo za imeto na periodot
	Write-Host "`n[" -NoNewline
	Write-Host $periodText -ForegroundColor White -NoNewline  # Imeto e zholto
	Write-Host $restText -ForegroundColor Yellow -NoNewline      # Ostatokot zelen
	Write-Host "`]" -NoNewline
	Write-Host "- Interfejs: " -ForegroundColor White -NoNewline
	Write-Host $ifaceName -ForegroundColor $ifaceColor           # Ime na interfejs so boja
	Write-MonitorLog "[$periodText$restText] - Interfejs: $ifaceName" -NoDisplay

	# Prikaz na Download/Upload/Total vo razlicni boi
	Write-Host "    Download: " -NoNewline
	Write-Host (Format-Size $dTotal) -ForegroundColor Red -NoNewline
	Write-Host "     Upload: " -NoNewline
	Write-Host (Format-Size $uTotal) -ForegroundColor Blue -NoNewline
	Write-Host "     Total: " -NoNewline
	Write-Host (Format-Size $tTotal) -ForegroundColor Yellow
	Write-MonitorLog ("    Download: " + (Format-Size $dTotal) + "     Upload: " + (Format-Size $uTotal) + "     Total: " + (Format-Size $tTotal)) -NoDisplay
		}
	}

	# --- ALL INTERFACES ---
	Write-Host "`n--- All Interfaces ---`n" -ForegroundColor Cyan
	Write-MonitorLog "--- All Interfaces ---" -NoDisplay

	foreach ($r in $ranges) {
		$subset = $data | Where-Object { $_.Timestamp -ge $r.From }
		if (-not $subset -or $subset.Count -eq 0) { continue }

		$dTotal = ($subset | Measure-Object Download_Bytes -Sum).Sum
		$uTotal = ($subset | Measure-Object Upload_Bytes -Sum).Sum
		$tTotal = ($subset | Measure-Object Total_Bytes -Sum).Sum

	switch ($r.Name) {
		"Current Day" { 
			$periodText = "Current Day"
			$restText = ": $($now.DayOfWeek), $($now.ToString('dd.MM.yyyy'))"
		}
		"Current Week" { 
			$weekNum = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
				$now,
				[System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
				[DayOfWeek]::Monday
			)
			$periodText = "Current Week"
			$restText = ": $weekNum"
		}
		"Current Month" { 
			$periodText = "Current Month"
			$restText = ": " + (Get-Culture).DateTimeFormat.GetMonthName($now.Month) + " $($now.Year)"
		}
		"Current Year" { 
			$periodText = "Current Year"
			$restText = ": $($now.Year)"
		}
	}

	# Прикажување: името на периодот жолта, остатокот и Interfejs зелени
	Write-Host "`n[" -NoNewline
	Write-Host $periodText -ForegroundColor Green -NoNewline  # Името е обоено
	Write-Host $restText -ForegroundColor Yellow -NoNewline      # Остатокот зелен
	Write-Host "`]" -NoNewline
	Write-Host " - Interfejs:" -ForegroundColor Green -NoNewline
	Write-Host " All Interfaces" -ForegroundColor DarkYellow
	Write-MonitorLog ("[$periodText$restText] - Interfejs: All Interfaces") -NoDisplay

    # Prikaz na Download/Upload/Total vo razlicni boi
    Write-Host "    Download: " -NoNewline
    Write-Host (Format-Size $dTotal) -ForegroundColor Red -NoNewline
    Write-Host "     Upload: " -NoNewline
    Write-Host (Format-Size $uTotal) -ForegroundColor Blue -NoNewline
    Write-Host "     Total: " -NoNewline
    Write-Host (Format-Size $tTotal) -ForegroundColor Cyan
    Write-MonitorLog ("    Download: " + (Format-Size $dTotal) + "     Upload: " + (Format-Size $uTotal) + "     Total: " + (Format-Size $tTotal)) -NoDisplay
    }
}

# --- PRIKAZI POSLEDNI 50 MONITOR LOG ZAPISI ---
function Monitor-Log {
    if (Test-Path $Global:monitorLogFile) {
        $logContent = Get-Content $Global:monitorLogFile -Tail 50
        Write-Host "`n=== Last 50 Net Monitoring Log entries ===`n" -ForegroundColor Cyan
        $logContent | ForEach-Object { Write-Host $_ -ForegroundColor Gray }

        if ($BotToken -and $ChatID) {
            $msg = "=== Last 50 Net Monitoring Log entries ===`n" + ($logContent -join "`n")
            Start-Sleep -Seconds 5
            Send-TelegramMessage -message $msg
        }
    } else {
        $msg = "No monitor log file found in: $Global:monitorLogFile"
        Write-Host $msg -ForegroundColor Yellow
        Write-MonitorLog -Message $msg -Color Yellow -NoDisplay

        if ($BotToken -and $ChatID) {
            Start-Sleep -Seconds 5
            Send-TelegramMessage -message $msg
        }
    }
}

# === lIVE PANEL ===
function Show-LiveTraffic {
    $scriptPath = Join-Path $PSScriptRoot "NetMonitor.exe"
    $isRunning = Get-CimInstance Win32_Process |
                 Where-Object { $_.CommandLine -like "*NetMonitor.exe*" }
    if ($isRunning) {
        Write-Host "Net Monitor Panel is already RUNNING!" -ForegroundColor Yellow
        return
    }
    if (Test-Path $scriptPath) {
        Write-Host "Launching Net Monitor Panel..." -ForegroundColor Cyan
        Start-Process `
            -FilePath "$scriptPath" `
            -WindowStyle Hidden
    }
    else {
        Write-Host "NetMonitor.exe not found!" -ForegroundColor Red
    }
}

# === EXIT lIVE PANEL ===
function Stop-LiveTraffic {
    $running = Get-CimInstance Win32_Process |
               Where-Object { $_.CommandLine -like "*NetMonitor.exe*" }
    if ($running) {
        Write-Host "Exit Net Monitor Panel..." -ForegroundColor Cyan
        foreach ($p in $running) {
            Stop-Process -Id $p.ProcessId -Force
        }
    }
    else {
        Write-Host "Net Monitor Panel is already EXIT!" -ForegroundColor Yellow
    }
}

# === AutoRun (for Telegram etc) ===
if ($AutoRunOps.Count -gt 0) {
    foreach ($op in $AutoRunOps) {
        switch ($op.ToLower()) {
            "1"  { Start-Monitoring }
            "2"  { Stop-Monitoring }
            "3"  { Show-MonitoringStatus | ConvertTo-Json -Compress | Write-Output }
			"4"  { if (Test-Path $CsvPath) { Get-Content $CsvPath -Tail 8 } else { Write-Host "No CSV log file found." } ; Read-Host "Press Enter..." }
            "5"  { Show-TrafficStatus }
			"6"  { Monitor-Log }
			"7"  { Show-LiveTraffic }
			"8"  { Stop-LiveTraffic }
             default  { Write-Warning "Unknown command: $op" }
        }
    }
    if ($Silent) { exit }
}

# === Interactive menu ===
function Show-Menu {
    Clear-Host
    Write-Host "=== Net Traffic Monitoring ===`n" -ForegroundColor Cyan

    Write-Host "1) Start Monitoring" -ForegroundColor Green
    Write-Host "2) Stop Monitoring" -ForegroundColor Red
    Write-Host "3) Status Monitoring" -ForegroundColor Blue
    Write-Host "4) CSV File" -ForegroundColor Yellow
    Write-Host "5) Traffic Statistic" -ForegroundColor DarkYellow
    Write-Host "6) Monitoring Log_File" -ForegroundColor DarkCyan
    Write-Host "7) Live Traffic Panel" -ForegroundColor DarkGreen
    Write-Host "8) Exit Live Traffic Panel" -ForegroundColor Blue
    Write-Host ""
    Write-Host "=== Close Traffic Monitoring ===`n" -ForegroundColor Cyan
    Write-Host "9) Exit" -ForegroundColor DarkRed
    Write-Host ""
}

if (-not $Silent) {
    while ($true) {
        Show-Menu
        $choice = Read-Host "Choose option (1-7)"
        switch ($choice) {
			"1" { Start-Monitoring; Read-Host "Press Enter to continue..." }
			"2" { Stop-Monitoring; Read-Host "Press Enter to continue..." }
			"3" { Show-MonitoringStatus | Format-List; Read-Host "Press Enter to continue..." }
			"4" { if (Test-Path $CsvPath) { Get-Content $CsvPath -Tail 8 } else { Write-Host "No CSV log file found." } ; Read-Host "Press Enter..." }
			"5" { Show-TrafficStatus; Read-Host "Press Enter to continue..." }
			"6" { Monitor-Log; Read-Host "Press Enter to continue..." }
			"7" { Show-LiveTraffic; Read-Host "`nPress Enter to return to menu..." }
			"8" { Stop-LiveTraffic; Read-Host "`nPress Enter to return to menu..." }
			"9" { 
				Stop-Monitoring
				Write-Host "The script is closing..." -ForegroundColor Red
				Write-MonitorLog "The script is closing..." -NoDisplay
				Start-Sleep -Seconds 1
				exit
			}
			default { Write-Host "Invalid option" -ForegroundColor Red; Start-Sleep -Milliseconds 500 }
		}
    }
}

############################################################################## Net Traffic Script End.