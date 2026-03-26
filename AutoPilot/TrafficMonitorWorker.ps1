param(
    [string]$CsvPath = "$PSScriptRoot\Data\traffic.csv",
    [int]$SampleIntervalSeconds = 1,    # Мерење секоја секунда
    [int]$WriteIntervalSeconds = 30,    # Запишување во CSV на секои 30 секунди
    [int]$AutoSaveIntervalSeconds = 15, # Auto-save за fail-safe
    [string]$StopFlagFile = "$PSScriptRoot\Autopilot_Data\Traffic_Logs\TrafficMonitor_Stop.flag"
)

# Проверка за админ
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "The script must be run as Administrator!"
    if (-not $Silent) { Pause }
    Exit
}

# --- Monitor log folder and file (same as other script) ---
$Global:monitorLogFolder = "$PSScriptRoot\Autopilot_Data\Traffic_Logs"
if (-not (Test-Path $Global:monitorLogFolder)) {
    New-Item -Path $Global:monitorLogFolder -ItemType Directory | Out-Null
}

$currentDate = Get-Date -Format 'yyyy-MM-dd'
$Global:monitorLogFile = "$Global:monitorLogFolder\traffic_$currentDate.txt"

if (-not (Test-Path $Global:monitorLogFile)) {
    New-Item -Path $Global:monitorLogFile -ItemType File | Out-Null
}

