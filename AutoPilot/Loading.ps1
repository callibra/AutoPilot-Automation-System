Add-Type -AssemblyName PresentationFramework

$exePath = Join-Path $PSScriptRoot "AutoPilot.exe"
$iconPath = Join-Path $PSScriptRoot "media\autopilot.ico"

if (-not (Test-Path $exePath)) {
    [System.Windows.MessageBox]::Show("Error: File not found at $exePath","Loader Error",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error)
    exit
}

# =================== Minimal WPF Loader ===================
$XAML = @"
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
            <TextBlock Name="txtStatus" FontFamily="Segoe UI Semibold" FontSize="18" Foreground="#E4E4E7" HorizontalAlignment="Center" Text="🔰 AutoPilot Dashboard Loading..." />
        </StackPanel>
    </Border>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($XAML))
$window = [Windows.Markup.XamlReader]::Load($reader)

# Show loader for 3 seconds
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({
    $timer.Stop()
    $window.Close()
})
$timer.Start()
$window.ShowDialog()

# Start EXE
Start-Process -FilePath $exePath -WindowStyle Normal

########################################################################################## End Loading.


