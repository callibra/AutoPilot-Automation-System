$global:CurrentStationIndex = 0
$global:VLCProcess = $null

# --- VLC radio stations
$vlcPath = "C:\Program Files\VideoLAN\VLC\vlc.exe"

# Log VLC configuration warnings without stopping AutoPilot
function Write-VlcConfigWarning {
    param([string]$Message)
    Write-Host "VLC Configuration Warning: $Message" -ForegroundColor Yellow
	Start-Sleep -Seconds 3
    try {
        if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "VLC Configuration Warning: $Message"
            return
        }
    }
    catch {}
    # Fallback logging if Write-Log is unavailable
    try {
        if (-not [string]::IsNullOrWhiteSpace($Global:logPath)) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -LiteralPath $Global:logPath `
                -Value "$timestamp - VLC Configuration Warning: $Message" `
                -Encoding UTF8 -ErrorAction Stop
        }
    }
    catch {
        Write-Host "Could not write VLC warning to the log: $($_.Exception.Message)" -ForegroundColor DarkYellow
		Start-Sleep -Seconds 3
    }
}

# Load VLC radio stations from a separate JSON file
$vlcRadioSettingsPath = Join-Path -Path $PSScriptRoot -ChildPath "JSON\vlc_radio.json"
$global:RadioStations = @()

if (-not (Test-Path -LiteralPath $vlcRadioSettingsPath -PathType Leaf)) {
    Write-VlcConfigWarning "Configuration file not found: $vlcRadioSettingsPath. AutoPilot will continue."
}
else {
    try {
        $vlcRadioConfig = Get-Content -LiteralPath $vlcRadioSettingsPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        # Check JSON structure
        if (
            $null -eq $vlcRadioConfig -or
            $vlcRadioConfig -is [array] -or
            $vlcRadioConfig.PSObject.Properties.Name -notcontains "RADIO_STATIONS"
        ) {
            throw "Missing or invalid RADIO_STATIONS property in vlc_radio.json."
        }
        $configuredStations = @($vlcRadioConfig.RADIO_STATIONS)
        if (
            $null -eq $vlcRadioConfig.RADIO_STATIONS -or
            $configuredStations.Count -eq 0
        ) {
            throw "RADIO_STATIONS is empty."
        }
        # Keep only valid HTTP/HTTPS station URLs
        $validStations = @(
            foreach ($station in $configuredStations) {
                if (
                    $station -is [string] -and
                    $station.Trim() -match '^https?://\S+$'
                ) {
                    $station.Trim()
                }
            }
        )
        if ($validStations.Count -eq 0) {
            throw "RADIO_STATIONS contains no valid HTTP/HTTPS station URLs."
        }
        $global:RadioStations = @($validStations)
        # Report invalid entries while keeping valid stations
        $invalidCount = $configuredStations.Count - $validStations.Count
        if ($invalidCount -gt 0) {
            Write-VlcConfigWarning "$invalidCount invalid radio station entries were ignored. Valid stations loaded: $($global:RadioStations.Count)."
        }
    }
    catch {
        # Never stop AutoPilot because of a VLC configuration problem
        $global:RadioStations = @()
        Write-VlcConfigWarning "Failed to load VLC radio stations: $($_.Exception.Message) AutoPilot will continue."
    }
}

