Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
# ============================================================
# 🔐 AutoPilot SECURITY DESIGN Script
# ============================================================
# • Commands accepted ONLY from OwnerId
# • Private chats only (non-private blocked)
# • Unauthorized access is logged (AUDIT)
# • Security alerts enabled with rate-limit
# • Y/N confirmations are case-sensitive
# • Protected against brute-force & injection
# ------------------------------------------------------------
# Status: PRODUCTION-READY
# ============================================================

# --- Admin authorization ---
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "AutoPilot must be run as Administrator!"
    if (-not $Silent) { Pause }
    Exit
}

# --- App ROOT ---
$AppRoot = $PSScriptRoot

# ================= JSON LOADER =================
$settingsPath = Join-Path -Path $PSScriptRoot -ChildPath "JSON\settings.json"

if (-not (Test-Path $settingsPath)) {
    Write-Host "Config file does not exist in $settingsPath" -ForegroundColor Red
    Pause
    return
}

try {
    $config = Get-Content $settingsPath -Raw | ConvertFrom-Json
} catch {
    Write-Warning "Error Loading settings.json: $_"
    Pause
    return
}

# ================= HELPER FUNCTIONS =================
function Get-IntConfigValue([PSCustomObject]$cfg, [string]$name, [int]$default) {
    if ($cfg.PSObject.Properties.Name -contains $name -and [int]::TryParse($cfg.$name,[ref]$null)) {
        return [int]$cfg.$name
    }
    return $default
}

function Get-BoolConfigValue([PSCustomObject]$cfg, [string]$name, [bool]$default) {
    if ($cfg.PSObject.Properties.Name -contains $name) {
        return [bool]$cfg.$name
    }
    return $default
}

function Validate-TelegramBotConfig(
    [string]$botName,
    [string]$token,
    [string]$chatId,
    [array]$ownerIds,
    [string]$url = $null
) {
    $errors = @()
    if (-not $token -or $token.Length -lt 10) { $errors += "$botName Token is not valid" }
    if (-not ($chatId -match '^-?\d+$')) { $errors += "$botName CHAT_ID not a valid number" }
    if (-not $ownerIds -or $ownerIds.Count -eq 0) {
        $errors += "$botName OWNER_IDS not set"
    } else {
        foreach ($id in $ownerIds) {
            if (-not ($id -match '^\d+$')) { $errors += "$botName OWNER_IDS contains an invalid ID: $id" }
        }
    }
    if ($url -and -not ($url -match '^https?://[^\s/$.?#].[^\s]*$')) {
        $errors += "$botName URL not a valid"
    }
    return $errors
}

# ================= LOAD MAIN CONFIG =================
$TempCheckInterval = Get-IntConfigValue $config "TEMP_CHECK_INTERVAL" 300
$AutoStartMonitoring = Get-BoolConfigValue $config "AUTO_START_MONITORING" $false
$TrafficMonitorAutoStart = Get-BoolConfigValue $config "TRAFFIC_MONITOR_AUTO_START" $false

$allowedDays = if ($config.PSObject.Properties.Name -contains "ALLOWED_DAYS" -and $config.ALLOWED_DAYS) {
    $config.ALLOWED_DAYS
} else { @("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday") }

$maxRuns = Get-IntConfigValue $config "MAX_RUNS" 1
$cpuLimit = Get-IntConfigValue $config "CPU_LIMIT" 50
$cpuTempCriticalLimit = Get-IntConfigValue $config "CPU_TEMP_CRITICAL_LIMIT" 60
$diskLimit = Get-IntConfigValue $config "DISK_LIMIT" 45
$diskTempCriticalLimit = Get-IntConfigValue $config "DISK_TEMP_CRITICAL_LIMIT" 52
$mbLimit = Get-IntConfigValue $config "MB_LIMIT" 45
$mbTempCriticalLimit = Get-IntConfigValue $config "MB_TEMP_CRITICAL_LIMIT" 50
$gpuLimit = Get-IntConfigValue $config "GPU_LIMIT" 50
$gpuTempCriticalLimit = Get-IntConfigValue $config "GPU_TEMP_CRITICAL_LIMIT" 70
$ramUsageAlarmLimit = Get-IntConfigValue $config "RAM_USAGE_ALARM_LIMIT" 60
$ramUsageCriticalLimit = Get-IntConfigValue $config "RAM_USAGE_CRITICAL_LIMIT" 88
$cpuLoadAlarmLimit = Get-IntConfigValue $config "CPU_LOAD_ALARM_LIMIT" 88
$cpuLoadCriticalLimit = Get-IntConfigValue $config "CPU_LOAD_CRITICAL_LIMIT" 101

# ================= Command Toggle Flags =================
$enableRestart = Get-BoolConfigValue $config "ENABLE_RESTART" $false
$enableShutdown = Get-BoolConfigValue $config "ENABLE_SHUTDOWN" $false

function Set-CommandState([string]$command, [bool]$enable) {
    if ($enable) {
        return $command -replace '^\s*#\s*',''  # uncomment
    } else {
        if ($command -notmatch '^\s*#') {
            return "# $command"                  # comment
        } else {
            return $command
        }
    }
}

$restartCmd  = Set-CommandState "Restart-Computer -Force" $enableRestart
$shutdownCmd = Set-CommandState "Stop-Computer -Force" $enableShutdown

# ================= Toggle Flags =================
$AutoPilotTelegramEnabled = Get-BoolConfigValue $config "AUTOPILOT_TELEGRAM_ENABLED" $false
$MediaTelegramEnabled     = Get-BoolConfigValue $config "MEDIA_TELEGRAM_ENABLED" $false

