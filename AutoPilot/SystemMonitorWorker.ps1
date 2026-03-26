param(
    [int]$SampleIntervalSeconds = $null,
    [string]$DllPath = "$PSScriptRoot\Dll\LibreHardwareMonitorLib.dll"
)

# === Path do JSON config ===
$configPath = "$PSScriptRoot\JSON\settings.json"

# === Load config safely ===
$config = $null
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Error parsing settings.json. Using default values."
        $config = $null
    }
} else {
    Write-Warning "settings.json not found. Using default values."
}

# === SampleIntervalSeconds (JSON → default) ===
if (-not $SampleIntervalSeconds) {
    if (
        $config -and
        $config.HardwareMonitor -and
        $config.HardwareMonitor.SampleIntervalSeconds -and
        ($config.HardwareMonitor.SampleIntervalSeconds -is [int]) -and
        ($config.HardwareMonitor.SampleIntervalSeconds -gt 0)
    ) {
        $SampleIntervalSeconds = $config.HardwareMonitor.SampleIntervalSeconds
    } else {
        $SampleIntervalSeconds = 300
    }
}

# Проверка за админ
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "The script must be run as Administrator!"
    if (-not $Silent) { Pause }
    Exit
}

# === Funktion for Temp ===
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
				if (-not $sensor.Value) { $null = $failures.Add("$($hardware.Name) - $($sensor.Name)") }
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
return $result
}

# Патека до AutoPilot.ps1
$autoPilotPath = Join-Path $PSScriptRoot "Autopilot.ps1"

# Cooldown од 500 секунди за CPU-friendly проверка
$autoCheckCooldown = 0
$autoPilotActive = $true

Add-Content -Path $Global:LogFile -Value "[${timestamp}] Monitoring has STARTED."

# === GLAVEN LOOP ===
while ($true) {
# --- Проверка дали AutoPilot.ps1 е активен (секои 500 секунди) ---
    if ($autoCheckCooldown -le 0) {
        $autoPilotActive = $false
        try {
            # земи ги сите powershell процеси
            $processes = Get-Process -Name "powershell" -ErrorAction SilentlyContinue
            foreach ($p in $processes) {
                try {
                    $procInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)"
                    if ($procInfo -and $procInfo.CommandLine -and
                        ($procInfo.CommandLine -match [regex]::Escape($autoPilotPath))) {

                        $autoPilotActive = $true
                        break
                    }
                } catch {
                    # Ignore единични грешки
                }
            }
        }
        catch {
            $autoPilotActive = $false
        }
        # следната проверка по 500 секунди
        $autoCheckCooldown = 500
    }
    # --- Ако AutoPilot не работи → Stop Monitoring ---
    if (-not $autoPilotActive) {

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        # секогаш пиши во истиот stop.flag
        $monitoringStopFlag = Join-Path $Global:monitoringLogsFolder "monitoring_stop.flag"
        Set-Content -Path $monitoringStopFlag -Value $timestamp -Encoding UTF8
        Write-Host "AutoPilot.ps1 not Active. Monitoring will Stop in $timestamp."
        Add-Content -Path $Global:LogFile -Value "[${timestamp}] AutoPilot.ps1 not Active. Monitoring STOPPED. Time: $timestamp"
        Add-Content -Path $Global:LogFile -Value "[${timestamp}] SystemMonitorWorker is Stopping because AutoPilot is not Running. Time: $timestamp"
        break
    }
    # намали cooldown според Sample interval
    $autoCheckCooldown -= $SampleIntervalSeconds
	
# --- Update hardware sensors using Get-Temperatures function ---
$tempData = Get-Temperatures -DllPath $DllPath

$cpuTempVal = $gpuTempVal = $mbTempVal = $null
$diskTemps = @{}

