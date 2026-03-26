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
$BG = [Drawing.Color]::FromArgb(18,18,18)
$SECTION = [Drawing.Color]::FromArgb(30,30,30)
$COLOR_TEXT = [Drawing.Color]::White

$ACCENTS = @{
    telegram = [Drawing.Color]::FromArgb(10,132,255)
    limits   = [Drawing.Color]::FromArgb(54,189,138)
    critical = [Drawing.Color]::FromArgb(255,159,10)
    hw       = [Drawing.Color]::FromArgb(230,230,71)
    screen   = [Drawing.Color]::FromArgb(100,210,255)
    days     = [Drawing.Color]::FromArgb(191,90,242)
}

$FONT_SECTION = New-Object Drawing.Font("Segoe UI",14,[Drawing.FontStyle]::Bold)
$FONT_LABEL   = New-Object Drawing.Font("Segoe UI",12)
$FONT_ENTRY   = New-Object Drawing.Font("Segoe UI",12,[Drawing.FontStyle]::Bold)
$FONT_SPIN    = New-Object Drawing.Font("Segoe UI",12,[Drawing.FontStyle]::Bold)
$FONT_BUTTON  = New-Object Drawing.Font("Segoe UI",12,[Drawing.FontStyle]::Bold)

# ================= ROOT FORM =================
$form = New-Object System.Windows.Forms.Form
$form.Text = "AutoPilot Settings"
$form.WindowState = "Maximized"
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
    } | ConvertTo-Json -Depth 5 | Set-Content $jsonPath -Encoding UTF8
}
$config = Get-Content $jsonPath | ConvertFrom-Json

