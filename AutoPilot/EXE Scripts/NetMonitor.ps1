# APP ROOT
if ($AppRoot) {
    $AppRoot = $AppRoot
}
else {
    $AppRoot = Split-Path -Parent (
        [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    )
}

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

# Load the NetMonitor DLL
Add-Type -Path "$AppRoot\Dll\NetMonitor.dll"

function Format-Size {
    param([long]$bytes)
    if ($bytes -ge 1GB) { "{0:N2} GB" -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { "{0:N2} MB" -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { "{0:N2} KB" -f ($bytes / 1KB) }
    else { "$bytes B" }
}

# --- XAML GUI ---
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Live Network Monitor"
        Width="600" Height="488"
        Background="#1E1E1E"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        FontFamily="Segoe UI">

        <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Center" Margin="0,0,0,15">
		    <Image Source="$AppRoot\media\table.png" Width="50" Height="50" VerticalAlignment="Center" Margin="3,0,8,0"/>		
            <TextBlock Text="Live Network Monitor"
                       FontSize="28"
                       FontWeight="Bold"
                       Foreground="#F0F0F0"
                       VerticalAlignment="Center"/>
	    	<Ellipse x:Name="netLight" Width="28" Height="28" Fill="Red" VerticalAlignment="Center" Margin="8,3,8,0"/>	   
        </StackPanel>

        <Border Grid.Row="1"
                Background="#2D2D30"
                CornerRadius="18"
                Padding="20"
                BorderBrush="#444"
                BorderThickness="1">
            <StackPanel>

                <TextBlock x:Name="lblInterface" FontSize="20" Margin="0,4" Foreground="#FFD700"/>
                <TextBlock x:Name="lblStart" FontSize="20" Margin="0,4" Foreground="#63A5FF"/>
                <TextBlock x:Name="lblStatus" FontSize="20" Margin="0,4" Foreground="#FFA500"/>
                <Separator Margin="0,10" Background="#555"/>

                <DockPanel Margin="0,2">
                    <TextBlock x:Name="lblDown" FontSize="20" Foreground="#4EC9B0" DockPanel.Dock="Left"/>
                    <TextBlock x:Name="lblDownSpeed" FontSize="20" Foreground="#4EC9B0" Margin="20,0,0,0"/>
                </DockPanel>

                <DockPanel Margin="0,2">
                    <TextBlock x:Name="lblUp" FontSize="20" Foreground="#D16969" DockPanel.Dock="Left"/>
                    <TextBlock x:Name="lblUpSpeed" FontSize="20" Foreground="#D16969" Margin="20,0,0,0"/>
                </DockPanel>

                <TextBlock x:Name="lblTotal" FontSize="21" FontWeight="SemiBold" Margin="0,4" Foreground="#569CD6"/>

                <!-- Internet Strength Meter with text -->
                <DockPanel Margin="0,10,0,0" LastChildFill="False">
                    <Border x:Name="netMeter" Height="20" Width="288" CornerRadius="5" Background="#444" DockPanel.Dock="Left">
                        <Rectangle x:Name="netMeterFill" Height="20" Width="0" Fill="#4EC9B0" RadiusX="5" RadiusY="5"/>
                    </Border>
                    <TextBlock x:Name="lblNetSpeed" FontSize="18" FontWeight="SemiBold" Margin="10,0,0,0" Foreground="White" VerticalAlignment="Center"/>
                </DockPanel>

            </StackPanel>
        </Border>
        
        <Grid Grid.Row="2" Margin="0,10,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <!-- Elapsed Text -->
            <TextBlock x:Name="lblElapsed" FontSize="18" Foreground="#569CD6" FontWeight="SemiBold" VerticalAlignment="Center" HorizontalAlignment="Left"/>

            <!-- Reset Button -->
            <Button x:Name="btnReset" Width="100" Height="28" Grid.Row="2" HorizontalAlignment="Right" Margin="0,0,0,0" Cursor="Hand">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" CornerRadius="5" Background="#3D3D3D">
                            <TextBlock x:Name="text"
                                       Text="Reset"
                                       FontFamily="Segoe UI"
                                       FontSize="18"
                                       FontWeight="SemiBold"
                                       Foreground="#569CD6"
                                       HorizontalAlignment="Center"
                                       VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#4F4F4F"/>
                                <Setter TargetName="text" Property="Foreground" Value="Red"/> 
                                <Setter TargetName="text" Property="FontSize" Value="18"/>  
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Button.Template>
            </Button>
        </Grid>
    </Grid>
</Window>
"@

# --- Load XAML and controls ---
$xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($xmlReader)

$iconPath = Join-Path $AppRoot "media\net.ico"
$window.Icon = New-Object System.Windows.Media.Imaging.BitmapImage(
    (New-Object System.Uri($iconPath))
)

$lblInterface = $window.FindName("lblInterface")
$lblStart     = $window.FindName("lblStart")
$lblStatus    = $window.FindName("lblStatus")
$lblDown      = $window.FindName("lblDown")
$lblDownSpeed = $window.FindName("lblDownSpeed")
$lblUp        = $window.FindName("lblUp")
$lblUpSpeed   = $window.FindName("lblUpSpeed")
$lblTotal     = $window.FindName("lblTotal")
$netMeter     = $window.FindName("netMeter")
$netMeterFill = $window.FindName("netMeterFill")
$lblNetSpeed  = $window.FindName("lblNetSpeed")
$lblElapsed   = $window.FindName("lblElapsed")
$btnReset     = $window.FindName("btnReset")
$netLight     = $window.FindName("netLight")

# --- Initialize statistics ---
$startTime = Get-Date
$totals = @{ Download = 0; Upload = 0 }
$prevStatsPerInterface = @{}

# --- Reset button click ---
$btnReset.Add_Click({
    $totals.Download = 0
    $totals.Upload = 0
    $prevStatsPerInterface.Clear()
})

# --- Dispatcher Timer ---
$refresh = New-Object System.Windows.Threading.DispatcherTimer
$refresh.Interval = [TimeSpan]::FromSeconds(1)

$refresh.Add_Tick({

    # --- Get network stats from DLL ---
    $samples = [NetMonitor.TrafficNative]::SampleAll()
    $adapterSample = if ($samples -and $samples.Count -gt 0) { $samples[0] } else { $null }

    # --- STATUS COLOR LOGIC ---
    if (-not $adapterSample) {
        $netLight.Fill = [System.Windows.Media.Brushes]::Red
        $lblStatus.Text = "Disconnected"
    }
    else {
        $netLight.Fill = [System.Windows.Media.Brushes]::Green
        $lblStatus.Text = "Connected"
    }

    if (-not $adapterSample) {
        $lblInterface.Text = "No Active Interface"
        $lblDown.Text  = "Download: {0}" -f (Format-Size $totals.Download)
        $lblDownSpeed.Text = " * Speed: 0 MB/s"
        $lblUp.Text    = "Upload:   {0}" -f (Format-Size $totals.Upload)
        $lblUpSpeed.Text = " * Speed: 0 MB/s"
        $lblTotal.Text = "Total:    {0}" -f (Format-Size ($totals.Download + $totals.Upload))
        $lblElapsed.Text = "Elapsed: {0:hh\:mm\:ss}" -f ((Get-Date) - $startTime)
        return
    }

    $name = $adapterSample.Interface
    $lblInterface.Text = "Interface: $name"

    $deltaDown = $adapterSample.DownloadBytes
    $deltaUp   = $adapterSample.UploadBytes

    # Update totals
    $totals.Download += $deltaDown
    $totals.Upload   += $deltaUp
    $totalBytes = $totals.Download + $totals.Upload

    # --- Internet Strength Meter ---
    $currentSpeedMB = ($deltaDown + $deltaUp) / 1MB
    $maxWidth = 288
    $scaledWidth = [Math]::Min($currentSpeedMB * 50, $maxWidth)
    $netMeterFill.Width = $scaledWidth

    if ($currentSpeedMB -lt 0.5) { $category = "Low"; $color = "#D16969" }
    elseif ($currentSpeedMB -lt 1.1) { $category = "Medium"; $color = "#FFA500" }
    elseif ($currentSpeedMB -lt 2.2) { $category = "Strong"; $color = "#FFD700" }
	elseif ($currentSpeedMB -lt 3) { $category = "Ultra"; $color = "#4EC9B0" }
    else { $category = "Rocket"; $color = "#569CD6" }

    $netMeterFill.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $lblNetSpeed.Text = "{0:N2} MB/s - $category" -f $currentSpeedMB
    $lblNetSpeed.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)

    # --- Update labels ---
    $lblStart.Text = "Started: $($startTime.ToString('HH:mm:ss'))"
    $lblDown.Text  = "Download: {0}" -f (Format-Size $totals.Download)
    $lblDownSpeed.Text = " * Speed: {0:N2} MB/s" -f ($deltaDown / 1MB)
    $lblUp.Text    = "Upload:   {0}" -f (Format-Size $totals.Upload)
    $lblUpSpeed.Text   = " * Speed: {0:N2} MB/s" -f ($deltaUp / 1MB)
    $lblTotal.Text = "Total:    {0}" -f (Format-Size $totalBytes)
    $lblElapsed.Text = "Elapsed: {0:hh\:mm\:ss}" -f ((Get-Date) - $startTime)
})

$refresh.Start()
$window.ShowDialog() | Out-Null

############################################################################ Net Monitor Script End.