# ================= AutoPilot Telegram Bot =================
if ($AutoPilotTelegramEnabled) {
    $telegramBotToken = $config.TELEGRAM_BOT_TOKEN
    $telegramChatId   = $config.TELEGRAM_CHAT_ID
    $OwnerId          = $config.OWNER_ID
    $autoPilotUrl     = $config.AUTOPILOT_URL  

    if (-not $autoPilotUrl -or $autoPilotUrl.Trim() -eq "") {
        Write-Host "AUTOPILOT_URL missing in AutoPilot Settings (Empty)!" -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
    $errors = Validate-TelegramBotConfig "AutoPilot" $telegramBotToken $telegramChatId @($OwnerId) $autoPilotUrl
    if ($errors.Count -gt 0) {
        Write-Host "ERROR: AutoPilot Telegram Bot is *ENABLED, but the configuration is invalid!" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
        Write-Host "Check the AutoPilot Bot settings in AutoPilot Settings." -ForegroundColor DarkCyan
        Pause
        return
    }
    $OwnerId = [long]$OwnerId
    Write-Host "AutoPilot Telegram Bot is *ENABLED and properly configured." -ForegroundColor Green
} else {
    Write-Host "AutoPilot Telegram Bot is *DISABLED, skipping." -ForegroundColor DarkYellow
	Start-Sleep -Seconds 3
}

# ================= Media Telegram Bot =================
if ($MediaTelegramEnabled) {
    $MediaFolderUrl = $config.MEDIA_FOLDER_URL
    $BotToken       = $config.BOT_TOKEN
    $ChatId         = $config.CHAT_ID
    $OwnerIds       = $config.OWNER_IDS

    $errors = Validate-TelegramBotConfig "Media" $BotToken $ChatId $OwnerIds $MediaFolderUrl
    if ($errors.Count -gt 0) {
        Write-Host "WARNING: Media Telegram Bot is *ENABLED, but the configuration is invalid!" -ForegroundColor Yellow
        $errors | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
        Write-Host "Check the Media Bot settings in AutoPilot Settings." -ForegroundColor DarkCyan
        Start-Sleep -Seconds 3
    } else {
        Write-Host "Media Telegram Bot is *ENABLED and properly configured." -ForegroundColor Green
        Start-Sleep -Seconds 3
    }
} else {
    Write-Host "Media Telegram Bot is *DISABLED, skipping." -ForegroundColor DarkYellow
	Start-Sleep -Seconds 3
}
# ================= END CONFIG LOADING =================

# Global variables
$global:scriptStopped = $false
$global:scriptPaused = $false
$global:confirmationRequests = @{}
$lastUpdateId = 0
$global:CurrentStationIndex = 0
$global:VLCProcess = $null

# --- Anti-spam alarm rate-limit 
if (-not $global:LastAuditAlert) { $global:LastAuditAlert = @{} }

# --- GLOBAL VARIABLES ---
$Global:WorkerPath = "$PSScriptRoot\SystemMonitorWorker.ps1"
$Global:pauseFlagPath = "$PSScriptRoot\Autopilot_Data\pause.flag"

# --- Command Execution ---
$global:commandsExecuted = @{}

# --- Modular Scripts ---
. "$PSScriptRoot\Graphs.ps1"
. "$PSScriptRoot\Media.ps1"
. "$PSScriptRoot\NetTrafficTable.ps1"
. "$PSScriptRoot\System.ps1"

# 🟩 INICIJALIZACIJA NA LOGOVI ZA AUTOPILOT Main ***
$Global:logDate = Get-Date -Format 'yyyy-MM-dd'
$Global:logFolder = "$PSScriptRoot\Autopilot_Data\Autopilot_Logs"
if (-not (Test-Path $Global:logFolder)) {
    New-Item -Path $Global:logFolder -ItemType Directory | Out-Null
}
# 📄 Дневен лог фајл za AUTOPILOT
$Global:logPath = "$Global:logFolder\autopilot_$Global:logDate.txt"

# 🟩 INICIJALIZACIJA NA LOGOVI ZA MONITORING Function ***
$Global:monitoringDate = Get-Date -Format 'yyyy-MM-dd'
$Global:monitoringLogsFolder = "$PSScriptRoot\Autopilot_Data\Monitoring_Logs"
if (-not (Test-Path $Global:monitoringLogsFolder)) {
    New-Item -Path $Global:monitoringLogsFolder -ItemType Directory | Out-Null
}
# 📄 Дневен лог фајл za MONITORING
$Global:LogFile = "$Global:monitoringLogsFolder\monitoring_$Global:monitoringDate.txt"

# 🟩 INICIJALIZACIJA NA LOGOVI ZA DATA Function ***
$Global:dataDate = Get-Date -Format 'yyyy-MM-dd'
$Global:dataLogFolder = "$PSScriptRoot\Autopilot_Data\DataFolder_Logs"
if (-not (Test-Path $Global:dataLogFolder)) { 
    New-Item -Path $Global:dataLogFolder -ItemType Directory | Out-Null 
}
# 📄 Дневен лог фајл za DATA
$Global:dataLogFile = "$Global:dataLogFolder\audit_$Global:dataDate.txt"

# 🟩 INICIJALIZACIJA NA LOGOVI ZA UPDATER ***
$Global:updaterLogsFolder = "$PSScriptRoot\AutoPilot_Data\Update_Logs"
if (-not (Test-Path $Global:updaterLogsFolder)) {
    New-Item -Path $Global:updaterLogsFolder -ItemType Directory | Out-Null
}
# 📄 Лог фајл за UPDATER (фиксно име)
$Global:updaterLogFile = "$Global:updaterLogsFolder\Updater.log"

# --- Vlc radio station
$vlcPath = "C:\Program Files\VideoLAN\VLC\vlc.exe"
# Радио станици
$global:RadioStations = @(
    "http://hirschmilch.de:7000/techno.mp3",
    "http://hirschmilch.de:7000/psytrance.mp3",
    "http://hirschmilch.de:7000/progressive.mp3",
	"http://hirschmilch.de:7000/prog-house.mp3",
    "http://hirschmilch.de:7000/electronic.mp3",
    "http://hirschmilch.de:7000/chillout.mp3"
)

# --- Avtomatski komandi ---
function Load-AutoCommandsFromJson {
    param (
        [string]$JsonPath = "$PSScriptRoot\JSON\commands_edit.json"
    )
    if (-not (Test-Path $JsonPath)) {
        Write-Host " JSON file for AutoCommands not found: $JsonPath" -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    } else {
        try {
            $jsonContent = Get-Content -Path $JsonPath -Raw | ConvertFrom-Json
            if (-not $jsonContent.AutoCommands -or $jsonContent.AutoCommands.PSObject.Properties.Count -eq 0) {
                Write-Host " JSON file is empty or contains no AutoCommands: $JsonPath" -ForegroundColor Cyan
                Start-Sleep -Seconds 3
            }
        } catch {
            Write-Host " Error reading JSON file: $JsonPath" -ForegroundColor Red
            Start-Sleep -Seconds 3
        }
    }
    $global:AutoCommands = @{ }
    foreach ($key in $jsonContent.AutoCommands.PSObject.Properties.Name) {
        $command = $jsonContent.AutoCommands.$key
        $timesArray = @($command.Times)
        $repeatArray = @($command.RepeatIntervalMinutes)
        # ---------- LOGIKA ZA Day ----------
        $dayArray = @()
        if ($command.PSObject.Properties.Name -contains "Day" -and
            $command.Day -and
            $command.Day.Count -gt 0) {
            for ($i = 0; $i -lt $command.Day.Count; $i++) {
                if (-not [string]::IsNullOrWhiteSpace($command.Day[$i])) {
                    # Formatiraj datum da se osiguraju 2 cifri za mesec i dan
                    $parts = $command.Day[$i] -split "-"
                    $year = $parts[0]
                    $month = "{0:D2}" -f [int]$parts[1]
                    $day = "{0:D2}" -f [int]$parts[2]
                    $dayArray += "$year-$month-$day"
                }
                # Ako je prazno -> NE dodavaj, ostane prazno
            }
        }
        # ---------- Dodavanje u AutoCommands ----------
        $global:AutoCommands[$key] = @{
            Cmd = $command.Cmd
            Times = $timesArray
            RepeatIntervalMinutes = $repeatArray
            Type = $command.Type
            Day = $dayArray
        }
    }
}
# Ucitaj JSON
Load-AutoCommandsFromJson

$global:CommandToImagePath = @{
	# Graphs Load Temp
    "Generate-LoadGraph-Day"    = Join-Path $AppRoot "Data\load_1d.png"
    "Generate-LoadGraph-Week"   = Join-Path $AppRoot "Data\load_7d.png"
    "Generate-LoadGraph-Month"  = Join-Path $AppRoot "Data\load_30d.png"
    "Generate-LoadGraph-Year"   = Join-Path $AppRoot "Data\load_365d.png"
	"Generate-LoadGraph-All"    = Join-Path $AppRoot "Data\load_Alld.png"

    "Generate-TempGraph-Day"    = Join-Path $AppRoot "Data\temperature_1d.png"
    "Generate-TempGraph-Week"   = Join-Path $AppRoot "Data\temperature_7d.png"
    "Generate-TempGraph-Month"  = Join-Path $AppRoot "Data\temperature_30d.png"
    "Generate-TempGraph-Year"   = Join-Path $AppRoot "Data\temperature_365d.png"
	"Generate-TempGraph-All"    = Join-Path $AppRoot "Data\temperature_Alld.png"

	"Generate-DiskGraph-Day"    = Join-Path $AppRoot "Data\disk_1d.png"
    "Generate-DiskGraph-Week"   = Join-Path $AppRoot "Data\disk_7d.png"
    "Generate-DiskGraph-Month"  = Join-Path $AppRoot "Data\disk_30d.png"
    "Generate-DiskGraph-Year"   = Join-Path $AppRoot "Data\disk_365d.png"
	"Generate-DiskGraph-All"    = Join-Path $AppRoot "Data\disk_Alld.png"

	"Take-Screenshot"           = Join-Path $AppRoot "Screenshot\screenshot.png"

	# Table Network Traffic
	"Generate-TableGraph-Day"   = Join-Path $AppRoot "Data\table_1d.png"
	"Generate-TableGraph-Week"  = Join-Path $AppRoot "Data\table_7d.png"
	"Generate-TableGraph-Month" = Join-Path $AppRoot "Data\table_30d.png"
	"Generate-TableGraph-Year"  = Join-Path $AppRoot "Data\table_365d.png"
	"Generate-TableGraph-All"   = Join-Path $AppRoot "Data\table_Alld.png"
}

# --- Avtomatski komandi (vremenski zakazani) za 8 scripti
$configPath = "$PSScriptRoot\JSON\scripts_edit.json"
if (-not (Test-Path $configPath)) {
    Write-Host " JSON file for Scripts not found: $configPath" -ForegroundColor Yellow
    Start-Sleep -Seconds 3
} else {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        if (-not $config.ScheduledScripts -or $config.ScheduledScripts.Count -eq 0) {
            Write-Host " JSON file is empty or contains no Scripts: $configPath" -ForegroundColor Cyan
            Start-Sleep -Seconds 3
        }
    } catch {
        Write-Host " Error reading JSON file: $configPath" -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
}
$ScheduledScripts = @()
foreach ($script in $config.ScheduledScripts) {
    $scriptPath = Join-Path $PSScriptRoot $script.Path # Kreiraj novi hashtable za svaki script
    $ScheduledScripts += @{
        Path = $scriptPath # Path = $script.Path
        Commands = $script.Commands
        Times = $script.Times
        DelaySeconds = $script.DelaySeconds
        RepeatIntervalMinutes = $script.RepeatIntervalMinutes
        Day = @()  # Start empty, only fill if JSON has real Day
    }
    # Popuni Day array samo ako JSON ima vrednosti
    for ($i = 0; $i -lt $script.Commands.Count; $i++) {
        if ($script.PSObject.Properties.Name -contains "Day" -and
            $script.Day -and
            $script.Day.Count -gt $i -and
            -not [string]::IsNullOrWhiteSpace($script.Day[$i])) {
            # Formatiraj datum da se osiguraju 2 cifri za mesec i dan
            $parts = $script.Day[$i] -split "-"
            $year = $parts[0]
            $month = "{0:D2}" -f [int]$parts[1]
            $day = "{0:D2}" -f [int]$parts[2]
            $ScheduledScripts[-1].Day += "$year-$month-$day"
        }
        else {
            # Empty
        }
    }
}

# Manuelni komandi za Telegram (5 za sekoja skripta)
$ManualCommands = @{
    # Defender manual commands
    "/def1"  = @{ Path = Join-Path $AppRoot "Defender.ps1"; Cmd = "1" }
    "/def2"  = @{ Path = Join-Path $AppRoot "Defender.ps1"; Cmd = "2" }
    "/def3"  = @{ Path = Join-Path $AppRoot "Defender.ps1"; Cmd = "3" }
    "/def4"  = @{ Path = Join-Path $AppRoot "Defender.ps1"; Cmd = "4" }
    "/def5"  = @{ Path = Join-Path $AppRoot "Defender.ps1"; Cmd = "5" }
    # Pi manual commands
    "/pi1"   = @{ Path = Join-Path $AppRoot "Pi.ps1"; Cmd = "1" }
    "/pi2"   = @{ Path = Join-Path $AppRoot "Pi.ps1"; Cmd = "2" }
    "/pi3"   = @{ Path = Join-Path $AppRoot "Pi.ps1"; Cmd = "3" }
    "/pi4"   = @{ Path = Join-Path $AppRoot "Pi.ps1"; Cmd = "4" }
    "/pi5"   = @{ Path = Join-Path $AppRoot "Pi.ps1"; Cmd = "5" }
    "/pi6"   = @{ Path = Join-Path $AppRoot "Pi.ps1"; Cmd = "6" }
    # Docker manual commands
    "/docker1"  = @{ Path = Join-Path $AppRoot "Docker.ps1"; Cmd = "1" }
    "/docker2"  = @{ Path = Join-Path $AppRoot "Docker.ps1"; Cmd = "2" }
    "/docker3"  = @{ Path = Join-Path $AppRoot "Docker.ps1"; Cmd = "3" }
    "/docker4"  = @{ Path = Join-Path $AppRoot "Docker.ps1"; Cmd = "4" }
    "/docker5"  = @{ Path = Join-Path $AppRoot "Docker.ps1"; Cmd = "5" }
    "/docker6"  = @{ Path = Join-Path $AppRoot "Docker.ps1"; Cmd = "6" }
    "/docker7"  = @{ Path = Join-Path $AppRoot "Docker.ps1"; Cmd = "7" }
    "/docker8"  = @{ Path = Join-Path $AppRoot "Docker.ps1"; Cmd = "8" }
    "/docker9"  = @{ Path = Join-Path $AppRoot "Docker.ps1"; Cmd = "9" }
    "/docker10" = @{ Path = Join-Path $AppRoot "Docker.ps1"; Cmd = "10" }
    # Cleaner manual commands
    "/cleaner1"  = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "1" }
    "/cleaner2"  = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "2" }
    "/cleaner3"  = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "3" }
    "/cleaner4"  = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "4" }
    "/cleaner5"  = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "5" }
    "/cleaner6"  = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "6" }
    "/cleaner7"  = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "7" }
    "/cleaner8"  = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "8" }
    "/cleaner9"  = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "9" }
    "/cleaner10" = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "10" }
    "/cleaner11" = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "11" }
    "/cleaner12" = @{ Path = Join-Path $AppRoot "Cleaner.ps1"; Cmd = "12" }
    # Network manual commands
    "/net1" = @{ Path = Join-Path $AppRoot "Network.ps1"; Cmd = "1" }
    "/net2" = @{ Path = Join-Path $AppRoot "Network.ps1"; Cmd = "2" }
    "/net3" = @{ Path = Join-Path $AppRoot "Network.ps1"; Cmd = "3" }
    "/net4" = @{ Path = Join-Path $AppRoot "Network.ps1"; Cmd = "4" }
    "/net5" = @{ Path = Join-Path $AppRoot "Network.ps1"; Cmd = "5" }
    "/net6" = @{ Path = Join-Path $AppRoot "Network.ps1"; Cmd = "6" }
    "/net7" = @{ Path = Join-Path $AppRoot "Network.ps1"; Cmd = "7" }
    "/net8" = @{ Path = Join-Path $AppRoot "Network.ps1"; Cmd = "8" }
    "/net9" = @{ Path = Join-Path $AppRoot "Network.ps1"; Cmd = "9" }
    # Net Traffic manual commands
    "/net_monitoring1" = @{ Path = Join-Path $AppRoot "NetTraffic.ps1"; Cmd = "1" }
    "/net_monitoring2" = @{ Path = Join-Path $AppRoot "NetTraffic.ps1"; Cmd = "2" }
    "/net_monitoring3" = @{ Path = Join-Path $AppRoot "NetTraffic.ps1"; Cmd = "3" }
    "/net_monitoring4" = @{ Path = Join-Path $AppRoot "NetTraffic.ps1"; Cmd = "4" }
    "/net_monitoring5" = @{ Path = Join-Path $AppRoot "NetTraffic.ps1"; Cmd = "5" }
    "/net_monitoring6" = @{ Path = Join-Path $AppRoot "NetTraffic.ps1"; Cmd = "6" }
    "/net_monitoring7" = @{ Path = Join-Path $AppRoot "NetTraffic.ps1"; Cmd = "7" }
    "/net_monitoring8" = @{ Path = Join-Path $AppRoot "NetTraffic.ps1"; Cmd = "8" }
	# System commands
    "/system_status"      = @{ Cmd = "System-Status" }
	"/ping"               = @{ Cmd = "Get-NetworkStatus" }
	"/autopilot_log"      = @{ Cmd = "Autopilot-Log" } 
	"/update_log"         = @{ Cmd = "Update-Log" } 
	"/pause"              = @{ Cmd = "Pause" }
    "/resume"             = @{ Cmd = "Resume" }
    "/status"             = @{ Cmd = "Status" }
	"/restart"            = @{ Cmd = "Restart-System" }
    "/shutdown"           = @{ Cmd = "Shutdown-System" }
    "/stop"               = @{ Cmd = "Stop-Script" }
	"/hide"               = @{ Cmd = "Hide-Script" }
    "/show"               = @{ Cmd = "Show-Script" }
	"/visible_status"     = @{ Cmd = "Visible-Status" }
	"/reset"              = @{ Cmd = "Reset-Script" }
	"/temp"               = @{ Cmd = "Get-Temperatures" }
	"/netusage"           = @{ Cmd = "Net-Usage" }
	"/monitor_open"       = @{ Cmd = "Open-SystemMonitor" }
	"/monitor_exit"       = @{ Cmd = "Stop-SystemMonitor" }
	"/commands_list"      = @{ Cmd = "Commands-ListAll" }
	"/hardware_load"      = @{ Cmd = "Get-LoadOnlyHardwareData" }
    "/hardware_data"      = @{ Cmd = "Get-NonLoadHardwareData" }
    "/autostart_enable"   = @{ Cmd = "Enable-AutoStart" }
    "/autostart_disable"  = @{ Cmd = "Disable-AutoStart" }
    "/autostart_status"   = @{ Cmd = "Status-AutoStart" }
	"/start"              = @{ Cmd = "Show-HelpMenu" }
	"/shutdownPC"         = @{ Cmd = "Auto-Shutdown-System" }
	"/restartPC"          = @{ Cmd = "Auto-Restart-System" }
	"/pauseAP"            = @{ Cmd = "Pause-Script" }
	# Recordings commands
	"/screen"             = @{ Cmd = "Take-Screenshot" }
	"/record"             = @{ Cmd = "Take-ScreenRecord" }
	"/rec_start"          = @{ Cmd = "Start-Recording" }
	"/rec_stop"           = @{ Cmd = "Stop-Recording" }
	# Camera commands
	"/cam_start"          = @{ Cmd = "Start-CameraRecording" }
    "/cam_stop"           = @{ Cmd = "Stop-CameraRecording" }
	"/data"               = @{ Cmd = "Data-CameraRecording" }
	"/data_stop"          = @{ Cmd = "Stop-PythonScript" }
	"/data_log"           = @{ Cmd = "Data-Log" }    
	# Monitoring Start Stop Status commands
	"/monitoring_start"   = @{ Cmd = "Monitoring-Start" }
    "/monitoring_stop"    = @{ Cmd = "Monitoring-Stop" }
    "/monitoring_status"  = @{ Cmd = "Monitoring-Status" }
	"/monitoring_log"     = @{ Cmd = "Monitoring-Log" } 
	# Graph Load commands
	"/load_day"           = @{ Cmd = "Generate-LoadGraph-Day" }
    "/load_week"          = @{ Cmd = "Generate-LoadGraph-Week" }
    "/load_month"         = @{ Cmd = "Generate-LoadGraph-Month" }
    "/load_year"          = @{ Cmd = "Generate-LoadGraph-Year" }
	"/load_all"           = @{ Cmd = "Generate-LoadGraph-All" }
    # Graph Temperature commands
    "/temp_day"           = @{ Cmd = "Generate-TempGraph-Day" }
    "/temp_week"          = @{ Cmd = "Generate-TempGraph-Week" }
    "/temp_month"         = @{ Cmd = "Generate-TempGraph-Month" }
    "/temp_year"          = @{ Cmd = "Generate-TempGraph-Year" }
	"/temp_all"           = @{ Cmd = "Generate-TempGraph-All" }
	# Graph Disk Load commands
	"/disk_day"           = @{ Cmd = "Generate-DiskGraph-Day" }
    "/disk_week"          = @{ Cmd = "Generate-DiskGraph-Week" }
    "/disk_month"         = @{ Cmd = "Generate-DiskGraph-Month" }
    "/disk_year"          = @{ Cmd = "Generate-DiskGraph-Year" }
	"/disk_all"           = @{ Cmd = "Generate-DiskGraph-All" }
	# Table Net Traffic commands
	"/table_day"          = @{ Cmd = "Generate-TableGraph-Day" }
	"/table_week"         = @{ Cmd = "Generate-TableGraph-Week" }
	"/table_month"        = @{ Cmd = "Generate-TableGraph-Month" }
	"/table_year"         = @{ Cmd = "Generate-TableGraph-Year" }
	"/table_all"          = @{ Cmd = "Generate-TableGraph-All" }
	# User commands
	"/teamviewer_start"   = @{ Cmd = "Start-TeamViewer" }
    "/teamviewer_stop"    = @{ Cmd = "Stop-TeamViewer" }
    "/teamviewer_status"  = @{ Cmd = "Status-TeamViewer" }
	"/das_start"          = @{ Cmd = "Start-Das" }
	"/das_stop"           = @{ Cmd = "Stop-Das" }
	"/das_status"         = @{ Cmd = "Status-Das" }
	"/monitor_start"      = @{ Cmd = "Start-TrafficMonitor" }
    "/monitor_stop"       = @{ Cmd = "Stop-TrafficMonitor" }
    "/monitor_status"     = @{ Cmd = "Status-TrafficMonitor" }
	# Vlc commands
    "/vlc_play"   = @{ Cmd = "Play-VLC" }
    "/vlc_stop"   = @{ Cmd = "Stop-VLC" }
    "/vlc_next"   = @{ Cmd = "Next-Station" }
    "/vlc_prev"   = @{ Cmd = "Prev-Station" }
    "/vlc_status" = @{ Cmd = "VLC-Status" }
}
# 📌 Vreme na start na skriptata (za trajanje)
$scriptStartTime = Get-Date

# 🔄 UPDATE LOG FILE - Funkcija za log
function Update-LogPath {
    $currentDate = Get-Date -Format 'yyyy-MM-dd'
    # AUTOPILOT лог
    if ($Global:logDate -ne $currentDate) {
        $Global:logDate = $currentDate
        $Global:logPath = "$Global:logFolder\autopilot_$currentDate.txt"
        if (-not (Test-Path $Global:logPath)) {
            New-Item -Path $Global:logPath -ItemType File | Out-Null
        }
        # 🔥 Бришење на AUTOPILOT фајлови постари од 30 дена
        Get-ChildItem -Path $Global:logFolder -Filter "autopilot_*.txt" |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
            Remove-Item -Force
    }
    # MONITORING лог
    if ($Global:monitoringDate -ne $currentDate) {
        $Global:monitoringDate = $currentDate
        $Global:LogFile = "$Global:monitoringLogsFolder\monitoring_$currentDate.txt"
        if (-not (Test-Path $Global:LogFile)) {
            New-Item -Path $Global:LogFile -ItemType File | Out-Null
        }
        # 🔥 Бришење на MONITORING фајлови постари од 30 дена
        Get-ChildItem -Path $Global:monitoringLogsFolder -Filter "monitoring_*.txt" |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
            Remove-Item -Force
    }
}

# 📝 Funkcija za AUTOPILOT log
function Write-Log {
    param (
        [string]$Message,
        [switch]$Display
    )
    Update-LogPath
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Add-Content -Path $Global:logPath -Value $logMessage

    if ($Display) {
        Write-Host $Message -ForegroundColor Green
    }
}

# 📝 Funkcija za MONITORING log 
function Write-MonitoringLog {
    param (
        [string]$Message,
        [switch]$Display
    )
    Update-LogPath
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    try {
        # Otvori FileStream so FileShare.ReadWrite
        $fs = [System.IO.File]::Open(
            $Global:LogFile,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )
        $sw = New-Object System.IO.StreamWriter($fs)
        $sw.WriteLine($logMessage)
        $sw.Close()
        $fs.Close()
    }
    catch {
        Write-Host "Cannot write to the log file: $($_.Exception.Message)"
    }
    if ($Display) {
        Write-Host "[MONITORING] $Message" -ForegroundColor Yellow
    }
}

# ================= AutoPilot Telegram Bot =================
$global:TelegramDisabledLogged = $false

