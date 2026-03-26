# FUNKCIJA ZA GENERIRANJE NA GRAFIKON - DAY / WEEK / MONTH / YEAR / ALL

#################  LOAD  ###################
function Generate-LoadGraph-Day   { return Generate-LoadGraph -PeriodDays 1 }
function Generate-LoadGraph-Week  { return Generate-LoadGraph -PeriodDays 7 }
function Generate-LoadGraph-Month { return Generate-LoadGraph -PeriodDays 30 }
function Generate-LoadGraph-Year  { return Generate-LoadGraph -PeriodDays 365 }
function Generate-LoadGraph-All   { return Generate-LoadGraph -PeriodDays "All" }

#################  TEMP  ###################
function Generate-TempGraph-Day   { return Generate-TempGraph -PeriodDays 1 }
function Generate-TempGraph-Week  { return Generate-TempGraph -PeriodDays 7 }
function Generate-TempGraph-Month { return Generate-TempGraph -PeriodDays 30 }
function Generate-TempGraph-Year  { return Generate-TempGraph -PeriodDays 365 }
function Generate-TempGraph-All   { return Generate-TempGraph -PeriodDays "All" }

#################  DISK  ###################
function Generate-DiskGraph-Day   { return Generate-DiskGraph -PeriodDays 1 }
function Generate-DiskGraph-Week  { return Generate-DiskGraph -PeriodDays 7 }
function Generate-DiskGraph-Month { return Generate-DiskGraph -PeriodDays 30 }
function Generate-DiskGraph-Year  { return Generate-DiskGraph -PeriodDays 365 }
function Generate-DiskGraph-All   { return Generate-DiskGraph -PeriodDays "All" }

##########  Funkcija za Agregacija  ##############
function Preprocess-Data {
    param(
        [object[]]$data,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [AllowNull()]
        [Object]$PeriodDays  # Прифаќа и "All"
    )

    function Format-Number {
        param([double]$num)
        if ($null -eq $num -or [double]::IsNaN($num)) { return 0 }
        return "{0:N2}" -f $num
    }

    if (-not $data -or $data.Count -eq 0) { return @() }

    # Автоматски одреди дали е Timestamp или Date
    $dateField = if ($data[0].PSObject.Properties.Name -contains "Timestamp") { "Timestamp" } else { "Date" }

    # === ФИЛТРИРАЊЕ според период (освен за "All") ===
    if ($PeriodDays -ne "All") {
        $startDate = (Get-Date).AddDays(-[int]$PeriodDays)
        $endDate = Get-Date

        $data = $data | Where-Object {
            try {
                $dt = [datetime]::Parse($_.$dateField)
                ($dt -ge $startDate) -and ($dt -le $endDate)
            } catch { $false }
        }
    }

    if (-not $data -or $data.Count -eq 0) { return @() }

    # ==== 1 ДЕН (24 часа) ====
    if ($PeriodDays -eq 1) {
        foreach ($item in $data) {
            foreach ($prop in $item.PSObject.Properties.Name | Where-Object { $_ -ne $dateField }) {
                $val = [double]$item.$prop
                $item.$prop = Format-Number $val
            }
        }
        return $data
    }

    # ==== 7 ДЕНА - групирање по утро/пладне/вечер ====
    elseif ($PeriodDays -eq 7) {
        $grouped = $data | Group-Object {
            $dt = [datetime]::Parse($_.$dateField)
            $date = $dt.Date
            if ($dt.Hour -lt 12) { "$date-Morning" }
            elseif ($dt.Hour -lt 18) { "$date-Noon" }
            else { "$date-Evening" }
        }

        return $grouped | ForEach-Object {
            $obj = New-Object PSObject
            $obj | Add-Member NoteProperty Timestamp ([datetime]::Parse($_.Group[0].$dateField))
            foreach ($prop in $_.Group[0].PSObject.Properties.Name | Where-Object { $_ -ne $dateField }) {
                $avg = ($_.Group | ForEach-Object { [double]($_.$prop) }) | Measure-Object -Average
                $obj | Add-Member NoteProperty $prop (Format-Number $avg.Average)
            }
            $obj
        }
    }

    # ==== 30 ДЕНА - групирање по ден ====
    elseif ($PeriodDays -eq 30) {
        $grouped = $data | Group-Object { [datetime]::Parse($_.$dateField).Date }

        return $grouped | ForEach-Object {
            $obj = New-Object PSObject
            $obj | Add-Member NoteProperty Timestamp ([datetime]::Parse($_.Group[0].$dateField).Date)
            foreach ($prop in $_.Group[0].PSObject.Properties.Name | Where-Object { $_ -ne $dateField }) {
                $avg = ($_.Group | ForEach-Object { [double]($_.$prop) }) | Measure-Object -Average
                $obj | Add-Member NoteProperty $prop (Format-Number $avg.Average)
            }
            $obj
        }
    }

    # ==== 365 ДЕНА - групирање по недела ====
    elseif ($PeriodDays -eq 365) {
        $grouped = $data | Group-Object {
            $dt = [datetime]::Parse($_.$dateField)
            $year = $dt.Year
            $week = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
                $dt,
                [System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
                [DayOfWeek]::Monday
            )
            "$year-Week$week"
        }

        return $grouped | ForEach-Object {
            $obj = New-Object PSObject
            $obj | Add-Member NoteProperty Timestamp ([datetime]::Parse($_.Group[0].$dateField).Date)
            foreach ($prop in $_.Group[0].PSObject.Properties.Name | Where-Object { $_ -ne $dateField }) {
                $avg = ($_.Group | ForEach-Object { [double]($_.$prop) }) | Measure-Object -Average
                $obj | Add-Member NoteProperty $prop (Format-Number $avg.Average)
            }
            $obj
        }
    }

    # ==== ALL - групирање по месец (YYYY-MM) ====
	elseif ($PeriodDays -eq "All") {
		# Групирање по месец (YYYY-MM), но само до денес (без идни датуми)
		$today = Get-Date
		$filtered = $data | Where-Object {
			try {
				$dt = [datetime]::Parse($_.$dateField)
				$dt -le $today
			} catch { $false }
		}

		if (-not $filtered -or $filtered.Count -eq 0) { return @() }

		$grouped = $filtered | Group-Object {
			$dt = [datetime]::Parse($_.$dateField)
			"{0:yyyy-MM}" -f $dt
		}

		return $grouped | ForEach-Object {
			$obj = New-Object PSObject
			# Зачувуваме првиот датум од месецот како Timestamp
			$obj | Add-Member NoteProperty Timestamp ([datetime]::Parse($_.Group[0].$dateField))
			foreach ($prop in $_.Group[0].PSObject.Properties.Name | Where-Object { $_ -ne $dateField }) {
				$avg = ($_.Group | ForEach-Object { [double]($_.$prop) }) | Measure-Object -Average
				$obj | Add-Member NoteProperty $prop (Format-Number $avg.Average)
			}
			$obj
		}
	}
}

