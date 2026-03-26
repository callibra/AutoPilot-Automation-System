# APP ROOT
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

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml

# ===================== Loader XAML =====================
$loaderXaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Loading...' Width='400' Height='150'
        WindowStartupLocation='CenterScreen'
        ResizeMode='NoResize'
        WindowStyle='None'
        Background='#1E1E1E'>
    <Grid>
		<StackPanel HorizontalAlignment='Center' VerticalAlignment='Center'>
			<TextBlock Text='Loading System Monitor...' FontSize='20' FontWeight='Bold' Foreground='White' HorizontalAlignment='Center' Margin='0,0,0,10'/>
			<Image Source="$AppRoot\media\system.png" Width='55' Height='55' Stretch='Uniform' Opacity='0.55' HorizontalAlignment='Center'/>
		</StackPanel>
    </Grid>
</Window>
"@

# Show loader
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($loaderXaml))
$loaderWindow = [Windows.Markup.XamlReader]::Load($reader)
$loaderWindow.Show()

# ===================== Load LibreHardwareMonitor =====================
$libPath = "$AppRoot\Dll\LibreHardwareMonitorLib.dll"
if (-not (Test-Path $libPath)) { 
    $loaderWindow.Close()
    [System.Windows.MessageBox]::Show("LibreHardwareMonitorLib.dll not found!","Error","OK","Error")
    exit 
}
Add-Type -Path $libPath

# ===================== Initialize Computer =====================
$computer = New-Object LibreHardwareMonitor.Hardware.Computer
$computer.IsCpuEnabled = $true
$computer.IsMemoryEnabled = $true
$computer.IsMotherboardEnabled = $true
$computer.IsGpuEnabled = $true
$computer.IsStorageEnabled = $true
$computer.Open()

# ===================== Prepare Disk Blocks =====================
$global:diskBlocks = @()
$diskIndex = 1
$diskColors = @("Pink","LightBlue","LightGreen","White","LightBlue","LightGreen","Orange","Magenta","Yellow","Cyan")

$computer.Hardware | Where-Object { $_.HardwareType -eq "Storage" } | ForEach-Object {
    $_.Update()
    $global:diskBlocks += [PSCustomObject]@{
        Hardware = $_
        TempText = $null
        MaxTemp = 0
    }
    $diskIndex++
}

# Max temperatures globals
$global:maxCPUTemp = 0
$global:maxGPUTemp = 0
$global:maxMoboTemp = 0

# ===================== Loader Done =====================
$loaderWindow.Close()

