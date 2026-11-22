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
$iconPath = Join-Path $AppRoot "media\system.png"
$loaderXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title=""
        Height="180" Width="355"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Topmost="True"
        Background="Transparent"
        WindowStyle="None"
        AllowsTransparency="True">
        <Border Background="#F222252C" CornerRadius="16" Padding="25" BorderBrush="#444954" BorderThickness="1">
        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
            <!-- PNG Logo -->
            <Image Name="imgLogo"
                   Width="64" Height="64"
                   Margin="0,0,0,10"
                   Source="$iconPath" />
            <!-- Modern Text -->
            <TextBlock Name="txtStatus" FontFamily="Segoe UI Semibold" FontSize="18" Foreground="#E4E4E7" HorizontalAlignment="Center" Text="⚙  System Monitor Loading..." />
        </StackPanel>
    </Border>
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
$diskColors = @("#A5B4FC","#5EEAD4","#FBBF24","#93C5FD","#FDA4AF","#C4B5FD","#86EFAC","#FDBA74","#67E8F9","#F9A8D4")

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
	    Width='1000'
		Icon="$AppRoot\media\system.ico"
        FontFamily='Segoe UI'
        WindowStartupLocation='CenterScreen'
        ResizeMode='NoResize'
	    Background='#1E2128'
	    SizeToContent='Height'>
	<Window.Resources>
	    <Style x:Key='ModernProgressBar' TargetType='ProgressBar'>
	        <Setter Property='Height' Value='10'/>
	        <Setter Property='Background' Value='#414754'/>
	        <Setter Property='BorderThickness' Value='0'/>
	        <Setter Property='Template'>
	            <Setter.Value>
	                <ControlTemplate TargetType='ProgressBar'>
	                    <Border Background='{TemplateBinding Background}' CornerRadius='5' ClipToBounds='True'>
	                        <Grid x:Name='PART_Track'>
	                            <Rectangle x:Name='PART_Indicator'
	                                       HorizontalAlignment='Left'
	                                       Fill='{TemplateBinding Foreground}'
	                                       RadiusX='5'
	                                       RadiusY='5'/>
	                        </Grid>
	                    </Border>
	                </ControlTemplate>
	            </Setter.Value>
	        </Setter>
	    </Style>
	</Window.Resources>
	<Grid Margin='24'>
	    <Grid.RowDefinitions>
	        <RowDefinition Height='Auto'/>
	        <RowDefinition Height='Auto'/>
	        <RowDefinition Height='Auto'/>
	        <RowDefinition Height='Auto'/>
	    </Grid.RowDefinitions>

	    <Grid Grid.Row='0' Margin='0,0,0,20'>
	        <Grid.ColumnDefinitions>
	            <ColumnDefinition Width='*'/>
	            <ColumnDefinition Width='Auto'/>
	        </Grid.ColumnDefinitions>
	        <StackPanel Orientation='Horizontal' VerticalAlignment='Center'>
	            <Image Source="$AppRoot\media\system.png" Width='48' Height='48' Stretch='Uniform' Margin='0,0,14,0'/>
	            <StackPanel VerticalAlignment='Center'>
	                <TextBlock Text='System Monitor' FontSize='28' FontWeight='Bold' Foreground='#F8FAFC'/>
	                <TextBlock Text='Live hardware performance &amp; temperature' FontSize='13' Foreground='#94A3B8' Margin='1,3,0,0'/>
	            </StackPanel>
	        </StackPanel>
	        <Border Grid.Column='1' Background='#272B34' BorderBrush='#3B3F4A' BorderThickness='1' CornerRadius='12' Padding='12,8' VerticalAlignment='Center'>
	            <StackPanel Orientation='Horizontal'>
	                <Ellipse Width='9' Height='9' Fill='#4ADE80' Margin='0,0,8,0' VerticalAlignment='Center'/>
	                <TextBlock Text='MONITORING' FontSize='12' FontWeight='Bold' Foreground='#E2E8F0' VerticalAlignment='Center'/>
	            </StackPanel>
	        </Border>
	    </Grid>

	    <Grid Grid.Row='1' Margin='0,0,0,14'>
	        <Grid.ColumnDefinitions>
	            <ColumnDefinition Width='*'/>
	            <ColumnDefinition Width='12'/>
	            <ColumnDefinition Width='*'/>
	            <ColumnDefinition Width='12'/>
	            <ColumnDefinition Width='*'/>
	        </Grid.ColumnDefinitions>

	        <Border Grid.Column='0' Background='#302D24' BorderBrush='#5A4A2B' BorderThickness='1' CornerRadius='14' Padding='17,16'>
	            <StackPanel>
	                <TextBlock Text='◉  PROCESSOR' FontSize='13' FontWeight='Bold' Foreground='#FBBF24' Margin='0,0,0,11'/>
	                <ProgressBar x:Name='barCPU' Minimum='0' Maximum='100' Value='0' Foreground='#FBBF24' Style='{StaticResource ModernProgressBar}'/>
	                <TextBlock x:Name='txtCPU' Text='0 %' FontSize='25' FontWeight='Bold' Foreground='#FFFBEB' Margin='0,8,0,14'/>
	                <TextBlock Text='CPU TEMPERATURE' FontSize='11' FontWeight='Bold' Foreground='#D6B95C' Margin='0,0,0,5'/>
	                <TextBlock x:Name='txtCPUTemp' Text='0 °C' FontSize='17' FontWeight='SemiBold' Foreground='#FEF3C7'/>
	            </StackPanel>
	        </Border>

	        <Border Grid.Column='2' Background='#202F2E' BorderBrush='#31564F' BorderThickness='1' CornerRadius='14' Padding='17,16'>
	            <StackPanel>
	                <TextBlock Text='▤  MEMORY' FontSize='13' FontWeight='Bold' Foreground='#5EEAD4' Margin='0,0,0,11'/>
	                <ProgressBar x:Name='barRAM' Minimum='0' Maximum='100' Value='0' Foreground='#2DD4BF' Style='{StaticResource ModernProgressBar}'/>
	                <TextBlock x:Name='txtRAM' Text='0 %' FontSize='25' FontWeight='Bold' Foreground='#CCFBF1' Margin='0,8,0,14'/>
	                <TextBlock Text='MOTHERBOARD TEMP' FontSize='11' FontWeight='Bold' Foreground='#5CCFC0' Margin='0,0,0,5'/>
	                <TextBlock x:Name='txtMotherboardTemp' Text='No measured' FontSize='17' FontWeight='SemiBold' Foreground='#CCFBF1'/>
	            </StackPanel>
	        </Border>

	        <Border Grid.Column='4' Background='#252B3A' BorderBrush='#3A4A69' BorderThickness='1' CornerRadius='14' Padding='17,16'>
	            <StackPanel>
	                <TextBlock Text='▣  GRAPHICS' FontSize='13' FontWeight='Bold' Foreground='#93C5FD' Margin='0,0,0,11'/>
	                <ProgressBar x:Name='barGPU' Minimum='0' Maximum='100' Value='0' Foreground='#60A5FA' Style='{StaticResource ModernProgressBar}'/>
	                <TextBlock x:Name='txtGPU' Text='0 %' FontSize='25' FontWeight='Bold' Foreground='#EFF6FF' Margin='0,8,0,14'/>
	                <TextBlock Text='GPU TEMPERATURE' FontSize='11' FontWeight='Bold' Foreground='#7CB6FA' Margin='0,0,0,5'/>
	                <TextBlock x:Name='txtGPUTemp' Text='0 °C' FontSize='17' FontWeight='SemiBold' Foreground='#DBEAFE'/>
	            </StackPanel>
	        </Border>
	    </Grid>

	    <Border Grid.Row='2' Background='#272B34' BorderBrush='#3B3F4A' BorderThickness='1' CornerRadius='14' Padding='20,17' Margin='0,0,0,14'>
	        <StackPanel>
	            <Grid Margin='0,0,0,14'>
	                <Grid.ColumnDefinitions>
	                    <ColumnDefinition Width='*'/>
	                    <ColumnDefinition Width='Auto'/>
	                </Grid.ColumnDefinitions>
	                <StackPanel Orientation='Horizontal'>
	                    <TextBlock Text='▣' FontSize='22' Foreground='#93C5FD' Margin='0,0,10,0' VerticalAlignment='Center'/>
	                    <StackPanel VerticalAlignment='Center'>
	                        <TextBlock Text='HARDWARE SENSOR TELEMETRY' FontSize='14' FontWeight='Bold' Foreground='#E2E8F0'/>
	                        <TextBlock Text='Live readings reported by available hardware sensors' FontSize='12' Foreground='#94A3B8' Margin='0,3,0,0'/>
	                    </StackPanel>
	                </StackPanel>
	                <Border Grid.Column='1' Background='#18372F' BorderBrush='#28634E' BorderThickness='1' CornerRadius='9' Padding='10,6' VerticalAlignment='Center'>
	                    <TextBlock Text='LIVE SENSOR DATA' FontSize='10' FontWeight='Bold' Foreground='#86EFAC'/>
	                </Border>
	            </Grid>
	            <Grid>
	                <Grid.ColumnDefinitions>
	                    <ColumnDefinition Width='*'/>
	                    <ColumnDefinition Width='1'/>
	                    <ColumnDefinition Width='*'/>
	                    <ColumnDefinition Width='1'/>
	                    <ColumnDefinition Width='*'/>
	                    <ColumnDefinition Width='1'/>
	                    <ColumnDefinition Width='*'/>
	                </Grid.ColumnDefinitions>
	                <StackPanel Grid.Column='0'>
	                    <TextBlock Text='CPU CLOCK (AVG)' FontSize='11' FontWeight='Bold' Foreground='#A5B4D4'/>
	                    <TextBlock x:Name='txtCPUClock' Text='Not measured' FontSize='17' FontWeight='Bold' Foreground='#FDE68A' Margin='0,5,0,0' TextWrapping='Wrap'/>
	                </StackPanel>
	                <Rectangle Grid.Column='1' Fill='#39415A' Width='1' Height='38' VerticalAlignment='Center'/>
	                <StackPanel Grid.Column='2' Margin='16,0,0,0'>
	                    <TextBlock Text='GPU MEMORY' FontSize='11' FontWeight='Bold' Foreground='#A5B4D4'/>
	                    <TextBlock x:Name='txtGPUMemory' Text='Not measured' FontSize='15' FontWeight='Bold' Foreground='#93C5FD' Margin='0,5,0,0' TextWrapping='Wrap'/>
	                </StackPanel>
	                <Rectangle Grid.Column='3' Fill='#39415A' Width='1' Height='38' VerticalAlignment='Center'/>
	                <StackPanel Grid.Column='4' Margin='16,0,0,0'>
	                    <TextBlock x:Name='lblFanHeader' Text='FAN SPEEDS (0)' FontSize='10' FontWeight='Bold' Foreground='#A5B4D4' TextWrapping='Wrap'/>
	                    <TextBlock x:Name='txtFanSpeed' Text='Not measured' FontSize='13' FontWeight='Bold' Foreground='#67E8F9' Margin='0,5,0,0' TextWrapping='Wrap'/>
	                </StackPanel>
	                <Rectangle Grid.Column='5' Fill='#39415A' Width='1' Height='38' VerticalAlignment='Center'/>
	                <StackPanel Grid.Column='6' Margin='16,0,0,0'>
	                    <TextBlock Text='CPU POWER' FontSize='11' FontWeight='Bold' Foreground='#A5B4D4'/>
	                    <TextBlock x:Name='txtCPUPower' Text='Not measured' FontSize='17' FontWeight='Bold' Foreground='#FDA4AF' Margin='0,5,0,0' TextWrapping='Wrap'/>
	                </StackPanel>
	            </Grid>
	        </StackPanel>
	    </Border>

	    <Border Grid.Row='3' Background='#272B34' BorderBrush='#3B3F4A' BorderThickness='1' CornerRadius='14' Padding='20,17'>
	        <StackPanel>
	            <Grid Margin='0,0,0,14'>
	                <Grid.ColumnDefinitions>
	                    <ColumnDefinition Width='*'/>
	                    <ColumnDefinition Width='Auto'/>
	                </Grid.ColumnDefinitions>
	                <StackPanel Orientation='Horizontal'>
	                    <TextBlock Text='▣' FontSize='22' Foreground='#A5B4FC' Margin='0,0,10,0' VerticalAlignment='Center'/>
	                    <StackPanel VerticalAlignment='Center'>
	                        <TextBlock Text='STORAGE TEMPERATURES' FontSize='14' FontWeight='Bold' Foreground='#E2E8F0'/>
	                        <TextBlock Text='Live readings from detected drives' FontSize='12' Foreground='#94A3B8' Margin='0,3,0,0'/>
	                    </StackPanel>
	                </StackPanel>
	                <Border Grid.Column='1' Background='#18372F' BorderBrush='#28634E' BorderThickness='1' CornerRadius='9' Padding='11,7' VerticalAlignment='Center'>
	                    <TextBlock x:Name='lblDiskCount' FontSize='11' FontWeight='Bold' Foreground='#86EFAC'/>
	                </Border>
	            </Grid>
	            <Border Background='#191D24' BorderBrush='#3B4657' BorderThickness='1' CornerRadius='12' Padding='12,10'>
	                <StackPanel x:Name='diskContainer' Orientation='Vertical' HorizontalAlignment='Stretch'/>
	            </Border>
	            <Grid Margin='0,15,0,0'>
	                <Grid.ColumnDefinitions>
	                    <ColumnDefinition Width='*'/>
	                    <ColumnDefinition Width='*'/>
	                </Grid.ColumnDefinitions>
	                <TextBlock x:Name='txtCurrentTime' Grid.Column='0' Text='◷  Time: 00:00:00' FontSize='14' FontWeight='SemiBold' Foreground='#93C5FD' HorizontalAlignment='Left'/>
	                <TextBlock x:Name='txtDiskElapsed' Grid.Column='1' Text='⏱  Elapsed: 00:00:00' FontSize='14' FontWeight='SemiBold' Foreground='#C7D2FE' HorizontalAlignment='Right'/>
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
$lblDiskCount = $window.FindName('lblDiskCount')
$driveCount = @($global:diskBlocks).Count
$lblDiskCount.Text = if ($driveCount -eq 1) { "●  1 DRIVE DETECTED" } else { "●  $driveCount DRIVES DETECTED" }

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
    $time = "{0:hh\:mm\:ss}" -f $elapsed

    if ($elapsed.Days -gt 0) {
        $dayText = if ($elapsed.Days -eq 1) { "Day" } else { "Days" }
        $txtDiskElapsed.Text = "Elapsed: $($elapsed.Days) $dayText $time"
    } else {
        $txtDiskElapsed.Text = "Elapsed: $time"
    }
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
$txtCPUClock = $window.FindName("txtCPUClock")
$txtGPUMemory = $window.FindName("txtGPUMemory")
$lblFanHeader = $window.FindName("lblFanHeader")
$txtFanSpeed = $window.FindName("txtFanSpeed")
$txtCPUPower = $window.FindName("txtCPUPower")

