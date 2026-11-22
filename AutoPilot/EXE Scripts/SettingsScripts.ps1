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

# ====================== Scripts Settings GUI ======================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ================= UNSAVED CHANGES =================
$script:HasUnsavedChanges = $false
function Mark-Dirty { $script:HasUnsavedChanges = $true }

# ================= COLORS & FONTS =================
$BG = [Drawing.Color]::FromArgb(21,22,26)
$SECTION = [Drawing.Color]::FromArgb(29,29,36)
$COLOR_TEXT = [Drawing.Color]::White

$ACCENTS = @{
    docker    = [Drawing.Color]::FromArgb(10,132,255)
    swap      = [Drawing.Color]::FromArgb(54,189,138)
	network   = [Drawing.Color]::FromArgb(255,159,10)
    demo1     = [Drawing.Color]::FromArgb(230,230,71)
	demo2     = [Drawing.Color]::FromArgb(100,210,255)
    demo3     = [Drawing.Color]::FromArgb(191,90,242)
}

$FONT_SECTION = New-Object Drawing.Font("Segoe UI Emoji",14,[Drawing.FontStyle]::Bold)
$FONT_LABEL   = New-Object Drawing.Font("Segoe UI Emoji",12)
$FONT_ENTRY   = New-Object Drawing.Font("Segoe UI Emoji",12,[Drawing.FontStyle]::Bold)
$FONT_BUTTON  = New-Object Drawing.Font("Segoe UI Emoji",12,[Drawing.FontStyle]::Bold)

# ================= ROOT FORM =================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Scripts Settings"
$form.WindowState = "Maximized"
$form.Size = New-Object System.Drawing.Size(1280, 800)
$form.StartPosition = "CenterScreen"
$form.BackColor = $BG

# ================= LOAD ICON =================
$iconPath = "$AppRoot\media\scripts_settings.ico"
if (Test-Path $iconPath) {
    $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
}

# ================= JSON =================
$jsonPath = "$AppRoot\JSON\settings_scripts.json"
$defaultJsonPath = "$AppRoot\JSON\settings_scripts_default.json"

# Create JSON folder if missing
if (-not (Test-Path (Split-Path $jsonPath))) { New-Item -ItemType Directory -Path (Split-Path $jsonPath) | Out-Null }

# Ensure JSON file exists and is valid
if (-not (Test-Path $jsonPath)) {
    $initialConfig = @{
        DockerPath=""; DockerCliPath=""; Containers=@()
        DockerDesktopPath=""; SwapFolderPath=""
    }
    $initialConfig | ConvertTo-Json -Depth 5 | Set-Content $jsonPath -Encoding UTF8
}

# Load JSON safely
try {
    $config = Get-Content $jsonPath -Raw | ConvertFrom-Json
} catch {
    [Windows.Forms.MessageBox]::Show("Invalid JSON at $jsonPath.`nResetting to default.","Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    $config = @{
        DockerPath=""; DockerCliPath=""; Containers=@()
        DockerDesktopPath=""; SwapFolderPath=""
    }
}

# ================= LOAD DEFAULT PROFILES =================
$defaultProfiles = @()

if (Test-Path $defaultJsonPath) {
    try {
        $defaultProfiles = Get-Content $defaultJsonPath -Raw | ConvertFrom-Json
    } catch {
        [Windows.Forms.MessageBox]::Show("Invalid default JSON format!","Error")
    }
}

# Ensure all required properties exist
$neededProps = "DockerPath","DockerCliPath","Containers","DockerDesktopPath","SwapFolderPath"
foreach ($p in $neededProps) {
    if (-not $config.PSObject.Properties.Match($p)) {
        $defaultValue = if ($p -eq "Containers") { @() } else { "" }
        $config | Add-Member -MemberType NoteProperty -Name $p -Value $defaultValue
    }
}

# ================= HELPERS =================
function Section($title, $accent, $textColor=[Drawing.Color]::White) {
    $p = New-Object Windows.Forms.Panel
    $p.BackColor = $SECTION
    $p.BorderStyle = 'None'
    $p.Width = 550
    $p.Height = 488
    # tinted title band (accent blended 22% into the card color)
    $tint = [Drawing.Color]::FromArgb(
        [int]($SECTION.R + ($accent.R - $SECTION.R) * 0.22),
        [int]($SECTION.G + ($accent.G - $SECTION.G) * 0.22),
        [int]($SECTION.B + ($accent.B - $SECTION.B) * 0.22))
    $hdr = New-Object Windows.Forms.Panel
    $hdr.Height = 44
    $hdr.Dock = 'Top'
    $hdr.BackColor = $tint
    $p.Controls.Add($hdr)
    # solid accent stripe on the left edge (added after the band so it spans the full height)
    $stripe = New-Object Windows.Forms.Panel
    $stripe.Width = 6
    $stripe.Dock = 'Left'
    $stripe.BackColor = $accent
    $p.Controls.Add($stripe)
    $l = New-Object Windows.Forms.Label
    $l.Text = $title
    $l.Font = $FONT_SECTION
    $l.ForeColor = $textColor   # <--- Овде задаваме различна боја
    $l.BackColor = $tint
    $l.AutoSize = $true
    $l.Top = 9
    $l.Left = 12
    $hdr.Controls.Add($l)
    return $p
}

function LabelText($parent,$text,$top) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Font = $FONT_LABEL; $l.ForeColor = $COLOR_TEXT
    $l.AutoSize = $true; $l.Left = 10; $l.Top = $top
    $parent.Controls.Add($l)
}

function AddEmoji($parent, $emoji, $control) {
    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = $emoji
    $lbl.AutoSize = $true
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 14, [System.Drawing.FontStyle]::Regular)
    $lbl.ForeColor = [System.Drawing.Color]::White
    $lbl.Left = $control.Right + 8
    $lbl.Top = $control.Top - 1
    $parent.Controls.Add($lbl)
}

function TextBoxRow($parent,$label,$value,$top) {
    LabelText $parent $label $top
    $t = New-Object Windows.Forms.TextBox
    $t.Text = $value; $t.Left = 200; $t.Top = $top-3; $t.Width = 300
    $t.Font = $FONT_ENTRY; $t.BackColor = $SECTION; $t.ForeColor = $COLOR_TEXT
    $t.Add_TextChanged({Mark-Dirty})
    $parent.Controls.Add($t)
    return $t
}

function AddFooterLine($panel, $text) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Font = New-Object Drawing.Font("Segoe UI",9)
    $l.ForeColor = [Drawing.Color]::FromArgb(48,209,88)
    $l.AutoSize = $true; $l.MaximumSize = New-Object Drawing.Size(($panel.Width - 20), 0)
    $l.Left = 10; $l.Top = $panel.Height - $l.PreferredHeight - 10
    $panel.Add_Resize({$l.MaximumSize = New-Object Drawing.Size(($panel.Width - 20), 0); $l.Top = $panel.Height - $l.PreferredHeight - 10})
    $panel.Controls.Add($l)
}

