Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
# APP ROOT
if (-not $AppRoot) {
    if ($PSCommandPath) {
        $AppRoot = Split-Path -Parent $PSCommandPath
    } else {
        $AppRoot = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
    }
}

# ===================== Password File =====================
$PasswordFile = Join-Path $AppRoot "Autopilot_Data\password.json"

# ===================== REGISTRY RESTORE =====================
$RegistryPath = "HKCU:\Software\MicrosoftKeySecurity"
$RegistryValueName = "ProgramValueKey"

function Restore-PasswordFromRegistry {
    if (-not (Test-Path $PasswordFile) -and (Test-Path $RegistryPath)) {
        try {
            $jsonContent = Get-ItemPropertyValue -Path $RegistryPath -Name $RegistryValueName
            $dir = Split-Path $PasswordFile -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $jsonContent | Set-Content -Path $PasswordFile -Encoding UTF8
        } catch {
           # Write-Warning "Cannot restore password.json from Registry"
        }
    }
}

# ===================== VERIFY JSON VS REGISTRY =====================
function Verify-PasswordIntegrity {
    if (-not (Test-Path $PasswordFile)) { return }
    if (-not (Test-Path $RegistryPath)) { return }
    try {
        $jsonFile = Get-Content $PasswordFile -Raw
        $jsonRegistry = Get-ItemPropertyValue -Path $RegistryPath -Name $RegistryValueName -ErrorAction SilentlyContinue
        if (-not $jsonRegistry) { return }
        if ($jsonFile.Trim() -ne $jsonRegistry.Trim()) {
            # ако некој го изменил json → се враќа оригиналниот од registry
            $jsonRegistry | Set-Content -Path $PasswordFile -Encoding UTF8
        }
    }
    catch {
        # Write-Warning "Cannot verify the integrity of password.json."
    }
}

# ===================== EXECUTE RESTORE =====================
Restore-PasswordFromRegistry

# ===================== VERIFY INTEGRITY =====================
Verify-PasswordIntegrity

# ===================== WARNING POP UP =====================
function Show-DarkWarning {
    param(
        [string]$Message,
        [string]$Title = "Warning"
    )
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Width="520"
        Height="235"
        Background="#1E1E1E"
        Title="$Title"
        WindowStyle="None"
        AllowsTransparency="True"
        ShowInTaskbar="False">
    <Border Background="#2D2D30"
            CornerRadius="14"
            Padding="25"
            BorderBrush="#3C3C3C"
            BorderThickness="2">
        <StackPanel Width="460">
            <TextBlock Text="$Title" FontSize="24" FontWeight="Bold" Foreground="#E6E6E6" Margin="0,0,0,15" HorizontalAlignment="Center"/>
            <TextBlock Text="$Message" TextWrapping="Wrap" FontSize="16" Foreground="#DADADA" Margin="0,0,0,25" TextAlignment="Center"/>
            <Button Content="OK" Width="140" Height="42" HorizontalAlignment="Center" Foreground="White" FontWeight="SemiBold" BorderThickness="0" Cursor="Hand">
				<Button.Template>
					<ControlTemplate TargetType="Button">
						<Border x:Name="border" Background="#007ACC" CornerRadius="4">
							<ContentPresenter HorizontalAlignment="Center"  VerticalAlignment="Center"/>
						</Border>
						<ControlTemplate.Triggers>
							<Trigger Property="IsMouseOver" Value="True">
								<Setter TargetName="border" Property="Background" Value="#3399FF"/>
							</Trigger>
							<Trigger Property="IsPressed" Value="True">
								<Setter TargetName="border" Property="Background" Value="#005999"/>
							</Trigger>
						</ControlTemplate.Triggers>
					</ControlTemplate>
				</Button.Template>
			</Button>
        </StackPanel>
    </Border>
</Window>
"@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $win = [Windows.Markup.XamlReader]::Load($reader)
    $btn = $win.Content.Child.Children[2]
    $btn.Add_Click({ $win.Close() })
    $win.ShowDialog() | Out-Null
}