function Is-AutoPilotTelegramEnabled {
    return $AutoPilotTelegramEnabled
}

# 📨 Funkcija za isprakjanje poraki na Telegram
function Send-TelegramMessage {
    param (
        [string]$message
    )
	if (-not (Is-AutoPilotTelegramEnabled)) {
        if (-not $global:TelegramDisabledLogged) {
            Write-Log "AutoPilot Telegram Bot is disabled, message Skipped."
            $global:TelegramDisabledLogged = $true
        }
        return
    }
	# Header Footer
    $Footer = "`n" + ("-" * 18) + "`n* Autopilot | Start Menu - /start"
    $Message = $message + $Footer 
    
	$uri = "https://api.telegram.org/bot$telegramBotToken/sendMessage"
    $body = @{ chat_id = $telegramChatId; text = $message }
    try {
        $null = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ErrorAction Stop
        Write-Log "Telegram message sent"
    } catch {
        Write-Log "Error with Telegram: $_"
    }
}

# 🔄 Funkcija za dobivanje novite Telegram poraki (updates)
function Get-Updates {
	if (-not (Is-AutoPilotTelegramEnabled)) {
        if (-not $global:TelegramDisabledLogged) {
            Write-Log "AutoPilot Telegram Bot is disabled, message Skipped."
            $global:TelegramDisabledLogged = $true
        }
        return
    }
    # Lokacija na offset fajlot
    $offsetFile = "$PSScriptRoot\Autopilot_Data\Autopilot_Logs\offset.txt"
    $offset = 0

    # Proveri dali ima offset zacuvan
    if (Test-Path $offsetFile) {
        $offset = Get-Content $offsetFile | Out-String
        $offset = [int]$offset.Trim()
    }

    $uri = "https://api.telegram.org/bot$telegramBotToken/getUpdates?offset=$offset"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop

        if ($response.result.Count -gt 0) {
            # Zacuvaj posledno offset + 1 vo fajl
            $maxUpdateId = ($response.result | Sort-Object update_id -Descending | Select-Object -First 1).update_id
            $nextOffset = $maxUpdateId + 1
            Set-Content -Path $offsetFile -Value $nextOffset
        }

        return $response.result
    } catch {
        Write-Log "Error retrieving Telegram messages: $_"
        return @()
    }
}

# 🔄 SENT PHOTO MESSAGE
function Send-TelegramPhoto {
    param (
        [string]$photoPath,
        [string]$caption = ""
    )
    if (-not (Is-AutoPilotTelegramEnabled)) {
        if (-not $global:TelegramDisabledLogged) {
            Write-Log "AutoPilot Telegram Bot is disabled, message Skipped."
            $global:TelegramDisabledLogged = $true
        }
        return
    }
    if (-not (Test-Path $photoPath)) {
        Write-Host "File does not exist: $photoPath"
        return
    }

    Add-Type -AssemblyName System.Net.Http

    $client = [System.Net.Http.HttpClient]::new()
    $uri = "https://api.telegram.org/bot$telegramBotToken/sendPhoto"

    $content = [System.Net.Http.MultipartFormDataContent]::new()
    $content.Add([System.Net.Http.StringContent]::new($telegramChatId), "chat_id")
    $content.Add([System.Net.Http.StringContent]::new($caption), "caption")

    $fileStream = [System.IO.File]::OpenRead($photoPath)
    $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
    $content.Add($fileContent, "photo", [System.IO.Path]::GetFileName($photoPath))

    try {
        $response = $client.PostAsync($uri, $content).Result
        $result = $response.Content.ReadAsStringAsync().Result
        if ($response.IsSuccessStatusCode) {
            Write-Host "Telegram photo sent: $photoPath"
        }
        else {
            Write-Host "Error sending Telegram photo: $result"
        }
    }
    catch {
        Write-Host "Error sending Telegram photo: $_"
    }
    finally {
        $fileStream.Dispose()
        $client.Dispose()
    }
}

# 🔄 SENT VIDEO MESSAGE
function Send-TelegramVideo {
    param (
        [string]$videoPath,
        [string]$caption = ""
    )
    if (-not (Is-AutoPilotTelegramEnabled)) {
        if (-not $global:TelegramDisabledLogged) {
            Write-Log "AutoPilot Telegram Bot is disabled, message Skipped."
            $global:TelegramDisabledLogged = $true
        }
        return
    }
    if (-not (Test-Path $videoPath)) {
        Write-Host "File does not exist: $videoPath"
        return
    }

    Add-Type -AssemblyName System.Net.Http

    $client = [System.Net.Http.HttpClient]::new()
    $uri = "https://api.telegram.org/bot$telegramBotToken/sendVideo"

    $content = [System.Net.Http.MultipartFormDataContent]::new()
    $content.Add([System.Net.Http.StringContent]::new($telegramChatId), "chat_id")
    if ($caption) {
        $content.Add([System.Net.Http.StringContent]::new($caption, [System.Text.Encoding]::UTF8), "caption")
    }

    $fileStream = [System.IO.File]::OpenRead($videoPath)
    $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("video/mp4")
    $content.Add($fileContent, "video", [System.IO.Path]::GetFileName($videoPath))

    try {
        $response = $client.PostAsync($uri, $content).Result
        $result = $response.Content.ReadAsStringAsync().Result
        if ($response.IsSuccessStatusCode) {
            Write-Host "Telegram video sent: $videoPath"
        }
        else {
            Write-Host "Error sending Telegram video: $result"
        }
    }
    catch {
        Write-Host "Error sending Telegram video: $_"
    }
    finally {
        $fileStream.Dispose()
        $client.Dispose()
    }
}

############### Dashboard #################################
$panelPath = Join-Path $PSScriptRoot "Loading.ps1"
$flagFile = "$PSScriptRoot\Autopilot_Data\Dashboard.flag"

try {
    $listenerScript = {
        param($panelPath, $flagFile)
        while ($true) {
            try {
                # Proverka za key W
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -eq 'W') {
                        if (-not (Test-Path $flagFile)) {
                            # Kreiraj flag file
                            New-Item -Path $flagFile -ItemType File -Force | Out-Null
                            try {
                                & $panelPath
                            } finally {
                                # Remove flag file
                                Remove-Item $flagFile -ErrorAction SilentlyContinue
                                # Cistenje na eventualni W pritisnati dodeka Panel bil otvoren
                                while ([Console]::KeyAvailable) {
                                    [Console]::ReadKey($true) | Out-Null
                                }
                            }
                        }
                        else {
                            # Panel is Open ignore W
                        }
                    }
                }
            } catch {
                # Ignore Error
            }
            Start-Sleep -Milliseconds 50
        }
    }
    # Runspace
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    $ps.AddScript($listenerScript).AddArgument($panelPath).AddArgument($flagFile) | Out-Null
    $ps.BeginInvoke() | Out-Null

} finally {
    $dashboardRunning = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "AutoPilot.exe"
    }
    if (-not $dashboardRunning) {
        if (Test-Path $flagFile) {
            Remove-Item $flagFile -Force -ErrorAction SilentlyContinue
        }
    }
}

############### MONITORING CODE START ###############

# === START TRAFFIC MONITORING ===
if ($TrafficMonitorAutoStart) {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    if (-not (Test-Path ($DataFolder = Join-Path $PSScriptRoot "Data"))) {
        New-Item $DataFolder -ItemType Directory -Force | Out-Null
    }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\TrafficMonitorWorker.ps1`"" -WindowStyle Hidden
    Send-TelegramMessage "Network Monitoring is starting in $timestamp. TrafficMonitorWorker script has Started."
}

# === START MONITORING ===
function Start-Monitoring {
    $existing = Get-WmiObject Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match "SystemMonitorWorker\.ps1"
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    # --- Fixed flag file paths ---
    $monitoringStartFlag = "$Global:monitoringLogsFolder\monitoring_start.flag"
    # --- Ako worker proces postoi → ne startuvaj ---
    if ($existing) {
        $msg = "Monitoring is already Running (Active process)."
        Write-MonitoringLog $msg -NoDisplay
        Send-TelegramMessage $msg
        return
    }
    # --- Kreiraj ili osvezi start flag so timestamp ---
    Set-Content -Path $monitoringStartFlag -Value $timestamp -Encoding UTF8
    Add-Content -Path $Global:LogFile -Value "[$timestamp] Monitoring Startuvan vo $timestamp"
    # --- Start Worker proces ---
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($Global:WorkerPath)`""
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.UseShellExecute = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($proc) {
        Write-MonitoringLog "SystemMonitorWorker process started (PID: $($proc.Id))" -NoDisplay
    } else {
        Write-MonitoringLog "ERROR: SystemMonitorWorker process cannot be started!" -NoDisplay
    }
    $msg = "System Monitoring is Starting at $timestamp. SystemMonitorWorker script has Started."
    Write-MonitoringLog $msg -NoDisplay
    Send-TelegramMessage $msg
}
# === Автоматски старт ако е дозволено ===
if ($AutoStartMonitoring) {
    Start-Monitoring
}

# === STOP MONITORING ===
function Stop-Monitoring {
    $existing = Get-WmiObject Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -match "SystemMonitorWorker\.ps1"
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    # --- Fixed flag file paths ---
    $monitoringStopFlag = "$Global:monitoringLogsFolder\monitoring_stop.flag"
    if ($existing) {
        # --- Kreiraj/osvezi stop flag ---
        Set-Content -Path $monitoringStopFlag -Value $timestamp -Encoding UTF8
        # --- Zatvoranje na procesite direktno ---
        foreach ($proc in $existing) {
            try {
                Stop-Process -Id $proc.ProcessId -Force
            } catch {
                Write-MonitoringLog "ERROR while closing PID $($proc.ProcessId): $_" -NoDisplay
            }
        }
        Start-Sleep -Seconds 1
        $msg = "Monitoring is Stopped. SystemMonitorWorker script closed at $timestamp."
        Write-MonitoringLog $msg -NoDisplay
        Send-TelegramMessage $msg
    }
    # Ако Monitoring НЕ работи
    else {
        # --- Ако постои monitoring_stop.flag → земи реално stop време ---
        if (Test-Path $monitoringStopFlag) {
            $realStopTime = Get-Content $monitoringStopFlag
        } else {
            # ако нема flag → користи тековно време
            $realStopTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        }
        $msg = "Monitoring is Not Running. Last Stopped at $realStopTime"
        Write-MonitoringLog $msg -NoDisplay
        Send-TelegramMessage $msg
    }
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
        $msg = "Monitoring is ACTIVE. Started at $startTime."
    }
    elseif (-not $workerProc -and (Test-Path $monitoringStopFlag)) {
        $stopTime = Get-Content $monitoringStopFlag
        $msg = "Monitoring is STOPPED. Stopped at $stopTime."
    }
    elseif ((Test-Path $monitoringStartFlag) -and -not (Test-Path $monitoringStopFlag)) {
        $startTime = Get-Content $monitoringStartFlag
        $msg = "Monitoring may be active (process not found, start flag exists) since $startTime."
    }
    else {
        $msg = "Monitoring status cannot be determined (no flag files found)."
    }
    Write-MonitoringLog $msg -NoDisplay
    Send-TelegramMessage $msg
}
############### MONITORING CODE END ###############

# =========================================
# Функција за проверка на автоматски команди со DelaySeconds
# =========================================
function Check-AutoCommands {
    if ($global:scriptStopped) { return }
    $currentTime = Get-Date
    foreach ($commandKey in $global:AutoCommands.Keys) {
        $cmdInfo = $global:AutoCommands[$commandKey]
        for ($i = 0; $i -lt $cmdInfo.Times.Count; $i++) {
            $timeStr = $cmdInfo.Times[$i]
            $repeatMinutes = 0
            if ($cmdInfo.ContainsKey("RepeatIntervalMinutes") -and $cmdInfo.RepeatIntervalMinutes.Count -gt $i) {
                $repeatMinutes = $cmdInfo.RepeatIntervalMinutes[$i]
            }
            $targetTime = [datetime]::Today.Add([timespan]::Parse($timeStr))
            $execKey = "$commandKey-$timeStr"
            # ===== КАЛЕНДАРСКА ЛОГИКА ЗА ИЗВРШУВАЊЕ =====
            $shouldRun = $true
            $type = if ($cmdInfo.ContainsKey("Type")) { $cmdInfo.Type.ToLower() } else { "daily" }
            switch ($type) {
                "weekly" {
                    if ($currentTime.DayOfWeek -ne 'Sunday') {
                        $shouldRun = $false
                    }
                }
                "monthly" {
                    $lastDay = [DateTime]::DaysInMonth($currentTime.Year, $currentTime.Month)
                    if ($currentTime.Day -ne $lastDay) {
                        $shouldRun = $false
                    }
                }
                "yearly" {
                    if (!($currentTime.Month -eq 12 -and $currentTime.Day -eq 31)) {
                        $shouldRun = $false
                    }
                }
                default { } # daily, секогаш дозволено
            }
			# ===== ПРОВЕРКА НА 'Day' ПОЛЕТО =====
            if ($shouldRun -and $cmdInfo.ContainsKey("Day") -and $cmdInfo.Day.Count -gt 0) {
                # Доколку денешниот датум не е во списокот Day, не извршувај
                $todayStr = $currentTime.ToString("yyyy-MM-dd")
                if (-not ($cmdInfo.Day -contains $todayStr)) {
                    $shouldRun = $false
                }
            }
			if ($shouldRun) {
            # --- 1) Прво извршување со толеранција од 1 минута ---
            if ($currentTime -ge $targetTime -and $currentTime -lt $targetTime.AddMinutes(1)) {
                if (-not $global:commandsExecuted.ContainsKey($execKey)) {
                    Invoke-CommandAndNotify $commandKey $cmdInfo.Cmd $timeStr
                    $global:commandsExecuted[$execKey] = $currentTime

                    # Ако има repeat, зачувај го и стартното време
                    if ($repeatMinutes -gt 0) {
                        $global:commandsExecuted["$execKey-Repeat"] = $currentTime
                    }
                }
            }
            # --- 2) Повторување со толеранција од 30 секунди ---
            if ($repeatMinutes -gt 0 -and $global:commandsExecuted.ContainsKey("$execKey-Repeat")) {
                $lastRun = $global:commandsExecuted["$execKey-Repeat"]
                $minutesSinceLast = ($currentTime - $lastRun).TotalMinutes
                $secondsSinceLast = ($currentTime - $lastRun).TotalSeconds

					if ($minutesSinceLast -ge $repeatMinutes -and $secondsSinceLast -lt (($repeatMinutes * 80) + 55)) {
						Invoke-CommandAndNotify $commandKey $cmdInfo.Cmd "$timeStr-Repeat"
						$global:commandsExecuted["$execKey-Repeat"] = $currentTime
					}
                }
			}
        }
    }
    # Чистење на стари записи од првично извршување
    $keysToRemove = @()
    foreach ($key in $global:commandsExecuted.Keys) {
        if ($key -notmatch "Repeat") {
            $timeStr = ($key -split '-')[ -1 ]
            $targetTime = [datetime]::Today.Add([timespan]::Parse($timeStr))
            if ($currentTime -ge $targetTime.AddMinutes(2)) {
                $keysToRemove += $key
            }
        }
    }
    foreach ($k in $keysToRemove) { $global:commandsExecuted.Remove($k) }
}