$diskContainer = $window.FindName("diskContainer")

# ===================== Create Disk TextBlocks =====================
$diskIndex = 1
foreach ($disk in $global:diskBlocks) {
    $diskName = "$diskIndex. $($disk.Hardware.Name)"
    $color = $diskColors[($diskIndex - 1) % $diskColors.Count]

    $nameBlock = New-Object System.Windows.Controls.TextBlock
    $nameBlock.Text = $diskName
    $nameBlock.FontSize = 16
    $nameBlock.FontWeight = "Bold"
    $nameBlock.Foreground = $color
    $nameBlock.HorizontalAlignment = "Left"
    $nameBlock.VerticalAlignment = "Center"
    $nameBlock.Margin = "0,0,12,0"

    $tempBlock = New-Object System.Windows.Controls.TextBlock
    $tempBlock.Text = "No measured"
    $tempBlock.FontSize = 16
    $tempBlock.FontWeight = "SemiBold"
    $tempBlock.Foreground = "#F1F5F9"
    $tempBlock.HorizontalAlignment = "Right"
    $tempBlock.VerticalAlignment = "Center"

    $disk.TempText = $tempBlock  # link textblock
    $diskRow = New-Object System.Windows.Controls.Grid
    $diskRow.Margin = [System.Windows.Thickness]::new(0,7,0,7)
    $diskRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) | Out-Null
    $diskRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "Auto" })) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($nameBlock,0)
    [System.Windows.Controls.Grid]::SetColumn($tempBlock,1)
    $diskRow.Children.Add($nameBlock) | Out-Null
    $diskRow.Children.Add($tempBlock) | Out-Null

    $diskCard = New-Object System.Windows.Controls.Border
    $diskCard.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(39,44,54))
    $diskCard.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(61,70,85))
    $diskCard.BorderThickness = [System.Windows.Thickness]::new(1)
    $diskCard.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $diskCard.Padding = [System.Windows.Thickness]::new(14,9,14,9)
    $diskCard.Margin = [System.Windows.Thickness]::new(0,0,0,8)
    $diskCard.Child = $diskRow
    $diskContainer.Children.Add($diskCard) | Out-Null

    $diskIndex++
}