# ===================== LOAD PASSWORD =====================
function Load-Password {
    if (-not (Test-Path $PasswordFile)) { return $null }
    $data = Get-Content $PasswordFile | ConvertFrom-Json
    if (-not $data.Enabled) { return $null }
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = [Convert]::FromBase64String($data.Key)
    $aes.IV = [Convert]::FromBase64String($data.IV)
    $cipherBytes = [Convert]::FromBase64String($data.Password)
    $decryptor = $aes.CreateDecryptor()
    $plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
    return [System.Text.Encoding]::UTF8.GetString($plainBytes)
}

# ===================== EXECUTE PASSWORD CHECK =====================
$Password = Load-Password
if (-not $Password) { exit 0 }  # ако нема лозинка, AutoPilot стартува нормално

# ===================== WPF Window =====================
$window = New-Object System.Windows.Window
$window.Title = "AutoPilot Dashboard Password Protect"
$window.Width = 400
$window.Height = 415
$window.WindowStartupLocation = "CenterScreen"
$window.ResizeMode = "NoResize"
$window.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(30,30,30))

# ===================== XAML Resources =====================
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Window.Resources>
        <!-- Modern button style -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="#2D2D30"/>
            <Setter Property="Padding" Value="20"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="FontSize" Value="20"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderBrush" Value="#444"/>
            <Setter Property="BorderThickness" Value="2"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="5"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#3E3E42"/>
                                <Setter Property="Foreground" Value="#4EC9B0"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#565658"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
</Window>
"@

# Load XAML resources into the current window
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window.Resources.MergedDictionaries.Add([System.Windows.Markup.XamlReader]::Load($reader).Resources)

# ===================== Layout =====================
$stack = New-Object System.Windows.Controls.StackPanel
$stack.Margin = [System.Windows.Thickness]::new(20)
$stack.VerticalAlignment = "Center" 

# Заглавие
$lblTitle = New-Object System.Windows.Controls.TextBlock
$lblTitle.Text = "🔑 Enter Dashboard Password"
$lblTitle.FontSize = 22
$lblTitle.FontWeight = "Bold"
$lblTitle.Foreground = [System.Windows.Media.Brushes]::White
$lblTitle.Margin = [System.Windows.Thickness]::new(0,0,0,20)
$stack.Children.Add($lblTitle) | Out-Null

# PasswordBox
$pwdBox = New-Object System.Windows.Controls.PasswordBox
$pwdBox.Width = 250
$pwdBox.FontSize = 18
$pwdBox.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(50,50,50))
$pwdBox.Foreground = [System.Windows.Media.Brushes]::White
$pwdBox.Margin = [System.Windows.Thickness]::new(0,0,0,10)
$stack.Children.Add($pwdBox) | Out-Null

# TextBox за Show/Hide
$txtBox = New-Object System.Windows.Controls.TextBox
$txtBox.Width = 250
$txtBox.FontSize = 18
$txtBox.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(50,50,50))
$txtBox.Foreground = [System.Windows.Media.Brushes]::White
$txtBox.Margin = [System.Windows.Thickness]::new(0,0,0,10)
$txtBox.Visibility = "Collapsed"
$stack.Children.Add($txtBox) | Out-Null

# Show/Hide Label
$lblShow = New-Object System.Windows.Controls.TextBlock
$lblShow.Text = "🔑 Show Password"
$lblShow.FontSize = 17
$lblShow.FontWeight = "Bold"
$lblShow.Foreground = [System.Windows.Media.Brushes]::White
$lblShow.Cursor = "Hand"
$lblShow.HorizontalAlignment = "Center"
$lblShow.Margin = [System.Windows.Thickness]::new(0,0,0,20)
$stack.Children.Add($lblShow) | Out-Null

$lblShow.Add_MouseLeftButtonUp({
    if ($pwdBox.Visibility -eq "Visible") {
        $txtBox.Text = $pwdBox.Password
        $pwdBox.Visibility = "Collapsed"
        $txtBox.Visibility = "Visible"
        $lblShow.Text = "🔑 Hide Password"
    } else {
        $pwdBox.Password = $txtBox.Text
        $pwdBox.Visibility = "Visible"
        $txtBox.Visibility = "Collapsed"
        $lblShow.Text = "🔑 Show Password"
    }
})