# ================= HELPERS =================
function Section($title,$accent) {
    $p = New-Object Windows.Forms.Panel
    $p.BackColor = $SECTION
    $p.BorderStyle = 'FixedSingle'
    $p.Width = 550
    $p.Height = 488
    $bar = New-Object Windows.Forms.Panel
    $bar.Height = 5; $bar.Dock = 'Top'; $bar.BackColor = $accent
    $p.Controls.Add($bar)
    $l = New-Object Windows.Forms.Label
    $l.Text = $title
    $l.Font = $FONT_SECTION
    $l.ForeColor = $COLOR_TEXT
    $l.AutoSize = $true
    $l.Top = 10; $l.Left = 10
    $p.Controls.Add($l)
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

function Set-ToggleState($btn, $state){
    if ($state) {
        $btn.Text = "ON"
        $btn.BackColor = [Drawing.Color]::FromArgb(48,209,88)
    } else {
        $btn.Text = "OFF"
        $btn.BackColor = [Drawing.Color]::FromArgb(255,69,58)
    }
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

# ================= LAYOUT =================
$grid = New-Object Windows.Forms.TableLayoutPanel
$grid.AutoSize = $true              # Автоматски се ресајзира според содржината
$grid.AutoSizeMode = 'GrowAndShrink'
$grid.ColumnCount = 3
$grid.RowCount = 2
$grid.CellBorderStyle = 'None'
$grid.Left = 10
$grid.Top  = 10

$scrollPanel.Controls.Add($grid)

# ================= CREATE SECTIONS =================
$telegram = Section "Telegram & Bot" $ACCENTS.telegram
$limits   = Section "System Alarms Limits" $ACCENTS.limits
$critical = Section "System Critical Limits" $ACCENTS.critical
$hw       = Section "System Monitoring / Alarms Limits Mode" $ACCENTS.hw
$screen   = Section "Record Screen / Camera" $ACCENTS.screen
$days     = Section "AutoPilot Allowed Days / Runs / Enable Bot" $ACCENTS.days

$grid.Controls.Add($telegram,0,0)
$grid.Controls.Add($limits,1,0)
$grid.Controls.Add($hw,2,1)
$grid.Controls.Add($screen,0,1)
$grid.Controls.Add($days,1,1)
$grid.Controls.Add($critical,2,0)

# ================= TELEGRAM =================
$y=50; $spacing=40
$sub1 = New-Object Windows.Forms.Label; $sub1.Text="*AutoPilot Bot"; $sub1.Font=$FONT_LABEL; $sub1.ForeColor=[Drawing.Color]::FromArgb(10,132,255)
$sub1.AutoSize=$true; $sub1.Left=10; $sub1.Top=$y; $telegram.Controls.Add($sub1); $y+=25
$t1 = TextBoxRow $telegram "Telegram Bot Token:" $config.TELEGRAM_BOT_TOKEN $y; $y+=$spacing
$t2 = TextBoxRow $telegram "Telegram Chat ID:" $config.TELEGRAM_CHAT_ID $y; $y+=$spacing
$t3 = TextBoxRow $telegram "Allowed Owner ID:" $config.OWNER_ID $y; $y+=$spacing
$t8 = TextBoxRow $telegram "Autopilot URL:" $config.AUTOPILOT_URL $y; $y+=$spacing

$sub2 = New-Object Windows.Forms.Label; $sub2.Text="*Media Bot"; $sub2.Font=$FONT_LABEL; $sub2.ForeColor=[Drawing.Color]::FromArgb(10,132,255)
$sub2.AutoSize=$true; $sub2.Left=10; $sub2.Top=$y; $telegram.Controls.Add($sub2); $y+=25
$t5 = TextBoxRow $telegram "Media Bot Token:" $config.BOT_TOKEN $y; $y+=$spacing
$t6 = TextBoxRow $telegram "Media Chat ID:" $config.CHAT_ID $y; $y+=$spacing
$t4 = TextBoxRow $telegram "Allowed Owner IDs (1+):" ($config.OWNER_IDS -join ",") $y; $y+=$spacing
$t7 = TextBoxRow $telegram "Media Folder URL:" $config.MEDIA_FOLDER_URL $y; $y+=$spacing
AddFooterLine $telegram "* Enter your Telegram Token and ID for two BOT Telegram Accounts.
* First Bot Account for AutoPilot and Second Bot Account for Media Folder Editor.
* Enter your Allowed ID. In IDs, you can enter multiple IDs, example: 12345,67890."

# ================= SYSTEM ALARMS =================
$y=50; $spacing=35
$subLimits = New-Object Windows.Forms.Label; $subLimits.Text="*Load and Temperatures Alarms"; $subLimits.Font=$FONT_LABEL; $subLimits.ForeColor=[Drawing.Color]::FromArgb(54,189,138)
$subLimits.AutoSize=$true; $subLimits.Left=10; $subLimits.Top=$y; $limits.Controls.Add($subLimits); $y+=25
$cpuLA = SpinRow $limits "CPU Load (percent):" $config.CPU_LOAD_ALARM_LIMIT 1 150 $y; $y+=$spacing
$ramA = SpinRow $limits "RAM Load (percent):" $config.RAM_USAGE_ALARM_LIMIT 1 100 $y; $y+=$spacing
$mbL = SpinRow $limits "MB Temperature (metric):" $config.MB_LIMIT 1 100 $y; $y+=$spacing
$cpuL = SpinRow $limits "CPU Temperature (metric):" $config.CPU_LIMIT 1 100 $y; $y+=$spacing
$gpuL = SpinRow $limits "GPU Temperature (metric):" $config.GPU_LIMIT 1 100 $y; $y+=$spacing
$diskL = SpinRow $limits "Disk Temperature (metric):" $config.DISK_LIMIT 1 100 $y; $y+=$spacing
AddFooterLine $limits "* Set your Alarms for CPU, RAM and load expressed in percentages.
* Set your Alarms for CPU, GPU, MotherBoard (MB), and Disk temperatures in metric units.
* When any of these parameters are exceeded, you will receive an Alarm notification in Your Telegram Chat."

# ================= SYSTEM LIMITS =================
$y=50; $spacing=35
$subCritical = New-Object Windows.Forms.Label; $subCritical.Text="*Load and Temperatures Limits"; $subCritical.Font=$FONT_LABEL; $subCritical.ForeColor=[Drawing.Color]::FromArgb(255,159,10)
$subCritical.AutoSize=$true; $subCritical.Left=10; $subCritical.Top=$y; $critical.Controls.Add($subCritical); $y+=25
$cpuLC = SpinRow $critical "CPU Load Limit (percent):" $config.CPU_LOAD_CRITICAL_LIMIT 1 200 $y; $y+=$spacing
$ramC = SpinRow $critical "RAM Load Limit (percent):" $config.RAM_USAGE_CRITICAL_LIMIT 1 100 $y; $y+=$spacing
$mbT = SpinRow $critical "MB Temperature Limit (metric):" $config.MB_TEMP_CRITICAL_LIMIT 40 120 $y; $y+=$spacing
$cpuT = SpinRow $critical "CPU Temperature Limit (metric):" $config.CPU_TEMP_CRITICAL_LIMIT 40 120 $y; $y+=$spacing
$gpuT = SpinRow $critical "GPU Temperature Limit (metric):" $config.GPU_TEMP_CRITICAL_LIMIT 40 120 $y; $y+=$spacing
$diskT = SpinRow $critical "Disk Temperature Limit (metric):" $config.DISK_TEMP_CRITICAL_LIMIT 40 120 $y; $y+=$spacing
AddFooterLine $critical "* Set your Limits Alarms for CPU, RAM and load expressed in percentages.
* Set your Limits Alarms for CPU, GPU, MotherBoard (MB), and Disk temperatures in metric units.
* When any of these parameters are exceeded, a safe action will be performed on your PC (restart, shutdown, or restart of the AutoPilot) depending on the duration for which the Alarm has been exceeded."

# ================= SYSTEM MONITORING =================
$y=50; $spacing=40
$sub1 = New-Object Windows.Forms.Label; $sub1.Text="*System Interval"; $sub1.Font=$FONT_LABEL; $sub1.ForeColor=[Drawing.Color]::FromArgb(230,230,71)
$sub1.AutoSize=$true; $sub1.Left=10; $sub1.Top=$y; $hw.Controls.Add($sub1); $y+=25
$sample = SpinRow $hw "System Hardware Monitoring Interval (sec):" $config.HardwareMonitor.SampleIntervalSeconds 60 500 $y; $y+=$spacing
$tempI  = SpinRow $hw "System Alarm Limit Interval (sec):" $config.TEMP_CHECK_INTERVAL 60 500 $y; $y+=$spacing
$sub2 = New-Object Windows.Forms.Label; $sub2.Text="*Monitoring ON / OFF"; $sub2.Font=$FONT_LABEL; $sub2.ForeColor=[Drawing.Color]::FromArgb(230,230,71)
$sub2.AutoSize=$true; $sub2.Left=10; $sub2.Top=$y; $hw.Controls.Add($sub2); $y+=25
$autoM  = ToggleRow $hw "Auto Start System Monitoring:" $config.AUTO_START_MONITORING $y; $y+=$spacing
$traffic = ToggleRow $hw "Auto Start Traffic Monitoring:" $config.TRAFFIC_MONITOR_AUTO_START $y; $y+=$spacing
# ================= Pro / Test Mode =================
# Label for the button
$lblProTest = New-Object Windows.Forms.Label
$lblProTest.Text = "*Alarms Limits Mode (Pro / Test):"
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
# ✅ Set initial state based on JSON (true = Pro, false = Test)
if ($config.ENABLE_RESTART -and $config.ENABLE_SHUTDOWN) {
    $proTestBtn.Text = "PRO"
    $proTestBtn.BackColor = [Drawing.Color]::FromArgb(48,209,88)  # green
} else {
    $proTestBtn.Text = "TEST"
    $proTestBtn.BackColor = [Drawing.Color]::FromArgb(255,69,58)  # red
}
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
    Mark-Dirty
})
$hw.Controls.Add($proTestBtn)
$y += 30
AddFooterLine $hw "* In System Interval, set how often (in seconds) data should be collected for alarm measurements and for recording data in system monitoring.
* The value must be between 60 and 500 seconds.
* In the Auto Start section, choose whether you want the System and Network Traffic Monitoring to Start Automatically when AutoPilot starts, using the ON/OFF buttons.
* If you select PRO Mode then your PC while RESTART or SHUTDOW when the alarms from the setting will be exceeded.
* If you select TEST Mode then your PC while NOT RESTART or SHUTDOW it while only show it is a SIMULATION."