foreach ($item in $tempData) {
	if (-not $item.TemperatureC) { continue }  # прескокни ако нема вредност

	$tempRounded = [math]::Round([double]$item.TemperatureC, 2)  # заокружи на 1 децимала

	switch ($item.HardwareType) {
		"Cpu"         { $cpuTempVal = $tempRounded }
		"GpuAmd"      { $gpuTempVal = $tempRounded }
		"GpuNvidia"   { $gpuTempVal = $tempRounded }
		"Motherboard" { $mbTempVal  = $tempRounded }
		"Storage"     { $diskTemps[$item.HardwareName] = $tempRounded }
	}
}

# --- CPU / RAM Load ---
$ramUsage = (Get-WmiObject Win32_OperatingSystem).TotalVisibleMemorySize - (Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory
$ramUsagePercent = [math]::Round(($ramUsage / (Get-WmiObject Win32_OperatingSystem).TotalVisibleMemorySize) * 100, 2)

# Uzimanje trenutnog CPU Load
$cpuLoad = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue

	############################ CODE MONITORING CSV FAJLOVI ############################
	$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
	$dataFolder = "$PSScriptRoot\Data"
	if (-not (Test-Path $dataFolder)) { New-Item -Path $dataFolder -ItemType Directory | Out-Null }

	# --- Патеки на CSV и JSON ---
	$tempCsv     = "$dataFolder\temperatures.csv"
	$loadCsv     = "$dataFolder\load.csv"
	$diskCsv     = "$dataFolder\disk.csv"
	$tempAllCsv  = "$dataFolder\temperatures_all.csv"
	$loadAllCsv  = "$dataFolder\load_all.csv"
	$diskAllCsv  = "$dataFolder\disk_all.csv"
	$stateFile   = "$dataFolder\state.json"

	# --- Вчитување на состојба од JSON ---
	if (Test-Path $stateFile) {
		try {
			$state = Get-Content $stateFile | ConvertFrom-Json
			$Global:LastDailyAverageDate = [datetime]$state.LastDailyAverageDate
			$Global:LastCleanupDate = [datetime]$state.LastCleanupDate
		}
		catch {
			Write-Warning "Corrupted *state.json* file detected. Resetting the file..."
			try { Remove-Item $stateFile -Force -ErrorAction SilentlyContinue } catch {}

			# Постави default состојби ако JSON е оштетен
			$Global:LastDailyAverageDate = (Get-Date).AddDays(-1)
			$Global:LastCleanupDate = (Get-Date).AddDays(-35)

			# Логирај само ако навистина е детектиран оштетен фајл
			if ($Global:LogFile) {
				Add-Content -Path $Global:LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Warning: *state.json* it was corrupted and has been Reset."
			}
		}
	}
	else {
		# Ако фајлот не постои — иницијализирај нова состојба
		$Global:LastDailyAverageDate = (Get-Date).AddDays(-1)
		$Global:LastCleanupDate = (Get-Date).AddDays(-35)
	}

	$today = (Get-Date).Date
	$currentDateStr = (Get-Date -Format 'yyyy-MM-dd')

	# --- Иницијализација на лог фолдер ---
	$Global:monitoringLogsFolder = "$PSScriptRoot\Autopilot_Data\Monitoring_Logs"
	if (-not (Test-Path $Global:monitoringLogsFolder)) { New-Item -Path $Global:monitoringLogsFolder -ItemType Directory | Out-Null }

	# --- Дефинирање на дневен лог ---
	if (-not $Global:monitoringDate -or $Global:monitoringDate -ne $currentDateStr) {
		$Global:monitoringDate = $currentDateStr
		$Global:LogFile = "$Global:monitoringLogsFolder\monitoring_$Global:monitoringDate.txt"
		Add-Content -Path $Global:LogFile -Value "[$timestamp] New day detected. Creating a new log file."
	}
	if (-not (Test-Path $Global:LogFile)) { New-Item -Path $Global:LogFile -ItemType File | Out-Null }

	# --- Helper: функција за дневен просек ---
	function Write-DailyAverage($src, $dest, $cols, $date) {
		if (-not (Test-Path $src)) { return }
		$data = Import-Csv $src | Where-Object { $_.Timestamp -and $_.Timestamp.Trim() -ne "" } |
				Where-Object { try { ([datetime]$_.Timestamp).Date -eq $date } catch { $false } }
		if ($data.Count -eq 0) { return }

		$avg = [ordered]@{ Date = $date.ToString('yyyy-MM-dd') }
		foreach ($c in $cols) {
			if ($data[0].PSObject.Properties[$c]) {
				$vals = $data | ForEach-Object { 
					$val = $_.$c
					if ($val -match '^-?\d+(\.\d+)?$') { [double]$val } 
				} | Where-Object { $_ -ne $null }
				$avg[$c + "_Avg"] = if ($vals.Count -gt 0) { [math]::Round(($vals | Measure-Object -Average).Average, 2) } else { "" }
			} else { $avg[$c + "_Avg"] = "" }
		}
		[pscustomobject]$avg | Export-Csv -Path $dest -NoTypeInformation -Append:$true -Force
	}

	# --- Проверка за назадно време, само логирање ---
	if ($today -lt $Global:LastDailyAverageDate.Date) {
		Add-Content -Path $Global:LogFile -Value "[$timestamp] Warning: Retrograde data detected ($today). Stopping the calculation of the daily average."
		return
	}

	# --- Start poraka (ednokratno) ---
	$monitoringLogsFolder = "$PSScriptRoot\Autopilot_Data\Monitoring_Logs"
	$monitoringStartFlag = Join-Path $monitoringLogsFolder "monitoring_start.flag"
	# Проверка дали worker процесот е активен
	$workerRunning = Get-WmiObject Win32_Process | Where-Object {
		$_.Name -eq "powershell.exe" -and $_.CommandLine -match "SystemMonitorWorker\.ps1"
	}
	# Креирај start flag само ако процесот не работи и flag не постои
	if (-not $workerRunning -and -not (Test-Path $monitoringStartFlag)) {
		$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
		# Зачувај timestamp во лог
		Add-Content -Path $Global:LogFile -Value "[$timestamp] Monitoring Started at $timestamp"
		# Зачувај timestamp во start flag (секогаш истиот фајл)
		Set-Content -Path $monitoringStartFlag -Value $timestamp -Encoding UTF8
	}

	# === ГЛАВНА ЛОГИКА: собирање на податоци ===
		# --- Температури ---
		$tempObj = [PSCustomObject]@{
			Timestamp = $timestamp
			CPU_Temp  = $cpuTempVal
			GPU_Temp  = $gpuTempVal
			MB_Temp   = $mbTempVal
		}
		foreach ($diskName in $diskTemps.Keys) {
			$cleanName = $diskName -replace '\s','_' -replace '[^a-zA-Z0-9_]',''
			$tempObj | Add-Member -NotePropertyName "Disk_${cleanName}_Temp" -NotePropertyValue $diskTemps[$diskName]
		}

		# Disk Load
		$diskLoads = @{}
		# Земаме само внатрешни дискови (исклучуваме USB и надворешни)
		$disks = Get-CimInstance Win32_DiskDrive | Where-Object { $_.InterfaceType -ne "USB" -and $_.MediaType -match "Fixed" }
		Get-Counter -Counter "\PhysicalDisk(*)\% Disk Time" | Select-Object -ExpandProperty CounterSamples | ForEach-Object {
			$instance = $_.InstanceName
			if ($instance -ne "_Total") {
				$diskIndex = ($instance -split ' ')[0]
				$disk = $disks | Where-Object { $_.Index -eq [int]$diskIndex }
				if ($disk) {
					$diskName = $disk.Model -replace '\s','_' -replace '[^a-zA-Z0-9_]',''

					# Безбедносна проверка на вредноста
					if ([double]::IsNaN($_.CookedValue) -or $_.CookedValue -lt 0) {
						$loadPercent = 0
					} else {
						$loadPercent = [math]::Min([math]::Max($_.CookedValue,0),100)
					}

					$diskLoads[$diskName] = [math]::Round($loadPercent,2)
				}
			}
		}

		# --- GPU Load Universal ---
		$gpuLoads = @{}
		# --- NVIDIA GPU ---
		try {
			$nvidiaOutput = & nvidia-smi --query-gpu=name,utilization.gpu --format=csv,noheader,nounits 2>$null
			if ($nvidiaOutput) {
				foreach ($line in $nvidiaOutput) {
					$parts = $line -split ','
					if ($parts.Count -ge 2) {
						$gpuName = "GPU_" + ($parts[0].Trim() -replace '\s','_' -replace '[^a-zA-Z0-9_]','')
						$gpuLoad = [math]::Round([double]$parts[1],2)
						$gpuLoads[$gpuName] = $gpuLoad
					}
				}
			}
		} catch {
			Write-Verbose "NVIDIA GPU load failed."
		}
		# --- Унифициран повик за GPU counters (AMD + Intel) ---
		$gpuCounters = @()
		try {
			$gpuCounters = Get-Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction SilentlyContinue |
						   Select-Object -ExpandProperty CounterSamples
		} catch {
			Write-Verbose "GPU Engine sensors are unavailable."
		}
		
		if ($gpuCounters.Count -gt 0) {
			# --- AMD GPU (Radeon) ---
			try {
				foreach ($c in $gpuCounters) {
					if ($c.InstanceName -ne "_Total" -and $c.InstanceName -match "AMD|Radeon") {
						$gpuName = "GPU_" + ($c.InstanceName -replace '\s','_' -replace '[^a-zA-Z0-9_]','')
						$gpuLoad = [math]::Round([math]::Min([math]::Max($c.CookedValue,0),100),2)
						$gpuLoads[$gpuName] = $gpuLoad
					}
				}
			} catch {
				Write-Verbose "AMD GPU load failed."
			}

			# --- Интегрирани GPU (Intel или AMD iGPU) ---
			try {
				$gpuMaxLoad = @{}

				foreach ($c in $gpuCounters) {
					if ($c.InstanceName -ne "_Total" -and $c.CookedValue -ne $null) {
						if ($c.InstanceName -match "Intel") {
							$gpuName = "GPU_Intel"
						} elseif ($c.InstanceName -match "AMD") {
							$gpuName = "GPU_AMD_IGPU"
						} else {
							$gpuName = "GPU_Integrated"
						}

						# Чувај само највисока вредност по GPU
						$val = [math]::Min([math]::Max($c.CookedValue,0),100)
						if ($gpuMaxLoad.ContainsKey($gpuName)) {
							if ($val -gt $gpuMaxLoad[$gpuName]) { $gpuMaxLoad[$gpuName] = $val }
						} else {
							$gpuMaxLoad[$gpuName] = $val
						}
					}
				}

				foreach ($gpuName in $gpuMaxLoad.Keys) {
					$gpuLoads[$gpuName] = [math]::Round($gpuMaxLoad[$gpuName],2)
				}
			} catch {
				Write-Verbose "Integrated GPU load failed."
			}
		}

		# Ако нема пронајдени GPU load вредности
		if ($gpuLoads.Count -eq 0) {
			Write-Verbose "No GPU load data available from any source."
		}

		# --- Load CSV --- 
		$loadObj = [PSCustomObject]@{
			Timestamp = $timestamp
			CPU_Load = [math]::Round($cpuLoad,2)
			RAM_Usage_Percent = $ramUsagePercent
		}

		# Додавање на GPU load колони
		foreach ($gpu in $gpuLoads.Keys) {
			$loadObj | Add-Member -NotePropertyName $gpu -NotePropertyValue $gpuLoads[$gpu]
		}

		# --- Disk CSV ---
		$diskObj = [PSCustomObject]@{ Timestamp = $timestamp }
		foreach ($diskName in $diskLoads.Keys) {
			$diskObj | Add-Member -NotePropertyName "Disk_${diskName}_Load" -NotePropertyValue $diskLoads[$diskName]
		}

		# --- Запиши податоци ---
		$tempObj | Export-Csv -Path $tempCsv -NoTypeInformation -Append:$true -Force
		$loadObj | Export-Csv -Path $loadCsv -NoTypeInformation -Append:$true -Force
		$diskObj | Export-Csv -Path $diskCsv -NoTypeInformation -Append:$true -Force

		# --- Дневни просеци ---
		if ($today -gt $Global:LastDailyAverageDate.Date) {
			$prevDay = $Global:LastDailyAverageDate.Date
			$tempColumns = @("CPU_Temp","GPU_Temp","MB_Temp") + ($diskTemps.Keys | ForEach-Object { "Disk_$($_ -replace '\s','_' -replace '[^a-zA-Z0-9_]','')_Temp" })
			$loadColumns = @("CPU_Load","RAM_Usage_Percent")
	    
		# --- Додај ги сите GPU колони динамички ---
		if ($gpuLoads.Count -gt 0) {
			$gpuColumns = $gpuLoads.Keys
			$loadColumns += $gpuColumns
		}
			$diskColumns = $diskLoads.Keys | ForEach-Object { "Disk_${_}_Load" }

			Write-DailyAverage $tempCsv $tempAllCsv $tempColumns $prevDay
			Write-DailyAverage $loadCsv $loadAllCsv $loadColumns $prevDay
			Write-DailyAverage $diskCsv $diskAllCsv $diskColumns $prevDay

			Add-Content -Path $Global:LogFile -Value "[$timestamp] Daily average recorded for $($prevDay.ToString('yyyy-MM-dd'))"
			$Global:LastDailyAverageDate = $today
		}

		# --- Чистење на стари податоци секои 35 дена ---
		if ((Get-Date) -gt $Global:LastCleanupDate.AddDays(35)) {
			foreach ($csvFile in @($tempCsv,$loadCsv,$diskCsv,$tempAllCsv,$loadAllCsv,$diskAllCsv)) {
				if (Test-Path $csvFile) {
					$data = Import-Csv $csvFile | Where-Object { $_.Timestamp -and $_.Timestamp.Trim() -ne "" }
					$dates = $data | ForEach-Object { try { ([datetime]$_.Timestamp).Date } catch { $null } } | Sort-Object -Unique
					if ($dates.Count -gt 32) {
						$keepDates = $dates | Select-Object -Last 32
						$newData = $data | Where-Object { try { $d = ([datetime]$_.Timestamp).Date; $keepDates -contains $d } catch { $false } }
						$newData | Export-Csv -Path $csvFile -NoTypeInformation -Force
						$deleted = $data.Count - $newData.Count
						Add-Content -Path $Global:LogFile -Value "[$timestamp] Deleting ${csvFile}: Deleted $deleted records retained to keep the last 31 unique calendar days."
					}
				}
			}
		$Global:LastCleanupDate = Get-Date
	}
	# --- Сними state ---
	$state = @{
		LastDailyAverageDate  = $Global:LastDailyAverageDate.ToString("yyyy-MM-dd")
		LastCleanupDate       = $Global:LastCleanupDate.ToString("yyyy-MM-dd")
	}
	$state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
	Add-Content -Path $Global:LogFile -Value "[$timestamp] Monitoring is Running - Data saved in $(Get-Date -Format 'HH:mm:ss')"
	############################ END CODE MONITORING ############################

    Start-Sleep -Seconds $SampleIntervalSeconds
}

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Add-Content -Path $Global:LogFile -Value "[$timestamp] Monitoring Stopped at $timestamp"

################################################################################ System Monitor Worker Script End.