# ===================== MAIN GUI XAML =====================
$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='System Monitor'
        Width='999'
		Icon="$AppRoot\media\system.ico"
        FontFamily='Segoe UI'
        WindowStartupLocation='CenterScreen'
        ResizeMode='NoResize'
        SizeToContent='Height'>
    <Window.Background>
        <DrawingBrush Stretch='None' AlignmentX='Center' AlignmentY='Center' Opacity='0.20'>
            <DrawingBrush.Drawing>
                <ImageDrawing Rect='0,0,415,415' ImageSource='$AppRoot\media\system.png'/>
            </DrawingBrush.Drawing>
        </DrawingBrush>
    </Window.Background>
    <Grid Margin='15'>
        <Grid.RowDefinitions>
            <RowDefinition Height='Auto' />
            <RowDefinition Height='Auto' />
        </Grid.RowDefinitions>
        <!-- Top Panels -->
        <Grid Grid.Row='0'>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width='*'/>
                <ColumnDefinition Width='*'/>
                <ColumnDefinition Width='*'/>
            </Grid.ColumnDefinitions>
            <!-- CPU -->
            <Border Grid.Column='0' Background='#CC2D2D30' CornerRadius='12' Padding='20' Margin='10'>
                <StackPanel HorizontalAlignment='Center'>
                    <TextBlock Text='CPU Usage' FontSize='20' FontWeight='Bold' Foreground='#FFD700' HorizontalAlignment='Center'/>
                    <ProgressBar x:Name='barCPU' Width='150' Height='18' Minimum='0' Maximum='100' Value='0' Margin='0,8,0,3' Foreground='#5CBD66'/>
                    <TextBlock x:Name='txtCPU' Text='0 %' FontSize='20' FontWeight='Bold' Foreground='White' HorizontalAlignment='Center'/>
                    <TextBlock Text='CPU Temp' FontSize='20' FontWeight='Bold' Foreground='#FFD700' HorizontalAlignment='Center' Margin='0,10,0,0'/>
                    <TextBlock x:Name='txtCPUTemp' Text='0 °C' FontSize='20' FontWeight='Bold' Foreground='White' HorizontalAlignment='Center'/>
                </StackPanel>
            </Border>
            <!-- RAM -->
            <Border Grid.Column='1' Background='#CC2D2D30' CornerRadius='12' Padding='20' Margin='10'>
                <StackPanel HorizontalAlignment='Center'>
                    <TextBlock Text='RAM Usage' FontSize='20' FontWeight='Bold' Foreground='#4EC9B0' HorizontalAlignment='Center'/>
                    <ProgressBar x:Name='barRAM' Width='150' Height='18' Minimum='0' Maximum='100' Value='0' Margin='0,8,0,3' Foreground='#5CBD66'/>
                    <TextBlock x:Name='txtRAM' Text='0 %' FontSize='20' FontWeight='Bold' Foreground='White' HorizontalAlignment='Center'/>
                    <TextBlock Text='MB Temp' FontSize='20' FontWeight='Bold' Foreground='#4EC9B0' HorizontalAlignment='Center' Margin='0,10,0,0'/>
                    <TextBlock x:Name='txtMotherboardTemp' Text='No measured' FontSize='20' FontWeight='Bold' Foreground='White' HorizontalAlignment='Center'/>
                </StackPanel>
            </Border>
            <!-- GPU -->
            <Border Grid.Column='2' Background='#CC2D2D30' CornerRadius='12' Padding='20' Margin='10'>
                <StackPanel HorizontalAlignment='Center'>
                    <TextBlock Text='GPU Usage' FontSize='20' FontWeight='Bold' Foreground='#4E90ED' HorizontalAlignment='Center'/>
                    <ProgressBar x:Name='barGPU' Width='150' Height='18' Minimum='0' Maximum='100' Value='0' Margin='0,8,0,3' Foreground='#5CBD66'/>
                    <TextBlock x:Name='txtGPU' Text='0 %' FontSize='20' FontWeight='Bold' Foreground='White' HorizontalAlignment='Center'/>
                    <TextBlock Text='GPU Temp' FontSize='20' FontWeight='Bold' Foreground='#4E90ED' HorizontalAlignment='Center' Margin='0,10,0,0'/>
                    <TextBlock x:Name='txtGPUTemp' Text='0 °C' FontSize='20' FontWeight='Bold' Foreground='White' HorizontalAlignment='Center'/>
                </StackPanel>
            </Border>
        </Grid>
		<!-- DISK -->
		<Border Grid.Row='1' Background='#CC2D2D30' CornerRadius='12' Padding='20' Margin='10'>
			<StackPanel>
				<TextBlock Text='DISK Temp' FontSize='20' FontWeight='Bold'  Foreground='#95E670' HorizontalAlignment='Center' Margin='0,0,0,10'/>
				<StackPanel x:Name='diskContainer' Orientation='Vertical' HorizontalAlignment='Stretch'/>
				<!-- Timer and Clock -->
				<Grid Margin='0,10,0,0'>
					<Grid.ColumnDefinitions>
						<ColumnDefinition Width='*'/>
						<ColumnDefinition Width='*'/>
					</Grid.ColumnDefinitions>
					<!-- LEFT : REAL TIME -->
					<TextBlock x:Name='txtCurrentTime' Grid.Column='0' Text='Time: 00:00:00' FontSize='18' FontWeight='Bold' Foreground='#5CBD66' HorizontalAlignment='Left'/>
					<!-- RIGHT : ELAPSED -->
					<TextBlock x:Name='txtDiskElapsed' Grid.Column='1' Text='Elapsed: 00:00:00' FontSize='18' FontWeight='Bold' Foreground='#E0DA4F' HorizontalAlignment='Right'/>
				</Grid>
			</StackPanel>
		</Border>
	</Grid>
</Window>
"@

# ===================== Load Main GUI =====================
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get TextBlocks from XAML
$txtCurrentTime = $window.FindName('txtCurrentTime')
$txtDiskElapsed  = $window.FindName('txtDiskElapsed')

# Store the start time
$startTime = Get-Date

# DispatcherTimer to update both every second
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)