# ===================== Login Protection =====================
$script:FailedAttempts = 0
$MaxAttempts = 3

$script:LockLevel = 0
$script:RemainingSeconds = 0

$LockTimer = New-Object System.Windows.Threading.DispatcherTimer
$LockTimer.Interval = [TimeSpan]::FromSeconds(1)

$LockTimer.Add_Tick({

    $script:RemainingSeconds--
    $lblTitle.Text = "🔒 Form is Locked ($script:RemainingSeconds s)"
    if ($script:RemainingSeconds -le 0) {
        $LockTimer.Stop()
        $btnOK.IsEnabled = $true
        $pwdBox.IsEnabled = $true
        $txtBox.IsEnabled = $true
        $lblTitle.Text = "Enter Dashboard Password"
        $script:FailedAttempts = 0
    }
})

# ===================== OK Button =====================
$btnOK = New-Object System.Windows.Controls.Button
$btnOK.Content = "🔓 Unlock"
$btnOK.Width = 200
$btnOK.HorizontalAlignment = "Center"
$btnOK.Margin = [System.Windows.Thickness]::new(0,10,0,0)

$btnOK.Style = $window.FindResource("ModernButton")
$stack.Children.Add($btnOK) | Out-Null

$btnOK.Add_Click({
    $entered = if ($pwdBox.Visibility -eq "Visible") { $pwdBox.Password } else { $txtBox.Text }
    if ($entered -eq $Password) {
        $script:LockLevel = 0
        $window.Tag = 0
        $window.Close()
    }
    else {
        $script:FailedAttempts++
        if ($script:FailedAttempts -ge $MaxAttempts) {
            $script:LockLevel++
            $LockTime = [math]::Pow(2,$script:LockLevel-1) * 60
            $script:RemainingSeconds = $LockTime
            Show-DarkWarning -Title "🔒 AutoPilot Dashboard Lock" -Message "Too many wrong attempts. Locked for $LockTime seconds."
            $btnOK.IsEnabled = $false
            $pwdBox.IsEnabled = $false
            $txtBox.IsEnabled = $false
            $LockTimer.Start()
        }
        else {
            $remaining = $MaxAttempts - $script:FailedAttempts
            Show-DarkWarning -Title "🔒 AutoPilot Dashboard Lock" -Message "Wrong password! Attempts left: $remaining"
        }
    }
})

# ===================== ENTER KEY LOGIN =====================
$pwdBox.Add_KeyDown({
    if ($_.Key -eq "Enter") {
        $btnOK.RaiseEvent(
            (New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))
        )
    }
})

$txtBox.Add_KeyDown({
    if ($_.Key -eq "Enter") {
        $btnOK.RaiseEvent(
            (New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))
        )
    }
})

# ===================== Logo and Text =====================
        $stackBottom = New-Object System.Windows.Controls.StackPanel
        $stackBottom.HorizontalAlignment = "Center"
        $stackBottom.VerticalAlignment = "Bottom"
        $stackBottom.Margin = [System.Windows.Thickness]::new(0,20,0,0)

        $imgLogo = New-Object System.Windows.Controls.Image
        $imgLogo.Width = 88
        $imgLogo.Height = 88
        $imgLogo.Margin = [System.Windows.Thickness]::new(0,0,0,30)
        $imgLogo.Source = [System.Windows.Media.Imaging.BitmapImage]::new((New-Object System.Uri("$AppRoot\media\autopilot.ico")))
        $stackBottom.Children.Add($imgLogo) | Out-Null

        $lblFooter = New-Object System.Windows.Controls.TextBlock
        $lblFooter.FontSize = 16
        $lblFooter.Foreground = [System.Windows.Media.Brushes]::White
        $lblFooter.HorizontalAlignment = "Center"
        $lblFooter.Text = "AutoPilot Dashboard Password Protect "
        $stackBottom.Children.Add($lblFooter) | Out-Null
        $stack.Children.Add($stackBottom) | Out-Null

$window.Content = $stack 
$window.ShowDialog() | Out-Null

# ===================== ExitCode =====================
if ($window.Tag -eq 0) { exit 0 } else { exit 1 }

######################################################################################################## End Lock.