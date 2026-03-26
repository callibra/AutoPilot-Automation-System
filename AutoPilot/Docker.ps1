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

### Помошна функција за печатење ако не е Silent 
function Write-Log {
    param ([string]$Message, [ConsoleColor]$Color = "White")
#    if (-not $Silent) {
        Write-Host $Message -ForegroundColor $Color
#    }
}

### Color Output Functions 
function Write-Info {
    param (
        [string]$msg,
        [string]$color = "Cyan"
    )
    Write-Host $msg -ForegroundColor $color
}

### Color Functions 
function Write-Ok   { param($msg) ; Write-Host $msg -ForegroundColor Green }
function Write-Warn { param($msg) ; Write-Host $msg -ForegroundColor Yellow }
function Write-Err  { param($msg) ; Write-Host $msg -ForegroundColor Red }

# Читање на конфигурациски фајл
$configFile = "$PSScriptRoot\JSON\settings_scripts.json"
if (-not (Test-Path $configFile)) {
    Write-Err "Config file does not exist: $configFile"
    exit
}
try {
    $config = Get-Content $configFile | ConvertFrom-Json
} catch {
    Write-Err "Cannot read config file. Error: $_"
    exit
}

# Патеките и контејнерите се зачувуваат во променливи
$DockerDesktopPath = $config.DockerPath
$DockerCliPath     = $config.DockerCliPath
$ContainerList     = $config.Containers

### Function Write-Info
function Write-Info($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
}
function Write-Warn($msg) {
    Write-Host $msg -ForegroundColor Red
}

function Start-PiNode         { Write-Info "Pi Node Starting" "Green" }
function Stop-PiNode          { Write-Info "Pi Node Stoping" "Red" }
function Restart-PiNode       { Write-Info "Pi Node Restarting" "Yellow" }
function Status-PiNode        { Write-Info "Pi node Status" "Cyan" }
function Start-Docker         { Write-Info "Docker Starting" "Green" }
function Restart-Docker       { Write-Info "Docker Restarting" "Yellow" }
function Stop-Docker          { Write-Info "Docker Stoping" "Red" }
function Check-Status         { Write-Info "Docker Status" "Cyan" }
function Clear-DockerCache    { Write-Info "Docker Cache Cleaning" "Green" }
function Clear-TempFolder     { Write-Info "Temp Folder Cache Cleaning" "Green" }

### MAIN FUNCTION
function Run-Option($op) {
    switch ($op) {
        "1"  { Start-PiNode }
        "2"  { Stop-PiNode }
        "3"  { Restart-PiNode }
        "4"  { Status-PiNode }
        "5"  { Start-Docker }
        "6"  { Restart-Docker }
        "7"  { Stop-Docker }
        "8"  { Check-Status }
        "9"  {
            Write-Info "Clearing Docker Cache is starting..." "Yellow"
            Clear-DockerCache
            Write-Info "Clearing Docker Cache is complete." "Green"
        }
        "10" {
            Write-Info "Clearing Temp folder is starting..." "Yellow"
            Clear-TempFolder
            Write-Info "Clearing Temp folder is complete." "Green"
        }
        "11" {
            Write-Info "Exiting the script..." "Green"
            exit
        }
        default {
            Write-Warn "Unknown option: $op"
        }
    }
}

