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
        Height="180" Width="300"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Topmost="True"
        Background="#1E1E1E"
        WindowStyle="None"
        AllowsTransparency="True">
    <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
        <!-- PNG Logo -->
        <Image Name="imgLogo"
               Width="64" Height="64"
               Margin="0,0,0,10"
               Source="$iconPath" />
        <!-- Modern Text -->
        <TextBlock Name="txtStatus"
                   FontFamily="Segoe UI Semibold"
                   FontSize="18"
                   Foreground="White"
                   HorizontalAlignment="Center"
                   Text="AutoPilot Dashboard Loading..." />
    </StackPanel>
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


