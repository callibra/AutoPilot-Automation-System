# ➕ Поддршка за автоматски параметри
param (
    [string[]]$AutoRunOps = @(),
    [switch]$Silent
)

### Проверка за админ
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "The script must be run as Administrator!"
    if (-not $Silent) { Pause }
    Exit
}

### Globalni promenlivi
$global:dataPath = "$PSScriptRoot\Autopilot_Data"
if (-not (Test-Path $global:dataPath)) {
    New-Item -Path $global:dataPath -ItemType Directory | Out-Null
}

$global:logFile = "$global:dataPath\defender-log.txt"
$global:defenderTimeFile = "$global:dataPath\defender-time.json"

### Funkcii za JSON - SET TIME
function Set-DefenderTime {
    param ([datetime]$time)
    $data = @{ DefenderStartTime = $time.ToString("o") }
    $data | ConvertTo-Json | Set-Content -Path $global:defenderTimeFile
}

### Funkcii za JSON - GET TIME
function Get-DefenderTime {
    if (-not (Test-Path $global:defenderTimeFile)) {
        return $null
    }
    try {
        $raw = Get-Content -Path $global:defenderTimeFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Remove-Item $global:defenderTimeFile -Force
            return $null
        }
        $json = $raw | ConvertFrom-Json
        if (-not $json.DefenderStartTime) {
            Remove-Item $global:defenderTimeFile -Force
            return $null
        }
        return [datetime]::Parse($json.DefenderStartTime)
    }
    catch {
        Remove-Item $global:defenderTimeFile -Force -ErrorAction SilentlyContinue
        Log "WARNING: defender-time.json it was corrupted and has been reset."
        return $null
    }
}

### Funkcii za JSON - CLEAR TIME
function Clear-DefenderTime {
    if (Test-Path $global:defenderTimeFile) { Remove-Item $global:defenderTimeFile -ErrorAction SilentlyContinue }
}