### MENU
function Show-Menu {
    Clear-Host
    $line = '=' * 90
    $sectionDivider = '-' * 90

    Write-Host "`n$line" -ForegroundColor DarkGray
    Write-Host ("{0,45}" -f "Docker and Pi Network Node") -ForegroundColor Blue
    Write-Host "$line" -ForegroundColor DarkGray

    Write-Host "`=== PI NETWORK NODE ===" -ForegroundColor Cyan
    Write-Host "  [1] Start Pi Node" -ForegroundColor Green
    Write-Host "  [2] Stop Pi Node" -ForegroundColor Red
    Write-Host "  [3] Restart Pi Node" -ForegroundColor Yellow
    Write-Host "  [4] Status Pi Node" -ForegroundColor Cyan
    Write-Host ""  
    Write-Host "`=== DOCKER ===" -ForegroundColor Cyan
    Write-Host "  [5] Start Docker" -ForegroundColor Green
    Write-Host "  [6] Restart Docker" -ForegroundColor Yellow
    Write-Host "  [7] Stop Docker" -ForegroundColor Red
    Write-Host "  [8] Status Docker" -ForegroundColor Cyan
    Write-Host ""  
    Write-Host "`=== MAINTENANCE ===" -ForegroundColor Cyan
    Write-Host "  [9] Clean Docker CACHE" -ForegroundColor Magenta
    Write-Host "  [10] Clean TEMP Folder" -ForegroundColor Magenta

    Write-Host "  [11] Exit" -ForegroundColor White

    Write-Host "`n$sectionDivider" -ForegroundColor DarkGray
    Write-Host ("{0,45}" -f "Enter a number for selection...") -ForegroundColor Yellow
}

##### PI NODE CONTAINER FUNCTION #####

### Test Docker
function Test-DockerReady {
    docker info >$null 2>&1
    return ($LASTEXITCODE -eq 0)
}

### Start PiNode 
function Start-PiNode {
    if (-not (Test-DockerReady)) {
        Write-Warning "Docker Engine is not Started. Containers cannot be Started."
        return
    }
    foreach ($container in $ContainerList) {
        Write-Info "Checking Pi Node '$container'..."
        # Proverka dali kontejnerot postoi
        $exists = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq $container }
        if (-not $exists) {
            Write-Warn "Pi Node '$container' does not exist in Docker. Starting is skipped."
            continue
        }
        # Proverka dali e veќе aktiviran
        $status = docker inspect -f "{{.State.Running}}" $container 2>$null
        if ($status -eq "true") {
            Write-Warn "Pi Node '$container' already Activated."
        } else {
            # Startuvanje bez da se prikazuva stderr
            docker start $container 2>$null | Out-Null
            Start-Sleep -Seconds 2
            Write-Ok "Pi Node '$container' is Started."
        }
    }
}

### Stop PiNode  
function Stop-PiNode {
    if (-not (Test-DockerReady)) {
        Write-Warning "Docker Engine is not Started. Containers cannot be Stopped."
        return
    }
    foreach ($container in $ContainerList) {
        Write-Info "Checking Pi Node '$container'..."
        # Proverka dali kontejnerot postoi
        $exists = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq $container }
        if (-not $exists) {
            Write-Warn "Pi Node '$container' does not exist in Docker. Stopping is skipped."
            continue
        }
        # Proverka dali e aktiviran
        $status = docker inspect -f "{{.State.Running}}" $container 2>$null
        if ($status -eq "true") {
            docker stop $container 2>$null | Out-Null
            Start-Sleep -Seconds 2
            Write-Ok "Pi Node '$container' is Stopped."
        } else {
            Write-Warn "Pi Node '$container' already Stopped."
        }
    }
}

### Restart PiNode  
function Restart-PiNode {
    if (-not (Test-DockerReady)) {
        Write-Warning "Docker Engine is not Started. Containers cannot be Restarted."
        return
    }
    foreach ($container in $ContainerList) {
        Write-Info "Checking Pi Node '$container'..."
        # Proverka dali kontejnerot postoi
        $exists = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq $container }
        if (-not $exists) {
            Write-Warn "Pi Node '$container' does not exist in Docker. Restart is skipped."
            continue
        }
        # Dobivanje na statusot
        $containerStatus = docker inspect --format '{{.State.Status}}' $container 2>$null

        if ($containerStatus -eq "exited") {
            Write-Warn "Pi Node '$container' it is turned off and cannot be Restarted."
        } else {
            Write-Info "Restarting of '$container'..."
            docker restart $container 2>$null | Out-Null
            Start-Sleep -Seconds 2
            Write-Ok "Pi Node '$container' is Restarted."
        }
    }
}