# ================= MODERN BUTTON STYLE =================
$script:BTN_RADIUS = 8
function Set-ModernButton($btn) {
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 0
    $btn.UseVisualStyleBackColor = $false
    $btn.Cursor = [Windows.Forms.Cursors]::Hand
    # smooth (anti-aliased) rounded corners: paint the 4 corners in the parent color
    $btn.Add_Paint({
        $w = $this.Width; $h = $this.Height
        if ($w -le 2 -or $h -le 2) { return }
        $r = [Math]::Min($script:BTN_RADIUS, [Math]::Floor([Math]::Min($w,$h) / 2))
        $d = $r * 2
        $bg = $SECTION
        if ($this.Parent) { $bg = $this.Parent.BackColor }
        $g = $_.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.FillMode = [System.Drawing.Drawing2D.FillMode]::Alternate
        $path.AddRectangle((New-Object System.Drawing.Rectangle(-1, -1, ($w + 2), ($h + 2))))
        $path.StartFigure()
        $path.AddArc(0, 0, $d, $d, 180, 90)
        $path.AddArc($w - $d, 0, $d, $d, 270, 90)
        $path.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
        $path.AddArc(0, $h - $d, $d, $d, 90, 90)
        $path.CloseFigure()
        $brush = New-Object System.Drawing.SolidBrush($bg)
        $g.FillPath($brush, $path)
        $brush.Dispose(); $path.Dispose()
    })
}

# ================= LAYOUT =================
$scrollPanel = New-Object Windows.Forms.Panel
$scrollPanel.Dock = 'Fill'
$scrollPanel.AutoScroll = $true
$scrollPanel.BackColor = $BG
$form.Controls.Add($scrollPanel)

# ================= GRID =================
$grid = New-Object Windows.Forms.TableLayoutPanel
$grid.AutoSize = $true
$grid.AutoSizeMode = 'GrowAndShrink'
$grid.ColumnCount = 3
$grid.RowCount = 3
$grid.ColumnStyles.Clear()
$grid.RowStyles.Clear()
[void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::AutoSize)))
[void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::AutoSize)))
[void]$grid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
[void]$grid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
[void]$grid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
$grid.CellBorderStyle = 'None'
$grid.Left = 8
$grid.Top = 12
$grid.BackColor = $BG
$grid.Margin = New-Object Windows.Forms.Padding(0)
$grid.Padding = New-Object Windows.Forms.Padding(0)
$scrollPanel.Controls.Add($grid)