# ================= RECORD SCREEN & CAMERA =================
$y=50; $spacing=40
$sub1 = New-Object Windows.Forms.Label; $sub1.Text="*Screen Record"; $sub1.Font=$FONT_LABEL; $sub1.ForeColor=[Drawing.Color]::FromArgb(100,210,255)
$sub1.AutoSize=$true; $sub1.Left=10; $sub1.Top=$y; $screen.Controls.Add($sub1); $y+=25
$sAudio = TextBoxRow $screen "Screen Audio Device:" $config.ScreenCapture.AudioDevice $y; $y+=$spacing
$incl   = ToggleRow $screen "Include Audio (Turn ON/OFF):" $config.ScreenCapture.IncludeAudio $y; $y+=$spacing
$sub2 = New-Object Windows.Forms.Label; $sub2.Text="*Camera Capture"; $sub2.Font=$FONT_LABEL; $sub2.ForeColor=[Drawing.Color]::FromArgb(100,210,255)
$sub2.AutoSize=$true; $sub2.Left=10; $sub2.Top=$y; $screen.Controls.Add($sub2); $y+=25
$cVideo = TextBoxRow $screen "Camera Video Device:" $config.CameraCapture.VideoDevice $y; $y+=$spacing 
$cAudio = TextBoxRow $screen "Camera Audio Device:" $config.CameraCapture.AudioDevice $y; $y+=$spacing
AddFooterLine $screen "* In the Screen Audio field, enter your Audio Device.
* In the Camera fields, enter your Camera Device and your Camera Audio Device.
* In order to be able to record system sound from the device, you must have *Stereo Mix* enabled in the Sound Settings.
* Use the Include Video button while you want both the Screen Recording and System Audio to be Captured.
* To find your Screen and Camera Audio/Video Devices, enter the following in PowerShell and press Enter:
* C:\AutoPilot\ffmpeg\bin\ffmpeg.exe -list_devices true -f dshow -i dummy"

