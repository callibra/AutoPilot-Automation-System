# requires -Version 5.1
# PS2EXE: Invoke-PS2EXE .\ScriptsEditor.ps1 .\ScriptsEditor.exe -noConsole -STA

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:AppRoot = if ($PSScriptRoot) { $PSScriptRoot } else { [AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\') }
$script:ConfigFile = Join-Path $script:AppRoot 'JSON\scripts_edit.json'
$script:DefaultConfigFile = Join-Path $script:AppRoot 'JSON\scripts_default.json'
$script:BackupDir = Join-Path $script:AppRoot 'JSON\Backups_ScriptsEditor'
$script:IconPath = Join-Path $script:AppRoot 'media\scripts.ico'
$script:MaxRows = 35
$script:Palette = @{
    Background = '#1E1E1E'; Panel = '#2D2D30'; Input = '#3C3F41'
    Gold = '#FFD700'; Text = '#E0E0E0'; Green = '#00FF00'
    Blue = '#1E90FF'; Red = '#FF4500'; Muted = '#CFCFCF'
}
$script:UiState = [pscustomobject]@{
    Rows = [System.Collections.Generic.List[object]]::new()
    RowsPanel = $null
}
$script:ScriptColors = @{}
$script:Config = $null
$script:CurrentScriptIndex = $null
$script:PreviousSelectedIndex = -1
$script:ConfigDirty = $false
$script:StatusTimer = $null
$script:TableForm = $null
$script:RecoveryForm = $null
$script:BuildingRows = $false

function Add-WhiteSpinnerArrows($Control, $Parent, [switch]$ButtonStyle) {
    $arrowPanel = [System.Windows.Forms.Panel]::new()
    $arrowPanelWidth = if ($ButtonStyle) { 18 } else { 20 }
    $arrowPanel.Left = $Control.Left + $Control.Width - $arrowPanelWidth - 1
    $arrowPanel.Top = $Control.Top + 1
    $arrowPanel.Width = $arrowPanelWidth
    $arrowPanel.Height = $Control.Height - 2
    $arrowPanel.BackColor = Get-UiColor '#1E1E1E'
    $arrowPanel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $arrowPanel.TabStop = $false
    $arrowPanel.Enabled = $Control.Enabled
    $useButtonStyle = [bool]$ButtonStyle
    $buttonState = [pscustomobject]@{ Hover = 0; Pressed = 0 }
    $holdTimer = [System.Windows.Forms.Timer]::new()
    $holdTimer.Interval = 350
    $repeatInterval = 70
    $arrowPanel.Add_Paint({
        param($sender, $eventArgs)
        $graphics = $eventArgs.Graphics
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $centerX = [single]($sender.ClientSize.Width / 2)
        $arrowColor = if ($sender.Enabled) { [System.Drawing.Color]::White } else { Get-UiColor '#707780' }
        if ($useButtonStyle) {
            $topHeight = [int][Math]::Floor($sender.ClientSize.Height / 2)
            $upFillColor = if ($buttonState.Pressed -eq 1) { '#191E26' } elseif ($buttonState.Hover -eq 1) { '#35404F' } else { '#252B35' }
            $downFillColor = if ($buttonState.Pressed -eq 2) { '#191E26' } elseif ($buttonState.Hover -eq 2) { '#35404F' } else { '#252B35' }
            $upBorderColor = if ($buttonState.Pressed -eq 1) { '#4F5B6C' } else { '#687587' }
            $downBorderColor = if ($buttonState.Pressed -eq 2) { '#4F5B6C' } else { '#687587' }
            $upFill = [System.Drawing.SolidBrush]::new((Get-UiColor $upFillColor))
            $downFill = [System.Drawing.SolidBrush]::new((Get-UiColor $downFillColor))
            $upBorder = [System.Drawing.Pen]::new((Get-UiColor $upBorderColor), 1)
            $downBorder = [System.Drawing.Pen]::new((Get-UiColor $downBorderColor), 1)
            $arrowBrush = [System.Drawing.SolidBrush]::new($arrowColor)
            try {
                $graphics.FillRectangle($upFill, 1, 1, $sender.ClientSize.Width - 2, $topHeight - 1)
                $graphics.FillRectangle($downFill, 1, $topHeight + 1, $sender.ClientSize.Width - 2, $sender.ClientSize.Height - $topHeight - 2)
                $graphics.DrawRectangle($upBorder, 0, 0, $sender.ClientSize.Width - 1, $topHeight)
                $graphics.DrawRectangle($downBorder, 0, $topHeight, $sender.ClientSize.Width - 1, $sender.ClientSize.Height - $topHeight - 1)
                $arrowWidth = [single]8
                $arrowHeight = [single]5
                $upCenterY = [single]($topHeight / 2)
                $downCenterY = [single]($topHeight + (($sender.ClientSize.Height - $topHeight) / 2))
                if ($buttonState.Pressed -eq 1) { $upCenterY += 1 }
                if ($buttonState.Pressed -eq 2) { $downCenterY += 1 }
                $upArrow = [System.Drawing.PointF[]]@(
                    [System.Drawing.PointF]::new($centerX, [single]($upCenterY - $arrowHeight / 2)),
                    [System.Drawing.PointF]::new([single]($centerX - $arrowWidth / 2), [single]($upCenterY + $arrowHeight / 2)),
                    [System.Drawing.PointF]::new([single]($centerX + $arrowWidth / 2), [single]($upCenterY + $arrowHeight / 2))
                )
                $downArrow = [System.Drawing.PointF[]]@(
                    [System.Drawing.PointF]::new($centerX, [single]($downCenterY + $arrowHeight / 2)),
                    [System.Drawing.PointF]::new([single]($centerX - $arrowWidth / 2), [single]($downCenterY - $arrowHeight / 2)),
                    [System.Drawing.PointF]::new([single]($centerX + $arrowWidth / 2), [single]($downCenterY - $arrowHeight / 2))
                )
                $graphics.FillPolygon($arrowBrush, $upArrow)
                $graphics.FillPolygon($arrowBrush, $downArrow)
            } finally {
                $upFill.Dispose()
                $downFill.Dispose()
                $upBorder.Dispose()
                $downBorder.Dispose()
                $arrowBrush.Dispose()
            }
            return
        }
        $arrowBrush = [System.Drawing.SolidBrush]::new($arrowColor)
        $centerY = [single]($sender.ClientSize.Height / 2)
        $upArrow = [System.Drawing.PointF[]]@(
            [System.Drawing.PointF]::new($centerX, [single]($centerY - 7)),
            [System.Drawing.PointF]::new([single]($centerX - 5), [single]($centerY - 1)),
            [System.Drawing.PointF]::new([single]($centerX + 5), [single]($centerY - 1))
        )
        $downArrow = [System.Drawing.PointF[]]@(
            [System.Drawing.PointF]::new($centerX, [single]($centerY + 7)),
            [System.Drawing.PointF]::new([single]($centerX - 5), [single]($centerY + 1)),
            [System.Drawing.PointF]::new([single]($centerX + 5), [single]($centerY + 1))
        )
        $graphics.FillPolygon($arrowBrush, $upArrow)
        $graphics.FillPolygon($arrowBrush, $downArrow)
        $arrowBrush.Dispose()
    }.GetNewClosure())
    $target = $Control
    if ($useButtonStyle) {
        $incrementValue = {
            param([int]$Direction)
            if (-not $target.Enabled) { return }
            if ($Direction -eq 1 -and $target.Value -lt $target.Maximum) {
                $target.Value = [Math]::Min($target.Maximum, $target.Value + $target.Increment)
            } elseif ($Direction -eq 2 -and $target.Value -gt $target.Minimum) {
                $target.Value = [Math]::Max($target.Minimum, $target.Value - $target.Increment)
            }
        }.GetNewClosure()
        $holdTimer.Add_Tick({
            $direction = $buttonState.Pressed
            if ($direction -eq 0 -or -not $target.Enabled) {
                $holdTimer.Stop()
                return
            }
            & $incrementValue $direction
            $holdTimer.Interval = $repeatInterval
        }.GetNewClosure())
        $arrowPanel.Add_MouseMove({
            param($sender, $eventArgs)
            $inside = $eventArgs.X -ge 0 -and $eventArgs.X -lt $sender.ClientSize.Width -and
                $eventArgs.Y -ge 0 -and $eventArgs.Y -lt $sender.ClientSize.Height
            $hover = if (-not $inside) { 0 } elseif ($eventArgs.Y -lt ($sender.ClientSize.Height / 2)) { 1 } else { 2 }
            if ($buttonState.Hover -ne $hover) {
                $buttonState.Hover = $hover
                $sender.Invalidate()
            }
        }.GetNewClosure())
        $arrowPanel.Add_MouseLeave({
            param($sender, $eventArgs)
            $buttonState.Hover = 0
            if ($buttonState.Pressed -eq 0) { $sender.Invalidate() }
        }.GetNewClosure())
        $arrowPanel.Add_MouseUp({
            param($sender, $eventArgs)
            $holdTimer.Stop()
            $holdTimer.Interval = 350
            $buttonState.Pressed = 0
            $inside = $eventArgs.X -ge 0 -and $eventArgs.X -lt $sender.ClientSize.Width -and
                $eventArgs.Y -ge 0 -and $eventArgs.Y -lt $sender.ClientSize.Height
            $buttonState.Hover = if ($inside -and $eventArgs.Y -lt ($sender.ClientSize.Height / 2)) { 1 } elseif ($inside) { 2 } else { 0 }
            $sender.Capture = $false
            $sender.Invalidate()
        }.GetNewClosure())
    }
    $arrowPanel.Add_MouseDown({
        param($sender, $eventArgs)
        if ($eventArgs.Button -ne [System.Windows.Forms.MouseButtons]::Left -or -not $target.Enabled) { return }
        if ($useButtonStyle) {
            $buttonState.Pressed = if ($eventArgs.Y -lt ($sender.ClientSize.Height / 2)) { 1 } else { 2 }
            $buttonState.Hover = $buttonState.Pressed
            $sender.Capture = $true
            $sender.Invalidate()
            & $incrementValue $buttonState.Pressed
            $holdTimer.Interval = 350
            $holdTimer.Start()
            return
        }
        $target.Focus()
        if ($eventArgs.Y -lt ($sender.ClientSize.Height / 2)) {
            if ($target.Value -lt $target.Maximum) { $target.Value += $target.Increment }
        } elseif ($target.Value -gt $target.Minimum) {
            $target.Value -= $target.Increment
        }
    }.GetNewClosure())
    $target.Add_EnabledChanged({
        $arrowPanel.Enabled = $target.Enabled
        if (-not $target.Enabled) {
            $holdTimer.Stop()
            $buttonState.Pressed = 0
        }
        $arrowPanel.Invalidate()
    }.GetNewClosure())
    $arrowPanel.Add_Disposed({ $holdTimer.Stop(); $holdTimer.Dispose() }.GetNewClosure())
    [void]$Parent.Controls.Add($arrowPanel)
    $arrowPanel.BringToFront()
}

function Get-UiColor([string]$Hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

function Get-ButtonHoverColor([string]$Hex, [double]$Factor = 1.18) {
    $base = Get-UiColor $Hex
    return [System.Drawing.Color]::FromArgb(
        [Math]::Min(255, [int]($base.R * $Factor)),
        [Math]::Min(255, [int]($base.G * $Factor)),
        [Math]::Min(255, [int]($base.B * $Factor))
    )
}

function Set-ControlStyle($Control, [string]$Back, [string]$Fore, [string]$FontName = 'Segoe UI', [float]$Size = 10, [bool]$Bold = $false) {
    $Control.BackColor = Get-UiColor $Back
    $Control.ForeColor = Get-UiColor $Fore
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $Control.Font = [System.Drawing.Font]::new($FontName, $Size, $style)
}

function New-UiButton([string]$Text, [string]$Back, [string]$Fore = '#FFFFFF') {
    $button = [System.Windows.Forms.Button]::new()
    $button.Text = $Text
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.BorderColor = Get-UiColor '#69758A'
    $button.FlatAppearance.MouseOverBackColor = Get-ButtonHoverColor $Back
    $button.FlatAppearance.MouseDownBackColor = Get-ButtonHoverColor $Back 0.78
    $button.BackColor = Get-UiColor $Back
    $button.ForeColor = Get-UiColor $Fore
    $button.Font = [System.Drawing.Font]::new('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $button.Height = 34
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.UseVisualStyleBackColor = $false
    return $button
}

function Show-Error([string]$Title, [string]$Message) {
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', 'Error')
}

function ConvertTo-JsonScalar($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string] -or $Value -is [char]) {
        return (ConvertTo-Json -InputObject ([string]$Value) -Compress)
    }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }
    if ($Value -is [datetime]) {
        return (ConvertTo-Json -InputObject $Value.ToString('o', [Globalization.CultureInfo]::InvariantCulture) -Compress)
    }
    if ($Value -is [System.Enum]) {
        return (ConvertTo-Json -InputObject $Value.ToString() -Compress)
    }
    if ($Value -is [System.IFormattable]) {
        return $Value.ToString($null, [Globalization.CultureInfo]::InvariantCulture)
    }
    return (ConvertTo-Json -InputObject $Value -Compress)
}

function Test-JsonPrimitive($Value) {
    return (
        $null -eq $Value -or
        $Value -is [string] -or
        $Value -is [char] -or
        $Value -is [bool] -or
        $Value -is [ValueType]
    )
}

function ConvertTo-JsonText($Value, [int]$Indent = 0) {
    if (Test-JsonPrimitive $Value) {
        return (ConvertTo-JsonScalar $Value)
    }

    $padding = ' ' * $Indent
    $childPadding = ' ' * ($Indent + 2)

    if ($Value -is [System.Collections.IDictionary]) {
        $entries = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $Value.Keys) {
            $encodedKey = ConvertTo-JsonScalar ([string]$key)
            $encodedValue = ConvertTo-JsonText $Value[$key] ($Indent + 2)
            $entries.Add("$childPadding$encodedKey`: $encodedValue")
        }
        if ($entries.Count -eq 0) { return '{}' }
        return "{`n$($entries -join ",`n")`n$padding}"
    }

    if ($Value -is [System.Array] -or ($Value -is [System.Collections.IList] -and $Value -isnot [string])) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '[]' }
        $allPrimitive = $true
        foreach ($item in $items) {
            if (-not (Test-JsonPrimitive $item)) { $allPrimitive = $false; break }
        }
        if ($allPrimitive) {
            $compactItems = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $items) { $compactItems.Add((ConvertTo-JsonScalar $item)) }
            return '[' + ($compactItems -join ', ') + ']'
        }
        $formattedItems = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $items) {
            $formattedItems.Add("$childPadding$(ConvertTo-JsonText $item ($Indent + 2))")
        }
        return "[`n$($formattedItems -join ",`n")`n$padding]"
    }

    $properties = @($Value.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty', 'Property', 'AliasProperty', 'ScriptProperty') })
    if ($properties.Count -eq 0) {
        return (ConvertTo-JsonScalar $Value)
    }
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($property in $properties) {
        $encodedKey = ConvertTo-JsonScalar $property.Name
        $encodedValue = ConvertTo-JsonText $property.Value ($Indent + 2)
        $entries.Add("$childPadding$encodedKey`: $encodedValue")
    }
    return "{`n$($entries -join ",`n")`n$padding}"
}

