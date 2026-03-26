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

### === Патеки и имиња ===
$PiNodePath = "C:\Users\ASUS\AppData\Local\Programs\pi-network-desktop"
$PiNodeExecutable = "Pi Network.exe"
$PiNodeFullPath = Join-Path $PiNodePath $PiNodeExecutable

### === Помошна функција за печатење ако не е Silent ===
function Write-Log {
    param ([string]$Message, [ConsoleColor]$Color = "White")
#    if (-not $Silent) {
        Write-Host $Message -ForegroundColor $Color
#    }
}

### === START PI NODE ===
function Start-PiNode {
    if (-Not (Test-Path $PiNodeFullPath)) {
        Write-Log "Pi Network executable not found at: $PiNodeFullPath" Red
        return
    }
    try {
        Get-Process -Name "Pi Network" -ErrorAction Stop | Out-Null
        Write-Log "Pi Network Node is already running!" Yellow
    } catch {
        Write-Log "Starting Pi Network Node..." White
        try {
            Start-Process -FilePath $PiNodeFullPath
            Write-Log "Pi Network Node started successfully." Green
        } catch {
            Write-Log "Failed to start Pi Network Node. Error: $_" Red
        }
    }
}

### === STOP PI NODE ===
function Stop-PiNode {
    try {
        Get-Process -Name "Pi Network" -ErrorAction Stop | Stop-Process -Force
        Write-Log "Pi Network Node stopped successfully." Green
    } catch {
        Write-Log "Pi Network Node is not running or could not be stopped." Yellow
    }
}

### === RESTART PI NODE ===
function Restart-PiNode {
    Write-Log "Restarting Pi Network Node..." White
    Stop-PiNode
    Start-Sleep -Seconds 3
    Start-PiNode
}

### === STATUS PI NODE ===
function Get-PiNodeStatus {
    try {
        Get-Process -Name "Pi Network" -ErrorAction Stop | Out-Null
        Write-Log "Pi Network Node is currently running." Green
    } catch {
        Write-Log "Pi Network Node is not running." Red
    }
}