# ================= HEADER BAR =================
$headerBar = New-Object Windows.Forms.Panel
$headerBar.Dock = 'Top'
$headerBar.Height = 76
$headerBar.BackColor = [Drawing.Color]::FromArgb(31,31,31)
# gradient background: charcoal (left) -> deep mint (right)
$headerBar.Add_Paint({
    $rect = $this.ClientRectangle
    if ($rect.Width -le 0 -or $rect.Height -le 0) { return }
    $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [Drawing.Color]::FromArgb(31,31,31),
        [Drawing.Color]::FromArgb(18,92,72),
        [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $_.Graphics.FillRectangle($gb, $rect)
    $gb.Dispose()
})
$headerBar.Add_Resize({ $this.Invalidate() })
$headerAccent = New-Object Windows.Forms.Panel
$headerAccent.Dock = 'Left'
$headerAccent.Width = 6
$headerAccent.BackColor = [Drawing.Color]::FromArgb(78, 230, 164)
$headerBar.Controls.Add($headerAccent)

# ================= HEADER LOGO =================
$titleLeft = 24
$subtitleLeft = 26
$headerLogoIcon = $null
try {
    if (Test-Path $iconPath) {
        $headerLogoIcon = New-Object System.Drawing.Icon($iconPath)
    }
    elseif ($form.Icon) {
        $headerLogoIcon = $form.Icon.Clone()
    }
    if ($headerLogoIcon) {
        $headerLogo = New-Object Windows.Forms.PictureBox
        $headerLogo.Size = New-Object Drawing.Size(48,48)
        $headerLogo.Location = New-Object Drawing.Point(20,14)
        $headerLogo.BackColor = [Drawing.Color]::Transparent
        $headerLogo.Tag = $headerLogoIcon
        $headerLogo.Add_Paint({
            try {
                if ($this.Tag) {
                    $_.Graphics.DrawIcon($this.Tag, $this.ClientRectangle)
                }
            } catch {}
        })
        $headerLogo.Add_Disposed({
            if ($this.Tag) {
                $this.Tag.Dispose()
                $this.Tag = $null
            }
        })
        $headerBar.Controls.Add($headerLogo)
        $titleLeft = 82
        $subtitleLeft = 84
    }
}
catch {
    if ($headerLogoIcon) { $headerLogoIcon.Dispose() }
    $headerLogoIcon = $null
}

# ================= HEADER TITLE =================
$headerTitle = New-Object Windows.Forms.Label
$headerTitle.Text = 'Scripts Settings Panel'
$headerTitle.Font = New-Object Drawing.Font('Segoe UI',16,[Drawing.FontStyle]::Bold)
$headerTitle.ForeColor = [Drawing.Color]::White
$headerTitle.BackColor = [Drawing.Color]::Transparent
$headerTitle.AutoSize = $true
$headerTitle.Location = New-Object Drawing.Point($titleLeft,11)
$headerBar.Controls.Add($headerTitle)

# ================= HEADER SUBTITLE =================
$headerSubtitle = New-Object Windows.Forms.Label
$headerSubtitle.Text = 'Docker Settings  /  Container  /  Network'
$headerSubtitle.Font = New-Object Drawing.Font('Segoe UI',8.5)
$headerSubtitle.ForeColor = [Drawing.Color]::FromArgb(177,190,211)
$headerSubtitle.BackColor = [Drawing.Color]::Transparent
$headerSubtitle.AutoSize = $true
$headerSubtitle.Location = New-Object Drawing.Point($subtitleLeft,43)
$headerBar.Controls.Add($headerSubtitle)
$form.Controls.Add($headerBar)

# ================= CREATE SECTIONS =================
$dockerCore   = Section "⚙️ Docker Script"      $ACCENTS.docker
$swap         = Section "⚛️ SetDocker Script"   $ACCENTS.swap
$network      = Section "🌐 Network Script"     $ACCENTS.network
$demo1        = Section "🌍 Net Traffic Script" $ACCENTS.demo1
$demo2        = Section "🧹 Cleaner Script"     $ACCENTS.demo2
$demo3        = Section "⚡ Power Plan Script"  $ACCENTS.demo3

$grid.Controls.Add($dockerCore, 0,0)
$grid.Controls.Add($swap, 1,0)
$grid.Controls.Add($network, 2,0)
$grid.Controls.Add($demo1, 0,1)
$grid.Controls.Add($demo2, 1,1)
$grid.Controls.Add($demo3, 2,1)

# ================= ALIAS ================
$docker = $dockerCore

# ================= DOCKER SECTION =================
$y=62; $spacing=40
$tDockerPath = TextBoxRow $docker "📁 Docker Path:" $config.DockerPath $y
AddEmoji $docker "📝" $tDockerPath
$y += $spacing
$tDockerCli = TextBoxRow $docker "📁 Docker CLI Path:" $config.DockerCliPath $y
AddEmoji $docker "📝" $tDockerCli
$y += $spacing
$tContainers = TextBoxRow $docker "⚙️ Containers:" ($config.Containers -join ",") $y
AddEmoji $docker "📝" $tContainers
$y += $spacing
AddFooterLine $docker "● Set Docker executable paths and container names for Docker Script.
● If you install Docker using its default path, then use the *DEFAULT BUTTON*.
● If you are using a custom path, meaning you installed it on a different drive, then use the *DEFAULT CUSTOM BATTON* and replace it with your drive and folder where Docker is located.
● This is used either to install Docker on your custom path or to use the default path.
● If you are using the default Docker path, then don’t change anything in the label. But if you are using your custom path, then just replace the drive *example:(E:, C:, D:) and the folder if you installed Docker in a different folder, *example: E:\Miner or E:\MyDockerFolder.
● The rest of the label stays the same; dont change it."

# ================= SET DOCKER SECTION =================
$y=62
$tDockerDesktop = TextBoxRow $swap "📁 Docker Desktop Path:" $config.DockerDesktopPath $y
AddEmoji $swap "📝" $tDockerDesktop
$y += $spacing
$tSwapFolder = TextBoxRow $swap "📁 Swap Folder Path:" $config.SwapFolderPath $y
AddEmoji $swap "📝" $tSwapFolder
$y += $spacing
AddFooterLine $swap "● Set Docker Desktop and Swap folder paths.
● If you install Docker using its default path, then use the *DEFAULT BUTTON*.
● If you are using a custom path, meaning you installed it on a different drive, then use the *DEFAULT CUSTOM BATTON* and replace it with your drive and folder where Docker is located.
● This is used to set Docker to use your custom hardware resources and either use your custom path for it or keep its default path.
● If you are using the default Docker path, then don’t change anything in the label. But if you are using your custom path, then just replace the drive *example:(E:, C:, D:) and the folder if you installed Docker in a different folder, *example: E:\Miner or E:\MyDockerFolder.
● The rest of the label stays the same; dont change it.
● In the line *Swap Folder Path* change the %USERNAME% with your custom pc name example C:\Users\ASUS\AppData\Local\Docker\wsl\data or Your custom path example like this E:\Miner\WSLSwap."

# ================= NETWORK SECTION =================
$y=62
$spacing = 60  # larger spacing for visual clarity
# --- Wi-Fi Names ---
$txtWifi1 = TextBoxRow $network "📶 WiFi 1 SSID:" $config.wifi1 $y
AddEmoji $network "📝" $txtWifi1
$y += $spacing
$txtWifi2 = TextBoxRow $network "📶 WiFi 2 SSID:" $config.wifi2 $y
AddEmoji $network "📝" $txtWifi2
$y += $spacing
# Function to create a modern spinner (NumericUpDown)
function New-TimeSpinner($parent, $left, $top, $value, $max) {
    $nud = New-Object Windows.Forms.NumericUpDown
    $nud.Left = $left
    $nud.Top = $top
    $nud.Width = 70
    $nud.Height = 35
    $nud.Font = New-Object Drawing.Font("Segoe UI",14,[Drawing.FontStyle]::Bold)
    $nud.BackColor = [Drawing.Color]::FromArgb(30,30,30)   # dark background
    $nud.ForeColor = [Drawing.Color]::White                # white numbers
    $nud.Minimum = 0
    $nud.Maximum = $max
    $nud.ReadOnly = $true            # no manual typing
    $nud.InterceptArrowKeys = $true  # arrows only
    $parent.Controls.Add($nud)
    return $nud
}

# ================= Tenda → Beni Time =================
$lblTendaToBeni = New-Object Windows.Forms.Label
$lblTendaToBeni.Text = "🔄 WiFi 1 switch to WiFi 2 (Hours:Min):"
$lblTendaToBeni.Font = $FONT_LABEL
$lblTendaToBeni.ForeColor = [Drawing.Color]::FromArgb(255,255,255)
$lblTendaToBeni.AutoSize = $true
$lblTendaToBeni.Left = 10
$lblTendaToBeni.Top = $y
$network.Controls.Add($lblTendaToBeni)

# ================= Tenda → Beni Time =================
$tHour = $null
$tMin  = $null
if ($config.TendaToBeniTime -match '^(\d{2}):(\d{2})$') {
    $tHour = [int]$matches[1]
    $tMin  = [int]$matches[2]
}
$tHourValue = if ($tHour -ne $null) { $tHour } else { 0 }
$tMinValue  = if ($tMin  -ne $null) { $tMin  } else { 0 }
# зачувуваме оригинални вредности
$originalTendaHour = $tHourValue
$originalTendaMin  = $tMinValue

$nudTendaHour = New-TimeSpinner $network 350 $y $tHourValue 23
$nudTendaMin  = New-TimeSpinner $network 430 $y $tMinValue 59

# ➜ emoji next to MIN spinner (WiFi 1 row)
$lblTendaEmoji = New-Object Windows.Forms.Label
$lblTendaEmoji.Text = "🕒"
$lblTendaEmoji.AutoSize = $true
$lblTendaEmoji.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 12)
$lblTendaEmoji.ForeColor = [Drawing.Color]::White
$lblTendaEmoji.Left = $nudTendaMin.Left + 78
$lblTendaEmoji.Top  = $y + 8
$network.Controls.Add($lblTendaEmoji)

# ⚡ Mark as dirty only if changed
$nudTendaHour.Add_ValueChanged({
    if ([int]$nudTendaHour.Value -ne $originalTendaHour -or [int]$nudTendaMin.Value -ne $originalTendaMin) { 
        Mark-Dirty 
    } else {
        $script:HasUnsavedChanges = $false
    }
})
$nudTendaMin.Add_ValueChanged({
    if ([int]$nudTendaHour.Value -ne $originalTendaHour -or [int]$nudTendaMin.Value -ne $originalTendaMin) { 
        Mark-Dirty 
    } else {
        $script:HasUnsavedChanges = $false
    }
})
# Форматираме Text за да прикажува секогаш две цифри
$nudTendaHour.Text = if ($tHour -ne $null) { "{0:D2}" -f $tHour } else { "" }
$nudTendaMin.Text  = if ($tMin  -ne $null) { "{0:D2}" -f $tMin  } else { "" }
$y += $spacing

# ================= Beni → Tenda Time =================
$lblBeniToTenda = New-Object Windows.Forms.Label
$lblBeniToTenda.Text = "🔄 WiFi 2 switch to WiFi 1 (Hours:Min):"
$lblBeniToTenda.Font = $FONT_LABEL
$lblBeniToTenda.ForeColor = [Drawing.Color]::FromArgb(255,255,255)
$lblBeniToTenda.AutoSize = $true
$lblBeniToTenda.Left = 10
$lblBeniToTenda.Top = $y
$network.Controls.Add($lblBeniToTenda)