function Save-Json {
    $json = ConvertTo-JsonText $script:Config
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($script:ConfigFile, $json + [Environment]::NewLine, $encoding)
}

function Set-JsonProperty($Object, [string]$Name, $Value) {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Set-Dirty([bool]$Value = $true) {
    $script:ConfigDirty = $Value
    if ($script:SaveButton) {
        $script:SaveButton.Enabled = $Value
    }
}

function Show-Status([string]$Message, [string]$Color = '#1E90FF', [int]$Duration = 2000) {
    $script:StatusLabel.Text = $Message
    $script:StatusLabel.ForeColor = Get-UiColor $Color
    $script:StatusLabel.Visible = $true
    $script:StatusTimer.Stop()
    if ($Duration -gt 0) {
        $script:StatusTimer.Interval = $Duration
        $script:StatusTimer.Start()
    }
}

function Get-Scripts {
    return @($script:Config.ScheduledScripts)
}

function Save-CurrentScript {
    if ($null -eq $script:CurrentScriptIndex) { return }
    $data = $script:Config.ScheduledScripts[[int]$script:CurrentScriptIndex]
    $commands = [System.Collections.Generic.List[string]]::new()
    $times = [System.Collections.Generic.List[string]]::new()
    $delays = [System.Collections.Generic.List[int]]::new()
    $repeats = [System.Collections.Generic.List[int]]::new()
    $days = [System.Collections.Generic.List[string]]::new()
    $modes = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $script:UiState.Rows) {
        $commands.Add([string][int]$row.Command.Value)
        $times.Add(('{0:D2}:{1:D2}:{2:D2}' -f [int]$row.Hour.Value, [int]$row.Minute.Value, [int]$row.Second.Value))
        $delays.Add([int]$row.Delay.Value)
        $repeats.Add([int]$row.Repeat.Value)
        if ($row.ModeValue -eq 'fixed') {
            if ($row.DateModified) {
                $days.Add(('{0:D4}-{1:D2}-{2:D2}' -f [int]$row.Year.Value, [int]$row.Month.Value, [int]$row.Day.Value))
            } else {
                $days.Add([string]$row.OriginalDay)
            }
        } else {
            $days.Add('')
        }
        $modes.Add([string]$row.ModeValue)
    }
    Set-JsonProperty $data 'Commands' @($commands.ToArray())
    Set-JsonProperty $data 'Times' @($times.ToArray())
    Set-JsonProperty $data 'DelaySeconds' @($delays.ToArray())
    Set-JsonProperty $data 'RepeatIntervalMinutes' @($repeats.ToArray())
    Set-JsonProperty $data 'Day' @($days.ToArray())
    Set-JsonProperty $data 'Mode' @($modes.ToArray())
}

function Save-AllConfig {
    try {
        Save-Json
        Set-Dirty $false
        Show-Status '✔ Global configuration saved' '#32CD32' 3000
    } catch {
        Show-Error 'Save failed' $_.Exception.Message
    }
}

function Save-ConfigWithStatus {
    try {
        if ($null -ne $script:CurrentScriptIndex) {
            Save-CurrentScript
            Save-Json
            Set-Dirty $false
            Show-Status '✔ Script configuration saved' '#32CD32' 3000
            $path = [string]$script:Config.ScheduledScripts[[int]$script:CurrentScriptIndex].Path
            [void][System.Windows.Forms.MessageBox]::Show("Config saved for $path", 'Saved', 'OK', 'Information')
        } else {
            Save-AllConfig
        }
    } catch {
        Show-Error 'Save failed' $_.Exception.Message
    }
}

