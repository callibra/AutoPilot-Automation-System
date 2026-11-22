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

# ====================== AutoPilot Settings GUI ======================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ================= UNSAVED CHANGES TRACKING =================
$script:HasUnsavedChanges = $false
function Mark-Dirty { $script:HasUnsavedChanges = $true }

# ================= COLORS & FONTS =================
$BG = [Drawing.Color]::FromArgb(21,22,26)
$SECTION = [Drawing.Color]::FromArgb(29,29,36)
$COLOR_TEXT = [Drawing.Color]::White

$ACCENTS = @{
    telegram = [Drawing.Color]::FromArgb(10,132,255)
    limits   = [Drawing.Color]::FromArgb(54,189,138)
    critical = [Drawing.Color]::FromArgb(255,159,10)
    hw       = [Drawing.Color]::FromArgb(230,230,71)
    screen   = [Drawing.Color]::FromArgb(100,210,255)
    days     = [Drawing.Color]::FromArgb(191,90,242)
}

$FONT_SECTION = New-Object Drawing.Font("Segoe UI Emoji",14,[Drawing.FontStyle]::Bold)
$FONT_LABEL   = New-Object Drawing.Font("Segoe UI Emoji",12)
$FONT_ENTRY   = New-Object Drawing.Font("Segoe UI Emoji",12,[Drawing.FontStyle]::Bold)
$FONT_SPIN    = New-Object Drawing.Font("Segoe UI Emoji",12,[Drawing.FontStyle]::Bold)
$FONT_BUTTON  = New-Object Drawing.Font("Segoe UI Emoji",12,[Drawing.FontStyle]::Bold)

# ================= ROOT FORM =================
$form = New-Object System.Windows.Forms.Form
$form.Text = "AutoPilot Settings"
$form.WindowState = "Maximized"
$form.Size = New-Object System.Drawing.Size(1280, 800)
$form.StartPosition = "CenterScreen"
$form.BackColor = $BG

# ================= LOAD ICON =================
$iconPath = "$AppRoot\media\settings.ico"
if (Test-Path $iconPath) {
    $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
}

# ================= JSON =================
$jsonPath = "$AppRoot\JSON\settings.json"
if (-not (Test-Path (Split-Path $jsonPath))) { New-Item -ItemType Directory -Path (Split-Path $jsonPath) | Out-Null }
if (-not (Test-Path $jsonPath)) {
    # Default config
    @{
        ALLOWED_DAYS=@("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")
        MAX_RUNS=1
        TELEGRAM_BOT_TOKEN=""
        TELEGRAM_CHAT_ID=""
        OWNER_ID=""
        MEDIA_FOLDER_URL=""
        BOT_TOKEN=""
        CHAT_ID=""
        OWNER_IDS=@()
        AUTOPILOT_URL=""
        AUTO_START_MONITORING=$true
        TRAFFIC_MONITOR_AUTO_START=$true
        TEMP_CHECK_INTERVAL=300
        CPU_LIMIT=50; CPU_TEMP_CRITICAL_LIMIT=60
        DISK_LIMIT=45; DISK_TEMP_CRITICAL_LIMIT=52
        MB_LIMIT=45; MB_TEMP_CRITICAL_LIMIT=50
        GPU_LIMIT=50; GPU_TEMP_CRITICAL_LIMIT=70
        RAM_USAGE_ALARM_LIMIT=60; RAM_USAGE_CRITICAL_LIMIT=88
        CPU_LOAD_ALARM_LIMIT=88; CPU_LOAD_CRITICAL_LIMIT=101
        HardwareMonitor=@{ SampleIntervalSeconds=300 }
        ScreenCapture=@{ IncludeAudio=$true; AudioDevice="" }
        CameraCapture=@{ VideoDevice=""; AudioDevice="" }
		AUTOPILOT_TELEGRAM_ENABLED=$false
		MEDIA_TELEGRAM_ENABLED=$false
		ENABLE_RESTART=$false
		ENABLE_SHUTDOWN=$false
		FIXED_NO_BLOCK_CYCLE=$false
		VIDEO_RETENTION_DAYS=15
    } | ConvertTo-Json -Depth 5 | Set-Content $jsonPath -Encoding UTF8
}
$config = Get-Content $jsonPath | ConvertFrom-Json

# ================= HELPERS =================
function Section($title,$accent) {
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
    $hdr.Height = 44; $hdr.Dock = 'Top'; $hdr.BackColor = $tint
    $p.Controls.Add($hdr)
    # solid accent stripe on the left edge (added after the band so it spans the full height)
    $stripe = New-Object Windows.Forms.Panel
    $stripe.Width = 6; $stripe.Dock = 'Left'; $stripe.BackColor = $accent
    $p.Controls.Add($stripe)
    $l = New-Object Windows.Forms.Label
    $l.Text = $title
    $l.Font = $FONT_SECTION
    $l.ForeColor = $COLOR_TEXT
    $l.BackColor = $tint
    $l.AutoSize = $true
    $l.Top = 9; $l.Left = 12
    $hdr.Controls.Add($l)
    return $p
}

function LabelText($parent,$text,$top) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.Font = $FONT_LABEL
    $l.ForeColor = $COLOR_TEXT
    $l.BackColor = $SECTION
    $l.AutoSize = $true
    $l.Left = 10; $l.Top = $top
    $parent.Controls.Add($l)
}

function TextBoxRow($parent,$label,$value,$top) {
    LabelText $parent $label $top
    $t = New-Object Windows.Forms.TextBox
    $t.Text = $value
    $t.Left = 220; $t.Top = $top-3; $t.Width = 255
    $t.Font = $FONT_ENTRY; $t.BackColor = $SECTION; $t.ForeColor = $COLOR_TEXT
	$t.Add_TextChanged({Mark-Dirty})
    $parent.Controls.Add($t)
    return $t
}