$bHour = $null
$bMin  = $null
if ($config.BeniToTendaTime -match '^(\d{2}):(\d{2})$') {
    $bHour = [int]$matches[1]
    $bMin  = [int]$matches[2]
}
$bHourValue = if ($bHour -ne $null) { $bHour } else { 0 }
$bMinValue  = if ($bMin  -ne $null) { $bMin  } else { 0 }
# зачувуваме оригинални вредности
$originalBeniHour = $bHourValue
$originalBeniMin  = $bMinValue

$nudBeniHour = New-TimeSpinner $network 350 $y $bHourValue 23
$nudBeniMin  = New-TimeSpinner $network 430 $y $bMinValue 59

# ➜ emoji next to MIN spinner (WiFi 2 row)
$lblBeniEmoji = New-Object Windows.Forms.Label
$lblBeniEmoji.Text = "🕒"
$lblBeniEmoji.AutoSize = $true
$lblBeniEmoji.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 12)
$lblBeniEmoji.ForeColor = [Drawing.Color]::White
$lblBeniEmoji.Left = $nudBeniMin.Left + 78
$lblBeniEmoji.Top  = $y + 8
$network.Controls.Add($lblBeniEmoji)

# ⚡ Mark as dirty only if changed
$nudBeniHour.Add_ValueChanged({
    if ([int]$nudBeniHour.Value -ne $originalBeniHour -or [int]$nudBeniMin.Value -ne $originalBeniMin) { 
        Mark-Dirty 
    } else {
        $script:HasUnsavedChanges = $false
    }
})
$nudBeniMin.Add_ValueChanged({
    if ([int]$nudBeniHour.Value -ne $originalBeniHour -or [int]$nudBeniMin.Value -ne $originalBeniMin) { 
        Mark-Dirty 
    } else {
        $script:HasUnsavedChanges = $false
    }
})
# Форматираме Text за да прикажува секогаш две цифри
$nudBeniHour.Text = if ($bHour -ne $null) { "{0:D2}" -f $bHour } else { "" }
$nudBeniMin.Text  = if ($bMin  -ne $null) { "{0:D2}" -f $bMin  } else { "" }
$y += $spacing
# --- Footer line ---
AddFooterLine $network "● Edit Wi-Fi SSID and Times using the arrow spinners.
● Use this SETTINGS to switch from one Wi-Fi network to another at a specific time by creating a task FOR automatically switch or manually from a Telegram Bot Chat message.
● Use the DEFAULT CUSTOM Batton as an example of how this should be configured.
● If the correct Wi-Fi SSID and the configured time for the switch are not entered, this will not work without these values.
● You can create an unlimited number of tasks that can be deleted from Network Script or from Telegram Bot Chat messages.
● This TASK are valid and executed every day at the same time.."

# ================= Demo 1 =================
$lblDemo1 = New-Object Windows.Forms.Label
$lblDemo1.Text = " - No SETTINGS for Editing for Net Traffic Script."
$lblDemo1.Font = $FONT_LABEL
$lblDemo1.ForeColor = [Drawing.Color]::White
$lblDemo1.AutoSize = $true
$lblDemo1.Left = 10
$lblDemo1.Top = 62
$demo1.Controls.Add($lblDemo1)
# --- Image ---
$picDemo1 = New-Object Windows.Forms.PictureBox
$picDemo1.Image = [Drawing.Image]::FromFile("$AppRoot\media\scripts_settings.ico")  
$picDemo1.SizeMode = "StretchImage"
$picDemo1.Width = 200     # custom width
$picDemo1.Height = 200   # custom height
$picDemo1.Left = ($demo1.Width - $picDemo1.Width) / 2
$picDemo1.Top = 120
$demo1.Controls.Add($picDemo1)
AddFooterLine $demo1 "● No SETTINGS for Editing for Net Traffic Script."

# ================= Demo 2 =================
$lblDemo2 = New-Object Windows.Forms.Label
$lblDemo2.Text = " - No SETTINGS for Editing for Cleaner Script."
$lblDemo2.Font = $FONT_LABEL
$lblDemo2.ForeColor = [Drawing.Color]::White
$lblDemo2.AutoSize = $true
$lblDemo2.Left = 10
$lblDemo2.Top = 62
$demo2.Controls.Add($lblDemo2)
# --- Image ---
$picDemo2 = New-Object Windows.Forms.PictureBox
$picDemo2.Image = [Drawing.Image]::FromFile("$AppRoot\media\scripts_settings.ico")
$picDemo2.SizeMode = "StretchImage"
$picDemo2.Width = 200
$picDemo2.Height = 200
$picDemo2.Left = ($demo2.Width - $picDemo2.Width) / 2
$picDemo2.Top = 120
$demo2.Controls.Add($picDemo2)
AddFooterLine $demo2 "● No SETTINGS for Editing for Cleaner Script."

# ================= Demo 3 =================
$lblDemo3 = New-Object Windows.Forms.Label
$lblDemo3.Text = " - No SETTINGS for Editing for Power Plan Script."
$lblDemo3.Font = $FONT_LABEL
$lblDemo3.ForeColor = [Drawing.Color]::White
$lblDemo3.AutoSize = $true
$lblDemo3.Left = 10
$lblDemo3.Top = 62
$demo3.Controls.Add($lblDemo3)
$picDemo2 = New-Object Windows.Forms.PictureBox
# --- Image ---
$picDemo3 = New-Object Windows.Forms.PictureBox
$picDemo3.Image = [Drawing.Image]::FromFile("$AppRoot\media\scripts_settings.ico")
$picDemo3.SizeMode = "StretchImage"
$picDemo3.Width = 200
$picDemo3.Height = 200
$picDemo3.Left = ($demo3.Width - $picDemo3.Width) / 2
$picDemo3.Top = 120
$demo3.Controls.Add($picDemo3)
AddFooterLine $demo3 "● No SETTINGS for Editing for Power Plan Script."

# ================= BOTTOM BUTTON BAR =================
$buttonBar = New-Object Windows.Forms.Panel
$buttonBar.Dock = 'Bottom'
$buttonBar.Height = 72
$buttonBar.BackColor = [Drawing.Color]::FromArgb(24,24,24)
$barLine = New-Object Windows.Forms.Panel
$barLine.Dock = 'Top'; $barLine.Height = 1
$barLine.BackColor = [Drawing.Color]::FromArgb(55,55,55)
$buttonBar.Controls.Add($barLine)
$form.Controls.Add($buttonBar)   # added after $scrollPanel so the scroll area fills the rest

# ================= SAVE BUTTON =================
$save = New-Object Windows.Forms.Button
$save.Text = "💾 Save Configuration"
$save.Font = $FONT_BUTTON
$save.Width = 200
$save.Height = 44
$save.BackColor = $ACCENTS.docker
$save.ForeColor = [Drawing.Color]::White
Set-ModernButton $save
$buttonBar.Controls.Add($save)