###############  Invoke-CommandAndNotify Automation Code
function Invoke-CommandAndNotify {
	param($commandKey, $cmdToRun, $timeStr)

	Write-Output "Executing command: $cmdToRun ($timeStr)"

	# Иницијализирај глобални хаштабли ако не постојат
	if ($null -eq $global:CommandToImagePath) { $global:CommandToImagePath = @{} }
	if ($null -eq $global:CommandToVideoPath) { $global:CommandToVideoPath = @{} }

	try {
		# Изврши ја командата
		& $cmdToRun

		$now = Get-Date
		$captionBase = "Automatic command: $commandKey`nTime: $($now.ToString('dd.MM.yyyy - HH:mm:ss'))`n" + ("-" * 18) + "`n* Autopilot | Start Menu - /start"

		# 📸 Ако има слика → прати ја
		if ($global:CommandToImagePath -and $global:CommandToImagePath.ContainsKey($cmdToRun)) {
			$imagePath = $global:CommandToImagePath[$cmdToRun]
			if (-not [string]::IsNullOrEmpty($imagePath) -and (Test-Path $imagePath)) {
				if ($imagePath -match '\.(png|jpg|jpeg|bmp|gif)$') {
					Send-TelegramPhoto -photoPath $imagePath -caption $captionBase
				}
			}
		}

		# 🎥 Ако има видео → прати го (без услов за Take-ScreenRecord)
		if ($global:CommandToVideoPath -and $global:CommandToVideoPath.ContainsKey($cmdToRun)) {
			$videoPath = $global:CommandToVideoPath[$cmdToRun]
			if (-not [string]::IsNullOrEmpty($videoPath) -and (Test-Path $videoPath)) {
				Send-TelegramVideo -videoPath $videoPath -caption $captionBase
			}
		}
	} catch {
		Write-Output ("Error executing {0}: {1}" -f $cmdToRun, $_)
	}
}
############### MONITORING CODE END ###############

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
    Send-TelegramMessage -message $status
}

# 💻 Start na Dashboard  (CPU, GPU, RAM, MB, Disk)
function Start-Das {
    $DasPath = "C:\Program Files (x86)\TRIGONE\Remote System Monitor Server\RemoteSystemMonitorServerControl.exe"
    # Proveri dali procesot (EXE) postoi
    $proc1 = Get-Process -Name RemoteSystemMonitorServerControl -ErrorAction SilentlyContinue
    # ✅ Ispravno ime na servisot
    $service = Get-Service -Name RemoteSystemMonitorService -ErrorAction SilentlyContinue
    # ✅ Proverka dali servisot postoi
    if ($null -eq $service) {
        Write-Log "Service 'RemoteSystemMonitorService' does not exist."
        Send-TelegramMessage -message "Service 'RemoteSystemMonitorService' does not exist."
        return
    }
    # Ako i EXE i servis se veќе aktivni
    if ($proc1 -and $service.Status -eq 'Running') {
        Write-Log "Dashboard is already running (exe and service). It will not be Restarted."
        Send-TelegramMessage -message "Dashboard is already Running (exe i servis)."
        return
    }
    # Flagovi za status na startuvanje
    $startedExe = $false
    $startedService = $false
    # Startuvaj exe ako ne e aktivno
    if (-not $proc1) {
        if (Test-Path $DasPath) {
            Start-Process -FilePath $DasPath
            Write-Log "Dashboard exe is Running."
            Send-TelegramMessage -message "Dashboard exe is Running."
            $startedExe = $true
        }
        else {
            Write-Log "Dashboard exe not found at: $DasPath"
            Send-TelegramMessage -message "Dashboard exe not found at: $DasPath"
        }
    }
    else {
        Write-Log "Dashboard exe was already active."
    }
    # Startuvaj servis ako ne e vo 'Running' sostojba
    if ($service.Status -ne 'Running') {
        try {
            Start-Service -Name RemoteSystemMonitorService
            Write-Log "Dashboard service is running."
            Send-TelegramMessage -message "Dashboard service is Running."
            $startedService = $true
        }
        catch {
            Write-Log "Failed to start the service: $($_.Exception.Message)"
            Send-TelegramMessage -message " Failed to start the service: $($_.Exception.Message)"
        }
    }
    else {
        Write-Log "Dashboard service was already Active."
    }
    # Ako nisto novo ne se startira, a nesto bese vekje aktivno - isprati info
    if (-not $startedExe -and -not $startedService) {
        if ($proc1) {
            Send-TelegramMessage -message "Dashboard exe was already Running."
        }
        if ($service.Status -eq 'Running') {
            Send-TelegramMessage -message "Dashboard service was already Running."
        }
    }
}

# 💻 Stop na Dashboard  (CPU, GPU, RAM, MB, Disk)
function Stop-Das {
    $stoppedSomething = $false
    # 1. Stopiraj procesot (exe)
    $proc = Get-Process -Name RemoteSystemMonitorServerControl -ErrorAction SilentlyContinue
    if ($proc) {
        $proc | Stop-Process -Force
        Write-Log "RemoteSystemMonitorServerControl process is Stopped."
        $stoppedSomething = $true
    }
    # 2. Stopiraj servisot ako postoi (ISPRAVENO IME)
    $service = Get-Service -Name RemoteSystemMonitorService -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        Stop-Service -Name RemoteSystemMonitorService -Force
        Write-Log "RemoteSystemMonitorService service is Stopped."
        $stoppedSomething = $true
    }
    # 3. Telegram poraka
    if ($stoppedSomething) {
        Send-TelegramMessage -message "Dashboard is Stopped (process and/or service)."
    } else {
        Write-Log "Dashboard was not Active (neither process nor service)." 
        Send-TelegramMessage -message "Dashboard was not Active."
    }
}

# 💻 Status na Dashboard  (CPU, GPU, RAM, MB, Disk)
function Status-Das {
    $msg = ""
    # Proces status
    $proc = Get-Process -Name RemoteSystemMonitorServerControl -ErrorAction SilentlyContinue
    if ($proc) {
        $msg += "`Process:  ACTIVE (PID: $($proc.Id))"
    } else {
        $msg += "`Process:  Not Active."
    }
    # Servis status (ISPRAVENO IME)
    $service = Get-Service -Name RemoteSystemMonitorService -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        $msg += "`Service:  ACTIVE (Status: $($service.Status))"
    } else {
        $msg += "`Service:  Not Active."
    }
    Send-TelegramMessage -message " Dashboard status:$msg"
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
        # Додавање на сите адаптери
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

# VLC player функции
function Play-VLC {
    # Затвори било кој активен VLC пред да пуштиш нов стрим
    Get-Process vlc -ErrorAction SilentlyContinue | Stop-Process -Force
    $url = $global:RadioStations[$global:CurrentStationIndex]
    Start-Process -FilePath "C:\Program Files\VideoLAN\VLC\vlc.exe" -ArgumentList $url
    return "Station started: $url"
}
function Stop-VLC {
    Get-Process vlc -ErrorAction SilentlyContinue | Stop-Process -Force
    return "VLC is closed."
}
function Next-Station {
    $global:CurrentStationIndex = ($global:CurrentStationIndex + 1) % $global:RadioStations.Count
    return Play-VLC
}
function Prev-Station {
    $global:CurrentStationIndex = ($global:CurrentStationIndex - 1)
    if ($global:CurrentStationIndex -lt 0) {
        $global:CurrentStationIndex = $global:RadioStations.Count - 1
    }
    return Play-VLC
}
function VLC-Status {
    if (Get-Process vlc -ErrorAction SilentlyContinue) {
        $url = $global:RadioStations[$global:CurrentStationIndex]
        return "VLC is running. Current station: $url"
    } else {
        return "VLC is not active."
    }
}
#################### end VLC Player ########################################

#  Network statistic meter
function Get-TrafficMonitorStats {
    param (
        [string]$FilePath = "C:\TrafficMonitor\history_traffic.dat"
    )
    if (-not (Test-Path $FilePath)) {
        return $null
    }
    $today = Get-Date
    $monthName = $today.ToString("MMMM", [System.Globalization.CultureInfo]::InvariantCulture)
    $year = $today.Year
    # Креирај иницијални клучеви со динамични имиња
    $results = [ordered]@{
        "Daily (24h)"        = @{ Download = 0.0; Upload = 0.0 }
        "Weekly (7d)"        = @{ Download = 0.0; Upload = 0.0 }
        "Monthly ($monthName)" = @{ Download = 0.0; Upload = 0.0 }
        "Yearly ($year)"     = @{ Download = 0.0; Upload = 0.0 }
    }
    foreach ($line in Get-Content $FilePath) {
        if ($line -notmatch "^\d{4}/\d{2}/\d{2}") { continue }

        $parts = $line -split "\s+"
        try {
            $date = [datetime]::ParseExact($parts[0], "yyyy/MM/dd", $null)
            $dl_ul = $parts[1] -split "/"
            $ul = [double]$dl_ul[0] / 1024
            $dl = [double]$dl_ul[1] / 1024
        } catch {
            continue
        }
        if ($date -ge $today.AddDays(-1)) {
            $results["Daily (24h)"].Download += $dl
            $results["Daily (24h)"].Upload += $ul
        }
        if ($date -ge $today.AddDays(-7)) {
            $results["Weekly (7d)"].Download += $dl
            $results["Weekly (7d)"].Upload += $ul
        }
        if (($date.Month -eq $today.Month) -and ($date.Year -eq $today.Year)) {
            $results["Monthly ($monthName)"].Download += $dl
            $results["Monthly ($monthName)"].Upload += $ul
        }
        if ($date -ge $today.AddDays(-365)) {
            $results["Yearly ($year)"].Download += $dl
            $results["Yearly ($year)"].Upload += $ul
        }
    }
    foreach ($key in $results.Keys) {
        $r = $results[$key]
        $r.Download = [math]::Round($r.Download, 2)
        $r.Upload   = [math]::Round($r.Upload, 2)
        $r.Total    = [math]::Round($r.Download + $r.Upload, 2)
    }

    return $results
}

