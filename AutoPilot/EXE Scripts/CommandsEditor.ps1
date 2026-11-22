# requires -Version 5.1
# PS2EXE: Invoke-PS2EXE .\CommandsEditor.ps1 .\CommandsEditor.exe -noConsole -STA

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:AppRoot = if ($PSScriptRoot) { $PSScriptRoot } else { [AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\') }
$script:ConfigFile = Join-Path $script:AppRoot 'JSON\commands_edit.json'
$script:DefaultConfigFile = Join-Path $script:AppRoot 'JSON\commands_default.json'
$script:BackupDir = Join-Path $script:AppRoot 'JSON\Backups_Commands'
$script:IconPath = Join-Path $script:AppRoot 'media\commands.ico'
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
$script:CommandColors = @{}
$script:Config = $null
$script:CurrentCommandKey = $null
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

function Get-CommandKeys {
    return @($script:Config.AutoCommands.PSObject.Properties | ForEach-Object { $_.Name })
}

function Save-CurrentCommand {
    if ($null -eq $script:CurrentCommandKey) { return }
    $data = $script:Config.AutoCommands.($script:CurrentCommandKey)
    $typeWasScalar = $null -ne $data.PSObject.Properties['Type'] -and $data.Type -isnot [array]
    $times = [System.Collections.Generic.List[string]]::new()
    $repeats = [System.Collections.Generic.List[int]]::new()
    $types = [System.Collections.Generic.List[string]]::new()
    $days = [System.Collections.Generic.List[string]]::new()
    $modes = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $script:UiState.Rows) {
        $times.Add(('{0:D2}:{1:D2}:{2:D2}' -f [int]$row.Hour.Value, [int]$row.Minute.Value, [int]$row.Second.Value))
        $repeats.Add([int]$row.Repeat.Value)
        $types.Add([string]$row.Type.SelectedItem)
        if ($row.Type.SelectedItem -eq 'daily' -and $row.ModeValue -eq 'fixed') {
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
    Set-JsonProperty $data 'Times' @($times.ToArray())
    Set-JsonProperty $data 'RepeatIntervalMinutes' @($repeats.ToArray())
    $typeValues = @($types.ToArray())
    if ($typeWasScalar -and $typeValues.Count -gt 0 -and @($typeValues | Select-Object -Unique).Count -eq 1) {
        Set-JsonProperty $data 'Type' ([string]$typeValues[0])
    } else {
        Set-JsonProperty $data 'Type' $typeValues
    }
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
        if ($null -ne $script:CurrentCommandKey) {
            Save-CurrentCommand
            Save-Json
            Set-Dirty $false
            Show-Status '✔ Command configuration saved' '#32CD32' 3000
            [void][System.Windows.Forms.MessageBox]::Show("Config saved for $($script:CurrentCommandKey)", 'Saved', 'OK', 'Information')
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
        'You have unsaved changes for this command.' + [Environment]::NewLine + 'Do you want to save them?',
        'Unsaved Changes', 'YesNo', 'Question'
    )
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Save-CurrentCommand
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

function Get-TypeColor([string]$Type) {
    switch ($Type) {
        'daily' { return (Get-UiColor '#FFFFFF') }
        'weekly' { return (Get-UiColor '#E4E665') }
        'monthly' { return (Get-UiColor '#65E683') }
        'yearly' { return (Get-UiColor '#E38AD8') }
        default { return [System.Drawing.Color]::White }
    }
}

function Update-ModeState($Row) {
    $daily = $Row.Type.SelectedItem -eq 'daily'
    if (-not $daily) {
        $Row.ModeValue = 'loop'
        $Row.ModeButton.Text = '📆 Type'
        $Row.ModeButton.BackColor = Get-UiColor '#85E6DE'
        $Row.ModeButton.ForeColor = Get-UiColor '#E05E5E'
        $Row.ModeButton.FlatAppearance.MouseOverBackColor = Get-UiColor '#B5F1EC'
        $Row.ModeButton.FlatAppearance.MouseDownBackColor = Get-UiColor '#66CCC2'
        $Row.ModeButton.Enabled = $false
        $Row.Year.Enabled = $false
        $Row.Month.Enabled = $false
        $Row.Day.Enabled = $false
    } else {
        $Row.ModeButton.Enabled = $true
        if ($Row.ModeValue -eq 'fixed') {
            $Row.ModeButton.Text = '✔ Fixed'
            $Row.ModeButton.BackColor = Get-UiColor '#32CD32'
            $Row.ModeButton.ForeColor = [System.Drawing.Color]::White
            $Row.ModeButton.FlatAppearance.MouseOverBackColor = Get-UiColor '#59E879'
            $Row.ModeButton.FlatAppearance.MouseDownBackColor = Get-UiColor '#22A83C'
            $Row.Year.Enabled = $true
            $Row.Month.Enabled = $true
            $Row.Day.Enabled = $true
        } else {
            $Row.ModeValue = 'loop'
            $Row.ModeButton.Text = '🔄 Loop'
            $Row.ModeButton.BackColor = Get-UiColor '#FFD700'
            $Row.ModeButton.ForeColor = Get-UiColor '#0031FF'
            $Row.ModeButton.FlatAppearance.MouseOverBackColor = Get-UiColor '#FFE45C'
            $Row.ModeButton.FlatAppearance.MouseDownBackColor = Get-UiColor '#D9A900'
            $Row.Year.Enabled = $false
            $Row.Month.Enabled = $false
            $Row.Day.Enabled = $false
        }
    }
}

function New-EditorRow($CommandData = $null, [int]$Index = -1) {
    if ($script:UiState.Rows.Count -ge $script:MaxRows) {
        [void][System.Windows.Forms.MessageBox]::Show("You cannot add more than $($script:MaxRows) rows.", 'Max Rows', 'OK', 'Warning')
        return $null
    }

    $today = [datetime]::Today
    $hour = 0; $minute = 0; $second = 0; $repeat = 0; $type = 'daily'; $mode = 'loop'; $date = $today
    $originalDay = $today.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    if ($null -ne $CommandData) {
        $commandTimes = [array]$CommandData.Times
        if ($Index -lt 0 -or $Index -ge $commandTimes.Length) {
            throw "Time entry $Index is not available for the selected command."
        }
        $parts = ([string]$commandTimes[$Index]).Split(':')
        $hour = [int]$parts[0]; $minute = [int]$parts[1]; $second = [int]$parts[2]
        if ($Index -lt @($CommandData.RepeatIntervalMinutes).Count) { $repeat = [int]$CommandData.RepeatIntervalMinutes[$Index] }
        if ($CommandData.PSObject.Properties['Type']) {
            if ($CommandData.Type -is [array]) {
                if ($Index -lt $CommandData.Type.Count -and $CommandData.Type[$Index]) { $type = [string]$CommandData.Type[$Index] }
            } elseif ($CommandData.Type) {
                $type = [string]$CommandData.Type
            }
        }
        if ($CommandData.PSObject.Properties['Day'] -and $Index -lt @($CommandData.Day).Count -and $CommandData.Day[$Index]) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParseExact([string]$CommandData.Day[$Index], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                $date = $parsed
                $originalDay = [string]$CommandData.Day[$Index]
            }
        }
        if ($CommandData.PSObject.Properties['Mode'] -and $Index -lt @($CommandData.Mode).Count -and $CommandData.Mode[$Index]) {
            $mode = [string]$CommandData.Mode[$Index]
        }
    }

    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Left = 0; $panel.Height = 48; $panel.Width = 1100
    $panel.BackColor = Get-UiColor '#191C24'
    $label = [System.Windows.Forms.Label]::new()
    $label.Left = 4; $label.Top = 11; $label.Width = 50; $label.Height = 26
    $label.Text = '{0}.' -f ($script:UiState.Rows.Count + 1)
    $label.TextAlign = 'MiddleCenter'; $label.ForeColor = Get-UiColor $script:Palette.Gold
    $label.Font = [System.Drawing.Font]::new('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    [void]$panel.Controls.Add($label)

    $hourBox = [System.Windows.Forms.NumericUpDown]::new()
    $hourBox.Left = 70; $hourBox.Top = 8; $hourBox.Width = 55; $hourBox.Minimum = 0; $hourBox.Maximum = 23; $hourBox.Value = $hour; $hourBox.ReadOnly = $true
    $minuteBox = [System.Windows.Forms.NumericUpDown]::new()
    $minuteBox.Left = 145; $minuteBox.Top = 8; $minuteBox.Width = 55; $minuteBox.Minimum = 0; $minuteBox.Maximum = 59; $minuteBox.Value = $minute; $minuteBox.ReadOnly = $true
    $secondBox = [System.Windows.Forms.NumericUpDown]::new()
    $secondBox.Left = 220; $secondBox.Top = 8; $secondBox.Width = 55; $secondBox.Minimum = 0; $secondBox.Maximum = 59; $secondBox.Value = $second; $secondBox.ReadOnly = $true
    foreach ($box in @($hourBox, $minuteBox, $secondBox)) {
        $box.BackColor = Get-UiColor '#1E1E1E'; $box.ForeColor = [System.Drawing.Color]::White
        $box.Font = [System.Drawing.Font]::new('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
        $box.TextAlign = 'Center'
        [void]$panel.Controls.Add($box)
    }
    foreach ($separator in @(@{X=128;Text=':'}, @{X=203;Text=':'})) {
        $sep = [System.Windows.Forms.Label]::new()
        $sep.Left = $separator.X; $sep.Top = 10; $sep.Width = 15; $sep.Text = $separator.Text
        $sep.ForeColor = [System.Drawing.Color]::White; $sep.Font = [System.Drawing.Font]::new('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        [void]$panel.Controls.Add($sep)
    }
    $repeatBox = [System.Windows.Forms.NumericUpDown]::new()
    $repeatBox.Left = 300; $repeatBox.Top = 7; $repeatBox.Width = 85; $repeatBox.Height = 34; $repeatBox.AutoSize = $false
    $repeatBox.Minimum = 0; $repeatBox.Maximum = 999; $repeatBox.Value = [Math]::Min(999, [Math]::Max(0, $repeat)); $repeatBox.ReadOnly = $true
    $repeatBox.BackColor = Get-UiColor '#1E1E1E'; $repeatBox.ForeColor = [System.Drawing.Color]::White
    $repeatBox.Font = [System.Drawing.Font]::new('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $repeatBox.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
    [void]$panel.Controls.Add($repeatBox)

    $typeBox = [System.Windows.Forms.ComboBox]::new()
    $typeBox.Left = 410; $typeBox.Top = 5; $typeBox.Width = 135; $typeBox.Height = 38
    $typeBox.DropDownStyle = 'DropDownList'
    [void]$typeBox.Items.AddRange(@('daily', 'weekly', 'monthly', 'yearly'))
    if ($type -notin @('daily', 'weekly', 'monthly', 'yearly')) { $type = 'daily' }
    $typeBox.SelectedItem = $type
    $typeBox.DrawMode = 'OwnerDrawFixed'
    $typeBox.ItemHeight = 28
    $typeBox.BackColor = Get-UiColor '#252A34'
    $typeBox.ForeColor = Get-TypeColor $type
    $typeBox.Font = [System.Drawing.Font]::new('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    [void]$panel.Controls.Add($typeBox)

    $yearBox = [System.Windows.Forms.NumericUpDown]::new()
    $yearBox.Left = 570; $yearBox.Top = 8; $yearBox.Width = 70
    $yearBox.Minimum = 1; $yearBox.Maximum = 9999
    $yearBox.Value = $date.Year
    $yearBox.ReadOnly = $true
    $monthBox = [System.Windows.Forms.NumericUpDown]::new()
    $monthBox.Left = 658; $monthBox.Top = 8; $monthBox.Width = 55
    $monthBox.Minimum = 1; $monthBox.Maximum = 12
    $monthBox.Value = $date.Month
    $monthBox.ReadOnly = $true
    $dayBox = [System.Windows.Forms.NumericUpDown]::new()
    $dayBox.Left = 731; $dayBox.Top = 8; $dayBox.Width = 55
    $dayBox.Minimum = 1
    $dayBox.Maximum = 31
    $dayBox.Value = $date.Day
    $dayBox.ReadOnly = $true
    foreach ($box in @($yearBox, $monthBox, $dayBox)) {
        $box.BackColor = Get-UiColor '#1E1E1E'
        $box.ForeColor = [System.Drawing.Color]::White
        $box.Font = [System.Drawing.Font]::new('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
        $box.TextAlign = 'Center'
        [void]$panel.Controls.Add($box)
    }
    foreach ($separator in @(@{X=643;Text='-'}, @{X=716;Text='-'})) {
        $sep = [System.Windows.Forms.Label]::new()
        $sep.Left = $separator.X; $sep.Top = 10; $sep.Width = 14; $sep.Text = $separator.Text
        $sep.ForeColor = [System.Drawing.Color]::White
        $sep.Font = [System.Drawing.Font]::new('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        [void]$panel.Controls.Add($sep)
    }

    $modeButton = New-UiButton '🔄 Loop' '#D6A500' '#101827'
    $modeButton.Font = [System.Drawing.Font]::new('Segoe UI Emoji', 13, [System.Drawing.FontStyle]::Bold)
    $modeButton.Left = 805; $modeButton.Top = 6; $modeButton.Width = 115
    [void]$panel.Controls.Add($modeButton)
    $deleteButton = New-UiButton '🗑 Delete' '#9E3447'
    $deleteButton.Font = [System.Drawing.Font]::new('Segoe UI Emoji', 11, [System.Drawing.FontStyle]::Bold)
    $deleteButton.FlatAppearance.MouseOverBackColor = Get-UiColor '#C64B60'
    $deleteButton.FlatAppearance.MouseDownBackColor = Get-UiColor '#7E2536'
    $deleteButton.Left = 945; $deleteButton.Top = 6; $deleteButton.Width = 120
    [void]$panel.Controls.Add($deleteButton)

    foreach ($spinner in @($hourBox, $minuteBox, $secondBox, $repeatBox, $yearBox, $monthBox, $dayBox)) {
        Add-WhiteSpinnerArrows $spinner $panel -ButtonStyle
    }

    $row = @{
        Panel=$panel; Number=$label; Hour=$hourBox; Minute=$minuteBox; Second=$secondBox
        Repeat=$repeatBox; Type=$typeBox; Year=$yearBox; Month=$monthBox; Day=$dayBox
        ModeButton=$modeButton; ModeValue=$mode; OriginalDay=$originalDay; DateModified=$false
    }
    $state = $script:UiState
    $modeButton.Add_Click({
        if ($row.ModeValue -eq 'loop') { $row.ModeValue = 'fixed' } else { $row.ModeValue = 'loop' }
        Update-ModeState $row
        if (-not $script:BuildingRows) { Set-Dirty $true }
    }.GetNewClosure())
    $typeBox.Add_SelectedIndexChanged({
        $typeBox.ForeColor = Get-TypeColor ([string]$typeBox.SelectedItem)
        Update-ModeState $row
        if (-not $script:BuildingRows) { Set-Dirty $true }
    }.GetNewClosure())
    $typeBox.Add_DrawItem({
        param($sender, $eventArgs)
        if ($eventArgs.Index -lt 0) { return }
        $eventArgs.DrawBackground()
        $typeName = [string]$sender.Items[$eventArgs.Index]
        $typeBrush = [System.Drawing.SolidBrush]::new((Get-TypeColor $typeName))
        $textBounds = [System.Drawing.RectangleF]::new(
            [single]$eventArgs.Bounds.X,
            [single]$eventArgs.Bounds.Y,
            [single]$eventArgs.Bounds.Width,
            [single]$eventArgs.Bounds.Height
        )
        $textFormat = [System.Drawing.StringFormat]::new()
        $textFormat.Alignment = [System.Drawing.StringAlignment]::Center
        $textFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
        try {
            $eventArgs.Graphics.DrawString($typeName, $sender.Font, $typeBrush, $textBounds, $textFormat)
        } finally {
            $textFormat.Dispose()
            $typeBrush.Dispose()
        }
        $eventArgs.DrawFocusRectangle()
    }.GetNewClosure())
    foreach ($control in @($hourBox, $minuteBox, $secondBox, $repeatBox, $yearBox, $monthBox, $dayBox)) {
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
    $yearBox.Add_ValueChanged($dateChanged)
    $monthBox.Add_ValueChanged($dateChanged)
    $dayBox.Add_ValueChanged($dateChanged)
    $capturedRow = $row
    $deleteButton.Add_Click({
        $deletedRow = $capturedRow
        try {
            if ($null -eq $deletedRow) { throw 'The selected row could not be identified.' }
            if ($null -eq $state.Rows -or $null -eq $state.RowsPanel) { throw 'The editor row collection is not available.' }
            $rowIndex = $state.Rows.IndexOf($deletedRow)
            if ($rowIndex -lt 0) { return }
            $state.Rows.RemoveAt($rowIndex)
            if ($null -ne $deletedRow.Panel -and -not $deletedRow.Panel.IsDisposed) {
                $state.RowsPanel.Controls.Remove($deletedRow.Panel)
                $deletedRow.Panel.Dispose()
            }
            Update-RowNumbers
            Set-Dirty $true
        } catch {
            Show-Error 'Delete failed' $_.Exception.Message
        }
    }.GetNewClosure())
    $toolTip = [System.Windows.Forms.ToolTip]::new()
    $typeBox.Add_MouseHover({
        $tip = switch ([string]$row.Type.SelectedItem) {
            'daily' { 'Daily → executes every day (Fixed works only when selected)' }
            'weekly' { 'Weekly → executes on Sunday (Default LOOP)' }
            'monthly' { 'Monthly → executes on last day of month' }
            'yearly' { 'Yearly → executes on last day of year' }
            default { '' }
        }
        $toolTip.SetToolTip($typeBox, $tip)
    }.GetNewClosure())
    Update-ModeState $row
    $script:UiState.Rows.Add($row)
    [void]$script:UiState.RowsPanel.Controls.Add($panel)
    Update-RowNumbers
    return $row
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

function Load-Command([int]$Index) {
    $keys = Get-CommandKeys
    if ($Index -lt 0 -or $Index -ge $keys.Count) { return }
    if ($script:CurrentCommandKey -eq $keys[$Index]) { return }
    if (-not (Confirm-SaveIfDirty)) { return }

    $script:CurrentCommandKey = $keys[$Index]
    $script:PreviousSelectedIndex = $Index
    try {
        $script:BuildingRows = $true
        Clear-EditorRows
        $data = $script:Config.AutoCommands.($script:CurrentCommandKey)
        $times = [array]$data.Times
        for ($i = 0; $i -lt $times.Length; $i++) { [void](New-EditorRow $data $i) }
        Update-RowNumbers
    } catch {
        $script:BuildingRows = $false
        Show-Error 'Load command failed' $_.Exception.Message
        return
    }
    $script:BuildingRows = $false
    $display = $script:CurrentCommandKey.TrimStart('/')
    $description = 'No description available.'
    if ($data.PSObject.Properties['Description'] -and $data.Description) { $description = [string]$data.Description }
    Set-CommandDescription $display $description
    $script:DescriptionLabel.Visible = $true
    Set-Dirty $false
    $script:StatusLabel.Visible = $false
    $script:AddButton.Enabled = $true
    $script:DefaultButton.Enabled = $true
    $script:SaveButton.Enabled = $false
    try { $script:RowScroll.VerticalScroll.Value = 0 } catch {}
}

function Reset-CurrentCommand {
    if ($null -eq $script:CurrentCommandKey) { return }
    if ([System.Windows.Forms.MessageBox]::Show('Are you sure?' + [Environment]::NewLine + 'Only the selected command will be reset.', 'Reset to Default', 'YesNo', 'Question') -ne 'Yes') { return }
    if (-not (Test-Path -LiteralPath $script:DefaultConfigFile)) {
        Show-Error 'Missing default file' "commands_default.json not found!`r`nPath:`r`n$script:DefaultConfigFile"
        return
    }
    try {
        $defaults = Get-Content -LiteralPath $script:DefaultConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $defaults.AutoCommands) { throw "The 'AutoCommands' section is missing from commands_default.json." }
        $defaultProperty = $defaults.AutoCommands.PSObject.Properties[$script:CurrentCommandKey]
        if ($null -eq $defaultProperty) { throw "Command '$($script:CurrentCommandKey)' is not present in commands_default.json." }
        $defaultJson = ConvertTo-Json -InputObject $defaultProperty.Value -Depth 100
        $defaultData = ConvertFrom-Json -InputObject $defaultJson
        if ($null -eq $defaultData.Times) { throw "Default data for '$($script:CurrentCommandKey)' is missing the Times array." }
        Set-JsonProperty $script:Config.AutoCommands $script:CurrentCommandKey $defaultData
        $data = $script:Config.AutoCommands.($script:CurrentCommandKey)
        $times = [array]$data.Times
        Set-JsonProperty $data 'Times' $times
        Set-JsonProperty $data 'Mode' (@('loop') * $times.Length)
        try {
            $script:BuildingRows = $true
            Clear-EditorRows
            for ($i = 0; $i -lt $times.Length; $i++) { [void](New-EditorRow $data $i) }
            Update-RowNumbers
        } finally {
            $script:BuildingRows = $false
        }
        $display = $script:CurrentCommandKey.TrimStart('/')
        $description = if ($data.PSObject.Properties['Description'] -and $data.Description) { [string]$data.Description } else { 'No description available.' }
        Set-CommandDescription $display $description
        $script:DescriptionLabel.Visible = $true
        Save-Json
        Set-Dirty $false
        Show-Status '↺ Command reset to default & auto-saved' '#32CD32' 3000
    } catch {
        Show-Error 'Reset failed' $_.Exception.Message
    }
}

function Reset-AllCommands {
    $message = "⚠ This will ERASE ALL AutoCommands data!`r`n`r`nAll Times, Repeat, Type, Mode and Day values`r`nwill be cleared for EVERY command.`r`n`r`nDo you want to continue?"
    if ([System.Windows.Forms.MessageBox]::Show($message, 'RESET ALL COMMANDS', 'YesNo', 'Warning') -ne 'Yes') { return }
    foreach ($property in $script:Config.AutoCommands.PSObject.Properties) {
        Set-JsonProperty $property.Value 'Times' @()
        Set-JsonProperty $property.Value 'RepeatIntervalMinutes' @()
        Set-JsonProperty $property.Value 'Type' @()
        Set-JsonProperty $property.Value 'Mode' @()
        Set-JsonProperty $property.Value 'Day' @()
    }
    Clear-EditorRows
    $script:CurrentCommandKey = $null
    $script:PreviousSelectedIndex = -1
    $script:CommandList.ClearSelected()
    $script:DescriptionLabel.Text = ''
    $script:AddButton.Enabled = $false
    $script:DefaultButton.Enabled = $false
    try {
        Save-Json
        Set-Dirty $false
        Show-Status '⚠ ALL AutoCommands RESET & auto-saved' '#FF4500' 3000
        $script:SelectStatusTimer.Stop()
        $script:SelectStatusTimer.Start()
    } catch {
        Show-Error 'Reset failed' $_.Exception.Message
    }
}

function Get-PastDate([string]$Day, [string]$Time) {
    if (-not $Day -or -not $Time) { return $false }
    try {
        $value = [datetime]::ParseExact("$Day $Time", 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
        return ($value -lt [datetime]::Now)
    } catch { return $false }
}

function Open-CommandsTable {
    if ($script:TableForm -and -not $script:TableForm.IsDisposed) {
        $script:TableForm.Activate()
        return
    }
    $form = [System.Windows.Forms.Form]::new()
    $script:TableForm = $form
    $form.Text = 'Auto Commands Overview (Read Only)'
    $form.Size = [System.Drawing.Size]::new(1500, 800)
    $form.StartPosition = 'CenterParent'
    $form.BackColor = Get-UiColor $script:Palette.Background
    if (Test-Path $script:IconPath) { try { $form.Icon = [System.Drawing.Icon]::new($script:IconPath) } catch {} }
    $grid = [System.Windows.Forms.DataGridView]::new()
    $grid.Dock = 'Fill'; $grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false; $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'; $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false; $grid.BorderStyle = 'None'
    $grid.CellBorderStyle = 'SingleHorizontal'
    $grid.ColumnHeadersBorderStyle = 'None'
    $grid.AllowUserToResizeRows = $false
    $grid.AllowUserToResizeColumns = $true
    $grid.ScrollBars = 'Both'
    $grid.BackgroundColor = Get-UiColor $script:Palette.Background
    $grid.GridColor = Get-UiColor '#343C4A'; $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersDefaultCellStyle.BackColor = Get-UiColor $script:Palette.Background
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Gold
    $grid.ColumnHeadersDefaultCellStyle.Font = [System.Drawing.Font]::new('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
    $grid.ColumnHeadersDefaultCellStyle.Alignment = 'MiddleCenter'
    $grid.ColumnHeadersHeight = 48
    $grid.ColumnHeadersHeightSizeMode = 'DisableResizing'
    $grid.DefaultCellStyle.BackColor = Get-UiColor $script:Palette.Background
    $grid.DefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Text
    $grid.DefaultCellStyle.SelectionBackColor = Get-UiColor '#34445A'
    $grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $grid.DefaultCellStyle.Font = [System.Drawing.Font]::new('Segoe UI', 15)
    $grid.DefaultCellStyle.Alignment = 'MiddleCenter'
    $grid.DefaultCellStyle.Padding = [System.Windows.Forms.Padding]::new(8, 2, 8, 2)
    $grid.AlternatingRowsDefaultCellStyle.BackColor = Get-UiColor '#252B37'
    $grid.AlternatingRowsDefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Text
    $grid.RowHeadersDefaultCellStyle.BackColor = Get-UiColor $script:Palette.Background
    $grid.RowHeadersDefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Gold
    $grid.TabStop = $false
    $grid.RowTemplate.Height = 42
    $grid.RowTemplate.MinimumHeight = 42
    foreach ($name in @('⚙ Command', '🆔 Row', '🕓 Time', '🔂 Repeat', '🔀 Type', '🔃 Mode', '📆 Day')) {
        [void]$grid.Columns.Add($name, $name)
    }
    foreach ($property in $script:Config.AutoCommands.PSObject.Properties) {
        $name = $property.Name
        $data = $property.Value
        $times = @($data.Times)
        if ($times.Count -eq 0) {
            $idx = $grid.Rows.Add($name.TrimStart('/'), '-', '📂 No Data', '-', '-', '-', '-')
            $grid.Rows[$idx].DefaultCellStyle.BackColor = Get-UiColor $script:Palette.Panel
            $grid.Rows[$idx].DefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Muted
        } else {
            for ($i = 0; $i -lt $times.Count; $i++) {
                $repeat = if ($i -lt @($data.RepeatIntervalMinutes).Count) { $data.RepeatIntervalMinutes[$i] } else { '-' }
                $type = if ($i -lt @($data.Type).Count) { $data.Type[$i] } else { '-' }
                $day = if ($i -lt @($data.Day).Count) { $data.Day[$i] } else { '' }
                $mode = if ($i -lt @($data.Mode).Count) { $data.Mode[$i] } else { 'loop' }
                $idx = $grid.Rows.Add($name.TrimStart('/'), ($i + 1), $times[$i], $repeat, $type, $mode, $(if ($day) { $day } else { '-' }))
                if ($mode -eq 'fixed' -and (Get-PastDate ([string]$day) ([string]$times[$i]))) {
                    $grid.Rows[$idx].DefaultCellStyle.BackColor = Get-UiColor '#8B0000'
                    $grid.Rows[$idx].DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
                } elseif ($mode -eq 'fixed') {
                    $grid.Rows[$idx].DefaultCellStyle.BackColor = Get-UiColor '#2E8B57'
                    $grid.Rows[$idx].DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
                } else {
                    $grid.Rows[$idx].DefaultCellStyle.BackColor = Get-UiColor '#252B37'
                    $grid.Rows[$idx].DefaultCellStyle.ForeColor = Get-UiColor $script:Palette.Muted
                }
                $grid.Rows[$idx].DefaultCellStyle.SelectionBackColor = Get-UiColor '#34445A'
            }
        }
        $spacerIndex = $grid.Rows.Add('', '', '', '', '', '', '')
        $grid.Rows[$spacerIndex].Height = 14
        $grid.Rows[$spacerIndex].DefaultCellStyle.BackColor = Get-UiColor $script:Palette.Background
        $grid.Rows[$spacerIndex].DefaultCellStyle.SelectionBackColor = Get-UiColor $script:Palette.Background
        $grid.Rows[$spacerIndex].DefaultCellStyle.SelectionForeColor = Get-UiColor $script:Palette.Background
    }
    $form.Controls.Add($grid)
    $form.Add_FormClosed({ $script:TableForm = $null })
    [void]$form.ShowDialog($script:MainForm)
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
    $form.Text = 'Recovery - Commands Backups'; $form.Size = [System.Drawing.Size]::new(760, 540)
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
        Show-Error 'Backup' 'commands_edit.json was not found.'
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
    if ([System.Windows.Forms.MessageBox]::Show("Restore backup '$name'?`r`nThe current commands_edit.json will be OVERWRITTEN.", 'Restore Backup', 'YesNo', 'Warning') -ne 'Yes') { return }
    try {
        $restored = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $restored -or $null -eq $restored.AutoCommands) { throw "The 'AutoCommands' section is missing." }
        [System.IO.File]::WriteAllBytes($script:ConfigFile, [System.IO.File]::ReadAllBytes($Path))
        $script:Config = $restored
        $script:CommandList.Items.Clear()
        $script:CommandColors.Clear()
        $i = 1
        foreach ($key in (Get-CommandKeys)) {
            [void]$script:CommandList.Items.Add("$i. $($key.TrimStart('/'))")
            $i++
        }
        Clear-EditorRows
        $script:CurrentCommandKey = $null; $script:PreviousSelectedIndex = -1
        $script:DescriptionLabel.Text = ''
        Set-Dirty $false
        $script:AddButton.Enabled = $false; $script:DefaultButton.Enabled = $false; $script:SaveButton.Enabled = $false
        Show-Status '⚠️ Select a COMMAND first, then edit selected COMMAND!' '#FFD700' 0
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

try {
    if (-not (Test-Path -LiteralPath $script:ConfigFile)) { throw "commands_edit.json was not found:`r`n$script:ConfigFile" }
    $script:Config = Get-Content -LiteralPath $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $script:Config.AutoCommands) { throw "The 'AutoCommands' section is missing from commands_edit.json." }
} catch {
    Show-Error 'Configuration error' $_.Exception.Message
    exit 1
}

$script:MainForm = [System.Windows.Forms.Form]::new()
$script:MainForm.Text = 'Automation Commands Editor'
$workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$initialWidth = [Math]::Min(1535, [Math]::Max(1100, $workingArea.Width))
$initialHeight = [Math]::Min(588, [Math]::Max(520, $workingArea.Height))
$script:MainForm.Size = [System.Drawing.Size]::new($initialWidth, $initialHeight)
$script:MainForm.MinimumSize = [System.Drawing.Size]::new(1100, 520)
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
$listTitle = [System.Windows.Forms.Label]::new(); $listTitle.Text = 'Commands List:'; $listTitle.Left = 75
$listTitle.Top = 18; $listTitle.Width = 275; $listTitle.Height = 38
$listTitle.ForeColor = Get-UiColor $script:Palette.Gold
$listTitle.Font = [System.Drawing.Font]::new('Segoe UI', 19, [System.Drawing.FontStyle]::Bold)
$left.Controls.Add($listTitle)
$script:CommandList = [System.Windows.Forms.ListBox]::new()
$script:CommandList.Left = 12; $script:CommandList.Top = 75; $script:CommandList.Width = 350
$script:CommandList.Anchor = 'Top,Left,Right'; $script:CommandList.BackColor = Get-UiColor '#202530'
$script:CommandList.ForeColor = [System.Drawing.Color]::White
$script:CommandList.Font = [System.Drawing.Font]::new('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$script:CommandList.IntegralHeight = $false; $script:CommandList.SelectionMode = 'One'
$script:CommandList.DrawMode = 'OwnerDrawFixed'
$script:CommandList.ItemHeight = 28
$script:CommandList.BorderStyle = 'None'
$left.Controls.Add($script:CommandList)
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
$script:CommandList.Name = 'CommandList'
$script:DescriptionLabel.Name = 'CommandDescription'
$brand.Name = 'AutoPilotBrand'
$left.Add_Resize({
    param($sender, $eventArgs)
    $list = $sender.Controls['CommandList']
    $description = $sender.Controls['CommandDescription']
    $brandLabel = $sender.Controls['AutoPilotBrand']
    if ($null -ne $list) { $list.Height = [Math]::Max(120, $sender.ClientSize.Height - 285) }
    if ($null -ne $description) { $description.Top = $sender.ClientSize.Height - 166 }
    if ($null -ne $brandLabel) { $brandLabel.Top = $sender.ClientSize.Height - 45 }
})
$script:CommandList.Height = [Math]::Max(120, $left.ClientSize.Height - 285)
$script:DescriptionLabel.Top = $left.ClientSize.Height - 166
$brand.Top = $left.ClientSize.Height - 45

$right = $split.Panel2
$right.BackColor = Get-UiColor $script:Palette.Background
$headers = [System.Windows.Forms.Panel]::new(); $headers.Height = 45; $headers.Width = 1100
$headers.BackColor = Get-UiColor $script:Palette.Background
$script:HeaderPanel = $headers
$headerSpecs = @(
    @{X=0;W=60;T='🆔';C='#FBBF24'},
    @{X=60;W=215;T='🕓 Time (HH:MM:SS)';C='#34D399'},
    @{X=270;W=140;T='🔂 Rep/Min';C='#A78BFA'},
    @{X=400;W=135;T='🔀 Type';C='#22D3EE'},
    @{X=560;W=230;T='📆 Date (YY:MM:DD)';C='#60A5FA'},
    @{X=790;W=130;T='⏱️ Interval';C='#A3E635'}
    @{X=928;W=150;T='🗑️ Delete';C='#F87171'}
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
$script:ScrollContentPanel.Width = 1100; $script:ScrollContentPanel.Height = 46
$script:ScrollContentPanel.BackColor = Get-UiColor $script:Palette.Background
$script:RowScroll.Controls.Add($script:ScrollContentPanel)
$script:ScrollContentPanel.Controls.Add($headers)
$rowsPanel = [System.Windows.Forms.Panel]::new()
$rowsPanel.Left = 0; $rowsPanel.Top = 50; $rowsPanel.Width = 1100
$rowsPanel.BackColor = Get-UiColor $script:Palette.Background
$script:ScrollContentPanel.Controls.Add($rowsPanel)
$script:UiState.RowsPanel = $rowsPanel
$script:RowScroll.Add_Resize({
    param($sender, $eventArgs)
    if ($null -eq $script:UiState.RowsPanel -or $script:UiState.RowsPanel.IsDisposed -or
        $null -eq $script:ScrollContentPanel -or $script:ScrollContentPanel.IsDisposed) { return }
    $targetWidth = [Math]::Max(1100, $sender.ClientSize.Width)
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
$footerText.Text = 'You can add up to 35 rows. Save Config and Default USE for every COMMAND separately. Fixed USE only when Type Selection is *daily*.'
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
    Show-Status '⚠️ Select a COMMAND first, then edit selected COMMAND!' '#FFD700' 0
})
$script:AddButton.Add_Click({
    try {
        if ($null -eq $script:CurrentCommandKey) { throw 'Select a command before adding a row.' }
        $beforeCount = $script:UiState.Rows.Count
        [void](New-EditorRow)
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
$script:DefaultButton.Add_Click({ Reset-CurrentCommand })
$listButton.Add_Click({ Open-CommandsTable })
$resetButton.Add_Click({ Reset-AllCommands })
$recoveryButton.Add_Click({ Open-RecoveryWindow })
$script:CommandList.Add_SelectedIndexChanged({
    if ($script:CommandList.SelectedIndex -ge 0) { Load-Command $script:CommandList.SelectedIndex }
})
Show-Status '⚠ Select a COMMAND first, then edit selected COMMAND!' '#FFD700' 0

$i = 1
foreach ($key in (Get-CommandKeys)) {
    [void]$script:CommandList.Items.Add("$i. $($key.TrimStart('/'))")
    $script:CommandList.DrawMode = 'OwnerDrawFixed'
    $i++
}
$script:CommandList.ItemHeight = 26
$script:CommandList.Add_DrawItem({
    param($sender, $eventArgs)
    if ($eventArgs.Index -lt 0) { return }
    $selected = ($eventArgs.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    if ($selected) {
        $backColor = Get-UiColor '#D9A928'
        $textColor = Get-UiColor '#10141C'
    } else {
        if (-not $script:CommandColors.ContainsKey($eventArgs.Index)) {
            $script:CommandColors[$eventArgs.Index] = [System.Drawing.Color]::FromArgb(
                (Get-Random -Minimum 145 -Maximum 225),
                (Get-Random -Minimum 155 -Maximum 230),
                (Get-Random -Minimum 175 -Maximum 245)
            )
        }
        $backColor = $sender.BackColor
        $textColor = $script:CommandColors[$eventArgs.Index]
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
            if ($null -ne $script:CurrentCommandKey) { Save-CurrentCommand }
            Save-Json
        } catch {
            Show-Error 'Save failed' $_.Exception.Message
            $eventArgs.Cancel = $true
        }
    }
})

[void][System.Windows.Forms.Application]::Run($script:MainForm)

############################################################################################################### End Commands Editor.