### Log
function Log {
    param ([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $global:logFile -Value "$timestamp - $msg"
}

### Set Boja
function Set-Boja {
    param (
        [string]$Text,
        [ConsoleColor]$Color = "White"
    )
    $origColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    Write-Host $Text
    $Host.UI.RawUI.ForegroundColor = $origColor
}

### MENI
function Show-Meni {
    Clear-Host
    $line = '=' * 50

    Set-Boja $line -Color Cyan
    Set-Boja ("{0,30}" -f "Windows Defender Control") -Color Yellow
    Set-Boja $line -Color Cyan
    Write-Host ""
    Set-Boja " [1] Turn OFF Real-Time Protection" -Color Red
    Set-Boja " [2] Turn ON Real-Time Protection" -Color Green
    Set-Boja " [3] Status for Real-Time Protection" -Color Blue
    Set-Boja " [4] Tamper Protection" -Color Yellow
    Set-Boja " [5] Turn ON Tamper Protection (Restart Defender)" -Color Magenta
    Set-Boja " [6] Exit" -Color White
    Write-Host ""
}

### Stop Defender
function Iskluci-Defender {
    $alreadyDisabled = Get-MpPreference | Select-Object -ExpandProperty DisableRealtimeMonitoring
    if ($alreadyDisabled) {
        Set-Boja "Real-time protection is ALREADY OFF." -Color DarkYellow
        $startTime = Get-DefenderTime
        if ($startTime -ne $null) {
            $duration = (Get-Date) - $startTime
            $timeParts = @()
            if ($duration.Days -gt 0) { $timeParts += "$($duration.Days) days" }
            if ($duration.Hours -gt 0) { $timeParts += "$($duration.Hours) hours" }
            if ($duration.Minutes -gt 0) { $timeParts += "$($duration.Minutes) minutes" }
            if ($duration.Seconds -gt 0) { $timeParts += "$($duration.Seconds) seconds" }
            $formattedDuration = ($timeParts -join ", ")
            if ([string]::IsNullOrEmpty($formattedDuration)) { $formattedDuration = "0 seconds" }
            Set-Boja "Turned off at: $startTime" -Color Red
            Set-Boja "Elapsed time: $formattedDuration." -Color DarkYellow
        }
        if (-not $Silent) { Pause }
        return
    }
    Set-Boja "Turning off real-time protection..." -Color Red
    Set-MpPreference -DisableRealtimeMonitoring $true
    $timeNow = Get-Date
    Set-DefenderTime -time $timeNow
    Log "REAL-TIME PROTECTION TURNED OFF at $timeNow"
    Set-Boja "Defender is turned off at: $timeNow" -Color Red
    if (-not $Silent) { Pause }
}

### Start Defender
function Vkluci-Defender {
    Set-Boja "Turning on real-time protection..." -Color Green
    Set-MpPreference -DisableRealtimeMonitoring $false
    $startTime = Get-DefenderTime
    if ($startTime -ne $null) {
        $duration = (Get-Date) - $startTime
        $timeParts = @()
        if ($duration.Days -gt 0) { $timeParts += "$($duration.Days) days" }
        if ($duration.Hours -gt 0) { $timeParts += "$($duration.Hours) hours" }
        if ($duration.Minutes -gt 0) { $timeParts += "$($duration.Minutes) minutes" }
        if ($duration.Seconds -gt 0) { $timeParts += "$($duration.Seconds) seconds" }
        $formattedDuration = ($timeParts -join ", ")
        if ([string]::IsNullOrEmpty($formattedDuration)) { $formattedDuration = "0 seconds" }
        Set-Boja "Defender was turned off $formattedDuration." -Color Green
        Log "REAL-TIME PROTECTION TURNED ON at $formattedDuration."
        Clear-DefenderTime
    } else {
        Set-Boja "Defender is turned on." -Color Green
        Log "REAL-TIME PROTECTION TURNED ON (no previous timestamp)."
    }
    if (-not $Silent) { Pause }
}

### Status Defender
function Status-Info {
    $status = Get-MpPreference | Select-Object -ExpandProperty DisableRealtimeMonitoring
    if ($status) {
        Set-Boja "Real-time protection is OFF." -Color Red
        $startTime = Get-DefenderTime
        if ($startTime -ne $null) {
            $duration = (Get-Date) - $startTime
            $timeParts = @()
            if ($duration.Days -gt 0) { $timeParts += "$($duration.Days) days" }
            if ($duration.Hours -gt 0) { $timeParts += "$($duration.Hours) hours" }
            if ($duration.Minutes -gt 0) { $timeParts += "$($duration.Minutes) minutes" }
            if ($duration.Seconds -gt 0) { $timeParts += "$($duration.Seconds) seconds" }
            $formattedDuration = ($timeParts -join ", ")
            if ([string]::IsNullOrEmpty($formattedDuration)) { $formattedDuration = "0 seconds" }
            Set-Boja "Turned off at: $startTime" -Color Red
            Set-Boja "Elapsed time $formattedDuration." -Color Red
        } else {
            Set-Boja "Time of Turn OFF is unknown." -Color DarkGray
        }
    } else {
        Set-Boja "Real-time protection is ON." -Color Green
    }
    if (-not $Silent) { Pause }
}

### Check Tamper
function Proveri-Tamper {
    try {
        $tamperStatus = Get-MpComputerStatus | Select-Object -ExpandProperty IsTamperProtected
        if ($tamperStatus) {
            Set-Boja "Tamper Protection is ON." -Color Green
        } else {
            Set-Boja "Tamper Protection is OFF." -Color Red
        }
    } catch {
        Set-Boja "Error during check: $($_.Exception.Message)" -Color Red
    }
    if (-not $Silent) { Pause }
}

### Restart Defender
function Restartiraj-Defender-Za-Tamper {
    try {
        $tamperStatus = Get-MpComputerStatus | Select-Object -ExpandProperty IsTamperProtected
        if ($tamperStatus) {
            Set-Boja "Tamper Protection is already ON." -Color Green
        } else {
            Set-Boja "Tamper Protection is OFF." -Color Red
            Set-Boja "Attempting to restart the Windows Defender service..." -Color Yellow

            try {
                Stop-Service -Name WinDefend -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
            } catch {}

            try {
                Start-Service -Name WinDefend -ErrorAction Stop
                Set-Boja "WinDefend service has been restarted." -Color Green
            } catch {
                Set-Boja "System restart is required." -Color Red
            }
        }
    } catch {
        Set-Boja "Error checking Tamper Protection." -Color Red
    }
    if (-not $Silent) { Pause }
}

### Avtomatsko izvrshuvanje
if ($AutoRunOps.Count -gt 0) {
    foreach ($op in $AutoRunOps) {
        switch ($op) {
            "1" { Iskluci-Defender }
            "2" { Vkluci-Defender }
            "3" { Status-Info }
            "4" { Proveri-Tamper }
            "5" { Restartiraj-Defender-Za-Tamper }
            default { Write-Host "Unknown option: $op" -ForegroundColor Red }
        }
    }
    exit
}

### MENI LOOP
do {
    Show-Meni
    $izbor = Read-Host "Select an option (1-6)"
    switch ($izbor) {
        "1" { Iskluci-Defender }
        "2" { Vkluci-Defender }
        "3" { Status-Info }
        "4" { Proveri-Tamper }
        "5" { Restartiraj-Defender-Za-Tamper }
        "6" {
            Set-Boja "Exiting the script..." -Color Cyan
            exit
        }
        default {
            Set-Boja "Invalid choice. Please try again." -Color Red
            if (-not $Silent) { Pause }
        }
    }
} while ($true)

######################################################################################################### Defender Script End.
