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

# Format Size
function Format-Size {
    param([long]$bytes)
    if ($bytes -ge 1GB) { "{0:N2} GB" -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { "{0:N2} MB" -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { "{0:N2} KB" -f ($bytes / 1KB) }
    else { "$bytes B" }
}

# Elapsed Time Clock
function Format-Elapsed {
    param([datetime]$Start)
    $elapsed = (Get-Date) - $Start
    $time = "{0:hh\:mm\:ss}" -f $elapsed

    if ($elapsed.Days -gt 0) {
        $dayText = if ($elapsed.Days -eq 1) { "Day" } else { "Days" }
        return "Elapsed: $($elapsed.Days) $dayText $time"
    }
    return "Elapsed: $time"
}

# --- XAML GUI ---
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Live Network Monitor"
        Width="720" Height="670"
        Background="#1E2128"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        FontFamily="Segoe UI">
        <Window.Resources>
            <Style x:Key="ModernButton" TargetType="Button">
                <Setter Property="Foreground" Value="#E4E4E7"/>
                <Setter Property="Background">
                    <Setter.Value>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                            <GradientStop Color="#2C3039" Offset="0.0"/>
                            <GradientStop Color="#22252C" Offset="1.0"/>
                        </LinearGradientBrush>
                    </Setter.Value>
                </Setter>
                <Setter Property="Padding" Value="18,10"/>
                <Setter Property="FontFamily" Value="Segoe UI"/>
                <Setter Property="FontSize" Value="15"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
                <Setter Property="Cursor" Value="Hand"/>
                <Setter Property="BorderBrush" Value="#3B3F4A"/>
                <Setter Property="BorderThickness" Value="1"/>
                <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
                <Setter Property="Template">
                    <Setter.Value>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="border"
                                    Background="{TemplateBinding Background}"
                                    BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="11">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="5"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="border" Property="Background">
                                        <Setter.Value>
                                            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                                <GradientStop Color="#1E3A44" Offset="0.0"/>
                                                <GradientStop Color="#172D35" Offset="1.0"/>
                                            </LinearGradientBrush>
                                        </Setter.Value>
                                    </Setter>
                                    <Setter TargetName="border" Property="BorderBrush" Value="#D4D4D8"/>
                                    <Setter TargetName="border" Property="Effect">
                                        <Setter.Value>
                                            <DropShadowEffect Color="#D4D4D8" BlurRadius="14" ShadowDepth="0" Opacity="0.35"/>
                                        </Setter.Value>
                                    </Setter>
                                    <Setter Property="Foreground" Value="#FFFFFF"/>
                                </Trigger>
                                <Trigger Property="IsPressed" Value="True">
                                    <Setter TargetName="border" Property="Background" Value="#12222A"/>
                                    <Setter TargetName="border" Property="BorderBrush" Value="#E4E4E7"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Setter.Value>
                </Setter>
            </Style>
        </Window.Resources>
        <Grid Margin="26">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Grid Margin="0,0,0,22">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Image Source="$AppRoot\media\table.png" Width="48" Height="48" VerticalAlignment="Center" Margin="0,0,14,0"/>
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Text="Network Monitor" FontSize="27" FontWeight="Bold" Foreground="#F8FAFC"/>
                        <TextBlock Text="Live connection &amp; traffic analytics" FontSize="13" Foreground="#94A3B8" Margin="1,3,0,0"/>
                    </StackPanel>
                </StackPanel>
                <Border Grid.Column="1" Background="#272B34" BorderBrush="#3B3F4A" BorderThickness="1" CornerRadius="14" Padding="14,8" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Ellipse x:Name="netLight" Width="10" Height="10" Fill="Red" Margin="0,0,9,0"/>
                        <TextBlock x:Name="lblStatus" FontSize="14" FontWeight="SemiBold" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                    </StackPanel>
                </Border>
            </Grid>

            <Grid Grid.Row="1" Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Border Background="#272B34" BorderBrush="#3B3F4A" BorderThickness="1" CornerRadius="14" Padding="16,13">
                    <StackPanel>
                        <TextBlock Text="NETWORK INTERFACE" FontSize="12" FontWeight="Bold" Foreground="#94A3B8" Margin="0,0,0,7"/>
                        <TextBlock x:Name="lblInterface" FontSize="17" FontWeight="SemiBold" Foreground="#FBBF24" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>
                <Border Grid.Column="2" Background="#272B34" BorderBrush="#3B3F4A" BorderThickness="1" CornerRadius="14" Padding="16,13">
                    <StackPanel>
                        <TextBlock Text="MONITORING SINCE" FontSize="12" FontWeight="Bold" Foreground="#94A3B8" Margin="0,0,0,7"/>
                        <TextBlock x:Name="lblStart" FontSize="17" FontWeight="SemiBold" Foreground="#93C5FD"/>
                    </StackPanel>
                </Border>
            </Grid>

            <Grid Grid.Row="2" Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Border Background="#202B2B" BorderBrush="#31564F" BorderThickness="1" CornerRadius="14" Padding="17,15">
                    <StackPanel>
                        <TextBlock Text="⬇  DOWNLOAD" FontSize="13" FontWeight="Bold" Foreground="#5EEAD4" Margin="0,0,0,10"/>
                        <TextBlock x:Name="lblDown" FontSize="19" FontWeight="SemiBold" Foreground="#CCFBF1" TextWrapping="Wrap"/>
                        <TextBlock x:Name="lblDownSpeed" FontSize="14" Foreground="#99F6E4" Margin="0,7,0,0"/>
                    </StackPanel>
                </Border>
                <Border Grid.Column="2" Background="#302528" BorderBrush="#614047" BorderThickness="1" CornerRadius="14" Padding="17,15">
                    <StackPanel>
                        <TextBlock Text="⬆  UPLOAD" FontSize="13" FontWeight="Bold" Foreground="#FDA4AF" Margin="0,0,0,10"/>
                        <TextBlock x:Name="lblUp" FontSize="19" FontWeight="SemiBold" Foreground="#FFE4E6" TextWrapping="Wrap"/>
                        <TextBlock x:Name="lblUpSpeed" FontSize="14" Foreground="#FECDD3" Margin="0,7,0,0"/>
                    </StackPanel>
                </Border>
            </Grid>

            <Border Grid.Row="3" Background="#272B34" BorderBrush="#3B3F4A" BorderThickness="1" CornerRadius="14" Padding="17,14" Margin="0,0,0,12">
                <DockPanel>
                    <TextBlock Text="↕" FontSize="25" Foreground="#A5B4FC" Margin="0,0,13,0" VerticalAlignment="Center"/>
                    <StackPanel>
                        <TextBlock Text="TOTAL DATA TRANSFERRED" FontSize="12" FontWeight="Bold" Foreground="#94A3B8" Margin="0,0,0,5"/>
                        <TextBlock x:Name="lblTotal" FontSize="21" FontWeight="Bold" Foreground="#C7D2FE"/>
                    </StackPanel>
                </DockPanel>
            </Border>

            <Border Grid.Row="4" MinHeight="130" Background="#272B34" BorderBrush="#3B3F4A" BorderThickness="1" CornerRadius="14" Padding="17,15">
                <StackPanel>
                    <TextBlock Text="⚡  LIVE NETWORK ACTIVITY" FontSize="13" FontWeight="Bold" Foreground="#CBD5E1" Margin="0,0,0,15"/>
                    <DockPanel LastChildFill="False">
                        <Border x:Name="netMeter" Height="16" Width="288" CornerRadius="8" Background="#414754" DockPanel.Dock="Left" ClipToBounds="True">
                            <Rectangle x:Name="netMeterFill" Height="16" Width="0" Fill="#4EC9B0" RadiusX="8" RadiusY="8" HorizontalAlignment="Left"/>
                        </Border>
                        <TextBlock x:Name="lblNetSpeed" FontSize="16" FontWeight="SemiBold" Margin="14,0,0,0" Foreground="#F8FAFC" VerticalAlignment="Center"/>
                    </DockPanel>
                    <TextBlock Text="Current combined download and upload speed" FontSize="12" Foreground="#94A3B8" Margin="0,12,0,0"/>
                </StackPanel>
            </Border>

            <Grid Grid.Row="5" Margin="0,17,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="lblElapsed" FontSize="15" Foreground="#93C5FD" FontWeight="SemiBold" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                <Button x:Name="btnReset" Grid.Column="1" Content="↻  Reset totals" Width="145" Height="42" Style="{StaticResource ModernButton}"/>
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
        $lblElapsed.Text = Format-Elapsed $startTime
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
    $lblElapsed.Text = Format-Elapsed $startTime
})

$refresh.Start()
$window.ShowDialog() | Out-Null

############################################################################ Net Monitor Script End.