### === START UP PI NODE DISABLED ===
function Disable-PiNodeStartup {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Write-Host "`n=== Disabling Pi Network from all startup sources ===" -ForegroundColor Cyan

    $piFolderPath = "C:\Users\ASUS\AppData\Local\Programs\pi-network-desktop"
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"

    # --- 1. Remove all registry startup entries ---
    $regPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    )

    foreach ($regPath in $regPaths) {
        try {
            $props = Get-ItemProperty -Path $regPath
            foreach ($name in $props.PSObject.Properties.Name) {
                $value = $props.$name
                if ($value -like "*pi-network-desktop*") {
                    Remove-ItemProperty -Path $regPath -Name $name -ErrorAction SilentlyContinue
                    Write-Host "Removed registry startup entry: $name from $regPath" -ForegroundColor Green
                }
            }
        } catch {
            Write-Host " Could not access $regPath - $_" -ForegroundColor DarkYellow
        }
    }

    # --- 2. Remove shortcut from Startup folder ---
    try {
        $shortcuts = Get-ChildItem $startupFolder -Filter *.lnk -ErrorAction SilentlyContinue
        foreach ($shortcut in $shortcuts) {
            $shell = New-Object -ComObject WScript.Shell
            $target = $shell.CreateShortcut($shortcut.FullName).TargetPath
            if ($target -like "*pi-network-desktop*") {
                Remove-Item $shortcut.FullName -Force
                Write-Host "Removed startup shortcut: $($shortcut.Name)" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "Error while checking startup folder: $_" -ForegroundColor Red
    }

    # --- 3. Identify (but do not modify) scheduled tasks related to Pi ---
    try {
        $piTasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*Pi*" -or $_.TaskPath -like "*Pi*" }
        if ($piTasks) {
            foreach ($task in $piTasks) {
                Write-Host " Found scheduled task: $($task.TaskName) (State: $($task.State))" -ForegroundColor Cyan
            }
        } else {
            Write-Host " No scheduled tasks found for Pi Network." -ForegroundColor Yellow
        }
    } catch {
        Write-Host " Error accessing scheduled tasks: $_" -ForegroundColor Red
    }

    # --- 4. Stop running process (optional) ---
    try {
        $proc = Get-Process | Where-Object { $_.Path -like "*pi-network-desktop*" }
        if ($proc) {
            $proc | Stop-Process -Force
            Write-Host "Pi Network process has been stopped." -ForegroundColor Green
        } else {
            Write-Host "No running Pi Network process found." -ForegroundColor Yellow
        }
    } catch {
        Write-Host " Error stopping Pi Network process: $_" -ForegroundColor Red
    }

    Write-Host "`nPi Network startup entries (except scheduled tasks) should now be fully disabled." -ForegroundColor Cyan
}

### === CLEAR CACHE PI NODE ==
function Clear-PiNodeCache {
    $pathsToClear = @(
        "$env:APPDATA\Pi Network",
        "$env:LOCALAPPDATA\Pi Network",
        "$env:TEMP\pi*"
    )

    $totalSize = 0
    $totalFiles = 0

    foreach ($path in $pathsToClear) {
        $resolvedPaths = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        if ($resolvedPaths) {
            foreach ($item in $resolvedPaths) {
                try {
                    $size = 0
                    if ($item.PSIsContainer) {
                        $childItems = Get-ChildItem -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        if ($childItems) {
                            $size = ($childItems | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
                        }
                        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                    } else {
                        $size = $item.Length
                        Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                    }

                    $totalFiles++
                    $totalSize += ($size -as [double])
                } catch {
                    Write-Log "Cannot delete: $($item.FullName) - $_" Yellow
                }
            }
            Write-Log "Cache cleared in: $path" Green
        } else {
            Write-Log "No cache found in: $path" Gray
        }
    }

    # Pretvoranje golemina
    if ($totalSize -gt 1GB) {
        $sizeStr = "{0:N2} GB" -f ($totalSize / 1GB)
    } elseif ($totalSize -gt 1MB) {
        $sizeStr = "{0:N2} MB" -f ($totalSize / 1MB)
    } else {
        $sizeStr = "{0:N2} KB" -f ($totalSize / 1KB)
    }

    Write-Log "`nDeleted $totalFiles files with a total size of $sizeStr." Cyan
}

### === Опции мапирање ===
$FunctionMap = @{
    "1" = { Start-PiNode }
    "2" = { Get-PiNodeStatus }
    "3" = { Stop-PiNode }
    "4" = { Restart-PiNode }
    "5" = { Disable-PiNodeStartup }
    "6" = { Clear-PiNodeCache }
}

### === Автоматско извршување ако има параметри ===
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

### === MENU ===
function Show-Menu {
    do {
        Clear
        Write-Host ""
        Write-Host "============ Pi Network Node Management ============" -ForegroundColor Cyan
        Write-Host ""
        Write-Host " [1] Start Pi Network Node" -ForegroundColor Green
        Write-Host " [2] Check Pi Network Node Status" -ForegroundColor Yellow
        Write-Host " [3] Stop Pi Network Node" -ForegroundColor Red
        Write-Host " [4] Restart Pi Network Node" -ForegroundColor Magenta
        Write-Host " [5] Disable Pi Network Startup" -ForegroundColor DarkRed
        Write-Host " [6] Clear Pi Network Cache" -ForegroundColor Blue
        Write-Host " [7] Exit" -ForegroundColor Gray
        Write-Host ""
        $selection = Read-Host "Enter a number (1-7) to select"

        if ($selection -eq "7") {
            Write-Log "Exiting..." White
            break
        }

        if ($FunctionMap.ContainsKey($selection)) {
            & $FunctionMap[$selection]
        } else {
            Write-Log "Invalid option, please select a valid number." Red
        }

        Read-Host "Press Enter to continue..."
    } while ($true)
}

# === Старт на мени ако нема AutoRunOps ===
Show-Menu

######################################################################################### Pi Script End.

