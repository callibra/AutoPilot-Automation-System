#Process Control Center - AutoPilot Automtion System
param(
    [switch]$AutoStartMonitor,
    [int]$AutoMonitorHours = -1,
    [int]$AutoMonitorMinutes = -1,
    [int]$AutoMonitorSeconds = -1,
    [int]$AutoPanelHours = -1,
    [int]$AutoPanelMinutes = -1,
    [int]$AutoPanelSeconds = -1
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Management
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:Rules = @{
    PS    = @{ Allowed = @{}; Blocked = @{} }
    Other = @{ Allowed = @{}; Blocked = @{} }
}
# Resolve the application directory. In the packaged build this is the folder
$AppRoot = $null
$runtimeExePath = $null
try { $runtimeExePath = [System.Windows.Forms.Application]::ExecutablePath } catch {}
if (-not [string]::IsNullOrWhiteSpace($runtimeExePath) -and
    [System.IO.Path]::GetFileName($runtimeExePath) -ieq 'ProcessManager.exe') {
    $AppRoot = Split-Path -Parent -Path $runtimeExePath
}
elseif (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    $AppRoot = Split-Path -Parent -Path $PSCommandPath
}
elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $AppRoot = $PSScriptRoot
}
else {
    # Last fallback for hosts that do not expose a script path.
    try {
        $commandLinePath = [Environment]::GetCommandLineArgs()[0]
        if (-not [string]::IsNullOrWhiteSpace($commandLinePath) -and
            [System.IO.Path]::GetFileName($commandLinePath) -ieq 'ProcessManager.exe') {
            $AppRoot = Split-Path -Parent -Path $commandLinePath
        }
    } catch {}
    if ([string]::IsNullOrWhiteSpace($AppRoot)) {
        $AppRoot = [Environment]::CurrentDirectory
    }
}
$AppRoot = [System.IO.Path]::GetFullPath($AppRoot)
$script:AppRoot = $AppRoot
$script:ProcessManagerExePath = Join-Path $AppRoot "ProcessManager.exe"
$script:RulesFile = Join-Path $AppRoot "JSON\Rules.json"
$script:AutoTaskName = 'AutoPilot-ProcessControlCenter'
$script:AutoStartSettingsFile = Join-Path $AppRoot "JSON\AutoStart.json"
$script:ProcessLogDirectory = Join-Path $AppRoot "Autopilot_Data\Process_Logs"
$script:AuditedRuleProcesses = @{}
$script:AutoStartEnabled = $false
$script:AutoStartMonitorRequested = [bool]$AutoStartMonitor
# AUTO START is now an independent saved application preference. TASK ON/OFF
try {
    if (Test-Path -LiteralPath $script:AutoStartSettingsFile -PathType Leaf) {
        $autoSettings = Get-Content -LiteralPath $script:AutoStartSettingsFile -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        $script:AutoStartEnabled = [bool]$autoSettings.Enabled
        if (-not $script:AutoStartMonitorRequested -and $script:AutoStartEnabled) {
            $script:AutoStartMonitorRequested = $true
            if ($null -ne $autoSettings.MonitorHours) { $AutoMonitorHours = [int]$autoSettings.MonitorHours }
            if ($null -ne $autoSettings.MonitorMinutes) { $AutoMonitorMinutes = [int]$autoSettings.MonitorMinutes }
            if ($null -ne $autoSettings.MonitorSeconds) { $AutoMonitorSeconds = [int]$autoSettings.MonitorSeconds }
            if ($null -ne $autoSettings.PanelHours) { $AutoPanelHours = [int]$autoSettings.PanelHours }
            if ($null -ne $autoSettings.PanelMinutes) { $AutoPanelMinutes = [int]$autoSettings.PanelMinutes }
            if ($null -ne $autoSettings.PanelSeconds) { $AutoPanelSeconds = [int]$autoSettings.PanelSeconds }
        }
    }
}
catch {
    $script:AutoStartEnabled = $false
}
$script:AutoStartButton = $null
$script:TaskButton = $null
$script:StartMonitorButton = $null
$script:Running = $false
$script:MonitorUntil = $null
$script:PanelUntil = $null
$script:PanelStopLogged = $true
$script:Busy = $false
$script:ScanActive = $false
$script:ScanWorkerBusy = $false
$script:ShowScanBusyIndicator = $false
$script:ScanBlinkOn = $true
$script:PauseTableRefresh = $false
$script:ExpandedTableWindow = $null
$script:ExpandedTableGrid = $null
$script:ExpandedTableParent = $null
$script:ExpandedTableOriginalDock = $null
$script:ExpandedTableOriginalMargin = $null
$script:ExpandedTableOriginalVisible = $true
$script:ExpandedTableCellPosition = $null
$script:InactiveRules = @{}
$script:SavedRulesSnapshot = $null
$script:PromptedThisCycle = @{}
# Tracks each blocked process instance (PID + identity) after one enforcement attempt.
$script:HandledBlockedInstances = @{}
$script:LastMonitorProcessScan = [datetime]::MinValue
$script:ProcessStartWatcher = $null
$script:ProcessStartWatcherActive = $false
$script:PendingProcessStarts = [System.Collections.Concurrent.ConcurrentQueue[int]]::new()
$script:LoggedProcessStates = @{}
# Live process-table search state. Hidden items remain cached so filtering does not
$script:ProcessTableFilters = @{ PS = ''; Other = '' }
$script:FilteredOutProcessItems = @{ PS = @{}; Other = @{} }
$script:PublisherCache = @{}
$script:NextProcessItemOrder = [long]0
$script:SyncProcessSearchBoxes = $false
$script:ExpandedSearchBox = $null
$script:ExpandedResetFilterButton = $null
# Conservative protection for core Windows processes.
$script:ProtectedNames = @(
    'System', 'Registry', 'smss.exe', 'csrss.exe', 'wininit.exe',
    'winlogon.exe', 'services.exe', 'lsass.exe', 'svchost.exe',
    'explorer.exe', 'dwm.exe', 'fontdrvhost.exe'
)
# Theme
$script:Theme = @{
    Bg       = [Drawing.Color]::FromArgb(15, 23, 42)
    Surface  = [Drawing.Color]::FromArgb(30, 41, 59)
    Surface2 = [Drawing.Color]::FromArgb(20, 29, 45)
    Text     = [Drawing.Color]::FromArgb(241, 245, 249)
    Muted    = [Drawing.Color]::FromArgb(148, 163, 184)
    Blue     = [Drawing.Color]::FromArgb(37, 99, 235)
    Green    = [Drawing.Color]::FromArgb(5, 150, 105)
    Red      = [Drawing.Color]::FromArgb(185, 28, 28)
    Yellow   = [Drawing.Color]::FromArgb(250, 204, 21)
}
$bg = $script:Theme.Bg
$card = $script:Theme.Surface
$fg = $script:Theme.Text
$muted = $script:Theme.Muted
$green = $script:Theme.Green
$red = $script:Theme.Red
$blue = $script:Theme.Blue
$form = [Windows.Forms.Form]::new()
# Use the custom ICO for the actual window/taskbar icon. The EXE's Explorer icon
$script:ProcessManagerIconPath = Join-Path $AppRoot 'media\process.ico'
$script:ProcessManagerIcon = $null
if (Test-Path -LiteralPath $script:ProcessManagerIconPath -PathType Leaf) {
    try {
        $script:ProcessManagerIcon = [Drawing.Icon]::new($script:ProcessManagerIconPath)
        $form.Icon = $script:ProcessManagerIcon
    }
    catch {
        $script:ProcessManagerIcon = $null
    }
}
$form.Text = 'AutoPilot Process Control Center'
$form.StartPosition = 'CenterScreen'
$form.WindowState = 'Maximized'
$form.MinimumSize = [Drawing.Size]::new(1100, 800)
$form.BackColor = $bg
$form.ForeColor = $fg
$form.Font = [Drawing.Font]::new('Segoe UI', 10)
$form.AutoScaleMode = 'Dpi'

# FUNCTION New-Label
function New-Label($text, $fontSize = 10, $color = $script:Theme.Text, $bold = $false) {
    $c = [Windows.Forms.Label]::new()
    $c.Text = $text
    $c.AutoSize = $false
    $c.Dock = 'Fill'
    $c.TextAlign = 'MiddleLeft'
    $c.ForeColor = $color
    $style = if ($bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular }
    $c.Font = [Drawing.Font]::new('Segoe UI', $fontSize, $style)
    return $c
}

# FUNCTION Set-RoundedButtonRegion
function Set-RoundedButtonRegion(
    [Windows.Forms.Control]$Button
    ){
    if ($Button.Width -le 0 -or $Button.Height -le 0) {
        return
    }
    $rect = [Drawing.RectangleF]::new(
        [single]0.5,
        [single]0.5,
        [single]($Button.Width - 1),
        [single]($Button.Height - 1)
    )
    $diameter = [single](
        [math]::Min(18, [math]::Min($rect.Width, $rect.Height))
    )
    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    try {
        $path.AddArc(
            $rect.X, $rect.Y,
            $diameter, $diameter, 180, 90
        )
        $path.AddArc(
            [single]($rect.Right - $diameter),
            $rect.Y,
            $diameter, $diameter, 270, 90
        )
        $path.AddArc(
            [single]($rect.Right - $diameter),
            [single]($rect.Bottom - $diameter),
            $diameter, $diameter, 0, 90
        )
        $path.AddArc(
            $rect.X,
            [single]($rect.Bottom - $diameter),
            $diameter, $diameter, 90, 90
        )
        $path.CloseFigure()
        $newRegion = [Drawing.Region]::new($path)
        $oldRegion = $Button.Region
        $Button.Region = $newRegion
        if ($null -ne $oldRegion) {
            $oldRegion.Dispose()
        }
    }
    finally {
        $path.Dispose()
    }
}

# FUNCTION New-Button
function New-Button($text, $color, $width = 170) {
    $c = [Windows.Forms.Button]::new()
    # Size and spacing
    $c.Size = [Drawing.Size]::new($width, 46)
    $c.Margin = [Windows.Forms.Padding]::new(5)
    $c.Padding = [Windows.Forms.Padding]::new(8, 0, 8, 0)
    $c.Text = $text
    $c.TextAlign = 'MiddleCenter'
    # Modern flat style
    $c.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $c.FlatAppearance.BorderSize = 0
    # Hover and click colors
    $c.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(
        [math]::Min(255, [int]$color.R + 18),
        [math]::Min(255, [int]$color.G + 18),
        [math]::Min(255, [int]$color.B + 18)
    )
    $c.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(
        [math]::Max(0, [int]$color.R - 20),
        [math]::Max(0, [int]$color.G - 20),
        [math]::Max(0, [int]$color.B - 20)
    )
    # Bolder, slightly larger typography
    $c.BackColor = $color
    $c.ForeColor = [Drawing.Color]::FromArgb(248, 250, 252)
    $c.Font = [Drawing.Font]::new(
        'Segoe UI',
        [single]11.5,
        [Drawing.FontStyle]::Bold
    )
    $c.Cursor = [Windows.Forms.Cursors]::Hand
    $c.UseVisualStyleBackColor = $false
    # Rounded corners, including after resizing
    $c.Add_Resize({
        param($sender, $e)
        Set-RoundedButtonRegion -Button $sender
    })
    # Subtle rounded outline
    $c.Add_Paint({
        param($sender, $e)
        if ($sender.Width -le 1 -or $sender.Height -le 1) {
            return
        }
        $graphics = $e.Graphics
        $graphics.SmoothingMode =
            [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = [Drawing.RectangleF]::new(
            [single]0.7,
            [single]0.7,
            [single]($sender.Width - 1.4),
            [single]($sender.Height - 1.4)
        )
        $diameter = [single]18
        $path = [Drawing.Drawing2D.GraphicsPath]::new()
        $pen = [Drawing.Pen]::new(
            [Drawing.Color]::FromArgb(71, 85, 105),
            [single]1.2
        )
        try {
            $path.AddArc(
                $rect.X, $rect.Y,
                $diameter, $diameter, 180, 90
            )
            $path.AddArc(
                [single]($rect.Right - $diameter),
                $rect.Y,
                $diameter, $diameter, 270, 90
            )
            $path.AddArc(
                [single]($rect.Right - $diameter),
                [single]($rect.Bottom - $diameter),
                $diameter, $diameter, 0, 90
            )
            $path.AddArc(
                $rect.X,
                [single]($rect.Bottom - $diameter),
                $diameter, $diameter, 90, 90
            )
            $path.CloseFigure()

            $graphics.DrawPath($pen, $path)
        }
        finally {
            $pen.Dispose()
            $path.Dispose()
        }
    })
    Set-RoundedButtonRegion -Button $c
    return $c
}

# FUNCTION Format-RemainingTime
function Format-RemainingTime($seconds) {
    if ($seconds -lt 0) { $seconds = 0 }
    $ts = [TimeSpan]::FromSeconds([math]::Floor($seconds))
    return ('{0:00}:{1:00}:{2:00}' -f [math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds)
}

# FUNCTION Get-Seconds
function Get-Seconds($controls) {
    return ([double]$controls[0].Value * 3600) +
           ([double]$controls[1].Value * 60) +
           [double]$controls[2].Value
}
# Root layout: all major areas resize with the window.
$root = [Windows.Forms.TableLayoutPanel]::new()
$root.Dock = 'Fill'
$root.BackColor = $bg
$root.Padding = [Windows.Forms.Padding]::new(18, 12, 18, 14)
$root.ColumnCount = 1
$root.RowCount = 5
[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 64))
[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 58))
[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 178))
[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100))
[void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 118))
$form.Controls.Add($root)
# Header
$header = [Windows.Forms.TableLayoutPanel]::new()
$header.Dock = 'Fill'
$header.ColumnCount = 2
$header.RowCount = 1
$header.BackColor = $bg
[void]$header.ColumnStyles.Add(
    [Windows.Forms.ColumnStyle]::new(
        [Windows.Forms.SizeType]::Percent, 62
    )
)
[void]$header.ColumnStyles.Add(
    [Windows.Forms.ColumnStyle]::new(
        [Windows.Forms.SizeType]::Percent, 38
    )
)
# Header logo + title
$headerContent = [Windows.Forms.FlowLayoutPanel]::new()
$headerContent.Dock = 'Fill'
$headerContent.FlowDirection = 'LeftToRight'
$headerContent.WrapContents = $false
$headerContent.BackColor = $bg
$headerContent.Padding = [Windows.Forms.Padding]::new(0)
$headerContent.Margin = [Windows.Forms.Padding]::new(0)
# Load a high-resolution frame from AppRoot\media\process.ico for the header.
$logoPicture = [Windows.Forms.PictureBox]::new()
$logoPicture.Size = [Drawing.Size]::new(45, 45)
$logoPicture.SizeMode = [Windows.Forms.PictureBoxSizeMode]::Normal
$logoPicture.BackColor = $bg
$logoPicture.Margin = [Windows.Forms.Padding]::new(2, 10, 0, 8)
$logoPicture.BorderStyle = 'None'
$logoPath = $script:ProcessManagerIconPath
if (Test-Path -LiteralPath $logoPath -PathType Leaf) {
    $logoIcon = $null
    $sourceBitmap = $null
    $targetBitmap = $null
    $logoGraphics = $null
    try {
        # Request a larger ICO frame when the file contains one.
        $logoIcon = [Drawing.Icon]::new($logoPath, 64, 64)
        $sourceBitmap = $logoIcon.ToBitmap()
        $targetBitmap = [Drawing.Bitmap]::new(
            45, 45, [Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $logoGraphics = [Drawing.Graphics]::FromImage($targetBitmap)
        $logoGraphics.Clear([Drawing.Color]::Transparent)
        $logoGraphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $logoGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $logoGraphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $logoGraphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
        $logoGraphics.DrawImage(
            $sourceBitmap,
            [Drawing.Rectangle]::new(0, 0, 45, 45),
            [Drawing.Rectangle]::new(0, 0, $sourceBitmap.Width, $sourceBitmap.Height),
            [Drawing.GraphicsUnit]::Pixel
        )
        $logoPicture.Image = $targetBitmap
        # The PictureBox now owns targetBitmap.
        $targetBitmap = $null
    }
    catch {
        # If the logo cannot be rendered, keep the title visible.
    }
    finally {
        if ($logoGraphics) { $logoGraphics.Dispose() }
        if ($sourceBitmap) { $sourceBitmap.Dispose() }
        if ($targetBitmap) { $targetBitmap.Dispose() }
        if ($logoIcon) { $logoIcon.Dispose() }
    }
}
$headerTitle = New-Label 'Process Control Center' 21 $fg $true
$headerTitle.Dock = 'None'
$headerTitle.Size = [Drawing.Size]::new(430, 64)
$headerTitle.Margin = [Windows.Forms.Padding]::new(0)
$headerTitle.Padding = [Windows.Forms.Padding]::new(2, 0, 0, 0)
[void]$headerContent.Controls.Add($logoPicture)
[void]$headerContent.Controls.Add($headerTitle)
$header.Controls.Add($headerContent, 0, 0)
# Monitor status, blinking LED, and global rule counters.
$monitorStatusPanel = [Windows.Forms.TableLayoutPanel]::new()
$monitorStatusPanel.Dock = 'None'
$monitorStatusPanel.Size = [Drawing.Size]::new(348, 46)
$monitorStatusPanel.Anchor = [Windows.Forms.AnchorStyles]::Right -bor
                             [Windows.Forms.AnchorStyles]::Top
$monitorStatusPanel.Margin = [Windows.Forms.Padding]::new(0, 9, 0, 9)
$monitorStatusPanel.ColumnCount = 4
$monitorStatusPanel.RowCount = 1
$monitorStatusPanel.BackColor = $bg
$monitorStatusPanel.Margin = [Windows.Forms.Padding]::new(0)
$monitorStatusPanel.Padding = [Windows.Forms.Padding]::new(0)
[void]$monitorStatusPanel.ColumnStyles.Add(
    [Windows.Forms.ColumnStyle]::new(
        [Windows.Forms.SizeType]::Absolute, 32
    )
)
[void]$monitorStatusPanel.ColumnStyles.Add(
    [Windows.Forms.ColumnStyle]::new(
        [Windows.Forms.SizeType]::Absolute, 128
    )
)
[void]$monitorStatusPanel.ColumnStyles.Add(
    [Windows.Forms.ColumnStyle]::new(
        [Windows.Forms.SizeType]::Absolute, 94
    )
)
[void]$monitorStatusPanel.ColumnStyles.Add(
    [Windows.Forms.ColumnStyle]::new(
        [Windows.Forms.SizeType]::Absolute, 94
    )
)
# Larger monitor LED.
$monitorLed = New-Label '●' 22 `
    ([Drawing.Color]::FromArgb(248, 113, 113)) $true
$monitorLed.TextAlign = 'MiddleCenter'
$monitorLed.BackColor = $bg
# Monitor status text. The dot is now a separate control.
$status = New-Label 'MONITOR STOPPED' 9.5 `
    ([Drawing.Color]::FromArgb(252, 165, 165)) $true
$status.TextAlign = 'MiddleCenter'
$status.BackColor = [Drawing.Color]::FromArgb(69, 20, 30)
$status.Padding = [Windows.Forms.Padding]::new(2)
# Total ALLOWED rules: PowerShell + Other Windows.
$monitorAllowedCount = New-Label 'ALLOWED 0' 9 `
    ([Drawing.Color]::FromArgb(52, 211, 153)) $true
$monitorAllowedCount.TextAlign = 'MiddleCenter'
$monitorAllowedCount.BackColor = [Drawing.Color]::FromArgb(6, 55, 47)
# Total BLOCKED rules: PowerShell + Other Windows.
$monitorBlockedCount = New-Label 'BLOCKED 0' 9 `
    ([Drawing.Color]::FromArgb(248, 113, 113)) $true
$monitorBlockedCount.TextAlign = 'MiddleCenter'
$monitorBlockedCount.BackColor = [Drawing.Color]::FromArgb(69, 20, 30)
$monitorStatusPanel.Controls.Add($monitorLed, 0, 0)
$monitorStatusPanel.Controls.Add($status, 1, 0)
$monitorStatusPanel.Controls.Add($monitorAllowedCount, 2, 0)
$monitorStatusPanel.Controls.Add($monitorBlockedCount, 3, 0)
$header.Controls.Add($monitorStatusPanel, 1, 0)
$root.Controls.Add($header, 0, 0)
# Main buttons
$buttonBar = [Windows.Forms.FlowLayoutPanel]::new()
$buttonBar.Dock = 'Fill'
$buttonBar.WrapContents = $false
$buttonBar.FlowDirection = 'LeftToRight'
$buttonBar.BackColor = $bg
$scan = New-Button 'SCAN ALL PROCESSES' $blue 220
$start = New-Button 'START MONITOR' $green 190
$autoStartButton = New-Button 'AUTO START: OFF' ([Drawing.Color]::FromArgb(124, 58, 237)) 205
$taskButton = New-Button 'TASK OFF' ([Drawing.Color]::FromArgb(180, 83, 9)) 140
$script:StartMonitorButton = $start
$script:AutoStartButton = $autoStartButton
$script:TaskButton = $taskButton
[void]$buttonBar.Controls.Add($scan)
[void]$buttonBar.Controls.Add($start)
[void]$buttonBar.Controls.Add($autoStartButton)
[void]$buttonBar.Controls.Add($taskButton)
# Live scan indicator: its LED blinks while a scan is active.
$scanIndicatorPanel = [Windows.Forms.Panel]::new()
$scanIndicatorPanel.Size = [Drawing.Size]::new(235, 44)
$scanIndicatorPanel.Margin = [Windows.Forms.Padding]::new(18, 5, 5, 5)
$scanIndicatorPanel.BackColor = $script:Theme.Surface
$scanIndicatorPanel.BorderStyle = 'FixedSingle'
$scanLed = [Windows.Forms.Label]::new()
$scanLed.Text = '●'
$scanLed.Font = [Drawing.Font]::new('Segoe UI Semibold', 18)
$scanLed.TextAlign = 'MiddleCenter'
$scanLed.Size = [Drawing.Size]::new(38, 42)
$scanLed.Location = [Drawing.Point]::new(2, 0)
$scanLed.ForeColor = $script:Theme.Muted
$scanLed.BackColor = $script:Theme.Surface
$scanIndicatorPanel.Controls.Add($scanLed)
$scanIndicatorText = [Windows.Forms.Label]::new()
$scanIndicatorText.Text = 'SCAN INACTIVE'
$scanIndicatorText.Font = [Drawing.Font]::new('Segoe UI Semibold', 10)
$scanIndicatorText.TextAlign = 'MiddleLeft'
$scanIndicatorText.AutoSize = $false
$scanIndicatorText.Size = [Drawing.Size]::new(185, 42)
$scanIndicatorText.Location = [Drawing.Point]::new(42, 0)
$scanIndicatorText.ForeColor = $script:Theme.Muted
$scanIndicatorText.BackColor = $script:Theme.Surface
$scanIndicatorPanel.Controls.Add($scanIndicatorText)
[void]$buttonBar.Controls.Add($scanIndicatorPanel)
$root.Controls.Add($buttonBar, 0, 1)
# Two timer cards, with larger HH:MM:SS spinners and prominent live countdowns.
$durationLayout = [Windows.Forms.TableLayoutPanel]::new()
$durationLayout.Dock = 'Fill'
$durationLayout.ColumnCount = 2
$durationLayout.RowCount = 1
$durationLayout.BackColor = $bg
[void]$durationLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 50))
[void]$durationLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 50))