# ===================== VLC PLAYER =====================
# --- Check VLC radio configuration
function Get-VLCRadioConfigProblem {
    $path = $vlcRadioSettingsPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $PSScriptRoot "JSON\vlc_radio.json"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return "Configuration file not found: $path"
    }
    try {
        $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return "Configuration file is empty: $path"
        }
        $cfg = ConvertFrom-Json $json -ErrorAction Stop
        if ($null -eq $cfg) {
            return "JSON configuration is empty or invalid."
        }
        if ($cfg -is [array]) {
            return "Invalid JSON structure. Expected a JSON object containing RADIO_STATIONS."
        }
        if ($cfg.PSObject.Properties.Name -notcontains "RADIO_STATIONS") {
            return "RADIO_STATIONS property is missing in vlc_radio.json."
        }
        if ($null -eq $cfg.RADIO_STATIONS) {
            return "RADIO_STATIONS is null or empty."
        }
        $stations = @($cfg.RADIO_STATIONS)
        if ($stations.Count -eq 0) {
            return "RADIO_STATIONS contains no entries."
        }
        $valid = @($stations | Where-Object {
            $_ -is [string] -and
            -not [string]::IsNullOrWhiteSpace($_) -and
            $_.Trim() -match '^https?://\S+$'
        })
        if ($valid.Count -eq 0) {
            return "RADIO_STATIONS contains no valid HTTP/HTTPS URLs."
        }
        return "Valid stations exist in JSON, but the station list is not loaded into memory. Restart AutoPilot to reload the configuration."
    }
    catch {
        return "JSON file is unreadable or invalid: $($_.Exception.Message)"
    }
}

# --- Write VLC warnings to console and log
function Write-VLCRadioProblem {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
    try {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Message $Message
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Global:logPath)) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -LiteralPath $Global:logPath `
                -Value "$timestamp - $Message" -Encoding UTF8 -ErrorAction Stop
        }
    }
    catch {
        Write-Host "Could not write VLC warning to log: $($_.Exception.Message)" -ForegroundColor DarkYellow
		Start-Sleep -Seconds 3
    }
}

# --- Safely check loaded VLC radio stations
function Test-VLCRadioStations {
    $validStations = @(
        $global:RadioStations | Where-Object {
            $_ -is [string] -and
            -not [string]::IsNullOrWhiteSpace($_) -and
            $_.Trim() -match '^https?://\S+$'
        }
    )
    if ($validStations.Count -gt 0) {
        $global:RadioStations = @($validStations)
        if (
            $null -eq $global:CurrentStationIndex -or
            $global:CurrentStationIndex -lt 0 -or
            $global:CurrentStationIndex -ge $global:RadioStations.Count
        ) {
            $global:CurrentStationIndex = 0
        }
        $global:VlcRadioConfigProblem = $null
        return $true
    }
    $global:VlcRadioConfigProblem = Get-VLCRadioConfigProblem
    $status = "⚠️ VLC radio unavailable: $($global:VlcRadioConfigProblem)"
    Write-VLCRadioProblem -Message $status
    return $false
}

# --- VLC player functions
# Play
function Play-VLC {
    if (-not (Test-Path -LiteralPath $vlcPath -PathType Leaf)) {
        Write-Host "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe" -ForegroundColor Yellow
        return "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe"
    }
    if (-not (Test-VLCRadioStations)) {
        return "⚠️ VLC radio unavailable: $($global:VlcRadioConfigProblem)"
    }
    # Close any active VLC before starting a new stream
    Get-Process vlc -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $index = $global:CurrentStationIndex
    $url = $global:RadioStations[$index]
    $title = "RadioStation $($index + 1)"
    $path = $vlcRadioSettingsPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $PSScriptRoot "JSON\vlc_radio.json"
    }
    try {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $cfg = Get-Content -LiteralPath $path -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            $titles = @($cfg.RADIO_STATION_TITLES)
            if (
                $index -lt $titles.Count -and
                $titles[$index] -is [string] -and
                -not [string]::IsNullOrWhiteSpace($titles[$index])
            ) {
                $title = $titles[$index].Trim()
            }
        }
    }
    catch {}
    try {
        Start-Process -FilePath $vlcPath -ArgumentList $url -ErrorAction Stop
        Write-Host "🔊 Station started: $($index + 1). $title" -ForegroundColor Green
        return "🔊 Station started: $($index + 1). $title`n`n`🎵 Play List: /vlc_list"
    }
    catch {
        $status = "⚠️ Failed to start VLC: $($_.Exception.Message)"
        Write-VLCRadioProblem -Message $status
        return $status
    }
}
# Stop
function Stop-VLC {
    if (-not (Test-Path -LiteralPath $vlcPath -PathType Leaf)) {
        Write-Host "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe" -ForegroundColor Yellow
        return "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe"
    }
    Get-Process vlc -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
	Write-Host "VLC is ❌ closed." -ForegroundColor Yellow
    return "VLC is ❌ closed."
}
# Next
function Next-Station {
    if (-not (Test-Path -LiteralPath $vlcPath -PathType Leaf)) {
        Write-Host "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe" -ForegroundColor Yellow
        return "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe"
    }
    if (-not (Test-VLCRadioStations)) {
        return "⚠️ VLC radio unavailable: $($global:VlcRadioConfigProblem)"
    }
    $global:CurrentStationIndex = (
        $global:CurrentStationIndex + 1
    ) % $global:RadioStations.Count
    return Play-VLC
}
# Prev 
function Prev-Station {
    if (-not (Test-Path -LiteralPath $vlcPath -PathType Leaf)) {
        Write-Host "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe" -ForegroundColor Yellow
        return "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe"
    }
    if (-not (Test-VLCRadioStations)) {
        return "⚠️ VLC radio unavailable: $($global:VlcRadioConfigProblem)"
    }
    $global:CurrentStationIndex = $global:CurrentStationIndex - 1
    if ($global:CurrentStationIndex -lt 0) {
        $global:CurrentStationIndex = $global:RadioStations.Count - 1
    }
    return Play-VLC
}
# Build paginated VLC station list
function Get-VlcStationPageView {
    param([int]$Page = 1)
    $pageSize = 15
    $totalStations = @($global:RadioStations).Count
    $totalPages = [Math]::Max(
        1,
        [int][Math]::Ceiling($totalStations / [double]$pageSize)
    )
    $Page = [Math]::Max(1, [Math]::Min($Page, $totalPages))
    # Load station titles from JSON
    $titles = @()
    $path = $vlcRadioSettingsPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $PSScriptRoot "JSON\vlc_radio.json"
    }
    try {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $cfg = Get-Content -LiteralPath $path -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop

            $titles = @($cfg.RADIO_STATION_TITLES)
        }
    }
    catch {
        Write-VLCRadioProblem -Message "Could not load VLC station titles: $($_.Exception.Message)"
    }
    $startIndex = ($Page - 1) * $pageSize
    $endIndex = [Math]::Min(
        $startIndex + $pageSize - 1,
        $totalStations - 1
    )
    $keyboard = [System.Collections.Generic.List[object]]::new()
    # Station buttons: maximum 15 per page
    for ($i = $startIndex; $i -le $endIndex; $i++) {
        $title = "RadioStation $($i + 1)"
        if (
            $i -lt $titles.Count -and
            -not [string]::IsNullOrWhiteSpace([string]$titles[$i])
        ) {
            $title = ([string]$titles[$i]).Trim()
        }
        $button = @{
            text          = "▶ $($i + 1). $title"
            callback_data = "vlc_play:$i"
        }
        [void]$keyboard.Add([object[]]@($button))
    }
