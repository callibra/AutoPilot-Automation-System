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
$BG = [Drawing.Color]::FromArgb(18,18,18)
$SECTION = [Drawing.Color]::FromArgb(30,30,30)
$COLOR_TEXT = [Drawing.Color]::White

$ACCENTS = @{
    docker    = [Drawing.Color]::FromArgb(10,132,255)
    swap      = [Drawing.Color]::FromArgb(54,189,138)
	network   = [Drawing.Color]::FromArgb(255,159,10)
    demo1     = [Drawing.Color]::FromArgb(230,230,71)
	demo2     = [Drawing.Color]::FromArgb(100,210,255)
    demo3     = [Drawing.Color]::FromArgb(191,90,242)
}

$FONT_SECTION = New-Object Drawing.Font("Segoe UI",14,[Drawing.FontStyle]::Bold)
$FONT_LABEL   = New-Object Drawing.Font("Segoe UI",12)
$FONT_ENTRY   = New-Object Drawing.Font("Segoe UI",12,[Drawing.FontStyle]::Bold)
$FONT_BUTTON  = New-Object Drawing.Font("Segoe UI",12,[Drawing.FontStyle]::Bold)

# ================= ROOT FORM =================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Scripts Settings"
$form.WindowState = "Maximized"
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
    $p.BorderStyle = 'FixedSingle'
    $p.Width = 550
    $p.Height = 488
    $bar = New-Object Windows.Forms.Panel
    $bar.Height = 5
    $bar.Dock = 'Top'
    $bar.BackColor = $accent
    $p.Controls.Add($bar)
    $l = New-Object Windows.Forms.Label
    $l.Text = $title
    $l.Font = $FONT_SECTION
    $l.ForeColor = $textColor   # <--- Овде задаваме различна боја
    $l.AutoSize = $true
    $l.Top = 10
    $l.Left = 10
    $p.Controls.Add($l)
    return $p
}

function LabelText($parent,$text,$top) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Font = $FONT_LABEL; $l.ForeColor = $COLOR_TEXT
    $l.AutoSize = $true; $l.Left = 10; $l.Top = $top
    $parent.Controls.Add($l)
}

function TextBoxRow($parent,$label,$value,$top) {
    LabelText $parent $label $top
    $t = New-Object Windows.Forms.TextBox
    $t.Text = $value; $t.Left = 180; $t.Top = $top-3; $t.Width = 300
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
$grid.RowCount    = 2
$grid.CellBorderStyle = 'None'
$grid.Left = 10
$grid.Top  = 10

# ✅ Колони
for ($i=0; $i -lt $grid.ColumnCount; $i++) {
    $colStyle = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.33)
    $grid.ColumnStyles.Add($colStyle) | Out-Null
}

# ✅ Редови
for ($i=0; $i -lt $grid.RowCount; $i++) {
    $rowStyle = New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50)
    $grid.RowStyles.Add($rowStyle) | Out-Null
}

$scrollPanel.Controls.Add($grid)

# ================= CREATE SECTIONS =================
$dockerCore   = Section "Docker Script"      $ACCENTS.docker $ACCENTS.docker
$swap         = Section "SetDocker Script"   $ACCENTS.swap   $ACCENTS.swap
$network      = Section "Network Script"     $ACCENTS.network  $ACCENTS.network
$demo1        = Section "Net Traffic Script" $ACCENTS.demo1  $ACCENTS.demo1
$demo2        = Section "Cleaner Script"     $ACCENTS.demo2  $ACCENTS.demo2
$demo3        = Section "Power Plan Script"  $ACCENTS.demo3  $ACCENTS.demo3

$grid.Controls.Add($dockerCore, 0,0)
$grid.Controls.Add($swap, 1,0)
$grid.Controls.Add($network, 2,0)
$grid.Controls.Add($demo1, 0,1)
$grid.Controls.Add($demo2, 1,1)
$grid.Controls.Add($demo3, 2,1)

# ================= ALIAS ================
$docker = $dockerCore

