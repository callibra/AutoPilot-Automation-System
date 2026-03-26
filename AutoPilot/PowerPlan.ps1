# === Проверка за администраторски права ===
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
    Write-Warning "The script must be run as Administrator!"
    Start-Sleep -Seconds 3
    exit
}

# -- Пат до ThrottleStop.ini и ThrottleStop.exe --
$iniPath = "C:\ThrottleStop\ThrottleStop.ini"
$throttleStopExe = "C:\ThrottleStop\ThrottleStop.exe"

# --- Функции за ThrottleStop профили ---
function Get-ThrottleStopProfile {
    if (Test-Path $iniPath) {
        $content = Get-Content $iniPath
        foreach ($line in $content) {
            if ($line -match '^Profile=(\d)') {
                return [int]$matches[1]
            }
        }
    }
    return $null
}

function Set-ThrottleStopProfile {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("0","1","2","3")]
        [string]$ProfileNumber
    )
    $content = Get-Content $iniPath
    $content = $content -replace 'Profile=\d', "Profile=$ProfileNumber"
    Set-Content -Path $iniPath -Value $content
    Write-Host "Profile changed to $([int]$ProfileNumber + 1)" -ForegroundColor Green
}

function Restart-ThrottleStop {
    $proc = Get-Process -Name "ThrottleStop" -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "Closing ThrottleStop..." -ForegroundColor Yellow
        $proc | Stop-Process -Force
        Start-Sleep -Seconds 3
    }
    Write-Host "Starting ThrottleStop..." -ForegroundColor Yellow
    Start-Process $throttleStopExe
    Start-Sleep -Seconds 2
}