function SpinRow($parent,$label,$value,$min,$max,$top){
    LabelText $parent $label $top
    $n = New-Object Windows.Forms.NumericUpDown
    $n.Minimum = $min; $n.Maximum = $max
    $n.Value   = [Math]::Min($max,[Math]::Max($min,$value))
    $n.Left = 380; $n.Top = $top-3; $n.Width = 90
    $n.Font = $FONT_SPIN; $n.BackColor = $SECTION; $n.ForeColor = $COLOR_TEXT
    $n.TextAlign = 'Center'; $n.ReadOnly = $true; $n.InterceptArrowKeys = $true
	$n.Add_ValueChanged({Mark-Dirty})
    $parent.Controls.Add($n)
    return $n
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

function Set-ToggleState($btn, $state){
    if ($state) {
        $btn.Text = "ON"
        $btn.BackColor = [Drawing.Color]::FromArgb(48,209,88)
    } else {
        $btn.Text = "OFF"
        $btn.BackColor = [Drawing.Color]::FromArgb(255,69,58)
    }
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

function ToggleRow($parent,$label,$value,$top) {
    LabelText $parent $label $top
    $b = New-Object Windows.Forms.Button
    $b.Width  = 90
    $b.Height = 30
    $b.Left   = 380
    $b.Top    = $top - 5
    $b.Font   = $FONT_BUTTON
    $b.ForeColor = [Drawing.Color]::White
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    # ✅ иницијална состојба
    Set-ToggleState $b $value
    # ✅ click → toggle + dirty flag
    $b.Add_Click({
        $newState = ($this.Text -eq "OFF")
        Set-ToggleState $this $newState
        Mark-Dirty
    })
    Set-ModernButton $b
    $parent.Controls.Add($b)
    return $b
}

function AddFooterLine($panel, $text) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.Font = New-Object Drawing.Font("Segoe UI",9)
    $l.ForeColor = [Drawing.Color]::FromArgb(48,209,88)
    $l.AutoSize = $true
    # ⬅️ ова е клучното за повеќе редови
    $l.MaximumSize = New-Object Drawing.Size(($panel.Width - 20), 0)
    $l.Left = 10
    # динамички долу (се наместува по висината на текстот)
    $l.Top = $panel.Height - $l.PreferredHeight - 10
    # ако панелот се ресајзира
    $panel.Add_Resize({
        $l.MaximumSize = New-Object Drawing.Size(($panel.Width - 20), 0)
        $l.Top = $panel.Height - $l.PreferredHeight - 10
    })
    $panel.Controls.Add($l)
}

# ================= LAYOUT =================
$scrollPanel = New-Object Windows.Forms.Panel
$scrollPanel.Dock = 'Fill'          # Пополнува целата форма
$scrollPanel.AutoScroll = $true     # Овозможува скрол
$scrollPanel.BackColor = $BG
$form.Controls.Add($scrollPanel)

# ================= GRID =================
$grid = New-Object Windows.Forms.TableLayoutPanel
$grid.AutoSize = $true              # Автоматски се ресајзира според содржината
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
$headerBar.BackColor = [Drawing.Color]::FromArgb(31, 31, 31)
# gradient background: charcoal (left) -> deep blue (right)
$headerBar.Add_Paint({
    $rect = $this.ClientRectangle
    if ($rect.Width -le 0 -or $rect.Height -le 0) { return }
    $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [Drawing.Color]::FromArgb(31, 31, 31),
        [Drawing.Color]::FromArgb(16, 58, 112),
        [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
    $_.Graphics.FillRectangle($gb, $rect)
    $gb.Dispose()
})
$headerBar.Add_Resize({ $this.Invalidate() })
$headerAccent = New-Object Windows.Forms.Panel
$headerAccent.Dock = 'Left'
$headerAccent.Width = 6
$headerAccent.BackColor = $ACCENTS.telegram
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
$headerTitle.Text = 'AutoPilot Settings Panel'
$headerTitle.Font = New-Object Drawing.Font('Segoe UI',16,[Drawing.FontStyle]::Bold)
$headerTitle.ForeColor = [Drawing.Color]::White
$headerTitle.BackColor = [Drawing.Color]::Transparent
$headerTitle.AutoSize = $true
$headerTitle.Location = New-Object Drawing.Point($titleLeft,11)
$headerBar.Controls.Add($headerTitle)

# ================= HEADER SUBTITLE =================
$headerSubtitle = New-Object Windows.Forms.Label
$headerSubtitle.Text = 'Main Settings  /  Telegram  /  System Monitoring'
$headerSubtitle.Font = New-Object Drawing.Font('Segoe UI',8.5)
$headerSubtitle.ForeColor = [Drawing.Color]::FromArgb(177,190,211)
$headerSubtitle.BackColor = [Drawing.Color]::Transparent
$headerSubtitle.AutoSize = $true
$headerSubtitle.Location = New-Object Drawing.Point($subtitleLeft,43)
$headerBar.Controls.Add($headerSubtitle)
$form.Controls.Add($headerBar)

# ================= CREATE SECTIONS =================
$telegram = Section "💎 Telegram & Bot" $ACCENTS.telegram
$limits   = Section "📢 System Alarms Limits" $ACCENTS.limits
$critical = Section "⚠️ System Critical Limits" $ACCENTS.critical
$hw       = Section "📊 System Monitoring / Alarms Limits Mode" $ACCENTS.hw
$screen   = Section "🎬 Record Screen / Camera" $ACCENTS.screen
$days     = Section "📆 AutoPilot Allowed Days / Runs / Enable Bot" $ACCENTS.days

$grid.Controls.Add($telegram,0,0)
$grid.Controls.Add($limits,1,0)
$grid.Controls.Add($hw,2,1)
$grid.Controls.Add($screen,0,1)
$grid.Controls.Add($days,1,1)
$grid.Controls.Add($critical,2,0)

# ================= TELEGRAM =================
$y=50; $spacing=40
$sub1 = New-Object Windows.Forms.Label; $sub1.Text="● AutoPilot Bot"; $sub1.Font=$FONT_LABEL; $sub1.ForeColor=[Drawing.Color]::FromArgb(10,132,255)
$sub1.AutoSize=$true; $sub1.Left=10; $sub1.Top=$y; $telegram.Controls.Add($sub1); $y+=25
$t1 = TextBoxRow $telegram "🔑 Telegram Bot Token:" $config.TELEGRAM_BOT_TOKEN $y
AddEmoji $telegram "📝" $t1
$y += $spacing
$t2 = TextBoxRow $telegram "🆔 Telegram Chat ID:" $config.TELEGRAM_CHAT_ID $y
AddEmoji $telegram "🔢" $t2
$y += $spacing
$t3 = TextBoxRow $telegram "✅ Allowed Owner ID:" $config.OWNER_ID $y
AddEmoji $telegram "👤" $t3
$y += $spacing
$t8 = TextBoxRow $telegram "🌐 Autopilot URL:" $config.AUTOPILOT_URL $y
AddEmoji $telegram "🔗" $t8
$y += $spacing
$sub2 = New-Object Windows.Forms.Label; $sub2.Text="● Media Bot"; $sub2.Font=$FONT_LABEL; $sub2.ForeColor=[Drawing.Color]::FromArgb(10,132,255)
$sub2.AutoSize=$true; $sub2.Left=10; $sub2.Top=$y; $telegram.Controls.Add($sub2); $y+=25
$t5 = TextBoxRow $telegram "🔑 Media Bot Token:" $config.BOT_TOKEN $y
AddEmoji $telegram "📝" $t5
$y += $spacing
$t6 = TextBoxRow $telegram "🆔 Media Chat ID:" $config.CHAT_ID $y
AddEmoji $telegram "🔢" $t6
$y += $spacing
$t4 = TextBoxRow $telegram "✅ Allowed Owner IDs (1+):" ($config.OWNER_IDS -join ",") $y
AddEmoji $telegram "👥" $t4
$y += $spacing
$t7 = TextBoxRow $telegram "🌐 Media Folder URL:" $config.MEDIA_FOLDER_URL $y
AddEmoji $telegram "🔗" $t7
$y += $spacing
AddFooterLine $telegram "● Enter your Telegram Token and ID for two BOT Telegram Accounts.
● First Bot Account for AutoPilot and Second Bot Account for Media Folder Editor.
● Enter your Allowed ID. In IDs, you can enter multiple IDs, example: 12345,67890."

# ================= SYSTEM ALARMS =================
$y=50; $spacing=35
$subLimits = New-Object Windows.Forms.Label; $subLimits.Text="● Load and Temperatures Alarms"; $subLimits.Font=$FONT_LABEL; $subLimits.ForeColor=[Drawing.Color]::FromArgb(54,189,138)
$subLimits.AutoSize=$true; $subLimits.Left=10; $subLimits.Top=$y; $limits.Controls.Add($subLimits); $y+=25
$cpuLA = SpinRow $limits "🔳 CPU Load (percent):" $config.CPU_LOAD_ALARM_LIMIT 1 150 $y
AddEmoji $limits "%" $cpuLA
$y += $spacing
$ramA = SpinRow $limits "🎟 RAM Load (percent):" $config.RAM_USAGE_ALARM_LIMIT 1 100 $y
AddEmoji $limits "%" $ramA
$y += $spacing
$mbL = SpinRow $limits "🏿 MB Temperature (metric):" $config.MB_LIMIT 1 100 $y
AddEmoji $limits "🌡️" $mbL
$y += $spacing
$cpuL = SpinRow $limits "🔳 CPU Temperature (metric):" $config.CPU_LIMIT 1 100 $y
AddEmoji $limits "🌡️" $cpuL
$y += $spacing
$gpuL = SpinRow $limits "🏼 GPU Temperature (metric):" $config.GPU_LIMIT 1 100 $y
AddEmoji $limits "🌡️" $gpuL
$y += $spacing
$diskL = SpinRow $limits "💾 Disk Temperature (metric):" $config.DISK_LIMIT 1 100 $y
AddEmoji $limits "🌡️" $diskL
$y += $spacing
AddFooterLine $limits "● Set your Alarms for CPU, RAM and load expressed in percentages.
● Set your Alarms for CPU, GPU, MotherBoard (MB), and Disk temperatures in metric units.
● When any of these parameters are exceeded, you will receive an Alarm notification in Your Telegram Chat."

# ================= SYSTEM LIMITS =================
$y=50; $spacing=35
$subCritical = New-Object Windows.Forms.Label; $subCritical.Text="● Load and Temperatures Limits"; $subCritical.Font=$FONT_LABEL; $subCritical.ForeColor=[Drawing.Color]::FromArgb(255,159,10)
$subCritical.AutoSize=$true; $subCritical.Left=10; $subCritical.Top=$y; $critical.Controls.Add($subCritical); $y+=25
$cpuLC = SpinRow $critical "🔳 CPU Load Limit (percent):" $config.CPU_LOAD_CRITICAL_LIMIT 1 200 $y
AddEmoji $critical "%" $cpuLC
$y += $spacing
$ramC = SpinRow $critical "🎟 RAM Load Limit (percent):" $config.RAM_USAGE_CRITICAL_LIMIT 1 100 $y
AddEmoji $critical "%" $ramC
$y += $spacing
$mbT = SpinRow $critical "🏿 MB Temperature Limit (metric):" $config.MB_TEMP_CRITICAL_LIMIT 40 120 $y
AddEmoji $critical "🌡️" $mbT
$y += $spacing
$cpuT = SpinRow $critical "🔳 CPU Temperature Limit (metric):" $config.CPU_TEMP_CRITICAL_LIMIT 40 120 $y
AddEmoji $critical "🌡️" $cpuT
$y += $spacing
$gpuT = SpinRow $critical "🏼 GPU Temperature Limit (metric):" $config.GPU_TEMP_CRITICAL_LIMIT 40 120 $y
AddEmoji $critical "🌡️" $gpuT
$y += $spacing
$diskT = SpinRow $critical "💾 Disk Temperature Limit (metric):" $config.DISK_TEMP_CRITICAL_LIMIT 40 120 $y
AddEmoji $critical "🌡️" $diskT
$y += $spacing
AddFooterLine $critical "● Set your Limits Alarms for CPU, RAM and load expressed in percentages.
● Set your Limits Alarms for CPU, GPU, MotherBoard (MB), and Disk temperatures in metric units.
● When any of these parameters are exceeded, a safe action will be performed on your PC (restart, shutdown, or restart of the AutoPilot) depending on the duration for which the Alarm has been exceeded."

# ================= SYSTEM MONITORING =================
$y=50; $spacing=40
$sub1 = New-Object Windows.Forms.Label; $sub1.Text="● System Interval"; $sub1.Font=$FONT_LABEL; $sub1.ForeColor=[Drawing.Color]::FromArgb(230,230,71)
$sub1.AutoSize=$true; $sub1.Left=10; $sub1.Top=$y; $hw.Controls.Add($sub1); $y+=25
$sample = SpinRow $hw "📈 System Hardware Monitoring Interval (sec):" $config.HardwareMonitor.SampleIntervalSeconds 60 500 $y
AddEmoji $hw "🕒" $sample
$y += $spacing
$tempI = SpinRow $hw "📢 System Alarm Limit Interval (sec):" $config.TEMP_CHECK_INTERVAL 60 500 $y
AddEmoji $hw "🕒" $tempI
$y += $spacing
$sub2 = New-Object Windows.Forms.Label; $sub2.Text="● Monitoring ON / OFF"; $sub2.Font=$FONT_LABEL; $sub2.ForeColor=[Drawing.Color]::FromArgb(230,230,71)
$sub2.AutoSize=$true; $sub2.Left=10; $sub2.Top=$y; $hw.Controls.Add($sub2); $y+=25
$autoM = ToggleRow $hw "📈 Auto Start System Monitoring:" $config.AUTO_START_MONITORING $y
AddEmoji $hw "🔵" $autoM
$y += $spacing
$traffic = ToggleRow $hw "📶 Auto Start Traffic Monitoring:" $config.TRAFFIC_MONITOR_AUTO_START $y
AddEmoji $hw "🔵" $traffic
$y += $spacing
# ================= Pro / Test Mode =================
# Label for the button
$lblProTest = New-Object Windows.Forms.Label
$lblProTest.Text = "⚡ Alarms Limits Mode (Pro / Test):"
$lblProTest.Font = $FONT_LABEL
$lblProTest.ForeColor = [Drawing.Color]::FromArgb(30,243,250)
$lblProTest.AutoSize = $true
$lblProTest.Left = 10
$lblProTest.Top  = $y
$hw.Controls.Add($lblProTest)
# Create the Pro/Test button
$proTestBtn = New-Object Windows.Forms.Button
$proTestBtn.Width  = 90
$proTestBtn.Height = 30
$proTestBtn.Left   = 380
$proTestBtn.Top    = $y - 5  # align visually with the label
$proTestBtn.Font   = $FONT_BUTTON
$proTestBtn.ForeColor = [Drawing.Color]::White
$proTestBtn.FlatStyle = 'Flat'
$proTestBtn.FlatAppearance.BorderSize = 0
# Emoji
$proEmoji = New-Object Windows.Forms.Label
$proEmoji.AutoSize = $true
$proEmoji.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 14)
$proEmoji.ForeColor = [Drawing.Color]::White
$proEmoji.Left = $proTestBtn.Left + $proTestBtn.Width + 8
$proEmoji.Top  = $proTestBtn.Top + 5
$hw.Controls.Add($proEmoji)
# function with proper closure handling
$updateProEmoji = {
    if ($proTestBtn.Text -eq "PRO") {
        $proEmoji.Text = "✔️"
    } else {
        $proEmoji.Text = "❌"
    }
}
# ✅ Set initial state based on JSON (true = Pro, false = Test)
if ($config.ENABLE_RESTART -and $config.ENABLE_SHUTDOWN) {
    $proTestBtn.Text = "PRO"
    $proTestBtn.BackColor = [Drawing.Color]::FromArgb(48,209,88)  # green
} else {
    $proTestBtn.Text = "TEST"
    $proTestBtn.BackColor = [Drawing.Color]::FromArgb(255,69,58)  # red
}
& $updateProEmoji
# ✅ Click event: toggle Pro/Test + update JSON
$proTestBtn.Add_Click({
    if ($this.Text -eq "PRO") {
        # switch to Test
        $this.Text = "TEST"
        $this.BackColor = [Drawing.Color]::FromArgb(255,69,58)
        $config.ENABLE_RESTART  = $false
        $config.ENABLE_SHUTDOWN = $false
    } else {
        # switch to Pro
        $this.Text = "PRO"
        $this.BackColor = [Drawing.Color]::FromArgb(48,209,88)
        $config.ENABLE_RESTART  = $true
        $config.ENABLE_SHUTDOWN = $true
    }
	& $updateProEmoji
    Mark-Dirty
})
Set-ModernButton $proTestBtn
$hw.Controls.Add($proTestBtn)
$y += 30
AddFooterLine $hw "● In System Interval, set how often (in seconds) data should be collected for alarm measurements and for recording data in system monitoring.
● The value must be between 60 and 500 seconds.
● In the Auto Start section, choose whether you want the System and Network Traffic Monitoring to Start Automatically when AutoPilot starts, using the ON/OFF buttons.
● If you select PRO Mode then your PC while RESTART or SHUTDOW when the alarms from the setting will be exceeded.
● If you select TEST Mode then your PC while NOT RESTART or SHUTDOW it while only show it is a SIMULATION."

# ================= RECORD SCREEN & CAMERA =================
$y=50; $spacing=40
$sub1 = New-Object Windows.Forms.Label; $sub1.Text="● Screen Record"; $sub1.Font=$FONT_LABEL; $sub1.ForeColor=[Drawing.Color]::FromArgb(100,210,255)
$sub1.AutoSize=$true; $sub1.Left=10; $sub1.Top=$y; $screen.Controls.Add($sub1); $y+=25
$sAudio = TextBoxRow $screen "🎵 Screen Audio Device:" $config.ScreenCapture.AudioDevice $y
AddEmoji $screen "📝" $sAudio
$y += $spacing
$incl = ToggleRow $screen "🔉 Include Audio (Turn ON/OFF):" $config.ScreenCapture.IncludeAudio $y
AddEmoji $screen " 🔵" $incl
$y += $spacing
$sub2 = New-Object Windows.Forms.Label; $sub2.Text="● Camera Capture"; $sub2.Font=$FONT_LABEL; $sub2.ForeColor=[Drawing.Color]::FromArgb(100,210,255)
$sub2.AutoSize=$true; $sub2.Left=10; $sub2.Top=$y; $screen.Controls.Add($sub2); $y+=25
$cVideo = TextBoxRow $screen "📸 Camera Video Device:" $config.CameraCapture.VideoDevice $y
AddEmoji $screen "📝" $cVideo
$y += $spacing
$cAudio = TextBoxRow $screen "📸 Camera Audio Device:" $config.CameraCapture.AudioDevice $y
AddEmoji $screen "📝" $cAudio
$y += $spacing
AddFooterLine $screen "● In the Screen Audio field, enter your Audio Device.
● In the Camera fields, enter your Camera Device and your Camera Audio Device.
● In order to be able to record system sound from the device, you must have *Stereo Mix* enabled in the Sound Settings.
● Use the Include Video button while you want both the Screen Recording and System Audio to be Captured.
● To find your Screen and Camera Audio/Video Devices, enter the following in PowerShell and press Enter:
● C:\AutoPilot\ffmpeg\bin\ffmpeg.exe -list_devices true -f dshow -i dummy"

# ================= DAYS =================
$y = 50
$spacing = 40
# ---- Subsection 1: Allowed Days ----
$sub1 = New-Object Windows.Forms.Label
$sub1.Text = "● Allowed Days"
$sub1.Font = $FONT_LABEL
$sub1.ForeColor = [Drawing.Color]::FromArgb(191,90,242)
$sub1.AutoSize = $true
$sub1.Left = 10
$sub1.Top = $y
$days.Controls.Add($sub1)
$y += 30
$dayButtons=@{}
$x = 10
foreach($d in "Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"){
    $b = New-Object Windows.Forms.Button
    $b.Text = $d.Substring(0,3)
    $b.Width = 62
	$b.Height=30
	$b.Font = $FONT_BUTTON; $b.ForeColor=[Drawing.Color]::White
    $b.Left = $x
    $b.Top = $y
    $b.ForeColor = [Drawing.Color]::White
    if($config.ALLOWED_DAYS -contains $d){
        $b.BackColor = [Drawing.Color]::FromArgb(48,209,88)
    } else {
        $b.BackColor = [Drawing.Color]::FromArgb(255,69,58)
    }
    $b.Add_Click({
        if($this.BackColor -eq [Drawing.Color]::FromArgb(48,209,88)){
            $this.BackColor = [Drawing.Color]::FromArgb(255,69,58)
        } else {
            $this.BackColor = [Drawing.Color]::FromArgb(48,209,88)
        }
    Mark-Dirty})
    Set-ModernButton $b
    $days.Controls.Add($b)
    $dayButtons[$d] = $b
    $x += 67
}
# -------- ONE emoji at end of whole row --------
$daysEmoji = New-Object Windows.Forms.Label
$daysEmoji.Text = "📆"
$daysEmoji.AutoSize = $true
$daysEmoji.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 14)
$daysEmoji.ForeColor = [Drawing.Color]::White
$daysEmoji.Left = $x + 1
$daysEmoji.Top = $y + 1
$days.Controls.Add($daysEmoji)
$y += 60
# ---- Subsection 2: Interval Runs ----
$sub2 = New-Object Windows.Forms.Label
$sub2.Text = "● Interval Runs"
$sub2.Font = $FONT_LABEL
$sub2.ForeColor = [Drawing.Color]::FromArgb(191,90,242)
$sub2.AutoSize = $true
$sub2.Left = 10
$sub2.Top = $y
$days.Controls.Add($sub2)
$y += 30
$maxRuns = SpinRow $days "⏳ Max Runs / Session:" $config.MAX_RUNS 0 99 $y
AddEmoji $days "🔄" $maxRuns
$y += 15
# ---- Subsection 3: Scripts Fixed Commands In/Out LOOP (ON/OFF) ----
$y += 20
$subFixed = New-Object Windows.Forms.Label
$subFixed.Text = "● Scripts Fixed Commands In/Out LOOP"
$subFixed.Font = $FONT_LABEL
$subFixed.ForeColor = [Drawing.Color]::FromArgb(191,90,242)
$subFixed.AutoSize = $true
$subFixed.Left = 10
$subFixed.Top = $y
$days.Controls.Add($subFixed)
$y += 30
# Custom label
$fixedCycleLabel = New-Object Windows.Forms.Label
$fixedCycleLabel.AutoSize = $true
$fixedCycleLabel.Font = $FONT_LABEL
$fixedCycleLabel.ForeColor = [Drawing.Color]::White
$fixedCycleLabel.Left = 10
$fixedCycleLabel.Top = $y
$days.Controls.Add($fixedCycleLabel)
# Toggle button
$fixedCycleToggle = New-Object Windows.Forms.Button
$fixedCycleToggle.Width  = 90
$fixedCycleToggle.Height = 30
$fixedCycleToggle.Left   = 380
$fixedCycleToggle.Top    = $y - 5
$fixedCycleToggle.Font   = $FONT_BUTTON
$fixedCycleToggle.ForeColor = [Drawing.Color]::White
$fixedCycleToggle.FlatStyle = 'Flat'
$fixedCycleToggle.FlatAppearance.BorderSize = 0
# ON = false in JSON, OFF = true in JSON
Set-ToggleState $fixedCycleToggle (-not [bool]$config.FIXED_NO_BLOCK_CYCLE)
# Dynamic label
if ($fixedCycleToggle.Text -eq "ON") {
    $fixedCycleLabel.Text = "🔄 Fixed Commands is In (Loop):"
}
else {
    $fixedCycleLabel.Text = "🔀 Fixed Commands is Out (Loop):"
}
$fixedCycleToggle.Add_Click({
    $newState = ($this.Text -eq "OFF")
    Set-ToggleState $this $newState
    if ($this.Text -eq "ON") {
        $fixedCycleLabel.Text = "🔄 Fixed Commands is In (Loop):"
    }
    else {
        $fixedCycleLabel.Text = "🔀 Fixed Commands is Out (Loop):"
    }
    Mark-Dirty
})
Set-ModernButton $fixedCycleToggle
$days.Controls.Add($fixedCycleToggle)
AddEmoji $days "🔄" $fixedCycleToggle
$y += 15 
# ---- Subsection 3: Telegram Bot Toggles ----
$y += 30  
$sub3 = New-Object Windows.Forms.Label
$sub3.Text = "● Telegram Bots"
$sub3.Font = $FONT_LABEL
$sub3.ForeColor = [Drawing.Color]::FromArgb(191,90,242)
$sub3.AutoSize = $true
$sub3.Left = 10
$sub3.Top = $y
$days.Controls.Add($sub3)
$y += 30
# AutoPilot Telegram Toggle
$autoPilotToggle = ToggleRow $days "💎 AutoPilot Telegram Bot (Enable/Disable):" $config.AUTOPILOT_TELEGRAM_ENABLED $y
AddEmoji $days "🔵" $autoPilotToggle
$y += $spacing
# Media Telegram Toggle
$mediaToggle = ToggleRow $days "💎 Media Telegram Bot (Enable/Disable):" $config.MEDIA_TELEGRAM_ENABLED $y
AddEmoji $days "🔵" $mediaToggle
$y += $spacing
AddFooterLine $days "● Specify the days you want AutoPilot to run.
● In the Interview Run section, set the number of repetitions.
● Scripts Fixed Commands In/Out LOOP (ON/OFF).
● Choose a number from 0 to 99, where 0 means an unlimited number of repetitions.
● Use the AutoPilot without the *AutoPilot Bot* and *Media Bot* using the On/Off buttons."

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