### Status PiNode  
function Status-PiNode {
    if (-not (Test-DockerReady)) {
        Write-Warning "Docker Engine is not Started. Status cannot be checked."
        return
    }
    foreach ($container in $ContainerList) {
        Write-Info "Checking Pi Node '$container'..."
        # Proverka dali kontejnerot postoi
        $exists = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq $container }
        if (-not $exists) {
            Write-Warn "Pi Node '$container' does not exist in Docker."
            continue
        }
        # Povikuvame inspect bez da gi prikazuvame Docker errors
        $status = docker inspect --format '{{.State.Status}}' $container 2>$null
        $uptimeRaw = docker inspect --format '{{.State.StartedAt}}' $container 2>$null

        if ($status -eq "running") {
            $uptime = [DateTime]::Parse($uptimeRaw).ToLocalTime()
            Write-Ok "Pi Node '$container' Is ACTIVE."
            Write-Host "Started at $uptime"
        } else {
            Write-Warning "Pi Node '$container' is in state: $status"
        }
    }
}

##### DOCKER FUNCTION #####

### Start Docker  
function Start-Docker {
    Write-Host "`n=== STARTING DOCKER AND CONTAINERS ===`n" -ForegroundColor White
    # Проверка дали Docker Desktop е веќе активен
    $dockerRunning = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if ($dockerRunning) {
        Write-Ok "Docker Desktop is currently Active. No need to Start it again."
        return
    }

    function Wait-ForDockerReady {
        param (
            [int]$maxTries = 10,
            [int]$delaySeconds = 5
        )
        $tryCount = 0
        while ($tryCount -lt $maxTries) {
            docker info >$null 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Docker became Active after $tryCount attempts."
                return $true
            }
            $tryCount++
            Write-Warn "Docker is still not Active... waiting $delaySeconds seconds..."
            Start-Sleep -Seconds $delaySeconds
        }
        return $false
    }

    function Force-RestartDocker {
        Write-Warn "Performing Forced shutdown of Docker Desktop..."
        $dockerProcesses = Get-Process -Name "Docker Desktop", "com.docker.backend", "com.docker.build" -ErrorAction SilentlyContinue
        foreach ($proc in $dockerProcesses) {
            try {
                Stop-Process -Id $proc.Id -Force
                Write-Ok "$($proc.Name) is Force-Stopped."
            } catch {
                Write-Err "Cannot be Stopped $($proc.Name). Error: $_"
            }
        }
        Start-Sleep -Seconds 5
        Write-Info "Restarting Docker Desktop..."
        try {
            Start-Process $DockerDesktopPath
            Write-Ok "Docker Desktop is Started."
        } catch {
            Write-Err "Cannot start Docker Desktop. Check the Path."
            return $false
        }
        Start-Sleep -Seconds 15
        return Wait-ForDockerReady
    }

    # Стартување на Docker Desktop
    Write-Info "Docker Desktop is not Active. Starting..."
    try {
        Start-Process $DockerDesktopPath
        Write-Ok "Docker Desktop is Started."
    } catch {
        Write-Err "Cannot start Docker Desktop. Check the Path."
        return
    }

    # Чекање Docker да се подигне
    Write-Info "Waiting 15 seconds for Docker to Start..."
    Start-Sleep -Seconds 15

    if (-not (Wait-ForDockerReady)) {
        Write-Warn "Docker is not Starting. Attempting Forced Restart..."
        if (-not (Force-RestartDocker)) {
            Write-Err "Docker failed to restart. Aborting."
            return
        }
    }
    Write-Ok "Docker is Active and Ready."

    # Стартување на Docker контејнери
    Write-Info "Starting Docker Containers..."
    $containers = $ContainerList
    foreach ($container in $ContainerList) {
    # Proverka dali kontejnerot postoi
    $exists = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq $container }
    if (-not $exists) {
        Write-Warn "$container Does not exist in Docker. Starting is skipped."
        continue
    }
    $containerStatus = docker inspect --format '{{.State.Running}}' $container 2>$null
    if ($containerStatus -eq "false") {
        Write-Info "Starting Container $container..."
        try {
            docker start $container | Out-Null
            Write-Ok "Container $container is Starting."
        } catch {
            Write-Err "Cannot Start $container. There is likely an Error."
        }
    } elseif ($containerStatus -eq "true") {
        Write-Ok "$container is already Started."
    } else {
        Write-Warn "$container there is a problem with Docker Inspect."
    }
  }
}