# ---  Write-TrafficLog function ---
function Write-TrafficLog {
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

# --- Create Start Flag ---
$WorkerStartFlag = "$PSScriptRoot\Autopilot_Data\Traffic_Logs\TrafficMonitor_Start.flag"
$startTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Set-Content -Path $WorkerStartFlag -Value $startTimestamp -Encoding UTF8
Write-TrafficLog "TrafficMonitorWorker STARTED at $startTimestamp"

# Подготовка на CSV ако не постои
if (-not (Test-Path $CsvPath)) {
    "Date,Download_Bytes/Upload_Bytes/Total_Bytes,Interface" | Out-File -FilePath $CsvPath -Encoding utf8
}

# Отстрани стар stop flag ако постои
if (Test-Path $StopFlagFile) { Remove-Item $StopFlagFile -Force }

# Инициализација на дневни totals
$dailyTotals = @{ }

# Load DLL
Add-Type -Path "$PSScriptRoot\Dll\NetMonitor.dll"

# Load existing CSV into $dailyTotals (од претходната имплементација)
if (Test-Path $CsvPath) {
    $lines = Get-Content $CsvPath
    if ($lines.Count -gt 1) {
        foreach ($line in $lines[1..($lines.Count-1)]) {
            if ($line -match "^([^,]+),([^,]+),(.+)$") {
                $date = $matches[1]
                $vals = $matches[2]
                $iface = $matches[3]
                $parts = $vals -split '/'
                if (-not $dailyTotals.ContainsKey($date)) { $dailyTotals[$date] = @{} }
                $dailyTotals[$date][$iface] = @{
                    DL = [int64]$parts[0]
                    UL = [int64]$parts[1]
                    Total = [int64]$parts[2]
                }
            }
        }
    }
}

# Function to write CSV
function Write-CSV {
    $tmp = "$CsvPath.tmp"
    $header = "Date,Download_Bytes/Upload_Bytes/Total_Bytes,Interface"

    $linesToWrite = $dailyTotals.GetEnumerator() |
        Sort-Object { [datetime]::ParseExact($_.Key, 'yyyy/MM/dd', $null) } |
        ForEach-Object {
            $date = $_.Key
            $dailyTotals[$date].GetEnumerator() | ForEach-Object {
                $iface = $_.Key
                $totals = $_.Value
                "$date,$($totals.DL)/$($totals.UL)/$($totals.Total),$iface"
            }
        }
    # Запиши атомски во .tmp
    $header | Out-File -FilePath $tmp -Encoding utf8
    $linesToWrite | Out-File -FilePath $tmp -Encoding utf8 -Append

    # Замени го оригиналниот CSV без ризик да се корумпира
    Move-Item -Path $tmp -Destination $CsvPath -Force
}

# === Main loop initialization ===
$writeCounter = 0
$autoSaveCounter = 0

# AutoPilot path and cooldown
$autoPilotPath = Join-Path $PSScriptRoot "Autopilot.ps1"
$autoCheckCooldown = 0
$autoPilotActive = $true

try {
    while (-not (Test-Path $StopFlagFile)) {
        # --- AutoPilot check секои 500 секунди (CPU-friendly) ---
        if ($autoCheckCooldown -le 0) {
            $autoPilotActive = $false
            try {
                # земи сите powershell процеси само кога треба
                $processes = Get-Process -Name "powershell" -ErrorAction SilentlyContinue
                foreach ($p in $processes) {
                    try {
                        $procInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)"
                        if ($procInfo -and $procInfo.CommandLine -and ($procInfo.CommandLine -match [regex]::Escape($autoPilotPath))) {
                            $autoPilotActive = $true
                            break
                        }
                    } catch {
                        # ignore single-process failures
                    }
                }
            } catch {
                # ignore overall failure, treat as not active to be safe
                $autoPilotActive = $false
            }
            # следната проверка по 500 секунди
            $autoCheckCooldown = 500
        }

        if (-not $autoPilotActive) {
            # Креира stop flag ако не постои и заврши
            $stopFlagFolder = Split-Path $StopFlagFile
            if (-not (Test-Path $stopFlagFolder)) {
                New-Item -Path $stopFlagFolder -ItemType Directory | Out-Null
            }
			
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Set-Content -Path $StopFlagFile -Value $timestamp -Encoding UTF8
            Write-Host "AutoPilot.ps1 not Active. Monitoring will Stop in $timestamp."
            Write-TrafficLog "AutoPilot.ps1 not Active. Monitoring STOPPED."
            Write-TrafficLog "TrafficMonitorWorker is Stopping because AutoPilot is not RUNNING. Time: $timestamp"
            break
        }

        # намалување на cooldown според Sample интервалот
        $autoCheckCooldown -= $SampleIntervalSeconds

        # --- Повик на SampleAll() за сите интерфејси ---
        $samples = [NetMonitor.TrafficNative]::SampleAll()
        if (-not $samples -or $samples.Count -eq 0) {
            Start-Sleep -Seconds $SampleIntervalSeconds
            continue
        }

        foreach ($sample in $samples) {
            $iface = $sample.Interface
            $currentDate = (Get-Date).ToString("yyyy/MM/dd")
            $dl = [int64]$sample.DownloadBytes
            $ul = [int64]$sample.UploadBytes
            $total = [int64]$sample.TotalBytes

            if (-not $dailyTotals.ContainsKey($currentDate)) {
                $dailyTotals[$currentDate] = @{}
            }

            if (-not $dailyTotals[$currentDate].ContainsKey($iface)) {
                $dailyTotals[$currentDate][$iface] = @{ DL = 0; UL = 0; Total = 0 }
            }

            $dailyTotals[$currentDate][$iface].DL += $dl
            $dailyTotals[$currentDate][$iface].UL += $ul
            $dailyTotals[$currentDate][$iface].Total += $total

            Write-Host "$(Get-Date -Format HH:mm:ss) - $iface : Download=$dl Upload=$ul Total=$total"
        }

        # File save counters
        $writeCounter += $SampleIntervalSeconds
        $autoSaveCounter += $SampleIntervalSeconds

        if ($writeCounter -ge $WriteIntervalSeconds) {
            Write-CSV
            $writeCounter = 0
        }

        if ($autoSaveCounter -ge $AutoSaveIntervalSeconds) {
            Write-CSV
            $autoSaveCounter = 0
            Write-Host "Auto-save executed at $(Get-Date -Format HH:mm:ss)"
        }

        Start-Sleep -Seconds $SampleIntervalSeconds
    }
}
catch {
    $errTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-TrafficLog "ERROR in TrafficMonitorWorker at $errTime : $($_.Exception.Message)"
    throw
}
finally {
    Write-Host "`nSaving last measured data before exit..."
    Write-CSV
    Write-Host "All pending data saved to CSV successfully!"
    $stopTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-TrafficLog "TrafficMonitorWorker stopped at $stopTimestamp"
}

########################################################################################## Traffic Monitor Worker Script End.