$save.Add_Click({
    $config.DockerPath = ($tDockerPath.Text -replace '\r|\n','').Trim()
	$config.DockerCliPath = ($tDockerCli.Text -replace '\r|\n','').Trim()
	$config.Containers = @(
		(($tContainers.Text -replace '\r|\n','').Trim()).Split(",") |
		ForEach-Object { $_.Trim() } |
		Where-Object { $_ -ne "" }
	)
	$config.DockerDesktopPath = ($tDockerDesktop.Text -replace '\r|\n','').Trim()
	$config.SwapFolderPath = ($tSwapFolder.Text -replace '\r|\n','').Trim()
	# --- Wi-Fi / Task Settings ---
	$config.wifi1 = ($txtWifi1.Text -replace '\r|\n','').Trim()
    $config.wifi2 = ($txtWifi2.Text -replace '\r|\n','').Trim()
	# --- Tenda → Beni time ---
	if ($nudTendaHour.Text -eq "" -and $nudTendaMin.Text -eq "") {
		$config.TendaToBeniTime = $null
	} else {
		$config.TendaToBeniTime = "{0:D2}:{1:D2}" -f `
			([int]$nudTendaHour.Value), ([int]$nudTendaMin.Value)
	}
	# --- Beni → Tenda time ---
	if ($nudBeniHour.Text -eq "" -and $nudBeniMin.Text -eq "") {
		$config.BeniToTendaTime = $null
	} else {
		$config.BeniToTendaTime = "{0:D2}:{1:D2}" -f `
			([int]$nudBeniHour.Value), ([int]$nudBeniMin.Value)
	}
    $config | ConvertTo-Json -Depth 5 | Set-Content $jsonPath -Encoding UTF8
    [Windows.Forms.MessageBox]::Show("✔️ Configuration saved successfully!")
    $script:HasUnsavedChanges = $false
})

# ================= DEFAULT BUTTON =================
$defaultBtn = New-Object Windows.Forms.Button
$defaultBtn.Text="☑️ Default"
$defaultBtn.Font=$FONT_BUTTON
$defaultBtn.Width=200
$defaultBtn.Height=44
$defaultBtn.BackColor=[Drawing.Color]::FromArgb(48,209,88)
$defaultBtn.ForeColor=[Drawing.Color]::White
Set-ModernButton $defaultBtn
$buttonBar.Controls.Add($defaultBtn)

$defaultBtn.Add_Click({
    if ($defaultProfiles.Count -lt 1) {
        [Windows.Forms.MessageBox]::Show("Factory default not found!","⚠️ Error")
        return
    }
    $def = $defaultProfiles[0]
    $tDockerPath.Text     = $def.DockerPath
    $tDockerCli.Text      = $def.DockerCliPath
    $tContainers.Text     = ($def.Containers -join ",")
    $tDockerDesktop.Text  = $def.DockerDesktopPath
    $tSwapFolder.Text     = $def.SwapFolderPath
	# Wi-Fi (Factory = blank)
    $txtWifi1.Text = $def.wifi1
    $txtWifi2.Text = $def.wifi2
    # Time spinners (Tenda → Beni)
    if ($def.TendaToBeniTime -and $def.TendaToBeniTime -match '(\d{2}):(\d{2})') {
        $nudTendaHour.Value = [int]$matches[1]
        $nudTendaMin.Value  = [int]$matches[2]
        $nudTendaHour.Text  = [int]$matches[1]   # ensure text matches value
        $nudTendaMin.Text   = [int]$matches[2]
    } else {
        $nudTendaHour.Value = 0
        $nudTendaMin.Value  = 0
        $nudTendaHour.Text  = ""   # show empty
        $nudTendaMin.Text   = ""
    }
    # Time spinners (Beni → Tenda)
    if ($def.BeniToTendaTime -and $def.BeniToTendaTime -match '(\d{2}):(\d{2})') {
        $nudBeniHour.Value = [int]$matches[1]
        $nudBeniMin.Value  = [int]$matches[2]
        $nudBeniHour.Text  = [int]$matches[1]
        $nudBeniMin.Text   = [int]$matches[2]
    } else {
        $nudBeniHour.Value = 0
        $nudBeniMin.Value  = 0
        $nudBeniHour.Text  = ""   # show empty
        $nudBeniMin.Text   = ""
    }
    $save.PerformClick()
    $script:HasUnsavedChanges = $false
})

# ================= DEFAULT CUSTOM BUTTON =================
$customBtn = New-Object Windows.Forms.Button
$customBtn.Text="✔️ Default Custom"
$customBtn.Font=$FONT_BUTTON
$customBtn.Width=200
$customBtn.Height=44
$customBtn.BackColor=[Drawing.Color]::FromArgb(182,42,184)
$customBtn.ForeColor=[Drawing.Color]::White
Set-ModernButton $customBtn
$buttonBar.Controls.Add($customBtn)

$customBtn.Add_Click({
    if ($defaultProfiles.Count -lt 2) {
        [Windows.Forms.MessageBox]::Show("Custom default not found!","⚠️ Error")
        return
    }
    $def = $defaultProfiles[1]
    $tDockerPath.Text     = $def.DockerPath
    $tDockerCli.Text      = $def.DockerCliPath
    $tContainers.Text     = ($def.Containers -join ",")
    $tDockerDesktop.Text  = $def.DockerDesktopPath
    $tSwapFolder.Text     = $def.SwapFolderPath
	# --- Wi-Fi (од JSON)
    $txtWifi1.Text = $def.wifi1
    $txtWifi2.Text = $def.wifi2
    # --- Time spinners (од JSON)
    if ($def.TendaToBeniTime -match '(\d{2}):(\d{2})') {
        $nudTendaHour.Value = [int]$matches[1]
        $nudTendaMin.Value  = [int]$matches[2]
    }
    if ($def.BeniToTendaTime -match '(\d{2}):(\d{2})') {
        $nudBeniHour.Value = [int]$matches[1]
        $nudBeniMin.Value  = [int]$matches[2]
    }
    $save.PerformClick()
    $script:HasUnsavedChanges = $false
})

# ================= RESET BUTTON =================
$resetBtn = New-Object Windows.Forms.Button
$resetBtn.Text = "⚠️ Reset"
$resetBtn.Font=$FONT_BUTTON
$resetBtn.Width=200
$resetBtn.Height=44
$resetBtn.BackColor=[Drawing.Color]::FromArgb(255,69,58)
$resetBtn.ForeColor=[Drawing.Color]::White
Set-ModernButton $resetBtn
$buttonBar.Controls.Add($resetBtn)