# FUNCTION Add-DurationCard
function Add-DurationCard($titleText, $timerCaption, $accent, $defaultHours, $defaultMinutes) {
    $panel = [Windows.Forms.Panel]::new()
    $panel.Dock = 'Fill'
    $panel.BackColor = $card
    $panel.Padding = [Windows.Forms.Padding]::new(14, 8, 14, 8)
    $panel.Margin = [Windows.Forms.Padding]::new(5, 5, 10, 7)
    $layout = [Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    $layout.BackColor = $card
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 28))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 64))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100))
    $heading = New-Label $titleText 10 $accent $true
    $layout.Controls.Add($heading, 0, 0)
    $spinners = [Windows.Forms.FlowLayoutPanel]::new()
    $spinners.Dock = 'Fill'
    $spinners.WrapContents = $false
    $spinners.FlowDirection = 'LeftToRight'
    $spinners.BackColor = $card
    $spinners.Padding = [Windows.Forms.Padding]::new(0, 2, 0, 0)
    $controls = @()
	$parts = @(
		@{ Name = 'HOURS';   Max = 99; Default = $defaultHours },
		@{ Name = 'MINUTES'; Max = 59; Default = $defaultMinutes },
		@{ Name = 'SECONDS'; Max = 59; Default = 0 }
	)
    foreach ($part in $parts) {
        $segment = [Windows.Forms.Panel]::new()
        $segment.Size = [Drawing.Size]::new(95, 55)
        $segment.Margin = [Windows.Forms.Padding]::new(0, 0, 12, 0)
        $segment.BackColor = $card
        $n = [Windows.Forms.NumericUpDown]::new()
        $n.Location = [Drawing.Point]::new(0, 0)
        $n.Size = [Drawing.Size]::new(90, 34)
        $n.Minimum = 0
        $n.Maximum = $part.Max
        $n.Value = $part.Default
        $n.TextAlign = 'Center'
        $n.ReadOnly = $true
        $n.Font = [Drawing.Font]::new('Segoe UI Semibold', 14)
        $n.BackColor = $script:Theme.Surface2
        $n.ForeColor = $fg
        $n.BorderStyle = 'FixedSingle'
        $segment.Controls.Add($n)
        $cap = New-Label $part.Name 9 $muted $true
		$cap.Dock = 'None'
		$cap.Location = [Drawing.Point]::new(0, 35)
		$cap.Size = [Drawing.Size]::new(90, 18)
		$cap.TextAlign = 'MiddleCenter'
		$cap.Visible = $true
		$segment.Controls.Add($cap)
		$cap.BringToFront()
				[void]$spinners.Controls.Add($segment)
				$controls += $n
    }
    $layout.Controls.Add($spinners, 0, 1)
    $countdown = New-Label "$timerCaption  00:00:00" 14 $accent $true
    $countdown.Padding = [Windows.Forms.Padding]::new(0, 1, 0, 0)
    $layout.Controls.Add($countdown, 0, 2)
    $panel.Controls.Add($layout)
    return @{ Panel = $panel; Controls = $controls; Countdown = $countdown }
}
$monitorCard = Add-DurationCard 'MONITOR DURATION' 'MONITOR REMAINING' ([Drawing.Color]::FromArgb(52, 211, 153)) 0 10
$panelCard = Add-DurationCard 'PANEL LIFETIME' 'PANEL REMAINING' ([Drawing.Color]::FromArgb(196, 181, 253)) 1 0
$durationLayout.Controls.Add($monitorCard.Panel, 0, 0)
$durationLayout.Controls.Add($panelCard.Panel, 1, 0)
$root.Controls.Add($durationLayout, 0, 2)
$monitorDuration = $monitorCard.Controls
$panelDuration = $panelCard.Controls
$monitorCountdown = $monitorCard.Countdown
$panelCountdown = $panelCard.Countdown
# A scheduled launch restores the duration values captured when AUTO START was enabled.
if ($script:AutoStartMonitorRequested) {
    if ($AutoMonitorHours -ge 0 -and $AutoMonitorHours -le 99) {
        $monitorDuration[0].Value = [decimal]$AutoMonitorHours
    }
    if ($AutoMonitorMinutes -ge 0 -and $AutoMonitorMinutes -le 59) {
        $monitorDuration[1].Value = [decimal]$AutoMonitorMinutes
    }
    if ($AutoMonitorSeconds -ge 0 -and $AutoMonitorSeconds -le 59) {
        $monitorDuration[2].Value = [decimal]$AutoMonitorSeconds
    }
    if ($AutoPanelHours -ge 0 -and $AutoPanelHours -le 99) {
        $panelDuration[0].Value = [decimal]$AutoPanelHours
    }
    if ($AutoPanelMinutes -ge 0 -and $AutoPanelMinutes -le 59) {
        $panelDuration[1].Value = [decimal]$AutoPanelMinutes
    }
    if ($AutoPanelSeconds -ge 0 -and $AutoPanelSeconds -le 59) {
        $panelDuration[2].Value = [decimal]$AutoPanelSeconds
    }
}
# Premium custom-drawn tabs with rounded surfaces, category badges, and clear selection.
$tabs = [Windows.Forms.TabControl]::new()
$tabs.Dock = 'Fill'
$tabs.DrawMode = 'OwnerDrawFixed'
$tabs.Appearance = [Windows.Forms.TabAppearance]::Buttons
$tabs.ItemSize = [Drawing.Size]::new(320, 54)
$tabs.SizeMode = 'Fixed'
$tabs.Padding = [Drawing.Point]::new(12, 5)
$tabs.Font = [Drawing.Font]::new('Segoe UI Semibold', 11)
$tabs.BackColor = $bg
$script:HoveredTabIndex = -1
$tabs.Add_MouseMove({
    param($sender, $e)
    $nextIndex = -1
    for ($i = 0; $i -lt $sender.TabPages.Count; $i++) {
        if ($sender.GetTabRect($i).Contains($e.Location)) { $nextIndex = $i; break }
    }
    if ($nextIndex -ne $script:HoveredTabIndex) {
        $script:HoveredTabIndex = $nextIndex
        $sender.Invalidate()
    }
})
$tabs.Add_MouseLeave({
    if ($script:HoveredTabIndex -ne -1) {
        $script:HoveredTabIndex = -1
        $tabs.Invalidate()
    }
})
$tabs.Add_DrawItem({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    # Paint the entire native tab item area dark first, so the Windows visual-style
    $stripBrush = [Drawing.SolidBrush]::new($script:Theme.Bg)
    try { $g.FillRectangle($stripBrush, $e.Bounds) } finally { $stripBrush.Dispose() }
    $i = $e.Index
    $page = $sender.TabPages[$i]
    $selected = ($i -eq $sender.SelectedIndex)
    $hovered = ($i -eq $script:HoveredTabIndex)
    $r = [Drawing.RectangleF]::new(
        [single]($e.Bounds.X + 4), [single]($e.Bounds.Y + 3),
        [single]([math]::Max(2, $e.Bounds.Width - 8)),
        [single]([math]::Max(2, $e.Bounds.Height - 7)))
    $radius = [single]12
    $d = [single]($radius * 2)
    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    try {
        $path.AddArc($r.X, $r.Y, $d, $d, 180, 90)
        $path.AddArc([single]($r.Right - $d), $r.Y, $d, $d, 270, 90)
        $path.AddArc([single]($r.Right - $d), [single]($r.Bottom - $d), $d, $d, 0, 90)
        $path.AddArc($r.X, [single]($r.Bottom - $d), $d, $d, 90, 90)
        $path.CloseFigure()
        if ($selected) {
            $fill = [Drawing.Drawing2D.LinearGradientBrush]::new(
                $r,
                [Drawing.Color]::FromArgb(37, 99, 235),
                [Drawing.Color]::FromArgb(30, 64, 175),
                [Drawing.Drawing2D.LinearGradientMode]::Vertical)
            try { $g.FillPath($fill, $path) } finally { $fill.Dispose() }
            $outlineColor = [Drawing.Color]::FromArgb(96, 165, 250)
        } else {
            $surfaceColor = if ($hovered) {
                [Drawing.Color]::FromArgb(51, 65, 85)
            } else {
                [Drawing.Color]::FromArgb(30, 41, 59)
            }
            $fill = [Drawing.SolidBrush]::new($surfaceColor)
            try { $g.FillPath($fill, $path) } finally { $fill.Dispose() }
            $outlineColor = if ($hovered) {
                [Drawing.Color]::FromArgb(100, 116, 139)
            } else {
                [Drawing.Color]::FromArgb(51, 65, 85)
            }
        }
        $outline = [Drawing.Pen]::new($outlineColor, [single]1)
        try { $g.DrawPath($outline, $path) } finally { $outline.Dispose() }
        # Compact category badge, different for PowerShell and Windows processes.
        $badgeRect = [Drawing.RectangleF]::new([single]($r.X + 13), [single]($r.Y + 12), [single]42, [single]27)
        $badgePath = [Drawing.Drawing2D.GraphicsPath]::new()
        $br = [single]7
        $bd = [single]($br * 2)
        try {
            $badgePath.AddArc($badgeRect.X, $badgeRect.Y, $bd, $bd, 180, 90)
            $badgePath.AddArc([single]($badgeRect.Right - $bd), $badgeRect.Y, $bd, $bd, 270, 90)
            $badgePath.AddArc([single]($badgeRect.Right - $bd), [single]($badgeRect.Bottom - $bd), $bd, $bd, 0, 90)
            $badgePath.AddArc($badgeRect.X, [single]($badgeRect.Bottom - $bd), $bd, $bd, 90, 90)
            $badgePath.CloseFigure()
            $badgeColor = if ($selected) {
                [Drawing.Color]::FromArgb(15, 23, 42)
            } else {
                [Drawing.Color]::FromArgb(15, 23, 42)
            }
            $badgeBrush = [Drawing.SolidBrush]::new($badgeColor)
            try { $g.FillPath($badgeBrush, $badgePath) } finally { $badgeBrush.Dispose() }
            $badgeFont = [Drawing.Font]::new('Segoe UI Semibold', [single]8.5)
            $badgeTextBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(191, 219, 254))
            $badgeFormat = [Drawing.StringFormat]::new()
            $badgeFormat.Alignment = [Drawing.StringAlignment]::Center
            $badgeFormat.LineAlignment = [Drawing.StringAlignment]::Center
            $badgeText = if ($i -eq 0) { 'PS' } else { 'WIN' }
            try { $g.DrawString($badgeText, $badgeFont, $badgeTextBrush, $badgeRect, $badgeFormat) }
            finally {
                $badgeFont.Dispose()
                $badgeTextBrush.Dispose()
                $badgeFormat.Dispose()
            }
        } finally { $badgePath.Dispose() }
        $textRect = [Drawing.RectangleF]::new([single]($r.X + 66), [single]($r.Y + 2), [single]($r.Width - 76), [single]($r.Height - 4))
        $textFont = [Drawing.Font]::new('Segoe UI Semibold', [single]11)
        $textBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(248, 250, 252))
        $format = [Drawing.StringFormat]::new()
        $format.Alignment = [Drawing.StringAlignment]::Near
        $format.LineAlignment = [Drawing.StringAlignment]::Center
        $format.Trimming = [Drawing.StringTrimming]::EllipsisCharacter
        try { $g.DrawString(([string]$page.Text).Trim(), $textFont, $textBrush, $textRect, $format) }
        finally {
            $textFont.Dispose()
            $textBrush.Dispose()
            $format.Dispose()
        }
        if ($selected) {
            $accent = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(191, 219, 254))
            try { $g.FillRectangle($accent, [single]($r.X + 67), [single]($r.Bottom - 5), [single]([math]::Min(126, $r.Width - 82)), [single]2) }
            finally { $accent.Dispose() }
        }
    } finally { $path.Dispose() }
})
$tabs.Add_SelectedIndexChanged({ $tabs.Invalidate() })