# Temperatura CPU GPU MB DISK 
function Get-Temperatures {
    param(
        [string]$DllPath = "$PSScriptRoot\Dll\LibreHardwareMonitorLib.dll"
    )
    # Проверка дали е load DLL библиотеката
    if (-not ("LibreHardwareMonitor.Hardware.Computer" -as [type])) {
        try {
            Add-Type -Path $DllPath
        } catch {
            return "Error: Cannot load DLL file at the path $DllPath."
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

    # Редослед на прикажување
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
        $output += "`nStatus: Cannot measure Motherboard temperature.`n"
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

# Alarm za CPU GPU MB DISK RAM Temp Load
function Check-TemperatureAndNotify {
    $tempData = Get-Temperatures | Out-String

    # ==== Флагови и списоци ====
    $cpuExceeded = @(); $diskExceeded = @(); $mbExceeded = @(); $gpuExceeded = @()
    $cpuFound = $false; $diskFound = $false; $mbFound = $false; $gpuFound = $false
    $criticalTriggered = $false
    $criticalReasons = @()
    $msg = ""
	
    # ==== Парсирање температури ====
    foreach ($line in $tempData -split "`n") {
        # CPU
        if ($line -match "CPU.*:\s*([\d\.]+)") {
        $cpuFound = $true
        $temp = [double]$matches[1]
        # Проверка дали температурата го надминува обичниот алармски лимит
        if ($temp -gt $cpuLimit) {
            $cpuExceeded += $line
        }
        # Проверка дали температурата го надминува критичниот алармски лимит
        if ($temp -gt $cpuTempCriticalLimit) {
            $criticalTriggered = $true
            $criticalReasons += "CPU: $($temp)°C (Limit: $($cpuTempCriticalLimit) °C)"
           }
        }
		# Disk (isklucuvaj CPU/GPU/Mainboard liniji)
        elseif ($line -match "^(?!.*(CPU|GPU|Mainboard)).*Temperature:\s*([\d\.]+)") {
            $diskFound = $true
            $temp = [double]$matches[2]
            if ($line -match "^(.+?):") { $name = $matches[1].Trim() } else { $name = "Disk" }
            if ($temp -gt $diskLimit) { $diskExceeded += "${name}: $($temp)°C" }
            if ($temp -gt $diskTempCriticalLimit) {
                $criticalTriggered = $true
                $criticalReasons += "Disk ${name}: $($temp)°C (Limit: $($diskTempCriticalLimit) °C)"
            }
        }
		# Maticna
        elseif ($line -match "(ASUS|Mainboard).*:\s*([\d\.]+)") {
            $mbFound = $true
            $temp = [double]$matches[2]
            if ($line -match "^(.+?):") { $name = $matches[1].Trim() } else { $name = "Motherboard" }
            if ($temp -gt $mbLimit) { $mbExceeded += "${name}: $($temp)°C" }
            if ($temp -gt $mbTempCriticalLimit) {
                $criticalTriggered = $true
                $criticalReasons += "${name}: $($temp)°C (Limit: $($mbTempCriticalLimit) °C)"
            }
        }
		# GPU
        elseif ($line -match "(GPU|NVIDIA|Radeon).*:\s*([\d\.]+)") {
            $gpuFound = $true
            $temp = [double]$matches[2]
            if ($line -match "^(.+?):") { $name = $matches[1].Trim() } else { $name = "GPU" }
            if ($temp -gt $gpuLimit) { $gpuExceeded += "${name}: $($temp)°C" }
            if ($temp -gt $gpuTempCriticalLimit) {
                $criticalTriggered = $true
                $criticalReasons += "${name}: $($temp)°C (Limit: $($gpuTempCriticalLimit) °C)"
            }
        }
    }

# ==== RAM & CPU Load ==== 
    # Uzimanje trenutnog RAM Usage
    $ramUsage = (Get-WmiObject Win32_OperatingSystem).TotalVisibleMemorySize - (Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory
    $ramUsagePercent = [math]::Round(($ramUsage / (Get-WmiObject Win32_OperatingSystem).TotalVisibleMemorySize) * 100, 2)

    # Uzimanje trenutnog CPU Load
    $cpuLoad = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue

    # Alarm vrednosti (bez limiti u običnom alarmu, samo brojke)
    if ($ramUsagePercent -gt $ramUsageAlarmLimit) {
        $msg += " RAM Load: $($ramUsagePercent)%`n"
    }
    if ($cpuLoad -gt $cpuLoadAlarmLimit) {
        $msg += " CPU Load: $([math]::Round($cpuLoad,2))%`n"
    }

    # Kritični alarmi (sa limitima samo ovde)
    if ($ramUsagePercent -gt $ramUsageCriticalLimit) {
        $criticalTriggered = $true
        $criticalReasons += "RAM Load: $($ramUsagePercent)% (Limit: $ramUsageCriticalLimit%)"
    }
    if ($cpuLoad -gt $cpuLoadCriticalLimit) {
        $criticalTriggered = $true
        $criticalReasons += "CPU Load: $([math]::Round($cpuLoad,2))% (Limit: $cpuLoadCriticalLimit%)"
    }
	
	# Vreme na izvrsuvanje na Alarmite
	 $alarmTime = Get-Date -Format 'HH:mm:ss dd-MM'
	 
    # ==== Обична аларм порака (без критични лимити) ====
    if ($cpuExceeded -or $diskExceeded -or $mbExceeded -or $gpuExceeded -or $msg) {
        $msg = "  **ALARM: Temperature or Load Exceeded!($alarmTime)`n`n" + $msg

        if ($cpuExceeded) { $msg += " CPU Temp:`n" + ($cpuExceeded -join "`n") + "`n`n" }
        if ($diskExceeded) { $msg += " Disk Temp:`n" + ($diskExceeded -join "`n") + "`n`n" }
        if ($mbExceeded) { $msg += " Motherboard Temp:`n" + ($mbExceeded -join "`n") + "`n`n" }
        if ($gpuExceeded) { $msg += " GPU Temp:`n" + ($gpuExceeded -join "`n") + "`n`n" }

        if (-not $cpuFound) { $msg += " CPU temperature is not being measured.`n" }
        if (-not $diskFound) { $msg += " Disk temperature is not being measured.`n" }
        if (-not $mbFound) { $msg += " Motherboard temperature is not being measured.`n" }
        if (-not $gpuFound) { $msg += " GPU temperature is not being measured.`n" }
    }

# ==== Критичен аларм (само тука ги прикажуваме критичните лимити) ====
if ($criticalTriggered) {
    $critMsg = "`n--- **SECURITY ALARM** ---($alarmTime)`n"

# Проверка на времето
$currentHour = (Get-Date).Hour
$actionMessage = ""

# Poverka za Restart ili Shutdown
$shouldRestart = $false
$shouldShutdown = $false

# Ако е помеѓу 11:00 и 13:00, изврши рестарт
if ($currentHour -ge 11 -and $currentHour -lt 13) { #(($currentHour -ge 15 -and $currentHour -lt 23) -or ($currentHour -ge 23 -and $currentHour -lt 24) -or ($currentHour -ge 0 -and $currentHour -lt 6)) Full Code 
    $actionMessage = "System is *RESTART* due to the following Exceedances:`n`n"
	$shouldRestart = $true
} 
# Ако е помеѓу 18:00 и 20:00, изврши рестарт
elseif ($currentHour -ge 18 -and $currentHour -lt 20) {
    $actionMessage = "System is *RESTART* due to the following Exceedances:`n`n"
	$shouldRestart = $true
}
# Ако е помеѓу 22:00 и 23:00, изврши рестарт
elseif ($currentHour -ge 22 -and $currentHour -lt 23) {
    $actionMessage = "System is *RESTART* due to the following Exceedances:`n`n"
	$shouldRestart = $true
} 
# Ако е помеѓу 00:00 и 24:00, изврши исклучување
else {
    $actionMessage = "System is *SHUTDOWN* due to the following Exceedances:`n`n"
	$shouldShutdown = $true
}
# Додавање на соодветното известување за рестарт или исклучување
$critMsg += $actionMessage

    # Иницијализација на групи со ASCII keys
    $groups = @{
        "CPU" = @()
        "Disk" = @()
        "Motherboard" = @()
        "GPU" = @()
        "RAM" = @()
        "CPU Load" = @()
        "Others" = @()
    }

    foreach ($reason in $criticalReasons) {
        if ($reason -match "^CPU Load\b") {
            $groups["CPU Load"] += $reason
        } elseif ($reason -match "^CPU\b") {
            $groups["CPU"] += $reason
        } elseif ($reason -match "^Disk") {
            $groups["Disk"] += $reason
        } elseif ($reason -match "Motherboard") {
            $groups["Motherboard"] += $reason
        } elseif ($reason -match "GPU") {
            $groups["GPU"] += $reason
        } elseif ($reason -match "^RAM") {
            $groups["RAM"] += $reason
        } else {
            $groups["Others"] += $reason
        }
    }

    foreach ($key in $groups.Keys) {
        if ($groups[$key].Count -gt 0) {
            $critMsg += "${key}:`n"
            foreach ($item in $groups[$key]) {
                $critMsg += " * $item`n"
            }
        }
    }

    # Запиши во текстуална датотека (предполагам $logPath е валиден пат)
    $critLogEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - SECURITY ALARM activated:`n" + ($criticalReasons -join "`n") + "`n"
    Add-Content -Path $logPath -Value $critLogEntry
    # Пауза 2 секунди за да се осигура запишување на лог
    Start-Sleep -Seconds 2
    Write-Log "The system would be Restarted or Shut down at this moment."
    
    if ($msg) {
        $msg += "`n" + $critMsg
    } else {
        $msg = $critMsg
    }

    Send-TelegramMessage -message $msg
    Start-Sleep -Seconds 5
    # === Изврши реална команда ===
    if ($shouldRestart) {
       Invoke-Expression $restartCmd
    } elseif ($shouldShutdown) {
       Invoke-Expression $shutdownCmd
    }
}
    elseif ($msg) {
    # Ако има само аларм порака, испрати ја
    Send-TelegramMessage -message $msg
    }
}  

# LOAD STATISTIC FROM LibreHardwareMonitiorLib.dll
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
    $hardwareList = @()
    foreach ($hardware in $computer.Hardware) {
        $hardware.Update()
        $loadSensors = $hardware.Sensors | Where-Object { $_.SensorType -eq "Load" }
        if ($loadSensors.Count -gt 0) {
            $text = "*$($hardware.Name)* - $($hardware.HardwareType)`n"
            foreach ($sensor in $loadSensors) {
                $value = if ($sensor.Value -ne $null) { "{0:N1}%" -f $sensor.Value } else { "N/A" }
                $text += " - $($sensor.Name): $value`n"
            }
            $text += "`n"
            $hardwareList += $text
        }
    }
    $computer.Close()
    # Telegram limit = 4096
    $maxLength = 4000
    $messages = @()
    $currentMessage = "*LibreHardwareMonitor Load:*`n`n"
    foreach ($item in $hardwareList) {
        if (($currentMessage.Length + $item.Length) -gt $maxLength) {
            $messages += $currentMessage
            $currentMessage = ""
        }
        $currentMessage += $item
    }
    if ($currentMessage.Length -gt 0) {
        $messages += $currentMessage
    }
    return $messages
}

# DATA STATISTIC FROM LibreHardwareMonitiorLib.dll
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
    $hardwareList = @()
    foreach ($hardware in $computer.Hardware) {
        $hardware.Update()
        $otherSensors = $hardware.Sensors | Where-Object { $_.SensorType -ne "Load" }
        if ($otherSensors.Count -gt 0) {
            $text = "*$($hardware.Name)* - $($hardware.HardwareType)`n"
            foreach ($sensor in $otherSensors) {
                $value = if ($sensor.Value -ne $null) { "{0:N2}" -f $sensor.Value } else { "N/A" }
                $text += " - $($sensor.SensorType): $($sensor.Name) = $value`n"
            }
            $text += "`n"
            $hardwareList += $text
        }
    }
    $computer.Close()
    # Telegram limit = 4096
    $maxLength = 4000
    $messages = @()
    $currentMessage = "*LibreHardwareMonitor Data:*`n`n"
    foreach ($item in $hardwareList) {
        if (($currentMessage.Length + $item.Length) -gt $maxLength) {
            $messages += $currentMessage
            $currentMessage = ""
        }
        $currentMessage += $item
    }
    if ($currentMessage.Length -gt 0) {
        $messages += $currentMessage
    }
    return $messages
}

# TASK Enabled Disabled Status
function Manage-PiScheduledTasks {
    param(
        [ValidateSet("enable", "disable", "status")]
        [string]$Action
    )
    try {
        # AutoPilot scheduled task (прилагоди ако името/патеката се различни)
        $taskName = "AutoPilot"
        $taskPath = "\"
        $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if (-not $task) {
            return " *Auto-Start on AutoPilot does not exist (scheduled task is not created)."
        }
        switch ($Action) {
            "disable" {
                Disable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue | Out-Null
                return " *Auto-Start for AutoPilot task e Disabled (Turned Off)."
            }
            "enable" {
                Enable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue | Out-Null
                return " *Auto-Start for AutoPilot task e Enabled (Turned On)."
            }
            "status" {
                $state = if ($task.State -eq "Disabled") { "Disabled (Turned Off)" } else { "Enabled (Turned On)" }
                return " *Auto-Start for AutoPilot task status: $state."
            }
        }
    } catch {
        return " Error in processing AutoPilot scheduled task: $_"
    }
}

# 📝 Funkcija za prikaz na log AUTOPILOT (20 posledni liniji)
function Autopilot-Log {
    $logDate = Get-Date -Format 'yyyy-MM-dd'
    $logFile = "$Global:logFolder\autopilot_$logDate.txt"

    if (Test-Path $logFile) {
        $logLines = Get-Content -Path $logFile -Tail 20
        $logContent = $logLines -join "`n"
        Send-TelegramMessage -message "Last 20 lines from the AUTOPILOT log:`n$logContent"
    } else {
        Send-TelegramMessage -message "The AUTOPILOT log file for today does not exist."
    }
}

# 📝 Funkcija za prikaz na log MONITORING (20 posledni liniji)
function Monitoring-Log {
    $monitoringDate = Get-Date -Format 'yyyy-MM-dd'
    $monitoringLogFile = "$Global:monitoringLogsFolder\monitoring_$monitoringDate.txt"

    if (Test-Path $monitoringLogFile) {
        $logLines = Get-Content -Path $monitoringLogFile -Tail 20
        $logContent = $logLines -join "`n"
        Send-TelegramMessage -message "Last 20 lines from the MONITORING log:`n$logContent"
    } else {
        Send-TelegramMessage -message "The MONITORING log file for today does not exist."
    }
}

# 📝 Funkcija za prikaz na log DATA (20 posledni liniji)
function Data-Log {
    $dataDate = Get-Date -Format 'yyyy-MM-dd'
    $dataLogFile = Join-Path $Global:dataLogFolder "audit_$dataDate.txt"

    if (Test-Path -LiteralPath $dataLogFile) {
        $logLines = Get-Content -Path $dataLogFile -Tail 20
        $logContent = $logLines -join "`n"
        Send-TelegramMessage -message "Last 20 lines from the DATA log:`n$logContent"
    } else {
        Write-Host "The file was not found!"
        Send-TelegramMessage -message "The DATA log file for today does not exist."
    }
}

# 📝 Funkcija za prikaz na log UPDATER (35 posledni liniji)
function Update-Log {
    $logFile = $Global:updaterLogFile  #  Updater.log

    if (Test-Path -LiteralPath $logFile) {
        $logLines = Get-Content -Path $logFile -Tail 35
        $logContent = $logLines -join "`n"
        Send-TelegramMessage -message "Last 35 lines from the UPDATER log:`n$logContent"
    } else {
        Write-Host "The UPDATER log file was not found!"
        Send-TelegramMessage -message "The Updater log file does not exist."
    }
}

##### GRAPHS LOAD TEMP DISK #####
function Send-Graph {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Load","Temp","Disk","Table")]
        [string]$GraphType,   # Load, Temp, Disk, Table

        [Parameter(Mandatory)]
        [ValidateSet("Day","Week","Month","Year","All")]  # Додадено "All"
        [string]$Period       # Day, Week, Month, Year, All
    )
    # Динамично формирање на името на функцијата, пример: Generate-LoadGraph-Day или Generate-TableGraph-Week
    $functionName = "Generate-$GraphType" + "Graph-" + $Period
    Write-Host "Calling function: $functionName"

    # Проверка дали постои таа функција
    if (-not (Get-Command $functionName -ErrorAction SilentlyContinue)) {
        $msg = " Function '$functionName' does not exist."
        Write-Host $msg
        Send-TelegramMessage -message $msg
        return
    }
    # Повик на функцијата за генерирање графикон или табела
    try {
        $result = & $functionName
    }
    catch {
        $msg = " Error during execution of '$functionName': $($_.Exception.Message)"
        Write-Host $msg
        Send-TelegramMessage -message $msg
        return
    }
    # Подготовка на caption за Telegram
    $now = Get-Date
    $periodInfo = $now.ToString("dddd, dd MMMM yyyy", [System.Globalization.CultureInfo]::GetCultureInfo("en-EN"))
    $caption = "Command: /$($GraphType.ToLower())_$($Period.ToLower())`n" +
               "Period: $periodInfo`nTime: $($now.ToString('HH:mm:ss'))" +
               "`n" + ("-" * 18) + "`n* Autopilot | Start Menu - /start"

    # Определи патека до PNG фајлот (графикон или табела)
    if ($result -is [string]) {
        $photoPath = $result
    }
    elseif ($result -is [hashtable]) {
        $photoPath = $null
        foreach ($key in $result.Keys) {
            if ($key -match 'Graph$' -or $key -match 'Table$' -or $key -match 'Output$') {
                $photoPath = $result[$key]
                break
            }
        }
    }
    else {
        $photoPath = $null
    }
    # Проверка дали PNG фајлот постои
    if (-not $photoPath -or -not (Test-Path $photoPath)) {
        $msg = " CSV file not found for '$GraphType' for the period '$Period'."
        Write-Host $msg
        Send-TelegramMessage -message $msg
        return
    }
    # Испрати PNG (табела или графикон)
    Write-Host " Image sent: $photoPath"
    Send-TelegramPhoto -photoPath $photoPath -caption $caption
}

# ALL COMMANDS #
function Show-HelpMenu {
    $msg = @"
* START MENU  List of commands by category:*

 *Defender commands:*
/def1  Stop Real-Time 
/def2  Start Real-Time 
/def3  Status Real-Time  
/def4  Tamper Protection  
/def5  Start Tamper Protection  

 *Pi commands:*
/pi1  Start Pi Node
/pi2  Status Pi Node 
/pi3  Stop Pi Node  
/pi4  Restart Pi Node 
/pi5  Disable Pi Node 
/pi6  Clear Pi Node Cache

 *Docker commands:*
/docker1  Star Pi Node  
/docker2  Stop Pi Node  
/docker3  Restart Pi Node  
/docker4  Status Pi Node 
/docker5  Start Docker 
/docker6  Restart Docker
/docker7  Stop Docker
/docker8  Status Docker
/docker9  Clear Cache Docker 
/docker10  Clear Temp Folder

 *Cleaner commands:*
/cleaner1  Status Hibernation 
/cleaner2  Stop Hibernation 
/cleaner3  Clear Windows Temp 
/cleaner4  Clear AppData Temp
/cleaner5  Clear SoftwareDistribution 
/cleaner6  Clear Prefetch
/cleaner7  Disk Cleanup  
/cleaner8  Clear Temp for All Users 
/cleaner9  Clear Temp for User 
/cleaner10  Total Clean 
/cleaner11  Status 
/cleaner12  Clean Registry  

 *Network commands:*
/net1  Connect to WiFi 1
/net2  Connect to WiFi 2
/net3  TASK (Switch WiFi 1 to WiFi 2)
/net4  TASK (Switch WiFi 2 to WiFi 1)
/net5  Show TASK
/net6  Delete TASK
/net7  Network Log File
/net8  Network Status
/net9  Network Restart

 *Net Traffic commands:*
/net_monitoring1  Net Monitoring Start 
/net_monitoring2  Net Monitoring Stop
/net_monitoring3  Net Monitoring Status
/net_monitoring4  Net CSV File
/net_monitoring5  Net Traffic Statistic
/net_monitoring6  Net Traffic Log File
/net_monitoring7  Live Panel Open
/net_monitoring8  Live Panel Exit

 *System commands:*
/system_status  System Status  
/ping  Ping Test
/autopilot_log  Autopilot Log File
/update_log Autopilot Update Log File
/temp  Temperature Cpu Gpu Disk MB
/hardware_load  LHM Load
/hardware_data  LHM Data 
/monitor_open  Dashboard Open
/monitor_exit  Dashboard Exit
/commands_list  All Commands List
/pause  Pause Script
/resume  Resume Script
/stop  Stop Script
/status  Status Script
/reset  Restart Script
/hide  Hide Script 
/show  Show Script
/visible_status  Display Status
/autostart_enable  Auto-Start Enable
/autostart_disable  Auto-Start Disable
/autostart_status  Auto-Start Status
/restart  Restart PC
/shutdown  Shutdown PC 

 *Recording commands:*
/screen  Desktop Screenshot
/record  Desktop Recording
/rec_start  Start Recording
/rec_stop  Stop Recording 

 *Camera commands:*
/cam_start  Start Camera 
/cam_stop  Stop Camera 
/data  Video Storage
/data_log  Data Log File

 *Monitoring commands:*
/monitoring_start  Start Monitoring
/monitoring_stop  Stop Monitoring
/monitoring_status  Status Monitoring
/monitoring_log  Monitoring Log File

 *Graph Load commands:*
/load_day  Load Day 
/load_week  Load Week   
/load_month  Load Month
/load_year  Load Year 
/load_all  Load All 

 *Graph Temperature commands:*
/temp_day  Temperature Day        
/temp_week  Temperature Week       
/temp_month  Temperature Month     
/temp_year  Temperature Year
/temp_all  Temperature All 

 *Graph Disk Load commands:*
/disk_day  Disk Load Day
/disk_week  Disk Load Week
/disk_month  Disk Load Month
/disk_year  Disk Load Year
/disk_all  Disk Load All 

 *Table Net Traffic commands:*
/table_day  Net Traffic Day
/table_week  Net Traffic Week
/table_month  Net Traffic Month
/table_year  Net Traffic Year
/table_all  Net Traffic All 

 *Third-party App commands:*
/teamviewer_start  Start TW
/teamviewer_stop  Stop TW 
/teamviewer_status  Status TW
/das_start  Start Dashboard
/das_stop  Stop Dashboard 
/das_status  Status Dashboard
/monitor_start  Start
/monitor_stop  Stop 
/monitor_status  Status 
/netusage  Network Usage 

 *VLC commands:*
/vlc_play  Play Vlc
/vlc_stop  Stop Vlc
/vlc_next  Next 
/vlc_prev  Prew
/vlc_status  Status Vlc

"@
    return $msg
}
# *Related bots:* [PC 1] (https://t.me/1_Bot) [PC 2] (https://t.me/2_Bot)  
 