### Stop Docker  
function Stop-Docker {
    Write-Host "`n=== STOPPING DOCKER AND CONTAINERS ===" -ForegroundColor White
    # Проверка дали Docker Desktop е активен
    $dockerRunning = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if (!$dockerRunning) {
        Write-Ok "Docker Desktop is not active. No need to Stop It."
        Write-Host "`nDocker and Services are already Turned Off." -ForegroundColor Cyan
    } else {
        # Стопирање на Docker контејнери
        $containers = $ContainerList
        foreach ($container in $ContainerList) {
    # Proverka dali kontejnerot postoi
    $exists = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq $container }
    if (-not $exists) {
        Write-Warn "$container does not exist in Docker. Stopping is skipped."
        continue
    }
    $status = docker inspect --format '{{.State.Running}}' $container 2>$null
    if ($status -eq "true") {
        Write-Info "Stopping Container $container..."
        try {
            docker stop $container | Out-Null
            Write-Ok "Container $container is Stopped."
        } catch {
            Write-Warn "Cannot Stop $container. Attempting Again..."
            Start-Sleep -Seconds 5
        }
    } else {
        Write-Ok "$container is already Stopped."
    }
}

	# Shutdown со timeout и fallback
	Write-Info "Turning Off Docker Desktop..."
	$shutdownOK = $false

	# --- Додадено: безопасно насилно затворање без -Shutdown ---
	Get-Process -Name "Docker Desktop", "com.docker.backend", "com.docker.build" -ErrorAction SilentlyContinue | ForEach-Object {
		try {
			Stop-Process -Id $_.Id -Force
			Write-Warn "$($_.Name) Force Turned Off."
			$shutdownOK = $true
		} catch {
			Write-Warn "Cannot close process: $($_.Name)"
		}
	}
	if (-not $shutdownOK) {
		Write-Warn "Docker Desktop failed to Turn Off."
	}
    }

    # Shutdown WSL backend
    Write-Info "Shutting down WSL2 backend..."
    try {
        wsl --shutdown
        Write-Ok "WSL2 backend is Turned Off."
    } catch {
        Write-Warn "Failed to turn off WSL2 backend."
    }

    Write-Ok "`nAll Docker processes and WSL have been successfully Turned Off."
}