function Get-AllHardwareSensors {
    param($HardwareItems)

    foreach ($hardwareItem in $HardwareItems) {
        foreach ($sensor in $hardwareItem.Sensors) {
            $sensor
        }
        if ($hardwareItem.SubHardware) {
            Get-AllHardwareSensors $hardwareItem.SubHardware
        }
    }
}

function Test-UsableHardwareSensorValue {
    param($Sensor)

    if ($null -eq $Sensor -or $null -eq $Sensor.Value) { return $false }
    $value = [double]$Sensor.Value
    return $value -ge 0 -and -not [double]::IsNaN($value) -and -not [double]::IsInfinity($value)
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

        $cpuHardware = $computer.Hardware | Where-Object { $_.HardwareType -eq 'Cpu' } | Select-Object -First 1
        $gpuHardware = $computer.Hardware | Where-Object { $_.HardwareType -in @('GpuNvidia','GpuAmd') } | Select-Object -First 1
        $allSensors = @(Get-AllHardwareSensors $computer.Hardware)
        $cpuSensors = if ($cpuHardware) { @(Get-AllHardwareSensors @($cpuHardware)) } else { @() }
        $gpuSensors = if ($gpuHardware) { @(Get-AllHardwareSensors @($gpuHardware)) } else { @() }

        $cpuClockSensors = @($cpuSensors | Where-Object {
            $_.SensorType -eq 'Clock' -and (Test-UsableHardwareSensorValue $_) -and $_.Name -notmatch 'Bus'
        })
        if ($cpuClockSensors.Count -gt 0) {
            $clockMHz = ($cpuClockSensors | Measure-Object -Property Value -Average).Average
            $txtCPUClock.Text = if ($clockMHz -ge 1000) { "Avg {0:N2} GHz" -f ($clockMHz / 1000) } else { "Avg {0:N0} MHz" -f $clockMHz }
        } else {
            $txtCPUClock.Text = "Not measured"
        }

        $gpuMemorySensors = @($gpuSensors | Where-Object {
            $_.Name -match 'Memory|VRAM' -and (Test-UsableHardwareSensorValue $_) -and $_.SensorType -in @('Data','SmallData','Load')
        })
        $gpuMemoryUsedSensor = $gpuMemorySensors |
            Where-Object { $_.Name -match '(?i)(used|usage|utili[sz](ed|ation))' } |
            Select-Object -First 1
        if (-not $gpuMemoryUsedSensor) {
            $gpuMemoryUsedSensor = $gpuMemorySensors |
                Where-Object { $_.SensorType -eq 'Load' -and $_.Name -notmatch '(?i)(total|capacity)' } |
                Select-Object -First 1
        }
        $gpuMemoryTotalSensor = $gpuMemorySensors |
            Where-Object { $_.Name -match '(?i)(total|capacity)' -and $_.SensorType -ne 'Load' } |
            Select-Object -First 1
        if ($gpuMemoryUsedSensor) {
            if ($gpuMemoryUsedSensor.SensorType -eq 'Load') {
                $txtGPUMemory.Text = "{0:N0}% utilization" -f [double]$gpuMemoryUsedSensor.Value
            } else {
                $usedUnit = if ($gpuMemoryUsedSensor.SensorType -eq 'SmallData') { 'MB' } else { 'GB' }
                $usedText = "{0:N2} {1}" -f [double]$gpuMemoryUsedSensor.Value, $usedUnit
                if ($gpuMemoryTotalSensor) {
                    $totalUnit = if ($gpuMemoryTotalSensor.SensorType -eq 'SmallData') { 'MB' } else { 'GB' }
                    $totalText = "{0:N2} {1}" -f [double]$gpuMemoryTotalSensor.Value, $totalUnit
                    $txtGPUMemory.Text = "$usedText / $totalText"
                } else {
                    $txtGPUMemory.Text = $usedText
                }
            }
        } else {
            $txtGPUMemory.Text = "Not measured"
        }

        $fanSensors = @($allSensors | Where-Object {
            $_.SensorType -eq 'Fan' -and (Test-UsableHardwareSensorValue $_)
        })
        if ($fanSensors.Count -gt 0) {
            $lblFanHeader.Text = "FAN SPEEDS ($($fanSensors.Count))"
            $fanLines = for ($fanIndex = 0; $fanIndex -lt $fanSensors.Count; $fanIndex++) {
                $fan = $fanSensors[$fanIndex]
                $fanName = if ([string]::IsNullOrWhiteSpace($fan.Name)) { "Fan $($fanIndex + 1)" } else { $fan.Name }
                "{0}. {1}: {2:N0} RPM" -f ($fanIndex + 1), $fanName, [double]$fan.Value
            }
            $txtFanSpeed.Text = $fanLines -join "`n"
        } else {
            $lblFanHeader.Text = "FAN SPEEDS (0)"
            $txtFanSpeed.Text = "Not measured"
        }

        $cpuPowerSensor = $cpuSensors |
            Where-Object { $_.SensorType -eq 'Power' -and (Test-UsableHardwareSensorValue $_) } |
            Sort-Object @{ Expression = {
                if ($_.Name -match '(?i)package') { 0 }
                elseif ($_.Name -match '(?i)(total|socket)') { 1 }
                elseif ($_.Name -match '(?i)cpu') { 2 }
                elseif ($_.Name -match '(?i)core') { 4 }
                else { 3 }
            } } |
            Select-Object -First 1
        $txtCPUPower.Text = if ($cpuPowerSensor) { "{0:N1} W" -f [double]$cpuPowerSensor.Value } else { "Not measured" }

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