# ================= DOCKER SECTION =================
$y=50; $spacing=40
$tDockerPath = TextBoxRow $docker "Docker Path:" $config.DockerPath $y; $y+=$spacing
$tDockerCli  = TextBoxRow $docker "Docker CLI Path:" $config.DockerCliPath $y; $y+=$spacing
$tContainers = TextBoxRow $docker "Containers:" ($config.Containers -join ",") $y; $y+=$spacing
AddFooterLine $docker "* Set Docker executable paths and container names for Docker Script.
* If you install Docker using its default path, then use the *DEFAULT BUTTON*.
* If you are using a custom path, meaning you installed it on a different drive, then use the *DEFAULT CUSTOM BATTON* and replace it with your drive and folder where Docker is located.
* This is used either to install Docker on your custom path or to use the default path.
* If you are using the default Docker path, then don’t change anything in the label. But if you are using your custom path, then just replace the drive *example:(E:, C:, D:) and the folder if you installed Docker in a different folder, *example: E:\Miner or E:\MyDockerFolder.
* The rest of the label stays the same; dont change it."

# ================= SET DOCKER SECTION =================
$y=50
$tDockerDesktop = TextBoxRow $swap "Docker Desktop Path:" $config.DockerDesktopPath $y; $y+=$spacing
$tSwapFolder    = TextBoxRow $swap "Swap Folder Path:" $config.SwapFolderPath $y; $y+=$spacing
AddFooterLine $swap "* Set Docker Desktop and Swap folder paths.
* If you install Docker using its default path, then use the *DEFAULT BUTTON*.
* If you are using a custom path, meaning you installed it on a different drive, then use the *DEFAULT CUSTOM BATTON* and replace it with your drive and folder where Docker is located.
* This is used to set Docker to use your custom hardware resources and either use your custom path for it or keep its default path.
* If you are using the default Docker path, then don’t change anything in the label. But if you are using your custom path, then just replace the drive *example:(E:, C:, D:) and the folder if you installed Docker in a different folder, *example: E:\Miner or E:\MyDockerFolder.
* The rest of the label stays the same; dont change it.
* In the line *Swap Folder Path* change the %USERNAME% with your custom pc name example C:\Users\ASUS\AppData\Local\Docker\wsl\data or Your custom path example like this E:\Miner\WSLSwap."

# ================= NETWORK SECTION =================
$y = 50
$spacing = 60  # larger spacing for visual clarity
# --- Wi-Fi Names ---
$txtWifi1 = TextBoxRow $network "WiFi 1 SSID:" $config.wifi1 $y
$y += $spacing
$txtWifi2 = TextBoxRow $network "WiFi 2 SSID:" $config.wifi2 $y
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
$lblTendaToBeni.Text = "WiFi 1 switch to WiFi 2 (Hours:Min):"
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

$nudTendaHour = New-TimeSpinner $network 330 $y $tHourValue 23
$nudTendaMin  = New-TimeSpinner $network 410 $y $tMinValue 59

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
$lblBeniToTenda.Text = "WiFi 2 switch to WiFi 1 (Hours:Min):"
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

$nudBeniHour = New-TimeSpinner $network 330 $y $bHourValue 23
$nudBeniMin  = New-TimeSpinner $network 410 $y $bMinValue 59

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
AddFooterLine $network "* Edit Wi-Fi SSID and Times using the arrow spinners.
* Use this SETTINGS to switch from one Wi-Fi network to another at a specific time by creating a task FOR automatically switch or manually from a Telegram Bot Chat message.
* Use the DEFAULT CUSTOM Batton as an example of how this should be configured.
* If the correct Wi-Fi SSID and the configured time for the switch are not entered, this will not work without these values.
* You can create an unlimited number of tasks that can be deleted from Network Script or from Telegram Bot Chat messages.
* This TASK are valid and executed every day at the same time.."

# ================= Demo 1 =================
$lblDemo1 = New-Object Windows.Forms.Label
$lblDemo1.Text = " - No SETTINGS for Editing for Net Traffic Script."
$lblDemo1.Font = $FONT_LABEL
$lblDemo1.ForeColor = [Drawing.Color]::White
$lblDemo1.AutoSize = $true
$lblDemo1.Left = 10
$lblDemo1.Top = 50
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
AddFooterLine $demo1 "* No SETTINGS for Editing for Net Traffic Script."

# ================= Demo 2 =================
$lblDemo2 = New-Object Windows.Forms.Label
$lblDemo2.Text = " - No SETTINGS for Editing for Cleaner Script."
$lblDemo2.Font = $FONT_LABEL
$lblDemo2.ForeColor = [Drawing.Color]::White
$lblDemo2.AutoSize = $true
$lblDemo2.Left = 10
$lblDemo2.Top = 50
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
AddFooterLine $demo2 "* No SETTINGS for Editing for Cleaner Script."