### Restart Docker  
function Restart-Docker {
    Write-Host "`n=== RESTARTING DOCKER AND CONTAINERS ===`n" -ForegroundColor White
    $dockerRunning = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if (!$dockerRunning) {
        Write-Info "Docker Desktop is not Active. Cannot be Restarted." 
        return
    }

    Write-Info "Docker Desktop is currently Active."

    # Stop Docker build processes if running
    $dockerBuildProcesses = Get-Process -Name "com.docker.build" -ErrorAction SilentlyContinue
    if ($dockerBuildProcesses) {
        Write-Info "Docker build processes are Running. Stopping them..."
        $dockerBuildProcesses | Stop-Process -Force
    }

    # Stop containers
    Write-Info "Stopping current Docker Containers..."
	$containers = $ContainerList
	foreach ($container in $containers) {
    # Proverka dali kontejnerot postoi
    $exists = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq $container }
    if (-not $exists) {
        Write-Warn "$container does not exist in Docker. Stopping is skipped."
        continue
    }
    $containerStatus = docker inspect --format '{{.State.Running}}' $container 2>$null
    if ($containerStatus -eq "true") {
        Write-Info "Stopping Container $container..."
        try {
            docker stop $container | Out-Null
            Write-Ok "Container $container is Stopped."
        } catch {
            Write-Warn "Cannot stop $container. Attempting Again..."
            Start-Sleep -Seconds 5
        }
    } else {
        Write-Ok "$container is already Stopped."
    }
}

    # === STOP NA DOCKER DESKTOP  ===
    Write-Info "Turning off Docker Desktop..."
    $shutdownOK = $false

    # Безопасно насилно затворање
    Get-Process -Name "Docker Desktop", "com.docker.backend", "com.docker.build" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Stop-Process -Id $_.Id -Force
            Write-Warn "$($_.Name) Force Turned Off."
            $shutdownOK = $true
        } catch {
            Write-Warn "Cannot close process: $($_.Name)"
        }
    }

    if (-not $shutdownOK) {
        Write-Warn "Docker Desktop failed to Turn Off."
    }

    # Shutdown WSL backend
    Write-Info "Shutting down WSL2 backend..."
    try {
        wsl --shutdown
        Write-Ok "WSL2 backend is Turned Off."
    } catch {
        Write-Warn "Failed to turn off WSL2 backend."
    }
    Write-Info "Waiting 10 seconds..."
    Start-Sleep -Seconds 10

    # Start Docker Desktop
    Write-Info "Starting Docker Desktop..."
    Start-Process $DockerDesktopPath
    Write-Ok "Docker Desktop is Started."
    Write-Info "Waiting 30 seconds for Docker to Load..."
    Start-Sleep -Seconds 30

    # Wait for Docker to be ready
    $tryCount = 0
    $maxRetries = 30
    $waitTime = 5
    while ($true) {
        try {
            docker info >$null 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Docker is Active and Ready."
                break
            }
        } catch {
            Write-Warn "Docker is still not ready... waiting $waitTime seconds..."
        }
        $tryCount++
        if ($tryCount -ge $maxRetries) {
            Write-Err "Docker did not Start after multiple attempts. Aborting."
            return
        }
        Start-Sleep -Seconds $waitTime
    }

	# Start containers
	Write-Info "Starting Docker containers..."
	foreach ($container in $containers) {
    # Proverka dali kontejnerot postoi
    $exists = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq $container }
    if (-not $exists) {
        Write-Warn "$container does not exist in Docker. Starting is skipped."
        continue
    }
    $containerStatus = docker inspect --format '{{.State.Running}}' $container 2>$null
    if ($containerStatus -eq "false") {
        Write-Info "Starting Container $container..."
        try {
            docker start $container | Out-Null
            Write-Ok "Container $container is Starting."
        } catch {
            Write-Warn "Cannot Start $container. Attempting Again..."
            Start-Sleep -Seconds 5
        }
    } else {
        Write-Ok "$container is already Started."
    }
}
    Write-Ok "`nDocker Desktop and Containers have been successfully Restarted."
}