$timer.Add_Tick({
    # Actual system time
    $txtCurrentTime.Text = "Time: " + (Get-Date).ToString("HH:mm:ss")
    
    # Elapsed time
    $elapsed = (Get-Date) - $startTime
    $txtDiskElapsed.Text = "Elapsed: " + $elapsed.ToString("hh\:mm\:ss")
})

$timer.Start()

# GUI Controls
$txtCPU = $window.FindName("txtCPU")
$barCPU = $window.FindName("barCPU")
$txtCPUTemp = $window.FindName("txtCPUTemp")

$txtRAM = $window.FindName("txtRAM")
$barRAM = $window.FindName("barRAM")
$txtMotherboardTemp = $window.FindName("txtMotherboardTemp")

$txtGPU = $window.FindName("txtGPU")
$barGPU = $window.FindName("barGPU")
$txtGPUTemp = $window.FindName("txtGPUTemp")

$diskContainer = $window.FindName("diskContainer")

# ===================== Create Disk TextBlocks =====================
$diskIndex = 1
foreach ($disk in $global:diskBlocks) {
    $diskName = "$diskIndex. $($disk.Hardware.Name)"
    $color = $diskColors[($diskIndex - 1) % $diskColors.Count]

    $nameBlock = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text = $diskName
    $nameBlock.FontSize = 20
    $nameBlock.FontWeight = "Bold"
    $nameBlock.Foreground = $color
    $nameBlock.HorizontalAlignment = "Center"
    $nameBlock.Margin = "0,10,0,0"

    $tempBlock = New-Object System.Windows.Controls.TextBlock
    $tempBlock.Text = "No measured"
    $tempBlock.FontSize = 20
    $tempBlock.FontWeight = "Bold"
    $tempBlock.Foreground = "White"
    $tempBlock.HorizontalAlignment = "Center"

    $disk.TempText = $tempBlock  # link textblock
    $diskContainer.Children.Add($nameBlock) | Out-Null
    $diskContainer.Children.Add($tempBlock) | Out-Null

    $diskIndex++
}

# Usage Color
function Get-UsageColor($value)
{
    if ($value -le 50)
    {
        # Green -> Yellow
        $ratio = $value / 50
        $r = [math]::Round(255 * $ratio)
        $g = 255
    }
    elseif ($value -le 70)
    {
        # Yellow стабилна зона
        $r = 255
        $g = 255
    }
    elseif ($value -le 85)
    {
        # Yellow -> Orange
        $ratio = ($value - 70) / 15
        $r = 255
        $g = [math]::Round(255 - (120 * $ratio))
    }
    else
    {
        # Orange -> Red
        $ratio = ($value - 85) / 15
        $r = 255
        $g = [math]::Round(135 - (135 * $ratio))
    }

    return [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb($r,$g,0)
    )
}

# CPU counter (Task Manager)
$cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor Information", "% Processor Utility", "_Total")

# Prime (Value 0)
$null = $cpuCounter.NextValue()
Start-Sleep -Milliseconds 300

# ===================== PerformanceCounter for RAM =====================
$ramCounter = New-Object System.Diagnostics.PerformanceCounter("Memory", "% Committed Bytes In Use")