# Reset/Stop Show/Hide Script - AutoPilot
$StopFlagFile = Join-Path $PSScriptRoot "Autopilot_Data\Traffic_Logs\TrafficMonitor_Stop.flag"
$Global:monitorLogFolder = "$PSScriptRoot\Autopilot_Data\Traffic_Logs"
if (-not (Test-Path $Global:monitorLogFolder)) { New-Item $Global:monitorLogFolder -ItemType Directory | Out-Null }

$currentDate = Get-Date -Format 'yyyy-MM-dd'
$Global:monitorLogFile = Join-Path $Global:monitorLogFolder "traffic_$currentDate.txt"
if (-not (Test-Path $Global:monitorLogFile)) { New-Item $Global:monitorLogFile -ItemType File | Out-Null }

function Stop-WorkerScripts {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
	# STOP TrafficMonitorWorker.ps1
    $trafficProc = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -like "*TrafficMonitorWorker.ps1*"
    }
    if ($trafficProc) {
        foreach ($p in $trafficProc) {
            try { Stop-Process -Id $p.ProcessId -Force } catch {}
        }
        $stopFlagFolder = Split-Path $StopFlagFile
        if (-not (Test-Path $stopFlagFolder)) {
            New-Item -Path $stopFlagFolder -ItemType Directory | Out-Null
        }
        Set-Content -Path $StopFlagFile -Value $timestamp -Encoding UTF8
		Add-Content -Path $Global:monitorLogFile -Value "[${timestamp}] TrafficMonitorWorker IS STOPPED due to AutoPilot Restart/Stop.. Time: $timestamp"
    }
	# STOP SystemMonitorWorker.ps1
    $systemProc = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq "powershell.exe" -and $_.CommandLine -like "*SystemMonitorWorker.ps1*"
    }
    if ($systemProc) {
        foreach ($p in $systemProc) {
            try { Stop-Process -Id $p.ProcessId -Force } catch {}
        }
        $monitoringStopFlag = Join-Path $Global:monitoringLogsFolder "monitoring_stop.flag"
        Set-Content -Path $monitoringStopFlag -Value $timestamp -Encoding UTF8
        Write-MonitoringLog "SystemMonitorWorker IS STOPPED due to AutoPilot Restart/Stop. Time: $timestamp"
    }
    # STOP Camera.exe 
    $cameraExePath = Join-Path $PSScriptRoot "Camera.exe"
    if (Test-Path $cameraExePath) {
        $cameraProcs = Get-Process -Name "Camera" -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $cameraExePath }
        foreach ($cam in $cameraProcs) {
            try {
                Stop-Process -Id $cam.Id -Force
                Add-Content -Path $Global:monitorLogFile -Value "[${timestamp}] Camera.exe process $($cam.Id) is STOPPED."
            } catch {}
        }
    }
}