### Status Docker  
function Check-Status {
    Write-Host "`n=== DOCKER / WSL / CONTAINER STATUS ===`n" -ForegroundColor White
    if (-not (Get-Variable Silent -Scope Global -ErrorAction SilentlyContinue)) {
        $Silent = $false
    }

    # Docker Desktop status
    Write-Info "`n[1] Docker Desktop status:"
    $d1 = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    $d2 = Get-Process -Name "com.docker.backend" -ErrorAction SilentlyContinue
    if ($d1 -or $d2) {
        Write-Ok "Docker is ACTIVE."
    } else {
        Write-Warn "Docker is NOT Active. Check if Docker is Installed or Enabled."
    }

    # Docker Engine status
	Write-Info "`n[2] Docker Engine status:"
	try {
    # Proverka dali Docker daemon e podignat
    $dockerAlive = docker version --format '{{.Server.Version}}' 2>$null
    if ($dockerAlive) {
        Write-Ok "Docker Engine is ACTIVE."
    } else {
        Write-Warn "Docker Engine is NOT Active or the command is not available."
    }
	} catch {
		Write-Warn "Docker Engine is NOT Active or the command is not available."
	}

    # WSL backend status
    Write-Info "`n[3] WSL backend status:"
    try {
        $wsl = wsl -l -v 2>$null
        if ($wsl) {
            Write-Ok "WSL is ACTIVE."
        } else {
            Write-Warn "WSL is NOT Active. Check if WSL is Installed."
        }
    } catch {
        Write-Warn "WSL is NOT Active or no distributions are available. Check the WSL Installation."
    }

    # WSL сервис (LxssManager)
    Write-Info "`n[4] WSL service (LxssManager):"
    $svc = Get-Service -Name "LxssManager" -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "Status  : $($svc.Status)"
        Write-Host "Startup : $($svc.StartType)"
    } else {
        Write-Err "The LxssManager service does not exist (WSL may not be installed)."
    }

    # Aktivni Docker kontejneri
	Write-Info "`n[5] Active Docker Containers:"
	try {
    # proverka dali Docker e sprem
    $dockerAlive = docker version --format '{{.Server.Version}}' 2>$null
    if ($dockerAlive) {
        $containers = docker ps --format "{{.Names}}" 2>$null
        if ($containers) {
            Write-Ok "Active Containers:"
            $containers -split "`n" | ForEach-Object { Write-Host "- $_" }
        } else {
            Write-Warn "No Active Containers."
        }
    } else {
        Write-Warn "Docker Engine is NOT Active. Cannot check the List of Containers."
    }
	} catch {
		Write-Warn "Docker command is not Available. Docker is likely Turned Off."
	}

    # Docker GUI статус
    Write-Info "`n[6] Docker GUI status:"
    if ($d1) {
        Write-Ok "Docker Desktop GUI is ACTIVE."
    } else {
        Write-Warn "Docker Desktop GUI is NOT Active. Check if the Application is Open."
    }

    # Docker Daemon како процес
    Write-Info "`n[7] Docker Daemon status:"
    $daemonProc = Get-Process -Name "com.docker.backend" -ErrorAction SilentlyContinue
    if ($daemonProc) {
        Write-Ok "Docker Daemon (com.docker.backend) is ACTIVE."
    } else {
        Write-Warn "Docker Daemon is NOT Active."
    }

    # WSL сервис процес (wslservice.exe)
    Write-Info "`n[8] WSL service process (wslservice.exe):"
    $wslProc = Get-Process -Name "wslservice" -ErrorAction SilentlyContinue
    if ($wslProc) {
        Write-Ok "WSL service process is ACTIVE in Task Manager."
    } else {
        Write-Warn "WSL service process is NOT Active at the moment."
    }
}

### Funkcija za prikazuvanje na informacii vo boja
function Write-Info {
    param (
        [string]$message,
        [string]$color
    )
    if ($color -eq 'green') {
        Write-Host $message -ForegroundColor Green
    } elseif ($color -eq 'yellow') {
        Write-Host $message -ForegroundColor Yellow
    } elseif ($color -eq 'red') {
        Write-Host $message -ForegroundColor Red
    } else {
        Write-Host $message
    }
}