# ================= GLOBAL SAVE BUTTON =================
$save = New-Object Windows.Forms.Button
$save.Text = "💾 Save Configuration"
$save.Font = $FONT_BUTTON
$save.Width = 200
$save.Height = 44
$save.BackColor = $ACCENTS.telegram
$save.ForeColor = [Drawing.Color]::White
Set-ModernButton $save
$buttonBar.Controls.Add($save)

# ================= SAVE =================
$save.Add_Click({
    # Telegram / Bot
	$config.TELEGRAM_BOT_TOKEN = ($t1.Text -replace '\r|\n','').Trim()
	$config.TELEGRAM_CHAT_ID   = ($t2.Text -replace '\r|\n','').Trim()
	$config.OWNER_ID           = ($t3.Text -replace '\r|\n','').Trim()
	$config.OWNER_IDS = @(
		($t4.Text -replace '\r|\n','').Split(",") |
		ForEach-Object { $_.Trim() } |
		Where-Object { $_ -ne "" }
	)
	$config.BOT_TOKEN       = ($t5.Text -replace '\r|\n','').Trim()
	$config.CHAT_ID         = ($t6.Text -replace '\r|\n','').Trim()
	$config.MEDIA_FOLDER_URL= ($t7.Text -replace '\r|\n','').Trim()
	$config.AUTOPILOT_URL   = ($t8.Text -replace '\r|\n','').Trim()
	# Telegram Toggles
    $config.AUTOPILOT_TELEGRAM_ENABLED = ($autoPilotToggle.Text -eq "ON")
    $config.MEDIA_TELEGRAM_ENABLED     = ($mediaToggle.Text -eq "ON")
	# Scripts Fixed Commands In/Out LOOP (ON/OFF)
    $config.FIXED_NO_BLOCK_CYCLE = -not ($fixedCycleToggle.Text -eq "ON")
	# Pro / Test Mode
	$config.ENABLE_RESTART  = ($proTestBtn.Text -eq "PRO")
	$config.ENABLE_SHUTDOWN = ($proTestBtn.Text -eq "PRO")
    # Limits
    $config.CPU_LIMIT = $cpuL.Value
    $config.CPU_TEMP_CRITICAL_LIMIT = $cpuT.Value
    $config.DISK_LIMIT = $diskL.Value
    $config.DISK_TEMP_CRITICAL_LIMIT = $diskT.Value
    $config.MB_LIMIT = $mbL.Value
    $config.MB_TEMP_CRITICAL_LIMIT = $mbT.Value
    # Critical / Alarms
    $config.GPU_LIMIT = $gpuL.Value
    $config.GPU_TEMP_CRITICAL_LIMIT = $gpuT.Value
    $config.RAM_USAGE_ALARM_LIMIT = $ramA.Value
    $config.RAM_USAGE_CRITICAL_LIMIT = $ramC.Value
    $config.CPU_LOAD_ALARM_LIMIT = $cpuLA.Value
    $config.CPU_LOAD_CRITICAL_LIMIT = $cpuLC.Value
    # Hardware
    $config.HardwareMonitor.SampleIntervalSeconds=$sample.Value
    $config.TEMP_CHECK_INTERVAL=$tempI.Value
    $config.AUTO_START_MONITORING=($autoM.Text -eq "ON")
    $config.TRAFFIC_MONITOR_AUTO_START=($traffic.Text -eq "ON")
    # Screen & Camera
    $config.ScreenCapture.AudioDevice = ($sAudio.Text -replace '\r|\n','').Trim()
	$config.CameraCapture.VideoDevice = ($cVideo.Text -replace '\r|\n','').Trim()
	$config.CameraCapture.AudioDevice = ($cAudio.Text -replace '\r|\n','').Trim()
    $config.ScreenCapture.IncludeAudio = ($incl.Text -eq "ON")
    # Days
    $config.ALLOWED_DAYS=@()
    foreach($k in $dayButtons.Keys){
        if($dayButtons[$k].BackColor -eq [Drawing.Color]::FromArgb(48,209,88)){
            $config.ALLOWED_DAYS+=$k
        }
    }
    $config.MAX_RUNS=$maxRuns.Value
    # Save to JSON
    $config | ConvertTo-Json -Depth 5 | Set-Content $jsonPath -Encoding UTF8
    [Windows.Forms.MessageBox]::Show("✔️ Configuration saved successfully!")
    $script:HasUnsavedChanges = $false
})