# ⚙️ Funkcija za procesiranje na manuelni Telegram komandi
function Process-ManualCommands {
    param(
        [ref]$lastUpdateId
    )

    if (-not $global:confirmationRequests) {
        $global:confirmationRequests = @{}
    }

    $updates = Get-Updates -offset ($lastUpdateId.Value + 1)
    foreach ($update in $updates) {
        if (-not ($update.message -and $update.message.text)) {
            continue
        }
        # 🛡️ SECURITY GATE 
		# Private chat
		if ($update.message.chat.type -ne "private") {
			Write-Log "AUDIT: Message from non-private chat | ChatType=$($update.message.chat.type) | ChatId=$($update.message.chat.id)"
			$lastUpdateId.Value = $update.update_id
			continue
		}
		# Chat OWNER
		$userId = $update.message.from.id
		if ($userId -ne $OwnerId) {

		$chatId = $update.message.chat.id
		$now = Get-Date
		# 📜 AUDIT LOG 
		Write-Log "AUDIT: Unauthorized Access | UserId=$userId | ChatId=$chatId | Text='$($update.message.text)'"
		# 🔔 ALARM (rate-limited)
		if (
			-not $global:LastAuditAlert.ContainsKey($userId) -or
			($now - $global:LastAuditAlert[$userId]).TotalMinutes -ge 3
		) {
			Send-TelegramMessage -message @"
 *SECURITY ALERT*
Unauthorized Access Attempt!

 UserId: $userId
 ChatId: $chatId
 Message: '$($update.message.text)'
 Time: $now
"@
		$global:LastAuditAlert[$userId] = $now
		}
		# 🚫 Block
		Send-TelegramMessage -message "Access to Chat is Forbidden."
		$lastUpdateId.Value = $update.update_id
		continue
		}
            $text = $update.message.text.Trim()
            $chatId = $update.message.chat.id

            # ✅ Proveri dali se ocekuva potvrda za kriticna komanda
            if ($confirmationRequests.ContainsKey($chatId)) {
                switch -CaseSensitive ($text) {
                    "Y" {
                        switch ($confirmationRequests[$chatId]) {
                            "restart" {
                                Send-TelegramMessage -message "The System is Restarting..."
                                Restart-Computer -Force
                            }
                            "shutdown" {
                                Send-TelegramMessage -message "The System is Shutting Down..."
                                Stop-Computer -Force
                            }
                            "stop" {
                                Send-TelegramMessage -message "The AutoPilot is Stopped."
								Stop-WorkerScripts
                                $global:scriptStopped = $true
                            }
							"reset" {
								Send-TelegramMessage -message "The AutoPilot is Restarting..."
								Stop-WorkerScripts
								Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
								Stop-Process -Id $PID
							}
							"show" {
                                $isHidden = (Get-Process -Id $PID).MainWindowHandle -eq 0
                                if (-not $isHidden) {
                                Send-TelegramMessage -message "The AutoPilot Cmd is already *VISIBLE* (visible on the desktop). No restart is needed."
                                } else {
                                Send-TelegramMessage "Restarting AutoPilot Cmd in *visible* mode..."
								Stop-WorkerScripts
                                $autoPilotLnk = Join-Path $PSScriptRoot "Shortcuts\Autopilot.lnk"
								if (Test-Path $autoPilotLnk) {
									Start-Process -WindowStyle Normal -FilePath $autoPilotLnk
								}
								else {
									Send-TelegramMessage "Error: Autopilot.lnk was not found!"
								}
								Stop-Process -Id $PID
							}
							}
                            "hide" {
                                $isHidden = (Get-Process -Id $PID).MainWindowHandle -eq 0
                                if ($isHidden) {
                                Send-TelegramMessage -message "The AutoPilot Cmd is already in *HIDDEN* mode (invisible). No restart is needed."
                                } else {
                                Send-TelegramMessage "Restarting AutoPilot Cmd in *hidden* mode..."
								Stop-WorkerScripts
                                Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
                                Stop-Process -Id $PID
                                }
                            }
                        }
                    }
                    "N" {
                        Send-TelegramMessage -message "The Action has been Canceled."
                    }
                    default {
                        Send-TelegramMessage -message "Invalid response. Reply with Y or N."
                    }
                }

                # ✅ Azhuriraj updateId za da ne se povtoruva istiot update
                $lastUpdateId.Value = $update.update_id
                $confirmationRequests.Remove($chatId)
                continue  # 🛑 Prekini ciklusot za da ne odi ponatamu
            }

            # ✅ Standardna obrabotka na komandi
            if ($ManualCommands.ContainsKey($text)) {
                $cmdInfo = $ManualCommands[$text]

                if ($cmdInfo.ContainsKey("Path")) {
					$scriptName = Split-Path $cmdInfo.Path -Leaf
                    Write-Log "Manual command applied $text - Invocation $($cmdInfo.Path) with argument $($cmdInfo.Cmd)"
                    Send-TelegramMessage -message "Command applied $text - Executing script ($scriptName):"
            # Avtomatski RESTART SHUTDOWN RESTART-SCRIPT ako ne se izvrsi nekoja komanda !!!
            # Start skriptata vo background kako Job
			$job = Start-Job -ScriptBlock {
				param($path, $cmd)
				& "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -File $path -AutoRunOps $cmd -Silent
			} -ArgumentList $cmdInfo.Path, $cmdInfo.Cmd

			$timeout = 355 # vo sekundi vremeto potrebno za da se izvrsi KOMANDA (Auto Manuelna).
			$jobCompleted = $job | Wait-Job -Timeout $timeout

			if ($jobCompleted) {
				try {
					$output = Receive-Job -Job $job
					Write-Log "Result: $output"
					Send-TelegramMessage -message "Result from $($text) ($scriptName):`n$output"
				} catch {
					Write-Log "Error retrieving result from job: $_"
					Send-TelegramMessage -message "Error executing command $text ($scriptName)."
				}
			} 
			    else {
			# Timeout - komanda se zaglavi
			$currentTime = Get-Date -Format "HH:mm"
			$hour = (Get-Date).Hour
			Write-Log "Command $text ($scriptName) is stuck. Action is being executed according to schedule ($currentTime)."

			# 1. RESTART SCRIPT  Avtomatski restart na skripta vo 17:00 - 00:00
			if (($hour -ge 07 -and $hour -lt 09) -or ($hour -ge 11 -and $hour -lt 12) -or ($hour -ge 15 -and $hour -lt 19)) {
				Write-Log "(($hour -ge 07 -and $hour -lt 09) -or ($hour -ge 11 -and $hour -lt 12) -or ($hour -ge 15 -and $hour -lt 19)): RESTART of AutoPilot"
				Send-TelegramMessage -message "Command $text ($scriptName) is stuck. AutoPilot is Restarting..."
				Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
				Stop-WorkerScripts
				Stop-Process -Id $PID
			}
			
			# 2. Vo site drugi slucai, pobaraj odgovor
			Send-TelegramMessage -message "Command $text ($scriptName) is stuck. Should an automatic Restart or Shutdown of the PC be executed? Reply with 'Y' or 'N' within the next 5 minutes… Choosing 'N' will cancel the automatic command (Restart or Shutdown) and only the AutoPilot will be Restarted."
			
			# Cekaj odgovor do 5 minuti (300 sekundi)
			$startTime = Get-Date
			$response = $null
			
			do {
				Start-Sleep -Seconds 5
				try {
					$updates = Get-Updates
					foreach ($update in $updates) {
						$msgText = ($update.message.text).Trim()  
						if ($msgText -cmatch '^[YN]$') {          
							$response = $msgText
							break
						} else {
							Send-TelegramMessage -message "Invalid response. Reply with Y or N."
						}
					}
				} catch {
					Write-Log "Error checking Telegram response: $_"
				}
            } 

            while (([datetime]::Now - $startTime).TotalSeconds -lt 300 -and -not $response)

			# Ako nema odgovor vo 5 minuti, default 'Y'
			if (-not $response) {
				$response = 'Y'
				Write-Log "No response within the time limit. Defaulting to 'Y'"
			}
			
			# Odluči akcija spored odgovor
			if ($response -eq 'Y') {
				# RESTART PC 09:00 - 10:00, 13:00 - 15:00, 21:00 - 23:00
				if (($hour -ge 09 -and $hour -lt 10) -or ($hour -ge 13 -and $hour -lt 15) -or ($hour -ge 21 -and $hour -lt 23)) {
					Write-Log "(($hour -ge 09 -and $hour -lt 10) -or ($hour -ge 13 -and $hour -lt 15) -or ($hour -ge 21 -and $hour -lt 23)): RESTART of PC"
					Send-TelegramMessage -message "PC RESTART is being Executed..."
					Invoke-Expression $restartCmd
				}
				# SHUTDOWN PC за сите други опсези
				elseif (($hour -ge 00 -and $hour -lt 24)) { #(($hour -ge 15 -and $hour -lt 23) -or ($hour -ge 23 -and $hour -lt 24) -or ($hour -ge 0 -and $hour -lt 6)) Full Code 
					Write-Log "00:00 - 24:00: SHUTDOWN of PC"
					Send-TelegramMessage -message "PC SHUTDOWN is being Executed..."
					Invoke-Expression $shutdownCmd
				}
				else {
					Write-Log "Unknown time range. No action is taken."
					Send-TelegramMessage -message "Unknown time range. No action is taken."
				}
			}
			
			# DEFAULT RESTART SCRIPT
			elseif ($response -eq 'N') {
				Write-Log "The User replied 'N'. Only AutoPilot is Restarting."
				Send-TelegramMessage -message "The Automatic Command is canceled. Only the AutoPilot is Restarting..."
				Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
				Stop-WorkerScripts
				Stop-Process -Id $PID
			}
           
		    # Resetiraj Telegram offset
            try {
                $lastUpdates = Get-Updates
                if ($lastUpdates.Count -gt 0) {
                    $maxUpdateId = ($lastUpdates | Sort-Object update_id -Descending | Select-Object -First 1).update_id
                    $nextOffset = $maxUpdateId + 1
                    $resetUri = "https://api.telegram.org/bot$telegramBotToken/getUpdates?offset=$nextOffset"
                    Invoke-RestMethod -Uri $resetUri -Method Get -ErrorAction SilentlyContinue
                    Write-Log "Telegram offset reset to $nextOffset"
                }
            } catch {
                Write-Log "Failed attempt to reset Telegram offset: $_"
					}
			}	
                } else {
                    switch ($cmdInfo.Cmd) {
                        "Start-TeamViewer" {
							$teamViewerPath = "C:\Program Files\TeamViewer\TeamViewer.exe"
							if (Test-Path $teamViewerPath) {
								Start-Process -FilePath $teamViewerPath -ErrorAction SilentlyContinue
								Write-Host "TeamViewer is Started."
								Send-TelegramMessage -message "TeamViewer is Started."
							}
							else {
								Write-Host "TeamViewer is NOT Installed."
								Send-TelegramMessage -message "TeamViewer is NOT Installed."
							}
						}
                        "Stop-TeamViewer" {
                            Get-Process -Name TeamViewer -ErrorAction SilentlyContinue | Stop-Process -Force
                            Send-TelegramMessage -message "TeamViewer is Closed."
                        }
                        "Status-TeamViewer" {
                            $tvProc = Get-Process -Name TeamViewer -ErrorAction SilentlyContinue
                            if ($tvProc) {
                                Send-TelegramMessage -message "TeamViewer is ACTIVE."
                            } else {
                                Send-TelegramMessage -message "TeamViewer is Not Active."
                            }
                        }
                        "System-Status" {
                            # Call the System-Status function
                            System-Status
                        }
						"Start-Das"   { Start-Das }  # Call the Dashboard-Start function
                        "Stop-Das"    { Stop-Das }   # Call the Dashboard-Stop function
                        "Status-Das"  { Status-Das } # Call the Dashboard-Status function
						    # TrafficMonitor
						"Start-TrafficMonitor" {
							$trafficMonitorPath = "C:\TrafficMonitor\TrafficMonitor.exe"
							if (Test-Path $trafficMonitorPath) {
								Start-Process -FilePath $trafficMonitorPath -ErrorAction SilentlyContinue
								Write-Host "TrafficMonitor is Started."
								Send-TelegramMessage -message "TrafficMonitor is Started."
							}
							else {
								Write-Host "TrafficMonitor is NOT Installed."
								Send-TelegramMessage -message "TrafficMonitor is NOT Installed."
							}
						}
                        "Stop-TrafficMonitor"    { Get-Process -Name TrafficMonitor -ErrorAction SilentlyContinue | Stop-Process -Force
                            Send-TelegramMessage -message "TrafficMonitor is Closed." }   
                        "Status-TrafficMonitor"  { $tvProc = Get-Process -Name TrafficMonitor -ErrorAction SilentlyContinue
                            if ($tvProc) {
                                Send-TelegramMessage -message "TrafficMonitor is ACTIVE."
                            } else {
                                Send-TelegramMessage -message "TrafficMonitor is Not Active."
                            } } 
						"Get-NetworkStatus" {
                                $status = Get-NetworkStatus
                                Send-TelegramMessage $status
                            }	
						"Pause" {
                            $global:scriptPaused = $true
                            New-Item -Path $Global:pauseFlagPath -ItemType File -Force | Out-Null
                            Send-TelegramMessage -message "The AutoPilot is PAUSED. To Resume, send /resume"
                            Write-Log "The AutoPilot is PAUSED"
                        }
                        "Resume" {
							if ($global:scriptPaused) {
								$global:scriptPaused = $false
								if (Test-Path $Global:pauseFlagPath) {
									Remove-Item -Path $Global:pauseFlagPath -Force
								}
								Send-TelegramMessage -message "AutoPilot is STARTED again."
								Write-Log "AutoPilot is STARTED again"
								Stop-WorkerScripts
								Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
								Stop-Process -Id $PID
							} else {
								Send-TelegramMessage -message "AutoPilot is not PAUSED."
							}
						}
                        "Status" {
                            if ($global:scriptStopped) {
                                Send-TelegramMessage -message "Status: AutoPilot is STOPPED."
                            } elseif ($global:scriptPaused) {
                                Send-TelegramMessage -message "Status: AutoPilot is PAUSED."
                            } else {
                                Send-TelegramMessage -message "Status: AutoPilot is ACTIVE."
                            }
                        }
						"Restart-System" {
                            $confirmationRequests[$chatId] = "restart"
                            Send-TelegramMessage -message "Are you sure you want to perform a System RESTART? Reply with Y or N."
                        }
                        "Shutdown-System" {
                            $confirmationRequests[$chatId] = "shutdown"
                            Send-TelegramMessage -message "Are you sure you want to perform a System SHUTDOWN? Reply with Y or N."
                        }
                        "Stop-Script" {
                            $confirmationRequests[$chatId] = "stop"
                            Send-TelegramMessage -message "Are you sure you want to STOP the AutoPilot? Reply with Y or N."
                        }
						"Reset-Script" {
							$confirmationRequests[$chatId] = "reset"
							Send-TelegramMessage -message "Are you sure you want to RESTART the AutoPilot? Reply with Y or N."
						}
						"Hide-Script" {
                            $confirmationRequests[$chatId] = "hide"
                            Send-TelegramMessage -message "Are you sure you want to Restart the AutoPilot Cmd in *HIDDEN* mode? Reply with Y or N."
                        }
                        "Show-Script" {
                            $confirmationRequests[$chatId] = "show"
                            Send-TelegramMessage -message "Are you sure you want to Restart the AutoPilot Cmd in *VISIBLE* mode? Reply with Y or N."
                        }
						"Visible-Status" {
                            $isHidden = (Get-Process -Id $PID).MainWindowHandle -eq 0
                            if ($isHidden) {
                            Send-TelegramMessage -message "The AutoPilot Cmd is currently in *HIDDEN* mode (invisible)."
                            } else {
                            Send-TelegramMessage -message "The AutoPilot Cmd is currently in *VISIBLE* mode (visible on the desktop)."
                            }
                        }
						"Play-VLC" {
                            $response = Play-VLC
                            Send-TelegramMessage -message $response -chatId $chatId
                        }
                        "Stop-VLC" {
                            $response = Stop-VLC
                            Send-TelegramMessage -message $response -chatId $chatId
                        }
                        "Next-Station" {
                            $response = Next-Station
                            Send-TelegramMessage -message $response -chatId $chatId
                        }
                        "Prev-Station" {
                            $response = Prev-Station
                            Send-TelegramMessage -message $response -chatId $chatId
                        }
                        "VLC-Status" {
                            $response = VLC-Status
                            Send-TelegramMessage -message $response -chatId $chatId
                        }
						"Net-Usage" {
                            $usage = Get-TrafficMonitorStats
                            if (-not $usage) {
                            Send-TelegramMessage -message " No DATA available from TrafficMonitor."
                            break
                        }
                            function Format-Traffic($val) {
                            if ($val -ge 1024) {
                            return ("{0:N2} GB" -f ($val / 1024))
                        }   else {
                            return ("{0:N2} MB" -f $val)
                        }
                        }
                           $msg = " Internet Consumption (TrafficMonitor)`n`n"
                           foreach ($key in $usage.Keys) {
                           $dl = Format-Traffic $usage[$key].Download
                           $ul = Format-Traffic $usage[$key].Upload
                           $tot = Format-Traffic $usage[$key].Total
                           $msg += "$key`n"
                           $msg += " Download: $dl`n"
                           $msg += " Upload:   $ul`n"
                           $msg += " Total:    $tot`n`n"
                        }
                           Send-TelegramMessage -message $msg
                        }
						"Get-Temperatures" {
                            $response = Get-Temperatures
                            Send-TelegramMessage -message $response -chatId $chatId
                        }
						"Get-LoadOnlyHardwareData" {
							$parts = Get-LoadOnlyHardwareData
							foreach ($part in $parts) {
								Send-TelegramMessage -message $part -chatId $chatId
							}
						}
                        "Get-NonLoadHardwareData" {
							$parts = Get-NonLoadHardwareData
							foreach ($part in $parts) {
								Send-TelegramMessage -message $part -chatId $chatId
							}
						}
						"Show-HelpMenu" {
                            $msg = Show-HelpMenu
                            Send-TelegramMessage -message $msg -chatId $chatId
                        }
						"Enable-AutoStart" {
                            $msg = Manage-PiScheduledTasks -Action "enable"
                            Send-TelegramMessage -message $msg
                        }
                        "Disable-AutoStart" {
                            $msg = Manage-PiScheduledTasks -Action "disable"
                            Send-TelegramMessage -message $msg
                        }
                        "Status-AutoStart" {
                            $msg = Manage-PiScheduledTasks -Action "status"
                            Send-TelegramMessage -message $msg
                        }
						# Graph - Load Temperature Disk - Day Week Month Year All
						"Generate-LoadGraph-Day"   { Send-Graph -GraphType "Load" -Period "Day" }
						"Generate-LoadGraph-Week"  { Send-Graph -GraphType "Load" -Period "Week" }
						"Generate-LoadGraph-Month" { Send-Graph -GraphType "Load" -Period "Month" }
						"Generate-LoadGraph-Year"  { Send-Graph -GraphType "Load" -Period "Year" }
						"Generate-LoadGraph-All"   { Send-Graph -GraphType "Load" -Period "All" }
						"Generate-TempGraph-Day"   { Send-Graph -GraphType "Temp" -Period "Day" }
						"Generate-TempGraph-Week"  { Send-Graph -GraphType "Temp" -Period "Week" }
						"Generate-TempGraph-Month" { Send-Graph -GraphType "Temp" -Period "Month" }
						"Generate-TempGraph-Year"  { Send-Graph -GraphType "Temp" -Period "Year" }
						"Generate-TempGraph-All"   { Send-Graph -GraphType "Temp" -Period "All" }
						"Generate-DiskGraph-Day"   { Send-Graph -GraphType "Disk" -Period "Day" }
						"Generate-DiskGraph-Week"  { Send-Graph -GraphType "Disk" -Period "Week" }
						"Generate-DiskGraph-Month" { Send-Graph -GraphType "Disk" -Period "Month" }
						"Generate-DiskGraph-Year"  { Send-Graph -GraphType "Disk" -Period "Year" }
						"Generate-DiskGraph-All"   { Send-Graph -GraphType "Disk" -Period "All" }
						# Table - Network Traffic - Day Week Month Year All
						"Generate-TableGraph-Day"   { Send-Graph -GraphType "Table" -Period "Day" }
						"Generate-TableGraph-Week"  { Send-Graph -GraphType "Table" -Period "Week" }
						"Generate-TableGraph-Month" { Send-Graph -GraphType "Table" -Period "Month" }
						"Generate-TableGraph-Year"  { Send-Graph -GraphType "Table" -Period "Year" }
						"Generate-TableGraph-All"   { Send-Graph -GraphType "Table" -Period "All" }
						# Screenshot
						"Take-Screenshot" {
							$result = Take-Screenshot
							$now = Get-Date
							$periodInfo = $now.ToString("dddd, dd MMMM yyyy")
							$caption = "Command: /screen`nPeriod: $periodInfo`nTime: $($now.ToString('HH:mm:ss'))" + "`n" + ("-" * 18) + "`n* Autopilot | Start Menu - /start"
							if ($result -is [string]) {
								Send-TelegramMessage -message $result
							}
							else {
								Send-TelegramPhoto -photoPath $result.Screenshot -caption $caption
							}
						}
						# ScreenRecord
						"Take-ScreenRecord" { Take-ScreenRecord -DurationInSeconds 35 }
						# Start Recording
						"Start-Recording" { Start-Recording }
						# Stop Recording
						"Stop-Recording" {
							$result = Stop-Recording
							if ($result -is [hashtable] -and $result.ContainsKey("Video") -and (Test-Path $result.Video)) {
								$startTime = $result.Start
								$stopTime  = $result.Stop
								$duration  = $result.Duration
								$periodInfo = $startTime.ToString("dddd, dd MMMM yyyy")
								$caption = "Command: /rec_stop`nPeriod: $periodInfo`nStart: $($startTime.ToString('HH:mm:ss'))`nStop: $($stopTime.ToString('HH:mm:ss'))`nDuration: $([math]::Round($duration.TotalSeconds)) seconds`n" + ("-" * 18) + "`n* Autopilot | Start Menu - /start"
								Send-TelegramVideo -videoPath $result.Video -caption $caption
							} else {
								Write-Host " No valid video to send." -ForegroundColor Yellow
							}
						}
						# Start Camera Recording
                        "Start-CameraRecording" { Start-CameraRecording } 
						# Stop Camera Recording
						"Stop-CameraRecording" {
							$result = Stop-CameraRecording
							if ($result -is [hashtable] -and $result.ContainsKey("Video") -and (Test-Path $result.Video)) {
								$startTime = $result.Start
								$stopTime  = $result.Stop
								$duration  = $result.Duration
								$periodInfo = $startTime.ToString("dddd, dd MMMM yyyy")
								$caption = "Command: /cam_stop`nPeriod: $periodInfo`nStart: $($startTime.ToString('HH:mm:ss'))`nStop: $($stopTime.ToString('HH:mm:ss'))`nDuration: $([math]::Round($duration.TotalSeconds)) seconds`n" + ("-" * 18) + "`n* Video Folder: /data`n* Autopilot | Start Menu - /start"
								Send-TelegramVideo -videoPath $result.Video -caption $caption
							} else {
								Write-Host " No valid video to send." -ForegroundColor Yellow
							}
						}
						# Data Folder
						"Data-CameraRecording" {
							if (-not $MediaTelegramEnabled) {
								Write-Log "Media Telegram Bot is Disabled, *Data* command Skipped."
								Send-TelegramMessage -message "Media Telegram Bot is Disabled, *Data* command Skipped."
								return
							}
							Data-CameraRecording
						}
						"Stop-PythonScript" { Stop-PythonScript }
						# Live Monitoring
						"Monitoring-Start" { Start-Monitoring }
						"Monitoring-Stop" { Stop-Monitoring }
						"Monitoring-Status" { Get-MonitoringStatus }
						"Autopilot-Log" { Autopilot-Log }
						"Update-Log" { Update-Log }
						"Monitoring-Log" { Monitoring-Log }
						"Data-Log" { Data-Log }
						"Auto-Shutdown-System" { Auto-Shutdown-System }
                        "Auto-Restart-System"  { Auto-Restart-System }
						"Pause-Script"  { Pause-Script }
						"Open-SystemMonitor" { Open-SystemMonitor }
	                    "Stop-SystemMonitor" { Stop-SystemMonitor }
						"Commands-ListAll" { Commands-ListAll }
                        Default {
                            Send-TelegramMessage -message "Unknown system command: $($cmdInfo.Cmd)"
                        }
                    }
                }
            } else {
                Send-TelegramMessage -message "Invalid command: $text"
            }
        $lastUpdateId.Value = $update.update_id
    }
}

# ▶️ Start log
Clear-Host

# ASCII art za "AUTOPILOT"
$autoPilotArt = @"
_______       _____      ___________________     _____ 
___    |___  ___  /_________  __ \__(_)__  /_______  /_
__  /| |  / / /  __/  __ \_  /_/ /_  /__  /_  __ \  __/
_  ___ / /_/ // /_ / /_/ /  ____/_  / _  / / /_/ / /_  
/_/  |_\__,_/ \__/ \____//_/     /_/  /_/  \____/\__/  
                                                       
"@