##########  Funkcija za Title  ##############
function Add-PeriodAnnotation {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.DataVisualization.Charting.Chart]$chart,
        [Parameter(Mandatory=$true)][Object]$PeriodDays,
        [Parameter(Mandatory=$true)][string]$GraphType
    )
    # --- Комбиниран текст за Graph Type + период ---
    $periodText = switch ($PeriodDays) {
        1   { "Last 24 Hours" }
        7   { "Last 7 Days" }
        30  { "Last 30 Days" }
        365 { "Last 365 Days" }
        "All" { "All Data" }
        default { "Period Unknown" }
    }
    $combinedText = "$GraphType Graph for $periodText"

    $annotation = New-Object System.Windows.Forms.DataVisualization.Charting.TextAnnotation
	$annotation.Text = $combinedText
	$annotation.AnchorX = 50           # десната страна
	$annotation.AnchorY = 3            # вертикално центрирано
	# 🔹 Полупрозирна боја (пример: темно magenta со 40% непрозирност)
	$alpha = [int](1 * 255)  # 0.4 = 40% видливост
	$annotation.ForeColor = [System.Drawing.Color]::FromArgb($alpha, 139, 0, 139)
	# 🔹 Нов фонт (пример: "Calibri", 11pt, Bold + Italic)
	$style = [System.Drawing.FontStyle]([System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic)
	$annotation.Font = New-Object System.Drawing.Font("Arial Narrow", 11, $style)
	$annotation.Alignment = [System.Drawing.ContentAlignment]::MiddleCenter
	$annotation.AxisX = $null
	$annotation.AxisY = $null
	$chart.Annotations.Add($annotation)
}