# ===================== Dispatcher Timer =====================
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    try {
        $computer.Hardware | ForEach-Object { $_.Update() }

        # CPU Load & Temp
        $cpuLoad = [math]::Round($cpuCounter.NextValue(),1)
        $cpuTempSensor = ($computer.Hardware | Where-Object { $_.HardwareType -eq 'Cpu' } | ForEach-Object { $_.Sensors | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Value -ne $null } } | Select-Object -First 1)
        $cpuTemp = if ($cpuTempSensor) { [math]::Round($cpuTempSensor.Value,1) } else {$null}
        if ($cpuTemp -ne $null -and $cpuTemp -gt $global:maxCPUTemp) { $global:maxCPUTemp = $cpuTemp }
        $txtCPU.Text = "$cpuLoad %"
        $barCPU.Value = $cpuLoad
        $barCPU.Foreground = Get-UsageColor $cpuLoad
        $txtCPUTemp.Inlines.Clear()
        if ($cpuTemp -ne $null) {
            $txtCPUTemp.Inlines.Add([System.Windows.Documents.Run]::new("$cpuTemp °C "))
            $runMaxCPU = [System.Windows.Documents.Run]::new("  Max: $global:maxCPUTemp °C")
            $runMaxCPU.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E04F4F")
            $txtCPUTemp.Inlines.Add($runMaxCPU)
        } else { $txtCPUTemp.Text = "No measured" }

        # RAM Load
        $ramLoad = [math]::Round($ramCounter.NextValue(),1)
        $txtRAM.Text = "$ramLoad %"
        $barRAM.Value = $ramLoad
        $barRAM.Foreground = Get-UsageColor $ramLoad

        # Motherboard Temp
        $mobo = $computer.Hardware | Where-Object { $_.HardwareType -eq 'Motherboard' } | Select-Object -First 1
        $moboTemp = $null
        if ($mobo) {
            $mobo.Update()
            $sensor = $mobo.Sensors | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Value -ne $null } | Select-Object -First 1
            if ($sensor) { $moboTemp = [math]::Round($sensor.Value,1) }
        }
        if ($moboTemp -ne $null -and $moboTemp -gt $global:maxMoboTemp) { $global:maxMoboTemp = $moboTemp }
        $txtMotherboardTemp.Inlines.Clear()
        if ($moboTemp -ne $null) {
            $txtMotherboardTemp.Inlines.Add([System.Windows.Documents.Run]::new("$moboTemp °C "))
            $runMaxMobo = [System.Windows.Documents.Run]::new("  Max: $global:maxMoboTemp °C")
            $runMaxMobo.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E04F4F")
            $txtMotherboardTemp.Inlines.Add($runMaxMobo)
        } else { $txtMotherboardTemp.Text = "No measured" }

        # GPU
        $gpuLoadSensor = ($computer.Hardware | Where-Object { $_.HardwareType -in @('GpuNvidia','GpuAmd') } | ForEach-Object { $_.Sensors | Where-Object { $_.SensorType -eq 'Load' -and $_.Value -ne $null } } | Select-Object -First 1)
        $gpuLoad = if ($gpuLoadSensor) { [math]::Round($gpuLoadSensor.Value,1) } else {0}

        $gpuTempSensor = ($computer.Hardware | Where-Object { $_.HardwareType -in @('GpuNvidia','GpuAmd') } | ForEach-Object { $_.Sensors | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Value -ne $null } } | Select-Object -First 1)
        $gpuTemp = if ($gpuTempSensor) { [math]::Round($gpuTempSensor.Value,1) } else {$null}

        if ($gpuTemp -ne $null -and $gpuTemp -gt $global:maxGPUTemp) { $global:maxGPUTemp = $gpuTemp }

        $txtGPU.Text = "$gpuLoad %"
        $barGPU.Value = $gpuLoad
        $barGPU.Foreground = Get-UsageColor $gpuLoad
        $txtGPUTemp.Inlines.Clear()
        if ($gpuTemp -ne $null) {
            $txtGPUTemp.Inlines.Add([System.Windows.Documents.Run]::new("$gpuTemp °C "))
            $runMaxGPU = [System.Windows.Documents.Run]::new("  Max: $global:maxGPUTemp °C")
            $runMaxGPU.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E04F4F")
            $txtGPUTemp.Inlines.Add($runMaxGPU)
        } else { $txtGPUTemp.Text = "No measured" }

        # Disk Temps
        foreach ($disk in $global:diskBlocks) {
            $disk.Hardware.Update()
            $sensor = $disk.Hardware.Sensors | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Value -ne $null } | Select-Object -First 1
            $currentTemp = if ($sensor) { [math]::Round($sensor.Value,1) } else {$null}

            if ($currentTemp -ne $null -and $currentTemp -gt $disk.MaxTemp) { $disk.MaxTemp = $currentTemp }

            $disk.TempText.Inlines.Clear()
            if ($currentTemp -ne $null) {
                $disk.TempText.Inlines.Add([System.Windows.Documents.Run]::new("$currentTemp °C "))
                $runMaxDisk = [System.Windows.Documents.Run]::new("  Max: $($disk.MaxTemp) °C")
                $runMaxDisk.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E04F4F")
                $disk.TempText.Inlines.Add($runMaxDisk)
            } else {
                $disk.TempText.Text = "No measured"
            }
        }

    } catch {
        # silent fail
    }
})
$timer.Start()

# ===================== Show Main Window =====================
$window.ShowDialog() | Out-Null

######################################################################################################## End System Monitor.