$resetBtn.Add_Click({
    if ([Windows.Forms.MessageBox]::Show(
        "This will RESET all settings and SAVE immediately.`nAre you sure?",
        "Confirm Reset",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning
    ) -ne [Windows.Forms.DialogResult]::Yes) { return }

    $tDockerPath.Text="Your Docker Path"; $tDockerCli.Text="Your Docker Cli"; $tContainers.Text="Your Docker Containers"
    $tDockerDesktop.Text="Your Docker Desktop Path"; $tSwapFolder.Text="Your Docker Swap Folder Path"
	# Clear Wi-Fi
    $txtWifi1.Text="SSID 1"
    $txtWifi2.Text="SSID 2"
    # Clear Time spinners (show empty)
    $nudTendaHour.Value=0
    $nudTendaMin.Value=0
    $nudTendaHour.Text=""
    $nudTendaMin.Text=""
	
    $nudBeniHour.Value=0
    $nudBeniMin.Value=0
    $nudBeniHour.Text=""
    $nudBeniMin.Text=""
    $save.PerformClick()
    $script:HasUnsavedChanges = $false
})

# ================= RECOVERY (BACKUP / RESTORE / DELETE) =================
# Backups are plain copies of JSON\settings_scripts.json stored in JSON\Backups_Scripts\<name>.json
$backupDir = "$AppRoot\JSON\Backups_Scripts"
$script:RecDlg  = $null
$script:RecList = $null
$script:RecTip  = $null
$FONT_POPUP = New-Object Drawing.Font("Segoe UI Emoji",11,[Drawing.FontStyle]::Bold)

function Get-BackupFiles {
    if (-not (Test-Path -LiteralPath $backupDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $backupDir -Filter *.json -File | Sort-Object CreationTimeUtc, Name)
}

function Show-Msg($text, $caption = "Recovery", $buttons = 'OK', $icon = 'Information') {
    $owner = $form
    if ($script:RecDlg -and -not $script:RecDlg.IsDisposed) { $owner = $script:RecDlg }
    return [Windows.Forms.MessageBox]::Show($owner, $text, $caption, $buttons, $icon)
}

# ---------- Dark input prompt (name of the backup) ----------
function Show-InputPrompt($title, $message, $initial, $owner) {
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = $title
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false; $dlg.ShowInTaskbar = $false
    $dlg.BackColor = $BG
    $dlg.ClientSize = New-Object Drawing.Size(460,200)

    $accent = New-Object Windows.Forms.Panel
    $accent.Dock = 'Top'; $accent.Height = 5; $accent.BackColor = $ACCENTS.demo3
    $dlg.Controls.Add($accent)

    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = $message
    $lbl.Font = $FONT_LABEL
    $lbl.ForeColor = $COLOR_TEXT
    $lbl.AutoSize = $true
    $lbl.MaximumSize = New-Object Drawing.Size(420,0)
    $lbl.Left = 20; $lbl.Top = 25
    $dlg.Controls.Add($lbl)
    $lblH = $lbl.GetPreferredSize((New-Object Drawing.Size(420,0))).Height

    $txt = New-Object Windows.Forms.TextBox
    $txt.Text = $initial
    $txt.Font = $FONT_ENTRY
    $txt.BackColor = $SECTION; $txt.ForeColor = $COLOR_TEXT
    $txt.BorderStyle = 'FixedSingle'
    $txt.Left = 20; $txt.Top = 25 + $lblH + 14; $txt.Width = 420
    $dlg.Controls.Add($txt)

    $btnTop = $txt.Bottom + 22
    $btnCancel = New-Object Windows.Forms.Button
    $btnCancel.Text = "Cancel"; $btnCancel.Font = $FONT_POPUP
    $btnCancel.Width = 120; $btnCancel.Height = 40
    $btnCancel.Left = 440 - 120; $btnCancel.Top = $btnTop
    $btnCancel.BackColor = [Drawing.Color]::FromArgb(70,70,70); $btnCancel.ForeColor = [Drawing.Color]::White
    $btnCancel.DialogResult = 'Cancel'
    Set-ModernButton $btnCancel
    $dlg.Controls.Add($btnCancel)

    $btnOk = New-Object Windows.Forms.Button
    $btnOk.Text = "✔️ Create"; $btnOk.Font = $FONT_POPUP
    $btnOk.Width = 120; $btnOk.Height = 40
    $btnOk.Left = $btnCancel.Left - 10 - 120; $btnOk.Top = $btnTop
    $btnOk.BackColor = [Drawing.Color]::FromArgb(48,209,88); $btnOk.ForeColor = [Drawing.Color]::White
    $btnOk.DialogResult = 'OK'
    Set-ModernButton $btnOk
    $dlg.Controls.Add($btnOk)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel
    $dlg.ActiveControl = $txt
    $dlg.ClientSize = New-Object Drawing.Size(460, ($btnTop + 40 + 22))

    $res = $dlg.ShowDialog($owner)
    $value = $null
    if ($res -eq 'OK') { $value = $txt.Text }
    $dlg.Dispose()
    return $value
}

# ---------- Create backup of the currently SAVED settings_scripts.json ----------
function New-SettingsBackup {
    if (-not (Test-Path -LiteralPath $jsonPath)) {
        [void](Show-Msg "settings_scripts.json was not found." "Backup" 'OK' 'Error')
        return
    }
    $msg = "Enter a name for the new backup:"
    if ($script:HasUnsavedChanges) {
        $msg += "`n`n⚠️ You have unsaved changes. The backup contains only the settings that are currently SAVED."
    }
    $name = Show-InputPrompt "New Backup" $msg ("Backup " + (Get-Date -Format "yyyy-MM-dd HH-mm")) $script:RecDlg
    if ($null -eq $name) { return }

    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $clean = -join ($name.ToCharArray() | Where-Object { $invalid -notcontains $_ })
    $clean = $clean.Trim().TrimEnd('.').Trim()
    if ($clean -like '*.json') { $clean = $clean.Substring(0, $clean.Length - 5).Trim() }
    if ([string]::IsNullOrWhiteSpace($clean)) {
        [void](Show-Msg "The backup name is empty or invalid." "Backup" 'OK' 'Warning')
        return
    }
    try {
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        $dest = Join-Path $backupDir "$clean.json"
        if (Test-Path -LiteralPath $dest) {
            if ((Show-Msg "A backup named '$clean' already exists.`nOverwrite it?" "Backup" 'YesNo' 'Warning') -ne 'Yes') { return }
        }
        [IO.File]::Copy($jsonPath, $dest, $true)
    } catch {
        [void](Show-Msg "Backup failed:`n$($_.Exception.Message)" "Backup" 'OK' 'Error')
        return
    }
    Refresh-BackupList
}

# ---------- Refresh the GUI controls from a config object (used after Restore) ----------
function Load-GuiFromConfig($c) {
    $tDockerPath.Text    = [string]$c.DockerPath
    $tDockerCli.Text     = [string]$c.DockerCliPath
    $tContainers.Text    = (@($c.Containers) -join ",")
    $tDockerDesktop.Text = [string]$c.DockerDesktopPath
    $tSwapFolder.Text    = [string]$c.SwapFolderPath
    # Wi-Fi
    $txtWifi1.Text = [string]$c.wifi1
    $txtWifi2.Text = [string]$c.wifi2
    # Time spinners (WiFi 1 -> WiFi 2)
    if ($c.TendaToBeniTime -and ($c.TendaToBeniTime -match '^(\d{2}):(\d{2})$')) {
        $h = [int]$matches[1]; $m = [int]$matches[2]
        $script:originalTendaHour = $h; $script:originalTendaMin = $m
        $nudTendaHour.Value = $h; $nudTendaMin.Value = $m
        $nudTendaHour.Text = "{0:D2}" -f $h; $nudTendaMin.Text = "{0:D2}" -f $m
    } else {
        $script:originalTendaHour = 0; $script:originalTendaMin = 0
        $nudTendaHour.Value = 0; $nudTendaMin.Value = 0
        $nudTendaHour.Text = "";  $nudTendaMin.Text = ""
    }
    # Time spinners (WiFi 2 -> WiFi 1)
    if ($c.BeniToTendaTime -and ($c.BeniToTendaTime -match '^(\d{2}):(\d{2})$')) {
        $h = [int]$matches[1]; $m = [int]$matches[2]
        $script:originalBeniHour = $h; $script:originalBeniMin = $m
        $nudBeniHour.Value = $h; $nudBeniMin.Value = $m
        $nudBeniHour.Text = "{0:D2}" -f $h; $nudBeniMin.Text = "{0:D2}" -f $m
    } else {
        $script:originalBeniHour = 0; $script:originalBeniMin = 0
        $nudBeniHour.Value = 0; $nudBeniMin.Value = 0
        $nudBeniHour.Text = "";  $nudBeniMin.Text = ""
    }
}

# ---------- Restore: overwrite settings_scripts.json with the selected backup ----------
function Restore-SettingsBackup($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        [void](Show-Msg "This backup file no longer exists." "Restore" 'OK' 'Warning')
        Refresh-BackupList
        return
    }
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    if ((Show-Msg "Restore backup '$name'?`nThe current settings_scripts.json will be OVERWRITTEN." "Restore Backup" 'YesNo' 'Warning') -ne 'Yes') { return }
    try {
        $restored = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if (-not $restored) { throw "The backup file is empty." }
    } catch {
        [void](Show-Msg "This backup is invalid or corrupted and was NOT restored:`n$($_.Exception.Message)" "Restore" 'OK' 'Error')
        return
    }
    try {
        [IO.File]::Copy($path, $jsonPath, $true)
    } catch {
        [void](Show-Msg "Restore failed:`n$($_.Exception.Message)" "Restore" 'OK' 'Error')
        return
    }
    # keep the in-memory config and the form in sync with the restored file
    foreach ($p in "DockerPath","DockerCliPath","Containers","DockerDesktopPath","SwapFolderPath") {
        if (-not $restored.PSObject.Properties.Match($p)) {
            $defaultValue = if ($p -eq "Containers") { @() } else { "" }
            $restored | Add-Member -MemberType NoteProperty -Name $p -Value $defaultValue
        }
    }
    $script:config = $restored
    try { Load-GuiFromConfig $restored } catch { }
    $script:HasUnsavedChanges = $false
    [void](Show-Msg "✔️ Backup '$name' restored successfully!" "Restore" 'OK' 'Information')
}

