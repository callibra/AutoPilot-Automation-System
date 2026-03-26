param (
    [string[]]$AutoRunOps = @(),
    [switch]$Silent
)

### Funkcija za prikaz na tekst vo boja
function Write-Colored {
    param([string]$text, [ConsoleColor]$color = "White")
#   if (-not $Silent) {
        Write-Host $text -ForegroundColor $color
#    }
}

### Проверка за админ
function Check-Admin {
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Colored "This script must be run with Administrative privileges!" Red
        Write-Colored "Right-click on PowerShell > Run as Administrator`n" Red
        pause
        exit
    }
}

### Funkcija za proverka statusa hibernacije
function Check-Hibernation {
    $output = powercfg /a
    if ($output -match "Hibernation has not been enabled" -or $output -match "hibernation is not available") {
        return $false
    } else {
        return $true
    }
}

### Funkcija za isključenje na hibernacija
function Disable-Hibernation {
    powercfg /hibernate off
    Write-Colored "Hibernation has been successfully disabled." Green
}

### Clear TemperFolder
function Clear-TempFolder {
    param([string]$folderPath)

    if (Test-Path $folderPath) {
        $filesBefore = Get-ChildItem -Path $folderPath -Recurse -Force -ErrorAction SilentlyContinue
        $countBefore = $filesBefore.Count
        $sizeBefore = 0

        foreach ($file in $filesBefore) {
            if (-not $file.PSIsContainer) {
                $sizeBefore += $file.Length
            }
        }
        Write-Colored "`In $folderPath there are $countBefore files with $([math]::Round($sizeBefore / 1MB, 2)) MB" Cyan
        Remove-Item "$folderPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        $filesAfter = Get-ChildItem -Path $folderPath -Recurse -Force -ErrorAction SilentlyContinue
        $countAfter = $filesAfter.Count
        $sizeAfter = 0

        foreach ($file in $filesAfter) {
            if (-not $file.PSIsContainer) {
                $sizeAfter += $file.Length
            }
        }
        $deletedFiles = $countBefore - $countAfter
        $deletedSize = $sizeBefore - $sizeAfter
        Write-Colored "Deleted: $deletedFiles files. Freed space: $([math]::Round($deletedSize / 1MB, 2)) MB" Green

        return [PSCustomObject]@{
            FilesDeleted = $deletedFiles
            SizeDeleted = $deletedSize
        }
    } else {
        Write-Colored "$folderPath does not exist." Yellow
        return $null
    }
}

### Clear TempForSpecificUser
function Clear-TempForSpecificUser {
    param([string]$userName)
    $userTempFolder = "C:\Users\$userName\AppData\Local\Temp"

    if (Test-Path $userTempFolder) {
        Write-Colored "`nCleaning Temp folder for user: $userName" Cyan
        $res = Clear-TempFolder -folderPath $userTempFolder
        return $res
    } else {
        Write-Colored "`Temp folder for user $userName does not exist." Yellow
        return $null
    }
}

### Start DiskCleanup
function Run-DiskCleanup {
    Write-Colored "Starting Disk Cleanup..." Cyan
    try {
        Start-Process "cleanmgr" -ArgumentList "/sagerun:1" -Wait
        Write-Colored "Disk Cleanup completed." Green
    } catch {
        Write-Colored "Cannot start Disk Cleanup." Red
    }
}

### Clear UnusedRegistry
function Clear-UnusedRegistry {
    Write-Host "`n[Registry Cleanup Started]" -ForegroundColor Cyan

    $regKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\CIDSizeMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunOnce",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit",
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store",
        "HKCU:\Software\Microsoft\Windows\Shell\BagMRU",
        "HKCU:\Software\Microsoft\Windows\Shell\Bags"
    )

    $removed = 0
    $notFound = 0
    $failed = 0
    $removedList = @()
    $failedList = @()
    $notFoundList = @()

    foreach ($key in $regKeys) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
                Write-Host "Removed: $key" -ForegroundColor Green
                $removed++
                $removedList += $key
            } catch {
                Write-Host "Failed to remove: $key" -ForegroundColor Red
                $failed++
                $failedList += $key
            }
        } else {
            Write-Host "Not found: $key" -ForegroundColor DarkGray
            $notFound++
            $notFoundList += $key
        }
    }

    Write-Host "`n[Registry Cleanup Completed]" -ForegroundColor Cyan
    Write-Host "----------------------------------------"
    Write-Host "Successfully Removed : $removed"
    Write-Host "Not Found             : $notFound"
    Write-Host "Failed to Remove      : $failed"
    Write-Host "----------------------------------------`n"

    if ($removedList.Count -gt 0) {
        Write-Host "Removed Keys:" -ForegroundColor Green
        $removedList | ForEach-Object { Write-Host "  - $_" }
    }

    if ($notFoundList.Count -gt 0) {
        Write-Host "`n Not Found:" -ForegroundColor Yellow
        $notFoundList | ForEach-Object { Write-Host "  - $_" }
    }

    if ($failedList.Count -gt 0) {
        Write-Host "`n Failed to Remove:" -ForegroundColor Red
        $failedList | ForEach-Object { Write-Host "  - $_" }
    }
}