# ================= DAYS =================
$y = 50
$spacing = 40
# ---- Subsection 1: Allowed Days ----
$sub1 = New-Object Windows.Forms.Label
$sub1.Text = "*Allowed Days"
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
    $days.Controls.Add($b)
    $dayButtons[$d] = $b
    $x += 67
}
$y += 60
# ---- Subsection 2: Interval Runs ----
$sub2 = New-Object Windows.Forms.Label
$sub2.Text = "*Interval Runs"
$sub2.Font = $FONT_LABEL
$sub2.ForeColor = [Drawing.Color]::FromArgb(191,90,242)
$sub2.AutoSize = $true
$sub2.Left = 10
$sub2.Top = $y
$days.Controls.Add($sub2)
$y += 30
$maxRuns = SpinRow $days "Max Runs / Session:" $config.MAX_RUNS 0 10 $y
# ---- Subsection 3: Telegram Bot Toggles ----
$y += 40  
$sub3 = New-Object Windows.Forms.Label
$sub3.Text = "*Telegram Bots"
$sub3.Font = $FONT_LABEL
$sub3.ForeColor = [Drawing.Color]::FromArgb(191,90,242)
$sub3.AutoSize = $true
$sub3.Left = 10
$sub3.Top = $y
$days.Controls.Add($sub3)
$y += 30
# AutoPilot Telegram Toggle
$autoPilotToggle = ToggleRow $days "AutoPilot Telegram Bot (Enable/Disable):" $config.AUTOPILOT_TELEGRAM_ENABLED $y
$y += $spacing
# Media Telegram Toggle
$mediaToggle = ToggleRow $days "Media Telegram Bot (Enable/Disable):" $config.MEDIA_TELEGRAM_ENABLED $y
$y += $spacing
AddFooterLine $days "* Specify the days you want AutoPilot to run.
* In the Interview Run section, set the number of repetitions.
* Choose a number from 0 to 10, where 0 means an unlimited number of repetitions.
* Use the AutoPilot without the *AutoPilot Bot* and *Media Bot* using the On/Off buttons."

# ================= GLOBAL SAVE BUTTON =================
$save = New-Object Windows.Forms.Button
$save.Text = "Save Configuration"
$save.Font = $FONT_BUTTON
$save.Width = 200
$save.Height = 45
$save.BackColor = $ACCENTS.telegram
$save.ForeColor = [Drawing.Color]::White
$scrollPanel.Controls.Add($save)
$form.Add_Shown({
    $gapFromGrid   = 5    # растојание од grid-от
    $bottomMargin  = 15   # растојание од долниот раб на grid
    $gap           = 10   # растојание помеѓу копчиња

    # Позиционирање на Save
    $save.Left = $grid.Right + $gapFromGrid
    $save.Top  = $grid.Bottom - $save.Height - $bottomMargin
})