# ---------- Delete: remove the selected backup file ----------
function Remove-SettingsBackup($path) {
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    if ((Show-Msg "Delete backup '$name'?`nThis cannot be undone." "Delete Backup" 'YesNo' 'Warning') -ne 'Yes') { return }
    try {
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    } catch {
        [void](Show-Msg "Delete failed:`n$($_.Exception.Message)" "Delete" 'OK' 'Error')
    }
    Refresh-BackupList
}

# ---------- Rebuild the list of backup rows ----------
function Refresh-BackupList {
    $tbl = $script:RecList
    if (-not $tbl) { return }
    $tbl.SuspendLayout()
    $tbl.Controls.Clear()
    $tbl.RowStyles.Clear()
    $files = @(Get-BackupFiles)

    if ($files.Count -eq 0) {
        $tbl.RowCount = 1
        [void]$tbl.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))
        $empty = New-Object Windows.Forms.Label
        $empty.Text = "No backup has been created yet."
        $empty.Font = $FONT_LABEL
        $empty.ForeColor = [Drawing.Color]::FromArgb(160,160,160)
        $empty.Height = 120
        $empty.Dock = 'Fill'
        $empty.TextAlign = 'MiddleCenter'
        $tbl.Controls.Add($empty, 0, 0)
    }
    else {
        $tbl.RowCount = $files.Count
        $i = 0
        foreach ($f in $files) {
            $i++
            [void]$tbl.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::AutoSize)))

            $row = New-Object Windows.Forms.Panel
            $row.Height = 56
            $row.Dock = 'Fill'
            $row.Margin = New-Object Windows.Forms.Padding(0,0,0,8)
            $row.BackColor = $SECTION

            $inner = New-Object Windows.Forms.TableLayoutPanel
            $inner.Dock = 'Fill'
            $inner.ColumnCount = 4
            $inner.RowCount = 1
            [void]$inner.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,60)))
            [void]$inner.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
            [void]$inner.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,120)))
            [void]$inner.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,120)))
            [void]$inner.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))

            $num = New-Object Windows.Forms.Label
            $num.Text = "$i."
            $num.Font = $FONT_ENTRY
            $num.ForeColor = $ACCENTS.demo3
            $num.Dock = 'Fill'
            $num.TextAlign = 'MiddleCenter'
            $num.Margin = New-Object Windows.Forms.Padding(0)

            $lblName = New-Object Windows.Forms.Label
            $lblName.Text = $f.BaseName
            $lblName.Font = $FONT_ENTRY
            $lblName.ForeColor = $COLOR_TEXT
            $lblName.Dock = 'Fill'
            $lblName.TextAlign = 'MiddleLeft'
            $lblName.AutoEllipsis = $true
            $lblName.Margin = New-Object Windows.Forms.Padding(0)
            if ($script:RecTip) { $script:RecTip.SetToolTip($lblName, ($f.BaseName + "`nCreated: " + $f.CreationTime.ToString("yyyy-MM-dd HH:mm"))) }

            $btnRestore = New-Object Windows.Forms.Button
            $btnRestore.Text = "♻️ Restore"
            $btnRestore.Font = $FONT_POPUP
            $btnRestore.Dock = 'Fill'
            $btnRestore.Margin = New-Object Windows.Forms.Padding(4,9,4,9)
            $btnRestore.BackColor = $ACCENTS.docker
            $btnRestore.ForeColor = [Drawing.Color]::White
            $btnRestore.Tag = $f.FullName
            Set-ModernButton $btnRestore
            $btnRestore.Add_Click({ Restore-SettingsBackup $this.Tag })

            $btnDelete = New-Object Windows.Forms.Button
            $btnDelete.Text = "🗑 Delete"
            $btnDelete.Font = $FONT_POPUP
            $btnDelete.Dock = 'Fill'
            $btnDelete.Margin = New-Object Windows.Forms.Padding(4,9,10,9)
            $btnDelete.BackColor = [Drawing.Color]::FromArgb(255,69,58)
            $btnDelete.ForeColor = [Drawing.Color]::White
            $btnDelete.Tag = $f.FullName
            Set-ModernButton $btnDelete
            $btnDelete.Add_Click({ Remove-SettingsBackup $this.Tag })

            $inner.Controls.Add($num, 0, 0)
            $inner.Controls.Add($lblName, 1, 0)
            $inner.Controls.Add($btnRestore, 2, 0)
            $inner.Controls.Add($btnDelete, 3, 0)
            $row.Controls.Add($inner)
            $tbl.Controls.Add($row, 0, $i - 1)
        }
    }
    $tbl.ResumeLayout($true)
}

