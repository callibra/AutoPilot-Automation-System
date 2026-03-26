##### NetTrafficTable #####
function Generate-TableGraph-Day   { return Generate-TableGraph -PeriodDays 1 }
function Generate-TableGraph-Week  { return Generate-TableGraph -PeriodDays 7 }
function Generate-TableGraph-Month { return Generate-TableGraph -PeriodDays 30 }
function Generate-TableGraph-Year  { return Generate-TableGraph -PeriodDays 365 }
function Generate-TableGraph-All   { return Generate-TableGraph -PeriodDays "All" }

##### Function Generate-TableGraph #####
function Generate-TableGraph {
    param(
        [Parameter(Mandatory=$false)]
        [Alias("Days")]
        [ValidateSet(1,7,30,365,"All")]
        $PeriodDays = 1,

        [string]$DataFolder = "$PSScriptRoot\Data"
    )

    # --- CSV ---
	$csvPath = Join-Path $DataFolder "traffic.csv"
	if (-not (Test-Path $csvPath)) {
		$msg = "CSV file not found: $csvPath"
		Write-Host $msg
		return @{ Status = "Error"; Message = $msg }   # Нема PNG, само порака
	}

	$rawData = Import-Csv $csvPath
	if (-not $rawData -or $rawData.Count -eq 0) {
		Write-Host "CSV file empty: $csvPath"
		# --- Генерирање на PNG со "No Data" ---
		Add-Type -AssemblyName System.Drawing
		$width = 780
		$bmpHeight = 400
		$bmp = New-Object System.Drawing.Bitmap $width, $bmpHeight
		$g = [System.Drawing.Graphics]::FromImage($bmp)
		$g.SmoothingMode = "AntiAlias"
		$g.Clear([System.Drawing.Color]::White)

		$font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
		$redBrush = [System.Drawing.Brushes]::Red
		$size = $g.MeasureString("No Data for create Table", $font)
		$g.DrawString("No Data for create Table", $font, $redBrush, ($width - $size.Width)/2, ($bmpHeight - $size.Height)/2)

		$outputFile = Join-Path $DataFolder "table_${PeriodDays}d.png"
		$bmp.Save($outputFile, [System.Drawing.Imaging.ImageFormat]::Png)
		$g.Dispose(); $bmp.Dispose()

		Write-Host " Table PNG generated with 'No Data': $outputFile"
		return @{ Status="OK"; Output=$outputFile; Data=@() }
	}

    # --- Подготовка на податоците ---
    $data = $rawData | ForEach-Object {
        $split = $_.'Download_Bytes/Upload_Bytes/Total_Bytes'.Split('/')
        [PSCustomObject]@{
            Date = [datetime]::ParseExact($_.Date,'yyyy/MM/dd',$null)
            Download = [int64]$split[0]
            Upload   = [int64]$split[1]
            Total    = [int64]$split[2]
            Interface = $_.Interface
        }
    }

    # --- Филтрирање според тековен период ---
    if ($PeriodDays -ne "All") {
	$today = Get-Date

	switch ($PeriodDays) {
		1 {
			# Само за денес
			$startDate = $today.Date
			$endDate   = $today
		}
		7 {
			# За тековната недела (понеделник до денес)
			$dayOfWeek = [int]$today.DayOfWeek
			if ($dayOfWeek -eq 0) { $dayOfWeek = 7 } # недела = 7
			$startDate = $today.AddDays(-($dayOfWeek - 1)).Date
			$endDate   = $today
		}
		30 {
			# За тековниот месец (од 1ви до денес)
			$startDate = (Get-Date -Day 1).Date
			$endDate   = $today
		}
		365 {
			# За тековната година (од 1ви јануари до денес)
			$startDate = (Get-Date -Month 1 -Day 1).Date
			$endDate   = $today
		}
		"All" {
			# Од најраниот до најновиот достапен датум
			$parsedData = $rawData | ForEach-Object {
				$split = $_.'Download_Bytes/Upload_Bytes/Total_Bytes'.Split('/')
				[PSCustomObject]@{
					Date = [datetime]::ParseExact($_.Date,'yyyy/MM/dd',$null)
					Download = [int64]$split[0]
					Upload   = [int64]$split[1]
					Total    = [int64]$split[2]
					Interface = $_.Interface
				}
			}
			$startDate = ($parsedData | Sort-Object Date | Select-Object -First 1).Date
			$endDate   = ($parsedData | Sort-Object Date -Descending | Select-Object -First 1).Date
			$data = $parsedData
			return
		}
		default {
			$startDate = $today.AddDays(-$PeriodDays)
			$endDate   = $today
		}
	}

	# --- Прво конвертирај ги сите датуми во datetime пред филтрирање ---
	$data = $rawData | ForEach-Object {
		$split = $_.'Download_Bytes/Upload_Bytes/Total_Bytes'.Split('/')
		[PSCustomObject]@{
			Date = [datetime]::ParseExact($_.Date,'yyyy/MM/dd',$null)
			Download = [int64]$split[0]
			Upload   = [int64]$split[1]
			Total    = [int64]$split[2]
			Interface = $_.Interface
		}
	} | Where-Object {
		$_.Date -ge $startDate -and $_.Date -le $endDate
	}
	}

	# --- Ако нема податоци за тековниот период ---
	if (-not $data -or $data.Count -eq 0) {
		Write-Host "No data found for current period ($PeriodDays)."
		
		# Наместо return — ќе направиме еден празен запис
		$data = @(
			[PSCustomObject]@{
				Interface = "No interface data"
				Download  = 0
				Upload    = 0
				Total     = 0
			}
		)
	}
	
    # --- Агрегација по Interface ---
    $aggregated = $data | Group-Object Interface | ForEach-Object {
        [PSCustomObject]@{
            Interface = $_.Name
            Download  = ($_.Group | Measure-Object -Property Download -Sum).Sum
            Upload    = ($_.Group | Measure-Object -Property Upload -Sum).Sum
            Total     = ($_.Group | Measure-Object -Property Total -Sum).Sum
        }
    }

    # --- Функција за конверзија ---
    function Convert-Bytes($b) {
		# Дефинирање на големини во bytes
		$KB = 1024
		$MB = $KB * 1024
		$GB = $MB * 1024
		$TB = $GB * 1024
		$PB = $TB * 1024
		$EB = $PB * 1024

		switch ($b) {
			{$_ -ge $EB} { return "{0:N2} EB" -f ($b / $EB) }
			{$_ -ge $PB} { return "{0:N2} PB" -f ($b / $PB) }
			{$_ -ge $TB} { return "{0:N2} TB" -f ($b / $TB) }
			{$_ -ge $GB} { return "{0:N2} GB" -f ($b / $GB) }
			{$_ -ge $MB} { return "{0:N2} MB" -f ($b / $MB) }
			{$_ -ge $KB} { return "{0:N2} KB" -f ($b / $KB) }
			default { return "$b B" }
		}
	}

    # --- Иницијализација на слика ---
    Add-Type -AssemblyName System.Drawing
    $width = 780
    $rowHeight = 45
    $headerHeight = 40
    $titleFont  = New-Object System.Drawing.Font ("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $headerFont = New-Object System.Drawing.Font ("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $cellFont   = New-Object System.Drawing.Font ("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200,200,200))
    $blackBrush = [System.Drawing.Brushes]::Black
    $whiteBrush = [System.Drawing.Brushes]::White
    $headerBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70,120,210))

    # --- Динамични бои за интерфејсите ---
    $rand = [System.Random]::new()
    $interfaceColors = @{}
    foreach ($iface in ($aggregated.Interface | Sort-Object -Unique)) {
        $interfaceColors[$iface] = [System.Drawing.Color]::FromArgb(
            255,
            $rand.Next(100,180),
            $rand.Next(130,200),
            $rand.Next(210,255)
        )
    }

    $maxTotal = ($aggregated.Total | Measure-Object -Maximum).Maximum
    function Get-Shade($color, $intensity) {
        $factor = [Math]::Min(1, [Math]::Max(0.3, $intensity))
        return [System.Drawing.Color]::FromArgb(
            255,
            [int]($color.R * $factor),
            [int]($color.G * $factor),
            [int]($color.B * $factor)
        )
    }

    # --- Динамична табела за периодот ---
    switch ($PeriodDays) {
        1 {
            $periodData = @([PSCustomObject]@{
                Period = (Get-Date -Format "dddd")
                Download = ($data | Measure-Object Download -Sum).Sum
                Upload = ($data | Measure-Object Upload -Sum).Sum
                Total = ($data | Measure-Object Total -Sum).Sum
            })
        }
        7 {
			$dayOfWeek = [int]$today.DayOfWeek
			$dayOfWeek = if ($dayOfWeek -eq 0) { 7 } else { $dayOfWeek } 
			$startWeek = $today.AddDays(1 - $dayOfWeek).Date 
			$endWeek = if ($dayOfWeek -eq 7) { $startWeek.AddDays(6) } else { $today.Date }
			$periodData = @()
			for ($d = $startWeek; $d -le $endWeek; $d = $d.AddDays(1)) {
				$dayData = $data | Where-Object { $_.Date.Date -eq $d.Date }
				$periodData += [PSCustomObject]@{
					Period = $d.ToString("dddd, dd MMM")
					Download = ($dayData | Measure-Object Download -Sum).Sum
					Upload   = ($dayData | Measure-Object Upload -Sum).Sum
					Total    = ($dayData | Measure-Object Total -Sum).Sum
				}
			}
		}
        30 {
            $startMonth = (Get-Date -Day 1)
            $daysInMonth = [DateTime]::DaysInMonth((Get-Date).Year,(Get-Date).Month)
            $periodData = @()
            for ($d=1; $d -le $daysInMonth; $d++) {
                $dayDate = (Get-Date -Day $d)
                if ($dayDate -gt (Get-Date)) { break }
                $dayData = $data | Where-Object { $_.Date.Day -eq $d }
                $periodData += [PSCustomObject]@{
                    Period = $dayDate.ToString("dd MMMM")
                    Download = ($dayData | Measure-Object Download -Sum).Sum
                    Upload = ($dayData | Measure-Object Upload -Sum).Sum
                    Total = ($dayData | Measure-Object Total -Sum).Sum
                }
            }
        }
        365 {
            $periodData = @()
            for ($m=1; $m -le (Get-Date).Month; $m++) {
                $monthData = $data | Where-Object { $_.Date.Month -eq $m }
                $monthName = (Get-Date -Month $m -Day 1).ToString("MMMM")
                $periodData += [PSCustomObject]@{
                    Period = $monthName
                    Download = ($monthData | Measure-Object Download -Sum).Sum
                    Upload = ($monthData | Measure-Object Upload -Sum).Sum
                    Total = ($monthData | Measure-Object Total -Sum).Sum
                }
            }
        }
        "All" {
            # --- За All: сите години ---
            $years = $data | ForEach-Object { $_.Date.Year } | Sort-Object -Unique
            $periodData = @()
            foreach ($y in $years) {
                $yearData = $data | Where-Object { $_.Date.Year -eq $y }
                $periodData += [PSCustomObject]@{
                    Period   = "$y"
                    Download = ($yearData | Measure-Object Download -Sum).Sum
                    Upload   = ($yearData | Measure-Object Upload -Sum).Sum
                    Total    = ($yearData | Measure-Object Total -Sum).Sum
                }
            }
        }
    }

    # --- Summary податоци (последна таблица) ---
	$summaryData = @()

	# Додавање summary за сите периоди
	if ($PeriodDays -eq "All") {
		$firstDate = ($data | Sort-Object Date | Select-Object -First 1).Date
        $lastDate = ($data | Sort-Object Date -Descending | Select-Object -First 1).Date

		$summaryData += [PSCustomObject]@{
			Period   = "$($firstDate.ToString('MMM yyyy')) - $($lastDate.ToString('MMM yyyy'))" 
			Download = ($data | Measure-Object Download -Sum).Sum
			Upload   = ($data | Measure-Object Upload -Sum).Sum
			Total    = ($data | Measure-Object Total -Sum).Sum
		}
	}
	elseif ($PeriodDays -eq 1) {
		$today = Get-Date
		$summaryData += [PSCustomObject]@{
			Period   = "Today ($($today.ToString('dd MMM yyyy')))"
			Download = ($data | Measure-Object Download -Sum).Sum
			Upload   = ($data | Measure-Object Upload -Sum).Sum
			Total    = ($data | Measure-Object Total -Sum).Sum
		}
	}
	else {
		$today = Get-Date
		switch ($PeriodDays) {
			7 {
				$dayOfWeek = [int]$today.DayOfWeek
				if ($dayOfWeek -eq 0) { $dayOfWeek = 7 }
				$startWeek = $today.AddDays(-($dayOfWeek - 1)).Date
				$dateRange = "$($startWeek.ToString('dd MMM')) - $($today.ToString('dd MMM yyyy'))"
				$summaryData += [PSCustomObject]@{
					Period   = "$dateRange"
					Download = ($data | Measure-Object -Property Download -Sum).Sum
					Upload   = ($data | Measure-Object -Property Upload -Sum).Sum
					Total    = ($data | Measure-Object -Property Total -Sum).Sum
				}
			}
			30 {
				$startMonth = (Get-Date -Day 1).Date
				$dateRange = "$($startMonth.ToString('dd MMM')) - $($today.ToString('dd MMM yyyy'))"
				$summaryData += [PSCustomObject]@{
					Period   = "$dateRange"
					Download = ($data | Measure-Object -Property Download -Sum).Sum
					Upload   = ($data | Measure-Object -Property Upload -Sum).Sum
					Total    = ($data | Measure-Object -Property Total -Sum).Sum
				}
			}
			365 {
				$startYear = (Get-Date -Month 1 -Day 1).Date
				$dateRange = "$($startYear.ToString('dd MMM')) - $($today.ToString('dd MMM yyyy'))"
				$summaryData += [PSCustomObject]@{
					Period   = "$dateRange"
					Download = ($data | Measure-Object -Property Download -Sum).Sum
					Upload   = ($data | Measure-Object -Property Upload -Sum).Sum
					Total    = ($data | Measure-Object -Property Total -Sum).Sum
				}
			}
		}
	}

    # --- Пресметка на висина на bitmap за сите таблици ---
    $periodRowHeight = 40
    $periodHeaderHeight = 40
    $mainRowHeight = $rowHeight
    $mainHeaderHeight = $headerHeight
    $summaryHeaderHeight = 40
    $summaryRowHeight = 40
    $padding = 88

    $periodTableHeight = $periodHeaderHeight + ($periodData.Count * $periodRowHeight)
    $mainTableHeight = $mainHeaderHeight + ($aggregated.Count * $mainRowHeight)
    $summaryTableHeight = if ($summaryData.Count -gt 0) { $summaryHeaderHeight + ($summaryData.Count * $summaryRowHeight) + 20 } else { 0 }

    $bmpHeight = 60 + $periodTableHeight + 20 + $mainTableHeight + $summaryTableHeight + $padding

    $bmp = New-Object System.Drawing.Bitmap $width, $bmpHeight
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"
    
	# --- Gradient background --- 
	$topColor = [System.Drawing.Color]::WhiteSmoke  #::FromArgb(245, 247, 250)    # светло сива/плава
	$bottomColor = [System.Drawing.Color]::WhiteSmoke  #::FromArgb(180, 200, 245) # потемна нијанса

	$rectangle = New-Object System.Drawing.Rectangle(0, 0, $width, $bmpHeight)
	$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
		$rectangle,
		$topColor,
		$bottomColor,
		[System.Drawing.Drawing2D.LinearGradientMode]::Vertical
	)

	# Пополнување на целата слика со gradient
	$g.FillRectangle($brush, $rectangle)
	$brush.Dispose()

    # --- Патека до сликата (логото) ---
	$logoPath = "$PSScriptRoot\media\table.png"

	# --- Поставување големина на логото ---
	$logoWidth = 45  # ширина во пиксели
	$logoHeight = 45  # висина во пиксели

	# --- Вчитување на логото ако постои ---
	if (Test-Path $logoPath) {
		$logo = [System.Drawing.Image]::FromFile($logoPath)
		$g.DrawImage($logo, 60, 5, $logoWidth, $logoHeight)  # цртање на logo на позиција X=60, Y=5
		$logo.Dispose()
	}

	# --- Заглавие --- 
	$titleMain = "Internet Traffic Data - "
	$titleColor = [System.Drawing.Color]::Blue  # бојата на заглавието
	$titleFontCustom = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
	$titleBrush = New-Object System.Drawing.SolidBrush($titleColor)

	# Измести текстот на X = 50 + $logoWidth + мала маргина
	$textX = 50+ $logoWidth + 10
	$g.DrawString($titleMain, $titleFontCustom, $titleBrush, $textX, 10)
    $titleBrush.Dispose()
    $titleFontCustom.Dispose()

	# --- Динамичен текст во продолжение со црвено ---
	$dynamicText = switch ($PeriodDays) {
		1 {
			# Ден → конкретен датум
			(Get-Date).ToString("dddd, dd MMMM yyyy")
		}
		7 {
			# Недела → број на недела
			$weekNum = [System.Globalization.CultureInfo]::CurrentCulture.Calendar.GetWeekOfYear(
				(Get-Date),
				[System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
				[System.DayOfWeek]::Monday
			)
			"Week $weekNum"
		}
		30 {
			# Месец → име на месец
			(Get-Date).ToString("MMMM")
		}
		365 {
			# Година → само годината
			"Year $((Get-Date).ToString('yyyy'))"
		}
		"All" {
			# All → од која до која година
			$firstDate = ($data | Sort-Object Date | Select-Object -First 1).Date
			$lastDate = ($data | Sort-Object Date -Descending | Select-Object -First 1).Date
			"All Data ($($firstDate.ToString('yyyy')) - $($lastDate.ToString('yyyy')))"
		}
		default {
			(Get-Date).ToString("dddd, dd MMMM yyyy")
		}
	}

	# Измери ширина на главното заглавие за да го продолжиш текстот
	$sizeTitle = $g.MeasureString($titleMain, $titleFont)

	# --- Црвен bold текст после насловот ---
	$boldRedFont = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
	$redBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Red)
	$g.DrawString(" $dynamicText", $boldRedFont, $redBrush, 90 + $sizeTitle.Width, 10)
	$redBrush.Dispose()
	$boldRedFont.Dispose()

	# --- Динамична табела (period) ---
	$periodTableX = 50
	$periodTableY = 60
	$colWidthsPeriod = @(200,160,160,160)
	$headerPeriod = @("","Download","Upload","Total")

	# Header
	$g.FillRectangle($headerBrush, $periodTableX, $periodTableY, ($colWidthsPeriod | Measure-Object -Sum).Sum, $periodHeaderHeight)
	$x = $periodTableX
	for ($i=0; $i -lt $headerPeriod.Count; $i++) {
		$g.DrawString($headerPeriod[$i], $headerFont, $whiteBrush, $x+10, $periodTableY+5)
		$x += $colWidthsPeriod[$i]
	}

	# --- Динамичен жолт текст за Period колона ---
	switch ($PeriodDays) {
		1   { $dynamicPeriod = "*Period - Day" }
		7   { 
			$week = [CultureInfo]::InvariantCulture.Calendar.GetWeekOfYear(
				(Get-Date),
				[System.Globalization.CalendarWeekRule]::FirstFourDayWeek,
				[DayOfWeek]::Monday
			)
			$dynamicPeriod = "*Period - Week"  # $week - Week Number
		}
		30  { $dynamicPeriod = "*Period - Month" }
		365 { $dynamicPeriod = "*Period - Year" }
		"All"{ $dynamicPeriod = "*Period - All" }
		default { $dynamicPeriod = "Period" }
	}

	$yellowFont = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
	$yellowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Yellow)

	$g.DrawString($dynamicPeriod, $yellowFont, $yellowBrush, $periodTableX + 10, $periodTableY + 5)

	$yellowBrush.Dispose()
	$yellowFont.Dispose()

	# --- Динамична табела со боја како кај главната табела ---
	$y = $periodTableY + $periodHeaderHeight
	foreach ($row in $periodData) {
		# Gradient боја за секој ред
		$fillColorTop = [System.Drawing.Color]::FromArgb(180, 200, 245)
		$fillColorBottom = [System.Drawing.Color]::FromArgb(70, 120, 210)
		$rect = New-Object System.Drawing.Rectangle($periodTableX, $y, ($colWidthsPeriod | Measure-Object -Sum).Sum, $periodRowHeight)
		$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $fillColorTop, $fillColorBottom, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
		$g.FillRectangle($brush, $rect)
		$brush.Dispose()

		$x = $periodTableX
		$values = @($row.Period, (Convert-Bytes $row.Download), (Convert-Bytes $row.Upload), (Convert-Bytes $row.Total))

		for ($i=0; $i -lt $values.Count; $i++) {
			if ($PeriodDays -eq 1 -and $i -eq 0) {
				# Ако е дневен извештај → првата колона (Period) во црвено
				$redBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Red)
				$g.DrawString($values[$i], $cellFont, $redBrush, $x+10, $y+10)
				$redBrush.Dispose()
			}
			else {
				$g.DrawString($values[$i], $cellFont, $blackBrush, $x+10, $y+10)
			}
			$x += $colWidthsPeriod[$i]
		}

		$g.DrawLine($pen, $periodTableX, $y+$periodRowHeight, $periodTableX+($colWidthsPeriod | Measure-Object -Sum).Sum, $y+$periodRowHeight)
		$y += $periodRowHeight
	}

	# Цртање рамка околу период табелата
	$g.DrawRectangle($pen, $periodTableX, $periodTableY, ($colWidthsPeriod | Measure-Object -Sum).Sum, $periodHeaderHeight + ($periodData.Count * $periodRowHeight))

    # --- Главна табела (Interface) со реден број --- 
	# Сортирај по Total descending
	$aggregated = $aggregated | Sort-Object -Property Total -Descending
    $tableX = 50
    $tableY = $y + 20
    $colWidths = @(200,160,160,160)
    $headers = @("*Interface","Download","Upload","Total")
    $g.FillRectangle($headerBrush, $tableX, $tableY, ($colWidths | Measure-Object -Sum).Sum, $headerHeight)
    $x = $tableX
    for ($i=0; $i -lt $headers.Count; $i++) {
        $g.DrawString($headers[$i], $headerFont, $whiteBrush, $x+10, $tableY+5)
        $x += $colWidths[$i]
    }

	$y = $tableY + $headerHeight
	foreach ($row in $aggregated) {
		# Случајна боја за целиот ред
		$randColor = [System.Drawing.Color]::FromArgb(
			255,
			$rand.Next(50,230),
			$rand.Next(50,230),
			$rand.Next(50,230)
		)
		$rowBrush = New-Object System.Drawing.SolidBrush($randColor)
		$g.FillRectangle($rowBrush, $tableX, $y, ($colWidths | Measure-Object -Sum).Sum, $rowHeight)
		$rowBrush.Dispose()

		# Пишување вредности во редот
		$x = $tableX
		$values = @($row.Interface,(Convert-Bytes $row.Download),(Convert-Bytes $row.Upload),(Convert-Bytes $row.Total))
		for ($i=0; $i -lt $values.Count; $i++) {
			$g.DrawString($values[$i], $cellFont, $blackBrush, $x+10, $y+12)
			$x += $colWidths[$i]
		}

		# Линии за редот
		$g.DrawLine($pen, $tableX, $y+$rowHeight, $tableX+($colWidths | Measure-Object -Sum).Sum, $y+$rowHeight)
		$y += $rowHeight
	}

	# Цртање рамка околу целата таблица
	$g.DrawRectangle($pen, $tableX, $tableY, ($colWidths | Measure-Object -Sum).Sum, $headerHeight + ($aggregated.Count * $rowHeight))

    # --- Summary таблица (последна) ---
    if ($summaryData.Count -gt 0) {
        $summaryTableX = 50
        $summaryTableY = $y + 20
        $colWidthsSummary = @(200,160,160,160)
        $summaryHeaderHeight = 40
        $summaryRowHeight = 40
        $summaryHeader = @("*All Data","Download","Upload","*Total")

        # Header
        $g.FillRectangle($headerBrush, $summaryTableX, $summaryTableY, ($colWidthsSummary | Measure-Object -Sum).Sum, $summaryHeaderHeight)
        $x = $summaryTableX
        for ($i=0; $i -lt $summaryHeader.Count; $i++) {
            $g.DrawString($summaryHeader[$i], $headerFont, $whiteBrush, $x+10, $summaryTableY+5)
            $x += $colWidthsSummary[$i]
        }

        # Rows
		$y = $summaryTableY + $summaryHeaderHeight
		foreach ($row in $summaryData) {
			$fillColorTop = [System.Drawing.Color]::FromArgb(180, 200, 245)
			$fillColorBottom = [System.Drawing.Color]::FromArgb(70, 120, 210)
			$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
				[System.Drawing.Point]::new($summaryTableX, $y),
				[System.Drawing.Point]::new($summaryTableX, $y + $summaryRowHeight),
				$fillColorTop,
				$fillColorBottom
			)
			$g.FillRectangle($brush, $summaryTableX, $y, ($colWidthsSummary | Measure-Object -Sum).Sum, $summaryRowHeight)
			$brush.Dispose()

			$x = $summaryTableX
			$values = @($row.Period,(Convert-Bytes $row.Download),(Convert-Bytes $row.Upload),(Convert-Bytes $row.Total))

			for ($i=0; $i -lt $values.Count; $i++) {
				if ($i -eq 0) {
					# --- Првата колона (Period) → секогаш црвено ---
					$redBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Red)
					$g.DrawString($values[$i], $cellFont, $redBrush, $x+10, $y+10)
					$redBrush.Dispose()
				}
				elseif ($i -eq 3) {
					# Total = црвено, bold
					$totalFont = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
					$redBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Red)
					$g.DrawString($values[$i], $totalFont, $redBrush, $x+10, $y+8)
					$redBrush.Dispose()
					$totalFont.Dispose()
				}
				else {
					# Download и Upload → црно
					$g.DrawString($values[$i], $cellFont, $blackBrush, $x+10, $y+10)
				}
				$x += $colWidthsSummary[$i]
			}
			$g.DrawLine($pen, $summaryTableX, $y+$summaryRowHeight, $summaryTableX+($colWidthsSummary | Measure-Object -Sum).Sum, $y+$summaryRowHeight)
			$y += $summaryRowHeight
		}
		# === Footer ред со gradient и фиксен бел текст ===
		$footerText = "*Traffic Data  $(Get-Date -Format 'dddd, dd MMMM yyyy - HH:mm:ss')" # ден, месец со име, година, час:мин:сек
		$footerFont = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Regular)
		$footerRowHeight = 40

		# Случајни бои за gradient (без да бидат премногу светли)
		$rand = New-Object System.Random
		$colorTop = [System.Drawing.Color]::FromArgb($rand.Next(50,200), $rand.Next(50,200), $rand.Next(50,200))
		$colorBottom = [System.Drawing.Color]::FromArgb($rand.Next(50,200), $rand.Next(50,200), $rand.Next(50,200))

		$footerBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
			[System.Drawing.Point]::new($summaryTableX, $y),
			[System.Drawing.Point]::new($summaryTableX, $y + $footerRowHeight),
			$colorTop,
			$colorBottom
		)

		# Цртање на фондирањето
		$g.FillRectangle($footerBrush, $summaryTableX, $y, ($colWidthsSummary | Measure-Object -Sum).Sum, $footerRowHeight)
		$footerBrush.Dispose()

		# Бел текст
		$footerTextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

		# Центрирање на текстот
		$totalWidth = ($colWidthsSummary | Measure-Object -Sum).Sum
		$size = $g.MeasureString($footerText, $footerFont)
		$textX = $summaryTableX + ($totalWidth - $size.Width)/2
		$textY = $y + ($footerRowHeight - $size.Height)/2

		$g.DrawString($footerText, $footerFont, $footerTextBrush, $textX, $textY)

		# Долна граница на табелата
		$g.DrawLine($pen, $summaryTableX, $y + $footerRowHeight, $summaryTableX + $totalWidth, $y + $footerRowHeight)

		$y += $footerRowHeight

		# Чистење на ресурси
		$footerFont.Dispose()
		$footerTextBrush.Dispose()
	}

    # --- Снимање PNG ---
    $outputFile = Join-Path $DataFolder "table_${PeriodDays}d.png"
	
	# --- Додај лого (во центар) ---
	$logoPath = "$PSScriptRoot\media\table.png"
	if (Test-Path $logoPath) {
		$logo = [System.Drawing.Image]::FromFile($logoPath)
		$logoWidth = 220
		$logoHeight = 220
		$xLogo = ($width - $logoWidth) / 2
		$yLogo = ($bmpHeight - $logoHeight) / 2

		$attr = New-Object System.Drawing.Imaging.ImageAttributes
		$matrix = New-Object System.Drawing.Imaging.ColorMatrix
		$matrix.Matrix33 = 0.15  # транспарентност 25%
		$attr.SetColorMatrix($matrix)

		$g.DrawImage($logo,
			[System.Drawing.Rectangle]::new($xLogo, $yLogo, $logoWidth, $logoHeight),
			0, 0, $logo.Width, $logo.Height,
			[System.Drawing.GraphicsUnit]::Pixel,
			$attr
		)
		$attr.Dispose()
		$logo.Dispose()
	}
	
	# --- Воден жиг вертикално средина десно ---
	$watermarkText = "Generated by AutoPilot"
	$watermarkFont = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
	$watermarkBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(88,0,0,0))  # 88% opacity

	# Измери текстот
	$sizeWatermark = $g.MeasureString($watermarkText, $watermarkFont)

	# X = десната страна со мал пад (маргина)
	$xWatermark = $width - 45
	# Y = центар на висината, така што текстот ќе биде вертикално во средина
	$yWatermark = ($bmpHeight + $sizeWatermark.Width) / 2  # користиме Width бидејќи ќе ротираш -90

	# RotateTransform за текст вертикално (од долу кон горе)
	$g.TranslateTransform($xWatermark, $yWatermark)
	$g.RotateTransform(-90)
	$g.DrawString($watermarkText, $watermarkFont, $watermarkBrush, 0, 0)
	$g.ResetTransform()

	$watermarkBrush.Dispose()
	$watermarkFont.Dispose()

    $bmp.Save($outputFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    # Write-Host " Table PNG generated: $outputFile"
    return @{ Status="OK"; Output=$outputFile; Data=$aggregated }
}

###################################################################################### NetTrafficTable Script End.