function Confirm-SaveIfDirty {
    if (-not $script:ConfigDirty) { return $true }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        'You have unsaved changes for this script.' + [Environment]::NewLine + 'Do you want to save them?',
        'Unsaved Changes', 'YesNo', 'Question'
    )
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Save-CurrentScript
            Save-Json
            Set-Dirty $false
        } catch {
            Show-Error 'Save failed' $_.Exception.Message
            return $false
        }
    } else {
        Set-Dirty $false
    }
    return $true
}

function Update-RowNumbers {
    for ($i = 0; $i -lt $script:UiState.Rows.Count; $i++) {
        $row = $script:UiState.Rows[$i]
        if ($null -ne $row -and $null -ne $row.Number -and $null -ne $row.Panel -and -not $row.Panel.IsDisposed) {
            $row.Number.Text = '{0}.' -f ($i + 1)
            $row.Panel.Top = $i * 52
        }
    }
    if ($null -ne $script:UiState -and $null -ne $script:UiState.RowsPanel -and -not $script:UiState.RowsPanel.IsDisposed) {
        $minimumHeight = 1
        if ($null -ne $script:RowScroll -and -not $script:RowScroll.IsDisposed) {
            $minimumHeight = [Math]::Max(1, $script:RowScroll.ClientSize.Height - $script:UiState.RowsPanel.Top)
        }
        $script:UiState.RowsPanel.Height = [Math]::Max($minimumHeight, $script:UiState.Rows.Count * 52)
        $script:UiState.RowsPanel.Invalidate()
    }
    if ($null -ne $script:ScrollContentPanel -and -not $script:ScrollContentPanel.IsDisposed) {
        $script:ScrollContentPanel.Height = $script:UiState.RowsPanel.Top + $script:UiState.RowsPanel.Height
    }
}

function Set-CommandDescription([string]$CommandName, [string]$Description) {
    $control = $script:DescriptionLabel
    if ($null -eq $control -or $control.IsDisposed) { return }
    $control.Clear()
    $control.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Center
    $control.SelectionColor = [System.Drawing.Color]::White
    $control.SelectionFont = [System.Drawing.Font]::new('Segoe UI Emoji', 13, [System.Drawing.FontStyle]::Bold)
    $control.AppendText("✅ Selected: $CommandName`r`n")
    $control.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Center
    $control.SelectionColor = Get-UiColor '#FFD700'
    $control.SelectionFont = [System.Drawing.Font]::new('Segoe UI Emoji', 12, [System.Drawing.FontStyle]::Italic)
    $control.AppendText($Description)
    $control.SelectionStart = 0
    $control.SelectionLength = 0
}

function Clear-EditorRows {
    $wasBuildingRows = $script:BuildingRows
    $script:BuildingRows = $true
    try {
        foreach ($row in @($script:UiState.Rows.ToArray())) {
            $script:UiState.RowsPanel.Controls.Remove($row.Panel)
            $row.Panel.Dispose()
        }
        $script:UiState.Rows.Clear()
        Update-RowNumbers
    } finally {
        $script:BuildingRows = $wasBuildingRows
    }
}