# FUNCTION New-ProcessTab
function New-ProcessTab($key, $caption) {
$page = [Windows.Forms.Panel]::new()
$page.BorderStyle = 'None'
    $page.BackColor = $bg
    $page.ForeColor = $fg
    $page.Padding = [Windows.Forms.Padding]::new(4)
    $layout = [Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    $layout.BackColor = $bg
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 56))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 68))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 32))
    $page.Controls.Add($layout)
    # Search controls filter the visible table immediately as each character changes.
    $searchBar = [Windows.Forms.FlowLayoutPanel]::new()
    $searchBar.Dock = 'Fill'
    $searchBar.FlowDirection = 'LeftToRight'
    $searchBar.WrapContents = $false
    $searchBar.BackColor = $bg
    $searchBar.Margin = [Windows.Forms.Padding]::new(0)
    $searchBar.Padding = [Windows.Forms.Padding]::new(0)
    $searchLabel = New-Label 'SEARCH PID / NAME / LOCATION / PUBLISHER' 9 $muted $true
    $searchLabel.Dock = 'None'
    $searchLabel.Size = [Drawing.Size]::new(310, 46)
    $searchLabel.Margin = [Windows.Forms.Padding]::new(4, 3, 4, 3)
    $searchBox = [Windows.Forms.TextBox]::new()
    $searchBox.Name = "ProcessSearch_$key"
    $searchBox.Tag = [string]$key
    $searchBox.Size = [Drawing.Size]::new(420, 32)
    $searchBox.Margin = [Windows.Forms.Padding]::new(4, 7, 10, 4)
    $searchBox.BorderStyle = 'FixedSingle'
    $searchBox.BackColor = $script:Theme.Surface2
    $searchBox.ForeColor = $script:Theme.Text
    $searchBox.Font = [Drawing.Font]::new('Segoe UI', 11)
    $resetFilterButton = New-Button '⛔ RESET FILTER' ([Drawing.Color]::FromArgb(217, 83, 54)) 190
    $resetFilterButton.Size = [Drawing.Size]::new(155, 40)
    $resetFilterButton.Margin = [Windows.Forms.Padding]::new(4, 4, 4, 3)
    $resetFilterButton.Tag = $searchBox
    $searchBox.Add_TextChanged({
        param($sender, $e)
        if ($script:SyncProcessSearchBoxes) { return }
        Set-ProcessTableFilter -Key ([string]$sender.Tag) -Text ([string]$sender.Text) -Source $sender
    })
    $resetFilterButton.Add_Click({
        param($sender, $e)
        $targetSearchBox = $sender.Tag
        if ($null -ne $targetSearchBox) { $targetSearchBox.Clear() }
    })
    [void]$searchBar.Controls.Add($searchLabel)
    [void]$searchBar.Controls.Add($searchBox)
    [void]$searchBar.Controls.Add($resetFilterButton)
    $layout.Controls.Add($searchBar, 0, 0)
    $grid = [Windows.Forms.ListView]::new()
    $grid.Dock = 'Fill'
    $grid.View = 'Details'
    $grid.FullRowSelect = $true
    $grid.MultiSelect = $false
    $grid.GridLines = $false
    $grid.HideSelection = $false
    $grid.BorderStyle = 'None'
    $grid.BackColor = $script:Theme.Surface2
    $grid.ForeColor = $fg
    $grid.Font = [Drawing.Font]::new('Segoe UI', 13)
    $grid.Margin = [Windows.Forms.Padding]::new(0)
    $grid.OwnerDraw = $true
    # Double-buffer the owner-drawn ListView to avoid visible flashes during refresh.
    try {
        $doubleBufferedProperty = [Windows.Forms.Control].GetProperty(
            'DoubleBuffered',
            [System.Reflection.BindingFlags]::Instance -bor
            [System.Reflection.BindingFlags]::NonPublic
        )
        if ($null -ne $doubleBufferedProperty) {
            $doubleBufferedProperty.SetValue($grid, $true, $null)
        }
    } catch {}
    $grid.UseCompatibleStateImageBehavior = $false
    $grid.HeaderStyle = 'Nonclickable'
    $grid.Columns.Add('PID', 90) | Out-Null
    $grid.Columns.Add('PROCESS', 240) | Out-Null
    $grid.Columns.Add('STATUS', 150) | Out-Null
    $grid.Columns.Add('EXECUTABLE / COMMAND LINE', 900) | Out-Null
    # ImageList sets a larger row height while keeping the table readable.
    $rowImages = [Windows.Forms.ImageList]::new()
    $rowImages.ImageSize = [Drawing.Size]::new(1, 38)
    $grid.SmallImageList = $rowImages
    $grid.Add_DrawColumnHeader({
        param($sender, $e)
        $headerBrush = [Drawing.SolidBrush]::new($script:Theme.Surface)
        $headerFont = [Drawing.Font]::new('Segoe UI Semibold', 10)
        $headerRect = [Drawing.RectangleF]::new([single]($e.Bounds.X + 8), [single]($e.Bounds.Y + 5),
            [single]([math]::Max(1, $e.Bounds.Width - 10)), [single]([math]::Max(1, $e.Bounds.Height - 8)))
        try {
            $e.Graphics.FillRectangle($headerBrush, $e.Bounds)
            $e.Graphics.DrawString($e.Header.Text, $headerFont, [Drawing.Brushes]::White, $headerRect)
            $e.DrawDefault = $false
        } finally {
            $headerBrush.Dispose()
            $headerFont.Dispose()
        }
    })
    $grid.Add_DrawItem({ param($sender, $e) $e.DrawDefault = $false })
    $grid.Add_DrawSubItem({
        param($sender, $e)
        $isSelected = $e.Item.Selected
        $state = [string]$e.Item.SubItems[2].Text
        if ($isSelected) {
            $rowBack = [Drawing.Color]::FromArgb(133, 77, 14)
            $rowFore = [Drawing.Color]::FromArgb(254, 240, 138)
        } elseif ($state -eq 'Blocked' -or $state -eq 'Terminated') {
            $rowBack = [Drawing.Color]::FromArgb(127, 29, 29)
            $rowFore = [Drawing.Color]::FromArgb(254, 202, 202)
        } elseif ($state -eq 'Allowed') {
            $rowBack = [Drawing.Color]::FromArgb(20, 64, 53)
            $rowFore = [Drawing.Color]::FromArgb(167, 243, 208)
        } else {
            $rowBack = $script:Theme.Surface2
            $rowFore = [Drawing.Color]::FromArgb(226, 232, 240)
        }
        $rowBrush = [Drawing.SolidBrush]::new($rowBack)
        try {
            $e.Graphics.FillRectangle($rowBrush, $e.Bounds)
        } finally { $rowBrush.Dispose() }
        $textRect = [Drawing.Rectangle]::new([int]($e.Bounds.X + 8), [int]($e.Bounds.Y + 1),
            [int]([math]::Max(0, $e.Bounds.Width - 12)), [int]([math]::Max(1, $e.Bounds.Height - 2)))
        $flags = [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::EndEllipsis -bor [Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::NoPrefix
        [Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$e.SubItem.Text, $sender.Font, $textRect, $rowFore, $flags)
    })
    # Dark frame around the process table.
	$grid.BorderStyle = 'None'
	$grid.Dock = 'Fill'
	$grid.Margin = [Windows.Forms.Padding]::new(0)
	$layout.Controls.Add($grid, 0, 1)
    $rules = [Windows.Forms.TableLayoutPanel]::new()
    $rules.Dock = 'Fill'
    $rules.ColumnCount = 2
    $rules.RowCount = 2
    $rules.BackColor = $bg
    $rules.Padding = [Windows.Forms.Padding]::new(0, 8, 0, 0)
    [void]$rules.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 50))
    [void]$rules.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 50))
    [void]$rules.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute, 28))
    [void]$rules.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent, 100))
    $allowTitle = New-Label 'ALLOWED PROCESSES' 10 ([Drawing.Color]::FromArgb(52, 211, 153)) $true
    $blockTitle = New-Label 'BLOCKED PROCESSES' 10 ([Drawing.Color]::FromArgb(248, 113, 113)) $true
    $allow = [Windows.Forms.ListBox]::new()
    $allow.Dock = 'Fill'
    $allow.BackColor = [Drawing.Color]::FromArgb(20, 55, 47)
    $allow.ForeColor = [Drawing.Color]::FromArgb(167, 243, 208)
    $allow.BorderStyle = 'None'
    $allow.Font = [Drawing.Font]::new('Segoe UI', 10)
    $block = [Windows.Forms.ListBox]::new()
    $block.Dock = 'Fill'
    $block.BackColor = [Drawing.Color]::FromArgb(69, 25, 33)
    $block.ForeColor = [Drawing.Color]::FromArgb(254, 202, 202)
    $block.BorderStyle = 'None'
    $block.Font = [Drawing.Font]::new('Segoe UI', 10)
    $rules.Controls.Add($allowTitle, 0, 0)
    $rules.Controls.Add($blockTitle, 1, 0)
    $rules.Controls.Add($allow, 0, 1)
    $rules.Controls.Add($block, 1, 1)
	$layout.Controls.Add($rules, 0, 2)
    return @{ Page = $page; Grid = $grid; Allow = $allow; Block = $block; Key = $key; SearchBox = $searchBox; ResetFilterButton = $resetFilterButton }
}
	$psTab = New-ProcessTab 'PS' 'PowerShell Processes'
	$otherTab = New-ProcessTab 'Other' 'Other Windows Processes'
	# Use a normal borderless panel instead of displaying a TabControl.
	$script:CurrentProcessKey = 'PS'
	$processContent = [Windows.Forms.Panel]::new()
	$processContent.Dock = 'Fill'
	$processContent.Margin = [Windows.Forms.Padding]::new(0)
	$processContent.Padding = [Windows.Forms.Padding]::new(0)
	$processContent.BackColor = $bg
	$processContent.BorderStyle = 'None'
	foreach ($page in @($psTab.Page, $otherTab.Page)) {
		$page.Dock = 'Fill'
		$page.Margin = [Windows.Forms.Padding]::new(0)
		$page.BorderStyle = 'None'
		$page.BackColor = $bg
	}
	[void]$processContent.Controls.Add($psTab.Page)
	[void]$processContent.Controls.Add($otherTab.Page)
	$psTab.Page.Visible = $true
	$otherTab.Page.Visible = $false
	$psTab.Page.BringToFront()
	# Workspace: switch buttons above the borderless content.
	$workspace = [Windows.Forms.TableLayoutPanel]::new()
	$workspace.Dock = 'Fill'
	$workspace.ColumnCount = 1
	$workspace.RowCount = 2
	$workspace.BackColor = $bg
	$workspace.Margin = [Windows.Forms.Padding]::new(0)
	$workspace.Padding = [Windows.Forms.Padding]::new(0)
	[void]$workspace.RowStyles.Add(
		[Windows.Forms.RowStyle]::new(
			[Windows.Forms.SizeType]::Absolute, 54
		)
	)
	[void]$workspace.RowStyles.Add(
		[Windows.Forms.RowStyle]::new(
			[Windows.Forms.SizeType]::Percent, 100
		)
	)
	# External category buttons.
	$processSwitchBar = [Windows.Forms.FlowLayoutPanel]::new()
	$processSwitchBar.Dock = 'Fill'
	$processSwitchBar.FlowDirection = 'LeftToRight'
	$processSwitchBar.WrapContents = $false
	$processSwitchBar.BackColor = $bg
	$processSwitchBar.Margin = [Windows.Forms.Padding]::new(0)
	$processSwitchBar.Padding = [Windows.Forms.Padding]::new(0)