##########  Funkcija za generiranje na Grafikon za LOAD so Statistika  ##############
function Generate-LoadGraph {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Object]$PeriodDays = 1,  # Може да биде 1,7,30,365 или "All"
        [string]$DataFolder = "$PSScriptRoot\Data"
    )

    function Has-ValidData {
        param ([object[]]$data)
        foreach ($item in $data) {
            if ($item -ne $null -and $item -ne "") {
                if ($item -as [double] -or $item -eq 0) { return $true }
            }
        }
        return $false
    }

    # Избор на CSV според период
    $loadCsv = if ($PeriodDays -eq 365 -or $PeriodDays -eq "All") {
        Join-Path $DataFolder "load_all.csv"
    } else {
        Join-Path $DataFolder "load.csv"
    }

    if (-not (Test-Path $loadCsv)) { 
        $msg = "Load CSV file not found at path: $loadCsv"
        Write-Host $msg
        return @{ Status = "Error"; Message = $msg }
    }

    # Читање на CSV
    $rawData = Import-Csv $loadCsv
    if (-not $rawData -or $rawData.Count -eq 0) {
        $msg = "Load CSV file is empty: $loadCsv"
        Write-Host $msg
        return @{ Status = "Error"; Message = $msg }
    }

    # Preprocess-Data
    $loadData = Preprocess-Data -data $rawData -PeriodDays $PeriodDays
    if (-not $loadData -or $loadData.Count -eq 0) {
        Write-Host "No load data found after preprocessing."
        return "No load data found for period $PeriodDays."
    }
	
	# Автоматско наоѓање на GPU колони
	$allColumns = $loadData[0].PSObject.Properties | ForEach-Object { $_.Name }
	$gpuColumns = $allColumns | Where-Object { $_ -like "GPU_*" }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Windows.Forms.DataVisualization

    $fontLegend = New-Object System.Drawing.Font("Segoe UI", 10)
    $fontTitle = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $fontAxis = New-Object System.Drawing.Font("Segoe UI", 9)
    $fontStats = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

	# Статистика
	$cpuProp = if ($PeriodDays -eq 365 -or $PeriodDays -eq "All") { "CPU_Load_Avg" } else { "CPU_Load" }
	$ramProp = if ($PeriodDays -eq 365 -or $PeriodDays -eq "All") { "RAM_Usage_Percent_Avg" } else { "RAM_Usage_Percent" }

	$cpuValues = $loadData | ForEach-Object { $_.$cpuProp } | Where-Object { $_ -as [double] }
	$ramValues = $loadData | ForEach-Object { $_.$ramProp } | Where-Object { $_ -as [double] }

	$cpuStat = if ($cpuValues.Count -ge 2) {
		"CPU Load  - Max: $([math]::Round(($cpuValues | Measure-Object -Maximum).Maximum, 2))%, Min: $([math]::Round(($cpuValues | Measure-Object -Minimum).Minimum, 2))%, Avg: $([math]::Round(($cpuValues | Measure-Object -Average).Average, 2))%"
	} else { "CPU Load  - No Data" }

	$ramStat = if ($ramValues.Count -ge 2) {
		"RAM Usage - Max: $([math]::Round(($ramValues | Measure-Object -Maximum).Maximum, 2))%, Min: $([math]::Round(($ramValues | Measure-Object -Minimum).Minimum, 2))%, Avg: $([math]::Round(($ramValues | Measure-Object -Average).Average, 2))%"
	} else { "RAM Usage - No Data" }

	$stats = @("=== Load Statistics for $PeriodDays days ===", $cpuStat, $ramStat)

	# Додај GPU статистика динамички
	foreach ($col in $gpuColumns) {
	$gpuName = ($col -replace "^GPU_", "") -replace "_", " "
	$values = $loadData | ForEach-Object { $_.$col } | Where-Object { $_ -as [double] }
	if ($values.Count -ge 2) {
		$stats += "GPU $gpuName - Max: $([math]::Round(($values | Measure-Object -Maximum).Maximum,2))%, Min: $([math]::Round(($values | Measure-Object -Minimum).Minimum,2))%, Avg: $([math]::Round(($values | Measure-Object -Average).Average,2))%"
	} else {
		$stats += "GPU $gpuName - No Data"
	}
	}
	$statText = $stats -join "`n"

    # Генерација на график
    $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
    $chart.Width = 900; $chart.Height = 855; $chart.BackColor = [System.Drawing.Color]::WhiteSmoke
	
	$chartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
    $chartArea.AxisX.Title = "Time (Auto)"
	$chartArea.AxisX.TitleFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
	$chartArea.AxisX.TitleForeColor = [System.Drawing.Color]::DarkGreen  # боја на X Axis title
	$chartArea.AxisY.Title = "Load  (Percent)"
	$chartArea.AxisY.TitleFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
	$chartArea.AxisY.TitleForeColor = [System.Drawing.Color]::DarkRed    # боја на Y Axis title
    $chartArea.AxisX.LabelStyle.Font = $fontAxis; $chartArea.AxisY.LabelStyle.Font = $fontAxis
    $chartArea.AxisX.LabelStyle.Format = "MM-dd HH:mm:ss"
    $chartArea.AxisX.MajorGrid.LineColor = [System.Drawing.Color]::LightGray
    $chartArea.AxisY.MajorGrid.LineColor = [System.Drawing.Color]::LightGray
    $chartArea.AxisX.MajorGrid.LineDashStyle = 'Dash'
    $chartArea.AxisY.MajorGrid.LineDashStyle = 'Dash'
    $chartArea.AxisX.LabelStyle.Angle = -45

    switch ($PeriodDays) {
        1 { $chartArea.AxisX.LabelStyle.Format = "HH:mm:ss" }
        7 { $chartArea.AxisX.LabelStyle.Format = "MM-dd HH:mm" }
        30 { $chartArea.AxisX.LabelStyle.Format = "MM-dd HH:mm" }
        365 { $chartArea.AxisX.LabelStyle.Format = "MM-dd" }
        "All" { $chartArea.AxisX.LabelStyle.Format = "yyyy-MM" }
    }
    $chartArea.Position.Auto = $false
    $chartArea.Position = New-Object System.Windows.Forms.DataVisualization.Charting.ElementPosition(5,3,90,80)
    $chartArea.InnerPlotPosition.Auto = $false
    $chartArea.InnerPlotPosition = New-Object System.Windows.Forms.DataVisualization.Charting.ElementPosition(10,10,85,70)
    $chart.ChartAreas.Add($chartArea)

    $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend
    $legend.Font = $fontLegend; $legend.Docking='Top'; $legend.Alignment='Center'
    $chart.Legends.Add($legend)

	function Get-SeriesColor($index) {
		$colors = @(
		[System.Drawing.Color]::FromArgb(255,31,119,180),    # сина
		[System.Drawing.Color]::FromArgb(255,255,127,14),    # портокалова
		[System.Drawing.Color]::FromArgb(255,44,160,44),     # зелена
		[System.Drawing.Color]::FromArgb(255,148,103,189),   # виолетова
		[System.Drawing.Color]::FromArgb(255,218,165,32),    # златна / goldenrod
		[System.Drawing.Color]::FromArgb(255,255,0,255),     # magenta
		[System.Drawing.Color]::FromArgb(255,0,0,139)        # darkblue
	)
		return $colors[$index % $colors.Length]
	}
    $seriesList = @(
    @{ Name = "CPU Load"; Property = $cpuProp; ColorIndex = 0 },
    @{ Name = "RAM Usage"; Property = $ramProp; ColorIndex = 1 })

	# Додај динамично GPU серии
	$gpuIndex = 2
	foreach ($col in $gpuColumns) {
		# Извади чисто име (без "GPU_")
		$gpuName = ($col -replace "^GPU_", "") -replace "_", " "
		$seriesList += @{ Name = "GPU $gpuName"; Property = $col; ColorIndex = $gpuIndex }
		$gpuIndex++
	}
    $global:NoDataMessageSent = $false

    foreach ($seriesInfo in $seriesList) {
        $dataSeries = $loadData | ForEach-Object { $_.$($seriesInfo.Property) }

        if (-not $dataSeries -or $dataSeries.Count -eq 0) {
            Write-Host "No data available for $($seriesInfo.Name). Skipping series."
            continue
        }

        $hasData = Has-ValidData -data $dataSeries
        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
        $series.Name = if ($hasData) { $seriesInfo.Name } else { "$($seriesInfo.Name) (not measured)" }
        $series.ChartType='Line'; $series.Color=Get-SeriesColor $seriesInfo.ColorIndex; $series.BorderWidth=3; $series.XValueType='DateTime'

        $xValues = $loadData | ForEach-Object { $_.Timestamp }
        $yValues = $dataSeries

        if ($xValues.Count -ge 2 -and $xValues.Count -eq $yValues.Count) {
            $series.Points.DataBindXY($xValues, $yValues)
        } else {
            if (-not $global:NoDataMessageSent) {
                Write-Host "Not enough data for the chart, or the number of X and Y values do not match."
                $noDataAnnotation = New-Object System.Windows.Forms.DataVisualization.Charting.TextAnnotation
                $noDataAnnotation.Text="No Data for create Load Graph"
                $noDataAnnotation.ForeColor=[System.Drawing.Color]::Red
                $noDataAnnotation.Font = New-Object System.Drawing.Font("Segoe UI",18,[System.Drawing.FontStyle]::Bold)
                $noDataAnnotation.Alignment=[System.Drawing.ContentAlignment]::MiddleCenter
                $noDataAnnotation.AnchorX=50; $noDataAnnotation.AnchorY=50
                $chart.Annotations.Add($noDataAnnotation)
                $global:NoDataMessageSent = $true
            }
        }
        $chart.Series.Add($series)
    }
	Add-PeriodAnnotation -chart $chart -PeriodDays $PeriodDays -GraphType "Load"   ### TITLE TEXT

    # Додавање на статистика
    $annotation = New-Object System.Windows.Forms.DataVisualization.Charting.TextAnnotation
    $annotation.Text = $statText; $annotation.AnchorX=50; $annotation.AnchorY=95
    $annotation.ForeColor = [System.Drawing.Color]::DarkBlue
    $annotation.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $annotation.Alignment=[System.Drawing.ContentAlignment]::MiddleCenter; $annotation.AxisX=$null; $annotation.AxisY=$null
    $chart.Annotations.Add($annotation)
	
    # --- Chart позадина и подготовка ---
	$chart.BackColor = [Drawing.Color]::WhiteSmoke
	$bmp = New-Object Drawing.Bitmap $chart.Width, $chart.Height
	$g = [Drawing.Graphics]::FromImage($bmp)
	$g.Clear([Drawing.Color]::White)

	# --- Center logo со transparency ---
	$logoPath = Join-Path $PSScriptRoot "media\graph.png"
	if (Test-Path $logoPath) {
		$logo = [Drawing.Image]::FromFile($logoPath)
		$attr = New-Object Drawing.Imaging.ImageAttributes
		($m = New-Object Drawing.Imaging.ColorMatrix).Matrix33 = 0.15
		$attr.SetColorMatrix($m)
		$rect = [Drawing.Rectangle]::new(($bmp.Width-450)/2, ($bmp.Height-450)/2, 450, 450)
		$g.DrawImage($logo, $rect, 0,0,$logo.Width,$logo.Height, 'Pixel', $attr)
		$logo.Dispose(); $attr.Dispose()
	}

	# --- Vertical watermark десно ---
	$wmFont  = [Drawing.Font]::new("Segoe UI",15,[Drawing.FontStyle]::Bold)
	$wmBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(88,0,0,0)) # 88% opacity
	$g.TranslateTransform($bmp.Width - 28, ($bmp.Height + $g.MeasureString("Generated by AutoPilot",$wmFont).Width)/4)
	$g.RotateTransform(-90)
	$g.DrawString("Generated by AutoPilot",$wmFont,$wmBrush,0,0)
	$g.ResetTransform()
	$wmFont.Dispose(); $wmBrush.Dispose()

	# --- Footer текст ---
	$footer = [Windows.Forms.DataVisualization.Charting.TextAnnotation]::new()
	$footer.Text = "*Load Graph   $((Get-Date).ToString('dddd, dd MMMM yyyy - HH:mm:ss'))"
	$footer.ForeColor = [Drawing.Color]::DarkMagenta
	$footer.Font = [Drawing.Font]::new("Segoe UI",13,[Drawing.FontStyle]::Bold)
	$footer.Alignment = [Drawing.ContentAlignment]::BottomCenter
	$footer.AnchorX, $footer.AnchorY = 50, 92
	$chart.Annotations.Add($footer)

	# --- Постави BackImage ---
	$tempPath = [IO.Path]::GetTempFileName()
	$bmp.Save($tempPath, [Drawing.Imaging.ImageFormat]::Png)
	$chartArea = $chart.ChartAreas[0]
	$chartArea.BackImage = $tempPath
	$chartArea.BackImageWrapMode = 'Scaled'
	$chartArea.BackColor = $chartArea.BackSecondaryColor = $chartArea.ShadowColor = [Drawing.Color]::White

	# --- Dispose ---
	$g.Dispose(); $bmp.Dispose()

    $outputFile = Join-Path $DataFolder "load_${PeriodDays}d.png"
    $chart.SaveImage($outputFile, 'Png')
    return @{ LoadGraph=$outputFile; Stats=$stats }
}

