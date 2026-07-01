# ================= APP ROOT =================
if (-not $AppRoot) {
    if ($PSCommandPath) {
        $AppRoot = Split-Path -Parent $PSCommandPath
    }
    else {
        $AppRoot = Split-Path -Parent (
            [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        )
    }
}

# ================= LOAD UI =================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ================= RANDOM COLOR =================
function Get-RandomColor {
    $r = Get-Random -Minimum 80 -Maximum 255
    $g = Get-Random -Minimum 80 -Maximum 255
    $b = Get-Random -Minimum 80 -Maximum 255
    return [Drawing.Color]::FromArgb($r,$g,$b)
}

# ================= CSV LOAD =================
function Load-CSV($path) {
    if (Test-Path $path) { return Import-Csv $path }
    return @()
}

# ================= BYTES CONVERT =================
function Convert-Bytes($bytes) {
    if ($null -eq $bytes -or $bytes -eq "") {
        return "0 B"
    }
    $KB = 1024
    $MB = $KB * 1024
    $GB = $MB * 1024
    $TB = $GB * 1024
    $PB = $TB * 1024
    $EB = $PB * 1024
    $b = [double]$bytes
    switch ($b) {
        { $_ -ge $EB } { return "{0:N2} EB" -f ($b / $EB) }
        { $_ -ge $PB } { return "{0:N2} PB" -f ($b / $PB) }
        { $_ -ge $TB } { return "{0:N2} TB" -f ($b / $TB) }
        { $_ -ge $GB } { return "{0:N2} GB" -f ($b / $GB) }
        { $_ -ge $MB } { return "{0:N2} MB" -f ($b / $MB) }
        { $_ -ge $KB } { return "{0:N2} KB" -f ($b / $KB) }
        default { return "{0:N0} B" -f $b }
    }
}

# ================= BUILD LINE DAY =================
function Build-Line($date,$disk,$load,$temp,$traffic) {
    $d = $disk | Where-Object { ([datetime]$_.Date).Date -eq ([datetime]$date).Date } | Select-Object -First 1
    $l = $load | Where-Object { ([datetime]$_.Date).Date -eq ([datetime]$date).Date } | Select-Object -First 1
    $t = $temp | Where-Object { ([datetime]$_.Date).Date -eq ([datetime]$date).Date } | Select-Object -First 1
    $r = $traffic | Where-Object { ([datetime]$_.Date).Date -eq ([datetime]$date).Date }
    if (-not $d -and -not $l -and -not $t -and -not $r) { return $null }
    # ================= DISK SAFE =================
    $diskText = "Disk:`r`n"
    if ($d) {
        foreach ($p in $d.PSObject.Properties) {
            if ($p.Name -ne "Date") {
                $val = if ([string]::IsNullOrWhiteSpace($p.Value)) { "Not available" } else { $p.Value }
                $diskText += "$($p.Name): $val`r`n"
            }
        }
    } else {
        $diskText += "No disk data`r`n"
    }
    # ================= LOAD SAFE =================
    $loadText = "Load:`r`n"
    if ($l) {
        foreach ($p in $l.PSObject.Properties) {
            if ($p.Name -ne "Date") {
                $val = if ([string]::IsNullOrWhiteSpace($p.Value)) { "Not available" } else { $p.Value }
                $loadText += "$($p.Name): $val`r`n"
            }
        }
    } else {
        $loadText += "No load data`r`n"
    }
    # ================= TEMP SAFE =================
    $tempText = "Temperatures:`r`n"
    if ($t) {
        foreach ($p in $t.PSObject.Properties) {
            if ($p.Name -ne "Date") {
                $val = $p.Value
                if ([string]::IsNullOrWhiteSpace($val)) {
                    $tempText += "$($p.Name): Not measured`r`n"
                } else {
                    $tempText += "$($p.Name): $val`r`n"
                }
            }
        }
    } else {
        $tempText += "No temperature data`r`n"
    }
    # ================= TRAFFIC =================
    $trafficText = ""
    if ($traffic) {
        $grouped = $traffic | Group-Object Interface
        foreach ($g in $grouped) {
            $row = $g.Group | Where-Object {
                ([datetime]$_.Date).Date -eq ([datetime]$date).Date
            } | Select-Object -First 1
            if ($row) {
                $parts = $row.'Download_Bytes/Upload_Bytes/Total_Bytes' -split "/"
                $trafficText += @"
       
Traffic [$($g.Name)]
Download: $(Convert-Bytes $parts[0])
Upload:   $(Convert-Bytes $parts[1])
Total:    $(Convert-Bytes $parts[2])

"@
            }
        }
        # ================= GLOBAL TRAFFIC =================
        $globalTraffic = $traffic | Where-Object {
            ([datetime]$_.Date).Date -eq ([datetime]$date).Date
        }
        if ($globalTraffic) {
            $totalDownload = [decimal]0
            $totalUpload   = [decimal]0
            $totalTotal    = [decimal]0
            foreach ($g in $globalTraffic) {
                $parts = $g.'Download_Bytes/Upload_Bytes/Total_Bytes' -split "/"
                if ($parts.Count -eq 3) {
                    $totalDownload += [decimal]$parts[0]
                    $totalUpload   += [decimal]$parts[1]
                    $totalTotal    += [decimal]$parts[2]
                }
            }
            $trafficText += @"

Global Traffic (All Interfaces)
Download: $(Convert-Bytes $totalDownload)
Upload:   $(Convert-Bytes $totalUpload)
Total:    $(Convert-Bytes $totalTotal)
"@
        }
    }
    # ================= FINAL OUTPUT =================
@"

Date: $date
-Hardware Data:

$diskText
$loadText
$tempText
-Network Data:
$trafficText
"@
}

# ================= BUILD LINE WEEK MONTH YEAR ALL =================
function Build-Line-Range($start,$end,$disk,$load,$temp,$traffic) {
    # ================= FILTER =================
    $diskFiltered = $disk | Where-Object {
        ([datetime]$_.Date) -ge $start -and ([datetime]$_.Date) -le $end
    }
    $loadFiltered = $load | Where-Object {
        ([datetime]$_.Date) -ge $start -and ([datetime]$_.Date) -le $end
    }
    $tempFiltered = $temp | Where-Object {
        ([datetime]$_.Date) -ge $start -and ([datetime]$_.Date) -le $end
    }
    $trafficFiltered = $traffic | Where-Object {
        ([datetime]$_.Date) -ge $start -and ([datetime]$_.Date) -le $end
    }
    if (-not $diskFiltered -and -not $loadFiltered -and -not $tempFiltered -and -not $trafficFiltered) {
        return "No data in selected range"
    }
    # ================= DISK (PRECISION AVG) =================
    $diskText = "Disk:`r`n"
    if ($diskFiltered) {
        $props = $diskFiltered[0].PSObject.Properties | Where-Object { $_.Name -ne "Date" }
        foreach ($p in $props) {
            $values = $diskFiltered | ForEach-Object { $_.$($p.Name) } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            if ($values) {
                $sum = [decimal]0
                $count = 0
                foreach ($v in $values) {
                    $sum += [decimal]$v
                    $count++
                }
                $avg = if ($count -gt 0) { $sum / $count } else { 0 }
                $diskText += "$($p.Name): {0:N2}`r`n" -f $avg
            }
            else {
                $diskText += "$($p.Name): Not available`r`n"
            }
        }
    }
    else {
        $diskText += "No disk data`r`n"
    }
    # ================= LOAD (PRECISION AVG) =================
    $loadText = "Load:`r`n"
    if ($loadFiltered) {
        $props = $loadFiltered[0].PSObject.Properties | Where-Object { $_.Name -ne "Date" }
        foreach ($p in $props) {
            $values = $loadFiltered | ForEach-Object { $_.$($p.Name) } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            if ($values) {
                $sum = [decimal]0
                $count = 0
                foreach ($v in $values) {
                    $sum += [decimal]$v
                    $count++
                }
                $avg = if ($count -gt 0) { $sum / $count } else { 0 }
                $loadText += "$($p.Name): {0:N2}`r`n" -f $avg
            }
            else {
                $loadText += "$($p.Name): Not available`r`n"
            }
        }
    }
    else {
        $loadText += "No load data`r`n"
    }
    # ================= TEMPERATURE (ALREADY OK, CLEANED) =================
    $tempText = "Temperatures:`r`n"
    if ($tempFiltered) {
        $props = $tempFiltered[0].PSObject.Properties | Where-Object { $_.Name -ne "Date" }
        foreach ($p in $props) {
            $values = $tempFiltered | ForEach-Object { $_.$($p.Name) } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            if ($values) {
                $sum = [decimal]0
                $count = 0
                foreach ($v in $values) {
                    $sum += [decimal]$v
                    $count++
                }
                $avg = if ($count -gt 0) { $sum / $count } else { 0 }
                $tempText += "$($p.Name): {0:N2}`r`n" -f $avg
            }
            else {
                $tempText += "$($p.Name): Not measured`r`n"
            }
        }
    }
    else {
        $tempText += "No temperature data`r`n"
    }
    # ================= TRAFFIC (FIXED PRECISION SUM) =================
    $trafficText = ""
    if ($trafficFiltered) {
        $grouped = $trafficFiltered | Group-Object Interface
        foreach ($g in $grouped) {
            $totalDownload = [decimal]0
            $totalUpload   = [decimal]0
            $totalTotal    = [decimal]0
            foreach ($row in $g.Group) {
                $parts = $row.'Download_Bytes/Upload_Bytes/Total_Bytes' -split "/"
                if ($parts.Count -eq 3) {
                    $totalDownload += [decimal]$parts[0]
                    $totalUpload   += [decimal]$parts[1]
                    $totalTotal    += [decimal]$parts[2]
                }
            }
            $trafficText += @"

Traffic [$($g.Name)]
Download: $(Convert-Bytes $totalDownload)
Upload:   $(Convert-Bytes $totalUpload)
Total:    $(Convert-Bytes $totalTotal)

"@
        }
        # ================= GLOBAL TRAFFIC (FIXED PRECISION) =================
        $gDownload = [decimal]0
        $gUpload   = [decimal]0
        $gTotal    = [decimal]0
        foreach ($row in $trafficFiltered) {
            $parts = $row.'Download_Bytes/Upload_Bytes/Total_Bytes' -split "/"
            if ($parts.Count -eq 3) {
                $gDownload += [decimal]$parts[0]
                $gUpload   += [decimal]$parts[1]
                $gTotal    += [decimal]$parts[2]
            }
        }
        $trafficText += @"

Global Traffic (All Interfaces)
Download: $(Convert-Bytes $gDownload)
Upload:   $(Convert-Bytes $gUpload)
Total:    $(Convert-Bytes $gTotal)
"@
    }
    # ================= FINAL =================
@"

Date: $($start.ToString("dddd, dd MMMM yyyy")) - $($end.ToString("dddd, dd MMMM yyyy"))
-Hardware Data:

$diskText
$loadText
$tempText
-Network Data:
$trafficText
"@
}

# ================= GLOBAL COLOR =================
$global:MonthColors = @{}
# ================= COLOR =================
function Get-MonthColor($monthName) {
    if ($global:MonthColors.ContainsKey($monthName)) {
        return $global:MonthColors[$monthName]
    }
    $color = Get-RandomColor
    $global:MonthColors[$monthName] = $color
    return $color
}
# ================= DATE =================
function Format-DateLine($dateString) {
    $date = [datetime]::Parse($dateString)
    $dayName = $date.DayOfWeek
    $month = $date.ToString("MMMM")
    $year = $date.Year
    $fixed = $date.ToString("dd-MM-yyyy")
    return @{
        Text = "$dayName $month $year - $fixed"
        Month = $month
    }
}

# ================= ALL FORM =================
function Show-AllData($container, $text) {
    $container.AutoScroll = $true
    $container.SuspendLayout()
    $container.Controls.Clear()
    # ================= TEXT VIEW =================
    $box = New-Object Windows.Forms.RichTextBox
    $box.ReadOnly = $true
    $form.SuspendLayout()
	$box.Dock = "Fill"
	$form.Controls.Add($box)
	$form.ResumeLayout()
    $box.BackColor = [Drawing.Color]::FromArgb(45,45,45)
    $box.ForeColor = "White"
    $box.BorderStyle = "None"
    $box.Font = New-Object Drawing.Font("Segoe UI",12)
	# ================= TITLE INSIDE TEXT (CENTERED) =================
	$box.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Center
	$box.SelectionColor = [Drawing.Color]::FromArgb(0,200,255)
	$box.SelectionFont = New-Object Drawing.Font("Segoe UI",20,[Drawing.FontStyle]::Bold)
	$box.AppendText("All System Data`r")
	# reset back to left alignment for normal text
	$box.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Left
    $lines = $text -split "`r?`n"
    $currentColor = [Drawing.Color]::White
    foreach ($line in $lines) {
        if ($line -match "^Disk:") {
            $currentColor = [Drawing.Color]::FromArgb(0,200,255)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match "^Load:") {
            $currentColor = [Drawing.Color]::FromArgb(0,255,150)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match "^Temperatures:") {
            $currentColor = [Drawing.Color]::FromArgb(255,180,0)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match "^Traffic") {
            $currentColor = [Drawing.Color]::FromArgb(103, 240, 101)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
		elseif ($line -match "^Global Traffic") {
            $currentColor = [Drawing.Color]::FromArgb(66, 189, 189)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
		elseif ($line -match "^Status") {
            $currentColor = [Drawing.Color]::FromArgb(39, 176, 245)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match "^Date:") {
            $parts = $line.Split(":",2)
            try {
                $dt = [datetime]::Parse($parts[1].Trim())
                $formatted = $dt.ToString("dddd, dd MMMM yyyy")
            } catch {
                $formatted = $parts[1].Trim()
            }
            $box.SelectionColor = [Drawing.Color]::White
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",18,[Drawing.FontStyle]::Bold)
            $box.AppendText("Date: ")

            $box.SelectionColor = [Drawing.Color]::Yellow
            $box.AppendText($formatted + "`r`n`r`n")
            continue
        }
        elseif ($line -match ":") {
            $parts = $line.Split(":",2)
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",13,[Drawing.FontStyle]::Bold)
            $box.AppendText($parts[0] + ": ")
            $box.SelectionColor = $currentColor
            $box.AppendText($parts[1] + "`r`n")
            continue
        }
        $box.AppendText($line + "`r`n")
    }
    $container.Controls.Add($box)
    # ================= FOOTER =================
    $footer = New-Object Windows.Forms.Panel
    $footer.Height = 60
    $footer.Dock = "Bottom"
    $footer.BackColor = [Drawing.Color]::FromArgb(30,30,30)
    # ================= GRAPH BUTTON =================
    $btnGraph = New-Object Windows.Forms.Button
	$btnGraph.Text = "Graphs"
	$btnGraph.Width = 120
	$btnGraph.Height = 35
	$btnGraph.Left = 20
	$btnGraph.Top = 10
	$btnGraph.BackColor = [Drawing.Color]::FromArgb(39,176,245)
	$btnGraph.ForeColor = "White"
	$btnGraph.FlatStyle = "Flat"
	$btnGraph.FlatAppearance.BorderSize = 0
	$btnGraph.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(60,200,255)
	$btnGraph.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(20,140,200)
	$btnGraph.Font = New-Object Drawing.Font("Segoe UI",10,[Drawing.FontStyle]::Bold)
	$btnGraph.Cursor = [System.Windows.Forms.Cursors]::Hand
    # ================= BACK BUTTON =================
    $btnBack = New-Object Windows.Forms.Button
	$btnBack.Text = "Back"
	$btnBack.Width = 120
	$btnBack.Height = 35
	$btnBack.Left = 160
	$btnBack.Top = 10
	$btnBack.BackColor = [Drawing.Color]::FromArgb(80,80,80)
	$btnBack.ForeColor = "White"
	$btnBack.FlatStyle = "Flat"
	$btnBack.FlatAppearance.BorderSize = 0
	$btnBack.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(110,110,110)
	$btnBack.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(50,50,50)
	$btnBack.Font = New-Object Drawing.Font("Segoe UI",10,[Drawing.FontStyle]::Bold)
	$btnBack.Cursor = [System.Windows.Forms.Cursors]::Hand
	# ================= GRAPH MODE (ONLY _all) =================
	$btnGraph.Add_Click({
    # ================= LOAD ONLY _ALL PNG =================
	$archivePath = "$AppRoot\Charts"
	if (-not (Test-Path $archivePath)) {
		[System.Windows.Forms.MessageBox]::Show("Graphs folder not found")
		return
	}
	$allFiles = Get-ChildItem $archivePath -Filter "*_Alld*.png"
	if (-not $allFiles -or $allFiles.Count -eq 0) {
		[System.Windows.Forms.MessageBox]::Show("No graphs found")
		return
	}
	# ================= GET LATEST MODIFICATION DATE (GLOBAL) =================
	$latestDate = $allFiles |
		ForEach-Object { $_.LastWriteTime } |
		Sort-Object -Descending |
		Select-Object -First 1
	if (-not $latestDate) {
		[System.Windows.Forms.MessageBox]::Show("No valid modification dates in files")
		return
	}
	$dateString = $latestDate.ToString("yyyy-MM-dd")
	# ================= FILTER FINAL (_all + latest modified date only) =================
	$files = $allFiles | Where-Object {
		$_.Name -like "*_Alld*" -and $_.LastWriteTime.ToString("yyyy-MM-dd") -eq $dateString
	}
	if (-not $files -or $files.Count -eq 0) {
		[System.Windows.Forms.MessageBox]::Show("No latest _All graphs found")
		return
	}
    if ($script:graphPanel) {
        $container.Controls.Remove($script:graphPanel)
        $script:graphPanel.Dispose()
        $script:graphPanel = $null
    }
    # ================= SCROLL PANEL =================
    $scroll = New-Object Windows.Forms.Panel
    $scroll.BackColor = [Drawing.Color]::FromArgb(45,45,45)
    $scroll.AutoScroll = $true
    # 🔥 CRITICAL FIX: prevent footer overlap
    $scroll.Dock = "Fill"
    $scroll.Padding = New-Object Windows.Forms.Padding(0,0,0,60)
    $script:graphPanel = $scroll
    # ================= HEADER =================
	$header = New-Object Windows.Forms.Panel
	$header.Height = 80
	$header.Dock = "Top"
	$header.BackColor = [Drawing.Color]::FromArgb(30,30,30)
	# TITLE
	$title = New-Object Windows.Forms.Label
	$title.Text = "Graphs - ALL DATA"
	$title.Font = New-Object Drawing.Font("Segoe UI",18,[Drawing.FontStyle]::Bold)
	$title.ForeColor = [Drawing.Color]::FromArgb(0,200,255)   # 🔵 боја
	$title.AutoSize = $true
	$title.Left = 20
	$title.Top = 10
	# SUBTITLE
	$subtitle = New-Object Windows.Forms.Label
	$subtitle.Text = "Graphs from: $latestYear $dateString"
	$subtitle.Font = New-Object Drawing.Font("Segoe UI",12,[Drawing.FontStyle]::Italic)
	$subtitle.ForeColor = [Drawing.Color]::FromArgb(180,180,180)
	$subtitle.AutoSize = $true
	$subtitle.Left = 20
	$subtitle.Top = 55
	$header.Controls.Add($title)
	$header.Controls.Add($subtitle)
	$scroll.Controls.Add($header)
	$scroll.Controls.SetChildIndex($header,0)
    # ================= GRID =================
    $col = 0
    $row = 0
	$tooltip = New-Object System.Windows.Forms.ToolTip
	$tooltip.AutoPopDelay = 5000
	$tooltip.InitialDelay = 200
	$tooltip.ReshowDelay = 100
	$tooltip.ShowAlways = $true
    foreach ($file in $files) {
        $pic = New-Object Windows.Forms.PictureBox
        $pic.Width = 420
        $pic.Height = 320
        $pic.SizeMode = "Zoom"
        try {
            $pic.Image = [System.Drawing.Image]::FromFile($file.FullName)
        } catch { continue }
        $pic.Tag = $file.FullName
		$name = $file.Name.ToLower()
		$type = ""
		if ($name -match "disk") { $type = "Disk" }
		elseif ($name -match "load") { $type = "Load" }
		elseif ($name -match "temp") { $type = "Temperatures" }
		elseif ($name -match "table") { $type = "Network" }
		else { $type = "Unknown" }
		$tooltip.SetToolTip($pic, "Type: $type`nFile: $($file.Name)")
        # OPEN IMAGE
        $pic.Add_Click({ Start-Process $this.Tag })
        # HOVER ZOOM
        $pic.Add_MouseEnter({
            $this.Width = 440
            $this.Height = 340
            $this.BringToFront()
        })
        $pic.Add_MouseLeave({
            $this.Width = 420
            $this.Height = 320
        })
        $pic.Left = 20 + ($col * 450)
        $pic.Top  = 95 + ($row * 350)
        $scroll.Controls.Add($pic)
        $col++
        if ($col -eq 2) {
            $col = 0
            $row++
        }
    }
    # ================= ADD GRAPH PANEL =================
    $container.Controls.Add($scroll)
    $container.Controls.SetChildIndex($scroll,0)
    })
	# ================= BACK =================
	$btnBack.Add_Click({
		if ($script:graphPanel) {
				$container.Controls.Remove($script:graphPanel)
				$script:graphPanel.Dispose()
				$script:graphPanel = $null
			}
			if ($script:mainTextBox) {
				$container.Controls.Add($script:mainTextBox)
				$container.Controls.SetChildIndex($script:mainTextBox,1)
			}
		})
	# ================= FOOTER =================
	$footer.Controls.Add($btnGraph)
	$footer.Controls.Add($btnBack)
	$container.Controls.Add($footer)
	$container.ResumeLayout()
}

# ================= STATUS FORM =================
function Show-InlineView($container, $text) {
    $container.AutoScroll = $true
    $container.SuspendLayout()
    $container.Controls.Clear()
    $box = New-Object Windows.Forms.RichTextBox
    $box.ReadOnly = $true
    $form.SuspendLayout()
	$box.Dock = "Fill"
	$form.Controls.Add($box)
	$form.ResumeLayout()
    $box.BackColor = [Drawing.Color]::FromArgb(45,45,45)
    $box.ForeColor = "White"
    $box.BorderStyle = "None"
    $box.Font = New-Object Drawing.Font("Segoe UI",12)
	# ================= TITLE INSIDE TEXT (CENTERED) =================
	$box.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Center
	$box.SelectionColor = [Drawing.Color]::FromArgb(0,200,255)
	$box.SelectionFont = New-Object Drawing.Font("Segoe UI",20,[Drawing.FontStyle]::Bold)
	$box.AppendText("System Data Status`r")
	# reset back to left alignment for normal text
	$box.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Left
    # 👉 SAME POPUP LOGIC (no UI splitting)
    $lines = $text -split "`r?`n"
    $currentColor = [Drawing.Color]::White
    foreach ($line in $lines) {
        if ($line -match "^Disk:") {
            $currentColor = [Drawing.Color]::FromArgb(0,200,255)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match "^Graphs Folder Status") {
            $currentColor = [Drawing.Color]::FromArgb(66, 214, 147)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
		elseif ($line -match "^Status") {
            $currentColor = [Drawing.Color]::FromArgb(39, 176, 245)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match ":") {
            $parts = $line.Split(":",2)
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",13,[Drawing.FontStyle]::Bold)
			$box.AppendText($parts[0] + ": ")
            $box.SelectionColor = $currentColor
            $box.AppendText($parts[1] + "`r`n")
            continue
        }
        $box.AppendText($line + "`r`n")
    }
    $container.Controls.Add($box)
	# ================= FOOTER =================
		$footer = New-Object Windows.Forms.Panel
		$footer.Height = 60
		$footer.Dock = "Bottom"
		$footer.BackColor = [Drawing.Color]::FromArgb(30,30,30)
		# ================= DELETE BUTTON =================
		$btnDelete = New-Object Windows.Forms.Button
		$btnDelete.Text = "Delete"
		$btnDelete.Width = 120
		$btnDelete.Height = 35
		$btnDelete.Left = 20
		$btnDelete.Top = 10
		$btnDelete.BackColor = [Drawing.Color]::FromArgb(220,60,60)
		$btnDelete.ForeColor = "White"
		$btnDelete.FlatStyle = "Flat"
		$btnDelete.FlatAppearance.BorderSize = 0
		$btnDelete.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(245, 73, 73)
		$btnDelete.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(222, 42, 42)
		$btnDelete.Font = New-Object Drawing.Font("Segoe UI",10,[Drawing.FontStyle]::Bold)
		$btnDelete.Cursor = [System.Windows.Forms.Cursors]::Hand
		# ================= CONFIRMATION =================
		$btnDelete.Add_Click({
			$res = [System.Windows.Forms.MessageBox]::Show(
			    "This will delete ALL data in folder Charts !`n`nAre you sure you want to delete ALL data ?",
				"Confirm Delete",
				[System.Windows.Forms.MessageBoxButtons]::YesNo,
				[System.Windows.Forms.MessageBoxIcon]::Warning
			)
			if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
				$path = "$AppRoot\Charts"
				try {
					Get-ChildItem $path -File -ErrorAction Stop | Remove-Item -Force
					[System.Windows.Forms.MessageBox]::Show("Deleted successfully")
				}
				catch {
					[System.Windows.Forms.MessageBox]::Show("Delete failed: $($_.Exception.Message)")
				}
			}
		})
		$footer.Controls.Add($btnDelete)
		$container.Controls.Add($footer)
		$container.ResumeLayout()
	}

# ================= POPUP FORM =================
function Show-Popup($text, $period, $startDate, $endDate) {
	if ([string]::IsNullOrWhiteSpace($text)) { return }
    $script:popupOpen = $true
	# ================= POPUP FORM =================
	$popup = New-Object Windows.Forms.Form
	$popup.Size = New-Object Drawing.Size(950,700)
	$popup.StartPosition = "CenterScreen"
	$popup.BackColor = [Drawing.Color]::FromArgb(20,20,20)
	$popup.Text = "Detail View"
	$popup.Tag = @{
    Period = $period
    Start  = $startDate
    End    = $endDate
    }
	$popup.Add_FormClosed({
		$script:popupOpen = $false
    })
	$popup.FormBorderStyle = "Sizable"
	$popup.MaximizeBox = $true
	$popup.MinimizeBox = $true
	$popup.Padding = New-Object Windows.Forms.Padding(10)
	$popup.Add_Paint({
		$pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(60,60,60),2)
		$_.Graphics.DrawRectangle($pen,0,0,$popup.Width-1,$popup.Height-1)
	})
	# ================= RICH TEXT =================
	$box = New-Object Windows.Forms.RichTextBox
	$box.ReadOnly = $true
	$box.Dock = "Fill"
	$box.BackColor = [Drawing.Color]::FromArgb(45,45,45)
	$box.ForeColor = "White"
	$box.BorderStyle = "None"
	$box.Font = New-Object Drawing.Font("Segoe UI",12)
	$box.ScrollBars = "Vertical"
	$box.HideSelection = $true
	$box.TabStop = $false
	$box.SelectionStart = 0
	$box.SelectionLength = 0
    # 🔥 IMPORTANT (BACK ќе работи)
    $script:mainTextBox = $box
	# ================= STYLING =================
    $lines = $text -split "`r?`n"
    $currentColor = [Drawing.Color]::White
    foreach ($line in $lines) {
        if ($line -match "^Disk:") {
            $currentColor = [Drawing.Color]::FromArgb(0,200,255)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match "^Load:") {
            $currentColor = [Drawing.Color]::FromArgb(0,255,150)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match "^Temperatures:") {
            $currentColor = [Drawing.Color]::FromArgb(255,180,0)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match "^Traffic") {
            $currentColor = [Drawing.Color]::FromArgb(103, 240, 101)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match "^Global Traffic") {
            $currentColor = [Drawing.Color]::FromArgb(66,189,189)
            $box.SelectionColor = $currentColor
            $box.SelectionFont = New-Object Drawing.Font("Segoe UI",16,[Drawing.FontStyle]::Bold)
        }
        elseif ($line -match "^Date:") {
			$parts = $line.Split(":",2)
			try {
				$dt = [datetime]::Parse($parts[1].Trim())
				$formatted = $dt.ToString("dddd, dd MMMM yyyy")
			} catch {
				$formatted = $parts[1].Trim()
			}
			$box.SelectionColor = [Drawing.Color]::White
			$box.SelectionFont = New-Object Drawing.Font("Segoe UI",18,[Drawing.FontStyle]::Bold)
			$box.AppendText("Date: ")
			$box.SelectionColor = [Drawing.Color]::Yellow
			$box.AppendText($formatted + "`r`n`r`n")
			continue
		}
        elseif ($line -match ":") {
            $parts = $line.Split(":",2)
			$box.SelectionColor = [Drawing.Color]::White
			$box.SelectionFont = New-Object Drawing.Font("Segoe UI",13,[Drawing.FontStyle]::Bold)
			$box.AppendText($parts[0] + ": ")
            $box.SelectionColor = $currentColor
            $box.AppendText($parts[1] + "`r`n")
            continue
        }
        $box.AppendText($line + "`r`n")
    }
    $popup.Controls.Add($box)
	# ================= FOOTER =================
	$footer = New-Object Windows.Forms.Panel
	$footer.Height = 60
	$footer.Dock = "Bottom"
	$footer.BackColor = [Drawing.Color]::FromArgb(30,30,30)
	# ================= METRICS MAP (GLOBAL - ONLY ONCE) =================
	$script:MetricsMap = @{
		"disk"    = "$AppRoot\Data\disk_all.csv"
		"load"    = "$AppRoot\Data\load_all.csv"
		"temp"    = "$AppRoot\Data\temperatures_all.csv"
		"traffic" = "$AppRoot\Data\traffic.csv"
	}
# ================= METRICS LOADER (GLOBAL - ONLY ONCE) =================
function Get-MetricsData {
	param(
		[datetime]$startDate,
		[datetime]$endDate
	)
		$result = @{
			disk    = @()
			load    = @()
			temp    = @()
			traffic = @()
		}
		foreach ($key in $script:MetricsMap.Keys) {
			$path = $script:MetricsMap[$key]
			if (Test-Path $path) {
				$data = Import-Csv $path
				$result[$key] = foreach ($row in $data) {
		try {
			$d = [datetime]$row.Date

			if ($d -ge $startDate -and $d -le $endDate) {
				$row
			}
		}
		catch {
			continue
		}
	}
			}
		}
		return $result
	}
	# ================= GRAPH BUTTON =================
	$btnGraph = New-Object Windows.Forms.Button
	$btnGraph.Text = "Graphs"
	$btnGraph.Width = 120
	$btnGraph.Height = 35
	$btnGraph.Left = 20
	$btnGraph.Top = 10
	$btnGraph.BackColor = [Drawing.Color]::FromArgb(39,176,245)
	$btnGraph.ForeColor = "White"
	$btnGraph.FlatStyle = "Flat"
	$btnGraph.FlatAppearance.BorderSize = 0
	$btnGraph.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(60,200,255)
	$btnGraph.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(20,140,200)
	$btnGraph.Font = New-Object Drawing.Font("Segoe UI",10,[Drawing.FontStyle]::Bold)
	$btnGraph.Cursor = [System.Windows.Forms.Cursors]::Hand
	# ================= CLICK =================
	$btnGraph.Add_Click({
		$meta = $popup.Tag
		if (-not $meta) {
			[System.Windows.Forms.MessageBox]::Show("No calendar context found")
			return
		}
		$localPeriod = $meta.Period
	if ($localPeriod -eq "DAY") {
		# НЕ користи datetime од meta (тоа ти е broken)
		$localStartDate = $null
		$localEndDate   = $null
	}
	else {

		$localStartDate = [datetime]$meta.Start
		$localEndDate   = [datetime]$meta.End
	}
    # ================= ARCHIVE =================
    $archivePath = "$AppRoot\Charts"
    if (-not (Test-Path $archivePath)) {
        [System.Windows.Forms.MessageBox]::Show("Graphs folder not found")
        return
    }
    $allFiles = Get-ChildItem $archivePath -Filter "*.png"
    # ================= PERIOD TOKEN =================
    $periodMap = @{
        "DAY"   = "_1d_"
        "WEEK"  = "_7d_"
        "MONTH" = "_30d_"
        "YEAR"  = "_365d_"
    }
    if (-not $periodMap.ContainsKey($localPeriod)) {
        [System.Windows.Forms.MessageBox]::Show("Invalid period")
        return
    }
    $token = $periodMap[$localPeriod]
    # ================= 🔥 ANCHOR DATE LOGIC =================
    switch ($localPeriod) {
        "DAY" {
			# 🔥 извлечи датум од текстот што веќе го прикажуваш
			$dateLine = ($text -split "`n" | Where-Object { $_ -match "^Date:" })
			if ($dateLine) {
				$raw = $dateLine -replace "Date:\s*", ""
				try {
					$dt = [datetime]$raw
					$anchorDate = $dt.ToString("yyyy-MM-dd")
				}
				catch {
					[System.Windows.Forms.MessageBox]::Show("Invalid DAY date format")
					return
				}
			}
			else {
				[System.Windows.Forms.MessageBox]::Show("Date not found in text")
				return
			}
		}
        "WEEK" {
            # end of week (Sunday)
            $dayOfWeek = [int]$localStartDate.DayOfWeek
            if ($dayOfWeek -eq 0) { $dayOfWeek = 7 }
            $endWeek = $localStartDate.AddDays(7 - $dayOfWeek)
            $anchorDate = $endWeek.ToString("yyyy-MM-dd")
        }
        "MONTH" {
            $endMonth = (Get-Date -Year $localStartDate.Year -Month $localStartDate.Month -Day 1)
            $endMonth = $endMonth.AddMonths(1).AddDays(-1)
            $anchorDate = $endMonth.ToString("yyyy-MM-dd")
        }
        "YEAR" {
            $anchorDate = Get-Date -Year $localStartDate.Year -Month 12 -Day 31
            $anchorDate = $anchorDate.ToString("yyyy-MM-dd")
        }
    }
    # ================= FILTER FILES =================
    $files = $allFiles | Where-Object {
        $_.Name -like "*$token*$anchorDate*"
    }
    if (-not $files -or $files.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No graphs found")
        return
    }
    # ================= UI RESET =================
    if ($script:graphPanel) {
        $popup.Controls.Remove($script:graphPanel)
        $script:graphPanel.Dispose()
        $script:graphPanel = $null
    }
    if ($script:mainTextBox) {
        $popup.Controls.Remove($script:mainTextBox)
    }
    # ================= SCROLL PANEL =================
	$scroll = New-Object Windows.Forms.Panel
	$scroll.Dock = "Fill"
	$scroll.AutoScroll = $true
	$scroll.BackColor = [Drawing.Color]::FromArgb(45,45,45)
	$script:graphPanel = $scroll
	$popup.Controls.Add($scroll)
	$popup.Controls.SetChildIndex($scroll,0)
	# ================= EXTRACT DATE FROM PNG =================
	$displayDate = ""
	if ($files.Count -gt 0) {
		$firstFile = $files[0].Name
		if ($firstFile -match "\d{4}-\d{2}-\d{2}") {
			try {
				$dt = [datetime]::Parse($matches[0])
				$displayDate = $dt.ToString("dddd, dd MMMM yyyy")
			}
			catch {
				$displayDate = $matches[0]
			}
		}
	}
	# ================= HEADER =================
	$header = New-Object Windows.Forms.Panel
	$header.Height = 80
	$header.Dock = "Top"
	$header.BackColor = [Drawing.Color]::FromArgb(30,30,30)
	# TITLE
	$title = New-Object Windows.Forms.Label
	$title.Text = "Graphs - $localPeriod"
	$title.Font = New-Object Drawing.Font("Segoe UI",18,[Drawing.FontStyle]::Bold)
	$title.ForeColor = [Drawing.Color]::FromArgb(0,200,255)   # 🔵 боја
	$title.AutoSize = $true
	$title.Left = 20
	$title.Top = 10
	# DATE
	$dateLabel = New-Object Windows.Forms.Label
	$dateLabel.Text = $displayDate
	$dateLabel.Font = New-Object Drawing.Font("Segoe UI",12,[Drawing.FontStyle]::Italic)
	$dateLabel.ForeColor = [Drawing.Color]::FromArgb(180,180,180)
	$dateLabel.AutoSize = $true
	$dateLabel.Left = 22
	$dateLabel.Top = 45
	$header.Controls.Add($title)
	$header.Controls.Add($dateLabel)
	$scroll.Controls.Add($header)
	$scroll.Controls.SetChildIndex($header,0)
	# ================= GRID (2 PER ROW) =================
	$col = 0
	$row = 0
	$tooltip = New-Object System.Windows.Forms.ToolTip
	$tooltip.AutoPopDelay = 5000
	$tooltip.InitialDelay = 200
	$tooltip.ReshowDelay = 100
	$tooltip.ShowAlways = $true
	foreach ($file in $files) {
    $pic = New-Object Windows.Forms.PictureBox
    $pic.Width = 415
    $pic.Height = 315
    $pic.SizeMode = "Zoom"
    try {
        $pic.Image = [System.Drawing.Image]::FromFile($file.FullName)
    } catch {
        continue
    }
    $pic.Tag = $file.FullName
	$name = $file.Name.ToLower()
		$type = ""
		if ($name -match "disk") { $type = "Disk" }
		elseif ($name -match "load") { $type = "Load" }
		elseif ($name -match "temp") { $type = "Temperatures" }
		elseif ($name -match "table") { $type = "Network" }
		else { $type = "Unknown" }
		$tooltip.SetToolTip($pic, "Type: $type`nFile: $($file.Name)")
    # ================= CLICK =================
    $pic.Add_Click({
        Start-Process $this.Tag
    })
    # ================= HOVER ZOOM =================
    $pic.Add_MouseEnter({
        $this.Width  = 430
        $this.Height = 330
        $this.BringToFront()
    })
    $pic.Add_MouseLeave({
        $this.Width  = 415
        $this.Height = 315
    })
    # ================= POSITION (2 COLUMNS GRID) =================
    $offsetY = $header.Height + 20
    $pic.Left = 20 + ($col * 435)
    $pic.Top  = $offsetY + ($row * 335)
    $scroll.Controls.Add($pic)
    $col++
    if ($col -eq 2) {
        $col = 0
        $row++
		}
	}
	})
	# ================= BACK BUTTON =================
	$btnExtra = New-Object Windows.Forms.Button
	$btnExtra.Text = "Back"
	$btnExtra.Width = 120
	$btnExtra.Height = 35
	$btnExtra.Left = 160
	$btnExtra.Top = 10
	$btnExtra.BackColor = [Drawing.Color]::FromArgb(80,80,80)
	$btnExtra.ForeColor = "White"
	$btnExtra.FlatStyle = "Flat"
	$btnExtra.FlatAppearance.BorderSize = 0
	$btnExtra.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(110,110,110)
	$btnExtra.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(50,50,50)
	$btnExtra.Font = New-Object Drawing.Font("Segoe UI",10,[Drawing.FontStyle]::Bold)
	$btnExtra.Cursor = [System.Windows.Forms.Cursors]::Hand
	$btnExtra.Add_Click({
		if ($script:graphPanel) {
			$popup.Controls.Remove($script:graphPanel)
			$script:graphPanel.Dispose()
			$script:graphPanel = $null
		}
		if ($script:mainTextBox) {
			$popup.Controls.Add($script:mainTextBox)
			$popup.Controls.SetChildIndex($script:mainTextBox,0)
		}
	})
	$footer.Controls.Add($btnGraph)
	$footer.Controls.Add($btnExtra)
	$popup.Controls.Add($footer)
	
	[void]$popup.ShowDialog()
	}

# ================= FOOTER MONTH =================
function Format-MonthFooter($dateString) {
    try {
        $date = [datetime]::Parse($dateString)
        return "{0} {1} {2}" -f $date.ToString("MMMM"), $date.Day, $date.Year
    }
    catch {
        return "Incorrect Date"
    }
}
# ================= FILTER DAY WEEK MONTH YEAR ALL =================
function Get-FilteredDates($dataSource, $period) {
    # ================= SAFETY CHECK =================
    if (-not $dataSource -or $dataSource.Count -eq 0) {
        return @()
    }
    # ================= PARSE (CLEAN) =================
    $parsed = $dataSource | ForEach-Object {
        try {
            if ($_.Date) {
                [PSCustomObject]@{
                    Date = [datetime]$_.Date
                }
            }
        } catch {
            # skip invalid rows silently
        }
    } | Where-Object { $_ -ne $null }
    # ================= EMPTY AFTER PARSE =================
    if (-not $parsed -or $parsed.Count -eq 0) {
        return @()
    }
    switch ($period) {
        # ================= DAY =================
        "DAY" {
            return $parsed |
                Sort-Object Date |
                ForEach-Object {
                    [PSCustomObject]@{
                        Label = $_.Date.ToString("dddd dd-MM-yyyy")
                        Start = $_.Date
                        End   = $_.Date
                    }
                }
        }
        # ================= WEEK =================
        "WEEK" {
			return $parsed |
				Group-Object {
					$d = $_.Date
					$dayOfWeek = [int]$d.DayOfWeek
					if ($dayOfWeek -eq 0) { $dayOfWeek = 7 }
					$d.AddDays(-($dayOfWeek - 1)).Date
				} |
				ForEach-Object {
					$start = [datetime]$_.Name
					$end   = $start.AddDays(6)
					$calendar = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
					$weekRule = [System.Globalization.CalendarWeekRule]::FirstFourDayWeek
					$firstDay = [System.DayOfWeek]::Monday
					$weekNumber = $calendar.GetWeekOfYear($start, $weekRule, $firstDay)
					[PSCustomObject]@{
						Label = "Week $weekNumber ($($start.ToString('dd MMM yyyy')) - $($end.ToString('dd MMM yyyy')))"
						Start = $start
						End   = $end
						WeekNumber = $weekNumber   # 🔥 important for sorting
					}
				} |
				Sort-Object WeekNumber
		}
        # ================= MONTH =================
        "MONTH" {
            return $parsed |
                Group-Object {
                    $_.Date.ToString("yyyy-MM")
                } |
                Sort-Object Name |
                ForEach-Object {
                    $parts = $_.Name -split "-"
                    $year  = [int]$parts[0]
                    $month = [int]$parts[1]
                    $start = [datetime]::new($year,$month,1)
                    $end   = $start.AddMonths(1).AddDays(-1)
                    [PSCustomObject]@{
                        Label = $start.ToString("MMMM yyyy")
                        Start = $start
                        End   = $end
                    }
                }
        }
        # ================= YEAR =================
        "YEAR" {
            return $parsed |
                Group-Object { $_.Date.Year } |
                Sort-Object Name |
                ForEach-Object {
                    $year  = [int]$_.Name
                    $start = Get-Date -Year $year -Month 1 -Day 1
                    $end   = Get-Date -Year $year -Month 12 -Day 31
                    [PSCustomObject]@{
                        Label = "$year"
                        Start = $start
                        End   = $end
                    }
                }
        }
        # ================= ALL =================
        "ALL" {
            $start = ($parsed | Sort-Object Date | Select-Object -First 1).Date
            $end   = ($parsed | Sort-Object Date -Descending | Select-Object -First 1).Date
            return @(
                [PSCustomObject]@{
                    Label = "ALL DATA"
                    Start = $start
                    End   = $end
                }
            )
        }
        # ================= DEFAULT =================
        default {
            return @()
        }
    }
}

# ================= DASHBOARD =================
function Show-Dashboard {
   # ================= DATA VALIDATION =================
	$missingFiles = @()
	if (-not (Test-Path "$AppRoot\Data\disk_all.csv")) { $missingFiles += "disk_all.csv" }
	if (-not (Test-Path "$AppRoot\Data\load_all.csv")) { $missingFiles += "load_all.csv" }
	if (-not (Test-Path "$AppRoot\Data\temperatures_all.csv")) { $missingFiles += "temperatures_all.csv" }
	if (-not (Test-Path "$AppRoot\Data\traffic.csv")) { $missingFiles += "traffic.csv" }
	# ================= LOAD DATA =================
	$diskData    = @(Load-CSV "$AppRoot\Data\disk_all.csv")
	$loadData    = @(Load-CSV "$AppRoot\Data\load_all.csv")
	$tempData    = @(Load-CSV "$AppRoot\Data\temperatures_all.csv")
	$trafficData = @(Load-CSV "$AppRoot\Data\traffic.csv")
	# ================= EMPTY CHECK =================
	$isEmpty = (
		(-not $diskData -or $diskData.Count -eq 0) -and
		(-not $loadData -or $loadData.Count -eq 0) -and
		(-not $tempData -or $tempData.Count -eq 0) -and
		(-not $trafficData -or $trafficData.Count -eq 0)
	)
	$statusMessage = ""
	if ($missingFiles.Count -gt 0) {
		$statusMessage = "Missing files:  " + ($missingFiles -join ",  ")
	}
	elseif ($isEmpty) {
		$statusMessage = "Status: All CSV files are empty"
	}
    $form = New-Object Windows.Forms.Form
    $form.Text = "AutoPilot Data System"
    $form.Size = New-Object Drawing.Size(1100,700)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [Drawing.Color]::FromArgb(45,45,45)
	# ================= ICON =================
	$iconPath = "$AppRoot\media\data.ico"
	if (Test-Path $iconPath) {
		$form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
	}
    # ================= STICKY HEADER =================
    $header = New-Object Windows.Forms.Panel
    $header.Height = 60
    $header.Dock = "Top"
    $header.BackColor = [Drawing.Color]::FromArgb(20,20,20)
    $form.Controls.Add($header)
	# ================= LOGO =================
	$logo = New-Object Windows.Forms.PictureBox
	$logo.Size = New-Object Drawing.Size(50,50)   # custom width/height
	$logo.Location = New-Object Drawing.Point(35,10)
	$logo.SizeMode = "Zoom"
	# load image (смени ја патеката)
	$logo.Image = [Drawing.Image]::FromFile("$AppRoot\media\data.ico")
	$logo.Size = New-Object System.Drawing.Size(40, 40)
	$logo.SizeMode = "StretchImage"
	$header.Controls.Add($logo)
	# ================= TITLE =================
	$title = New-Object Windows.Forms.Label
	$title.Text = "AutoPilot Data System"
	$title.Font = New-Object Drawing.Font("Segoe UI",18,[Drawing.FontStyle]::Bold)
	$title.ForeColor = "White"
	$title.AutoSize = $true
	# помести го title десно од логото
	$title.Left = 80
	$title.Top = 15
	$header.Controls.Add($title)
    # ================= STICKY MENU =================
    $menu = New-Object Windows.Forms.Panel
    $menu.Height = 160
    $menu.Dock = "Top"
    $menu.BackColor = [Drawing.Color]::FromArgb(25,25,25)
    $form.Controls.Add($menu)
    $labels = @("DAY","WEEK","MONTH","YEAR","ALL","STATUS","SEARCH")
    $x = 40
    $y = 20
    $isRendering = $false
    foreach ($text in $labels) {
        $panel = New-Object Windows.Forms.Panel
        $panel.Size = New-Object Drawing.Size(160,120)
        $panel.Left = $x
        $panel.Top = $y
        $panel.BackColor = Get-RandomColor
        $panel.Cursor = "Hand"
        $panel.BorderStyle = "FixedSingle"
        $label = New-Object Windows.Forms.Label
        $label.Text = $text
        $label.Dock = "Fill"
        $label.TextAlign = "MiddleCenter"
        $label.Font = New-Object Drawing.Font("Segoe UI",20,[Drawing.FontStyle]::Bold)
        $label.ForeColor = "White"
        $label.Enabled = $false
        $panel.Controls.Add($label)
		# ================= SEARCH CLICK =================
		if ($text -eq "SEARCH") {
			# ================= HOVER EFFECT (ADD THIS) =================
			$panel.Add_MouseEnter({
				$this.BackColor = [Drawing.Color]::FromArgb(226, 237, 121)
				$this.Controls[0].ForeColor = "Black"
			})
			$panel.Add_MouseLeave({
				$this.BackColor = Get-RandomColor
				$this.Controls[0].ForeColor = "White"
			})
			$panel.Add_Click({
				# ================= COLLECT ALL VALID DATES =================
				$allDates = @()
				$allDates += $diskData     | ForEach-Object { $_.Date }
				$allDates += $loadData     | ForEach-Object { $_.Date }
				$allDates += $tempData     | ForEach-Object { $_.Date }
				$allDates += $trafficData  | ForEach-Object { $_.Date }
				$validDates = $allDates |
					Where-Object { $_ } |
					ForEach-Object { 
						try { [datetime]$_ } catch {}
					} |
					Where-Object { $_ } |
					Sort-Object -Unique

				if (-not $validDates -or $validDates.Count -eq 0) {
					[System.Windows.Forms.MessageBox]::Show("No available dates in CSV")
					return
				}
				# ================= CALENDAR FORM (MODERN DARK) =================
				$calForm = New-Object Windows.Forms.Form
				$calForm.Text = "Select Date"
				$calForm.Size = New-Object Drawing.Size(355,288)   # 🔥 bigger
				$calForm.StartPosition = "CenterScreen"
				$calForm.BackColor = [Drawing.Color]::FromArgb(28,28,28)
				$calForm.FormBorderStyle = "FixedDialog"
				$calForm.MaximizeBox = $false
				$calForm.MinimizeBox = $false
				$calForm.Padding = New-Object Windows.Forms.Padding(10)
				# ================= HEADER =================
				$header = New-Object Windows.Forms.Label
				$header.Text = "Select a Date"
				$header.Dock = "Top"
				$header.Height = 40
				$header.TextAlign = "MiddleCenter"
				$header.Font = New-Object Drawing.Font("Segoe UI",14,[Drawing.FontStyle]::Bold)
				$header.ForeColor = [Drawing.Color]::FromArgb(0,200,255)
				$calForm.Controls.Add($header)
				# ================= CONTAINER =================
				$panelCal = New-Object Windows.Forms.Panel
				$panelCal.Dock = "Fill"
				$panelCal.BackColor = [Drawing.Color]::FromArgb(35,35,35)
				$panelCal.Padding = New-Object Windows.Forms.Padding(55)
				# ================= CALENDAR =================
				$calendar = New-Object Windows.Forms.MonthCalendar
				$calendar.MaxSelectionCount = 1
				$calendar.Dock = "Fill"
				# 🔥 DARK STYLE
				$calendar.BackColor = [Drawing.Color]::FromArgb(28,28,28)
				$calendar.ForeColor = [Drawing.Color]::White
				$calendar.TitleBackColor = [Drawing.Color]::FromArgb(0,120,215)
				$calendar.TitleForeColor = [Drawing.Color]::White
				$calendar.TrailingForeColor = [Drawing.Color]::Gray
				# 🔥 RANGE
				$calendar.MinDate = ($validDates | Select-Object -First 1)
				$calendar.MaxDate = ($validDates | Select-Object -Last 1)
				# 🔥 HIGHLIGHT AVAILABLE
				$calendar.BoldedDates = $validDates
				# ================= HOVER EFFECT =================
				$calendar.Add_DateChanged({
					$this.BackColor = [Drawing.Color]::FromArgb(35,35,35)
				})
				# ================= CLICK =================
				$calendar.Add_DateSelected({
					$selectedDate = $calendar.SelectionStart
					$selectedStr  = $selectedDate.ToString("yyyy-MM-dd")
					if ($validDates.Date -notcontains $selectedDate.Date) {
						[System.Windows.Forms.MessageBox]::Show("No data for selected date")
						return
					}
					$result = Build-Line $selectedStr $diskData $loadData $tempData $trafficData
					if (-not [string]::IsNullOrWhiteSpace($result)) {
						Show-Popup $result "DAY" $selectedDate $selectedDate
					}
					else {
						[System.Windows.Forms.MessageBox]::Show("No data found for selected date")
					}
				})
				$panelCal.Controls.Add($calendar)
				$calForm.Controls.Add($panelCal)
				[void]$calForm.ShowDialog()
			})
			# 🔥 IMPORTANT: skip default handler
			$menu.Controls.Add($panel)
			$x += 180
			continue
		}
        # ================= CLICK =================
		$panel.Add_Click({
			if ($script:isRendering) { return }
			$script:isRendering = $true
			$period = $this.Controls[0].Text  # DAY/WEEK/MONTH/YEAR/ALL
			# 🔥 RESET SCROLL
			$container.VerticalScroll.Value = 0
			$container.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
			# 🔥 CLEAR UI
			$container.SuspendLayout()
			$container.Controls.Clear()
			$allDates = @()
			$allDates += $diskData    | ForEach-Object { $_.Date }
			$allDates += $loadData    | ForEach-Object { $_.Date }
			$allDates += $tempData    | ForEach-Object { $_.Date }
			$allDates += $trafficData | ForEach-Object { $_.Date }
			$allDates = $allDates | Where-Object { $_ } | Sort-Object -Unique
			$masterData = $allDates | ForEach-Object {
				[PSCustomObject]@{ Date = $_ }
			}
			$items = Get-FilteredDates $masterData $period
			$offsetY = 20
			# ================= TITLE HEADER =================
			$titlePanel = New-Object Windows.Forms.Panel
			$titlePanel.Size = New-Object Drawing.Size(950,60)
			$titlePanel.Left = 40
			$titlePanel.Top = 10
			# gradient background
			$titlePanel.Add_Paint({
				param($sender, $e)
				$rect = $sender.ClientRectangle
				$brush = New-Object Drawing.Drawing2D.LinearGradientBrush(
					$rect,
					[Drawing.Color]::FromArgb(40,40,40),
					[Drawing.Color]::FromArgb(39, 176, 245),
					[Drawing.Drawing2D.LinearGradientMode]::Vertical
				)
				$e.Graphics.FillRectangle($brush, $rect)
				$brush.Dispose()
			})
			# ================= TITLE =================
			$titleLabel = New-Object Windows.Forms.Label
			$titleLabel.Text = $period
			$titleLabel.ForeColor = "White"
			$titleLabel.Font = New-Object Drawing.Font("Segoe UI",20,[Drawing.FontStyle]::Bold)
			$titleLabel.AutoSize = $true
			$titleLabel.Location = New-Object Drawing.Point(10,15)
			# ================= COUNT =================
			$countLabel = New-Object Windows.Forms.Label
			$countLabel.ForeColor = [Drawing.Color]::FromArgb(255, 255, 255)
			$countLabel.Font = New-Object Drawing.Font("Segoe UI",18,[Drawing.FontStyle]::Bold)
			$countLabel.AutoSize = $true
			$countLabel.Location = New-Object Drawing.Point(788,18)
			$countLabel.Text = "Count: $(@($items).Count)"
			$titleLabel.BackColor = [System.Drawing.Color]::Transparent
			$countLabel.BackColor = [System.Drawing.Color]::Transparent
			$titleLabel.Parent = $titlePanel
			$countLabel.Parent = $titlePanel
			# ================= ADD CONTROLS =================
			$titlePanel.Controls.Add($titleLabel)
			$titlePanel.Controls.Add($countLabel)
			$container.Controls.Add($titlePanel)
			# offset
			$offsetY = 80
			if ($period -eq "ALL" -or $period -eq "STATUS") {
			# ================= NO DATA GUARD =================
			if ($isEmpty) {
				$result = $statusMessage
				$container.Controls.Clear()
				Show-InlineView $container $result
				$container.ResumeLayout()
				$container.PerformLayout()
				$script:isRendering = $false
				return
			}
			if ($period -eq "ALL") {
				$result = Build-Line-Range `
					($items[0].Start) `
					($items[0].End) `
					$diskData `
					$loadData `
					$tempData `
					$trafficData
			}
			elseif ($period -eq "STATUS") {
				# ================= COLLECT ALL DATES =================
				$allDates = @()
				$allDates += $diskData     | ForEach-Object { $_.Date }
				$allDates += $loadData     | ForEach-Object { $_.Date }
				$allDates += $tempData     | ForEach-Object { $_.Date }
				$allDates += $trafficData  | ForEach-Object { $_.Date }
				$parsedDates = $allDates |
					Where-Object { $_ } |
					ForEach-Object { [datetime]$_ } |
					Sort-Object -Unique
				if (-not $parsedDates -or $parsedDates.Count -eq 0) {
					$result = $statusMessage
				}
				else {
					# ================= COUNTS =================
					$sorted = $parsedDates | Sort-Object
					$minDate = $sorted | Select-Object -First 1
					$maxDate = $sorted | Select-Object -Last 1
					$totalDays = $parsedDates.Count
					$totalWeeks = ($parsedDates | Group-Object {
						$d = $_
						$dayOfWeek = [int]$d.DayOfWeek
						if ($dayOfWeek -eq 0) { $dayOfWeek = 7 }
						$d.AddDays(-($dayOfWeek - 1)).Date
					}).Count
					$totalMonths = ($parsedDates | Group-Object { $_.ToString("yyyy-MM") }).Count
					$totalYears = ($maxDate.Year - $minDate.Year) + 1
					# 🔥 IMPORTANT: STRUCTURED FORMAT (MATCHES INLINE VIEW STYLES)
					# ================= FILE STATUS (FULL PRO SYSTEM) =================
					$fileStatus = @()
					$files = @(
						@{ Name="disk_all.csv"; Path="$AppRoot\Data\disk_all.csv"; Data=$diskData },
						@{ Name="load_all.csv"; Path="$AppRoot\Data\load_all.csv"; Data=$loadData },
						@{ Name="temperatures_all.csv"; Path="$AppRoot\Data\temperatures_all.csv"; Data=$tempData },
						@{ Name="traffic.csv"; Path="$AppRoot\Data\traffic.csv"; Data=$trafficData }
					)
					foreach ($f in $files) {
						$exists = Test-Path $f.Path
						$rows   = if ($f.Data) { $f.Data.Count } else { 0 }
						# ================= LAST UPDATE (FIXED MAX DATE) =================
						$lastDate = $null
						try {
							if ($f.Data -and $f.Data.Count -gt 0) {
								$dates = $f.Data | ForEach-Object { $_.Date } | Where-Object { $_ }
								if ($dates.Count -gt 0) {
									$lastDate = ($dates |
										ForEach-Object { [datetime]$_ } |
										Sort-Object -Descending |
										Select-Object -First 1)
								}
							}
						} catch {}
						# ================= AGE =================
						$daysOld = if ($lastDate) {
							(New-TimeSpan -Start $lastDate -End (Get-Date)).Days
						} else {
							$null
						}
						# ================= STATUS + HEALTH =================
						if (-not $exists) {
							$status = "MISSING"
							$health = 0
						}
						elseif ($rows -eq 0) {
							$status = "EMPTY"
							$health = 10
						}
						elseif ($rows -lt 5) {
							$status = "LOW DATA"
							$health = 40
						}
						else {
							$status = "ACTIVE"
							$health = 70
							# boost rows
							if ($rows -ge 50) { $health += 15 }
							if ($rows -ge 200) { $health += 10 }
							# age penalty
							if ($daysOld -ne $null) {
								if ($daysOld -le 1) { $health += 10 }
								elseif ($daysOld -le 3) { $health += 5 }
								elseif ($daysOld -ge 7) { $health -= 15 }
								elseif ($daysOld -ge 14) { $health -= 30 }
							}
						}
						# clamp
						if ($health -lt 0) { $health = 0 }
						if ($health -gt 100) { $health = 100 }
						# ================= FINAL LINE =================
						$fileStatus += "$($f.Name): $status  |  Rows: $rows  |  Last Update: $lastDate  |  Age: $daysOld days  |  Health: $health/100"
					}
					$fileStatusText = ($fileStatus -join "`r`n")
					# ================= FINAL RESULT =================
					$archiveFolder = "$AppRoot\Charts"
					$folderInfoText = ""
					if (Test-Path $archiveFolder) {
						$items = Get-ChildItem $archiveFolder -File -ErrorAction SilentlyContinue
						$count = $items.Count
						$sizeBytes = ($items | Measure-Object -Property Length -Sum).Sum
						$sizeMB = [math]::Round($sizeBytes / 1MB, 2)
						$byType = $items | Group-Object Extension | ForEach-Object {
							"$($_.Name): $($_.Count)"
						}
						$folderInfoText = @"
Graphs Folder Status

-Graphs Folder:

Path: $archiveFolder
Items: $count
Size: $sizeMB MB

Types:
$($byType -join "`r`n")

"@
						}
						else {
							$folderInfoText = "Graphs folder not found: $archiveFolder"
						}
						$result = @"

Status

-Data:

Total Days: $totalDays
Total Weeks: $totalWeeks
Total Months: $totalMonths
Total Years: $totalYears

-Csv File:

$fileStatusText

$folderInfoText

"@
            }
				}
				# ================= RENDER =================
				$container.Controls.Clear()
				if ($period -eq "ALL") {
					Show-AllData $container $result
				}
				else {
					Show-InlineView $container $result
				}
				$container.ResumeLayout()
				$container.PerformLayout()
				$script:isRendering = $false
				return
			}
			$script:lastClickTime = Get-Date
			foreach ($item in $items) {
				$startDate = $item.Start
				$endDate   = $item.End
				$label     = $item.Label
				$monthColor = Get-MonthColor ($startDate.ToString("MMMM"))
				$card = New-Object Windows.Forms.Panel
				$card.Size = New-Object Drawing.Size(950,55)
				$card.Left = 40
				$card.Top = $offsetY
				$card.BackColor = $monthColor
				$card.Cursor = "Hand"
				$card.Padding = New-Object Windows.Forms.Padding(15,10,15,10)
				# ✅ TAG FIX
				if ($period -eq "DAY") {
					$card.Tag = @{
						Period = "DAY"
						Date   = $startDate
						Color  = $monthColor
					}
				}
				else {
					$card.Tag = @{
						Period = $period
						Start  = $startDate
						End    = $endDate
						Color  = $monthColor
					}
				}
				# LABEL
				$lbl = New-Object Windows.Forms.Label
				$lbl.Text = $label
				$lbl.Dock = "Fill"
				$lbl.Font = New-Object Drawing.Font("Segoe UI",15,[Drawing.FontStyle]::Bold)
				$lbl.ForeColor = "#000000"
				# RIGHT LABEL
				$right = New-Object Windows.Forms.Label
				# 🔥 DYNAMIC YEAR FROM DATA (not system / not hardcoded)
				$startYear = $startDate.Year
				$endYear   = $endDate.Year
				if ($period -eq "DAY") {
					$right.Text = $startDate.ToString("dd MMM yyyy")
				}
				else {
					if ($startYear -eq $endYear) {
						# same year → show once
						$right.Text = "$($startDate.ToString('dd MMM')) - $($endDate.ToString('dd MMM yyyy'))"
					}
					else {
						# different years → show both
						$right.Text = "$($startDate.ToString('dd MMM yyyy')) - $($endDate.ToString('dd MMM yyyy'))"
					}
				}
				$right.Dock = "Right"
				$right.Width = 240
				$right.AutoSize = $false
				$right.TextAlign = "MiddleRight"
				$right.Font = New-Object Drawing.Font("Segoe UI",15,[Drawing.FontStyle]::Bold)
				$right.ForeColor = "#660000"
				# 🔥 CLICK FIX (HERE)
				$clickHandler = {
					if ((Get-Date) - $script:lastClickTime -lt [TimeSpan]::FromMilliseconds(300)) {
						return
					}
					$script:lastClickTime = Get-Date
					$meta = $this.Parent.Tag
					if (-not $meta) { $meta = $this.Tag }
					$period = $meta.Period
					if ($period -eq "DAY") {
						$selectedDate = $meta.Date.ToString("yyyy-MM-dd")
						$result = Build-Line $selectedDate $diskData $loadData $tempData $trafficData
					}
					else {
						$result = Build-Line-Range $meta.Start $meta.End $diskData $loadData $tempData $trafficData
					}
					Show-Popup $result $period $meta.Start $meta.End
				}
				foreach ($ctrl in @($card, $lbl, $right)) {
					$ctrl.Tag = $card.Tag
					$ctrl.Cursor = "Hand"
					$ctrl.Add_Click($clickHandler)
				}
				$card.Controls.Add($right)
				$card.Controls.Add($lbl)
				#$lbl.Enabled = $false
				#$right.Enabled = $false
				# ================= HOVER (SAFE - NO NULL CRASH) =================
				$card.Add_MouseEnter({
					$c = $this.Tag.Color
					if ($null -ne $c) {
						$this.BackColor = [Drawing.Color]::FromArgb(
							255,
							[Math]::Min($c.R + 20,255),
							[Math]::Min($c.G + 20,255),
							[Math]::Min($c.B + 20,255)
						)
					}
				})
				$card.Add_MouseLeave({
					$c = $this.Tag.Color
					if ($null -ne $c) {
						$this.BackColor = $c
					}
				})
				# ================= ADD TO CONTAINER =================
				$container.Controls.Add($card)
				$offsetY += 65
			}
			    $container.ResumeLayout()
				$container.PerformLayout()
				$script:isRendering = $false
		})        
		# hover
        $panel.Add_MouseEnter({
            $this.BackColor = [Drawing.Color]::FromArgb(255, 255, 255)
            $this.Controls[0].ForeColor = "Black"
        })
        $panel.Add_MouseLeave({
            $this.BackColor = Get-RandomColor
            $this.Controls[0].ForeColor = "White"
        })
        $menu.Controls.Add($panel)
        $x += 180
    }
    # ================= MAIN SCROLL PANEL =================
	$container = New-Object Windows.Forms.Panel
	$container.Dock = "Fill"
	$container.AutoScroll = $true
	$container.BackColor = $form.BackColor
	# ================= BACKGROUND IMAGE =================
	$bgPath = "$AppRoot\media\data.ico"   # смени по потреба
	$bgImage = $null
	if (Test-Path $bgPath) {
		$bgImage = [System.Drawing.Image]::FromFile($bgPath)
		$container.Add_Paint({
			param($sender, $e)
			# ако има контроли -> НЕ цртај background
			if ($sender.Controls.Count -gt 0) { return }
			if (-not $bgImage) { return }
			$g = $e.Graphics
			# opacity (0.0 - 1.0)
			$opacity = 0.38
			$colorMatrix = New-Object System.Drawing.Imaging.ColorMatrix
			$colorMatrix.Matrix33 = $opacity
			$imgAttributes = New-Object System.Drawing.Imaging.ImageAttributes
			$imgAttributes.SetColorMatrix($colorMatrix)
			# center positioning
			$x = ($sender.ClientSize.Width - $bgImage.Width) / 2
			$y = ($sender.ClientSize.Height - $bgImage.Height) / 2
			$destRect = New-Object System.Drawing.Rectangle($x, $y, $bgImage.Width, $bgImage.Height)
			$g.DrawImage(
				$bgImage,
				$destRect,
				0, 0,
				$bgImage.Width,
				$bgImage.Height,
				[System.Drawing.GraphicsUnit]::Pixel,
				$imgAttributes
			)
		})
		# redraw on resize / scroll
		$container.Add_Resize({ $container.Invalidate() })
		$container.Add_ControlAdded({ $container.Invalidate() })
		$container.Add_ControlRemoved({ $container.Invalidate() })
	}
	# ================= ADD TO FORM =================
	$form.Controls.Add($container)
	$form.Controls.Add($menu)
	$form.Controls.Add($header)
    # ================= SCROLL FIX (SAFE) =================
    $container.Add_MouseWheel({
        $delta = $_.Delta
        $new = $container.VerticalScroll.Value - ($delta / 2)
        if ($new -lt $container.VerticalScroll.Minimum) {
            $new = $container.VerticalScroll.Minimum
        }
        if ($new -gt $container.VerticalScroll.Maximum) {
            $new = $container.VerticalScroll.Maximum
        }
        $container.VerticalScroll.Value = $new
    })
	# ================= FOOTER =================
	$footer = New-Object Windows.Forms.Panel
	$footer.Height = 40
	$footer.Dock = "Bottom"
	$footer.BackColor = [Drawing.Color]::FromArgb(20,20,20)
	$footerLabel = New-Object Windows.Forms.Label
	$footerLabel.Text = "AutoPilot Automation System"
	$footerLabel.Dock = "Fill"
	$footerLabel.TextAlign = "MiddleCenter"
	$footerLabel.Font = New-Object Drawing.Font("Segoe UI",11,[Drawing.FontStyle]::Bold)
	$footerLabel.ForeColor = [Drawing.Color]::FromArgb(212, 212, 212)
	$footer.Controls.Add($footerLabel)
	$form.Controls.Add($footer)
	# ================= LOGO =================
	$logo = New-Object Windows.Forms.PictureBox
	$logo.Size = New-Object Drawing.Size(22,22)
	$logo.Location = New-Object Drawing.Point(10,7)
	$logo.SizeMode = "StretchImage"
	$logo.BackColor = [Drawing.Color]::Transparent
	$logo.Image = [Drawing.Image]::FromFile("$AppRoot\media\autopilot.ico")
	$footer.Controls.Add($logo)
	$logo.BringToFront()
	$footerLabel.Padding = New-Object System.Windows.Forms.Padding(35,0,0,0)
	$footerLabel.TextAlign = "MiddleLeft"
	# ================= DYNAMIC DAYS INFO =================
	$allDates = @()
	$allDates += $diskData     | ForEach-Object { $_.Date }
	$allDates += $loadData     | ForEach-Object { $_.Date }
	$allDates += $tempData     | ForEach-Object { $_.Date }
	$allDates += $trafficData  | ForEach-Object { $_.Date }
	$uniqueDays = ($allDates | Where-Object { $_ } | Sort-Object -Unique).Count
	# container panel (right side inside footer)
	$dynamicPanel = New-Object Windows.Forms.Panel
	$dynamicPanel.Dock = "Right"
	$dynamicPanel.Width = 200
	$dynamicPanel.BackColor = [Drawing.Color]::FromArgb(20,20,20)
	# "Date for:" label (WHITE)
	$labelText = New-Object Windows.Forms.Label
	$labelText.Text = "Data for:"
	$labelText.ForeColor = [Drawing.Color]::FromArgb(212, 212, 212)
	$labelText.Font = New-Object Drawing.Font("Segoe UI",11,[Drawing.FontStyle]::Bold)
	$labelText.AutoSize = $true
	$labelText.Location = New-Object Drawing.Point(10,10)
	# number label (RED)
	$labelValue = New-Object Windows.Forms.Label
	$labelValue.Text = "$uniqueDays days"
	$labelValue.ForeColor = [Drawing.Color]::FromArgb(39, 176, 245)
	$labelValue.Font = New-Object Drawing.Font("Segoe UI",11,[Drawing.FontStyle]::Bold)
	$labelValue.AutoSize = $true
	$labelValue.Location = New-Object Drawing.Point(78,10)
	$dynamicPanel.Controls.Add($labelText)
	$dynamicPanel.Controls.Add($labelValue)
	$footer.Controls.Add($dynamicPanel)
    # ================= STATUS BAR =================
	if ($statusMessage -ne "") {
		$status = New-Object Windows.Forms.Label
		$status.Text = $statusMessage
		$status.Dock = "Top"
		$status.Height = 35
		$status.TextAlign = "MiddleCenter"
		$status.Font = New-Object Drawing.Font("Segoe UI",15,[Drawing.FontStyle]::Bold)
		$status.ForeColor = "White"
		$status.BackColor = [Drawing.Color]::FromArgb(200, 80, 20)
		$form.Controls.Add($status)
	}
    [void]$form.ShowDialog()
}
# ================= START =================
Show-Dashboard

########################################################################################################### End Data.