$colors = @("Red", "Yellow", "Green", "Cyan", "Blue", "Magenta")
foreach ($line in $autoPilotArt -split "`n") {
    $charIndex = 0
    foreach ($char in $line.ToCharArray()) {
        $color = $colors[$charIndex % $colors.Length]
        Write-Host -NoNewline $char -ForegroundColor $color
        $charIndex++
    }
    Write-Host ""  
}
Write-Host " *AutoPilot by Ivance" -ForegroundColor Blue
Write-Host " *Press W for Dashboard" -ForegroundColor DarkYellow
Write-Host "===============================" -ForegroundColor Cyan
Write-Host ""
Write-Host "=== START OF AUTOPILOT ===" -ForegroundColor Green
Write-Host ("Time: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -ForegroundColor Yellow
Write-Host ("User: {0}" -f $env:USERNAME) -ForegroundColor Magenta
Write-Host ("Computer: {0}" -f $env:COMPUTERNAME) -ForegroundColor Magenta
Write-Host ("PowerShell version: {0}" -f $PSVersionTable.PSVersion) -ForegroundColor Cyan
Write-Host ("OS version: {0}" -f (Get-CimInstance Win32_OperatingSystem).Caption) -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

if ($maxRuns -eq 1) {
    Write-Log "Mode: SINGLE (1 Repeat)" -Display
} elseif ($maxRuns -gt 1) {
    Write-Log "Mode: LIMITED ($maxRuns Repetitions)" -Display
} else {
    Write-Log "Mode: INFINITE (Loop)" -Display
}

Write-Log "===============================" -Display

if ($AutoPilotTelegramEnabled) {
    $hostname = $env:COMPUTERNAME
    $startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $message = "AutoPilot started...`nTime: $startTime`nMaximum repetitions: $maxRuns`nDay: $(Get-Date -Format 'dddd')"
    Send-TelegramMessage -message $message
}

# 🔄 DELETE PAUSE FLAG ON START AutoPilot
if (Test-Path $Global:pauseFlagPath) {
    Remove-Item -Path $Global:pauseFlagPath -Force
    Write-Log "Pause flag cleared at AutoPilot start"
}

#  Function PAUSE Flag
function Sync-PauseStateFromFlag {
    if (Test-Path $Global:pauseFlagPath) {
        if (-not $global:scriptPaused) {
            $global:scriptPaused = $true
            Write-Log "Pause activated via pause.flag (external)"
        }
    } else {
        if ($global:scriptPaused) {
            $global:scriptPaused = $false
            Write-Log "Resume activated via pause.flag (external)"
        }
    }
}

# Inicializiraj promenliva za sledniot update_id na Telegram
$lastTelegramUpdateId = 0
# Dodatna promenliva za sledno vreme na proverka temperatura
$lastTempCheckTime = Get-Date

# 🔁 Glaven loop za brojot na povtoruvanja
$r = 1
while ($maxRuns -eq 0 -or $r -le $maxRuns) {
    Sync-PauseStateFromFlag  # 👈 Pause from FLAG
    # Ako je pauza, čekaj na /resume komandu
    while ($global:scriptPaused) {
        Write-Log "AutoPilot is PAUSED. Waiting for the /resume command..."
        Start-Sleep -Seconds 5
        Process-ManualCommands -lastUpdateId ([ref]$lastTelegramUpdateId)
        Sync-PauseStateFromFlag  # 👈 Pause from FLAG 
    }

    $now = Get-Date
    if ($allowedDays -notcontains $now.DayOfWeek.ToString()) {
        Write-Log "Skip: Day not allowed ($($now.DayOfWeek))"
        if ($AutoPilotTelegramEnabled) {
            Send-TelegramMessage -message "The script did not run today ($($now.DayOfWeek))."
        }
        break
    }

    Write-Log "Repetition number: $r" -Display
    Write-Host ""
    Write-Host "-List of completed automatic commands:" -ForegroundColor Yellow
    if ($AutoPilotTelegramEnabled) {
        Send-TelegramMessage -message "Repetition $r started..."
    }
	
    # --- Pravi listu svih narednih izvršenja komandi sa ponavljanjem i Day ---
	$allCommands = @()
	foreach ($script in $ScheduledScripts) {
		for ($i = 0; $i -lt $script.Commands.Count; $i++) {
			$timeSpan = [TimeSpan]::Parse($script.Times[$i])
			$delaySeconds = $script.DelaySeconds[$i]
			# Repeat interval
			$repeatInterval = 0
			if ($script.ContainsKey("RepeatIntervalMinutes") -and
				$script.RepeatIntervalMinutes.Count -gt $i) {
				$repeatInterval = $script.RepeatIntervalMinutes[$i]
			}
			# ---------- CHECK IF EXPLICIT DAY EXISTS ----------
			$useExplicitDay =
				$script.ContainsKey("Day") -and
				$script.Day -and
				$script.Day.Count -gt $i -and
				-not [string]::IsNullOrWhiteSpace($script.Day[$i])
			# ---------- BASE TIME ----------
			if ($useExplicitDay) {
				# Logika od Day (strogo za taj datum)
				$baseTime = [DateTime]::ParseExact(
					$script.Day[$i],
					"yyyy-MM-dd",
					$null
				).Add($timeSpan)
				# Ako je vreme u proslosti, preskoci
				if ($baseTime -lt (Get-Date)) {
					continue
				}
				$endTime = $baseTime.Date.AddDays(1)   # do kraja tog dana
			}
			else {
				# Logika od prviot kod (ako nema Day)
				$baseTime = [DateTime]::Today.Add($timeSpan)
				if ($baseTime -lt (Get-Date)) {
					$baseTime = $baseTime.AddDays(1)
				}

				$endTime = $baseTime.AddDays(1)        # narednih 24h
			}
			# ---------- GENERISANJE EXEC TIMES ----------
			if ($repeatInterval -gt 0) {
				$currentExecTime = $baseTime
				while ($currentExecTime -lt $endTime) {
					$execTime = $currentExecTime.AddSeconds($delaySeconds)

					$allCommands += [PSCustomObject]@{
						ScriptPath   = $script.Path
						Command      = $script.Commands[$i]
						ExecTime     = $execTime
						DelaySeconds = $delaySeconds
					}

					$currentExecTime = $currentExecTime.AddMinutes($repeatInterval)
				}
			}
			else {
				$execTime = $baseTime.AddSeconds($delaySeconds)

				$allCommands += [PSCustomObject]@{
					ScriptPath   = $script.Path
					Command      = $script.Commands[$i]
					ExecTime     = $execTime
					DelaySeconds = $delaySeconds
				}
			}
		}
	}

    # Sortiraj komande po ExecTime
    $sortedCommands = $allCommands | Sort-Object ExecTime
    # --- Izvrši komande po redosledu ---
    foreach ($cmd in $sortedCommands) {
        # Čekaj dok ne dođe vreme izvršenja komande
        while ((Get-Date) -lt $cmd.ExecTime) {
			Sync-PauseStateFromFlag   # 👈 Pause from FLAG
            Start-Sleep -Seconds 1
            Process-ManualCommands -lastUpdateId ([ref]$lastTelegramUpdateId)
			Check-AutoCommands # NE RABOTI VO PAUSE
			# DODADI proverka temperatura na na 5 minuti  OVA E PLUS SAMO VO KODOT!
                # DELETE
				# 🔹 NOVO - da se proveruva temperatura i dok e pauzirano
                $now = Get-Date
                if (($now - $lastTempCheckTime).TotalSeconds -ge $TempCheckInterval) {
                    Check-TemperatureAndNotify
                    $lastTempCheckTime = $now
                }
                # 🔹 KRAJ
				# DELETE
            while ($global:scriptPaused) {
                Write-Log "AutoPilot is PAUSED. Waiting for the /resume..."
				Sync-PauseStateFromFlag   # 👈 Pause from FLAG
                # DELETE
				# 🔹 NOVO - da se proveruva temperatura i dok e pauzirano
                $now = Get-Date
                if (($now - $lastTempCheckTime).TotalSeconds -ge $TempCheckInterval) {
                    Check-TemperatureAndNotify
                    $lastTempCheckTime = $now
                }
                # 🔹 KRAJ
				# DELETE
				Start-Sleep -Seconds 5
                Process-ManualCommands -lastUpdateId ([ref]$lastTelegramUpdateId)
				# Check-AutoCommands # RABOTI VO PAUSE
                if ($global:scriptStopped) { break 3 } # Izlaz iz foreach i oba while
            }

            if ($global:scriptStopped) { break 2 }
        }

        # Provera pauze pre pokretanja komande
        while ($global:scriptPaused) {
            Write-Log "AutoPilot is PAUSED before executing the command. Waiting for /resume..."
			Sync-PauseStateFromFlag   # 👈 Pause from FLAG
                # DELETE
				# 🔹 NOVO - da se proveruva temperatura i dok e pauzirano
                $now = Get-Date
                if (($now - $lastTempCheckTime).TotalSeconds -ge $TempCheckInterval) {
                    Check-TemperatureAndNotify
                    $lastTempCheckTime = $now
                }
                # 🔹 KRAJ
				# DELETE
			Start-Sleep -Seconds 5
            Process-ManualCommands -lastUpdateId ([ref]$lastTelegramUpdateId)
            if ($global:scriptStopped) { break 2 }
        }

        if ($global:scriptStopped) { break }
        # Avtomatski RESTART SHUTDOWN RESTART-SCRIPT ako ne se izvrsi nekoja komanda !!!
		Write-Log "Invocation $($cmd.ScriptPath) -AutoRunOps $($cmd.Command)"
        $scriptName = Split-Path $cmd.ScriptPath -Leaf
		
		# Start skriptata vo background kako Job
			$job = Start-Job -ScriptBlock {
			param($path, $command)
			& "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -File $path -AutoRunOps $command -Silent
		    } -ArgumentList $cmd.ScriptPath, $cmd.Command

			$timeout = 355 # vo sekundi vremeto potrebno za da se izvrsi KOMANDA (Auto Manuelna).
			$jobCompleted = $job | Wait-Job -Timeout $timeout

			if ($jobCompleted) {
				try {
					$output = Receive-Job -Job $job
					Write-Log "Result: $output"
					Send-TelegramMessage -message "Result from $($cmd.Command) ($scriptName):`n$output"
				} catch {
					Write-Log "Error retrieving result from job: $_"
					Send-TelegramMessage -message "Error executing command $text ($scriptName)."
				}
			} 
			    else {
			# Timeout - komanda se zaglavi
			$currentTime = Get-Date -Format "HH:mm"
			$hour = (Get-Date).Hour
			Write-Log "Command $($cmd.Command) ($scriptName) is stuck. Action is being executed according to schedule ($currentTime)."

			# 1. RESTART SCRIPT  Avtomatski restart na skripta vo 17:00 - 00:00
			if (($hour -ge 07 -and $hour -lt 09) -or ($hour -ge 11 -and $hour -lt 12) -or ($hour -ge 15 -and $hour -lt 19)) {
				Write-Log "(($hour -ge 07 -and $hour -lt 09) -or ($hour -ge 11 -and $hour -lt 12) -or ($hour -ge 15 -and $hour -lt 19)): RESTART of AutoPilot"
				Send-TelegramMessage -message "Command $($cmd.Command) ($scriptName) is stuck. The AutioPilot is Restarting..."
				Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
				Stop-WorkerScripts
				Stop-Process -Id $PID
			}
			
			# 2. Vo site drugi slucai, pobaraj odgovor
			Send-TelegramMessage -message "Command $($cmd.Command) ($scriptName) is stuck. Should an automatic Restart or Shutdown of the PC be executed? Reply with 'Y' or 'N' within the next 5 minutes… Choosing 'N' will cancel the automatic command (Restart or Shutdown) and only the AutoPilot will be Restarted."
			
			# Cekaj odgovor do 5 minuti (300 sekundi)
			$startTime = Get-Date
			$response = $null
			
			do {
				Start-Sleep -Seconds 5
				try {
					$updates = Get-Updates
					foreach ($update in $updates) {
                        # 🛡️ SECURITY GATE 
						# Private chat
						if ($update.message.chat.type -ne "private") {
							Write-Log "AUDIT: Message from non-private chat | ChatType=$($update.message.chat.type) | ChatId=$($update.message.chat.id)"
							$lastUpdateId.Value = $update.update_id
							continue
						}
						# Chat OWNER
						$userId = $update.message.from.id
						if ($userId -ne $OwnerId) {
						$chatId = $update.message.chat.id
						$now = Get-Date
						# 📜 AUDIT LOG 
						Write-Log "AUDIT: Unauthorized Access | UserId=$userId | ChatId=$chatId | Text='$($update.message.text)'"
						# 🔔 ALARM (rate-limited)
						if (
							-not $global:LastAuditAlert.ContainsKey($userId) -or
							($now - $global:LastAuditAlert[$userId]).TotalMinutes -ge 3
						) {
							Send-TelegramMessage -message @"
 *SECURITY ALERT*
Unauthorized Access Attempt!

 UserId: $userId
 ChatId: $chatId
 Message: '$($update.message.text)'
 Time: $now
"@
						$global:LastAuditAlert[$userId] = $now
						}
						# 🚫 Block
						Send-TelegramMessage -message "Access to Chat is Forbidden."
						$lastUpdateId.Value = $update.update_id
						continue
						}
						$msgText = ($update.message.text).Trim()  
						if ($msgText -cmatch '^[YN]$') {          
							$response = $msgText
							break
						} else {
							Send-TelegramMessage -message "Invalid response. Reply with Y or N."
						}
					}
				} catch {
					Write-Log "Error checking Telegram response: $_"
				}
            } 

            while (([datetime]::Now - $startTime).TotalSeconds -lt 300 -and -not $response)

			# Ako nema odgovor vo 5 minuti, default 'Y'
			if (-not $response) {
				$response = 'Y'
				Write-Log "No response within the time limit. Defaulting to 'Y'"
			}
			
			# Odluči akcija spored odgovor
			if ($response -eq 'Y') {
				# RESTART PC 09:00 - 10:00, 13:00 - 15:00, 21:00 - 23:00
				if (($hour -ge 09 -and $hour -lt 10) -or ($hour -ge 13 -and $hour -lt 15) -or ($hour -ge 21 -and $hour -lt 23)) {
					Write-Log "(($hour -ge 09 -and $hour -lt 10) -or ($hour -ge 13 -and $hour -lt 15) -or ($hour -ge 21 -and $hour -lt 23)): RESTART of PC" 
					Send-TelegramMessage -message "PC RESTART is being Executed..."
					Invoke-Expression $restartCmd
				}
				# SHUTDOWN PC за сите други опсези
				elseif (($hour -ge 00 -and $hour -lt 24)) { #(($hour -ge 15 -and $hour -lt 23) -or ($hour -ge 23 -and $hour -lt 24) -or ($hour -ge 0 -and $hour -lt 6)) Full Code 
					Write-Log "00:00 - 24:00: SHUTDOWN of PC"
					Send-TelegramMessage -message "PC SHUTDOWN is being Executed..."
					Invoke-Expression $shutdownCmd
				}
				else {
					Write-Log "Unknown time range. No action is taken."
					Send-TelegramMessage -message "Unknown time range. No action is taken."
				}
			}

			# DEFAULT RESTART SCRIPT
			elseif ($response -eq 'N') {
				Write-Log "The User replied 'N'. Only the AutoPilot is Restarting."
				Send-TelegramMessage -message "The Automatic Command is canceled. Only the AutoPilot is Restarting..."
				Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
				Stop-WorkerScripts
				Stop-Process -Id $PID
			}
           
		    # Resetiraj Telegram offset
            try {
                $lastUpdates = Get-Updates
                if ($lastUpdates.Count -gt 0) {
                    $maxUpdateId = ($lastUpdates | Sort-Object update_id -Descending | Select-Object -First 1).update_id
                    $nextOffset = $maxUpdateId + 1
                    $resetUri = "https://api.telegram.org/bot$telegramBotToken/getUpdates?offset=$nextOffset"
                    Invoke-RestMethod -Uri $resetUri -Method Get -ErrorAction SilentlyContinue
                    Write-Log "Telegram offset resetiran na $nextOffset"
                }
            } catch {
                Write-Log "Failed attempt to reset Telegram offset: $_"
					}
			}	

        # Čekaj delay posle izvršenja komande
        Start-Sleep -Seconds $cmd.DelaySeconds
        Process-ManualCommands -lastUpdateId ([ref]$lastTelegramUpdateId)
    }

    Write-Log "Repetition number completed $r"
    if ($AutoPilotTelegramEnabled) {
        Send-TelegramMessage -message "Repetition $r completed."
    }

    $r++
}

Write-Host "" 
Write-Log "=== END OF AUTOPILOT ===" -Display
Write-Host ""
if ($AutoPilotTelegramEnabled) {
    $endTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $duration = ((Get-Date) - $scriptStartTime).ToString("hh\:mm\:ss")
    $message = "AutoPilot has Finished...`nEnd: $endTime`nExecution time: $duration`nRepetitions: $($r - 1)"
    Send-TelegramMessage -message $message
}
# ⛔ Stop All Worker Scripts
Stop-WorkerScripts
# Za da ostane skriptata 15 sekundi pred da se zatvori:
Write-Host " *AutoPilot Cmd will close in 15 seconds ..." -ForegroundColor Red
Write-Host ""
Write-Host " *AutoPilot by Ivance" -ForegroundColor Blue
Write-Host "===============================" -ForegroundColor Cyan
Start-Sleep -Seconds 15
############################################################################################################################################################################################ 888 AutoPilot Script.

#  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

#  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Restricted

#  Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Restricted 

#  Set-ExecutionPolicy Restricted -Scope CurrentUser -Force  (Full Locked)

#  Set-ExecutionPolicy Restricted -Scope LocalMachine  (Full Locked)