### Show Menu
function Show-Menu {
    if (-not $Silent) {
        Clear-Host
        Write-Colored "===============================" Cyan
        Write-Colored "   AutoPilot Cleaner   " Green
        Write-Colored "===============================" Cyan
        Write-Colored "1.  Hibernation Status" Yellow
        Write-Colored "2.  Turn Off Hibernation" Yellow
        Write-Colored "3.  Clean Windows Temp" Cyan
        Write-Colored "4.  Clean AppData Temp" Cyan
        Write-Colored "5.  Clean SoftwareDistribution" Green
        Write-Colored "6.  Clean Prefetch" Green
        Write-Colored "7.  Start Disk Cleanup" Yellow
        Write-Colored "8.  Clean Temp for all users" Yellow
        Write-Colored "9.  Clean Temp for a specific user" Cyan
        Write-Colored "10. TOTAL CLEAN (All Operations)" Magenta
        Write-Colored "11. Clean Status" Blue
		Write-Colored "12. Clean Registry" Green
		Write-Colored "13. Exit" Red
        Write-Colored "===============================" Cyan
        Write-Colored "`n`nSelect an option (1-12)" Magenta
    }
    return Read-Host "`n[ENTER option]"
}

### MAIN Function
function Main {
    Check-Admin
    $totalDeletedFiles = 0
    $totalDeletedSize = 0
    $operationsDone = @()
    # Automatsko izvršavanje operacija
	if ($AutoRunOps.Count -gt 0) {
		foreach ($op in $AutoRunOps) {
			switch ($op) {
				1 {
					if (Check-Hibernation) {
						Write-Colored "Hibernation is ENABLED." Green
					} else {
						Write-Colored "Hibernation is DISABLED." Red
					}
				}
				2 {
					if (Check-Hibernation) {
						Disable-Hibernation
						$operationsDone += "Hibernation is turned off"
					} else {
						Write-Colored "Hibernation is already turned off." Cyan
					}
				}
				3 {
					$res = Clear-TempFolder -folderPath "$env:SystemRoot\Temp"
					if ($res) {
						$totalDeletedFiles += $res.FilesDeleted
						$totalDeletedSize += $res.SizeDeleted
						$operationsDone += "Windows Temp is cleaned"
					}
				}
				4 {
					$res = Clear-TempFolder -folderPath "$env:USERPROFILE\AppData\Local\Temp"
					if ($res) {
						$totalDeletedFiles += $res.FilesDeleted
						$totalDeletedSize += $res.SizeDeleted
						$operationsDone += "AppData Temp is cleaned"
					}
				}
				5 {
					$res = Clear-TempFolder -folderPath "C:\Windows\SoftwareDistribution\Download"
					if ($res) {
						$totalDeletedFiles += $res.FilesDeleted
						$totalDeletedSize += $res.SizeDeleted
						$operationsDone += "SoftwareDistribution is cleaned"
					}
				}
				6 {
					$res = Clear-TempFolder -folderPath "C:\Windows\Prefetch"
					if ($res) {
						$totalDeletedFiles += $res.FilesDeleted
						$totalDeletedSize += $res.SizeDeleted
						$operationsDone += "Prefetch is cleaned"
					}
				}
				7 {
					Run-DiskCleanup
					$operationsDone += "Disk Cleanup is completed"
				}
				8 {
					$userProfiles = Get-ChildItem "C:\Users" | Where-Object { $_.PSIsContainer }
					foreach ($user in $userProfiles) {
						$res = Clear-TempForSpecificUser -userName $user.Name
						if ($res) {
							$totalDeletedFiles += $res.FilesDeleted
							$totalDeletedSize += $res.SizeDeleted
							$operationsDone += "Temp folder for user $($user.Name) is cleaned"
						}
					}
				}
				9 {
					Write-Colored "AutoRunOps does not support interactive user selection for option 9. Skipping..." Yellow
				}
				10 {
					Write-Colored "Starting bulk cleanup..." Cyan

					$paths = @(
						"$env:SystemRoot\Temp",
						"$env:USERPROFILE\AppData\Local\Temp",
						"C:\Windows\SoftwareDistribution\Download",
						"C:\Windows\Prefetch"
					)

					foreach ($path in $paths) {
						$res = Clear-TempFolder -folderPath $path
						if ($res) {
							$totalDeletedFiles += $res.FilesDeleted
							$totalDeletedSize += $res.SizeDeleted
							$operationsDone += "$path is cleaned"
						}
					}

					$userProfiles = Get-ChildItem "C:\Users" | Where-Object { $_.PSIsContainer }
					foreach ($user in $userProfiles) {
						$res = Clear-TempForSpecificUser -userName $user.Name
						if ($res) {
							$totalDeletedFiles += $res.FilesDeleted
							$totalDeletedSize += $res.SizeDeleted
							$operationsDone += "Temp folder for user $($user.Name) is cleaned"
						}
					}

					Run-DiskCleanup
					$operationsDone += "Disk Cleanup is completed"
				}
				11 {
					Write-Colored "`STATUS REPORT" Cyan
					Write-Colored "------------------------" Cyan

					if ($operationsDone.Count -gt 0) {
						foreach ($o in $operationsDone) {
							Write-Colored "$o" Green
						}

						Write-Colored "Total deleted files: $totalDeletedFiles" Cyan
						Write-Colored "TotalDeletedSize (bytes): $totalDeletedSize" Cyan

						if ($totalDeletedSize -gt 0) {
							$totalMB = [math]::Round($totalDeletedSize / 1MB, 2)
							Write-Colored "Total freed space: $totalMB MB" Green
						}
					} else {
						Write-Colored "No operations were performed." Yellow
					}
				}
				12 {
					Clear-UnusedRegistry
					$operationsDone += "Registry keys have been cleaned"
				}
				default {
					Write-Colored "Invalid option: $op" Red
				}
			}
		}
		return
	}
    # Ako nije Silent, prikazuj meni
    if (-not $Silent) {
        while ($true) {
            $choice = Show-Menu
            switch ($choice) {
                1 {
					if (Check-Hibernation) {
						Write-Colored "Hibernation is ENABLED." Green
					} else {
						Write-Colored "Hibernation is DISABLED." Red
					}
					Read-Host "`Press ENTER to return to the Main Menu..."
				}
				2 {
					if (Check-Hibernation) {
						Disable-Hibernation
						Write-Colored "Hibernation has been successfully disabled." Yellow
						$operationsDone += "Hibernation is turned off"
					} else {
						Write-Colored "Hibernation is already turned off." Cyan
					}
					Read-Host "`Press ENTER to return to the Main Menu..."
				}
                3 {
                    $res = Clear-TempFolder -folderPath "$env:SystemRoot\Temp"
                    if ($res) {
                        $totalDeletedFiles += $res.FilesDeleted
                        $totalDeletedSize += $res.SizeDeleted
                        $operationsDone += "Windows Temp is cleaned"
                    }
                    Read-Host "`Press ENTER to return to the Main Menu..."
                }
                4 {
                    $res = Clear-TempFolder -folderPath "$env:USERPROFILE\AppData\Local\Temp"
                    if ($res) {
                        $totalDeletedFiles += $res.FilesDeleted
                        $totalDeletedSize += $res.SizeDeleted
                        $operationsDone += "AppData Temp is cleaned"
                    }
                    Read-Host "`Press ENTER to return to the Main Menu..."
                }
                5 {
                    $res = Clear-TempFolder -folderPath "C:\Windows\SoftwareDistribution\Download"
                    if ($res) {
                        $totalDeletedFiles += $res.FilesDeleted
                        $totalDeletedSize += $res.SizeDeleted
                        $operationsDone += "SoftwareDistribution is cleaned"
                    }
                    Read-Host "`Press ENTER to return to the Main Menu..."
                }
                6 {
                    $res = Clear-TempFolder -folderPath "C:\Windows\Prefetch"
                    if ($res) {
                        $totalDeletedFiles += $res.FilesDeleted
                        $totalDeletedSize += $res.SizeDeleted
                        $operationsDone += "Prefetch is cleaned"
                    }
                    Read-Host "`Press ENTER to return to the Main Menu..."
                }
                7 {
                    Run-DiskCleanup
                    $operationsDone += "Disk Cleanup is completed"
                    Read-Host "`Press ENTER to return to the Main Menu..."
                }
                8 {
                    Write-Colored "Starting bulk cleanup for all users..." Cyan
                    $userProfiles = Get-ChildItem "C:\Users" | Where-Object { $_.PSIsContainer }

                    foreach ($user in $userProfiles) {
                        $res = Clear-TempForSpecificUser -userName $user.Name
                        if ($res) {
                            $totalDeletedFiles += $res.FilesDeleted
                            $totalDeletedSize += $res.SizeDeleted
                            $operationsDone += "Temp folder for user $($user.Name) is cleaned"
                        }
                    }
                    Read-Host "`Press ENTER to return to the Main Menu..."
                }
                9 {
                    $userProfiles = Get-ChildItem "C:\Users" | Where-Object { $_.PSIsContainer }

                    if ($userProfiles.Count -gt 1) {
                        Write-Colored "Available users:" Cyan
                        $userProfiles | ForEach-Object { Write-Colored "$($_.Name)" Green }

                        $userName = Read-Host "Enter the username (example: Roki)"
                        $res = Clear-TempForSpecificUser -userName $userName
                        if ($res) {
                            $totalDeletedFiles += $res.FilesDeleted
                            $totalDeletedSize += $res.SizeDeleted
                            $operationsDone += "Temp folder for user $userName is cleaned"
                        }
                    } else {
                        Write-Colored "There are no other users on this PC" Yellow
                    }
                    Read-Host "`Press ENTER to return to the Main Menu..."
                }
                10 {
                    Write-Colored "Starting bulk cleanup..." Cyan

                    $paths = @(
                        "$env:SystemRoot\Temp",
                        "$env:USERPROFILE\AppData\Local\Temp",
                        "C:\Windows\SoftwareDistribution\Download",
                        "C:\Windows\Prefetch"
                    )

                    foreach ($path in $paths) {
                        $res = Clear-TempFolder -folderPath $path
                        if ($res) {
                            $totalDeletedFiles += $res.FilesDeleted
                            $totalDeletedSize += $res.SizeDeleted
                            $operationsDone += "$path is cleaned"
                        }
                    }
                    # Site korisnici
                    $userProfiles = Get-ChildItem "C:\Users" | Where-Object { $_.PSIsContainer }
                    foreach ($user in $userProfiles) {
                        $res = Clear-TempForSpecificUser -userName $user.Name
                        if ($res) {
                            $totalDeletedFiles += $res.FilesDeleted
                            $totalDeletedSize += $res.SizeDeleted
                            $operationsDone += "Temp folder for user $($user.Name) is cleaned"
                        }
                    }

                    Run-DiskCleanup
                    $operationsDone += "Disk Cleanup completed"
                    Write-Colored "Bulk cleanup completed." Green
                    Read-Host "`Press ENTER to return to the Main Menu..."
                }
                11 {
					Write-Colored "`STATUS REPORT:" Cyan
					Write-Colored "------------------------" Cyan

					if ($operationsDone.Count -gt 0) {
						foreach ($op in $operationsDone) {
							Write-Colored "$op" Green
						}

						Write-Colored "Total deleted files: $totalDeletedFiles" Cyan
						Write-Colored "TotalDeletedSize (bytes): $totalDeletedSize" Cyan

						$totalMB = [math]::Round($totalDeletedSize / 1MB, 2)
					Write-Colored "Total freed space: $totalMB MB" Green

					} else {
						Write-Colored "No operations were performed." Yellow
					}

					Read-Host "`Press ENTER to return to the Main Menu..."
					continue
				}
				12 {
					Clear-UnusedRegistry
					Write-Colored "Registry keys have been successfully cleaned." Green
					Read-Host "`Press ENTER to return to the Main Menu..."
				}
				13 {
					Write-Colored "Exiting the script." Red
					exit
				}
								default {
									Write-Colored "Invalid option." Red
									Read-Host "`Press ENTER to return to the Main Menu..."
								}
							}
						}
					}
				}
# Pokreni glavnu funkciju
Main

############################################################################################# Cleaner Script End.

### powercfg /hibernate on

### powercfg /availablesleepstates

### powercfg /hibernate off