#################  Funkcija za Generiranje na grafikon za TEMP so Statistika  ###################
function Generate-TempGraph {
    param(
        [Object]$PeriodDays = 1,  # може да биде int или "All"
        [string]$DataFolder = "$PSScriptRoot\Data"
    )

    function Has-ValidData {
        param ([object[]]$data)
        foreach ($item in $data) {
            if ($item -ne $null -and $item -ne "") {
                if ($item -as [double] -or $item -eq 0) { return $true }
            }
        }
        return $false
    }

    # Избор на CSV според период
    $tempCsv = if ($PeriodDays -eq 365 -or $PeriodDays -eq "All") {
        Join-Path $DataFolder "temperatures_all.csv"
    } else {
        Join-Path $DataFolder "temperatures.csv"
    }

    if (-not (Test-Path $tempCsv)) { 
        $msg = "Temperature CSV file not found at path: $tempCsv"
        Write-Host $msg
        return @{ Status = "Error"; Message = $msg }
    }

    $rawData = Import-Csv $tempCsv
    if (-not $rawData -or $rawData.Count -eq 0) {
        $msg = "Temperature CSV file is empty: $tempCsv"
        Write-Host $msg
        return @{ Status = "Error"; Message = $msg }
    }

    # Филтрирање само ако е број на денови, не за "All"
    if ($PeriodDays -is [int] -and $PeriodDays -ne 365) {
        $startDate = (Get-Date).AddDays(-$PeriodDays)
        $rawData = $rawData | Where-Object { 
            try { [datetime]::Parse($_.Timestamp) -ge $startDate } catch { $false }
        }
    }

    # Preprocess-Data
    $tempData = Preprocess-Data -data $rawData -PeriodDays $PeriodDays
    if (-not $tempData -or $tempData.Count -eq 0) {
        Write-Host "No temperature data found after preprocessing."
        return "No temperature data found for last $PeriodDays days."
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Windows.Forms.DataVisualization

    function Get-SeriesColor($index) {
        $colors = @(
            [System.Drawing.Color]::FromArgb(255,31,119,180),
            [System.Drawing.Color]::FromArgb(255,255,127,14),
            [System.Drawing.Color]::FromArgb(255,44,160,44),
            [System.Drawing.Color]::FromArgb(255,214,39,40),
            [System.Drawing.Color]::FromArgb(255,148,103,189),
			[System.Drawing.Color]::FromArgb(255,255,0,255),     # magenta
		    [System.Drawing.Color]::FromArgb(255,0,0,139)        # darkblue
        )
        return $colors[$index % $colors.Length]
    }

    # Статистика
	$stats = @()
	$tempColumns = $tempData[0].PSObject.Properties.Name | Where-Object { $_ -ne "Timestamp" }

	foreach ($col in $tempColumns) {
		$values = $tempData.$col | Where-Object { $_ -as [double] }
		if ($values.Count -ge 2) {
			$max = ($values | Measure-Object -Maximum).Maximum
			$min = ($values | Measure-Object -Minimum).Minimum
			$avg = [Math]::Round(($values | Measure-Object -Average).Average, 2)
			$stats += "$col - Max: $max, Min: $min, Avg: $avg"
		} else {
			$stats += "$col - No Data"
		}
	}

	$statText = "=== Temperature Statistics for $PeriodDays days ===`n" + ($stats -join "`n")

    # Генерација на график
    $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
    $chart.Width = 900; $chart.Height = 855; $chart.BackColor = [System.Drawing.Color]::WhiteSmoke

    $chartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
    $chartArea.AxisX.Title = "Time (Auto)"
	$chartArea.AxisX.TitleFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
	$chartArea.AxisX.TitleForeColor = [System.Drawing.Color]::DarkGreen  # боја на X Axis title
	$chartArea.AxisY.Title = "Temperature  (Metric)"
	$chartArea.AxisY.TitleFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
	$chartArea.AxisY.TitleForeColor = [System.Drawing.Color]::DarkRed    # боја на Y Axis title
    $chartArea.AxisX.LabelStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $chartArea.AxisY.LabelStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $chartArea.AxisX.MajorGrid.LineColor = [System.Drawing.Color]::LightGray
    $chartArea.AxisY.MajorGrid.LineColor = [System.Drawing.Color]::LightGray
    $chartArea.AxisX.MajorGrid.LineDashStyle = 'Dash'
    $chartArea.AxisY.MajorGrid.LineDashStyle = 'Dash'
    $chartArea.AxisX.LabelStyle.Angle = -45

    switch ($PeriodDays) {
        1   { $chartArea.AxisX.LabelStyle.Format = "HH:mm:ss" }
        7   { $chartArea.AxisX.LabelStyle.Format = "MM-dd HH:mm" }
        30  { $chartArea.AxisX.LabelStyle.Format = "MM-dd HH:mm" }
        365 { $chartArea.AxisX.LabelStyle.Format = "MM-dd" }
        "All" { $chartArea.AxisX.LabelStyle.Format = "yyyy-MM" } # за месечни просеци
    }

    $chartArea.Position.Auto = $false
    $chartArea.Position = New-Object System.Windows.Forms.DataVisualization.Charting.ElementPosition(5, 3, 90, 80)
    $chartArea.InnerPlotPosition.Auto = $false
    $chartArea.InnerPlotPosition = New-Object System.Windows.Forms.DataVisualization.Charting.ElementPosition(10, 10, 85, 70)
    $chart.ChartAreas.Add($chartArea)

    $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend
    $legend.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $legend.Docking = 'Top'; $legend.Alignment = 'Center'
    $chart.Legends.Add($legend)

    $global:NoDataMessageSent = $false
    $index = 0
    foreach ($col in $tempColumns) {
        $dataSeries = $tempData.$col
        if (-not $dataSeries -or $dataSeries.Count -eq 0) { $index++; continue }

        $hasData = Has-ValidData -data $dataSeries
        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
        $series.Name = if ($hasData) { $col } else { "$col (not measured)" }
        $series.ChartType = 'Line'
        $series.Color = Get-SeriesColor $index
        $series.BorderWidth = 3
        $series.XValueType = 'DateTime'

        $xValues = $tempData | ForEach-Object { $_.Timestamp }
        $yValues = $dataSeries

        if ($xValues.Count -ge 2 -and $xValues.Count -eq $yValues.Count) {
            $series.Points.DataBindXY($xValues, $yValues)
        } else {
            if (-not $global:NoDataMessageSent) {
                Write-Host "Not enough data for the chart, or the number of X and Y values do not match."
                $noDataAnnotation = New-Object System.Windows.Forms.DataVisualization.Charting.TextAnnotation
                $noDataAnnotation.Text="No Data for create Temperature Graph"
                $noDataAnnotation.ForeColor = [System.Drawing.Color]::Red
                $noDataAnnotation.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
                $noDataAnnotation.Alignment = [System.Drawing.ContentAlignment]::MiddleCenter
                $noDataAnnotation.AnchorX = 50; $noDataAnnotation.AnchorY = 50
                $chart.Annotations.Add($noDataAnnotation)
                $global:NoDataMessageSent = $true
            }
        }
        $chart.Series.Add($series)
        $index++
    }
	Add-PeriodAnnotation -chart $chart -PeriodDays $PeriodDays -GraphType "Temp"   ### TITLE TEXT

    # Додавање на статистика
    $annotation = New-Object System.Windows.Forms.DataVisualization.Charting.TextAnnotation
    $annotation.Text = $statText
    $annotation.AnchorX = 50; $annotation.AnchorY = 95
    $annotation.ForeColor = [System.Drawing.Color]::DarkBlue
    $annotation.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $annotation.Alignment = [System.Drawing.ContentAlignment]::MiddleCenter
    $annotation.AxisX = $null; $annotation.AxisY = $null
    $chart.Annotations.Add($annotation)
	
	# --- Chart позадина и подготовка ---
	$chart.BackColor = [Drawing.Color]::WhiteSmoke
	$bmp = New-Object Drawing.Bitmap $chart.Width, $chart.Height
	$g = [Drawing.Graphics]::FromImage($bmp)
	$g.Clear([Drawing.Color]::White)

	# --- Center logo со transparency ---
	$logoPath = Join-Path $PSScriptRoot "media\graph.png"
	if (Test-Path $logoPath) {
		$logo = [Drawing.Image]::FromFile($logoPath)
		$attr = New-Object Drawing.Imaging.ImageAttributes
		($m = New-Object Drawing.Imaging.ColorMatrix).Matrix33 = 0.15
		$attr.SetColorMatrix($m)
		$rect = [Drawing.Rectangle]::new(($bmp.Width-450)/2, ($bmp.Height-450)/2, 450, 450)
		$g.DrawImage($logo, $rect, 0,0,$logo.Width,$logo.Height, 'Pixel', $attr)
		$logo.Dispose(); $attr.Dispose()
	}

	# --- Vertical watermark десно ---
	$wmFont  = [Drawing.Font]::new("Segoe UI",15,[Drawing.FontStyle]::Bold)
	$wmBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(88,0,0,0)) # 88% opacity
	$g.TranslateTransform($bmp.Width - 28, ($bmp.Height + $g.MeasureString("Generated by AutoPilot",$wmFont).Width)/4)
	$g.RotateTransform(-90)
	$g.DrawString("Generated by AutoPilot",$wmFont,$wmBrush,0,0)
	$g.ResetTransform()
	$wmFont.Dispose(); $wmBrush.Dispose()

	# --- Footer текст ---
	$footer = [Windows.Forms.DataVisualization.Charting.TextAnnotation]::new()
	$footer.Text = "*Temp Graph   $((Get-Date).ToString('dddd, dd MMMM yyyy - HH:mm:ss'))"
	$footer.ForeColor = [Drawing.Color]::DarkMagenta
	$footer.Font = [Drawing.Font]::new("Segoe UI",13,[Drawing.FontStyle]::Bold)
	$footer.Alignment = [Drawing.ContentAlignment]::BottomCenter
	$footer.AnchorX, $footer.AnchorY = 50, 92
	$chart.Annotations.Add($footer)

	# --- Постави BackImage ---
	$tempPath = [IO.Path]::GetTempFileName()
	$bmp.Save($tempPath, [Drawing.Imaging.ImageFormat]::Png)
	$chartArea = $chart.ChartAreas[0]
	$chartArea.BackImage = $tempPath
	$chartArea.BackImageWrapMode = 'Scaled'
	$chartArea.BackColor = $chartArea.BackSecondaryColor = $chartArea.ShadowColor = [Drawing.Color]::White

	# --- Dispose ---
	$g.Dispose(); $bmp.Dispose()

    $outputFile = Join-Path $DataFolder "temperature_${PeriodDays}d.png"
    $chart.SaveImage($outputFile, 'Png')

    return @{
        TempGraph = $outputFile
        Stats = $stats
    }
}