# ================= DEFAULT BUTTON =================
$defaultBtn = New-Object Windows.Forms.Button;$defaultBtn.Text="☑️ Default";$defaultBtn.Font=New-Object Drawing.Font("Segoe UI Emoji",12,[Drawing.FontStyle]::Bold);$defaultBtn.Width=200;$defaultBtn.Height=44;$defaultBtn.BackColor=[Drawing.Color]::FromArgb(48,209,88);$defaultBtn.ForeColor=[Drawing.Color]::White;
Set-ModernButton $defaultBtn
$buttonBar.Controls.Add($defaultBtn)

$defaultBtn.Add_Click({
    $defaultPath = "$AppRoot\JSON\settings_default.json"
    if (-not (Test-Path $defaultPath)) {
        [Windows.Forms.MessageBox]::Show("settings_default not found!","Error")
        return
    }
    try {
        $def = Get-Content $defaultPath -Raw | ConvertFrom-Json
    } catch {
        [Windows.Forms.MessageBox]::Show("settings_default is invalid or corrupted.","⚠️ Fatal Error")
        return
    }
    if (-not $def) {
        [Windows.Forms.MessageBox]::Show("settings_default is empty or invalid.","⚠️ Fatal Error")
        return
    }
    # ---------- Telegram / Bot ----------
    $t1.Text = $def.TELEGRAM_BOT_TOKEN
    $t2.Text = $def.TELEGRAM_CHAT_ID
    $t3.Text = $def.OWNER_ID
    $t4.Text = ($def.OWNER_IDS -join ",")
    $t5.Text = $def.BOT_TOKEN
    $t6.Text = $def.CHAT_ID
    $t7.Text = $def.MEDIA_FOLDER_URL
    $t8.Text = $def.AUTOPILOT_URL
	# ---------- Telegram Bots ----------
	Set-ToggleState $autoPilotToggle $def.AUTOPILOT_TELEGRAM_ENABLED
    Set-ToggleState $mediaToggle     $def.MEDIA_TELEGRAM_ENABLED
	# ---------- Scripts Fixed Commands In/Out LOOP (ON/OFF) ----------
    Set-ToggleState $fixedCycleToggle (-not [bool]$def.FIXED_NO_BLOCK_CYCLE)
	# ---------- Pro / Test Mode ----------
	if ($def.ENABLE_RESTART -and $def.ENABLE_SHUTDOWN) {
		$proTestBtn.Text = "PRO"
		$proTestBtn.BackColor = [Drawing.Color]::FromArgb(48,209,88)
	} else {
		$proTestBtn.Text = "TEST"
		$proTestBtn.BackColor = [Drawing.Color]::FromArgb(255,69,58)
	}
    # ---------- Limits ----------
    $cpuL.Value = $def.CPU_LIMIT
    $cpuT.Value = $def.CPU_TEMP_CRITICAL_LIMIT
    $diskL.Value = $def.DISK_LIMIT
    $diskT.Value = $def.DISK_TEMP_CRITICAL_LIMIT
    $mbL.Value = $def.MB_LIMIT
    $mbT.Value = $def.MB_TEMP_CRITICAL_LIMIT
    # ---------- Critical / Alarms ----------
    $gpuL.Value = $def.GPU_LIMIT
    $gpuT.Value = $def.GPU_TEMP_CRITICAL_LIMIT
    $ramA.Value = $def.RAM_USAGE_ALARM_LIMIT
    $ramC.Value = $def.RAM_USAGE_CRITICAL_LIMIT
    $cpuLA.Value = $def.CPU_LOAD_ALARM_LIMIT
    $cpuLC.Value = $def.CPU_LOAD_CRITICAL_LIMIT
    # ---------- Hardware ----------
    $sample.Value = $def.HardwareMonitor.SampleIntervalSeconds
    $tempI.Value  = $def.TEMP_CHECK_INTERVAL
    Set-ToggleState $autoM   $def.AUTO_START_MONITORING
    Set-ToggleState $traffic $def.TRAFFIC_MONITOR_AUTO_START
    # ---------- Screen & Camera ----------
    Set-ToggleState $incl $def.ScreenCapture.IncludeAudio
    $sAudio.Text = $def.ScreenCapture.AudioDevice
    $cVideo.Text = $def.CameraCapture.VideoDevice
    $cAudio.Text = $def.CameraCapture.AudioDevice
    # ---------- Allowed Days ----------
    foreach($k in $dayButtons.Keys){
        if($def.ALLOWED_DAYS -contains $k){
            $dayButtons[$k].BackColor = [Drawing.Color]::FromArgb(48,209,88)
        } else {
            $dayButtons[$k].BackColor = [Drawing.Color]::FromArgb(255,69,58)
        }
    }
    # ---------- Max Runs ----------
    $maxRuns.Value = $def.MAX_RUNS
    # Auto save after applying defaults
    $save.PerformClick()
    $script:HasUnsavedChanges = $false
})