# ---------- Recovery popup ----------
function Show-RecoveryDialog {
    $dlg = New-Object Windows.Forms.Form
    $dlg.Text = "Recovery - Scripts Settings Backups"
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = $BG
    $dlg.ShowInTaskbar = $false
    $dlg.MinimizeBox = $false
    if ($form.Icon) { $dlg.Icon = $form.Icon }
    $wa = [Windows.Forms.Screen]::FromControl($form).WorkingArea
    $w = [Math]::Min(760, [int]($wa.Width  * 0.9))
    $h = [Math]::Min(540, [int]($wa.Height * 0.85))
    $dlg.ClientSize = New-Object Drawing.Size($w,$h)
    $dlg.MinimumSize = New-Object Drawing.Size(520,340)

    # scrollable list area (fills everything below the header)
    $hostPanel = New-Object Windows.Forms.Panel
    $hostPanel.Dock = 'Fill'
    $hostPanel.AutoScroll = $true
    $hostPanel.BackColor = $BG
    $hostPanel.Padding = New-Object Windows.Forms.Padding(15)

    $tbl = New-Object Windows.Forms.TableLayoutPanel
    $tbl.Dock = 'Top'
    $tbl.AutoSize = $true
    $tbl.AutoSizeMode = 'GrowAndShrink'
    $tbl.ColumnCount = 1
    $tbl.BackColor = $BG
    [void]$tbl.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
    $hostPanel.Controls.Add($tbl)

    # header: title + Backup button
    $header = New-Object Windows.Forms.Panel
    $header.Dock = 'Top'
    $header.Height = 80
    $header.BackColor = $SECTION

    $hdrTbl = New-Object Windows.Forms.TableLayoutPanel
    $hdrTbl.Dock = 'Fill'
    $hdrTbl.ColumnCount = 2
    $hdrTbl.RowCount = 1
    $hdrTbl.Padding = New-Object Windows.Forms.Padding(15,0,15,0)
    [void]$hdrTbl.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
    [void]$hdrTbl.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,170)))
    [void]$hdrTbl.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))

    $title = New-Object Windows.Forms.Label
    $title.Text = "🛟 Recovery"
    $title.Font = $FONT_SECTION
    $title.ForeColor = $COLOR_TEXT
    $title.Dock = 'Fill'
    $title.TextAlign = 'MiddleLeft'

    $btnBackup = New-Object Windows.Forms.Button
    $btnBackup.Text = "➕ Backup"
    $btnBackup.Font = $FONT_BUTTON
    $btnBackup.Dock = 'Fill'
    $btnBackup.Margin = New-Object Windows.Forms.Padding(8,18,0,15)
    $btnBackup.BackColor = [Drawing.Color]::FromArgb(48,209,88)
    $btnBackup.ForeColor = [Drawing.Color]::White
    Set-ModernButton $btnBackup
    $btnBackup.Add_Click({ New-SettingsBackup })

    $hdrTbl.Controls.Add($title, 0, 0)
    $hdrTbl.Controls.Add($btnBackup, 1, 0)
    $header.Controls.Add($hdrTbl)

    $accent = New-Object Windows.Forms.Panel
    $accent.Dock = 'Top'; $accent.Height = 5; $accent.BackColor = $ACCENTS.demo3
    $header.Controls.Add($accent)

    # Fill control first (front of z-order), docked controls after it
    $dlg.Controls.Add($hostPanel)
    $dlg.Controls.Add($header)

    $script:RecDlg  = $dlg
    $script:RecList = $tbl
    $script:RecTip  = New-Object Windows.Forms.ToolTip
    Refresh-BackupList

    [void]$dlg.ShowDialog($form)

    $script:RecList = $null
    $script:RecDlg  = $null
    $script:RecTip.Dispose()
    $script:RecTip  = $null
    $dlg.Dispose()
}

# ================= RECOVERY BUTTON =================
$recoveryBtn = New-Object Windows.Forms.Button
$recoveryBtn.Text = "🛟 Recovery"
$recoveryBtn.Font = $FONT_BUTTON
$recoveryBtn.Width = 200
$recoveryBtn.Height = 44
$recoveryBtn.BackColor = $ACCENTS.demo3
$recoveryBtn.ForeColor = [Drawing.Color]::White
Set-ModernButton $recoveryBtn
$buttonBar.Controls.Add($recoveryBtn)
$recoveryBtn.Add_Click({ Show-RecoveryDialog })

# ================= BUTTON BAR LAYOUT (centered row at the bottom) =================
function Update-ButtonBar {
    $btns = @($save, $defaultBtn, $customBtn, $resetBtn, $recoveryBtn)
    $gap = 15
    $total = $gap * ($btns.Count - 1)
    foreach ($b in $btns) { $total += $b.Width }
    $x = [Math]::Max(10, [int](($buttonBar.ClientSize.Width - $total) / 2))
    foreach ($b in $btns) {
        $b.Left = $x
        $b.Top  = [int](($buttonBar.ClientSize.Height - $b.Height) / 2) + 1
        $x += $b.Width + $gap
    }
}
$buttonBar.Add_Resize({ Update-ButtonBar })
$form.Add_Shown({ Update-ButtonBar })
# ================= BUTTON BAR STYLE =================
$buttonBar.BackColor = [Drawing.Color]::FromArgb(31,31,31)
$buttonBarAccent = New-Object Windows.Forms.Panel
$buttonBarAccent.Dock = 'Left'
$buttonBarAccent.Width = 6
$buttonBarAccent.BackColor = [Drawing.Color]::FromArgb(78, 230, 164)
$buttonBar.Controls.Add($buttonBarAccent)
$buttonBarAccent.SendToBack()
Update-ButtonBar

# ================= FORM CLOSING =================
$form.Add_FormClosing({
    if (-not $script:HasUnsavedChanges) { return }
    $closingEvent = $_
    $res = [Windows.Forms.MessageBox]::Show(
        "You have unsaved changes.`nDo you want to save before exiting?",
        "Unsaved Changes",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($res -eq [Windows.Forms.DialogResult]::Yes) {
        try {
            $save.PerformClick()
            if ($script:HasUnsavedChanges) {
                $closingEvent.Cancel = $true
            }
        }
        catch {
            $closingEvent.Cancel = $true
            [Windows.Forms.MessageBox]::Show(
                "Unable to save changes:`n$($_.Exception.Message)",
                "Save Error",
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }
})
# ================= SHOW FORM =================
[void]$form.ShowDialog()

################################################################################################ Settings Scripts End.