#################  Funkcija za Generiranje na grafikon za DISK so Statistika  ###################
function Generate-DiskGraph {
    param(
        [Object]$PeriodDays = 1,  # може да биде int или "All"
        [string]$DataFolder = "$PSScriptRoot\Data"
    )

    function Has-ValidData {
        param ([object[]]$data)
        foreach ($item in $data) {
            if ($item -ne $null -and $item -ne "") {
                if ($item -as [double] -or $item -eq 0) { return $true }
            }
        }
        return $false
    }

    # Избор на CSV според период
    $diskCsv = if ($PeriodDays -eq 365 -or $PeriodDays -eq "All") { 
        Join-Path $DataFolder "disk_all.csv" 
    } else { 
        Join-Path $DataFolder "disk.csv" 
    }

    if (-not (Test-Path $diskCsv)) {
        $msg = "CSV file not found at path: $diskCsv"
        Write-Host $msg
        return @{ Status="Error"; Message=$msg }
    }

    $rawData = Import-Csv $diskCsv
    if (-not $rawData -or $rawData.Count -eq 0) {
        $msg = "CSV file is empty: $diskCsv"
        Write-Host $msg
        return @{ Status="Error"; Message=$msg }
    }

    # Филтрирање само ако е број на денови и не е 365
    if ($PeriodDays -is [int] -and $PeriodDays -ne 365) {
        $startDate = (Get-Date).AddDays(-$PeriodDays)
        $rawData = $rawData | Where-Object { try { [datetime]::Parse($_.Timestamp) -ge $startDate } catch { $false } }
    }

    # Preprocess-Data за сите случаи (вклучувајќи "All")
    $diskData = Preprocess-Data -data $rawData -PeriodDays $PeriodDays
    if (-not $diskData -or $diskData.Count -eq 0) {
        Write-Host "No disk data found after preprocessing."
        return "No disk data found for last $PeriodDays days."
    }

    # Автоматско наоѓање на колони за дискови
    $allColumns = $diskData[0].PSObject.Properties | ForEach-Object { $_.Name }
    $diskColumns = $allColumns | Where-Object { $_ -ne "Timestamp" }
    if ($diskColumns.Count -eq 0) {
        Write-Host "No disk columns found in CSV."
        return "No disk columns found in CSV."
    }

    # Chart setup
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Windows.Forms.DataVisualization

    $fontLegend = New-Object System.Drawing.Font("Segoe UI", 10)
    $fontTitle = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $fontAxis = New-Object System.Drawing.Font("Segoe UI", 9)

    $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
    $chart.Width = 900; $chart.Height = 855; $chart.BackColor = [System.Drawing.Color]::WhiteSmoke

    $chartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
    $chartArea.AxisX.Title = "Time (Auto)"
	$chartArea.AxisX.TitleFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
	$chartArea.AxisX.TitleForeColor = [System.Drawing.Color]::DarkGreen  # боја на X Axis title
	$chartArea.AxisY.Title = "Load Disk  (Percent)"
	$chartArea.AxisY.TitleFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
	$chartArea.AxisY.TitleForeColor = [System.Drawing.Color]::DarkRed    # боја на Y Axis title
    $chartArea.AxisX.LabelStyle.Font = $fontAxis; $chartArea.AxisY.LabelStyle.Font = $fontAxis
    $chartArea.AxisX.MajorGrid.LineColor = [System.Drawing.Color]::LightGray
    $chartArea.AxisY.MajorGrid.LineColor = [System.Drawing.Color]::LightGray
    $chartArea.AxisX.MajorGrid.LineDashStyle = 'Dash'; $chartArea.AxisY.MajorGrid.LineDashStyle = 'Dash'
    $chartArea.AxisX.LabelStyle.Angle = -45

    switch ($PeriodDays) {
        1   { $chartArea.AxisX.LabelStyle.Format = "HH:mm:ss" }
        7   { $chartArea.AxisX.LabelStyle.Format = "MM-dd HH:mm" }
        30  { $chartArea.AxisX.LabelStyle.Format = "MM-dd HH:mm" }
        365 { $chartArea.AxisX.LabelStyle.Format = "MM-dd" }
        "All" { $chartArea.AxisX.LabelStyle.Format = "yyyy-MM" }
    }

    $chartArea.Position.Auto = $false
    $chartArea.Position = New-Object System.Windows.Forms.DataVisualization.Charting.ElementPosition(5,3,90,80)
    $chartArea.InnerPlotPosition.Auto = $false
    $chartArea.InnerPlotPosition = New-Object System.Windows.Forms.DataVisualization.Charting.ElementPosition(10,10,85,70)
    $chart.ChartAreas.Add($chartArea)

    $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend
    $legend.Font = $fontLegend; $legend.Docking='Top'; $legend.Alignment='Center'
    $chart.Legends.Add($legend)

    $global:NoDataMessageSent = $false

    function Get-SeriesColor($index) {
        $colors = @(
            [System.Drawing.Color]::FromArgb(255,31,119,180),
            [System.Drawing.Color]::FromArgb(255,255,127,14),
            [System.Drawing.Color]::FromArgb(255,44,160,44),
            [System.Drawing.Color]::FromArgb(255,214,39,40),
            [System.Drawing.Color]::FromArgb(255,148,103,189),
			[System.Drawing.Color]::FromArgb(255,255,0,255),     # magenta
		    [System.Drawing.Color]::FromArgb(255,0,0,139)        # darkblue
        )
        return $colors[$index % $colors.Length]
    }

    $i = 0
    foreach ($col in $diskColumns) {
        $dataSeries = $diskData | ForEach-Object { $_.$col }
        $hasData = Has-ValidData -data $dataSeries
        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
        $series.Name = if ($hasData) { $col } else { "$col (not measured)" }
        $series.ChartType = 'Line'; $series.Color = Get-SeriesColor $i; $series.BorderWidth = 3; $series.XValueType='DateTime'

        $xValues = $diskData | ForEach-Object { $_.Timestamp }
        $yValues = $dataSeries

        if ($xValues.Count -ge 2 -and $xValues.Count -eq $yValues.Count) {
            $series.Points.DataBindXY($xValues, $yValues)
        } else {
            if (-not $global:NoDataMessageSent) {
                Write-Host "Not enough data for the chart, or the number of X and Y values do not match."
                $noDataAnnotation = New-Object System.Windows.Forms.DataVisualization.Charting.TextAnnotation
                $noDataAnnotation.Text="No Data for create Disk Graph"
                $noDataAnnotation.ForeColor=[System.Drawing.Color]::Red
                $noDataAnnotation.Font = New-Object System.Drawing.Font("Segoe UI",18,[System.Drawing.FontStyle]::Bold)
                $noDataAnnotation.Alignment=[System.Drawing.ContentAlignment]::MiddleCenter
                $noDataAnnotation.AnchorX=50; $noDataAnnotation.AnchorY=50
                $chart.Annotations.Add($noDataAnnotation)
                $global:NoDataMessageSent = $true
            }
        }
        $chart.Series.Add($series)
        $i++
    }
	Add-PeriodAnnotation -chart $chart -PeriodDays $PeriodDays -GraphType "Disk"   ### TITLE TEXT

	# Статистика
	$stats = @()
	foreach ($col in $diskColumns) {
		$values = $diskData | ForEach-Object { $_.$col } | Where-Object { $_ -as [double] }
		if ($values.Count -ge 2) {
			$stats += "$col - Max: $([math]::Round(($values | Measure-Object -Maximum).Maximum,2))%, Min: $([math]::Round(($values | Measure-Object -Minimum).Minimum,2))%, Avg: $([math]::Round(($values | Measure-Object -Average).Average,2))%"
		} else {
			$stats += "$col - No Data"
		}
	}
	$statText = "=== Disk Load Statistics for $PeriodDays days ===`n" + ($stats -join "`n")
    $annotation = New-Object System.Windows.Forms.DataVisualization.Charting.TextAnnotation
    $annotation.Text = $statText; $annotation.AnchorX=50; $annotation.AnchorY=95
    $annotation.ForeColor = [System.Drawing.Color]::DarkBlue
    $annotation.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $annotation.Alignment=[System.Drawing.ContentAlignment]::MiddleCenter; $annotation.AxisX=$null; $annotation.AxisY=$null
    $chart.Annotations.Add($annotation)
	
    # --- Chart позадина и подготовка ---
	$chart.BackColor = [Drawing.Color]::WhiteSmoke
	$bmp = New-Object Drawing.Bitmap $chart.Width, $chart.Height
	$g = [Drawing.Graphics]::FromImage($bmp)
	$g.Clear([Drawing.Color]::White)

	# --- Center logo со transparency ---
	$logoPath = Join-Path $PSScriptRoot "media\graph.png"
	if (Test-Path $logoPath) {
		$logo = [Drawing.Image]::FromFile($logoPath)
		$attr = New-Object Drawing.Imaging.ImageAttributes
		($m = New-Object Drawing.Imaging.ColorMatrix).Matrix33 = 0.15
		$attr.SetColorMatrix($m)
		$rect = [Drawing.Rectangle]::new(($bmp.Width-450)/2, ($bmp.Height-450)/2, 450, 450)
		$g.DrawImage($logo, $rect, 0,0,$logo.Width,$logo.Height, 'Pixel', $attr)
		$logo.Dispose(); $attr.Dispose()
	}

	# --- Vertical watermark десно ---
	$wmFont  = [Drawing.Font]::new("Segoe UI",15,[Drawing.FontStyle]::Bold)
	$wmBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(88,0,0,0)) # 88% opacity
	$g.TranslateTransform($bmp.Width - 28, ($bmp.Height + $g.MeasureString("Generated by AutoPilot",$wmFont).Width)/4)
	$g.RotateTransform(-90)
	$g.DrawString("Generated by AutoPilot",$wmFont,$wmBrush,0,0)
	$g.ResetTransform()
	$wmFont.Dispose(); $wmBrush.Dispose()

	# --- Footer текст ---
	$footer = [Windows.Forms.DataVisualization.Charting.TextAnnotation]::new()
	$footer.Text = "*Disk Load Graph   $((Get-Date).ToString('dddd, dd MMMM yyyy - HH:mm:ss'))"
	$footer.ForeColor = [Drawing.Color]::DarkMagenta
	$footer.Font = [Drawing.Font]::new("Segoe UI",13,[Drawing.FontStyle]::Bold)
	$footer.Alignment = [Drawing.ContentAlignment]::BottomCenter
	$footer.AnchorX, $footer.AnchorY = 50, 92
	$chart.Annotations.Add($footer)

	# --- Постави BackImage ---
	$tempPath = [IO.Path]::GetTempFileName()
	$bmp.Save($tempPath, [Drawing.Imaging.ImageFormat]::Png)
	$chartArea = $chart.ChartAreas[0]
	$chartArea.BackImage = $tempPath
	$chartArea.BackImageWrapMode = 'Scaled'
	$chartArea.BackColor = $chartArea.BackSecondaryColor = $chartArea.ShadowColor = [Drawing.Color]::White

	# --- Dispose ---
	$g.Dispose(); $bmp.Dispose()

    $outputFile = Join-Path $DataFolder "disk_${PeriodDays}d.png"
    $chart.SaveImage($outputFile, 'Png')
    return @{ DiskGraph=$outputFile; Stats=$stats }
}

###################################################################### Graphs Script End.