# ================= SAVE =================
$save.Add_Click({
    # Telegram / Bot
    $config.TELEGRAM_BOT_TOKEN=$t1.Text
    $config.TELEGRAM_CHAT_ID=$t2.Text
    $config.OWNER_ID=$t3.Text
    $config.OWNER_IDS = @($t4.Text.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    $config.BOT_TOKEN=$t5.Text
    $config.CHAT_ID=$t6.Text
    $config.MEDIA_FOLDER_URL=$t7.Text
    $config.AUTOPILOT_URL=$t8.Text
	# Telegram Toggles
    $config.AUTOPILOT_TELEGRAM_ENABLED = ($autoPilotToggle.Text -eq "ON")
    $config.MEDIA_TELEGRAM_ENABLED     = ($mediaToggle.Text -eq "ON")
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
    $config.ScreenCapture.AudioDevice = $sAudio.Text
    $config.CameraCapture.VideoDevice  = $cVideo.Text
    $config.CameraCapture.AudioDevice  = $cAudio.Text
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
    [Windows.Forms.MessageBox]::Show("Configuration saved successfully!")
    $script:HasUnsavedChanges = $false
})

# ================= DEFAULT BUTTON =================
$defaultBtn = New-Object Windows.Forms.Button;$defaultBtn.Text="Default";$defaultBtn.Font=New-Object Drawing.Font("Segoe UI",11,[Drawing.FontStyle]::Bold);$defaultBtn.Width=200;$defaultBtn.Height=40;$defaultBtn.BackColor=[Drawing.Color]::FromArgb(48,209,88);$defaultBtn.ForeColor=[Drawing.Color]::White;
$scrollPanel.Controls.Add($defaultBtn)
$form.Add_Shown({
    $gapFromGrid   = 5    # растојание од grid-от
    $bottomMargin  = 15   # растојание од долниот раб на grid
    $gap           = 10   # растојание помеѓу копчиња

    # Позиционирање на Default (над Save)
    $defaultBtn.Left = $save.Left
    $defaultBtn.Top  = $save.Top - $defaultBtn.Height - $gap

})

$defaultBtn.Add_Click({
    $defaultPath = "$AppRoot\JSON\settings_default.json"
    if (-not (Test-Path $defaultPath)) {
        [Windows.Forms.MessageBox]::Show("settings_default not found!","Error")
        return
    }
    try {
        $def = Get-Content $defaultPath -Raw | ConvertFrom-Json
    } catch {
        [Windows.Forms.MessageBox]::Show("settings_default is invalid or corrupted.","Fatal Error")
        return
    }
    if (-not $def) {
        [Windows.Forms.MessageBox]::Show("settings_default is empty or invalid.","Fatal Error")
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
$resetBtn.Text = "Reset"
$resetBtn.Font = New-Object Drawing.Font("Segoe UI",11,[Drawing.FontStyle]::Bold)
$resetBtn.Width = 200
$resetBtn.Height = 40
$resetBtn.BackColor = [Drawing.Color]::FromArgb(255,69,58)   # црвена (danger)
$resetBtn.ForeColor = [Drawing.Color]::White
$scrollPanel.Controls.Add($resetBtn)
$form.Add_Shown({
    $gapFromGrid   = 5    # растојание од grid-от
    $bottomMargin  = 15   # растојание од долниот раб на grid
    $gap           = 10   # растојание помеѓу копчиња

    # Позиционирање на Reset (над Custom)
    $resetBtn.Left = $save.Left
    $resetBtn.Top  = $defaultBtn.Top - $resetBtn.Height - $gap
})

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

# ================= FORM CLOSING =================
$form.Add_FormClosing({
    if (-not $script:HasUnsavedChanges) { return }
    $res = [Windows.Forms.MessageBox]::Show(
        "You have unsaved changes.`nDo you want to save before exiting?",
        "Unsaved Changes",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning
    )
    switch ($res) {
        'Yes' { $save.PerformClick() }
        'No'  { return }
    }
})

# ================= SHOW FORM =================
[void]$form.ShowDialog()

################################################################################################## Settings End.