# ================= RESET + AUTOSAVE BUTTON =================
$resetBtn = New-Object Windows.Forms.Button
$resetBtn.Text = "⚠️ Reset"
$resetBtn.Font = New-Object Drawing.Font("Segoe UI Emoji",12,[Drawing.FontStyle]::Bold)
$resetBtn.Width = 200
$resetBtn.Height = 44
$resetBtn.BackColor = [Drawing.Color]::FromArgb(255,69,58)   # црвена (danger)
$resetBtn.ForeColor = [Drawing.Color]::White
Set-ModernButton $resetBtn
$buttonBar.Controls.Add($resetBtn)

$resetBtn.Add_Click({
    if ([Windows.Forms.MessageBox]::Show(
        "This will RESET all settings and SAVE immediately.`nAre you sure?",
        "Confirm Reset",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning
    ) -ne "Yes") { return }
    # ---------- Text fields ----------
    $t1.Text="";$t2.Text="";$t3.Text="";$t4.Text=""
    $t5.Text="";$t6.Text="";$t7.Text="";$t8.Text=""
	# ---------- RESET BOT URLs (NEW LINES) ----------
	$config.MEDIA_FOLDER_URL   = "https://t.me/Your_Bot"
	$config.AUTOPILOT_URL      = "https://t.me/Your_Bot"
	# update the GUI labels
	$t7.Text = $config.MEDIA_FOLDER_URL
	$t8.Text = $config.AUTOPILOT_URL
	# ---------- Telegram Bots ----------
	Set-ToggleState $autoPilotToggle $false
    Set-ToggleState $mediaToggle     $false
	# ---------- Scripts Fixed Commands In/Out LOOP (ON/OFF) ----------
    Set-ToggleState $fixedCycleToggle $true
	# ---------- Pro / Test Mode ----------
	$proTestBtn.Text = "TEST"
	$proTestBtn.BackColor = [Drawing.Color]::FromArgb(255,69,58)
	$config.ENABLE_RESTART  = $false
	$config.ENABLE_SHUTDOWN = $false
    # ---------- Limits ----------
    $cpuL.Value=$cpuL.Minimum
    $cpuT.Value=80              # CPU Temp Critical Limit
    $diskL.Value=$diskL.Minimum
    $diskT.Value=80              # Disk Temp Critical Limit
    $mbL.Value=$mbL.Minimum
    $mbT.Value=80               # MB Temp Critical Limit
    # ---------- Critical / Alarms ----------
    $gpuL.Value=$gpuL.Minimum
    $gpuT.Value=80               # GPU Temp Critical Limit
    $ramA.Value=$ramA.Minimum
    $ramC.Value=80               # RAM Usage Critical Limit
    $cpuLA.Value=$cpuLA.Minimum
    $cpuLC.Value=80              # CPU Load Critical Limit
    # ---------- Hardware ----------
    if ($sample.Tag) { $sample.Value = 0 }
    if ($tempI.Tag)  { $tempI.Value  = 0 }
    Set-ToggleState $autoM   $false
    Set-ToggleState $traffic $false
    # ---------- Screen & Camera ----------
    Set-ToggleState $incl $false
    $sAudio.Text="Audio"
    $cVideo.Text="Camera"
    $cAudio.Text="Microphone"
    # ---------- Allowed Days ----------
    foreach($k in $dayButtons.Keys){
        $dayButtons[$k].BackColor = [Drawing.Color]::FromArgb(255,69,58)
    }
    # ---------- Max Runs ----------
    $maxRuns.Value = 1
    # ---------- Auto Save ----------
    $save.PerformClick()
    $script:HasUnsavedChanges = $false
})