### Funkcija za konvertiranje vo MB ili GB
function Convert-BytesToMBGB {
    param ([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    else { return "{0:N2} KB" -f ($Bytes / 1KB) }
}

### Funkcija za brisenje na Docker cache
function Clear-DockerCache {
    Write-Info "Starting to Clear Docker Cache..." 'yellow'
    # DODADENO za JSON kompatibilnost
    $dockerCmd = $DockerCliPath

    try {
        & $dockerCmd info >$null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Docker is not Active. Aborting the Operation."
            return
        }
    } catch {
        Write-Warn "Docker Command is not available. Aborting the Operation."
        return
    }

    # Stopiranje kontejneri
    $running = & $dockerCmd ps -q
    if ($running) {
        $stoppedContainers = & $dockerCmd stop $running
        Write-Info "Stopped Containers: $($stoppedContainers.Count)" 'green'
    } else {
        Write-Warn "No Active Containers to Stop."
    }

    # Golemina i brisenje na kontejneri
    $containerSizeBefore = (& $dockerCmd ps -a --format "{{.Size}}" | ForEach-Object {
        $_ -match "(\d+)([A-Za-z]+)" | Out-Null
        switch ($matches[2]) {
            'MB' { [int]$matches[1] * 1MB }
            'GB' { [int]$matches[1] * 1GB }
            default { 0 }
        }
    } | Measure-Object -Sum).Sum

    $allContainers = & $dockerCmd ps -a -q
    if ($allContainers) {
        $removedContainers = & $dockerCmd rm $allContainers
        Write-Info "Deleted Containers: $($removedContainers.Count)" 'green'
    } else {
        Write-Warn "No Containers to Delete."
    }

    Write-Info "Size of Deleted Containers: $(Convert-BytesToMBGB $containerSizeBefore)" 'green'

    # Golemina i brisenje na sliki
    $imageSizeBefore = (& $dockerCmd images --format "{{.Size}}" | ForEach-Object {
        $_ -match "(\d+)([A-Za-z]+)" | Out-Null
        switch ($matches[2]) {
            'MB' { [int]$matches[1] * 1MB }
            'GB' { [int]$matches[1] * 1GB }
            default { 0 }
        }
    } | Measure-Object -Sum).Sum

    $allImages = & $dockerCmd images -q | Sort-Object -Unique
    if ($allImages) {
        $removedImages = & $dockerCmd rmi $allImages -f
        Write-Info "Deleted Images: $($removedImages.Count)" 'green'
    } else {
        Write-Warn "No Images to Delete."
    }

    Write-Info "Size of Deleted Images: $(Convert-BytesToMBGB $imageSizeBefore)" 'green'

    & $dockerCmd builder prune -f >$null
    Write-Info "Build Cache Deleted." 'green'

    & $dockerCmd volume prune -f >$null
    Write-Info "Unnecessary Volumes Deleted." 'green'

    & $dockerCmd network prune -f >$null
    Write-Info "Unnecessary Networks Deleted." 'green'

    $totalSize = $containerSizeBefore + $imageSizeBefore
    Write-Info "Total Size of Deleted Objects: $(Convert-BytesToMBGB $totalSize)" 'green'

    Write-Info "Docker Cache Cleanup completed Successfully." 'yellow'
}

### Funkcija za brisenje na TempFolder
function Clear-TempFolder {
    $tempFolder = $env:TEMP 
    Write-Info "Starting to Delete the Temp Folder $tempFolder" 'yellow'

    if (Test-Path $tempFolder) {
        $files = Get-ChildItem $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        $failedFiles = @()
        $deletedFilesCount = 0
        $deletedFoldersCount = 0
        $totalDeletedSize = 0
        foreach ($file in $files) {
            try {
                $fileSize = if (-not $file.PSIsContainer) { $file.Length } else { 0 }
                Remove-Item $file.FullName -Force -Recurse -ErrorAction Stop
                if (-not $file.PSIsContainer) {
                    $deletedFilesCount++
                    $totalDeletedSize += $fileSize
                } else {
                    $deletedFoldersCount++
                }

                Write-Info "Successfully Deleted: $($file.FullName)" 'green'
            }
            catch {
                $failedFiles += $file.FullName
                Write-Info "Cannot Delete: $($file.FullName)" 'red'
            }
        }
        # Presmetka na osloboden prostor
        $totalDeletedSizeMB = [math]::Round($totalDeletedSize / 1MB, 2)
        $totalDeletedSizeGB = [math]::Round($totalDeletedSize / 1GB, 2)
        Write-Info "Deleted $deletedFilesCount Files and $deletedFoldersCount Folders." 'green'
        Write-Info "Total Space Freed: $totalDeletedSizeMB MB ($totalDeletedSizeGB GB)" 'green'
        if ($failedFiles.Count -gt 0) {
            Write-Info "`nThe following files could not be deleted:" 'red'
            $failedFiles | ForEach-Object { Write-Info $_ 'red' }
        } else {
            Write-Info "Temp Folder is fully Cleaned.." 'green'
        }
    } else {
        Write-Info "Temp Folder does not Exist: $tempFolder" 'red'
    }
}

# === Автоматски режим преку параметар ===
if ($AutoRunOps.Count -gt 0) {
    Write-Info "`n[AutoRun Mode is Active.] Operations: $($AutoRunOps -join ', ')" "Magenta"
    foreach ($op in $AutoRunOps) {
        Run-Option $op
    }
    Write-Info "`n[AutoRun Mode Completed]" "Magenta"
    if (-not $Silent) { Pause }
    exit
}

# === Интерактивен режим ===
do {
    Show-Menu
    $choice = Read-Host "Select an Option (1-11)"
    Run-Option $choice
    if (-not $Silent) { Pause }  # Pause
} while ($choice -ne "11")

######################################################################################################### Docker Script End.