# FUNCTION New-ProcessSwitchPanel
function New-ProcessSwitchPanel(
    [string]$Caption,
    [int]$Width,
    [Drawing.Color]$InitialColor
    ) {
    $panel = [Windows.Forms.Panel]::new()
    $panel.Size = [Drawing.Size]::new($Width, 46)
    $panel.Margin = [Windows.Forms.Padding]::new(5)
    $panel.BackColor = $InitialColor
    $panel.BorderStyle = 'None'
    $panel.Cursor = [Windows.Forms.Cursors]::Hand
    $captionLabel = New-Label $Caption 9.5 `
        ([Drawing.Color]::White) $true
    $captionLabel.Dock = 'None'
    $captionLabel.Location = [Drawing.Point]::new(0, 0)
    $captionLabel.Size = [Drawing.Size]::new($Width - 90, 46)
    $captionLabel.TextAlign = 'MiddleCenter'
    $captionLabel.BackColor = $InitialColor
    $captionLabel.Cursor = [Windows.Forms.Cursors]::Hand
    # Red counter: blocked rules
    $countLabel = New-Label '0' 11 `
    ([Drawing.Color]::FromArgb(248, 113, 113)) $true
    $countLabel.Dock = 'None'
    $countLabel.Location = [Drawing.Point]::new($Width - 90, 0)
    $countLabel.Size = [Drawing.Size]::new(45, 46)
    $countLabel.TextAlign = 'MiddleCenter'
    $countLabel.BackColor = $InitialColor
    $countLabel.ForeColor = [Drawing.Color]::FromArgb(248, 113, 113)
    $countLabel.Cursor = [Windows.Forms.Cursors]::Hand
    # Green counter: allowed rules
    $allowedCountLabel = New-Label '0' 11 `
    ([Drawing.Color]::FromArgb(52, 211, 153)) $true
    $allowedCountLabel.Dock = 'None'
    $allowedCountLabel.Location = [Drawing.Point]::new($Width - 45, 0)
    $allowedCountLabel.Size = [Drawing.Size]::new(45, 46)
    $allowedCountLabel.TextAlign = 'MiddleCenter'
    $allowedCountLabel.BackColor = $InitialColor
    $allowedCountLabel.ForeColor = [Drawing.Color]::FromArgb(52, 211, 153)
    $allowedCountLabel.Cursor = [Windows.Forms.Cursors]::Hand
    [void]$panel.Controls.Add($captionLabel)
    [void]$panel.Controls.Add($countLabel)
    [void]$panel.Controls.Add($allowedCountLabel)
    return @{
        Panel       = $panel
        Caption     = $captionLabel
        Count       = $countLabel
        AllowedCount = $allowedCountLabel
		}
	}
	$psSwitchParts = New-ProcessSwitchPanel `
		'POWERSHELL PROCESSES' 245 $blue
	$otherSwitchParts = New-ProcessSwitchPanel `
		'OTHER WINDOWS PROCESSES' 280 $card
	$psSwitch = $psSwitchParts.Panel
	$psSwitchLabel = $psSwitchParts.Caption
	$psSwitchCount = $psSwitchParts.Count
	$otherSwitch = $otherSwitchParts.Panel
	$otherSwitchLabel = $otherSwitchParts.Caption
	$otherSwitchCount = $otherSwitchParts.Count
	$psSwitchAllowedCount = $psSwitchParts.AllowedCount
	$otherSwitchAllowedCount = $otherSwitchParts.AllowedCount
	# Rounded corners for the two process-category switches only.
	Set-RoundedButtonRegion -Button $psSwitch
	Set-RoundedButtonRegion -Button $otherSwitch
	$psSwitch.Add_Resize({
		param($sender, $e)
		Set-RoundedButtonRegion -Button $sender
	})
	$otherSwitch.Add_Resize({
		param($sender, $e)
		Set-RoundedButtonRegion -Button $sender
	})
	[void]$processSwitchBar.Controls.Add($psSwitch)
	[void]$processSwitchBar.Controls.Add($otherSwitch)
	# Pause/resume only the visible process table refresh.
	$pauseTableButton = New-Button 'PAUSE TABLE' $blue 175
	[void]$processSwitchBar.Controls.Add($pauseTableButton)
	$workspace.Controls.Add($processSwitchBar, 0, 0)
	$workspace.Controls.Add($processContent, 0, 1)

# FUNCTION Update-ProcessSwitchButtons
function Update-ProcessSwitchButtons {
    if ($script:CurrentProcessKey -eq 'PS') {
        $activeColor = $blue
        $inactiveColor = $card
    }
    else {
        $activeColor = $blue
        $inactiveColor = $card
    }
    # PowerShell button
    $psSwitch.BackColor = if ($script:CurrentProcessKey -eq 'PS') {
        $activeColor
    } else {
        $inactiveColor
    }
    $psSwitchLabel.BackColor = $psSwitch.BackColor
    $psSwitchCount.BackColor = $psSwitch.BackColor
    $psSwitchAllowedCount.BackColor = $psSwitch.BackColor
    # Other Windows button
    $otherSwitch.BackColor = if ($script:CurrentProcessKey -eq 'Other') {
        $activeColor
    } else {
        $inactiveColor
    }
    $otherSwitchLabel.BackColor = $otherSwitch.BackColor
    $otherSwitchCount.BackColor = $otherSwitch.BackColor
    $otherSwitchAllowedCount.BackColor = $otherSwitch.BackColor
    # Keep the counters red and green, regardless of selection.
    $psSwitchCount.ForeColor =
        [Drawing.Color]::FromArgb(248, 113, 113)
    $otherSwitchCount.ForeColor =
        [Drawing.Color]::FromArgb(248, 113, 113)
    $psSwitchAllowedCount.ForeColor =
        [Drawing.Color]::FromArgb(52, 211, 153)
    $otherSwitchAllowedCount.ForeColor =
        [Drawing.Color]::FromArgb(52, 211, 153)
}

# FUNCTION Update-ProcessSwitchCounts
function Update-ProcessSwitchCounts {
    # Red: blocked rules
    $psSwitchCount.Text = [string]$script:Rules.PS.Blocked.Count
    $otherSwitchCount.Text = [string]$script:Rules.Other.Blocked.Count
    # Green: allowed rules
    $psSwitchAllowedCount.Text = [string]$script:Rules.PS.Allowed.Count
    $otherSwitchAllowedCount.Text = [string]$script:Rules.Other.Allowed.Count
    $psSwitchCount.ForeColor =
        [Drawing.Color]::FromArgb(248, 113, 113)
    $otherSwitchCount.ForeColor =
        [Drawing.Color]::FromArgb(248, 113, 113)
    $psSwitchAllowedCount.ForeColor =
        [Drawing.Color]::FromArgb(52, 211, 153)
    $otherSwitchAllowedCount.ForeColor =
        [Drawing.Color]::FromArgb(52, 211, 153)
}

# FUNCTION Show-ProcessCategory
function Show-ProcessCategory([string]$Key) {
    $script:CurrentProcessKey = $Key
    if ($Key -eq 'PS') {
        $psTab.Page.Visible = $true
        $otherTab.Page.Visible = $false
        $psTab.Page.BringToFront()
    }
    else {
        $psTab.Page.Visible = $false
        $otherTab.Page.Visible = $true
        $otherTab.Page.BringToFront()
    }
    Update-ProcessSwitchButtons
    Resize-ProcessColumns
	}
	$psSwitchAllowedCount.Add_Click({
		Show-ProcessCategory 'PS'
	})
	$psSwitchLabel.Add_Click({
		Show-ProcessCategory 'PS'
	})
	$psSwitchCount.Add_Click({
		Show-ProcessCategory 'PS'
	})
	$otherSwitchAllowedCount.Add_Click({
		Show-ProcessCategory 'Other'
	})
	$otherSwitchLabel.Add_Click({
		Show-ProcessCategory 'Other'
	})
	$otherSwitchCount.Add_Click({
		Show-ProcessCategory 'Other'
	})
	Update-ProcessSwitchButtons
	# Add only the borderless workspace to the root layout.
	$root.Controls.Add($workspace, 0, 3)
	# Footer action row and log
	$footer = [Windows.Forms.TableLayoutPanel]::new()
	$footer.Dock = 'Fill'
	$footer.ColumnCount = 2
	$footer.RowCount = 1
	$footer.BackColor = $bg
	[void]$footer.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute, 700))
	[void]$footer.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent, 100))
	$actions = [Windows.Forms.FlowLayoutPanel]::new()
	$actions.Dock = 'Fill'
	$actions.WrapContents = $false
	$actions.FlowDirection = 'LeftToRight'
	$actions.BackColor = $bg
	$allowSelected = New-Button 'ALLOW SELECTED' $green 170
	$blockSelected = New-Button 'BLOCK SELECTED' $red 170
	$removeRule = New-Button 'REMOVE RULE' $blue 160
	$saveRulesButton = New-Button 'SAVE RULES' `
		([Drawing.Color]::FromArgb(124, 58, 237)) 150
	[void]$actions.Controls.Add($allowSelected)
	[void]$actions.Controls.Add($blockSelected)
	[void]$actions.Controls.Add($removeRule)
	[void]$actions.Controls.Add($saveRulesButton)
	$saveRulesButton.Add_Click({
		try {
			# Saving rules is intentionally unavailable while monitoring runs.
			if ($script:Running) {
				[Windows.Forms.MessageBox]::Show(
					'Monitoring is running. Stop MONITOR before saving rules.',
					'Save Rules Unavailable',
					[Windows.Forms.MessageBoxButtons]::OK,
					[Windows.Forms.MessageBoxIcon]::Information
				) | Out-Null
				return
			}
			$currentSnapshot = Get-RulesSnapshot
			$ruleCount = 0
			foreach ($category in @('PS', 'Other')) {
				$ruleCount += $script:Rules[$category].Allowed.Count
				$ruleCount += $script:Rules[$category].Blocked.Count
			}
			if (
				$null -ne $script:SavedRulesSnapshot -and
				$currentSnapshot -ceq [string]$script:SavedRulesSnapshot
			) {
				$message = if ($ruleCount -eq 0) {
					'There are no rules and no changes to save.'
				} else {
					'No changes to save. All current rules are already saved.'
				}
				[Windows.Forms.MessageBox]::Show(
					$message,
					'Nothing to Save',
					[Windows.Forms.MessageBoxButtons]::OK,
					[Windows.Forms.MessageBoxIcon]::Information
				) | Out-Null
				return
			}
			# An empty rule set is meaningful if the user removed the last saved rule.
			if ($ruleCount -eq 0 -and $null -eq $script:SavedRulesSnapshot) {
				[Windows.Forms.MessageBox]::Show(
					'There are no rules to save. Add at least one ALLOWED or BLOCKED rule first.',
					'Nothing to Save',
					[Windows.Forms.MessageBoxButtons]::OK,
					[Windows.Forms.MessageBoxIcon]::Information
				) | Out-Null
				return
			}
			# Save the complete rule set whenever its snapshot differs from the saved baseline.
			Save-RulesToJson
			Write-Log "Rules saved to: $script:RulesFile"
			[Windows.Forms.MessageBox]::Show(
				"Rules saved successfully!`r`n`r`n$script:RulesFile",
				"Save Rules",
				[Windows.Forms.MessageBoxButtons]::OK,
				[Windows.Forms.MessageBoxIcon]::Information
			) | Out-Null
		}
		catch {
			[Windows.Forms.MessageBox]::Show(
				"Saving failed:`r`n$($_.Exception.Message)",
				"Save Error",
				[Windows.Forms.MessageBoxButtons]::OK,
				[Windows.Forms.MessageBoxIcon]::Error
			) | Out-Null
		}
	})
	$footer.Controls.Add($actions, 0, 0)
	$log = [Windows.Forms.TextBox]::new()
	$log.Dock = 'Fill'
	$log.Multiline = $true
	$log.ReadOnly = $true
	$log.WordWrap = $false
	$log.ScrollBars = 'Vertical'
	$log.BackColor = [Drawing.Color]::FromArgb(8, 13, 24)
	$log.ForeColor = [Drawing.Color]::FromArgb(110, 231, 183)
	$log.Font = [Drawing.Font]::new('Consolas', 11)
	$log.BorderStyle = 'FixedSingle'
	$footer.Controls.Add($log, 1, 0)
	$root.Controls.Add($footer, 0, 4)

# FUNCTION Write-Log
function Write-Log($message) {
    $log.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $message`r`n")
}

# FUNCTION Get-ProcessAuditLogPath
function Get-ProcessAuditLogPath {
    param([datetime]$Date)
    if (-not (Test-Path -LiteralPath $script:ProcessLogDirectory -PathType Container)) {
        New-Item -Path $script:ProcessLogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $fileName = 'ProcessLog_{0}.log' -f $Date.ToString('yyyy-MM-dd')
    $filePath = Join-Path $script:ProcessLogDirectory $fileName
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        $header = "# Process Control Center audit log - {0}`r`n" -f $Date.ToString('yyyy-MM-dd')
        [System.IO.File]::WriteAllText(
            $filePath,
            $header,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    return $filePath
}

# FUNCTION Write-ProcessAuditLog
function Write-ProcessAuditLog {
    param(
        [Parameter(Mandatory = $true)][string]$Event,
        [string]$Details = ''
    )
    try {
        $now = Get-Date
        $filePath = Get-ProcessAuditLogPath -Date $now
        $cleanEvent = ($Event -replace '[\r\n]+', ' ').Trim().ToUpperInvariant()
        # Add a visual emoji marker to the audit-log event only; event behavior and details stay unchanged.
        $eventEmoji = switch -Regex ($cleanEvent) {
            '^MONITOR STARTED$'                   { '🟢'; break }
            '^MONITOR STOPPED$'                   { '🛑'; break }
            '^PANEL LIFETIME EXPIRED$'            { '⏳'; break }
            '^ALLOWED RULE ADDED$'                { '✅'; break }
            '^BLOCKED RULE ADDED$'                { '🚫'; break }
            '^ALLOWED RULE REMOVED$'              { '🗑️'; break }
            '^BLOCKED RULE REMOVED$'              { '🗑️'; break }
            '^ALLOWED PROCESS STARTED$'           { '🟩'; break }
            '^ALLOWED PROCESS DETECTED$'          { '🟢'; break }
            '^ALLOWED PROCESS ENDED$'             { '🔵'; break }
            '^BLOCKED PROCESS STARTED$'           { '🚨'; break }
            '^BLOCKED PROCESS DETECTED$'          { '🚫'; break }
            '^BLOCKED PROCESS ENDED$'             { '⚫'; break }
            '^BLOCKED PROCESS TERMINATED$'        { '🛑'; break }
            '^BLOCKED TERMINATION FAILED$'        { '❌'; break }
            '^BLOCKED TERMINATION SKIPPED$'       { '⚠️'; break }
            default                               { '📝' }
        }
        $cleanDetails = ([string]$Details -replace '[\r\n\t]+', ' ').Trim()
        $line = '[{0}] [{1} {2}] {3}' -f $now.ToString('yyyy-MM-dd HH:mm:ss.fff'), $eventEmoji, $cleanEvent, $cleanDetails
        [System.IO.File]::AppendAllText(
            $filePath,
            ($line + "`r`n"),
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    catch {
        # Audit logging must never stop process monitoring if the folder is unavailable.
        try {
            if ($null -ne $log -and -not $log.IsDisposed) {
                $log.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Process audit log write failed: $($_.Exception.Message)`r`n")
            }
        }
        catch {}
    }
}
# Create today's folder and file on application startup; future dates get their own file.
try {
    $null = Get-ProcessAuditLogPath -Date (Get-Date)
}
catch {
    Write-Log "Could not initialize daily process audit log: $($_.Exception.Message)"
}

# FUNCTION Update-ExpandedPauseButton
function Update-ExpandedPauseButton {
    if (
        $null -eq $script:ExpandedPauseTableButton -or
        $script:ExpandedPauseTableButton.IsDisposed
    ) {
        return
    }
    if ($script:PauseTableRefresh) {
        $script:ExpandedPauseTableButton.Text = 'RESUME TABLE'
        $script:ExpandedPauseTableButton.BackColor = $green
        $script:ExpandedPauseTableButton.FlatAppearance.MouseOverBackColor =
            [Drawing.Color]::FromArgb(16, 185, 129)
        $script:ExpandedPauseTableButton.FlatAppearance.MouseDownBackColor =
            [Drawing.Color]::FromArgb(4, 120, 87)
    }
    else {
        $script:ExpandedPauseTableButton.Text = 'PAUSE TABLE'
        $script:ExpandedPauseTableButton.BackColor = $blue
        $script:ExpandedPauseTableButton.FlatAppearance.MouseOverBackColor =
            [Drawing.Color]::FromArgb(59, 130, 246)
        $script:ExpandedPauseTableButton.FlatAppearance.MouseDownBackColor =
            [Drawing.Color]::FromArgb(29, 78, 216)
    }
}
$pauseTableButton.Add_Click({
    # Allow table pause only while monitoring or continuous scanning is active.
    if (-not $script:Running -and -not $script:ScanActive) {
        [Windows.Forms.MessageBox]::Show(
            'Monitoring and scanning have not been started. Start MONITOR or SCAN ALL PROCESSES before using table pause.',
            'Table Pause Unavailable',
            'OK',
            'Information'
        ) | Out-Null

        return
    }
    if (-not $script:PauseTableRefresh) {
        # Pause only the visible table refresh.
        $script:PauseTableRefresh = $true
		Update-ExpandedPauseButton
        $pauseTableButton.Text = 'RESUME TABLE'
        $pauseTableButton.BackColor = $green
        $pauseTableButton.FlatAppearance.MouseOverBackColor =
            [Drawing.Color]::FromArgb(16, 185, 129)
        $pauseTableButton.FlatAppearance.MouseDownBackColor =
            [Drawing.Color]::FromArgb(4, 120, 87)
        Write-Log 'Table display paused; background operations continue.'
        [Windows.Forms.MessageBox]::Show(
            "VISUAL TABLE PAUSE`r`n`r`n" +
            "Only the visible process table refresh is paused.`r`n`r`n" +
            "Process scanning, monitoring, rule enforcement, timers " +
            "and logging continue running in the background.`r`n`r`n" +
            "Click RESUME TABLE to refresh the table again.",
            'Visual Pause Only',
            'OK',
            'Information'
        ) | Out-Null
		}
		else {
			# Resume visual table refresh.
			$script:PauseTableRefresh = $false
			Update-ExpandedPauseButton
			$pauseTableButton.Text = 'PAUSE TABLE'
			$pauseTableButton.BackColor = $blue
			$pauseTableButton.FlatAppearance.MouseOverBackColor =
				[Drawing.Color]::FromArgb(59, 130, 246)
			$pauseTableButton.FlatAppearance.MouseDownBackColor =
				[Drawing.Color]::FromArgb(29, 78, 216)
			Write-Log 'Table display resumed.'
			if (-not $script:ScanWorkerBusy -and -not $script:Busy) {
				Start-AsyncScan
			}
		}
	})
	$openTableButton = New-Button 'OPEN FULL TABLE' ([Drawing.Color]::FromArgb(124, 58, 237)) 190
	[void]$processSwitchBar.Controls.Add($openTableButton)

# FUNCTION Current-Tab
function Current-Tab {
    if ($script:CurrentProcessKey -eq 'PS') {
        return $psTab
    }
    return $otherTab
}

# FUNCTION Update-ExpandedTableSwitchButtons
function Update-ExpandedTableSwitchButtons {
    if ($script:ExpandedTableKey -eq 'PS') {
        $psColor = $blue
        $otherColor = $card
    }
    else {
        $psColor = $card
        $otherColor = $blue
    }
    # PowerShell switch
    $script:ExpandedPsSwitch.BackColor = $psColor
    $script:ExpandedPsSwitch.FlatAppearance.MouseOverBackColor =
        [Drawing.Color]::FromArgb(
            [math]::Min(255, [int]$psColor.R + 18),
            [math]::Min(255, [int]$psColor.G + 18),
            [math]::Min(255, [int]$psColor.B + 18)
        )
    $script:ExpandedPsSwitch.FlatAppearance.MouseDownBackColor =
        [Drawing.Color]::FromArgb(
            [math]::Max(0, [int]$psColor.R - 20),
            [math]::Max(0, [int]$psColor.G - 20),
            [math]::Max(0, [int]$psColor.B - 20)
        )
    # Other Windows switch
    $script:ExpandedOtherSwitch.BackColor = $otherColor
    $script:ExpandedOtherSwitch.FlatAppearance.MouseOverBackColor =
        [Drawing.Color]::FromArgb(
            [math]::Min(255, [int]$otherColor.R + 18),
            [math]::Min(255, [int]$otherColor.G + 18),
            [math]::Min(255, [int]$otherColor.B + 18)
        )
    $script:ExpandedOtherSwitch.FlatAppearance.MouseDownBackColor =
        [Drawing.Color]::FromArgb(
            [math]::Max(0, [int]$otherColor.R - 20),
            [math]::Max(0, [int]$otherColor.G - 20),
            [math]::Max(0, [int]$otherColor.B - 20)
        )
}

# FUNCTION Restore-ExpandedTableGrid
function Restore-ExpandedTableGrid([string]$Key) {
    if ($null -eq $script:ExpandedTableStates -or
        -not $script:ExpandedTableStates.ContainsKey($Key)) {
        return
    }
    $state = $script:ExpandedTableStates[$Key]
    $grid = $state.Grid
    if ($grid.Parent -eq $script:ExpandedTableHost) {
        $script:ExpandedTableHost.Controls.Remove($grid)
    }
    if ($grid.Parent -ne $state.Parent) {
        if ($grid.Parent) {
            $grid.Parent.Controls.Remove($grid)
        }
        $grid.Dock = $state.Dock
        $grid.Margin = $state.Margin

        [void]$state.Parent.Controls.Add($grid)
    }
    else {
        $grid.Dock = $state.Dock
        $grid.Margin = $state.Margin
    }
    if ($state.Parent -is [Windows.Forms.TableLayoutPanel] -and
        $null -ne $state.CellPosition) {
        $state.Parent.SetCellPosition($grid, $state.CellPosition)
    }
}

# FUNCTION Show-ExpandedTableCategory
function Show-ExpandedTableCategory([string]$Key) {
    if ($script:ExpandedTableKey -eq $Key) {
        return
    }
    # Return the previous grid to its original layout.
    Restore-ExpandedTableGrid $script:ExpandedTableKey
    $state = $script:ExpandedTableStates[$Key]
    $grid = $state.Grid
    # Move the requested grid into the expanded window.
    if ($grid.Parent) {
        $grid.Parent.Controls.Remove($grid)
    }
    $grid.Dock = 'Fill'
    $grid.Margin = [Windows.Forms.Padding]::new(0)
    [void]$script:ExpandedTableHost.Controls.Add($grid)
    $script:ExpandedTableKey = $Key
    $script:ExpandedTableGrid = $grid
    if ($null -ne $script:ExpandedSearchBox -and -not $script:ExpandedSearchBox.IsDisposed) {
        $script:SyncProcessSearchBoxes = $true
        try { $script:ExpandedSearchBox.Text = [string]$script:ProcessTableFilters[$Key] }
        finally { $script:SyncProcessSearchBoxes = $false }
    }
    if ($Key -eq 'PS') {
        $script:ExpandedTableWindow.Text =
            'PowerShell Processes - Full Table'
    }
    else {
        $script:ExpandedTableWindow.Text =
            'Other Windows Processes - Full Table'
    }
    Show-ProcessCategory $Key
    Apply-ProcessTableFilter -Key $Key
    Update-ExpandedTableSwitchButtons
    Resize-ProcessColumns
    $grid.Focus() | Out-Null
}
$openTableButton.Add_Click({
    if ($script:ExpandedTableWindow -and
        -not $script:ExpandedTableWindow.IsDisposed) {
        $script:ExpandedTableWindow.Activate()
        return
    }
    $selectedTab = Current-Tab
    # Remember the original location of both tables.
    $states = @{}
    foreach ($t in @($psTab, $otherTab)) {
        $grid = $t.Grid
        $parent = $grid.Parent
        if ($null -eq $parent) {
            [Windows.Forms.MessageBox]::Show(
                'A process table is not available.',
                'Table Unavailable',
                'OK',
                'Information'
            ) | Out-Null
            return
        }
        $cellPosition = $null
        if ($parent -is [Windows.Forms.TableLayoutPanel]) {
            $cellPosition = $parent.GetCellPosition($grid)
        }
        $states[$t.Key] = @{
            Grid         = $grid
            Parent       = $parent
            Dock         = $grid.Dock
            Margin       = $grid.Margin
            CellPosition = $cellPosition
        }
    }
    # Create the expanded dark window.
    $tableWindow = [Windows.Forms.Form]::new()
    $tableWindow.Text = "$($selectedTab.Page.Text) - Full Table"
    $tableWindow.StartPosition = 'CenterScreen'
    $tableWindow.WindowState = 'Maximized'
    $tableWindow.MinimumSize = [Drawing.Size]::new(1000, 600)
    $tableWindow.BackColor = $bg
    $tableWindow.ForeColor = $fg
    $tableWindow.Font = [Drawing.Font]::new('Segoe UI', 10)
    $tableWindow.Padding = [Windows.Forms.Padding]::new(8)
    $tableWindow.KeyPreview = $true
    # Layout: search strip, category controls, then the table.
    $expandedLayout = [Windows.Forms.TableLayoutPanel]::new()
    $expandedLayout.Dock = 'Fill'
    $expandedLayout.ColumnCount = 1
    $expandedLayout.RowCount = 3
    $expandedLayout.BackColor = $bg
    $expandedLayout.Margin = [Windows.Forms.Padding]::new(0)
    $expandedLayout.Padding = [Windows.Forms.Padding]::new(0)
    [void]$expandedLayout.RowStyles.Add(
        [Windows.Forms.RowStyle]::new(
            [Windows.Forms.SizeType]::Absolute, 56
        )
    )
    [void]$expandedLayout.RowStyles.Add(
        [Windows.Forms.RowStyle]::new(
            [Windows.Forms.SizeType]::Absolute, 56
        )
    )
    [void]$expandedLayout.RowStyles.Add(
        [Windows.Forms.RowStyle]::new(
            [Windows.Forms.SizeType]::Percent, 100
        )
    )
    $expandedSearchBar = [Windows.Forms.FlowLayoutPanel]::new()
    $expandedSearchBar.Dock = 'Fill'
    $expandedSearchBar.FlowDirection = 'LeftToRight'
    $expandedSearchBar.WrapContents = $false
    $expandedSearchBar.BackColor = $bg
    $expandedSearchBar.Margin = [Windows.Forms.Padding]::new(0)
    $expandedSearchBar.Padding = [Windows.Forms.Padding]::new(0)
    $expandedSearchLabel = New-Label 'SEARCH PID / NAME / LOCATION / PUBLISHER' 9 $muted $true
    $expandedSearchLabel.Dock = 'None'
    $expandedSearchLabel.Size = [Drawing.Size]::new(310, 46)
    $expandedSearchLabel.Margin = [Windows.Forms.Padding]::new(4, 3, 4, 3)
    $expandedSearchBox = [Windows.Forms.TextBox]::new()
    $expandedSearchBox.Name = 'ExpandedProcessSearch'
    $expandedSearchBox.Size = [Drawing.Size]::new(420, 32)
    $expandedSearchBox.Margin = [Windows.Forms.Padding]::new(4, 7, 10, 4)
    $expandedSearchBox.BorderStyle = 'FixedSingle'
    $expandedSearchBox.BackColor = $script:Theme.Surface2
    $expandedSearchBox.ForeColor = $script:Theme.Text
    $expandedSearchBox.Font = [Drawing.Font]::new('Segoe UI', 11)
    $expandedSearchBox.Text = [string]$script:ProcessTableFilters[$selectedTab.Key]
    $script:ExpandedSearchBox = $expandedSearchBox
    $script:ExpandedResetFilterButton = New-Button '⛔ RESET FILTER' ([Drawing.Color]::FromArgb(217, 83, 54)) 190
    $script:ExpandedResetFilterButton.Size = [Drawing.Size]::new(155, 40)
    $script:ExpandedResetFilterButton.Margin = [Windows.Forms.Padding]::new(4, 4, 4, 3)
    $script:ExpandedResetFilterButton.Tag = $expandedSearchBox
    $expandedSearchBox.Add_TextChanged({
        param($sender, $e)
        if ($script:SyncProcessSearchBoxes) { return }
        if ([string]::IsNullOrWhiteSpace([string]$script:ExpandedTableKey)) { return }
        Set-ProcessTableFilter -Key ([string]$script:ExpandedTableKey) -Text ([string]$sender.Text) -Source $sender
    })
    $script:ExpandedResetFilterButton.Add_Click({
        param($sender, $e)
        $targetSearchBox = $sender.Tag
        if ($null -ne $targetSearchBox) { $targetSearchBox.Clear() }
    })
    [void]$expandedSearchBar.Controls.Add($expandedSearchLabel)
    [void]$expandedSearchBar.Controls.Add($expandedSearchBox)
    [void]$expandedSearchBar.Controls.Add($script:ExpandedResetFilterButton)
    $expandedLayout.Controls.Add($expandedSearchBar, 0, 0)
    $expandedSwitchBar = [Windows.Forms.FlowLayoutPanel]::new()
    $expandedSwitchBar.Dock = 'Fill'
    $expandedSwitchBar.FlowDirection = 'LeftToRight'
    $expandedSwitchBar.WrapContents = $false
    $expandedSwitchBar.BackColor = $bg
    $expandedSwitchBar.Margin = [Windows.Forms.Padding]::new(0)
    $expandedSwitchBar.Padding = [Windows.Forms.Padding]::new(0)
	$script:ExpandedPsSwitch =
		New-Button 'POWERSHELL PROCESSES' $blue 245
	$script:ExpandedOtherSwitch =
		New-Button 'OTHER WINDOWS PROCESSES' $card 280
	$expandedPauseCaption = if ($script:PauseTableRefresh) {
		'RESUME TABLE'
	} else {
		'PAUSE TABLE'
	}
	$expandedPauseColor = if ($script:PauseTableRefresh) {
		$green
	} else {
		$blue
	}
	$script:ExpandedPauseTableButton =
	New-Button $expandedPauseCaption $expandedPauseColor 175
	[void]$expandedSwitchBar.Controls.Add($script:ExpandedPsSwitch)
	[void]$expandedSwitchBar.Controls.Add($script:ExpandedOtherSwitch)
	[void]$expandedSwitchBar.Controls.Add($script:ExpandedPauseTableButton)
    $expandedHost = [Windows.Forms.Panel]::new()
    $expandedHost.Dock = 'Fill'
    $expandedHost.BackColor = $bg
    $expandedHost.Margin = [Windows.Forms.Padding]::new(0)
    $expandedHost.Padding = [Windows.Forms.Padding]::new(0)
    $expandedHost.BorderStyle = 'None'
    $expandedLayout.Controls.Add($expandedSwitchBar, 0, 1)
    $expandedLayout.Controls.Add($expandedHost, 0, 2)
    [void]$tableWindow.Controls.Add($expandedLayout)
    # Save state before moving the selected grid.
    $script:ExpandedTableStates = $states
    $script:ExpandedTableHost = $expandedHost
    $script:ExpandedTableKey = $selectedTab.Key
    $script:ExpandedTableGrid = $selectedTab.Grid
    $script:ExpandedTableWindow = $tableWindow
    $selectedGrid = $selectedTab.Grid
    $selectedGrid.Parent.Controls.Remove($selectedGrid)
    $selectedGrid.Dock = 'Fill'
    $selectedGrid.Margin = [Windows.Forms.Padding]::new(0)
    [void]$expandedHost.Controls.Add($selectedGrid)
    # Switch categories inside the expanded window.
    $script:ExpandedPsSwitch.Add_Click({
        Show-ExpandedTableCategory 'PS'
    })
    $script:ExpandedOtherSwitch.Add_Click({
        Show-ExpandedTableCategory 'Other'
    })
	$script:ExpandedPauseTableButton.Add_Click({
    $pauseTableButton.PerformClick()
    Update-ExpandedPauseButton
    })
    Update-ExpandedTableSwitchButtons
    # Keep the original category switches disabled while expanded.
    $psSwitch.Enabled = $false
    $otherSwitch.Enabled = $false
    $tableWindow.Add_Shown({
        Resize-ProcessColumns
        $script:ExpandedTableGrid.Focus() | Out-Null
    })
    $tableWindow.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [Windows.Forms.Keys]::Escape) {
            $sender.Close()
        }
    })
    # Return both tables to their original positions on close.
    $tableWindow.Add_FormClosing({
        Restore-ExpandedTableGrid 'PS'
        Restore-ExpandedTableGrid 'Other'
        $psSwitch.Enabled = $true
        $otherSwitch.Enabled = $true
        $script:ExpandedTableWindow = $null
        $script:ExpandedTableGrid = $null
        $script:ExpandedTableHost = $null
        $script:ExpandedTableStates = $null
        $script:ExpandedTableKey = $null
        $script:ExpandedPauseTableButton = $null
        $script:ExpandedSearchBox = $null
        $script:ExpandedResetFilterButton = $null
        Resize-ProcessColumns
    })
    $tableWindow.Show()
})

# FUNCTION Get-RulesSnapshot
function Get-RulesSnapshot {
    $data = [ordered]@{
        PS = [ordered]@{
            Allowed = @($script:Rules.PS.Allowed.Keys | ForEach-Object { [string]$_ } | Sort-Object)
            Blocked = @($script:Rules.PS.Blocked.Keys | ForEach-Object { [string]$_ } | Sort-Object)
        }
        Other = [ordered]@{
            Allowed = @($script:Rules.Other.Allowed.Keys | ForEach-Object { [string]$_ } | Sort-Object)
            Blocked = @($script:Rules.Other.Blocked.Keys | ForEach-Object { [string]$_ } | Sort-Object)
        }
    }
    return (ConvertTo-Json -InputObject $data -Depth 5 -Compress)
}

# FUNCTION Save-RulesToJson
function Save-RulesToJson {
    $folder = Split-Path -Parent $script:RulesFile
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -Path $folder -ItemType Directory -Force |
            Out-Null
    }
    $data = @{
        PS = @{
            Allowed = @($script:Rules.PS.Allowed.Keys)
            Blocked = @($script:Rules.PS.Blocked.Keys)
        }
        Other = @{
            Allowed = @($script:Rules.Other.Allowed.Keys)
            Blocked = @($script:Rules.Other.Blocked.Keys)
        }
    }
    $json = ConvertTo-Json -InputObject $data -Depth 5
    Set-Content -LiteralPath $script:RulesFile `
        -Value $json -Encoding UTF8 -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $script:RulesFile)) {
        throw "JSON file was not created: $script:RulesFile"
    }
    $script:SavedRulesSnapshot = Get-RulesSnapshot
}

# FUNCTION Load-RulesFromJson
function Load-RulesFromJson {
    if (-not (Test-Path -LiteralPath $script:RulesFile)) {
        # No file yet: the current empty rule set is the starting baseline.
        $script:SavedRulesSnapshot = Get-RulesSnapshot
        return
    }
    try {
        $json = Get-Content -LiteralPath $script:RulesFile `
            -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            $script:SavedRulesSnapshot = Get-RulesSnapshot
            return
        }
        $data = $json | ConvertFrom-Json -ErrorAction Stop
        foreach ($type in @('PS', 'Other')) {
            foreach ($ruleType in @('Allowed', 'Blocked')) {
                $script:Rules[$type][$ruleType].Clear()
                $entries = @($data.$type.$ruleType)
                foreach ($entry in $entries) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$entry)) {
                        $script:Rules[$type][$ruleType][[string]$entry] = $true
                    }
                }
            }
        }
        Write-Log "Rules loaded from JSON: $script:RulesFile"
        $script:SavedRulesSnapshot = Get-RulesSnapshot
    }
    catch {
        # If loading failed, leave the baseline unset so the user can attempt to save/repair the current rules.
        $script:SavedRulesSnapshot = $null
        [Windows.Forms.MessageBox]::Show(
            "Could not load saved rules:`r`n$($_.Exception.Message)",
            "Load Rules Error",
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

# FUNCTION Update-AutoStartButton
function Update-AutoStartButton {
    if ($null -eq $script:AutoStartButton -or $script:AutoStartButton.IsDisposed) {
        return
    }
    if ($script:AutoStartEnabled) {
        $script:AutoStartButton.Text = 'AUTO START: ON'
        $script:AutoStartButton.BackColor = $script:Theme.Green
        $script:AutoStartButton.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(16, 185, 129)
        $script:AutoStartButton.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(4, 120, 87)
    }
    else {
        $script:AutoStartButton.Text = 'AUTO START: OFF'
        $script:AutoStartButton.BackColor = [Drawing.Color]::FromArgb(124, 58, 237)
        $script:AutoStartButton.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(139, 92, 246)
        $script:AutoStartButton.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(91, 33, 182)
    }
}

# FUNCTION Update-TaskButton
function Update-TaskButton {
    if ($null -eq $script:TaskButton -or $script:TaskButton.IsDisposed) {
        return
    }
    $taskExists = $false
    try {
        $registeredTask = Get-ScheduledTask -TaskName $script:AutoTaskName -ErrorAction Stop
        $taskExists = ($null -ne $registeredTask)
    }
    catch {
        $taskExists = $false
    }
    if ($taskExists) {
        $script:TaskButton.Text = 'TASK ON'
        $script:TaskButton.BackColor = [Drawing.Color]::FromArgb(5, 150, 105)
        $script:TaskButton.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(16, 185, 129)
        $script:TaskButton.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(4, 120, 87)
    }
    else {
        $script:TaskButton.Text = 'TASK OFF'
        $script:TaskButton.BackColor = [Drawing.Color]::FromArgb(180, 83, 9)
        $script:TaskButton.FlatAppearance.MouseOverBackColor = [Drawing.Color]::FromArgb(217, 119, 6)
        $script:TaskButton.FlatAppearance.MouseDownBackColor = [Drawing.Color]::FromArgb(146, 64, 14)
    }
}

# FUNCTION Resolve-ApplicationExePath
function Resolve-ApplicationExePath {
    $candidate = Join-Path $script:AppRoot "ProcessManager.exe"
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "ProcessManager.exe was not found at the expected location: $candidate"
    }
    return [System.IO.Path]::GetFullPath($candidate)
}

# FUNCTION Test-AutoStartRequirements
function Test-AutoStartRequirements {
    # AUTO START and TASK ON both require a valid Rules.json containing at least one rule.
    if (-not (Test-Path -LiteralPath $script:RulesFile -PathType Leaf)) {
        [Windows.Forms.MessageBox]::Show(
            "This option cannot be enabled because the saved rules file does not exist:`r`n$script:RulesFile`r`n`r`nAdd at least one rule to ALLOWED or BLOCKED and click SAVE RULES first.",
            'Saved Rules Required',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }
    $savedRuleCount = 0
    try {
        $savedRulesJson = Get-Content -LiteralPath $script:RulesFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($savedRulesJson)) {
            throw 'Rules.json is empty.'
        }
        $savedRuleData = $savedRulesJson | ConvertFrom-Json -ErrorAction Stop
        foreach ($savedCategory in @('PS', 'Other')) {
            foreach ($savedRuleType in @('Allowed', 'Blocked')) {
                foreach ($savedEntry in @($savedRuleData.$savedCategory.$savedRuleType)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$savedEntry)) {
                        $savedRuleCount++
                    }
                }
            }
        }
    }
    catch {
        [Windows.Forms.MessageBox]::Show(
            "The saved Rules.json file is empty or invalid.`r`n`r`n$script:RulesFile`r`n`r`nAdd at least one rule and use SAVE RULES before enabling this option.`r`n`r`nDetails: $($_.Exception.Message)",
            'Saved Rules Required',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }
    if ($savedRuleCount -eq 0) {
        [Windows.Forms.MessageBox]::Show(
            "Rules.json contains no saved Allowed or Blocked rules.`r`n`r`nAdd at least one rule to ALLOWED or BLOCKED and click SAVE RULES first.",
            'No Saved Process Rules',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }
    $currentRuleCount = 0
    foreach ($category in @('PS', 'Other')) {
        $currentRuleCount += $script:Rules[$category].Allowed.Count
        $currentRuleCount += $script:Rules[$category].Blocked.Count
    }
    if ($currentRuleCount -eq 0) {
        [Windows.Forms.MessageBox]::Show(
            'There are no current Allowed or Blocked process rules. Load or add a rule, save it to Rules.json, then try again.',
            'No Process Rules',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }
    return $true
}

# FUNCTION Get-ConfiguredDurations
function Get-ConfiguredDurations {
    $monitorHours = [int]$monitorDuration[0].Value
    $monitorMinutes = [int]$monitorDuration[1].Value
    $monitorSecondsPart = [int]$monitorDuration[2].Value
    $panelHours = [int]$panelDuration[0].Value
    $panelMinutes = [int]$panelDuration[1].Value
    $panelSecondsPart = [int]$panelDuration[2].Value
    $monitorTotalSeconds = ($monitorHours * 3600) + ($monitorMinutes * 60) + $monitorSecondsPart
    $panelTotalSeconds = ($panelHours * 3600) + ($panelMinutes * 60) + $panelSecondsPart
    if ($monitorTotalSeconds -le 0 -or $panelTotalSeconds -le 0) {
        [Windows.Forms.MessageBox]::Show(
            'Both MONITOR DURATION and PANEL LIFETIME must be greater than zero.',
            'Invalid Duration',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $null
    }
    return [pscustomobject]@{
        MonitorHours = $monitorHours
        MonitorMinutes = $monitorMinutes
        MonitorSeconds = $monitorSecondsPart
        PanelHours = $panelHours
        PanelMinutes = $panelMinutes
        PanelSeconds = $panelSecondsPart
    }
}

# FUNCTION Save-AutoStartSettings
function Save-AutoStartSettings {
    param(
        [bool]$Enabled,
        [int]$MonitorHours,
        [int]$MonitorMinutes,
        [int]$MonitorSeconds,
        [int]$PanelHours,
        [int]$PanelMinutes,
        [int]$PanelSeconds
    )
    $settingsFolder = Split-Path -Parent $script:AutoStartSettingsFile
    if (-not (Test-Path -LiteralPath $settingsFolder -PathType Container)) {
        New-Item -Path $settingsFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $settings = [ordered]@{
        Enabled = $Enabled
        MonitorHours = $MonitorHours
        MonitorMinutes = $MonitorMinutes
        MonitorSeconds = $MonitorSeconds
        PanelHours = $PanelHours
        PanelMinutes = $PanelMinutes
        PanelSeconds = $PanelSeconds
    }
    try {
        if (Test-Path -LiteralPath $script:AutoStartSettingsFile -PathType Leaf) {
            $oldSettings = Get-Content -LiteralPath $script:AutoStartSettingsFile -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            foreach ($timeKey in 'MonitorStartTime', 'PanelStartTime', 'MonitorStopTime', 'PanelStopTime') {
                $oldValue = $oldSettings.$timeKey
                if ($null -ne $oldValue) {
                    if ($oldValue -is [datetime]) { $oldValue = $oldValue.ToString('yyyy-MM-dd HH:mm:ss') }
                    $settings[$timeKey] = $oldValue
                }
            }
        }
    }
    catch { }
    ConvertTo-Json -InputObject $settings -Depth 3 |
        Set-Content -LiteralPath $script:AutoStartSettingsFile -Encoding UTF8 -ErrorAction Stop
}

# FUNCTION Update-AutoStartTimeInfo
# Writes only start/stop times into AutoStart.json; every other value stays exactly as saved.
function Update-AutoStartTimeInfo {
    param(
        [System.Collections.IDictionary]$Values,
        [string[]]$RemoveKeys = @()
    )
    try {
        $settings = [ordered]@{}
        if (Test-Path -LiteralPath $script:AutoStartSettingsFile -PathType Leaf) {
            $existing = Get-Content -LiteralPath $script:AutoStartSettingsFile -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            foreach ($prop in $existing.PSObject.Properties) {
                $propValue = $prop.Value
                if ($propValue -is [datetime]) { $propValue = $propValue.ToString('yyyy-MM-dd HH:mm:ss') }
                $settings[$prop.Name] = $propValue
            }
        }
        if ($settings.Count -eq 0) {
            $settings['Enabled'] = [bool]$script:AutoStartEnabled
            $settings['MonitorHours'] = [int]$monitorDuration[0].Value
            $settings['MonitorMinutes'] = [int]$monitorDuration[1].Value
            $settings['MonitorSeconds'] = [int]$monitorDuration[2].Value
            $settings['PanelHours'] = [int]$panelDuration[0].Value
            $settings['PanelMinutes'] = [int]$panelDuration[1].Value
            $settings['PanelSeconds'] = [int]$panelDuration[2].Value
        }
        foreach ($removeKey in $RemoveKeys) { $settings.Remove($removeKey) }
        foreach ($valueKey in $Values.Keys) { $settings[$valueKey] = $Values[$valueKey] }
        $settingsFolder = Split-Path -Parent $script:AutoStartSettingsFile
        if (-not (Test-Path -LiteralPath $settingsFolder -PathType Container)) {
            New-Item -Path $settingsFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        ConvertTo-Json -InputObject $settings -Depth 3 |
            Set-Content -LiteralPath $script:AutoStartSettingsFile -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Time info is informational only; never break the monitor because of it.
    }
}

# FUNCTION Toggle-AutoStartSetting
function Toggle-AutoStartSetting {
    try {
        if ($script:AutoStartEnabled) {
            # Disabling AUTO START must always be possible, even when a timer spinner is zero.
            $durations = [pscustomobject]@{
                MonitorHours = [int]$monitorDuration[0].Value
                MonitorMinutes = [int]$monitorDuration[1].Value
                MonitorSeconds = [int]$monitorDuration[2].Value
                PanelHours = [int]$panelDuration[0].Value
                PanelMinutes = [int]$panelDuration[1].Value
                PanelSeconds = [int]$panelDuration[2].Value
            }
            Save-AutoStartSettings -Enabled $false `
                -MonitorHours $durations.MonitorHours -MonitorMinutes $durations.MonitorMinutes -MonitorSeconds $durations.MonitorSeconds `
                -PanelHours $durations.PanelHours -PanelMinutes $durations.PanelMinutes -PanelSeconds $durations.PanelSeconds
            $script:AutoStartEnabled = $false
            Update-AutoStartButton
            Write-Log 'AUTO START disabled. Newly launched ProcessManager.exe instances will not start monitoring automatically.'
            [Windows.Forms.MessageBox]::Show(
                'AUTO START is OFF. Launching ProcessManager.exe will no longer start monitoring automatically.',
                'AUTO START Disabled',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }
        if (-not (Test-AutoStartRequirements)) { return }
        $durations = Get-ConfiguredDurations
        if ($null -eq $durations) { return }
        Save-RulesToJson
        Save-AutoStartSettings -Enabled $true `
            -MonitorHours $durations.MonitorHours -MonitorMinutes $durations.MonitorMinutes -MonitorSeconds $durations.MonitorSeconds `
            -PanelHours $durations.PanelHours -PanelMinutes $durations.PanelMinutes -PanelSeconds $durations.PanelSeconds
        $script:AutoStartEnabled = $true
        Update-AutoStartButton
        Write-Log ('AUTO START preference enabled. ProcessManager.exe launch will start monitoring automatically; durations {0:00}:{1:00}:{2:00} and panel lifetime {3:00}:{4:00}:{5:00}.' -f `
            $durations.MonitorHours, $durations.MonitorMinutes, $durations.MonitorSeconds, $durations.PanelHours, $durations.PanelMinutes, $durations.PanelSeconds)
        [Windows.Forms.MessageBox]::Show(
            ("AUTO START is ON.`r`n`r`nWhenever ProcessManager.exe is launched, monitoring will start automatically.`r`n`r`nMonitor duration: {0:00}:{1:00}:{2:00}`r`nPanel lifetime: {3:00}:{4:00}:{5:00}`r`n`r`nWindows logon scheduling is controlled separately by the TASK ON/OFF button." -f `
                $durations.MonitorHours, $durations.MonitorMinutes, $durations.MonitorSeconds, $durations.PanelHours, $durations.PanelMinutes, $durations.PanelSeconds),
            'AUTO START Enabled',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        Update-AutoStartButton
        Write-Log "AUTO START error: $($_.Exception.Message)"
        [Windows.Forms.MessageBox]::Show(
            "Failed to configure AUTO START:`r`n`r`n$($_.Exception.Message)",
            'AUTO START Error',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

# FUNCTION Toggle-TaskScheduler
function Toggle-TaskScheduler {
    try {
        # Clicking TASK ON while it exists removes the task immediately.
        $existingTask = Get-ScheduledTask -TaskName $script:AutoTaskName -ErrorAction SilentlyContinue
        if ($null -ne $existingTask) {
            Unregister-ScheduledTask -TaskName $script:AutoTaskName -Confirm:$false -ErrorAction Stop
            Update-TaskButton
            Write-Log 'TASK OFF. Scheduled Task removed.'
            [Windows.Forms.MessageBox]::Show(
                'Windows logon task has been removed. AUTO START preference is unchanged.',
                'TASK OFF',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }
        if (-not (Test-AutoStartRequirements)) { return }
        $durations = Get-ConfiguredDurations
        if ($null -eq $durations) { return }
        $applicationExePath = Resolve-ApplicationExePath
        Save-RulesToJson

        $workingDirectory = $script:AppRoot
        $arguments = (
            '-end -AutoStartMonitor ' +
            '-AutoMonitorHours {0} -AutoMonitorMinutes {1} -AutoMonitorSeconds {2} ' +
            '-AutoPanelHours {3} -AutoPanelMinutes {4} -AutoPanelSeconds {5}'
        ) -f $durations.MonitorHours, $durations.MonitorMinutes, $durations.MonitorSeconds,
             $durations.PanelHours, $durations.PanelMinutes, $durations.PanelSeconds
        $action = New-ScheduledTaskAction -Execute $applicationExePath -Argument $arguments -WorkingDirectory $workingDirectory
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
        $trigger.Delay = 'PT2M'
        $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew
        Register-ScheduledTask `
            -TaskName $script:AutoTaskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Description 'Starts Process Control Center two minutes after user logon and starts monitoring automatically.' `
            -Force `
            -ErrorAction Stop | Out-Null
        Update-TaskButton
        Write-Log ('TASK ON enabled. Monitor duration {0:00}:{1:00}:{2:00}; panel lifetime {3:00}:{4:00}:{5:00}.' -f `
            $durations.MonitorHours, $durations.MonitorMinutes, $durations.MonitorSeconds, $durations.PanelHours, $durations.PanelMinutes, $durations.PanelSeconds)
        [Windows.Forms.MessageBox]::Show(
            ("TASK ON is enabled.`r`n`r`nProcessManager.exe will open 2 minutes after you sign in to Windows and START MONITOR will start automatically.`r`n`r`nMonitor duration: {0:00}:{1:00}:{2:00}`r`nPanel lifetime: {3:00}:{4:00}:{5:00}`r`n`r`nClick TASK ON again to remove the scheduled task." -f `
                $durations.MonitorHours, $durations.MonitorMinutes, $durations.MonitorSeconds, $durations.PanelHours, $durations.PanelMinutes, $durations.PanelSeconds),
            'TASK ON',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        Update-TaskButton
        Write-Log "TASK Scheduler error: $($_.Exception.Message)"
        [Windows.Forms.MessageBox]::Show(
            "Failed to configure the Windows Scheduled Task:`r`n`r`n$($_.Exception.Message)",
            'TASK Scheduler Error',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}
$script:AutoStartButton.Add_Click({
    Toggle-AutoStartSetting
})
$script:TaskButton.Add_Click({
    Toggle-TaskScheduler
})

# FUNCTION Update-MonitorRuleCounts
function Update-MonitorRuleCounts {
    $allowedTotal =
        $script:Rules.PS.Allowed.Count +
        $script:Rules.Other.Allowed.Count
    $blockedTotal =
        $script:Rules.PS.Blocked.Count +
        $script:Rules.Other.Blocked.Count
    $monitorAllowedCount.Text = "ALLOWED $allowedTotal"
    $monitorBlockedCount.Text = "BLOCKED $blockedTotal"
}

# FUNCTION Update-InactiveRuleState
function Update-InactiveRuleState {
    try {
        $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)
        $activePS = @{}
        $activeOther = @{}
        foreach ($p in $processes) {
            if (-not [string]::IsNullOrWhiteSpace($p.CommandLine)) {
                $activePS[[string]$p.CommandLine] = $true
            }
            if (-not [string]::IsNullOrWhiteSpace($p.ExecutablePath)) {
                $path = ([string]$p.ExecutablePath).Trim()
                $activeOther[$path] = $true
            }
        }
        $inactive = @{}
        foreach ($type in @('PS', 'Other')) {
            foreach ($ruleType in @('Allowed', 'Blocked')) {
                foreach ($identity in $script:Rules[$type][$ruleType].Keys) {
                    $identity = [string]$identity
                    if ($type -eq 'PS') {
                        $isActive = $activePS.ContainsKey($identity)
                    }
                    else {
                        $isActive = $activeOther.ContainsKey($identity.Trim())
                    }
                    if (-not $isActive) {
                        $stateKey = "$type|$ruleType|$identity"
                        $inactive[$stateKey] = $true
                    }
                }
            }
        }
        # Azhuriraj ja sostojbata samo ako proverката zavrshi uspesno.
        $script:InactiveRules = $inactive
    }
    catch {
        Write-Log "Could not check process status: $($_.Exception.Message)"
    }
}

# FUNCTION Set-SingleRuleListSelection
function Set-SingleRuleListSelection {
    param(
        [System.Windows.Forms.ListBox]$SelectedList
    )
    foreach ($list in @(
        $psTab.Allow,
        $psTab.Block,
        $otherTab.Allow,
        $otherTab.Block
    )) {
        if (($list -ne $SelectedList) -and ($list.SelectedIndex -ge 0)) {
            $list.ClearSelected()
        }
    }
}

# FUNCTION Enable-RuleListDrawing
function Enable-RuleListDrawing {
    param(
        [System.Windows.Forms.ListBox]$List,
        [string]$Type,
        [string]$RuleType
    )
    $List.Name = "RuleList_${Type}_${RuleType}"
    # Ne registriraj povtorno event-i ako listata e vekje konfigurirana.
    if ($List.DrawMode -eq [System.Windows.Forms.DrawMode]::OwnerDrawFixed) {
        return
    }
    $List.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $List.ItemHeight = [Math]::Max($List.Font.Height + 6, 20)
    $List.IntegralHeight = $false
    # Crtanje na stavkite vo listata.
    $List.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0) {
            return
        }
        $identity = [string]$sender.Items[$e.Index]
        $parts = $sender.Name -split '_'
        $typeName = $parts[1]
        $ruleName = $parts[2]
        $stateKey = "$typeName|$ruleName|$identity"
        $notFound = (
            $null -ne $script:InactiveRules -and
            $script:InactiveRules.ContainsKey($stateKey)
        )
        $displayText = $identity
        if ($notFound) {
            if ($typeName -eq 'Other') {
                $processName = [System.IO.Path]::GetFileName($identity)
            }
            else {
                if ($identity -match '^\s*"?([^"]+?\.exe)"?(?:\s|$)') {
                    $processName = [System.IO.Path]::GetFileName($matches[1])
                }
                else {
                    $processName = 'PowerShell process'
                }
            }
            $displayText = "$processName — PROCESS NOT FOUND ⛔"
        }
        $e.DrawBackground()
        $textColor = [System.Drawing.Color]::White
        $selectedBrush = $null
        try {
            if ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) {
                $selectedBackColor = [System.Drawing.Color]::FromArgb(55, 95, 145)
                $selectedBrush = New-Object System.Drawing.SolidBrush($selectedBackColor)
                $e.Graphics.FillRectangle($selectedBrush, $e.Bounds)
                $textColor = [System.Drawing.Color]::White
            }
            elseif ($notFound) {
                $textColor = [System.Drawing.Color]::DarkOrange
            }
            else {
                $textColor = $sender.ForeColor
            }
            if (
                $e.Bounds.Width -gt 0 -and
                $e.Bounds.Height -gt 0 -and
                $null -ne $sender.Font
            ) {
                [System.Windows.Forms.TextRenderer]::DrawText(
                    $e.Graphics,
                    [string]$displayText,
                    $sender.Font,
                    $e.Bounds,
                    $textColor,
                    [System.Windows.Forms.TextFormatFlags]::Left -bor
                    [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                    [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor
                    [System.Windows.Forms.TextFormatFlags]::EndEllipsis
                )
            }
        }
        finally {
            if ($null -ne $selectedBrush) {
                $selectedBrush.Dispose()
            }
        }
        $e.DrawFocusRectangle()
    })
    # Samo edna selekcija megju Allowed/Blocked listite.
    $List.Add_SelectedIndexChanged({
        param($sender, $e)

        if ($sender.SelectedIndex -ge 0) {
            Set-SingleRuleListSelection -SelectedList $sender
        }
    })
}

# FUNCTION Refresh-RuleLists
function Refresh-RuleLists {
    Enable-RuleListDrawing $psTab.Allow 'PS' 'Allowed'
    Enable-RuleListDrawing $psTab.Block 'PS' 'Blocked'
    Enable-RuleListDrawing $otherTab.Allow 'Other' 'Allowed'
    Enable-RuleListDrawing $otherTab.Block 'Other' 'Blocked'
    Update-InactiveRuleState
    foreach ($t in @($psTab, $otherTab)) {
        $t.Allow.Items.Clear()
        $t.Block.Items.Clear()
        foreach ($r in $script:Rules[$t.Key].Allowed.Keys) {
            [void]$t.Allow.Items.Add($r)
        }
        foreach ($r in $script:Rules[$t.Key].Blocked.Keys) {
            [void]$t.Block.Items.Add($r)
        }
        $t.Allow.Invalidate()
        $t.Block.Invalidate()
    }
    Update-ProcessSwitchCounts
    Update-MonitorRuleCounts
}
Load-RulesFromJson
Refresh-RuleLists
Update-AutoStartButton
Update-TaskButton

# Timer za avtomatska proverka na aktivnosta na procesite
$script:RuleStatusTimer = New-Object System.Windows.Forms.Timer
$script:RuleStatusTimer.Interval = 3000
$script:RuleStatusTimer.Add_Tick({
    Update-InactiveRuleState
    foreach ($t in @($psTab, $otherTab)) {
        $t.Allow.Invalidate()
        $t.Block.Invalidate()
    }
})
$script:RuleStatusTimer.Start()

foreach ($t in @($psTab, $otherTab)) {
    $grid = $t.Grid
    $grid.Tag = @{
        LastSelectedItem = $null
        PendingItem      = $null
        TogglePending    = $false
    }
    $grid.Add_ItemSelectionChanged({
        param($sender, $e)
        if (-not $e.IsSelected) {
            $state = $sender.Tag
            if (
                $null -ne $state -and
                [object]::ReferenceEquals($state.LastSelectedItem, $e.Item)
            ) {
                $state.LastSelectedItem = $null
            }
        }
    })
    $grid.Add_MouseDown({
        param($sender, $e)
        $state = $sender.Tag
        $state.PendingItem = $null
        $state.TogglePending = $false
        if ($e.Button -ne [Windows.Forms.MouseButtons]::Left) { return }
        $hit = $sender.HitTest($e.Location)
        if ($null -eq $hit.Item) { return }
        $state.PendingItem = $hit.Item
        $state.TogglePending = (
            $null -ne $state.LastSelectedItem -and
            [object]::ReferenceEquals($state.LastSelectedItem, $hit.Item)
        )
    })
    $grid.Add_MouseUp({
        param($sender, $e)
        $state = $sender.Tag
        if (
            $e.Button -eq [Windows.Forms.MouseButtons]::Left -and
            $state.TogglePending -and
            $null -ne $state.PendingItem
        ) {
            $hit = $sender.HitTest($e.Location)
            if ([object]::ReferenceEquals($hit.Item, $state.PendingItem)) {
                if ($state.PendingItem.Selected) {
                    $state.PendingItem.Selected = $false
                }
                $state.PendingItem.Focused = $false
            }
        }
        if ($sender.SelectedItems.Count -gt 0) {
            $state.LastSelectedItem = $sender.SelectedItems[0]
        }
        else {
            $state.LastSelectedItem = $null
        }
        $state.PendingItem = $null
        $state.TogglePending = $false
    })
    # Keep click-toggle behavior correct after using keyboard navigation too.
    $grid.Add_KeyUp({
        param($sender, $e)
        $state = $sender.Tag
        if ($sender.SelectedItems.Count -gt 0) {
            $state.LastSelectedItem = $sender.SelectedItems[0]
        }
        else {
            $state.LastSelectedItem = $null
        }
    })
}

# FUNCTION Get-RuleIdentity
function Get-RuleIdentity($p, $key) {
    if ($key -eq 'PS') { return [string]$p.CommandLine }
    return [string]$p.ExecutablePath
}

# FUNCTION Get-ProcessPublisher
function Get-ProcessPublisher([string]$ExecutablePath) {
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { return '' }
    $path = $ExecutablePath.Trim()
    if ($script:PublisherCache.ContainsKey($path)) {
        return [string]$script:PublisherCache[$path]
    }
    $publisher = ''
    try {
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
        $publisher = [string]$versionInfo.CompanyName
        if ([string]::IsNullOrWhiteSpace($publisher)) {
            $publisher = [string]$versionInfo.LegalCopyright
        }
    }
    catch {
        $publisher = ''
    }
    $script:PublisherCache[$path] = $publisher
    return $publisher
}

# FUNCTION Test-ProcessItemMatchesSearch
function Test-ProcessItemMatchesSearch($Item, [string]$Query) {
    if ([string]::IsNullOrWhiteSpace($Query)) { return $true }
    if ($null -eq $Item -or $null -eq $Item.Tag -or $Item.Tag.SearchPlaceholder) { return $false }
    $tag = $Item.Tag
    $searchableValues = @(
        [string]$tag.PID,
        [string]$tag.Name,
        [string]$tag.Identity,
        [string]$tag.ExecutablePath,
        [string]$tag.Publisher
    )
    $searchableText = $searchableValues -join "`n"
    return ($searchableText.IndexOf($Query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

# FUNCTION Get-ProcessItemOrder
function Get-ProcessItemOrder($Item) {
    if ($null -ne $Item -and $null -ne $Item.Tag -and $Item.Tag.ContainsKey('Order')) {
        return [long]$Item.Tag.Order
    }
    return [long]0
}

# FUNCTION Insert-ProcessItemByOrder
function Insert-ProcessItemByOrder([System.Windows.Forms.ListView]$Grid, $Item) {
    $wantedOrder = Get-ProcessItemOrder $Item
    $insertIndex = $Grid.Items.Count
    for ($i = 0; $i -lt $Grid.Items.Count; $i++) {
        $currentOrder = Get-ProcessItemOrder $Grid.Items[$i]
        if ($currentOrder -lt $wantedOrder) {
            $insertIndex = $i
            break
        }
    }
    [void]$Grid.Items.Insert($insertIndex, $Item)
}

# FUNCTION Apply-ProcessTableFilter
function Apply-ProcessTableFilter([string]$Key) {
    if ($Key -notin @('PS', 'Other')) { return }
    $tab = if ($Key -eq 'PS') { $psTab } else { $otherTab }
    if ($null -eq $tab -or $null -eq $tab.Grid -or $tab.Grid.IsDisposed) { return }
    $grid = $tab.Grid
    $query = [string]$script:ProcessTableFilters[$Key]
    $hiddenItems = $script:FilteredOutProcessItems[$Key]
    if ($null -eq $hiddenItems) {
        $hiddenItems = @{}
        $script:FilteredOutProcessItems[$Key] = $hiddenItems
    }
    $grid.BeginUpdate()
    try {
        $existingPlaceholder = $null
        foreach ($row in @($grid.Items)) {
            if ($null -ne $row.Tag -and $row.Tag.SearchPlaceholder) {
                $existingPlaceholder = $row
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($query) -and $null -ne $existingPlaceholder) {
            [void]$grid.Items.Remove($existingPlaceholder)
            $existingPlaceholder = $null
        }
        # Move visible rows that do not match into a per-category cache.
        if (-not [string]::IsNullOrWhiteSpace($query)) {
            for ($i = $grid.Items.Count - 1; $i -ge 0; $i--) {
                $row = $grid.Items[$i]
                if ($null -ne $row.Tag -and $row.Tag.SearchPlaceholder) { continue }
                if (-not (Test-ProcessItemMatchesSearch -Item $row -Query $query)) {
                    if ($null -ne $row.Tag -and -not $row.Tag.SearchPlaceholder) {
                        $rowKey = '{0}|{1}' -f [int]$row.Tag.PID, [string]$row.Tag.Identity
                        $hiddenItems[$rowKey] = $row
                    }
                    $grid.Items.RemoveAt($i)
                }
            }
        }
        # Restore rows which match the current query (or all rows when resetting).
        $restoreRows = @(
            foreach ($entry in $hiddenItems.GetEnumerator()) {
                if (Test-ProcessItemMatchesSearch -Item $entry.Value -Query $query) {
                    [pscustomobject]@{
                        Key = [string]$entry.Key
                        Item = $entry.Value
                        Order = (Get-ProcessItemOrder $entry.Value)
                    }
                }
            }
        ) | Sort-Object -Property Order -Descending
        foreach ($entry in $restoreRows) {
            [void]$hiddenItems.Remove([string]$entry.Key)
            Insert-ProcessItemByOrder -Grid $grid -Item $entry.Item
        }
        # If a typed query has no matches, show one stable message row inside the table.
        if (-not [string]::IsNullOrWhiteSpace($query)) {
            $visibleProcessCount = 0
            foreach ($row in $grid.Items) {
                if ($null -eq $row.Tag -or -not $row.Tag.SearchPlaceholder) {
                    $visibleProcessCount++
                }
            }
            if ($visibleProcessCount -eq 0 -and $null -eq $existingPlaceholder) {
                $emptyRow = [Windows.Forms.ListViewItem]::new('—')
                [void]$emptyRow.SubItems.Add('⚠️ NO SUCH PROCESS')
                [void]$emptyRow.SubItems.Add('⚠️ NOT FOUND')
                [void]$emptyRow.SubItems.Add('⛔ No process matches this search.')
                $emptyRow.Tag = @{ SearchPlaceholder = $true; PID = -1; Name = '⛔ NO SUCH PROCESS'; Identity = ''; Key = $Key }
                [void]$grid.Items.Add($emptyRow)
            }
            elseif ($visibleProcessCount -gt 0 -and $null -ne $existingPlaceholder) {
                [void]$grid.Items.Remove($existingPlaceholder)
            }
        }
    }
    finally {
        $grid.EndUpdate()
    }
}

# FUNCTION Set-ProcessTableFilter
function Set-ProcessTableFilter([string]$Key, [string]$Text, $Source = $null) {
    if ($Key -notin @('PS', 'Other')) { return }
    $script:ProcessTableFilters[$Key] = [string]$Text
    $tab = if ($Key -eq 'PS') { $psTab } else { $otherTab }
    $script:SyncProcessSearchBoxes = $true
    try {
        if ($null -ne $tab.SearchBox -and -not $tab.SearchBox.IsDisposed -and
            $tab.SearchBox -ne $Source -and $tab.SearchBox.Text -cne [string]$Text) {
            $tab.SearchBox.Text = [string]$Text
        }
        if ($null -ne $script:ExpandedSearchBox -and
            -not $script:ExpandedSearchBox.IsDisposed -and
            $script:ExpandedTableKey -eq $Key -and
            $script:ExpandedSearchBox -ne $Source -and
            $script:ExpandedSearchBox.Text -cne [string]$Text) {
            $script:ExpandedSearchBox.Text = [string]$Text
        }
    }
    finally {
        $script:SyncProcessSearchBoxes = $false
    }
    Apply-ProcessTableFilter -Key $Key
}

# FUNCTION Resize-ProcessColumns
function Resize-ProcessColumns {
    foreach ($t in @($psTab, $otherTab)) {
        $w = [math]::Max(600, $t.Grid.ClientSize.Width)
        $t.Grid.Columns[0].Width = 90
        $t.Grid.Columns[1].Width = 230
        $t.Grid.Columns[2].Width = 145
        $t.Grid.Columns[3].Width = [math]::Max(200, $w - 485)
    }
}

# FUNCTION Update-ProcessTables
function Update-ProcessTables($all, [switch]$Quiet) {
    $tableRefreshPaused = [bool]$script:PauseTableRefresh
    $seenRuleKeys = @{}
    foreach ($t in @($psTab, $otherTab)) {
        $existingByKey = @{}
        if (-not $tableRefreshPaused) {
            foreach ($existingItem in $t.Grid.Items) {
                if ($null -ne $existingItem.Tag -and -not $existingItem.Tag.SearchPlaceholder) {
                    $existingKey = '{0}|{1}' -f [int]$existingItem.Tag.PID, [string]$existingItem.Tag.Identity
                    if (-not $existingByKey.ContainsKey($existingKey)) {
                        $existingByKey[$existingKey] = $existingItem
                    }
                }
            }
            foreach ($hiddenKey in @($script:FilteredOutProcessItems[$t.Key].Keys)) {
                $existingByKey[[string]$hiddenKey] = $script:FilteredOutProcessItems[$t.Key][[string]$hiddenKey]
            }
            $t.Grid.BeginUpdate()
        }
        try {
            foreach ($p in $all) {
                $isPS = $p.Name -in @('powershell.exe', 'pwsh.exe')
                if (($t.Key -eq 'PS') -ne $isPS) { continue }

                $identity = Get-RuleIdentity $p $t.Key
                if ([string]::IsNullOrWhiteSpace($identity)) {
                    $identity = '[identity unavailable]'
                }
                $rule = 'Unclassified'
                if ($script:Rules[$t.Key].Allowed.ContainsKey($identity)) {
                    $rule = 'Allowed'
                }
                elseif ($script:Rules[$t.Key].Blocked.ContainsKey($identity)) {
                    $rule = 'Blocked'
                }
                # Preserve the existing rule-state logging behavior.
                $ruleLogKey = "$($t.Key)|$($p.ProcessId)|$identity"
                if ($rule -eq 'Allowed' -or $rule -eq 'Blocked') {
                    $seenRuleKeys[$ruleLogKey] = $true
                    if (
                        -not $script:LoggedProcessStates.ContainsKey($ruleLogKey) -or
                        $script:LoggedProcessStates[$ruleLogKey] -ne $rule
                    ) {
                        Write-Log (
                            '{0}: {1} | PID {2} | Category: {3}' -f
                            $rule, $p.Name, $p.ProcessId, $t.Key
                        )
                        $script:LoggedProcessStates[$ruleLogKey] = $rule
                    }
                }
                # A paused table continues its background rule/log processing without redraws.
                if ($tableRefreshPaused) { continue }
                $itemKey = '{0}|{1}' -f [int]$p.ProcessId, [string]$identity
                if ($existingByKey.ContainsKey($itemKey)) {
                    # Reuse the existing row so unchanged processes do not blink/re-render.
                    $item = $existingByKey[$itemKey]
                    [void]$existingByKey.Remove($itemKey)
                    $isHiddenByFilter = $script:FilteredOutProcessItems[$t.Key].ContainsKey($itemKey)
                    $itemOrder = Get-ProcessItemOrder $item
                    $pidText = [string]$p.ProcessId
                    $nameText = [string]$p.Name
                    $identityText = [string]$identity
                    $executablePath = [string]$p.ExecutablePath
                    if ([string]::IsNullOrWhiteSpace($executablePath) -and $t.Key -eq 'Other') {
                        $executablePath = [string]$identity
                    }
                    $publisherText = Get-ProcessPublisher $executablePath
                    if ($item.Text -cne $pidText) {
                        $item.Text = $pidText
                    }
                    if ($item.SubItems[1].Text -cne $nameText) {
                        $item.SubItems[1].Text = $nameText
                    }
                    if ($item.SubItems[2].Text -cne $rule) {
                        $item.SubItems[2].Text = $rule
                    }
                    if ($item.SubItems[3].Text -cne $identityText) {
                        $item.SubItems[3].Text = $identityText
                    }
                    $item.Tag = @{
                        Identity      = $identityText
                        PID           = [int]$p.ProcessId
                        Name          = $nameText
                        Key           = $t.Key
                        ExecutablePath = $executablePath
                        Publisher     = $publisherText
                        Order         = $itemOrder
                    }
                    if ($isHiddenByFilter) { continue }
                }
                else {
                    # Only genuinely new process instances get a row at the top.
                    $executablePath = [string]$p.ExecutablePath
                    if ([string]::IsNullOrWhiteSpace($executablePath) -and $t.Key -eq 'Other') {
                        $executablePath = [string]$identity
                    }
                    $publisherText = Get-ProcessPublisher $executablePath
                    $script:NextProcessItemOrder++
                    $item = [Windows.Forms.ListViewItem]::new([string]$p.ProcessId)
                    [void]$item.SubItems.Add([string]$p.Name)
                    [void]$item.SubItems.Add([string]$rule)
                    [void]$item.SubItems.Add([string]$identity)
                    $item.Tag = @{
                        Identity       = [string]$identity
                        PID            = [int]$p.ProcessId
                        Name           = [string]$p.Name
                        Key            = $t.Key
                        ExecutablePath = $executablePath
                        Publisher      = $publisherText
                        Order          = [long]$script:NextProcessItemOrder
                    }
                    $currentFilter = [string]$script:ProcessTableFilters[$t.Key]
                    if (
                        -not [string]::IsNullOrWhiteSpace($currentFilter) -and
                        -not (Test-ProcessItemMatchesSearch -Item $item -Query $currentFilter)
                    ) {
                        $script:FilteredOutProcessItems[$t.Key][$itemKey] = $item
                    }
                    else {
                        [void]$t.Grid.Items.Insert(0, $item)
                    }
                }
            }
            if (-not $tableRefreshPaused) {
                # Any unmatched old rows represent processes that have exited or changed identity.
                foreach ($staleKey in @($existingByKey.Keys)) {
                    $staleItem = $existingByKey[[string]$staleKey]
                    [void]$t.Grid.Items.Remove($staleItem)
                    [void]$script:FilteredOutProcessItems[$t.Key].Remove([string]$staleKey)
                }
            }
        }
        finally {
            if (-not $tableRefreshPaused) {
                $t.Grid.EndUpdate()
            }
        }
        if (
            -not $tableRefreshPaused -and
            (
                -not [string]::IsNullOrWhiteSpace([string]$script:ProcessTableFilters[$t.Key]) -or
                $script:FilteredOutProcessItems[$t.Key].Count -gt 0
            )
        ) {
            Apply-ProcessTableFilter -Key $t.Key
        }
    }
    # Remove log-state entries for processes that no longer exist or match a rule.
    foreach ($loggedKey in @($script:LoggedProcessStates.Keys)) {
        if (-not $seenRuleKeys.ContainsKey($loggedKey)) {
            [void]$script:LoggedProcessStates.Remove($loggedKey)
        }
    }
    if (-not $tableRefreshPaused) {
        Resize-ProcessColumns
    }
    if (-not $Quiet) {
        Write-Log ('Scan completed. {0} processes found.' -f $all.Count)
    }
}

# FUNCTION Get-WmiProcessSnapshot
function Get-WmiProcessSnapshot {
    $searcher = $null
    $collection = $null
    $rows = New-Object 'System.Collections.Generic.List[object]'
    try {
        $query = 'SELECT ProcessId, Name, CommandLine, ExecutablePath FROM Win32_Process'
        $searcher = [System.Management.ManagementObjectSearcher]::new($query)
        $collection = $searcher.Get()
        foreach ($proc in $collection) {
            try {
                $row = [pscustomobject]@{
                    ProcessId = [int]$proc['ProcessId']
                    Name = [string]$proc['Name']
                    CommandLine = [string]$proc['CommandLine']
                    ExecutablePath = [string]$proc['ExecutablePath']
                }
                [void]$rows.Add($row)
            } finally {
                try { $proc.Dispose() } catch {}
            }
        }
        return $rows.ToArray()
    } finally {
        if ($collection) { try { $collection.Dispose() } catch {} }
        if ($searcher) { try { $searcher.Dispose() } catch {} }
    }
}

# FUNCTION Get-WmiProcessById
function Get-WmiProcessById([int]$ProcessId) {
    $searcher = $null
    $collection = $null
    try {
        $query = "SELECT ProcessId, Name, CommandLine, ExecutablePath FROM Win32_Process WHERE ProcessId = $ProcessId"
        $searcher = [System.Management.ManagementObjectSearcher]::new($query)
        $collection = $searcher.Get()
        foreach ($proc in $collection) {
            try {
                return [pscustomobject]@{
                    ProcessId = [int]$proc['ProcessId']
                    Name = [string]$proc['Name']
                    CommandLine = [string]$proc['CommandLine']
                    ExecutablePath = [string]$proc['ExecutablePath']
                }
            } finally {
                try { $proc.Dispose() } catch {}
            }
        }
        return $null
    } finally {
        if ($collection) { try { $collection.Dispose() } catch {} }
        if ($searcher) { try { $searcher.Dispose() } catch {} }
    }
}

# FUNCTION Format-ScanError
function Format-ScanError($record, $worker = $null) {
    $parts = New-Object 'System.Collections.Generic.List[string]'
    if ($record) {
        $msg = [string]$record.Exception.Message
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = [string]$record.ToString() }
        if (-not [string]::IsNullOrWhiteSpace($msg)) { $parts.Add($msg.Trim()) }
    }
    if ($worker -and $worker.Streams -and $worker.Streams.Error.Count -gt 0) {
        foreach ($err in $worker.Streams.Error) {
            $msg = [string]$err.ToString()
            if (-not [string]::IsNullOrWhiteSpace($msg)) { $parts.Add($msg.Trim()) }
        }
    }
    $unique = @($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($unique.Count -eq 0) { return 'Unknown WMI scan error; no diagnostic message was returned.' }
    return ($unique -join ' | ')
}

# FUNCTION Scan-All
function Scan-All([switch]$Quiet) {
    if ($script:Busy -or $script:ScanWorkerBusy) { return }
    $script:Busy = $true
    try {
        $all = @(Get-WmiProcessSnapshot)
        Update-ProcessTables -all $all -Quiet:$Quiet
    } catch {
        $errorText = Format-ScanError $_
        Write-Log "Scan failed: $errorText"
    } finally {
        $script:Busy = $false
    }
}
	# A dedicated runspace performs WMI queries off the UI thread. This avoids a dependency
	$script:ScanPowerShell = $null
	$script:ScanRunspace = $null
	$script:ScanAsyncResult = $null
	$script:ScanWorkerBusy = $false
	$script:ScanPollTimer = [Windows.Forms.Timer]::new()
	$script:ScanPollTimer.Interval = 150

# FUNCTION Complete-AsyncScan
function Complete-AsyncScan {
    if (-not $script:ScanWorkerBusy -or -not $script:ScanPowerShell -or -not $script:ScanAsyncResult) { return }
    if (-not $script:ScanAsyncResult.IsCompleted) { return }
    $worker = $script:ScanPowerShell
    $runspace = $script:ScanRunspace
    try {
        $payload = @($worker.EndInvoke($script:ScanAsyncResult))
        if ($payload.Count -eq 0) { throw 'The background scanner returned no result.' }
        $scanResult = $payload[$payload.Count - 1]
        if ($null -eq $scanResult.PSObject.Properties['ScanSuccess']) {
            throw 'The background scanner returned an unexpected result format.'
        }
        if (-not [bool]$scanResult.ScanSuccess) {
            $workerError = [string]$scanResult.ErrorText
            if ([string]::IsNullOrWhiteSpace($workerError)) { $workerError = 'WMI query failed without a diagnostic message.' }
            throw $workerError
        }
        $result = @($scanResult.Processes)
        # Reuse this scan for rule enforcement while the monitor is active.
        if ($script:Running) {
            Update-MonitorEnforcementFromSnapshot -Processes $result
        }
        Update-ProcessTables -all $result -Quiet
        if (-not $script:ScanActive) {
            Write-Log ('Scan completed. {0} processes found.' -f $result.Count)
        }
    } catch {
        $errorText = Format-ScanError $_ $worker
        Write-Log "Scan failed: $errorText"
    } finally {
        if ($script:ScanPollTimer) { $script:ScanPollTimer.Stop() }
        $script:ScanWorkerBusy = $false
        $script:ShowScanBusyIndicator = $false
        $script:ScanPowerShell = $null
        $script:ScanRunspace = $null
        $script:ScanAsyncResult = $null
        try { $worker.Dispose() } catch {}
        if ($runspace) {
            try { $runspace.Close() } catch {}
            try { $runspace.Dispose() } catch {}
        }
        Update-ScanVisualState
    }
}
$script:ScanPollTimer.Add_Tick({ Complete-AsyncScan })

# FUNCTION Start-AsyncScan
function Start-AsyncScan {
    if ($script:ScanWorkerBusy -or $script:Busy) { return }
    try {
        $scanCode = @'
$ErrorActionPreference = 'Stop'
$searcher = $null
$collection = $null
$rows = New-Object System.Collections.ArrayList
$scanResult = $null
try {
    Add-Type -AssemblyName System.Management -ErrorAction Stop | Out-Null
    $query = 'SELECT ProcessId, Name, CommandLine, ExecutablePath FROM Win32_Process'
    $searcher = [System.Management.ManagementObjectSearcher]::new($query)
    $collection = $searcher.Get()
    foreach ($proc in $collection) {
        try {
            [void]$rows.Add([pscustomobject]@{
                ProcessId = [int]$proc['ProcessId']
                Name = [string]$proc['Name']
                CommandLine = [string]$proc['CommandLine']
                ExecutablePath = [string]$proc['ExecutablePath']
            })
        } finally {
            try { $proc.Dispose() } catch {}
        }
    }
    $scanResult = [pscustomobject]@{
        ScanSuccess = $true
        Processes = [object[]]$rows.ToArray()
        ErrorText = ''
    }
} catch {
    $detail = [string]$_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = [string]($_ | Out-String).Trim() }
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'WMI query failed without a diagnostic message.' }
    $scanResult = [pscustomobject]@{
        ScanSuccess = $false
        Processes = @()
        ErrorText = $detail
    }
} finally {
    if ($collection) { try { $collection.Dispose() } catch {} }
    if ($searcher) { try { $searcher.Dispose() } catch {} }
}
$scanResult
'@
        $script:ScanRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $script:ScanRunspace.Open()
        $script:ScanPowerShell = [System.Management.Automation.PowerShell]::Create()
        $script:ScanPowerShell.Runspace = $script:ScanRunspace
        $null = $script:ScanPowerShell.AddScript($scanCode)
        $script:ScanAsyncResult = $script:ScanPowerShell.BeginInvoke()
        $script:ScanWorkerBusy = $true
        Update-ScanVisualState
        $script:ScanPollTimer.Start()
		} catch {
			$errorText = Format-ScanError $_ $script:ScanPowerShell
			$script:ScanWorkerBusy = $false
			$script:ShowScanBusyIndicator = $false
			if ($script:ScanPowerShell) { try { $script:ScanPowerShell.Dispose() } catch {} }
			if ($script:ScanRunspace) {
				try { $script:ScanRunspace.Close() } catch {}
				try { $script:ScanRunspace.Dispose() } catch {}
			}
			$script:ScanPowerShell = $null
			$script:ScanRunspace = $null
			$script:ScanAsyncResult = $null
			Write-Log "Could not start scan: $errorText"
			Update-ScanVisualState
			}
		}
		$script:ScanCycleTimer = [Windows.Forms.Timer]::new()
		$script:ScanCycleTimer.Interval = 2500
		$script:ScanCycleTimer.Add_Tick({
			if ($script:ScanActive -and -not $script:ScanWorkerBusy -and -not $script:Busy) {
				Start-AsyncScan
			}
		})
		$script:ScanBlinkTimer = [Windows.Forms.Timer]::new()
		$script:ScanBlinkTimer.Interval = 420
		$script:ScanBlinkTimer.Add_Tick({
			if ($script:ScanActive -or $script:ShowScanBusyIndicator -or $script:ScanWorkerBusy) {
				$script:ScanBlinkOn = -not $script:ScanBlinkOn
				if ($script:ScanBlinkOn) {
					$scanLed.ForeColor = [Drawing.Color]::FromArgb(52, 211, 153)
				} else {
					$scanLed.ForeColor = [Drawing.Color]::FromArgb(6, 95, 70)
				}
			} else {
				$scanLed.ForeColor = $script:Theme.Muted
			}
		})

# FUNCTION Update-ScanVisualState
function Update-ScanVisualState {
    if ($script:ScanActive) {
        $scan.Text = 'STOP SCAN'
        $scan.BackColor = $script:Theme.Red
        $scan.ForeColor = [Drawing.Color]::White
        $scanIndicatorText.Text = 'SCANNING  •  ACTIVE'
        $scanIndicatorText.ForeColor = [Drawing.Color]::FromArgb(52, 211, 153)
        if (-not $script:ScanBlinkTimer.Enabled) { $script:ScanBlinkTimer.Start() }
        if (-not $script:ScanCycleTimer.Enabled) { $script:ScanCycleTimer.Start() }
        if ($script:ScanBlinkOn) {
            $scanLed.ForeColor = [Drawing.Color]::FromArgb(52, 211, 153)
        }
    } elseif ($script:ShowScanBusyIndicator -or $script:ScanWorkerBusy) {
        $scan.Text = 'SCAN ALL PROCESSES'
        $scan.BackColor = $script:Theme.Blue
        $scan.ForeColor = [Drawing.Color]::White
        $scanIndicatorText.Text = 'SCANNING...'
        $scanIndicatorText.ForeColor = [Drawing.Color]::FromArgb(52, 211, 153)
        if (-not $script:ScanBlinkTimer.Enabled) { $script:ScanBlinkTimer.Start() }
        if ($script:ScanBlinkOn) {
            $scanLed.ForeColor = [Drawing.Color]::FromArgb(52, 211, 153)
        }
    } else {
        $scan.Text = 'SCAN ALL PROCESSES'
        $scan.BackColor = $script:Theme.Blue
        $scan.ForeColor = [Drawing.Color]::White
        $scanIndicatorText.Text = 'SCAN INACTIVE'
        $scanIndicatorText.ForeColor = $script:Theme.Muted
        if ($script:ScanBlinkTimer.Enabled) { $script:ScanBlinkTimer.Stop() }
        $scanLed.ForeColor = $script:Theme.Muted
        $script:ScanCycleTimer.Stop()
    }
}

# FUNCTION Start-ContinuousScan
function Start-ContinuousScan {
    if ($script:ScanActive) { return }
    $script:ScanActive = $true
    $script:ShowScanBusyIndicator = $false
    $script:ScanBlinkOn = $true
    Update-ScanVisualState
    $scanIndicatorPanel.Refresh()
    Write-Log 'Continuous scanning started.'
    Start-AsyncScan
}

# FUNCTION Stop-ContinuousScan
function Stop-ContinuousScan {
    if (-not $script:ScanActive) { return }
    $script:ScanActive = $false
    # If a scan is already in progress, keep the LED active until that scan returns.
    $script:ShowScanBusyIndicator = [bool]$script:ScanWorkerBusy
    $script:ScanCycleTimer.Stop()
    Update-ScanVisualState
    Write-Log 'Continuous scanning stopped; any in-progress scan will finish.'
}

# FUNCTION Selected-Process
function Selected-Process {
    $t = Current-Tab
    if ($t.Grid.SelectedItems.Count -eq 0) { return $null }
    $selectedTag = $t.Grid.SelectedItems[0].Tag
    if ($null -eq $selectedTag -or $selectedTag.SearchPlaceholder) { return $null }
    return $selectedTag
}
$scan.Add_Click({
    if ($script:ScanActive) {
        Stop-ContinuousScan
    } else {
        Start-ContinuousScan
    }
})
$allowSelected.Add_Click({
    $t = Current-Tab
    $selected = Selected-Process
    if (-not $selected) {
        [Windows.Forms.MessageBox]::Show('Select a process first.', 'No process selected', 'OK', 'Information') | Out-Null
        return
    }
    if ($selected.Identity -eq '[identity unavailable]') {
        [Windows.Forms.MessageBox]::Show('This process has no readable identity and cannot be added to a rule.', 'Identity unavailable', 'OK', 'Warning') | Out-Null
        return
    }
    $confirm = [Windows.Forms.MessageBox]::Show(
        "Add this process identity to the ALLOW list?`r`n`r`n$($selected.Identity)",
        'Confirm allow rule', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $script:Rules[$t.Key].Allowed[$selected.Identity] = $true
    [void]$script:Rules[$t.Key].Blocked.Remove($selected.Identity)
    Write-ProcessAuditLog -Event 'ALLOWED RULE ADDED' -Details ("Category={0}; Process={1}; PID={2}; Identity={3}" -f $t.Key, $selected.Name, $selected.PID, $selected.Identity)
    Refresh-RuleLists
    Scan-All
})
$blockSelected.Add_Click({
    $t = Current-Tab
    $selected = Selected-Process
    if (-not $selected) {
        [Windows.Forms.MessageBox]::Show('Select a process first.', 'No process selected', 'OK', 'Information') | Out-Null
        return
    }
    if ($selected.Identity -eq '[identity unavailable]') {
        [Windows.Forms.MessageBox]::Show('This process has no readable identity and cannot be added to a rule.', 'Identity unavailable', 'OK', 'Warning') | Out-Null
        return
    }
    $warning = @"
WARNING: DANGEROUS PROCESS RULE

A blocked rule can cause matching processes to be terminated.
This may interrupt work or cause data loss.

Category: $($t.Key)
Process: $($selected.Name)
PID at selection: $($selected.PID)

Rule identity:
$($selected.Identity)

Add this rule to the BLOCK list?
"@
    $confirm = [Windows.Forms.MessageBox]::Show($warning, 'Dangerous process warning', 'YesNo', 'Warning')
    if ($confirm -ne 'Yes') { return }
    $script:Rules[$t.Key].Blocked[$selected.Identity] = $true
    [void]$script:Rules[$t.Key].Allowed.Remove($selected.Identity)
    Write-ProcessAuditLog -Event 'BLOCKED RULE ADDED' -Details ("Category={0}; Process={1}; PID={2}; Identity={3}" -f $t.Key, $selected.Name, $selected.PID, $selected.Identity)
    Refresh-RuleLists
    Scan-All
})
$removeRule.Add_Click({
    $t = Current-Tab
    if ($t.Allow.SelectedItem) {
        $removedIdentity = [string]$t.Allow.SelectedItem
        [void]$script:Rules[$t.Key].Allowed.Remove($removedIdentity)
        Write-ProcessAuditLog -Event 'ALLOWED RULE REMOVED' -Details ("Category={0}; Identity={1}" -f $t.Key, $removedIdentity)
    } elseif ($t.Block.SelectedItem) {
        $removedIdentity = [string]$t.Block.SelectedItem
        [void]$script:Rules[$t.Key].Blocked.Remove($removedIdentity)
        Write-ProcessAuditLog -Event 'BLOCKED RULE REMOVED' -Details ("Category={0}; Identity={1}" -f $t.Key, $removedIdentity)
    } else {
        [Windows.Forms.MessageBox]::Show('Select a rule from either the allowed or blocked list first.', 'No rule selected', 'OK', 'Information') | Out-Null
        return
    }
    Refresh-RuleLists
    Scan-All
})
# Monitor LED blink timer.
$script:MonitorBlinkOn = $true
$script:MonitorBlinkTimer = [Windows.Forms.Timer]::new()
$script:MonitorBlinkTimer.Interval = 420
$script:MonitorBlinkTimer.Add_Tick({
    if (-not $script:Running) { return }
    $script:MonitorBlinkOn = -not $script:MonitorBlinkOn
    if ($script:MonitorBlinkOn) {
        $monitorLed.ForeColor =
            [Drawing.Color]::FromArgb(52, 211, 153)
    }
    else {
        $monitorLed.ForeColor =
            [Drawing.Color]::FromArgb(6, 95, 70)
    }
})

# FUNCTION Get-MonitorProcessCategory
function Get-MonitorProcessCategory($Process) {
    if ([string]$Process.Name -in @('powershell.exe', 'pwsh.exe')) {
        return 'PS'
    }
    return 'Other'
}

# FUNCTION Get-MonitorProcessInstanceKey
function Get-MonitorProcessInstanceKey($Process) {
    $category = Get-MonitorProcessCategory $Process
    $identity = [string](Get-RuleIdentity $Process $category)
    if ([string]::IsNullOrWhiteSpace($identity)) { return $null }
    return ('{0}|{1}|{2}' -f $category, [int]$Process.ProcessId, $identity)
}

# FUNCTION Register-RuleProcessAudit
function Register-RuleProcessAudit {
    param(
        $Process,
        [string]$Category,
        [string]$Identity,
        [ValidateSet('ALLOWED', 'BLOCKED')][string]$Rule,
        [switch]$FromStartEvent
    )
    $instanceKey = '{0}|{1}|{2}' -f $Category, [int]$Process.ProcessId, $Identity
    if ($script:AuditedRuleProcesses.ContainsKey($instanceKey)) { return }
    $script:AuditedRuleProcesses[$instanceKey] = @{
        Rule = $Rule
        Category = $Category
        Name = [string]$Process.Name
        PID = [int]$Process.ProcessId
        Identity = $Identity
        TerminatedByRule = $false
    }
    $eventName = if ($FromStartEvent) {
        "$Rule PROCESS STARTED"
    }
    else {
        "$Rule PROCESS DETECTED"
    }
    Write-ProcessAuditLog -Event $eventName -Details (
        'Name={0}; PID={1}; Category={2}; Identity={3}' -f
        $Process.Name, $Process.ProcessId, $Category, $Identity
    )
}

# FUNCTION Invoke-MonitorProcessRule
function Invoke-MonitorProcessRule($Process, [switch]$Revalidated, [switch]$FromStartEvent) {
    if (-not $script:Running -or $null -eq $Process) { return }
    $category = Get-MonitorProcessCategory $Process
    $identity = [string](Get-RuleIdentity $Process $category)
    if ([string]::IsNullOrWhiteSpace($identity)) { return }
    if ($script:Rules[$category].Allowed.ContainsKey($identity)) {
        Register-RuleProcessAudit -Process $Process -Category $category -Identity $identity -Rule 'ALLOWED' -FromStartEvent:$FromStartEvent
        return
    }
    if (-not $script:Rules[$category].Blocked.ContainsKey($identity)) { return }
    $instanceKey = '{0}|{1}|{2}' -f $category, [int]$Process.ProcessId, $identity
    if ($script:HandledBlockedInstances.ContainsKey($instanceKey)) { return }
    $script:HandledBlockedInstances[$instanceKey] = $true
    Register-RuleProcessAudit -Process $Process -Category $category -Identity $identity -Rule 'BLOCKED' -FromStartEvent:$FromStartEvent
    # Keep the existing safety protections for core Windows processes and this UI.
    if ([int]$Process.ProcessId -le 4) {
        Write-ProcessAuditLog -Event 'BLOCKED TERMINATION SKIPPED' -Details ("Protected system PID={0}; Name={1}; Category={2}; Identity={3}" -f $Process.ProcessId, $Process.Name, $category, $identity)
        return
    }
    if ($script:ProtectedNames -contains [string]$Process.Name) {
        Write-ProcessAuditLog -Event 'BLOCKED TERMINATION SKIPPED' -Details ("Protected process Name={0}; PID={1}; Category={2}; Identity={3}" -f $Process.Name, $Process.ProcessId, $category, $identity)
        return
    }
    if ([int]$Process.ProcessId -eq $PID) {
        Write-ProcessAuditLog -Event 'BLOCKED TERMINATION SKIPPED' -Details ("Current application process protected; Name={0}; PID={1}; Category={2}" -f $Process.Name, $Process.ProcessId, $category)
        return
    }
    try {
        # Revalidate PID and identity immediately before termination.
        $current = Get-WmiProcessById -ProcessId ([int]$Process.ProcessId)
        if ($null -eq $current) { return }
        $currentIdentity = [string](Get-RuleIdentity $current $category)
        if ($currentIdentity -ne $identity) {
            # PID may have been reused between the scan/event and revalidation.
            [void]$script:HandledBlockedInstances.Remove($instanceKey)
            if (-not $Revalidated -and -not [string]::IsNullOrWhiteSpace($currentIdentity)) {
                Invoke-MonitorProcessRule -Process $current -Revalidated -FromStartEvent:$FromStartEvent
            }
            return
        }
        if ($script:Rules[$category].Allowed.ContainsKey($currentIdentity)) { return }
        if (-not $script:Rules[$category].Blocked.ContainsKey($currentIdentity)) { return }
        if ([string]$current.Name -in $script:ProtectedNames) { return }
        Stop-Process -Id ([int]$current.ProcessId) -Force -ErrorAction Stop
        if ($script:AuditedRuleProcesses.ContainsKey($instanceKey)) {
            $script:AuditedRuleProcesses[$instanceKey].TerminatedByRule = $true
        }
        Write-ProcessAuditLog -Event 'BLOCKED PROCESS TERMINATED' -Details ("Name={0}; PID={1}; Category={2}; Identity={3}" -f $current.Name, $current.ProcessId, $category, $currentIdentity)
        Write-Log ('Terminated {0}, PID {1} (blocked rule).' -f $current.Name, $current.ProcessId)
    }
    catch {
        Write-ProcessAuditLog -Event 'BLOCKED TERMINATION FAILED' -Details ("Name={0}; PID={1}; Category={2}; Identity={3}; Error={4}" -f $Process.Name, $Process.ProcessId, $category, $identity, $_.Exception.Message)
        Write-Log ('Blocked rule attempt failed for {0}, PID {1}: {2}' -f `
            $Process.Name, $Process.ProcessId, $_.Exception.Message)
    }
}

# FUNCTION Update-MonitorEnforcementFromSnapshot
function Update-MonitorEnforcementFromSnapshot {
    param([object[]]$Processes)
    $activeInstances = @{}
    foreach ($process in $Processes) {
        $instanceKey = Get-MonitorProcessInstanceKey $process
        if (-not [string]::IsNullOrWhiteSpace($instanceKey)) {
            $activeInstances[$instanceKey] = $true
        }
        Invoke-MonitorProcessRule -Process $process
    }
    foreach ($auditKey in @($script:AuditedRuleProcesses.Keys)) {
        if (-not $activeInstances.ContainsKey([string]$auditKey)) {
            $auditRecord = $script:AuditedRuleProcesses[[string]$auditKey]
            if (-not [bool]$auditRecord.TerminatedByRule) {
                Write-ProcessAuditLog -Event ("{0} PROCESS ENDED" -f $auditRecord.Rule) -Details (
                    'Name={0}; PID={1}; Category={2}; Identity={3}' -f
                    $auditRecord.Name, $auditRecord.PID, $auditRecord.Category, $auditRecord.Identity
                )
            }
            [void]$script:AuditedRuleProcesses.Remove([string]$auditKey)
        }
    }
    foreach ($handledKey in @($script:HandledBlockedInstances.Keys)) {
        if (-not $activeInstances.ContainsKey([string]$handledKey)) {
            [void]$script:HandledBlockedInstances.Remove([string]$handledKey)
        }
    }
}

# FUNCTION Start-MonitorProcessWatcher
function Start-MonitorProcessWatcher {
    Stop-MonitorProcessWatcher
    $script:PendingProcessStarts = [System.Collections.Concurrent.ConcurrentQueue[int]]::new()
    $watcher = $null
    try {
        $watcher = [System.Management.ManagementEventWatcher]::new()
        $watcher.Query = [System.Management.WqlEventQuery]::new(
            'SELECT * FROM Win32_ProcessStartTrace'
        )
        $watcher.Add_EventArrived({
            param($sender, $e)
            try {
                $startedPid = [int]$e.NewEvent.Properties['ProcessID'].Value
                if ($startedPid -gt 0) {
                    # Thread-safe queue: UI timer resolves the PID and applies its rule.
                    $script:PendingProcessStarts.Enqueue($startedPid)
                }
            }
            catch {}
        })
        $watcher.Start()
        $script:ProcessStartWatcher = $watcher
        $script:ProcessStartWatcherActive = $true
        Write-Log 'Event-driven process-start monitoring enabled.'
    }
    catch {
        if ($watcher) {
            try { $watcher.Stop() } catch {}
            try { $watcher.Dispose() } catch {}
        }
        $script:ProcessStartWatcher = $null
        $script:ProcessStartWatcherActive = $false
        Write-Log ('Process-start event watcher unavailable; using periodic fallback scan: {0}' -f $_.Exception.Message)
    }
}

# FUNCTION Stop-MonitorProcessWatcher
function Stop-MonitorProcessWatcher {
    if ($script:ProcessStartWatcher) {
        try { $script:ProcessStartWatcher.Stop() } catch {}
        try { $script:ProcessStartWatcher.Dispose() } catch {}
    }
    $script:ProcessStartWatcher = $null
    $script:ProcessStartWatcherActive = $false
    if ($null -ne $script:PendingProcessStarts) {
        [int]$discardedPid = 0
        while ($script:PendingProcessStarts.TryDequeue([ref]$discardedPid)) {
            $discardedPid = 0
        }
    }
}

# FUNCTION Stop-Monitor
function Stop-Monitor {
    $wasRunning = [bool]$script:Running
    $script:Running = $false
    if ($wasRunning) {
        Write-ProcessAuditLog -Event 'MONITOR STOPPED' -Details 'Monitoring stopped.'
        Update-AutoStartTimeInfo -Values ([ordered]@{ MonitorStopTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') })
    }
    $script:AuditedRuleProcesses = @{}
    if ($null -ne $saveRulesButton -and -not $saveRulesButton.IsDisposed) {
        $saveRulesButton.Enabled = $true
    }
    Stop-MonitorProcessWatcher
    $script:HandledBlockedInstances = @{}
    $script:LastMonitorProcessScan = [datetime]::MinValue
    $status.Text = 'MONITOR STOPPED'
    if ($script:MonitorBlinkTimer) {
        $script:MonitorBlinkTimer.Stop()
    }
    $monitorLed.ForeColor =
        [Drawing.Color]::FromArgb(248, 113, 113)
    $status.ForeColor = [Drawing.Color]::FromArgb(252, 165, 165)
    $status.BackColor = [Drawing.Color]::FromArgb(69, 20, 30)
    $start.Enabled = $true
	$start.Text = 'START MONITOR'
	$start.BackColor = $green
	$start.FlatAppearance.MouseOverBackColor =
		[Drawing.Color]::FromArgb(23, 168, 123)
	$start.FlatAppearance.MouseDownBackColor =
		[Drawing.Color]::FromArgb(0, 130, 85)
		$monitorCountdown.ForeColor = [Drawing.Color]::FromArgb(52, 211, 153)
	$allowSelected.Enabled = $true
	$removeRule.Enabled = $true
	# Re-enable process actions after monitoring stops.
	$allowSelected.Enabled = $true
	$blockSelected.Enabled = $true
	$removeRule.Enabled = $true
	Write-Log 'Monitoring stopped.'
	}
	$timer = [Windows.Forms.Timer]::new()
	$timer.Interval = 1000
	$timer.Add_Tick({
	$now = Get-Date
    if ($script:PanelUntil) {
        $panelLeft = ($script:PanelUntil - $now).TotalSeconds
        $panelCountdown.Text = 'PANEL REMAINING  ' + (Format-RemainingTime $panelLeft)
        if ($panelLeft -le 60) {
            $panelCountdown.ForeColor = [Drawing.Color]::FromArgb(248, 113, 113)
        } else {
            $panelCountdown.ForeColor = [Drawing.Color]::FromArgb(196, 181, 253)
        }
        if ($panelLeft -le 0) {
            $timer.Stop()
            if ($script:Running) {
                Write-ProcessAuditLog -Event 'MONITOR STOPPED' -Details 'Panel lifetime expired.'
            }
            Write-ProcessAuditLog -Event 'PANEL LIFETIME EXPIRED' -Details 'Process Control Center panel is closing.'
            $stopValues = [ordered]@{ PanelStopTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
            if ($script:Running) { $stopValues['MonitorStopTime'] = $stopValues['PanelStopTime'] }
            Update-AutoStartTimeInfo -Values $stopValues
            $script:PanelStopLogged = $true
            $script:Running = $false
            $script:AuditedRuleProcesses = @{}
            Write-Log 'Panel lifetime expired; closing panel.'
            $form.Close()
            return
        }
    }
    if ($script:Running -and $script:MonitorUntil) {
        $monitorLeft = ($script:MonitorUntil - $now).TotalSeconds
        $monitorCountdown.Text = 'MONITOR REMAINING  ' + (Format-RemainingTime $monitorLeft)
        if ($monitorLeft -le 60) {
            $monitorCountdown.ForeColor = [Drawing.Color]::FromArgb(248, 113, 113)
        } else {
            $monitorCountdown.ForeColor = [Drawing.Color]::FromArgb(52, 211, 153)
        }
        if ($monitorLeft -le 0) {
            Stop-Monitor
            $monitorCountdown.Text = 'MONITOR FINISHED  00:00:00'
            Write-Log 'Monitor duration expired.'
            return
        }
    }
    if (-not $script:Running) { return }
    # Apply rules to new process starts from the WMI event queue. No full-system
    try {
        [int]$startedPid = 0
        while ($script:PendingProcessStarts.TryDequeue([ref]$startedPid)) {
            if ($startedPid -gt 0) {
                # A start event means this PID now represents a fresh instance. Clear
                # an old cached key in case Windows has reused the PID after an exit.
                foreach ($handledKey in @($script:HandledBlockedInstances.Keys)) {
                    if ([string]$handledKey -match ('^(PS|Other)\|' + $startedPid + '\|')) {
                        [void]$script:HandledBlockedInstances.Remove([string]$handledKey)
                    }
                }
                try {
                    $startedProcess = Get-WmiProcessById -ProcessId $startedPid
                    if ($null -ne $startedProcess) {
                        Invoke-MonitorProcessRule -Process $startedProcess -FromStartEvent
                    }
                }
                catch {
                    Write-Log ('Could not inspect newly started PID {0}: {1}' -f $startedPid, $_.Exception.Message)
                }
            }
            $startedPid = 0
        }
        # When continuous scanning is active, Complete-AsyncScan reuses its result
        # for rule enforcement and table updates. Avoid a duplicate monitor scan.
        if ($script:ScanActive -or $script:Busy -or $script:ScanWorkerBusy) { return }
        # The event watcher handles startups promptly. A slower full snapshot is kept
        # as a fallback for missed events and to refresh the process table.
        $scanIntervalMs = if ($script:ProcessStartWatcherActive) { 4000 } else { 2000 }
        if (($now - $script:LastMonitorProcessScan).TotalMilliseconds -lt $scanIntervalMs) {
            return
        }
        $script:Busy = $true
        try {
            $procs = @(Get-WmiProcessSnapshot)
            Update-MonitorEnforcementFromSnapshot -Processes $procs
            Update-ProcessTables -all $procs -Quiet
            $script:LastMonitorProcessScan = Get-Date
        }
        finally {
            $script:Busy = $false
        }
    }
    catch {
        $monitorError = Format-ScanError $_
        Write-Log "Monitor error: $monitorError"
    }
})
$start.Add_Click({
	if ($script:Running) {
    Stop-Monitor
    return
}
    $monitorSeconds = Get-Seconds $monitorDuration
    $panelSeconds = Get-Seconds $panelDuration
    if ($monitorSeconds -le 0 -or $panelSeconds -le 0) {
        [Windows.Forms.MessageBox]::Show('Both durations must be greater than zero.', 'Invalid duration', 'OK', 'Warning') | Out-Null
        return
    }
	$allowedCount = $script:Rules.PS.Allowed.Count +
					$script:Rules.Other.Allowed.Count
	$blockedCount = $script:Rules.PS.Blocked.Count +
					$script:Rules.Other.Blocked.Count
	if (($allowedCount + $blockedCount) -eq 0) {
		[Windows.Forms.MessageBox]::Show(
			'Add at least one allowed or blocked rule before starting.',
			'No process rules',
			'OK',
			'Warning'
		) | Out-Null
		return
	}
    # Automatic startup skips this one-time start confirmation. Manual clicks keep it.
    if (-not $script:AutoStartMonitorRequested) {
        $review = [Windows.Forms.MessageBox]::Show(
            "Automatic process monitoring will start.`r`n`r`nEvery matching process will require a separate confirmation before termination.`r`nThe panel will close when its lifetime expires.`r`n`r`nContinue?",
            'Confirm monitoring', 'YesNo', 'Warning')
        if ($review -ne 'Yes') { return }
    }
    $now = Get-Date
    $script:MonitorUntil = $now.AddSeconds($monitorSeconds)
    $script:PanelUntil = $now.AddSeconds($panelSeconds)
    $script:HandledBlockedInstances = @{}
    $script:AuditedRuleProcesses = @{}
    $script:LastMonitorProcessScan = [datetime]::MinValue
    Start-MonitorProcessWatcher
    $script:Running = $true
    $saveRulesButton.Enabled = $false
	# Lock process actions while monitoring is running.
	$allowSelected.Enabled = $false
	$blockSelected.Enabled = $false
	$removeRule.Enabled = $false
	# Clear any existing process selections.
	foreach ($t in @($psTab, $otherTab)) {
		foreach ($item in @($t.Grid.SelectedItems)) {
			$item.Selected = $false
		}
	}
	$allowSelected.Enabled = $false
	$removeRule.Enabled = $false
	$script:MonitorBlinkOn = $true
	$monitorLed.ForeColor =
		[Drawing.Color]::FromArgb(52, 211, 153)
	$script:MonitorBlinkTimer.Start()
    $status.Text = 'MONITOR RUNNING'
    $status.ForeColor = [Drawing.Color]::FromArgb(110, 231, 183)
    $status.BackColor = [Drawing.Color]::FromArgb(6, 55, 47)
	$start.Enabled = $true
	$start.Text = 'STOP MONITOR'
	$start.BackColor = $red
	$start.FlatAppearance.MouseOverBackColor =
		[Drawing.Color]::FromArgb(203, 46, 46)
	$start.FlatAppearance.MouseDownBackColor =
    [Drawing.Color]::FromArgb(165, 8, 8)
    $monitorCountdown.Text = 'MONITOR REMAINING  ' + (Format-RemainingTime $monitorSeconds)
    $panelCountdown.Text = 'PANEL REMAINING  ' + (Format-RemainingTime $panelSeconds)
    $monitorCountdown.ForeColor = [Drawing.Color]::FromArgb(52, 211, 153)
    $panelCountdown.ForeColor = [Drawing.Color]::FromArgb(196, 181, 253)
    $timer.Start()
    $startStamp = $now.ToString('yyyy-MM-dd HH:mm:ss')
    Update-AutoStartTimeInfo -Values ([ordered]@{ MonitorStartTime = $startStamp; PanelStartTime = $startStamp }) -RemoveKeys @('MonitorStopTime', 'PanelStopTime')
    $script:PanelStopLogged = $false
    Write-ProcessAuditLog -Event 'MONITOR STARTED' -Details ("Monitor duration={0}; Panel lifetime={1}" -f (Format-RemainingTime $monitorSeconds), (Format-RemainingTime $panelSeconds))
    Write-Log 'Monitoring started.'
})
$form.Add_Shown({
    Resize-ProcessColumns
    $script:ShowScanBusyIndicator = $true
    Update-ScanVisualState
    Start-AsyncScan
    # Use the real START MONITOR click handler so timer/monitor behavior stays identical.
    if ($script:AutoStartMonitorRequested) {
        [void]$start.PerformClick()
        $script:AutoStartMonitorRequested = $false
    }
})
$form.Add_Resize({ Resize-ProcessColumns })
$form.Add_FormClosing({
    if ($script:Running) {
        Write-ProcessAuditLog -Event 'MONITOR STOPPED' -Details 'Application window closed while monitoring.'
    }
    if (-not $script:PanelStopLogged) {
        $closeValues = [ordered]@{ PanelStopTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
        if ($script:Running) { $closeValues['MonitorStopTime'] = $closeValues['PanelStopTime'] }
        Update-AutoStartTimeInfo -Values $closeValues
        $script:PanelStopLogged = $true
    }
    $script:AuditedRuleProcesses = @{}
    Stop-MonitorProcessWatcher
    if ($timer) { $timer.Stop(); $timer.Dispose() }
    if ($script:ScanCycleTimer) { $script:ScanCycleTimer.Stop(); $script:ScanCycleTimer.Dispose() }
    if ($script:ScanBlinkTimer) { $script:ScanBlinkTimer.Stop(); $script:ScanBlinkTimer.Dispose() }
    if ($script:ScanPollTimer) { $script:ScanPollTimer.Stop(); $script:ScanPollTimer.Dispose() }
    if ($script:ScanPowerShell) {
        try { $script:ScanPowerShell.Stop() } catch {}
        try { $script:ScanPowerShell.Dispose() } catch {}
    }
    if ($script:ScanRunspace) {
        try { $script:ScanRunspace.Close() } catch {}
        try { $script:ScanRunspace.Dispose() } catch {}
    }
	if ($script:MonitorBlinkTimer) {
    $script:MonitorBlinkTimer.Stop()
    $script:MonitorBlinkTimer.Dispose()
}
    $script:ScanPowerShell = $null
    $script:ScanRunspace = $null
    $script:ScanAsyncResult = $null
    $script:ScanWorkerBusy = $false
    $script:ScanActive = $false
    $script:Running = $false
})
$form.Add_FormClosed({
    if ($script:ProcessManagerIcon) {
        try { $script:ProcessManagerIcon.Dispose() } catch {}
        $script:ProcessManagerIcon = $null
    }
})
Write-Log 'Ready. Initial scan uses Windows Management Instrumentation (WMI). Click SCAN ALL PROCESSES for continuous scanning; click STOP SCAN to stop the loop.'
[void]$form.ShowDialog()

####################################################################################################################### End Process Manager.