function Show-ThrottleStopMenu {
    $currentProfile = Get-ThrottleStopProfile
    $profileNames = @("Profile Power (3.5)", "Profile Cool (3.0)", "Profile Medium (2.8)", "Profile Low End (2.6)")
    Clear-Host
    Write-Host "=== ThrottleStop Menu ===" -ForegroundColor Cyan
    Write-Host "Current profile: " -NoNewline
    if ($currentProfile -ge 0 -and $currentProfile -lt $profileNames.Length) {
        Write-Host "$($profileNames[$currentProfile])" -ForegroundColor Green
    } else {
        Write-Host "Unidentified profile" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "[1] Change profile"
    Write-Host "[2] Show current profile"
    Write-Host "[3] Return to main menu"
    Write-Host ""
}

function ThrottleStopMenu {
    do {
        Show-ThrottleStopMenu
        $selection = Read-Host "Enter option number"
        switch ($selection) {
            "1" {
                Write-Host "Select a profile for ThrottleStop:" -ForegroundColor Cyan
                Write-Host " -0 = Profile Power"
                Write-Host " -1 = Profile Cool"
                Write-Host " -2 = Profile Medium"
                Write-Host " -3 = Profile Low End"
                $choice = Read-Host "Enter profile number (0-3)"
                if ($choice -in '0','1','2','3') {
                    Set-ThrottleStopProfile -ProfileNumber $choice
                    Restart-ThrottleStop
                    Write-Host "Change completed! Press any key to continue..." -ForegroundColor Green
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
                else {
                    Write-Host "Invalid selection, please try again." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
                $continueMenu = $true
            }
            "2" {
                $currentProfile = Get-ThrottleStopProfile
                Write-Host "Current profile: " -NoNewline
                switch ($currentProfile) {
                    0 { Write-Host "-Profile Power" -ForegroundColor Green }
                    1 { Write-Host "-Profile Cool" -ForegroundColor Green }
                    2 { Write-Host "-Profile Medium" -ForegroundColor Green }
                    3 { Write-Host "-Profile Low End" -ForegroundColor Green }
                    default { Write-Host "Unidentified profile" -ForegroundColor Red }
                }
                Write-Host "Press any key to continue..." -ForegroundColor Yellow
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                $continueMenu = $true
            }
            "3" {
                return $false  # Vrati se vo glavno meni
            }
            default {
                Write-Host "Invalid selection, please try again." -ForegroundColor Red
                Start-Sleep -Seconds 2
                $continueMenu = $true
            }
        }
    } while ($continueMenu)
}

# --- CPU Performance Functions ---
function Get-CurrentPowerPlan {
    $guid = (powercfg /getactivescheme | Select-String -Pattern 'GUID: ([a-f0-9-]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value })
    return $guid
}

function Set-PowerPlan($guid) {
    powercfg -setactive $guid | Out-Null
}

function Get-CPUThrottle {
    $guid = Get-CurrentPowerPlan
    $maxThrottle = powercfg -query $guid SUB_PROCESSOR PROCTHROTTLEMAX | Select-String -Pattern "Current AC Power Setting Index: 0x([a-f0-9]+)" | ForEach-Object {
        [Convert]::ToInt32($_.Matches[0].Groups[1].Value,16)
    }
    $minThrottle = powercfg -query $guid SUB_PROCESSOR PROCTHROTTLEMIN | Select-String -Pattern "Current AC Power Setting Index: 0x([a-f0-9]+)" | ForEach-Object {
        [Convert]::ToInt32($_.Matches[0].Groups[1].Value,16)
    }
    return @{Max=$maxThrottle; Min=$minThrottle}
}

function Set-CPUThrottle($max, $min) {
    $guid = Get-CurrentPowerPlan
    powercfg -setacvalueindex $guid SUB_PROCESSOR PROCTHROTTLEMAX $max | Out-Null
    powercfg -setacvalueindex $guid SUB_PROCESSOR PROCTHROTTLEMIN $min | Out-Null
    powercfg -setactive $guid | Out-Null
}

function Get-TurboBoostStatus {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\be337238-0d82-4146-a960-4f3749d470c7"
        $val = Get-ItemPropertyValue -Path $regPath -Name "ACSettingIndex" -ErrorAction Stop
        return $val -eq 1
    } catch {
        $guid = Get-CurrentPowerPlan
        $output = powercfg -query $guid SUB_PROCESSOR PERFBOOSTMODE
        $val = $output | Select-String -Pattern "Current AC Power Setting Index: 0x([0-9a-f]+)" | ForEach-Object {
            [Convert]::ToInt32($_.Matches[0].Groups[1].Value,16)
        } | Select-Object -First 1
        if ($null -ne $val) {
            return $val -eq 1
        } else {
            return $false
        }
    }
}

function Set-TurboBoost($enable) {
    $guid = Get-CurrentPowerPlan
    $value = if ($enable) { 1 } else { 0 }
    powercfg -setacvalueindex $guid SUB_PROCESSOR PERFBOOSTMODE $value | Out-Null

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\be337238-0d82-4146-a960-4f3749d470c7"
    try {
        Set-ItemProperty -Path $regPath -Name "ACSettingIndex" -Value $value -ErrorAction Stop
        Set-ItemProperty -Path $regPath -Name "DCSettingIndex" -Value $value -ErrorAction Stop
    } catch {
        # ignore errors
    }
    powercfg -setactive $guid | Out-Null
}

function Show-CurrentCPUStatus {
    Clear-Host
    Write-Host "=== Current CPU Settings ===" -ForegroundColor Cyan
    $cpuThrottle = Get-CPUThrottle
    Write-Host "CPU Max Throttle: $($cpuThrottle.Max)%"
    Write-Host "CPU Min Throttle: $($cpuThrottle.Min)%"
    $turbo = Get-TurboBoostStatus
    Write-Host "Turbo Boost Enabled: $([bool]$turbo)"
    Write-Host ""
    Write-Host "Press any key to go back..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function CustomCPUMode {
    do {
        $maxInput = Read-Host "Enter max CPU throttle (0-100)%"
        $maxParsed = 0
        $isValidMax = [int]::TryParse($maxInput, [ref]$maxParsed) -and ($maxParsed -ge 0) -and ($maxParsed -le 100)
        if (-not $isValidMax) {
            Write-Host "Invalid input. Enter a number from 0 to 100." -ForegroundColor Red
        }
    } while (-not $isValidMax)

    do {
        $minInput = Read-Host "Enter min CPU throttle (0-100)%"
        $minParsed = 0
        $isValidMin = [int]::TryParse($minInput, [ref]$minParsed) -and ($minParsed -ge 0) -and ($minParsed -le 100)
        if (-not $isValidMin) {
            Write-Host "Invalid input. Enter a number from 0 to 100" -ForegroundColor Red
        }
    } while (-not $isValidMin)

    do {
        $turbo = Read-Host "Is Turbo Boost enabled? (Y/N)"
        $turboUpper = $turbo.ToUpper()
        if ($turboUpper -ne "Y" -and $turboUpper -ne "N") {
            Write-Host "Invalid input. Enter Y or N." -ForegroundColor Red
            $validTurbo = $false
        } else {
            $validTurbo = $true
        }
    } while (-not $validTurbo)

    Set-CPUThrottle $maxParsed $minParsed
    Set-TurboBoost ($turboUpper -eq "Y")

    Write-Host "Custom CPU mode applied: Max=$maxParsed%, Min=$minParsed%, Turbo=$turboUpper" -ForegroundColor Green
    Write-Host "Press any key to continue..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Show-CPUMenu {
    Clear-Host
    Write-Host "=== CPU Performance Menu ===" -ForegroundColor Cyan
    Write-Host "[1] Activate i3 Mode (CPU max 60%, Turbo off)"
    Write-Host "[2] Activate i5 Mode (CPU max 85%, Turbo on)"
    Write-Host "[3] Custom CPU Mode"
    Write-Host "[4] Reset to Default (saved default values)"
    Write-Host "[5] Show current status"
    Write-Host "[6] Return to main menu"
    Write-Host ""
}

# --- Default settings save/load ---
$defaultSettingsFile = "$PSScriptRoot\defaultSettings.json"

function Read-DefaultSettings {
    if (Test-Path $defaultSettingsFile) {
        return Get-Content $defaultSettingsFile | ConvertFrom-Json
    } else {
        return $null
    }
}

function Save-DefaultSettings($settings) {
    $settings | ConvertTo-Json -Depth 5 | Set-Content $defaultSettingsFile
}

function SaveDefaultSettingsIfNeeded {
    if (-not (Test-Path $defaultSettingsFile)) {
        Write-Host "Saving current system settings as default..." -ForegroundColor Yellow
        $cpuThrottle = Get-CPUThrottle
        $turbo = Get-TurboBoostStatus
        $powerPlan = Get-CurrentPowerPlan
        $default = [PSCustomObject]@{
            PowerPlan = $powerPlan
            CPUThrottleMax = $cpuThrottle.Max
            CPUThrottleMin = $cpuThrottle.Min
            TurboBoostEnabled = $turbo
        }
        Save-DefaultSettings $default
        Write-Host "Defaults saved." -ForegroundColor Green
        Start-Sleep -Seconds 2
    }
}

function ResetToDefault {
    $default = Read-DefaultSettings
    if ($default -eq $null) {
        Write-Host "Default settings not found!" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }
    Set-PowerPlan $default.PowerPlan
    Set-CPUThrottle $default.CPUThrottleMax $default.CPUThrottleMin
    Set-TurboBoost $default.TurboBoostEnabled
    Write-Host "System restored to default settings." -ForegroundColor Green
    Start-Sleep -Seconds 2
}

# --- Glavno Meni ---
function Show-MainMenu {
    Clear-Host
    Write-Host "=== Main Menu ===" -ForegroundColor Cyan
    Write-Host "[1] ThrottleStop Profile Menu"
    Write-Host "[2] CPU Performance Menu"
    Write-Host "[3] Exit"
    Write-Host ""
}

# --- Glavna logika ---
SaveDefaultSettingsIfNeeded

do {
    Show-MainMenu
    $choice = Read-Host "Enter selection"
    switch ($choice) {
        "1" {
            $continueTS = $true
            while ($continueTS) {
                $continueTS = ThrottleStopMenu
            }
        }
        "2" {
            do {
                Show-CPUMenu
                $cpuChoice = Read-Host "Enter selection"
                switch ($cpuChoice) {
                    "1" {
                        Set-CPUThrottle 60 30
                        Set-TurboBoost $false
                        Write-Host "i3 Mode applied." -ForegroundColor Green
                        Write-Host "Press any key to continue..." -ForegroundColor Yellow
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                    "2" {
                        Set-CPUThrottle 85 30
                        Set-TurboBoost $true
                        Write-Host "i5 Mode applied." -ForegroundColor Green
                        Write-Host "Press any key to continue..." -ForegroundColor Yellow
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                    "3" { CustomCPUMode }
                    "4" { ResetToDefault }
                    "5" { Show-CurrentCPUStatus }
                    "6" { break }
                    default {
                        Write-Host "Invalid option. Try again." -ForegroundColor Red
                        Start-Sleep -Seconds 2
                    }
                }
            } while ($cpuChoice -ne "6")
        }
        "3" {
            Write-Host "Exiting the script!" -ForegroundColor Cyan
            exit
        }
        default {
            Write-Host "Invalid option. Try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($true)

### powercfg.exe -attributes sub_processor perfboostmode -attrib_hide   da se prikazat turbo boost 

### powercfg.exe -attributes sub_processor perfboostmode +attrib_hide   da se sokrie turbo boost