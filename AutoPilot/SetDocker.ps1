param (
    [string[]]$AutoRunOps = @()
)

### Check if script is run as Administrator
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "The script must be run as Administrator!"
    if (-not $Silent) { Pause }
    Exit
}

# Path to JSON config
$configPath = "$PSScriptRoot\JSON\settings_scripts.json"
if (-not (Test-Path $configPath)) {
    Write-Host "Config file does not exist: $configPath" -ForegroundColor Red
    Pause
    return
}
try {
    $config = Get-Content $configPath | ConvertFrom-Json
} catch {
    Write-Host "Cannot read config file. Error: $_" -ForegroundColor Red
    Pause
    return
}

# Read JSON config
$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

# Dynamic paths from JSON
$dockerPath  = $config.DockerDesktopPath
$swapFolder  = $config.SwapFolderPath
$swapFilePath = Join-Path -Path $swapFolder -ChildPath "swap.vhdx"

### Path for status file logging
$statusFile = Join-Path -Path $PSScriptRoot -ChildPath "Autopilot_Data\Setdocker-status.txt"

### Write-Status Function
function Write-Status {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $statusFile -Encoding UTF8 -Append
}

### Function to display interactive menu
function Show-Menu {
    Clear-Host
    Write-Host "`n`n==== Docker Configuration Menu ====" -ForegroundColor Cyan
    Write-Host "1. Set Docker Resources (RAM, CPU, SWAP)" -ForegroundColor Green
    Write-Host "2. View Status" -ForegroundColor Yellow
    Write-Host "3. Exit" -ForegroundColor Red

    $choice = Read-Host "Please select an option (1, 2, or 3)"

    switch ($choice) {
        1 { Set-DockerResources }
        2 { View-Status }
        3 { Write-Host "Exiting..." -ForegroundColor Magenta; exit 0 }
        default {
            Write-Host "Invalid choice, please try again." -ForegroundColor DarkYellow
            Show-Menu
        }
    }
}

### Function to get valid input (RAM, CPU, SWAP)
function Get-ValidInput {
    param (
        [string]$prompt,
        [string]$type
    )

    $validInput = $false
    $input = ""

    while (-not $validInput) {
        # Prompt user for input
        $input = Read-Host $prompt
        Write-Host "Debug: Raw input for ${type}: '$input'"

        # Remove unwanted characters
        $input = $input.Trim()

        # Check for empty input
        if (-not $input) {
            Write-Host "$type cannot be empty. Please enter a valid value."
            continue
        }

        # Безбедно парсирање (НЕ фрла exception)
        [int]$parsedValue = 0
        $isNumber = [int]::TryParse($input, [ref]$parsedValue)

        # Validate based on type (RAM, CPU, SWAP)
        switch ($type) {
            "RAM" {
                if ($isNumber -and $parsedValue -ge 1 -and $parsedValue -le 999) {
                    $validInput = $true
                    $input = "$parsedValue" + "GB"
                } else {
                    Write-Host "RAM must be a valid number greater than 0 and less than or equal to 999."
                }
                break
            }
            "CPU" {
                if ($isNumber -and $parsedValue -ge 1 -and $parsedValue -le 999) {
                    $validInput = $true
                    $input = "$parsedValue"
                } else {
                    Write-Host "CPU must be a valid number between 1 and 999."
                }
                break
            }
            "SWAP" {
                if ($isNumber -and $parsedValue -ge 1 -and $parsedValue -le 999) {
                    $validInput = $true
                    $input = "$parsedValue" + "GB"
                } else {
                    Write-Host "SWAP must be a valid number between 1 and 999."
                }
                break
            }
            default {
                Write-Host "Unknown type. Please ensure you specify RAM, CPU, or SWAP correctly."
                break
            }
        }
    }

    return $input
}