# ================= Demo 3 =================
$lblDemo3 = New-Object Windows.Forms.Label
$lblDemo3.Text = " - No SETTINGS for Editing for Power Plan Script."
$lblDemo3.Font = $FONT_LABEL
$lblDemo3.ForeColor = [Drawing.Color]::White
$lblDemo3.AutoSize = $true
$lblDemo3.Left = 10
$lblDemo3.Top = 50
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
AddFooterLine $demo3 "* No SETTINGS for Editing for Power Plan Script."

# ================= SAVE BUTTON =================
$save = New-Object Windows.Forms.Button
$save.Text = "Save Configuration"
$save.Font = $FONT_BUTTON
$save.Width = 200
$save.Height = 45
$save.BackColor = $ACCENTS.docker
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

$save.Add_Click({
    $config.DockerPath = $tDockerPath.Text
    $config.DockerCliPath = $tDockerCli.Text
    $config.Containers = @($tContainers.Text.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    $config.DockerDesktopPath = $tDockerDesktop.Text
    $config.SwapFolderPath = $tSwapFolder.Text
	# --- Wi-Fi / Task Settings ---
	$config.wifi1 = $txtWifi1.Text
	$config.wifi2 = $txtWifi2.Text
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
    [Windows.Forms.MessageBox]::Show("Configuration saved successfully!")
    $script:HasUnsavedChanges = $false
})

# ================= DEFAULT BUTTON =================
$defaultBtn = New-Object Windows.Forms.Button
$defaultBtn.Text="Default"
$defaultBtn.Font=$FONT_BUTTON
$defaultBtn.Width=200
$defaultBtn.Height=40
$defaultBtn.BackColor=[Drawing.Color]::FromArgb(48,209,88)
$defaultBtn.ForeColor=[Drawing.Color]::White
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
    if ($defaultProfiles.Count -lt 1) {
        [Windows.Forms.MessageBox]::Show("Factory default not found!","Error")
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
$customBtn.Text="Default Custom"
$customBtn.Font=$FONT_BUTTON
$customBtn.Width=200
$customBtn.Height=40
$customBtn.BackColor=[Drawing.Color]::FromArgb(182,42,184)
$customBtn.ForeColor=[Drawing.Color]::White
$scrollPanel.Controls.Add($customBtn)
$form.Add_Shown({
    $gapFromGrid   = 5    # растојание од grid-от
    $bottomMargin  = 15   # растојание од долниот раб на grid
    $gap           = 10   # растојание помеѓу копчиња

    # Позиционирање на Custom (над Default)
    $customBtn.Left = $save.Left
    $customBtn.Top  = $defaultBtn.Top - $customBtn.Height - $gap

})

$customBtn.Add_Click({
    if ($defaultProfiles.Count -lt 2) {
        [Windows.Forms.MessageBox]::Show("Custom default not found!","Error")
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
$resetBtn.Text = "Reset"
$resetBtn.Font=$FONT_BUTTON
$resetBtn.Width=200
$resetBtn.Height=40
$resetBtn.BackColor=[Drawing.Color]::FromArgb(255,69,58)
$resetBtn.ForeColor=[Drawing.Color]::White
$scrollPanel.Controls.Add($resetBtn)
$form.Add_Shown({
    $gapFromGrid   = 5    # растојание од grid-от
    $bottomMargin  = 15   # растојание од долниот раб на grid
    $gap           = 10   # растојание помеѓу копчиња

    # Позиционирање на Reset (над Custom)
    $resetBtn.Left = $save.Left
    $resetBtn.Top  = $customBtn.Top - $resetBtn.Height - $gap
})

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

# ================= FORM CLOSING =================
$form.Add_FormClosing({
    if (-not $script:HasUnsavedChanges) { return }
    $res = [Windows.Forms.MessageBox]::Show(
        "You have unsaved changes.`nDo you want to save before exiting?",
        "Unsaved Changes",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($res -eq [Windows.Forms.DialogResult]::Yes) { $save.PerformClick() }
})

# ================= SHOW FORM =================
[void]$form.ShowDialog()

################################################################################################ Settings Scripts End.