# Bottom navigation row - wider buttons
$navigationRow1 = @(
    @{
        text          = "⏪  PREV"
        callback_data = "vlc_page:prev:$Page"
    }
    @{
        text          = "NEXT  ⏩"
        callback_data = "vlc_page:next:$Page"
    }
)
$navigationRow2 = @(
    @{
        text          = "🟢  FIRST"
        callback_data = "vlc_page:home:$Page"
    }
    @{
        text          = "LAST  🔵"
        callback_data = "vlc_page:last:$Page"
    }
)
[void]$keyboard.Add([object[]]$navigationRow1)
[void]$keyboard.Add([object[]]$navigationRow2)
    $firstStation = if ($totalStations -gt 0) {
        $startIndex + 1
    } else {
        0
    }
    $lastStation = [Math]::Min(
        $startIndex + $pageSize,
        $totalStations
    )
    $text = @(
        "🎵 VLC Radio Stations"
        "━━━━━━━━━━━━━━━━━━━━"
        "📝 Stations: $firstStation-$lastStation of $totalStations"
        "📄 Page: $Page of $totalPages"
        ""
        "Select a station to play:"
    ) -join "`n"

    return @{
        Page           = $Page
        TotalPages     = $totalPages
        TotalStations  = $totalStations
        Text           = $text
        InlineKeyboard = $keyboard.ToArray()
    }
}
# Answer Telegram callback
function Send-VlcCallbackAnswer {
    param(
        [string]$CallbackQueryId,
        [string]$Text,
        [bool]$ShowAlert = $false
    )
    try {
        $body = @{
            callback_query_id = $CallbackQueryId
            text              = $Text
            show_alert        = $ShowAlert
        } | ConvertTo-Json -Compress
        Invoke-RestMethod `
            -Uri "https://api.telegram.org/bot$telegramBotToken/answerCallbackQuery" `
            -Method Post `
            -ContentType "application/json; charset=utf-8" `
            -Body $body `
            -ErrorAction Stop | Out-Null
    }
    catch {
        Write-VLCRadioProblem -Message "VLC callback response failed: $($_.Exception.Message)"
    }
}
# List VLC radio stations, 15 per page
function Vlc-List {
    param([string]$ChatId)
    if (-not (Test-VLCRadioStations)) {
        return "⚠️ VLC radio unavailable: $($global:VlcRadioConfigProblem)"
    }
    if ([string]::IsNullOrWhiteSpace($ChatId)) {
        return "⚠️ Could not display VLC list: ChatId is empty."
    }
    $view = Get-VlcStationPageView -Page 1
    $payload = @{
        chat_id      = $ChatId
        text         = $view.Text
        reply_markup = @{
            inline_keyboard = $view.InlineKeyboard
        }
    }
    try {
        $json = $payload | ConvertTo-Json -Depth 10 -Compress
        $result = Invoke-RestMethod `
            -Uri "https://api.telegram.org/bot$telegramBotToken/sendMessage" `
            -Method Post `
            -ContentType "application/json; charset=utf-8" `
            -Body $json `
            -ErrorAction Stop
        if (-not $result.ok) {
            return "⚠️ Telegram error: $($result.description)"
        }
        return $null
    }
    catch {
        Write-VLCRadioProblem -Message "Failed to send VLC station list: $($_.Exception.Message)"
        return "⚠️ Could not display VLC radio list: $($_.Exception.Message)"
    }
}
# Handle VLC station selection and pagination
function Invoke-VLCStationCallback {
    param([object]$CallbackQuery)
    $data = [string]$CallbackQuery.data
    $chatId = [string]$CallbackQuery.message.chat.id
    $messageId = $CallbackQuery.message.message_id
    $callbackId = $CallbackQuery.id
    # Ignore unrelated callback buttons
    if (
        $data -notmatch '^vlc_play:\d+$' -and
        $data -notmatch '^vlc_page:(home|prev|next|last):\d+$'
    ) {
        return
    }
    # Authorization: keep the existing owner check
    if (
        $OwnerId -and
        [string]$CallbackQuery.from.id -ne [string]$OwnerId
    ) {
        Send-VlcCallbackAnswer `
            -CallbackQueryId $callbackId `
            -Text "⛔ Not authorized." `
            -ShowAlert $true
        return
    }
    if (-not (Test-VLCRadioStations)) {
        Send-VlcCallbackAnswer `
            -CallbackQueryId $callbackId `
            -Text "⚠️ VLC radio unavailable." `
            -ShowAlert $true
        return
    }
    # ===================== PAGE NAVIGATION =====================
    if ($data -match '^vlc_page:(home|prev|next|last):(\d+)$') {
        $action = $Matches[1]
        $currentPage = [int]$Matches[2]
        $pageSize = 15
        $totalPages = [Math]::Max(
            1,
            [int][Math]::Ceiling(
                $global:RadioStations.Count / [double]$pageSize
            )
        )
        switch ($action) {
            'home' {
                $targetPage = 1
            }
            'prev' {
                $targetPage = [Math]::Max(1, $currentPage - 1)
            }
            'next' {
                $targetPage = [Math]::Min($totalPages, $currentPage + 1)
            }
            'last' {
                $targetPage = $totalPages
            }
        }
        # Do not edit the message if the page would stay the same
        if ($targetPage -eq $currentPage) {
            $status = "📄 Page $currentPage of $totalPages"
            if ($action -eq 'prev' -or $action -eq 'home') {
                $status = "📄 You are on the first page."
            }
            elseif ($action -eq 'next' -or $action -eq 'last') {
                $status = "📄 You are on the last page."
            }
            Send-VlcCallbackAnswer `
                -CallbackQueryId $callbackId `
                -Text $status
            return
        }
        $view = Get-VlcStationPageView -Page $targetPage
        $editPayload = @{
            chat_id      = $chatId
            message_id   = $messageId
            text         = $view.Text
            reply_markup = @{
                inline_keyboard = $view.InlineKeyboard
            }
        }
        try {
            $json = $editPayload | ConvertTo-Json -Depth 10 -Compress
            Invoke-RestMethod `
                -Uri "https://api.telegram.org/bot$telegramBotToken/editMessageText" `
                -Method Post `
                -ContentType "application/json; charset=utf-8" `
                -Body $json `
                -ErrorAction Stop | Out-Null
            Send-VlcCallbackAnswer `
                -CallbackQueryId $callbackId `
                -Text "📄 Page $targetPage of $totalPages"
        }
        catch {
            Write-VLCRadioProblem -Message "Could not change VLC list page: $($_.Exception.Message)"
            Send-VlcCallbackAnswer `
                -CallbackQueryId $callbackId `
                -Text "⚠️ Could not change page." `
                -ShowAlert $true
        }
        return
    }
    # ===================== PLAY SELECTED STATION =====================
    if ($data -match '^vlc_play:(\d+)$') {
        $index = [int]$Matches[1]
        if ($index -ge $global:RadioStations.Count) {
            Send-VlcCallbackAnswer `
                -CallbackQueryId $callbackId `
                -Text "⚠️ Invalid station selection." `
                -ShowAlert $true
            return
        }
        $global:CurrentStationIndex = $index
        $response = Play-VLC
        Send-VlcCallbackAnswer `
            -CallbackQueryId $callbackId `
            -Text "🔊 Starting station $($index + 1)"
        Send-TelegramMessage -message $response -chatId $chatId
    }
}
# Status
function VLC-Status {
    if (-not (Test-Path -LiteralPath $vlcPath -PathType Leaf)) {
        Write-Host "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe" -ForegroundColor Yellow
        return "ℹ️ VLC is Not Installed. 📥 Please install VLC to the default path: 📂 C:\Program Files\VideoLAN\VLC\vlc.exe"
    }
    if (-not (Test-VLCRadioStations)) {
        return "⚠️ VLC radio unavailable: $($global:VlcRadioConfigProblem)"
    }
    if (Get-Process vlc -ErrorAction SilentlyContinue) {
        $index = $global:CurrentStationIndex
        $title = "RadioStation $($index + 1)"
        $path = $vlcRadioSettingsPath
        if ([string]::IsNullOrWhiteSpace($path)) {
            $path = Join-Path $PSScriptRoot "JSON\vlc_radio.json"
        }
        try {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $cfg = Get-Content -LiteralPath $path -Raw -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop
                $titles = @($cfg.RADIO_STATION_TITLES)
                if (
                    $index -lt $titles.Count -and
                    $titles[$index] -is [string] -and
                    -not [string]::IsNullOrWhiteSpace($titles[$index])
                ) {
                    $title = $titles[$index].Trim()
                }
            }
        }
        catch {}
        return "VLC is ✅ running. 🔊 Current station: $($index + 1). $title"
    }
    else {
        return "ℹ️ VLC is not active."
    }
}
#################### END VLC PLAYER ########################################