# ================= RECOVERY (BACKUP / RESTORE / DELETE) =================
# Backups are plain copies of JSON\settings.json stored in JSON\Backups\<name>.json
$backupDir = "$AppRoot\JSON\Backups"
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
    $accent.Dock = 'Top'; $accent.Height = 5; $accent.BackColor = $ACCENTS.days
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

# ---------- Create backup of the currently SAVED settings.json ----------
function New-SettingsBackup {
    if (-not (Test-Path -LiteralPath $jsonPath)) {
        [void](Show-Msg "settings.json was not found." "Backup" 'OK' 'Error')
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
function Set-SpinSafe($n, $v) {
    if ($null -eq $v) { return }
    $n.Value = [Math]::Min($n.Maximum, [Math]::Max($n.Minimum, [decimal]$v))
}
function Set-ToggleSafe($b, $v) {
    if ($null -eq $v) { return }
    Set-ToggleState $b ([bool]$v)
}
function Load-GuiFromConfig($c) {
    # Telegram / Bot
    $t1.Text = [string]$c.TELEGRAM_BOT_TOKEN
    $t2.Text = [string]$c.TELEGRAM_CHAT_ID
    $t3.Text = [string]$c.OWNER_ID
    $t4.Text = (@($c.OWNER_IDS) -join ",")
    $t5.Text = [string]$c.BOT_TOKEN
    $t6.Text = [string]$c.CHAT_ID
    $t7.Text = [string]$c.MEDIA_FOLDER_URL
    $t8.Text = [string]$c.AUTOPILOT_URL
    Set-ToggleSafe $autoPilotToggle $c.AUTOPILOT_TELEGRAM_ENABLED
    Set-ToggleSafe $mediaToggle     $c.MEDIA_TELEGRAM_ENABLED
    # Fixed Commands In/Out LOOP (ON = FIXED_NO_BLOCK_CYCLE false)
    Set-ToggleState $fixedCycleToggle (-not [bool]$c.FIXED_NO_BLOCK_CYCLE)
    if ($fixedCycleToggle.Text -eq "ON") { $fixedCycleLabel.Text = "🔄 Fixed Commands is In (Loop):" }
    else { $fixedCycleLabel.Text = "🔀 Fixed Commands is Out (Loop):" }
    # Pro / Test
    if ($c.ENABLE_RESTART -and $c.ENABLE_SHUTDOWN) {
        $proTestBtn.Text = "PRO";  $proTestBtn.BackColor = [Drawing.Color]::FromArgb(48,209,88)
    } else {
        $proTestBtn.Text = "TEST"; $proTestBtn.BackColor = [Drawing.Color]::FromArgb(255,69,58)
    }
    & $updateProEmoji
    # Limits / Alarms
    Set-SpinSafe $cpuL  $c.CPU_LIMIT;               Set-SpinSafe $cpuT  $c.CPU_TEMP_CRITICAL_LIMIT
    Set-SpinSafe $diskL $c.DISK_LIMIT;              Set-SpinSafe $diskT $c.DISK_TEMP_CRITICAL_LIMIT
    Set-SpinSafe $mbL   $c.MB_LIMIT;                Set-SpinSafe $mbT   $c.MB_TEMP_CRITICAL_LIMIT
    Set-SpinSafe $gpuL  $c.GPU_LIMIT;               Set-SpinSafe $gpuT  $c.GPU_TEMP_CRITICAL_LIMIT
    Set-SpinSafe $ramA  $c.RAM_USAGE_ALARM_LIMIT;   Set-SpinSafe $ramC  $c.RAM_USAGE_CRITICAL_LIMIT
    Set-SpinSafe $cpuLA $c.CPU_LOAD_ALARM_LIMIT;    Set-SpinSafe $cpuLC $c.CPU_LOAD_CRITICAL_LIMIT
    # Hardware
    Set-SpinSafe $sample $c.HardwareMonitor.SampleIntervalSeconds
    Set-SpinSafe $tempI  $c.TEMP_CHECK_INTERVAL
    Set-ToggleSafe $autoM   $c.AUTO_START_MONITORING
    Set-ToggleSafe $traffic $c.TRAFFIC_MONITOR_AUTO_START
    # Screen & Camera
    Set-ToggleSafe $incl $c.ScreenCapture.IncludeAudio
    $sAudio.Text = [string]$c.ScreenCapture.AudioDevice
    $cVideo.Text = [string]$c.CameraCapture.VideoDevice
    $cAudio.Text = [string]$c.CameraCapture.AudioDevice
    # Allowed days / runs
    foreach ($k in $dayButtons.Keys) {
        if (@($c.ALLOWED_DAYS) -contains $k) { $dayButtons[$k].BackColor = [Drawing.Color]::FromArgb(48,209,88) }
        else { $dayButtons[$k].BackColor = [Drawing.Color]::FromArgb(255,69,58) }
    }
    Set-SpinSafe $maxRuns $c.MAX_RUNS
}

# ---------- Restore: overwrite settings.json with the selected backup ----------
function Restore-SettingsBackup($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        [void](Show-Msg "This backup file no longer exists." "Restore" 'OK' 'Warning')
        Refresh-BackupList
        return
    }
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    if ((Show-Msg "Restore backup '$name'?`nThe current settings.json will be OVERWRITTEN." "Restore Backup" 'YesNo' 'Warning') -ne 'Yes') { return }
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
            $num.ForeColor = $ACCENTS.days
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
            $btnRestore.BackColor = $ACCENTS.telegram
            $btnRestore.ForeColor = [Drawing.Color]::White
            $btnRestore.Tag = $f.FullName
            Set-ModernButton $btnRestore
            $btnRestore.Add_Click({ Restore-SettingsBackup $this.Tag })

            $btnDelete = New-Object Windows.Forms.Button
            $btnDelete.Text = "🗑 Delete"
            $btnDelete.Font = $FONT_POPUP
            $btnDelete.Dock = 'Fill'
            $btnDelete.Margin = New-Object Windows.Forms.Padding(4,9,4,9)
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
    $dlg.Text = "Recovery - Settings Backups"
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
    $accent.Dock = 'Top'; $accent.Height = 5; $accent.BackColor = $ACCENTS.days
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
$recoveryBtn.BackColor = $ACCENTS.days
$recoveryBtn.ForeColor = [Drawing.Color]::White
Set-ModernButton $recoveryBtn
$buttonBar.Controls.Add($recoveryBtn)
$recoveryBtn.Add_Click({ Show-RecoveryDialog })

# ================= BUTTON BAR LAYOUT (centered row at the bottom) =================
function Update-ButtonBar {
    $btns = @($save, $defaultBtn, $resetBtn, $recoveryBtn)
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
$buttonBarAccent.BackColor = $ACCENTS.telegram
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

################################################################################################## Settings End.