function Get-PastDate([string]$Day, [string]$Time) {
    if (-not $Day -or -not $Time) { return $false }
    try {
        $value = [datetime]::ParseExact("$Day $Time", 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
        return ($value -lt [datetime]::Now)
    } catch { return $false }
}

function Get-BackupFiles {
    if (-not (Test-Path -LiteralPath $script:BackupDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $script:BackupDir -Filter '*.json' -File | Sort-Object CreationTime, Name)
}

function Refresh-BackupList {
    if (-not $script:BackupListPanel -or $script:BackupListPanel.IsDisposed) { return }
    $script:BackupListPanel.SuspendLayout()
    $script:BackupListPanel.Controls.Clear()
    $files = Get-BackupFiles
    if ($files.Count -eq 0) {
        $empty = [System.Windows.Forms.Label]::new()
        $empty.Text = 'No backup has been created yet.'; $empty.ForeColor = Get-UiColor '#9E9E9E'
        $empty.Font = [System.Drawing.Font]::new('Segoe UI', 13); $empty.AutoSize = $true
        $empty.Margin = [System.Windows.Forms.Padding]::new(20, 35, 10, 10)
        $script:BackupListPanel.Controls.Add($empty)
    } else {
        $index = 0
        foreach ($file in $files) {
            $rowPanel = [System.Windows.Forms.Panel]::new()
            $rowPanel.Width = [Math]::Max(500, $script:BackupListPanel.ClientSize.Width - 30)
            $rowPanel.Height = 48
            $rowPanel.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 8)
            $rowPanel.BackColor = Get-UiColor $script:Palette.Panel
            $number = [System.Windows.Forms.Label]::new()
            $number.Text = "$($index + 1)."; $number.Left = 8; $number.Top = 0
            $number.Width = 45; $number.Height = 48; $number.TextAlign = 'MiddleCenter'
            $number.ForeColor = Get-UiColor $script:Palette.Gold; $number.Font = [System.Drawing.Font]::new('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
            $name = [System.Windows.Forms.Label]::new()
            $name.Text = $file.BaseName; $name.Left = 58; $name.Top = 0
            $name.Height = 48; $name.TextAlign = 'MiddleLeft'; $name.ForeColor = [System.Drawing.Color]::White
            $name.Font = [System.Drawing.Font]::new('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
            $created = $file.CreationTime.ToString('yyyy-MM-dd HH:mm')
            $backupTip = [System.Windows.Forms.ToolTip]::new()
            $backupTip.SetToolTip($name, "$($file.BaseName)`r`nCreated: $created")
            $restore = New-UiButton '♻ Restore' '#1E90FF'; $restore.Width = 110; $restore.Height = 34; $restore.Top = 7
            $delete = New-UiButton '🗑 Delete' '#B22222'; $delete.Width = 100; $delete.Height = 34; $delete.Top = 7
            $restore.Anchor = 'Top,Right'; $delete.Anchor = 'Top,Right'
            $number.Anchor = 'Top,Left'; $name.Anchor = 'Top,Left,Right'
            $rowPanel.Controls.AddRange(@($number, $name, $restore, $delete))
            $layoutRow = {
                param($sender, $eventArgs)
                $delete.Left = $sender.ClientSize.Width - $delete.Width - 10
                $restore.Left = $delete.Left - $restore.Width - 12
                $name.Width = [Math]::Max(100, $restore.Left - $name.Left - 12)
            }.GetNewClosure()
            $rowPanel.Add_Resize($layoutRow)
            & $layoutRow $rowPanel $null
            $backupPath = $file.FullName
            $restore.Add_Click({ Restore-Backup $backupPath }.GetNewClosure())
            $delete.Add_Click({ Remove-Backup $backupPath }.GetNewClosure())
            $script:BackupListPanel.Controls.Add($rowPanel)
            $index++
        }
    }
    $script:BackupListPanel.ResumeLayout()
}

function Open-RecoveryWindow {
    if ($script:RecoveryForm -and -not $script:RecoveryForm.IsDisposed) {
        $script:RecoveryForm.Activate()
        Refresh-BackupList
        return
    }
    $form = [System.Windows.Forms.Form]::new()
    $script:RecoveryForm = $form
    $form.Text = 'Recovery - Scripts Backups'; $form.Size = [System.Drawing.Size]::new(760, 540)
    $form.MinimumSize = [System.Drawing.Size]::new(520, 340); $form.StartPosition = 'CenterParent'
    $form.BackColor = Get-UiColor $script:Palette.Background
    if (Test-Path $script:IconPath) { try { $form.Icon = [System.Drawing.Icon]::new($script:IconPath) } catch {} }
    $header = [System.Windows.Forms.Panel]::new(); $header.Dock = 'Top'; $header.Height = 58
    $header.BackColor = Get-UiColor $script:Palette.Panel
    $title = [System.Windows.Forms.Label]::new(); $title.Text = '🛟 Recovery'; $title.Dock = 'Left'
    $title.Width = 400; $title.TextAlign = 'MiddleLeft'; $title.ForeColor = Get-UiColor $script:Palette.Gold
    $title.Font = [System.Drawing.Font]::new('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $backupButton = New-UiButton '➕ Backup' '#228B22'; $backupButton.Dock = 'Right'; $backupButton.Width = 130
    $backupButton.Add_Click({ New-Backup })
    $header.Controls.Add($backupButton); $header.Controls.Add($title)
    $script:BackupListPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $script:BackupListPanel.Dock = 'Fill'; $script:BackupListPanel.AutoScroll = $true
    $script:BackupListPanel.FlowDirection = 'TopDown'; $script:BackupListPanel.WrapContents = $false
    $script:BackupListPanel.Padding = [System.Windows.Forms.Padding]::new(12)
    $script:BackupListPanel.BackColor = Get-UiColor $script:Palette.Background
    $script:BackupListPanel.Add_Resize({
        param($sender, $eventArgs)
        $targetWidth = [Math]::Max(500, $sender.ClientSize.Width - $sender.Padding.Horizontal - 8)
        foreach ($row in $sender.Controls) {
            if ($row -is [System.Windows.Forms.Panel]) { $row.Width = $targetWidth }
        }
        $sender.PerformLayout()
    })
    $form.Controls.Add($script:BackupListPanel); $form.Controls.Add($header)
    $form.Add_FormClosed({ $script:RecoveryForm = $null; $script:BackupListPanel = $null })
    Refresh-BackupList
    [void]$form.ShowDialog($script:MainForm)
}

function Read-BackupName([string]$Message, [string]$InitialName) {
    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = 'New Backup'
    $dialog.Size = [System.Drawing.Size]::new(480, 220)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = Get-UiColor $script:Palette.Background
    $prompt = [System.Windows.Forms.Label]::new()
    $prompt.Text = $Message
    $prompt.Left = 18; $prompt.Top = 12; $prompt.Width = 425; $prompt.Height = 58
    $prompt.ForeColor = [System.Drawing.Color]::White
    $prompt.Font = [System.Drawing.Font]::new('Segoe UI', 10)
    $dialog.Controls.Add($prompt)
    $entry = [System.Windows.Forms.TextBox]::new()
    $entry.Left = 18; $entry.Top = 75; $entry.Width = 425; $entry.Text = $InitialName
    $entry.Font = [System.Drawing.Font]::new('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $dialog.Controls.Add($entry)
    $create = New-UiButton '✔ Create' '#228B22'; $create.Left = 205; $create.Top = 120; $create.Width = 110
    $cancel = New-UiButton '❌ Cancel' '#555555'; $cancel.Left = 325; $cancel.Top = 120; $cancel.Width = 115
    $create.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.AcceptButton = $create; $dialog.CancelButton = $cancel
    $dialog.Controls.AddRange(@($create, $cancel))
    $dialog.Add_Shown({ $entry.Select(); $entry.SelectAll() }.GetNewClosure())
    if ($dialog.ShowDialog($script:RecoveryForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $result = $entry.Text
        $dialog.Dispose()
        return $result
    }
    $dialog.Dispose()
    return $null
}

function New-Backup {
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) {
        Show-Error 'Backup' 'scripts_edit.json was not found.'
        return
    }
    $defaultName = 'Backup ' + (Get-Date -Format 'yyyy-MM-dd HH-mm')
    $message = 'Enter a name for the new backup:'
    if ($script:ConfigDirty) {
        $message += "`r`n`r`n⚠ You have unsaved changes. The backup contains only the settings that are currently SAVED."
    }
    $name = Read-BackupName $message $defaultName
    if ($null -eq $name) { return }
    $clean = [regex]::Replace($name, '[<>:"/\\|?*\x00-\x1F]', '').Trim().TrimEnd('.').Trim()
    if ($clean.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) { $clean = $clean.Substring(0, $clean.Length - 5).Trim() }
    if (-not $clean) {
        [void][System.Windows.Forms.MessageBox]::Show('The backup name is empty or invalid.', 'Backup', 'OK', 'Warning')
        return
    }
    try {
        [void][System.IO.Directory]::CreateDirectory($script:BackupDir)
        $dest = Join-Path $script:BackupDir "$clean.json"
        if ((Test-Path -LiteralPath $dest) -and [System.Windows.Forms.MessageBox]::Show("A backup named '$clean' already exists.`r`nOverwrite it?", 'Backup', 'YesNo', 'Warning') -ne 'Yes') { return }
        [System.IO.File]::WriteAllBytes($dest, [System.IO.File]::ReadAllBytes($script:ConfigFile))
        Refresh-BackupList
    } catch { Show-Error 'Backup failed' $_.Exception.Message }
}

function Restore-Backup([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        [void][System.Windows.Forms.MessageBox]::Show('This backup file no longer exists.', 'Restore', 'OK', 'Warning')
        Refresh-BackupList
        return
    }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ([System.Windows.Forms.MessageBox]::Show("Restore backup '$name'?`r`nThe current scripts_edit.json will be OVERWRITTEN.", 'Restore Backup', 'YesNo', 'Warning') -ne 'Yes') { return }
    try {
        $restored = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $restored -or $null -eq $restored.ScheduledScripts) { throw "The 'ScheduledScripts' section is missing." }
        [System.IO.File]::WriteAllBytes($script:ConfigFile, [System.IO.File]::ReadAllBytes($Path))
        $script:Config = $restored
        $script:ScriptList.Items.Clear()
        $script:ScriptColors.Clear()
        $i = 1
        foreach ($item in (Get-Scripts)) {
            [void]$script:ScriptList.Items.Add("$i. $(Get-ScriptDisplayName $item)")
            $i++
        }
        Clear-EditorRows
        $script:CurrentScriptIndex = $null; $script:PreviousSelectedIndex = -1
        $script:DescriptionLabel.Text = ''
        Set-Dirty $false
        $script:AddButton.Enabled = $false; $script:DefaultButton.Enabled = $false; $script:SaveButton.Enabled = $false
        Show-Status '⚠️ Select a SCRIPT first, then edit selected SCRIPT!' '#FFD700' 0
        [void][System.Windows.Forms.MessageBox]::Show("✔️ Backup '$name' restored successfully!", 'Restore', 'OK', 'Information')
        Refresh-BackupList
    } catch { Show-Error 'Restore failed' $_.Exception.Message }
}

function Remove-Backup([string]$Path) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ([System.Windows.Forms.MessageBox]::Show("Delete backup '$name'?`r`nThis cannot be undone.", 'Delete Backup', 'YesNo', 'Warning') -ne 'Yes') { return }
    try { Remove-Item -LiteralPath $Path -ErrorAction Stop; Refresh-BackupList }
    catch { Show-Error 'Delete failed' $_.Exception.Message }
}

function Get-ScriptDisplayName($ScriptData) {
    return [System.IO.Path]::GetFileName([string]$ScriptData.Path)
}

function Set-ScriptModeState($Row) {
    $fixed = $Row.ModeValue -eq 'fixed'
    if ($fixed) {
        $Row.ModeButton.Text = '✔ Fixed'; $Row.ModeButton.BackColor = Get-UiColor '#32CD32'
        $Row.ModeButton.ForeColor = [System.Drawing.Color]::White
        $Row.ModeButton.FlatAppearance.MouseOverBackColor = Get-UiColor '#59E879'
        $Row.ModeButton.FlatAppearance.MouseDownBackColor = Get-UiColor '#22A83C'
    } else {
        $Row.ModeValue = 'loop'; $Row.ModeButton.Text = '🔄 Loop'; $Row.ModeButton.BackColor = Get-UiColor '#FFD700'
        $Row.ModeButton.ForeColor = Get-UiColor '#0031FF'
        $Row.ModeButton.FlatAppearance.MouseOverBackColor = Get-UiColor '#FFE45C'
        $Row.ModeButton.FlatAppearance.MouseDownBackColor = Get-UiColor '#D9A900'
    }
    foreach ($control in @($Row.Year, $Row.Month, $Row.Day)) { $control.Enabled = $fixed }
}

function New-ScriptRow($ScriptData = $null, [int]$Index = -1) {
    if ($script:UiState.Rows.Count -ge $script:MaxRows) {
        [void][System.Windows.Forms.MessageBox]::Show("You cannot add more than $($script:MaxRows) rows.", 'Max Rows', 'OK', 'Warning')
        return $null
    }
    $today = [datetime]::Today
    $command = 1; $hour = 0; $minute = 0; $second = 0; $delay = 0; $repeat = 0; $mode = 'loop'; $date = $today
    $originalDay = $today.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    if ($null -ne $ScriptData) {
        $commands = @($ScriptData.Commands)
        if ($Index -lt 0 -or $Index -ge $commands.Count) { throw "Command entry $Index is not available for the selected script." }
        $parsed = 1
        if ([int]::TryParse([string]$commands[$Index], [ref]$parsed)) { $command = [Math]::Min(100, [Math]::Max(0, $parsed)) }
        $times = @($ScriptData.Times)
        if ($Index -lt $times.Count -and [string]$times[$Index] -match '^(\d{1,2}):(\d{1,2}):(\d{1,2})$') {
            $hour = [Math]::Min(23, [int]$Matches[1]); $minute = [Math]::Min(59, [int]$Matches[2]); $second = [Math]::Min(59, [int]$Matches[3])
        }
        $delays = @($ScriptData.DelaySeconds); $repeats = @($ScriptData.RepeatIntervalMinutes)
        if ($Index -lt $delays.Count) { $delay = [Math]::Min(999, [Math]::Max(0, [int]$delays[$Index])) }
        if ($Index -lt $repeats.Count) { $repeat = [Math]::Min(999, [Math]::Max(0, [int]$repeats[$Index])) }
        $days = @($ScriptData.Day); $parsedDate = [datetime]::MinValue
        if ($Index -lt $days.Count -and [string]$days[$Index] -and [datetime]::TryParseExact([string]$days[$Index], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
            $date = $parsedDate
            $originalDay = [string]$days[$Index]
        }
        $modes = @($ScriptData.Mode)
        if ($Index -lt $modes.Count -and $modes[$Index] -eq 'fixed') { $mode = 'fixed' }
    }

    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Height = 52; $panel.Width = 1260; $panel.BackColor = Get-UiColor '#191C24'
    $number = [System.Windows.Forms.Label]::new()
    $number.Left = 4; $number.Top = 11; $number.Width = 50; $number.Height = 30
    $number.Text = '{0}.' -f ($script:UiState.Rows.Count + 1)
    $number.TextAlign = 'MiddleCenter'; $number.ForeColor = Get-UiColor $script:Palette.Gold
    $number.Font = [System.Drawing.Font]::new('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    [void]$panel.Controls.Add($number)

    $commandBox = [System.Windows.Forms.NumericUpDown]::new()
    $commandBox.Left = 70; $commandBox.Top = 9; $commandBox.Width = 90; $commandBox.Height = 34
    $commandBox.Minimum = 0; $commandBox.Maximum = 100; $commandBox.Value = $command; $commandBox.ReadOnly = $true
    $hourBox = [System.Windows.Forms.NumericUpDown]::new()
    $hourBox.Left = 195; $hourBox.Top = 9; $hourBox.Width = 55; $hourBox.Minimum = 0; $hourBox.Maximum = 23; $hourBox.Value = $hour; $hourBox.ReadOnly = $true
    $minuteBox = [System.Windows.Forms.NumericUpDown]::new()
    $minuteBox.Left = 260; $minuteBox.Top = 9; $minuteBox.Width = 55; $minuteBox.Minimum = 0; $minuteBox.Maximum = 59; $minuteBox.Value = $minute; $minuteBox.ReadOnly = $true
    $secondBox = [System.Windows.Forms.NumericUpDown]::new()
    $secondBox.Left = 325; $secondBox.Top = 9; $secondBox.Width = 55; $secondBox.Minimum = 0; $secondBox.Maximum = 59; $secondBox.Value = $second; $secondBox.ReadOnly = $true
    $delayBox = [System.Windows.Forms.NumericUpDown]::new()
    $delayBox.Left = 425; $delayBox.Top = 9; $delayBox.Width = 95; $delayBox.Minimum = 0; $delayBox.Maximum = 999; $delayBox.Value = $delay; $delayBox.ReadOnly = $true
    $repeatBox = [System.Windows.Forms.NumericUpDown]::new()
    $repeatBox.Left = 565; $repeatBox.Top = 9; $repeatBox.Width = 105; $repeatBox.Minimum = 0; $repeatBox.Maximum = 999; $repeatBox.Value = $repeat; $repeatBox.ReadOnly = $true
    foreach ($box in @($commandBox, $hourBox, $minuteBox, $secondBox, $delayBox, $repeatBox)) {
        $box.BackColor = Get-UiColor '#1E1E1E'; $box.ForeColor = [System.Drawing.Color]::White
        $box.Font = [System.Drawing.Font]::new('Segoe UI Emoji', 14, [System.Drawing.FontStyle]::Bold)
        $box.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
        [void]$panel.Controls.Add($box)
    }
    foreach ($sepSpec in @(@{X=250;T=':'}, @{X=315;T=':'})) {
        $sep = [System.Windows.Forms.Label]::new(); $sep.Left = $sepSpec.X; $sepSpecText = $sepSpec.T
        $sep.Top = 10; $sep.Width = 10; $sep.Height = 30; $sep.Text = $sepSpecText
        $sep.ForeColor = [System.Drawing.Color]::White; $sep.Font = [System.Drawing.Font]::new('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        [void]$panel.Controls.Add($sep)
    }
    $yearBox = [System.Windows.Forms.NumericUpDown]::new()
    $yearBox.Left = 705; $yearBox.Top = 9; $yearBox.Width = 80; $yearBox.Minimum = 1; $yearBox.Maximum = 9999
    $yearBox.Value = $date.Year; $yearBox.ReadOnly = $true
    $monthBox = [System.Windows.Forms.NumericUpDown]::new()
    $monthBox.Left = 800; $monthBox.Top = 9; $monthBox.Width = 65
    $monthBox.Minimum = 1; $monthBox.Maximum = 12; $monthBox.Value = $date.Month; $monthBox.ReadOnly = $true
    $dayBox = [System.Windows.Forms.NumericUpDown]::new()
    $dayBox.Left = 880; $dayBox.Top = 9; $dayBox.Width = 65
    $dayBox.Minimum = 1; $dayBox.Maximum = 31; $dayBox.Value = $date.Day; $dayBox.ReadOnly = $true
    foreach ($box in @($yearBox, $monthBox, $dayBox)) {
        $box.BackColor = Get-UiColor '#1E1E1E'; $box.ForeColor = [System.Drawing.Color]::White
        $box.Font = [System.Drawing.Font]::new('Segoe UI Emoji', 14, [System.Drawing.FontStyle]::Bold)
        $box.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
        [void]$panel.Controls.Add($box)
    }
    foreach ($sepSpec in @(@{X=785;T='-'}, @{X=865;T='-'})) {
        $sep = [System.Windows.Forms.Label]::new(); $sep.Left = $sepSpec.X; $sep.Top = 10
        $sep.Width = 14; $sep.Height = 30; $sep.Text = $sepSpec.T
        $sep.ForeColor = [System.Drawing.Color]::White; $sep.Font = [System.Drawing.Font]::new('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        [void]$panel.Controls.Add($sep)
    }
    $modeButton = New-UiButton '🔄 Loop' '#FFD700' '#0031FF'
    $modeButton.Font = [System.Drawing.Font]::new('Segoe UI Emoji', 13, [System.Drawing.FontStyle]::Bold)
    $modeButton.Left = 970; $modeButton.Top = 8; $modeButton.Width = 115; [void]$panel.Controls.Add($modeButton)
    $deleteButton = New-UiButton '🗑 Delete' '#9E3447'
    $deleteButton.Font = [System.Drawing.Font]::new('Segoe UI Emoji', 11, [System.Drawing.FontStyle]::Bold)
    $deleteButton.FlatAppearance.MouseOverBackColor = Get-UiColor '#C64B60'; $deleteButton.FlatAppearance.MouseDownBackColor = Get-UiColor '#7E2536'
    $deleteButton.Left = 1120; $deleteButton.Top = 8; $deleteButton.Width = 120; [void]$panel.Controls.Add($deleteButton)
    foreach ($spinner in @($commandBox, $hourBox, $minuteBox, $secondBox, $delayBox, $repeatBox, $yearBox, $monthBox, $dayBox)) {
        Add-WhiteSpinnerArrows $spinner $panel -ButtonStyle
    }
    $row = @{
        Panel=$panel; Number=$number; Command=$commandBox; Hour=$hourBox; Minute=$minuteBox; Second=$secondBox
        Delay=$delayBox; Repeat=$repeatBox; Year=$yearBox; Month=$monthBox; Day=$dayBox
        ModeButton=$modeButton; ModeValue=$mode; OriginalDay=$originalDay; DateModified=$false
    }
    $modeButton.Add_Click({
        if ($row.ModeValue -eq 'loop') { $row.ModeValue = 'fixed' } else { $row.ModeValue = 'loop' }
        Set-ScriptModeState $row
        if (-not $script:BuildingRows) { Set-Dirty $true }
    }.GetNewClosure())
    foreach ($control in @($commandBox, $hourBox, $minuteBox, $secondBox, $delayBox, $repeatBox, $yearBox, $monthBox, $dayBox)) {
        $control.Add_ValueChanged({ if (-not $script:BuildingRows) { Set-Dirty $true } }.GetNewClosure())
    }
    $dateState = [pscustomobject]@{ Updating = $false }
    $updateDateLimits = {
        if ($dateState.Updating) { return }
        $dateState.Updating = $true
        try {
            $current = [datetime]::Today
            $lastDay = [datetime]::DaysInMonth([int]$yearBox.Value, [int]$monthBox.Value)
            if ($dayBox.Value -gt $lastDay) { $dayBox.Value = $lastDay }
            $selectedDate = [datetime]::new([int]$yearBox.Value, [int]$monthBox.Value, [int]$dayBox.Value)
            if ($selectedDate.Date -lt $current) {
                $yearBox.Value = $current.Year
                $monthBox.Value = $current.Month
                $dayBox.Value = $current.Day
            }
            $yearBox.Maximum = [Math]::Max($current.Year + 10, [int]$yearBox.Value)
            $yearBox.Minimum = $current.Year
            $monthMinimum = if ([int]$yearBox.Value -eq $current.Year) { $current.Month } else { 1 }
            $monthBox.Maximum = 12
            $monthBox.Minimum = 1
            if ($monthBox.Value -lt $monthMinimum) { $monthBox.Value = $monthMinimum }
            $monthBox.Minimum = $monthMinimum
            $lastDay = [datetime]::DaysInMonth([int]$yearBox.Value, [int]$monthBox.Value)
            $dayMinimum = if ([int]$yearBox.Value -eq $current.Year -and [int]$monthBox.Value -eq $current.Month) { $current.Day } else { 1 }
            $dayBox.Minimum = 1
            if ($dayBox.Value -gt $lastDay) { $dayBox.Value = $lastDay }
            $dayBox.Maximum = $lastDay
            if ($dayBox.Value -lt $dayMinimum) { $dayBox.Value = $dayMinimum }
            $dayBox.Minimum = $dayMinimum
        } finally {
            $dateState.Updating = $false
        }
    }.GetNewClosure()
    $dateChanged = {
        if ($dateState.Updating) { return }
        $row.DateModified = $true
        & $updateDateLimits
    }.GetNewClosure()
    $yearBox.Add_ValueChanged($dateChanged); $monthBox.Add_ValueChanged($dateChanged); $dayBox.Add_ValueChanged($dateChanged)
    $capturedRow = $row; $state = $script:UiState
    $deleteButton.Add_Click({
        $rowIndex = $state.Rows.IndexOf($capturedRow)
        if ($rowIndex -lt 0) { return }
        $state.Rows.RemoveAt($rowIndex); $state.RowsPanel.Controls.Remove($capturedRow.Panel); $capturedRow.Panel.Dispose()
        Update-RowNumbers; Set-Dirty $true
    }.GetNewClosure())
    Set-ScriptModeState $row
    $script:UiState.Rows.Add($row); [void]$script:UiState.RowsPanel.Controls.Add($panel)
    Update-RowNumbers
    return $row
}

function Load-Script([int]$Index) {
    $scripts = @($script:Config.ScheduledScripts)
    if ($Index -lt 0 -or $Index -ge $scripts.Count -or $script:CurrentScriptIndex -eq $Index) { return }
    if (-not (Confirm-SaveIfDirty)) { return }
    $script:CurrentScriptIndex = $Index; $script:PreviousSelectedIndex = $Index
    $data = $scripts[$Index]
    try {
        $script:BuildingRows = $true; Clear-EditorRows
        $commands = @($data.Commands)
        for ($i = 0; $i -lt $commands.Count; $i++) { [void](New-ScriptRow $data $i) }
        Update-RowNumbers
    } catch {
        Show-Error 'Load script failed' $_.Exception.Message
        return
    } finally { $script:BuildingRows = $false }
    $description = if ($data.Description) { [string]$data.Description } else { 'No description available.' }
    Set-CommandDescription (Get-ScriptDisplayName $data) $description
    $script:DescriptionLabel.Visible = $true; Set-Dirty $false; $script:StatusLabel.Visible = $false
    $script:AddButton.Enabled = $true; $script:DefaultButton.Enabled = $true
    try { $script:RowScroll.VerticalScroll.Value = 0 } catch {}
}

function Reset-CurrentScript {
    if ($null -eq $script:CurrentScriptIndex) { return }
    if ([System.Windows.Forms.MessageBox]::Show('Are you sure?' + [Environment]::NewLine + 'Only the selected script will be reset.', 'Reset to Default', 'YesNo', 'Question') -ne 'Yes') { return }
    try {
        if (-not (Test-Path -LiteralPath $script:DefaultConfigFile)) { throw "scripts_default.json not found:`r`n$script:DefaultConfigFile" }
        $defaults = Get-Content -LiteralPath $script:DefaultConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $defaults.ScheduledScripts) { throw "The 'ScheduledScripts' section is missing from scripts_default.json." }
        $index = [int]$script:CurrentScriptIndex
        if ($index -ge $defaults.ScheduledScripts.Count) { throw "Script index $index is not present in scripts_default.json." }
        $data = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $defaults.ScheduledScripts[$index] -Depth 100)
        if ($null -eq $data.Commands) { throw "Default script at index $index is missing Commands." }
        $commands = @($data.Commands); $data.Mode = @('loop') * $commands.Count; $data.Day = @('') * $commands.Count
        $script:Config.ScheduledScripts[$index] = $data
        $script:BuildingRows = $true; Clear-EditorRows
        for ($i = 0; $i -lt $commands.Count; $i++) { [void](New-ScriptRow $data $i) }
        Update-RowNumbers; Save-Json; Set-Dirty $false
        Set-CommandDescription (Get-ScriptDisplayName $data) ([string]$data.Description)
        Show-Status '↺ Script reset to default & auto-saved' '#32CD32' 3000
    } catch { Show-Error 'Reset failed' $_.Exception.Message }
    finally { $script:BuildingRows = $false }
}

function Reset-AllScripts {
    $message = "⚠ This will ERASE ALL ScheduledScripts data!`r`n`r`nCommands, Times, Delay, Repeat, Mode and Day`r`nwill be cleared for EVERY script.`r`n`r`nDo you want to continue?"
    if ([System.Windows.Forms.MessageBox]::Show($message, 'RESET ALL SCRIPTS', 'YesNo', 'Warning') -ne 'Yes') { return }
    foreach ($item in $script:Config.ScheduledScripts) {
        Set-JsonProperty $item 'Commands' @(); Set-JsonProperty $item 'Times' @()
        Set-JsonProperty $item 'DelaySeconds' @(); Set-JsonProperty $item 'RepeatIntervalMinutes' @()
        Set-JsonProperty $item 'Mode' @(); Set-JsonProperty $item 'Day' @()
    }
    Clear-EditorRows; $script:CurrentScriptIndex = $null; $script:PreviousSelectedIndex = -1
    $script:ScriptList.ClearSelected(); $script:DescriptionLabel.Clear()
    $script:AddButton.Enabled = $false; $script:DefaultButton.Enabled = $false
    try {
        Save-Json; Set-Dirty $false; Show-Status '⚠ ALL scripts RESET & auto-saved' '#FF4500' 3000
        $script:SelectStatusTimer.Stop(); $script:SelectStatusTimer.Start()
    } catch { Show-Error 'Reset failed' $_.Exception.Message }
}

function Open-ScriptsTable {
    if ($script:TableForm -and -not $script:TableForm.IsDisposed) { $script:TableForm.Activate(); return }
    $form = [System.Windows.Forms.Form]::new(); $script:TableForm = $form
    $form.Text = 'Scripts Overview (Read Only)'; $form.Size = [System.Drawing.Size]::new(1500, 800)
    $form.StartPosition = 'CenterParent'; $form.BackColor = Get-UiColor $script:Palette.Background
    if (Test-Path $script:IconPath) { try { $form.Icon = [System.Drawing.Icon]::new($script:IconPath) } catch {} }
    $grid = [System.Windows.Forms.DataGridView]::new()
    $grid.Dock = 'Fill'; $grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false; $grid.AutoSizeColumnsMode = 'Fill'; $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false; $grid.BorderStyle = 'None'; $grid.CellBorderStyle = 'SingleHorizontal'
    $grid.ColumnHeadersBorderStyle = 'None'; $grid.AllowUserToResizeRows = $false; $grid.ScrollBars = 'Both'
    $grid.BackgroundColor = Get-UiColor $script:Palette.Background; $grid.GridColor = Get-UiColor '#343C4A'; $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersDefaultCellStyle.BackColor = Get-UiColor $script:Palette.Background
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Gold
    $grid.ColumnHeadersDefaultCellStyle.Font = [System.Drawing.Font]::new('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
    $grid.ColumnHeadersDefaultCellStyle.Alignment = 'MiddleCenter'; $grid.ColumnHeadersHeight = 48; $grid.ColumnHeadersHeightSizeMode = 'DisableResizing'
    $grid.DefaultCellStyle.BackColor = Get-UiColor $script:Palette.Background; $grid.DefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Text
    $grid.DefaultCellStyle.SelectionBackColor = Get-UiColor '#34445A'; $grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $grid.DefaultCellStyle.Font = [System.Drawing.Font]::new('Segoe UI', 15); $grid.DefaultCellStyle.Alignment = 'MiddleCenter'
    $grid.DefaultCellStyle.Padding = [System.Windows.Forms.Padding]::new(8, 2, 8, 2)
    $grid.AlternatingRowsDefaultCellStyle.BackColor = Get-UiColor '#252B37'; $grid.AlternatingRowsDefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Text
    $grid.RowTemplate.Height = 42; $grid.RowTemplate.MinimumHeight = 42
    foreach ($column in @('⚛ Script', '🆔 Row', '⚙ Command', '🕓 Time', '🌀 Delay', '🔂 Repeat', '🔃 Mode', '📆 Day')) { [void]$grid.Columns.Add($column, $column) }
    for ($scriptIndex = 0; $scriptIndex -lt $script:Config.ScheduledScripts.Count; $scriptIndex++) {
        $data = $script:Config.ScheduledScripts[$scriptIndex]; $name = Get-ScriptDisplayName $data; $commands = @($data.Commands)
        if ($commands.Count -eq 0) {
            $rowIndex = $grid.Rows.Add($name, '-', '📂 No Data', '-', '-', '-', '-', '-')
            $grid.Rows[$rowIndex].DefaultCellStyle.BackColor = Get-UiColor $script:Palette.Panel
            $grid.Rows[$rowIndex].DefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Muted
        } else {
            for ($i = 0; $i -lt $commands.Count; $i++) {
                $time = if ($i -lt @($data.Times).Count) { $data.Times[$i] } else { '-' }
                $delay = if ($i -lt @($data.DelaySeconds).Count) { $data.DelaySeconds[$i] } else { '-' }
                $repeat = if ($i -lt @($data.RepeatIntervalMinutes).Count) { $data.RepeatIntervalMinutes[$i] } else { '-' }
                $mode = if ($i -lt @($data.Mode).Count -and $data.Mode[$i]) { $data.Mode[$i] } else { 'loop' }
                $day = if ($i -lt @($data.Day).Count) { $data.Day[$i] } else { '' }
                $rowIndex = $grid.Rows.Add($name, ($i + 1), $commands[$i], $time, $delay, $repeat, $mode, $(if ($day) { $day } else { '-' }))
                if ($mode -eq 'fixed' -and (Get-PastDate ([string]$day) ([string]$time))) {
                    $grid.Rows[$rowIndex].DefaultCellStyle.BackColor = Get-UiColor '#8B0000'; $grid.Rows[$rowIndex].DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
                } elseif ($mode -eq 'fixed') {
                    $grid.Rows[$rowIndex].DefaultCellStyle.BackColor = Get-UiColor '#2E8B57'; $grid.Rows[$rowIndex].DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
                } else {
                    $grid.Rows[$rowIndex].DefaultCellStyle.BackColor = Get-UiColor '#252B37'; $grid.Rows[$rowIndex].DefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Muted
                }
            }
        }
        if ($scriptIndex -lt $script:Config.ScheduledScripts.Count - 1) {
            $spacer = $grid.Rows.Add('', '', '', '', '', '', '', '')
            $grid.Rows[$spacer].Height = 14; $grid.Rows[$spacer].DefaultCellStyle.BackColor = Get-UiColor $script:Palette.Background
        }
    }
    $form.Controls.Add($grid); $form.Add_FormClosed({ $script:TableForm = $null })
    [void]$form.ShowDialog($script:MainForm)
}

try {
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) { throw "scripts_edit.json was not found:`r`n$script:ConfigFile" }
    $script:Config = Get-Content -LiteralPath $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $script:Config.ScheduledScripts -or $script:Config.ScheduledScripts -isnot [array]) { throw "The 'ScheduledScripts' array is missing from scripts_edit.json." }
} catch {
    Show-Error 'Configuration error' $_.Exception.Message
    exit 1
}

$script:MainForm = [System.Windows.Forms.Form]::new()
$script:MainForm.Text = 'Automation Scripts Editor'
$workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$initialWidth = [Math]::Min(1535, [Math]::Max(640, $workingArea.Width - 40))
$initialHeight = [Math]::Min(588, [Math]::Max(520, $workingArea.Height))
$script:MainForm.Size = [System.Drawing.Size]::new($initialWidth, $initialHeight)
$script:MainForm.MinimumSize = [System.Drawing.Size]::new([Math]::Min(1100, $initialWidth), 520)
$script:MainForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$script:MainForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
$script:MainForm.StartPosition = 'CenterScreen'
$script:MainForm.BackColor = Get-UiColor $script:Palette.Background
$script:MainForm.Font = [System.Drawing.Font]::new('Segoe UI', 10)
if (Test-Path $script:IconPath) { try { $script:MainForm.Icon = [System.Drawing.Icon]::new($script:IconPath) } catch {} }

$split = [System.Windows.Forms.SplitContainer]::new()
$split.Size = [System.Drawing.Size]::new($initialWidth, $initialHeight)
$split.Dock = 'Fill'; $split.SplitterDistance = 380; $split.FixedPanel = 'Panel1'; $split.IsSplitterFixed = $true
$split.BackColor = Get-UiColor $script:Palette.Background
$script:MainForm.Controls.Add($split)

$left = $split.Panel1
$left.BackColor = Get-UiColor '#171A21'
$logo = [System.Windows.Forms.PictureBox]::new(); $logo.Width = 50; $logo.Height = 50
$logo.SizeMode = 'CenterImage'; $logo.Top = 12; $logo.Left = 12
if (Test-Path $script:IconPath) {
    try {
        $logoIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($script:IconPath)
        if ($null -ne $logoIcon) { $logo.Image = $logoIcon.ToBitmap() }
    } catch {}
}
$left.Controls.Add($logo)
$listTitle = [System.Windows.Forms.Label]::new(); $listTitle.Text = 'Scripts List:'; $listTitle.Left = 75
$listTitle.Top = 18; $listTitle.Width = 275; $listTitle.Height = 38
$listTitle.ForeColor = Get-UiColor $script:Palette.Gold
$listTitle.Font = [System.Drawing.Font]::new('Segoe UI', 19, [System.Drawing.FontStyle]::Bold)
$left.Controls.Add($listTitle)
$script:ScriptList = [System.Windows.Forms.ListBox]::new()
$script:ScriptList.Left = 12; $script:ScriptList.Top = 75; $script:ScriptList.Width = 350
$script:ScriptList.Anchor = 'Top,Left,Right'; $script:ScriptList.BackColor = Get-UiColor '#202530'
$script:ScriptList.ForeColor = [System.Drawing.Color]::White
$script:ScriptList.Font = [System.Drawing.Font]::new('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$script:ScriptList.IntegralHeight = $false; $script:ScriptList.SelectionMode = 'One'
$script:ScriptList.DrawMode = 'OwnerDrawFixed'
$script:ScriptList.ItemHeight = 28
$script:ScriptList.BorderStyle = 'None'
$left.Controls.Add($script:ScriptList)
$script:DescriptionLabel = [System.Windows.Forms.RichTextBox]::new()
$script:DescriptionLabel.Left = 12; $script:DescriptionLabel.Width = 350; $script:DescriptionLabel.Height = 116
$script:DescriptionLabel.Anchor = 'Bottom,Left,Right'; $script:DescriptionLabel.Top = 0
$script:DescriptionLabel.BackColor = Get-UiColor '#242B38'
$script:DescriptionLabel.ForeColor = [System.Drawing.Color]::White
$script:DescriptionLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:DescriptionLabel.Padding = [System.Windows.Forms.Padding]::new(8)
$script:DescriptionLabel.Font = [System.Drawing.Font]::new('Segoe UI Emoji', 12)
$script:DescriptionLabel.ReadOnly = $true
$script:DescriptionLabel.DetectUrls = $false
$script:DescriptionLabel.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::None
$script:DescriptionLabel.WordWrap = $true
$script:DescriptionLabel.TabStop = $false
$left.Controls.Add($script:DescriptionLabel)
$brand = [System.Windows.Forms.Label]::new()
$script:BrandLabel = $brand
$brand.Text = '𝘼𝙪𝙩𝙤𝙋𝙞𝙡𝙤𝙩 𝙎𝙮𝙨𝙩𝙚𝙢'; $brand.Left = 10; $brand.Width = 350; $brand.Height = 40
$brand.Anchor = 'Bottom,Left,Right'; $brand.ForeColor = Get-UiColor '#FFD700'
$brand.Font = [System.Drawing.Font]::new('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$brand.TextAlign = 'MiddleCenter'; $left.Controls.Add($brand)
$script:BrandLabel = $brand
$script:ScriptList.Name = 'ScriptList'
$script:DescriptionLabel.Name = 'ScriptDescription'
$brand.Name = 'AutoPilotBrand'
$left.Add_Resize({
    param($sender, $eventArgs)
    $list = $sender.Controls['ScriptList']
    $description = $sender.Controls['ScriptDescription']
    $brandLabel = $sender.Controls['AutoPilotBrand']
    if ($null -ne $list) { $list.Height = [Math]::Max(120, $sender.ClientSize.Height - 285) }
    if ($null -ne $description) { $description.Top = $sender.ClientSize.Height - 166 }
    if ($null -ne $brandLabel) { $brandLabel.Top = $sender.ClientSize.Height - 45 }
})
$script:ScriptList.Height = [Math]::Max(120, $left.ClientSize.Height - 285)
$script:DescriptionLabel.Top = $left.ClientSize.Height - 166
$brand.Top = $left.ClientSize.Height - 45

$right = $split.Panel2
$right.BackColor = Get-UiColor $script:Palette.Background
$headers = [System.Windows.Forms.Panel]::new(); $headers.Height = 45; $headers.Width = 1260
$headers.BackColor = Get-UiColor $script:Palette.Background
$script:HeaderPanel = $headers
$headerSpecs = @(
    @{X=0;W=60;T='🆔';C='#FBBF24'},
    @{X=60;W=110;T='⚙️ Cmd';C='#38BDF8'}
    @{X=180;W=210;T='🕓 Time (HH:MM:SS)';C='#34D399'},
    @{X=400;W=135;T='🌀 Del/Sec';C='#F472B6'},
    @{X=545;W=140;T='🔂 Rep/Min';C='#A78BFA'},
    @{X=690;W=270;T='📆 Date (YY:MM:DD)';C='#60A5FA'},
    @{X=955;W=140;T='🔃 Mode';C='#2DD4BF'},
    @{X=1103;W=150;T='🗑️ Delete';C='#F87171'}
)
foreach ($spec in $headerSpecs) {
    $h = [System.Windows.Forms.Label]::new()
    $h.Left = $spec.X; $h.Width = $spec.W; $h.Height = 40; $h.Text = $spec.T
    $h.ForeColor = Get-UiColor $spec.C; $h.TextAlign = 'MiddleCenter'
    $h.Font = [System.Drawing.Font]::new('Segoe UI Emoji', 14, [System.Drawing.FontStyle]::Bold)
    [void]$headers.Controls.Add($h)
}
$script:RowScroll = [System.Windows.Forms.Panel]::new()
$script:RowScroll.Dock = 'Fill'; $script:RowScroll.AutoScroll = $true
$script:RowScroll.BackColor = Get-UiColor $script:Palette.Background
$right.Controls.Add($script:RowScroll)
$script:ScrollContentPanel = [System.Windows.Forms.Panel]::new()
$script:ScrollContentPanel.Left = 0; $script:ScrollContentPanel.Top = 0
$script:ScrollContentPanel.Width = 1260; $script:ScrollContentPanel.Height = 46
$script:ScrollContentPanel.BackColor = Get-UiColor $script:Palette.Background
$script:RowScroll.Controls.Add($script:ScrollContentPanel)
$script:ScrollContentPanel.Controls.Add($headers)
$rowsPanel = [System.Windows.Forms.Panel]::new()
$rowsPanel.Left = 0; $rowsPanel.Top = 50; $rowsPanel.Width = 1260
$rowsPanel.BackColor = Get-UiColor $script:Palette.Background
$script:ScrollContentPanel.Controls.Add($rowsPanel)
$script:UiState.RowsPanel = $rowsPanel
$script:RowScroll.Add_Resize({
    param($sender, $eventArgs)
    if ($null -eq $script:UiState.RowsPanel -or $script:UiState.RowsPanel.IsDisposed -or
        $null -eq $script:ScrollContentPanel -or $script:ScrollContentPanel.IsDisposed) { return }
    $targetWidth = [Math]::Max(1260, $sender.ClientSize.Width)
    $script:ScrollContentPanel.Width = $targetWidth
    $script:HeaderPanel.Width = $targetWidth
    $script:UiState.RowsPanel.Width = $targetWidth
    foreach ($row in $script:UiState.Rows) {
        if ($null -ne $row.Panel -and -not $row.Panel.IsDisposed) {
            $row.Panel.Width = $targetWidth
        }
    }
    $script:RowScroll.PerformLayout()
    Update-RowNumbers
}.GetNewClosure())

$footer = [System.Windows.Forms.Panel]::new(); $footer.Dock = 'Bottom'; $footer.Height = 132
$footer.BackColor = Get-UiColor '#252B37'
$right.Controls.Add($footer)
$buttonPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
$buttonPanel.Height = 50; $buttonPanel.Width = 860; $buttonPanel.FlowDirection = 'LeftToRight'
$buttonPanel.Name = 'MainButtons'
$buttonPanel.WrapContents = $false; $buttonPanel.AutoSize = $false
$buttonPanel.Padding = [System.Windows.Forms.Padding]::new(5, 6, 5, 0)
$buttonPanel.BackColor = Get-UiColor '#252B37'
$footer.Controls.Add($buttonPanel)
$script:AddButton = New-UiButton '✔ Add Row' '#1E90FF'; $script:AddButton.Width = 130; $script:AddButton.Enabled = $false
$script:SaveButton = New-UiButton '💾 Save Config' '#228B22'; $script:SaveButton.Width = 150; $script:SaveButton.Enabled = $false
$script:DefaultButton = New-UiButton '☑ Default' '#B8860B'; $script:DefaultButton.Width = 125; $script:DefaultButton.Enabled = $false
$listButton = New-UiButton '📋 List All' '#1E90FF'; $listButton.Width = 120
$resetButton = New-UiButton '❌ Reset All' '#B22222'; $resetButton.Width = 130
$recoveryButton = New-UiButton '🛟 Recovery' '#6A5ACD'; $recoveryButton.Width = 135
$buttonPanel.Controls.AddRange(@($script:AddButton, $script:SaveButton, $script:DefaultButton, $listButton, $resetButton, $recoveryButton))
$buttonPanel.Top = 34
$script:StatusLabel = [System.Windows.Forms.Label]::new()
$script:StatusLabel.Name = 'MainStatus'
$script:StatusLabel.Left = 0; $script:StatusLabel.Top = 3; $script:StatusLabel.Width = $footer.ClientSize.Width
$script:StatusLabel.Anchor = 'Top,Left,Right'; $script:StatusLabel.Height = 26; $script:StatusLabel.TextAlign = 'MiddleCenter'
$script:StatusLabel.BackColor = Get-UiColor '#252B37'
$script:StatusLabel.Font = [System.Drawing.Font]::new('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$script:StatusLabel.Visible = $false; $footer.Controls.Add($script:StatusLabel)
$footerText = [System.Windows.Forms.Label]::new()
$footerText.Dock = 'Bottom'; $footerText.Height = 31; $footerText.TextAlign = 'MiddleCenter'
$footerText.BackColor = Get-UiColor '#252B37'
$footerText.ForeColor = Get-UiColor '#AAB4C5'; $footerText.Font = [System.Drawing.Font]::new('Segoe UI', 9)
$footerText.Text = 'You can add up to 35 rows. Save Config and Default are used separately for each script.'
$footer.Controls.Add($footerText)
$footer.Add_Resize({
    param($sender, $eventArgs)
    $status = $sender.Controls['MainStatus']
    $buttons = $sender.Controls['MainButtons']
    if ($null -ne $status) { $status.Width = $sender.ClientSize.Width }
    if ($null -ne $buttons) { $buttons.Left = [Math]::Max(0, [int](($sender.ClientSize.Width - $buttons.Width) / 2)) }
})
$buttonPanel.Left = [Math]::Max(0, [int](($footer.ClientSize.Width - $buttonPanel.Width) / 2))

$script:StatusTimer = [System.Windows.Forms.Timer]::new()
$script:StatusTimer.Interval = 2000
$script:StatusTimer.Add_Tick({ $script:StatusTimer.Stop(); $script:StatusLabel.Visible = $false })
$script:SelectStatusTimer = [System.Windows.Forms.Timer]::new()
$script:SelectStatusTimer.Interval = 3000
$script:SelectStatusTimer.Add_Tick({
    $script:SelectStatusTimer.Stop()
    Show-Status '⚠️ Select a SCRIPT first, then edit selected SCRIPT!' '#FFD700' 0
})
$script:AddButton.Add_Click({
    try {
        if ($null -eq $script:CurrentScriptIndex) { throw 'Select a script before adding a row.' }
        $beforeCount = $script:UiState.Rows.Count
        [void](New-ScriptRow)
        if ($script:UiState.Rows.Count -le $beforeCount) { return }
        $newRow = $script:UiState.Rows[$script:UiState.Rows.Count - 1]
        Update-RowNumbers
        $script:RowScroll.ScrollControlIntoView($newRow.Panel)
        Set-Dirty $true
        Show-Status '✔ Row added' '#1E90FF' 1500
    } catch {
        Show-Error 'Add row failed' $_.Exception.Message
    }
})
$script:SaveButton.Add_Click({ Save-ConfigWithStatus })
$script:DefaultButton.Add_Click({ Reset-CurrentScript })
$listButton.Add_Click({ Open-ScriptsTable })
$resetButton.Add_Click({ Reset-AllScripts })
$recoveryButton.Add_Click({ Open-RecoveryWindow })
$script:ScriptList.Add_SelectedIndexChanged({
    if ($script:ScriptList.SelectedIndex -ge 0) { Load-Script $script:ScriptList.SelectedIndex }
})
Show-Status '⚠ Select a SCRIPT first, then edit selected SCRIPT!' '#FFD700' 0

$i = 1
foreach ($item in (Get-Scripts)) {
    [void]$script:ScriptList.Items.Add("$i. $(Get-ScriptDisplayName $item)")
    $script:ScriptList.DrawMode = 'OwnerDrawFixed'
    $i++
}
$script:ScriptList.ItemHeight = 26
$script:ScriptList.Add_DrawItem({
    param($sender, $eventArgs)
    if ($eventArgs.Index -lt 0) { return }
    $selected = ($eventArgs.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    if ($selected) {
        $backColor = Get-UiColor '#D9A928'
        $textColor = Get-UiColor '#10141C'
    } else {
        if (-not $script:ScriptColors.ContainsKey($eventArgs.Index)) {
            $script:ScriptColors[$eventArgs.Index] = [System.Drawing.Color]::FromArgb(
                (Get-Random -Minimum 145 -Maximum 225),
                (Get-Random -Minimum 155 -Maximum 230),
                (Get-Random -Minimum 175 -Maximum 245)
            )
        }
        $backColor = $sender.BackColor
        $textColor = $script:ScriptColors[$eventArgs.Index]
    }
    $backgroundBrush = [System.Drawing.SolidBrush]::new($backColor)
    $eventArgs.Graphics.FillRectangle($backgroundBrush, $eventArgs.Bounds)
    $backgroundBrush.Dispose()
    $brush = [System.Drawing.SolidBrush]::new($textColor)
    $bounds = $eventArgs.Bounds
    $layout = [System.Drawing.RectangleF]::new(
        [single]$bounds.X,
        [single]$bounds.Y,
        [single]$bounds.Width,
        [single]$bounds.Height
    )
    $eventArgs.Graphics.DrawString([string]$sender.Items[$eventArgs.Index], $sender.Font, $brush, $layout)
    $brush.Dispose()
    if ($selected) { $eventArgs.DrawFocusRectangle() }
})

$brandTimer = [System.Windows.Forms.Timer]::new()
$brandTimer.Interval = 3000
$brandTimer.Add_Tick({
    $script:BrandLabel.ForeColor = [System.Drawing.Color]::FromArgb(
        (Get-Random -Minimum 50 -Maximum 256),
        (Get-Random -Minimum 50 -Maximum 256),
        (Get-Random -Minimum 50 -Maximum 256)
    )
}.GetNewClosure())
$brandTimer.Start()

$script:MainForm.Add_FormClosing({
    param($sender, $eventArgs)
    if (-not $script:ConfigDirty) { return }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        'You have unsaved changes.' + [Environment]::NewLine + 'Do you want to save before exiting?',
        'Unsaved Changes', 'YesNoCancel', 'Question'
    )
    if ($answer -eq [System.Windows.Forms.DialogResult]::Cancel) {
        $eventArgs.Cancel = $true
    } elseif ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            if ($null -ne $script:CurrentScriptIndex) { Save-CurrentScript }
            Save-Json
        } catch {
            Show-Error 'Save failed' $_.Exception.Message
            $eventArgs.Cancel = $true
        }
    }
})

[void][System.Windows.Forms.Application]::Run($script:MainForm)

############################################################################################################### End Scripts Editor.