### Function to set Docker resources (RAM, CPU, SWAP)
function Set-DockerResources {
    Write-Host "`nSetting WSL2 resources for Docker Desktop (manual input)`n" -ForegroundColor Yellow

    # Getting valid input for RAM
    $memory = Get-ValidInput -prompt "Enter RAM memory (e.g., 2, 4):" -type "RAM"

    # Getting valid input for CPU
    $cpus   = Get-ValidInput -prompt "Enter the number of CPU cores (e.g., 2, 4):" -type "CPU"

    # Getting valid input for SWAP
    $swap   = Get-ValidInput -prompt "Enter SWAP memory (e.g., 1, 0):" -type "SWAP"

    Write-Host "Successfully gathered valid inputs:"
    Write-Host "RAM: $memory"
    Write-Host "CPU: $cpus"
    Write-Host "SWAP: $swap"

    Write-Status "Started configuration with RAM=$memory, CPU=$cpus, SWAP=$swap"

    # Define paths for swap file and .wslconfig
    $swapFolder  = $config.SwapFolderPath
    $swapFilePath = Join-Path -Path $swapFolder -ChildPath "swap.vhdx"

    # Check if swap folder exists and create if not
    if (-Not (Test-Path -Path $swapFolder)) {
        Write-Host "Folder doesn't exist. Creating: $swapFolder" -ForegroundColor Red
        New-Item -ItemType Directory -Path $swapFolder -Force | Out-Null
        Write-Status "Created swap folder: $swapFolder"
    } else {
        Write-Host "Folder already exists: $swapFolder" -ForegroundColor Green
        Write-Status "Swap folder already exists: $swapFolder"
    }

    # Escape backslashes in swapFile path
      $escapedSwapFilePath = $swapFilePath.Split('\') -join '\\'  #  $swapFilePath -replace '\\', '\\\\' 

    # Prepare .wslconfig file content
    $wslConfigPath = Join-Path -Path $env:USERPROFILE -ChildPath ".wslconfig"
    $wslContent = @"
[wsl2]
memory=$memory
processors=$cpus
swap=$swap
swapFile=$escapedSwapFilePath
localhostForwarding=true
"@

    # Write .wslconfig file
    Write-Host "Writing .wslconfig file to: $wslConfigPath" -ForegroundColor Cyan
    $wslContent | Set-Content -Encoding UTF8 -Path $wslConfigPath -Force
    Write-Status "Created .wslconfig file at $wslConfigPath"

    # Restart WSL
    Write-Host "Restarting WSL..." -ForegroundColor Magenta
    wsl --shutdown
    Write-Status "WSL restarted"

    # Start Docker Desktop
    $dockerPath  = $config.DockerDesktopPath
    Write-Host "Starting Docker Desktop..." -ForegroundColor Green

    if (Test-Path $dockerPath) {
        Start-Process -FilePath $dockerPath
        Write-Host "Docker Desktop started from: $dockerPath" -ForegroundColor Cyan
        Write-Status "Docker Desktop started from $dockerPath"
    } else {
        Write-Host "Docker Desktop not found!" -ForegroundColor Red
        Write-Host "Check location: $dockerPath" -ForegroundColor Red
        Write-Status "Error: Docker Desktop not found at $dockerPath"
    }

    # Final message
    Write-Host "`nAll done. Docker Desktop now uses:" -ForegroundColor Cyan
    Write-Host "RAM: $memory" -ForegroundColor Green
    Write-Host "CPU: $cpus cores" -ForegroundColor Green
    Write-Host "SWAP: $swap" -ForegroundColor Green
    Write-Host "SWAP file: $swapFilePath" -ForegroundColor Green
    Write-Status "Configuration completed with RAM=$memory, CPU=$cpus, SWAP=$swap"

    # Show return prompt after execution
    Write-Host "`nPress ENTER to return to the main menu..." -ForegroundColor Yellow
    Read-Host | Out-Null
    Show-Menu
}

### Function to view status from the status file
function View-Status {
    # Check if the status file exists and display the latest status
    if (Test-Path $statusFile) {
        # Read the content and get the last line (the most recent configuration)
        $status = Get-Content $statusFile | Select-Object -Last 1
        Write-Host "`n=== Latest Configuration ===" -ForegroundColor Cyan
        Write-Host $status -ForegroundColor Green
    } else {
        Write-Host "Status file does not exist." -ForegroundColor Red
    }

    # Show details for RAM, CPU, and SWAP from .wslconfig
    $wslConfigPath = Join-Path -Path $env:USERPROFILE -ChildPath ".wslconfig"
    if (Test-Path $wslConfigPath) {
        $wslConfig = Get-Content -Path $wslConfigPath
        Write-Host "`n=== .wslconfig Configuration ===" -ForegroundColor Cyan
        Write-Host $wslConfig -ForegroundColor Green
    } else {
        Write-Host ".wslconfig file not found!" -ForegroundColor Red
    }

    # Check the swap folder
    $swapFolder  = $config.SwapFolderPath
    if (Test-Path $swapFolder) {
        Write-Host "`n=== Swap Folder ===" -ForegroundColor Cyan
        Write-Host "Folder exists: $swapFolder" -ForegroundColor Green
    } else {
        Write-Host "Swap folder does not exist!" -ForegroundColor Red
    }

    # Show return prompt after viewing status
    Write-Host "`nPress ENTER to return to the main menu..." -ForegroundColor Yellow
    Read-Host | Out-Null
    Show-Menu
}

# If the script is run with arguments, skip the menu and directly handle operations
if ($AutoRunOps.Count -eq 1 -and $AutoRunOps[0].ToLower() -eq '-status') {
    View-Status
} else {
    Show-Menu
}
# Auto select option #

############################################################################## SetDocker Script End.