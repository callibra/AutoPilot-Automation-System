# ============================================================
#  FileStorage.ps1 - standalone PowerShell implementation of the media bot.
#  Targets Windows PowerShell 5.1 and PowerShell 7+.
# ============================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# =============== Pomosni funkcii (ekvivalent na Python stdlib) ===============
# =============================================================================
function Format-Date([datetime]$dt, [string]$fmt) {
    return $dt.ToString($fmt, $script:Inv)
}

function Format-Size([double]$bytes) {
    if ($bytes -lt [math]::Pow(1024, 2)) {
        return ($bytes / 1024).ToString('F2', $script:Inv) + ' KB'
    }
    elseif ($bytes -lt [math]::Pow(1024, 3)) {
        return ($bytes / [math]::Pow(1024, 2)).ToString('F2', $script:Inv) + ' MB'
    }
    else {
        return ($bytes / [math]::Pow(1024, 3)).ToString('F2', $script:Inv) + ' GB'
    }
}

# Python: str(datetime.timedelta(seconds=N))
function Format-TimeDelta([long]$totalSeconds) {
    $days = [long][math]::Floor($totalSeconds / 86400)
    $rem = $totalSeconds - ($days * 86400)
    $h = [long][math]::Floor($rem / 3600)
    $m = [long][math]::Floor(($rem % 3600) / 60)
    $s = $rem % 60
    $t = "$($h):$($m.ToString('00')):$($s.ToString('00'))"
    if ($days -gt 0) {
        if ($days -eq 1) { return "1 day, $t" } else { return "$($days) days, $t" }
    }
    return $t
}

# Python: a // b
function FloorDiv([long]$a, [long]$b) {
    return [long][math]::Floor([double]$a / [double]$b)
}

function Test-StartsWith([string]$s, [string]$prefix) {
    return $s.StartsWith($prefix, [System.StringComparison]::Ordinal)
}

function Get-Ctx($ctx, [string]$key, $default) {
    if ($ctx.ContainsKey($key)) { return $ctx[$key] } else { return $default }
}

# Python: [f for f in os.listdir(folder) if os.path.isfile(...)]
function Get-FileNames([string]$folder_path) {
    $names = @()
    foreach ($p in [System.IO.Directory]::GetFiles($folder_path)) {
        $names += [System.IO.Path]::GetFileName($p)
    }
    return ,$names
}

# =============== JSON (ekvivalent na json.dumps / json.dump so ensure_ascii) ===============
# ===========================================================================================
function ConvertTo-JsonString([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        switch ($c) {
            34 { [void]$sb.Append('\"') }
            92 { [void]$sb.Append('\\') }
            10 { [void]$sb.Append('\n') }
            13 { [void]$sb.Append('\r') }
            9  { [void]$sb.Append('\t') }
            8  { [void]$sb.Append('\b') }
            12 { [void]$sb.Append('\f') }
            default {
                if ($c -lt 32 -or $c -gt 126) { [void]$sb.Append('\u' + $c.ToString('x4')) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function New-RawJson([string]$json) {
    return [pscustomobject]@{ RawJson = $json }
}

function ConvertTo-JsonText {
    param($Value, [int]$Indent = 0, [int]$Level = 0)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return (ConvertTo-JsonString $Value) }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }

    $nl = ''; $pad = ''; $padIn = ''; $kv = ':'
    if ($Indent -gt 0) {
        $nl = "`n"
        $pad = ' ' * ($Indent * $Level)
        $padIn = ' ' * ($Indent * ($Level + 1))
        $kv = ': '
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $plist = @($Value.PSObject.Properties)
        if ($plist.Count -eq 1 -and $plist[0].Name -ceq 'RawJson') { return [string]$plist[0].Value }
    }

    $items = New-Object System.Collections.Generic.List[string]
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($k in $Value.Keys) {
            $items.Add($padIn + (ConvertTo-JsonString ([string]$k)) + $kv + (ConvertTo-JsonText $Value[$k] $Indent ($Level + 1)))
        }
        if ($items.Count -eq 0) { return '{}' }
        return '{' + $nl + ($items -join (',' + $nl)) + $nl + $pad + '}'
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $Value.PSObject.Properties) {
            $items.Add($padIn + (ConvertTo-JsonString ([string]$p.Name)) + $kv + (ConvertTo-JsonText $p.Value $Indent ($Level + 1)))
        }
        if ($items.Count -eq 0) { return '{}' }
        return '{' + $nl + ($items -join (',' + $nl)) + $nl + $pad + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($v in $Value) {
            $items.Add($padIn + (ConvertTo-JsonText $v $Indent ($Level + 1)))
        }
        if ($items.Count -eq 0) { return '[]' }
        return '[' + $nl + ($items -join (',' + $nl)) + $nl + $pad + ']'
    }
    if ($Value -is [decimal] -or $Value.GetType().IsPrimitive) { return $Value.ToString($script:Inv) }
    return (ConvertTo-JsonString ([string]$Value))
}

# Inline keyboard (InlineKeyboardMarkup / InlineKeyboardButton)
function New-Btn([string]$text, [string]$callback_data) {
    return '{"text":' + (ConvertTo-JsonString $text) + ',"callback_data":' + (ConvertTo-JsonString $callback_data) + '}'
}
function New-UrlBtn([string]$text, $url) {
    if ($null -eq $url) { return '{"text":' + (ConvertTo-JsonString $text) + '}' }
    return '{"text":' + (ConvertTo-JsonString $text) + ',"url":' + (ConvertTo-JsonString ([string]$url)) + '}'
}
function New-Row([string[]]$buttons) {
    return '[' + ($buttons -join ',') + ']'
}
function New-Markup([string[]]$rows) {
    return '{"inline_keyboard":[' + ($rows -join ',') + ']}'
}

# =============== APP ROOT ===============
# ========================================
if ($PSScriptRoot) {
    $APP_ROOT = $PSScriptRoot
}
else {
    # (ekvivalent na sys.frozen / EXE)
    $APP_ROOT = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}

$LAST_AUDIT_ALERT = @{}
# === LOAD CONFIG FROM JSON ===
$CONFIG_PATH = [System.IO.Path]::Combine($APP_ROOT, "JSON", "settings.json")

if (-not (Test-Path -LiteralPath $CONFIG_PATH)) {
    throw "❌ Config file does not exist: $($CONFIG_PATH)"
}

$config = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($CONFIG_PATH, [System.Text.Encoding]::UTF8))

$BOT_TOKEN = $config.BOT_TOKEN
$CHAT_ID = [long]$config.CHAT_ID
$OWNER_IDS = New-Object 'System.Collections.Generic.HashSet[long]'
if ($null -ne $config.OWNER_IDS) {
    foreach ($x in $config.OWNER_IDS) { [void]$OWNER_IDS.Add([long]$x) }
}
$AUTOPILOT_URL = $config.AUTOPILOT_URL

if (-not $BOT_TOKEN -or -not $CHAT_ID) {
    throw "❌ BOT_TOKEN or CHAT_ID is missing in config.json"
}

# === BASE PATH (exe-safe) ===
$BASE_DIR = $APP_ROOT
$FOLDER = [System.IO.Path]::Combine($BASE_DIR, "Camera")
$SCREEN_FOLDER = [System.IO.Path]::Combine($BASE_DIR, "Archive/Recordings")
$LOG_FOLDER = [System.IO.Path]::Combine($BASE_DIR, "Autopilot_Data", "DataFolder_Logs")
$UPDATE_OFFSET_PATH = [System.IO.Path]::Combine($LOG_FOLDER, "telegram_update_offset.txt")

$PAGE_SIZE = 5
if ($null -ne $config.VIDEO_RETENTION_DAYS) { $VIDEO_RETENTION_DAYS = [int]$config.VIDEO_RETENTION_DAYS } else { $VIDEO_RETENTION_DAYS = 15 }
$LOG_RETENTION_DAYS = 30

# ✅ Kreiranje na folderi (sekogas, i vo EXE)
[void][System.IO.Directory]::CreateDirectory($LOG_FOLDER)

# Funkcija za Log_File
function Write-AuditLog([string]$message) {
    # Zapisi vo Log_File.
    $now = Get-Date
    $log_filename = [System.IO.Path]::Combine($LOG_FOLDER, "audit_$(Format-Date $now 'yyyy-MM-dd').txt")
    [System.IO.File]::AppendAllText($log_filename, "$(Format-Date $now 'yyyy-MM-dd HH:mm:ss') | $($message)`r`n", $script:Utf8NoBom)
    Clear-OldLogs
}

function Clear-OldLogs {
    # Brisenje na Logovi posteri od 30 dena.
    $now = Get-Date
    foreach ($path in [System.IO.Directory]::GetFiles($LOG_FOLDER)) {
        $created_time = [System.IO.File]::GetCreationTime($path)
        if (($now - $created_time).Days -gt $LOG_RETENTION_DAYS) {
            [System.IO.File]::Delete($path)
        }
    }
}

$tokenBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$BOT_TOKEN)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $tokenHash = [System.BitConverter]::ToString($sha256.ComputeHash($tokenBytes)).Replace('-', '')
}
finally {
    $sha256.Dispose()
}

$mutexName = "Local\PlayBot_$($tokenHash)"
$script:InstanceMutex = New-Object System.Threading.Mutex($false, $mutexName)
$hasInstanceLock = $false
try {
    $hasInstanceLock = $script:InstanceMutex.WaitOne(0)
}
catch [System.Threading.AbandonedMutexException] {
    $hasInstanceLock = $true
}

if (-not $hasInstanceLock) {
    Write-AuditLog "⚠️ Duplicate DATA Server start blocked; an instance for this bot is already running."
    $script:InstanceMutex.Dispose()
    exit 0
}

# Funkcija za Video Folder Info
function Get-VideoInfo([string]$path) {
    $duration = $null
    try {
        if ($null -eq $script:ShellApp) { $script:ShellApp = New-Object -ComObject Shell.Application }
        $full = [System.IO.Path]::GetFullPath($path)
        $dirNs = $script:ShellApp.NameSpace([System.IO.Path]::GetDirectoryName($full))
        $item = $dirNs.ParseName([System.IO.Path]::GetFileName($full))
        $raw = [string]$dirNs.GetDetailsOf($item, 27)
        $clean = $raw -replace '[^0-9:]', ''
        if ($clean -match '^\d+:\d{1,2}:\d{1,2}$') {
            $p = $clean.Split([char]':')
            $duration = ([long]$p[0] * 3600) + ([long]$p[1] * 60) + [long]$p[2]
        }
    }
    catch { $duration = $null }
    if ($null -eq $duration) {
        return "⏱ Unknown"
    }
    return (Format-TimeDelta $duration)
}

function Get-TotalFolderSize([string]$folder_path) {
    [long]$total_bytes = 0
    foreach ($p in [System.IO.Directory]::GetFiles($folder_path)) {
        $total_bytes += ([System.IO.FileInfo]$p).Length
    }
    return (Format-Size $total_bytes)
}

# =============== Telegram Bot API (ekvivalent na python-telegram-bot) ===============
# ====================================================================================
$script:Http = New-Object System.Net.Http.HttpClient
$script:Http.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan

# Greski: Kind = Timeout | RetryAfter | Telegram | Network   (site osven "Other" se TelegramError)
function New-TgError([string]$Kind, [string]$Message, [int]$RetryAfter = 0) {
    $ex = New-Object System.Exception($Message)
    $ex.Data['Kind'] = $Kind
    $ex.Data['RetryAfter'] = $RetryAfter
    return $ex
}

function Test-IsTgError($e) {
    $k = $e.Data['Kind']
    return ($k -ceq 'Timeout' -or $k -ceq 'RetryAfter' -or $k -ceq 'Telegram' -or $k -ceq 'Network')
}

function Get-RootException($e) {
    while ($null -ne $e -and $null -ne $e.InnerException -and
           ($e.GetType().Name -in 'MethodInvocationException', 'AggregateException', 'TargetInvocationException', 'ErrorRecordException')) {
        $e = $e.InnerException
    }
    return $e
}

# Python: PermissionError (WinError 5 / 32 / 33)
function Test-PermissionError($e) {
    $r = Get-RootException $e
    if ($r -is [System.UnauthorizedAccessException]) { return $true }
    if ($r -is [System.IO.IOException]) {
        $code = $r.HResult -band 0xFFFF
        return ($code -eq 32 -or $code -eq 33)
    }
    return $false
}

function Send-TgHttp([string]$Url, $Content, [int]$TimeoutMs) {
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter($TimeoutMs)
    $bytes = $null
    $status = 0
    try {
        $resp = $script:Http.PostAsync($Url, $Content, $cts.Token).GetAwaiter().GetResult()
        $status = [int]$resp.StatusCode
        $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $resp.Dispose()
    }
    catch {
        $ex = Get-RootException $_.Exception
        if ($ex -is [System.OperationCanceledException] -or $ex -is [System.TimeoutException]) {
            throw (New-TgError 'Timeout' 'Timed out')
        }
        throw (New-TgError 'Network' $ex.Message)
    }
    finally {
        $cts.Dispose()
    }

    if ($status -eq 413) {
        throw (New-TgError 'Network' 'File too large. Check telegram api limits https://core.telegram.org/bots/api#senddocument')
    }

    try { $json = ConvertFrom-Json -InputObject ([System.Text.Encoding]::UTF8.GetString($bytes)) }
    catch { throw (New-TgError 'Telegram' 'Invalid server response') }

    if ($json.ok -ne $true) {
        $code = 0
        if ($null -ne $json.error_code) { $code = [int]$json.error_code }
        $desc = [string]$json.description
        if ($code -eq 429) {
            $ra = 0
            if ($null -ne $json.parameters -and $null -ne $json.parameters.retry_after) { $ra = [int]$json.parameters.retry_after }
            throw (New-TgError 'RetryAfter' "Flood control exceeded. Retry in $($ra) seconds" $ra)
        }
        foreach ($prefix in 'Error: ', '[Error]: ', 'Bad Request: ') {
            if ($desc.StartsWith($prefix, [System.StringComparison]::Ordinal)) { $desc = $desc.Substring($prefix.Length) }
        }
        throw (New-TgError 'Telegram' $desc)
    }
    return $json.result
}

function Invoke-TgApi {
    param([string]$Method, $Params = $null, [int]$TimeoutSec = 60)
    if ($null -ne $Params) { $body = ConvertTo-JsonText $Params } else { $body = '{}' }
    $content = New-Object System.Net.Http.StringContent($body, $script:Utf8NoBom, 'application/json')
    try {
        return (Send-TgHttp "https://api.telegram.org/bot$($BOT_TOKEN)/$($Method)" $content ($TimeoutSec * 1000))
    }
    finally { $content.Dispose() }
}

function Get-MimeType([string]$Path) {
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.mp4'  { return 'video/mp4' }
        '.avi'  { return 'video/x-msvideo' }
        '.mkv'  { return 'video/x-matroska' }
        '.mov'  { return 'video/quicktime' }
        '.webm' { return 'video/webm' }
        '.mpg'  { return 'video/mpeg' }
        '.mpeg' { return 'video/mpeg' }
        '.wmv'  { return 'video/x-ms-wmv' }
        default { return 'application/octet-stream' }
    }
}

# reply_document / reply_video  (multipart upload)
function Send-TgFile([long]$ChatId, [string]$Method, [string]$Field, [string]$Path) {
    $multi = New-Object System.Net.Http.MultipartFormDataContent
    $fs = $null
    try {
        $multi.Add((New-Object System.Net.Http.StringContent([string]$ChatId)), 'chat_id')
        $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        $sc = New-Object System.Net.Http.StreamContent($fs)
        $sc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse((Get-MimeType $Path))
        $multi.Add($sc, $Field, [System.IO.Path]::GetFileName($Path))
        return (Send-TgHttp "https://api.telegram.org/bot$($BOT_TOKEN)/$($Method)" $multi (30 * 60 * 1000))
    }
    finally {
        if ($null -ne $fs) { $fs.Dispose() }
        $multi.Dispose()
    }
}

# message.reply_text(...)
function Send-TgReply($Message, [string]$Text, [string]$MarkupJson = '', [string]$ParseMode = '') {
    $p = [ordered]@{ chat_id = [long]$Message.chat.id; text = $Text }
    if ($MarkupJson) { $p['reply_markup'] = New-RawJson $MarkupJson }
    if ($ParseMode) { $p['parse_mode'] = $ParseMode }
    return (Invoke-TgApi 'sendMessage' $p)
}

# query.answer(...)
function Invoke-TgAnswer($Query, [string]$Text = '', [bool]$ShowAlert = $false) {
    $p = [ordered]@{ callback_query_id = [string]$Query.id }
    if ($Text) { $p['text'] = $Text }
    if ($ShowAlert) { $p['show_alert'] = $true }
    [void](Invoke-TgApi 'answerCallbackQuery' $p)
}

function Invoke-TgAnswerSafely($Query, [string]$Text = '', [bool]$ShowAlert = $false) {
    try {
        Invoke-TgAnswer $Query $Text $ShowAlert
        return $true
    }
    catch {
        if ($_.Exception.Message -match 'query is too old|response timeout expired|query ID is invalid') {
            $now = Get-Date
            if ($null -eq $script:LastCallbackWarning -or
                ($now - $script:LastCallbackWarning).TotalSeconds -ge 60) {
                Write-AuditLog "Expired Telegram callback ignored: $($_.Exception.Message)"
                $script:LastCallbackWarning = $now
            }
            return $false
        }
        throw
    }
}

# =============== 🛡️ SECURITY GATE ===============
# ================================================
function Test-Security($obj) {
    $props = $obj.PSObject.Properties

    # --- CASE 1: CallbackQuery direktno ---
    if ($null -ne $props['chat_instance']) {
        $user = $obj.'from'
        $message = $obj.message
        $text = [string]$obj.data
    }
    # --- CASE 2: Update со callback_query ---
    elseif ($null -ne $props['update_id'] -and $null -ne $obj.callback_query) {
        $cq = $obj.callback_query
        $user = $cq.'from'
        $message = $cq.message
        $text = [string]$cq.data
    }
    # --- CASE 3: Update со message ---
    elseif ($null -ne $props['update_id'] -and $null -ne $obj.message) {
        $user = $obj.message.'from'
        $message = $obj.message
        $text = [string]$obj.message.text
    }
    else {
        return $false  # unsupported object
    }

    $user_id = [long]$user.id
    $chat_id = [long]$message.chat.id
    $chat_type = [string]$message.chat.type

    # Private chat check
    if ($chat_type -cne "private") {
        $log = "🛡️ Message from ⛔ non-private chat  👨‍💼 ChatType=$($chat_type)  🆔 ChatId=$($chat_id)"
        Write-AuditLog "AUDIT: $($log)"
        return $false
    }

    # Owner check
    if (-not $OWNER_IDS.Contains($user_id)) {
        $now = Get-Date
        $log = "🛡️ Unauthorized access  👨‍💼 UserId=$($user_id)  🆔 ChatId=$($chat_id)  📨 Text=$($text)"
        Write-AuditLog "AUDIT: $($log)"

        $last_alert_time = $LAST_AUDIT_ALERT[$user_id]
        if (-not $last_alert_time -or ($now - $last_alert_time).TotalSeconds -ge 180) {
            $alert_text = "🛡️ SECURITY ALERT 🛡️`n" +
                "Unauthorized attempt to access!`n`n" +
                "👨‍💼 UserId: $($user_id)`n" +
                "🆔 ChatId: $($chat_id)`n" +
                "📨 Message: $($text)`n" +
                "🕒 Time: $(Format-Date $now 'dd-MM-yyyy HH:mm:ss')"
            [void](Send-TgReply $message $alert_text)
            $LAST_AUDIT_ALERT[$user_id] = $now
        }

        [void](Send-TgReply $message "Chat access ⛔ not Allowed.")
        return $false
    }

    return $true
}

# =============== Meni ===============
# ====================================
function Get-MainMenu {
    return (New-Markup @(
        (New-Row @((New-Btn "📷 Camera Video" "mode|camera"))),
        (New-Row @((New-Btn "🖥️ Recordings Video" "mode|screen"))),  #  Comment for 1 Folder
        (New-Row @((New-Btn "⚙️ Retention Days" "retention"))),
        (New-Row @((New-Btn "🚪 Exit" "exit")))
    ))
}

# === Funkcija za start meni ===
function Send-StartMenu {
    $MENU_TEXT = "💿  *DATA System Started*  ✅"
    $MAIN_MENU = Get-MainMenu
    [void](Invoke-TgApi 'sendMessage' ([ordered]@{
        chat_id      = $CHAT_ID
        text         = $MENU_TEXT
        reply_markup = (New-RawJson $MAIN_MENU)
        parse_mode   = 'Markdown'
    }))
}

function Show-MainMenu($update_or_query, $context) {
    $MAIN_MENU = Get-MainMenu

    $text = "💿  *DATA System Menu*  ✅"
    [void](Send-TgReply $update_or_query.message $text $MAIN_MENU 'Markdown')
}

# === Funkcija za prikaz na stranata ===
function Show-Page($update_or_query, $context, [int]$page) {
    # SECURITY CHECK
    if (-not (Test-Security $update_or_query)) {
        return
    }

    # helper za reply/edit
    $reply_to = $update_or_query.message

    # ✅ Logiranje za pristap
    $user_id = [long]$update_or_query.message.'from'.id
    Write-AuditLog "User $($user_id) use the media folder page $($page + 1)"

    # ✅ Auto-create folder if not exists
    $mode = Get-Ctx $context "mode" "camera"
    if ($mode -ceq "screen") { $active_folder = $SCREEN_FOLDER } else { $active_folder = $FOLDER }

    $folder_created = $false
    if (-not (Test-Path -LiteralPath $active_folder)) {
        [void][System.IO.Directory]::CreateDirectory($active_folder)
        $folder_created = $true
        Write-AuditLog "Folder $($active_folder) has been created."
    }

    $files = Get-FileNames $active_folder

    if ($mode -ceq "camera") { $folder_label = "Camera" } else { $folder_label = "Recordings" }
    if ($files.Count -eq 0) {
        if ($folder_created) {
            $text = "🗂️ New folder created:`n$($active_folder)`n`n" +
                "ℹ️ The folder is empty."
        }
        else {
            $text = "🗂️ $($folder_label) Media Folder`n`n" +
                "ℹ️ The folder is empty.`n`n" +
                "🎦 No videos have been saved yet."
        }
        $markup = New-Markup @(
            (New-Row @((New-Btn "✅ Menu" "main_menu"))),
            (New-Row @((New-Btn "🚪 Exit" "exit")))
        )
        [void](Send-TgReply $reply_to $text $markup "Markdown")
        return
    }

    # === Auto delete videos older than VIDEO_RETENTION_DAYS ===
    $now = Get-Date
    foreach ($f in $files) {
        $path = [System.IO.Path]::Combine($active_folder, $f)
        $created = [System.IO.File]::GetCreationTime($path)
        if (($now - $created).Days -gt $VIDEO_RETENTION_DAYS) {
            [System.IO.File]::Delete($path)
            $del_message = "Old 🎬 videos automatically 🗑️ deleted: $($f)`n" +
                "📅 Created on: $(Format-Date $created 'yyyy-MM-dd HH:mm:ss')`n" +
                "⚠️ Status: Video older than $($VIDEO_RETENTION_DAYS) days`n" +
                "🕒 Today: $(Format-Date $now 'yyyy-MM-dd HH:mm:ss')"
            Write-AuditLog $del_message
            [void](Invoke-TgApi 'sendMessage' ([ordered]@{ chat_id = $CHAT_ID; text = $del_message }))
        }
    }

    # Refresh file list and sort by creation date
    $listing = Get-FileNames $active_folder
    $rows = @()
    $n = 0
    foreach ($name in $listing) {
        $rows += [pscustomobject]@{
            Name  = $name
            Ticks = [System.IO.File]::GetCreationTimeUtc([System.IO.Path]::Combine($active_folder, $name)).Ticks
            Idx   = $n
        }
        $n++
    }
    $files = @($rows | Sort-Object -Property @{ Expression = { $_.Ticks }; Descending = $true }, @{ Expression = { $_.Idx }; Descending = $false } | ForEach-Object { $_.Name })

    $total = $files.Count
    # ✅ FIX: korekcija na stranica po brishenje
    $max_page = [math]::Max(0, (FloorDiv ($total - 1) $PAGE_SIZE))
    if ($page -gt $max_page) {
        $page = $max_page
    }
    $start = $page * $PAGE_SIZE
    $end = $start + $PAGE_SIZE
    # Zapisi momentalna stranica vo user_data
    $context["current_page"] = $page

    # === Header ===
    $created_now = Get-Date
    $total_size_text = Get-TotalFolderSize $active_folder
    if ($mode -ceq "camera") { $folder_label = "Camera" } else { $folder_label = "Recordings" }
    $header_text = "🗂️ FOLDER ($($folder_label))  🧾 Page $($page + 1) from $((FloorDiv ($total - 1) $PAGE_SIZE) + 1)`n`n" +
        "🕒 $(Format-Date $created_now 'HH:mm:ss - dd-MM-yyyy')`n`n" +
        "💾 *Total folder size:* $($total_size_text)`n`n" +
        "📀 *Total number of videos:* $($total)`n`n"
    [void](Send-TgReply $reply_to $header_text "" "Markdown")

    # === Sekoe video: text + Play/Delete ===
    $idx = $start + 1
    for ($i = $start; $i -lt [math]::Min($end, $total); $i++) {
        $f = $files[$i]
        $path = [System.IO.Path]::Combine($active_folder, $f)
        $created = [System.IO.File]::GetCreationTime($path)
        $duration = Get-VideoInfo $path
        $size_bytes = ([System.IO.FileInfo]$path).Length
        $size_text = Format-Size $size_bytes
        $text = "*$($idx). $($f)*`n" +
            "📅 *Creation date:* $(Format-Date $created 'yyyy-MM-dd')`n" +
            "🕒 *Creation time:* $(Format-Date $created 'HH:mm:ss')`n" +
            "⏱ *Duration:* $($duration)`n" +
            "💾 *Size:* $($size_text)"
        $keyboard = New-Markup @(
            (New-Row @(
                (New-Btn "▶️ Play" "play|$($f)"),
                (New-Btn "🗑 Delete" "del|$($f)")
            ))
        )
        [void](Send-TgReply $reply_to $text $keyboard "Markdown")
        $idx++
    }

    # === Footer: pagination + Media + Izlez ===
    $nav_buttons = @()
    if ($start -gt 0) {
        $nav_buttons += (New-Btn "⬅️ Prev" "page|$($page - 1)")
    }
    if ($end -lt $total) {
        $nav_buttons += (New-Btn "Next ➡️" "page|$($page + 1)")
        $nav_buttons += (New-Btn "Last ⏭️" "page|$(FloorDiv ($total - 1) $PAGE_SIZE)")
    }

    $nav_buttons += (New-Btn "🗂️ Folder" "data_command")
    $nav_buttons += (New-Btn "✅ Menu" "main_menu")
    $exit_button = New-Row @((New-Btn "🚪 Exit" "exit"))
    $footer_markup = New-Markup @((New-Row $nav_buttons), $exit_button)
    $footer_text = "🎬 Display from $($start + 1) to $([math]::Min($end, $total)) from $($total) videos"
    [void](Send-TgReply $reply_to $footer_text $footer_markup)
}

# === /data komanda ===
function Invoke-DataCommand($update, $context) {
    if (-not (Test-Security $update)) {
        return
    }
    Show-MainMenu $update $context
}

# =============== Zastita od path traversal (os.path.realpath / commonpath) ===============
# =========================================================================================
function Get-RealPath([string]$p) {
    $full = [System.IO.Path]::GetFullPath($p)
    try {
        $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if ($item.LinkType) {
            $t = $item.ResolveLinkTarget($true)
            if ($t) { return $t.FullName }
        }
    }
    catch { }
    return $full
}

function Test-PathInBase([string]$real_path, [string]$real_base) {
    $rb = $real_base.TrimEnd([char]'\', [char]'/')
    $rp = $real_path.TrimEnd([char]'\', [char]'/')
    if ([string]::Equals($rp, $rb, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $rp.StartsWith($rb + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

# Global per-user processing flag
$user_processing = @{}
# Per-user "context.user_data"
$script:UserData = @{}

function Get-UserData([long]$uid) {
    if (-not $script:UserData.ContainsKey($uid)) { $script:UserData[$uid] = @{} }
    return $script:UserData[$uid]
}

function Save-UpdateOffset([long]$value) {
    $tempPath = "$($UPDATE_OFFSET_PATH).tmp"
    $backupPath = "$($UPDATE_OFFSET_PATH).bak"
    [System.IO.File]::WriteAllText($tempPath, $value.ToString($script:Inv), $script:Utf8NoBom)
    if ([System.IO.File]::Exists($UPDATE_OFFSET_PATH)) {
        if ([System.IO.File]::Exists($backupPath)) {
            [System.IO.File]::Delete($backupPath)
        }
        [System.IO.File]::Replace($tempPath, $UPDATE_OFFSET_PATH, $backupPath)
        if ([System.IO.File]::Exists($backupPath)) {
            [System.IO.File]::Delete($backupPath)
        }
    }
    else {
        [System.IO.File]::Move($tempPath, $UPDATE_OFFSET_PATH)
    }
}

# === Callback handler ===
function Invoke-ButtonHandler($update, $context) {
    $query = $update.callback_query
    $user_id = [long]$query.'from'.id
    $data = [string]$query.data

    if ($user_processing[$user_id] -eq $true) {
        [void](Invoke-TgAnswerSafely $query "⌛ Processing previous command, Please wait a moment…" $true)
        return
    }

    $answerText = ''
    $showAnswerAlert = $false
    if ((Test-StartsWith $data "play|") -or (Test-StartsWith $data "del|")) {
        $answerText = "⌛ Executing command…"
        $showAnswerAlert = $true
    }
    if (-not (Invoke-TgAnswerSafely $query $answerText $showAnswerAlert)) {
        return
    }

    # 1. SECURITY FIRST
    if (-not (Test-Security $query)) {
        return
    }

    if ($data -ceq "exit") {
        $keyboard = New-Markup @((New-Row @((New-UrlBtn "👉 Return to AutoPilot" $AUTOPILOT_URL))))
        try {
            [void](Send-TgReply $query.message "🚪 DATA Server has been Stopped..." $keyboard)
        }
        finally {
            if ($null -ne $script:CurrentUpdateId) {
                Save-UpdateOffset ([long]$script:CurrentUpdateId + 1)
            }
            [System.Environment]::Exit(0)
        }
    }

    # MODE CHANGE HANDLER
    if (Test-StartsWith $data "mode|") {
        $mode = $data.Split([char]'|')[1]
        $context["mode"] = $mode
        $context["current_page"] = 0
        Show-Page $query $context 0
        return
    }

    # 3. GET MODE AFTER SECURITY
    $mode = Get-Ctx $context "mode" "camera"
    if ($mode -ceq "screen") { $active_folder = $SCREEN_FOLDER } else { $active_folder = $FOLDER }

    # MEDIA BUTTON (FIX - MOVED HERE)
    if ($data -ceq "data_command") {
        $page = Get-Ctx $context "current_page" 0
        Show-Page $query $context $page
        return
    }

    if ($data -ceq "retention") {
        $keyboard = New-Markup @(
            (New-Row @((New-Btn "7 Days" "ret|7"))),
            (New-Row @((New-Btn "15 Days" "ret|15"))),
            (New-Row @((New-Btn "30 Days" "ret|30"))),
            (New-Row @((New-Btn "60 Days" "ret|60"))),
            (New-Row @((New-Btn "✅ Menu" "main_menu"))),
            (New-Row @((New-Btn "🚪 Exit" "exit")))
        )
        [void](Send-TgReply $query.message "📅 Current retention: $($VIDEO_RETENTION_DAYS) days" $keyboard)
        return
    }

    if (Test-StartsWith $data "ret|") {
        $days = [int]$data.Split([char]'|')[1]
        $script:VIDEO_RETENTION_DAYS = $days
        if ($null -ne $config.PSObject.Properties['VIDEO_RETENTION_DAYS']) {
            $config.VIDEO_RETENTION_DAYS = $days
        }
        else {
            $config | Add-Member -NotePropertyName 'VIDEO_RETENTION_DAYS' -NotePropertyValue $days
        }
        $json_out = (ConvertTo-JsonText $config 4).Replace("`n", "`r`n")
        [System.IO.File]::WriteAllText($CONFIG_PATH, $json_out, $script:Utf8NoBom)
        Write-AuditLog "Video retention changed to $($days) days by user $($query.'from'.id)"
        [void](Send-TgReply $query.message "✅ Video retention changed to $($days) days")
        Show-MainMenu $query $context   # 🔥 BACK TO MAIN MENU
        return
    }

    # Active User
    $user_processing[$user_id] = $true
    $last_markup = $null
    if ($query.message.reply_markup) { $last_markup = $query.message.reply_markup }
    try {
        # Remove keyboard
        try {
            [void](Invoke-TgApi 'editMessageReplyMarkup' ([ordered]@{
                chat_id    = [long]$query.message.chat.id
                message_id = [long]$query.message.message_id
            }))
        }
        catch { if (-not (Test-IsTgError $_.Exception)) { throw } }

        # PLAY VIDEO
        if (Test-StartsWith $data "play|") {
            $parts = $data.Split(@([char]'|'), 2)
            if ($parts.Count -ne 2) {
                [void](Send-TgReply $query.message "❌ Request failed.")
                return
            }

            $filename = [System.IO.Path]::GetFileName($parts[1])
            $path = [System.IO.Path]::Combine($active_folder, $filename)
            $real_path = Get-RealPath $path
            $real_base = Get-RealPath $active_folder

            if (-not (Test-PathInBase $real_path $real_base)) {
                [void](Send-TgReply $query.message "❌ Path failed.")
                return
            }

            if (-not (Test-Path -LiteralPath $real_path)) {
                [void](Send-TgReply $query.message "❌ File does not exist.")
                Write-AuditLog "Missing file requested: $($filename) by user $($query.'from'.id)"
                Write-AuditLog "You attempted to start a video that does not exist: $($filename) from user $($query.'from'.id)"
                return
            }

            $status_msg = Send-TgReply $query.message "⌛ The video is Loading…"
            $upload_success = $false
            $last_error = $null

            # Optional retry loop (safe + simple)
            for ($attempt = 1; $attempt -lt 3; $attempt++) {  # 2 attempts max
                try {
                    # Core upload logic (send_file)
                    $file_size = ([System.IO.FileInfo]$real_path).Length
                    # Large file -> document
                    if ($file_size -gt 50 * 1024 * 1024) {
                        [void](Send-TgFile ([long]$query.message.chat.id) 'sendDocument' 'document' $real_path)
                    }
                    # Small file -> video
                    else {
                        [void](Send-TgFile ([long]$query.message.chat.id) 'sendVideo' 'video' $real_path)
                    }
                    $upload_success = $true
                    $last_error = $null
                    break
                }
                catch {
                    $e = $_.Exception
                    $kind = $e.Data['Kind']
                    if ($kind -ceq 'Timeout') {
                        $last_error = "Timeout error (attempt $($attempt)): $($e.Message)"
                        Start-Sleep -Milliseconds 1500
                    }
                    elseif ($kind -ceq 'RetryAfter') {
                        $last_error = "Rate limited: retry after $($e.Data['RetryAfter'])s"
                        Start-Sleep -Seconds ([int]$e.Data['RetryAfter'])
                    }
                    elseif (Test-IsTgError $e) {
                        $last_error = "Telegram API error: $($e.Message)"
                        break
                    }
                    else {
                        $last_error = "Unexpected error: $((Get-RootException $e).Message)"
                        break
                    }
                }
            }

            # Final status handling
            if ($upload_success) {
                [void](Invoke-TgApi 'editMessageText' ([ordered]@{
                    chat_id    = [long]$status_msg.chat.id
                    message_id = [long]$status_msg.message_id
                    text       = "✅ Video sent successfully"
                }))
                Write-AuditLog "Video sent: $($filename) by user $($query.'from'.id)"
            }
            else {
                [void](Invoke-TgApi 'editMessageText' ([ordered]@{
                    chat_id    = [long]$status_msg.chat.id
                    message_id = [long]$status_msg.message_id
                    text       = "❌ Failed to send video:`n$($last_error)"
                }))
                Write-AuditLog "Video send FAILED: $($filename) | Error: $($last_error) | User $($query.'from'.id)"
            }
        }

        # DELETE VIDEO
        elseif (Test-StartsWith $data "del|") {
            $parts = $data.Split(@([char]'|'), 2)
            if ($parts.Count -ne 2) {
                [void](Send-TgReply $query.message "❌ Request failed.")
                return
            }

            $filename = [System.IO.Path]::GetFileName($parts[1])
            $path = [System.IO.Path]::Combine($active_folder, $filename)
            $real_path = Get-RealPath $path
            $real_base = Get-RealPath $active_folder

            if (-not (Test-PathInBase $real_path $real_base)) {
                [void](Send-TgReply $query.message "❌ Path failed.")
                return
            }

            if (-not (Test-Path -LiteralPath $real_path)) {
                [void](Send-TgReply $query.message "❌ File does not exist.")
                Write-AuditLog "You attempted to delete a missing video: $($filename) from user $($query.'from'.id)"
            }
            else {
                try {
                    [System.IO.File]::Delete($real_path)
                    $current_page = Get-Ctx $context "current_page" 0
                    Show-Page $query $context $current_page
                    [void](Send-TgReply $query.message "🗑️ Video deleted`n`n🎬 File: $($filename)`n`n✅ The video has been successfully removed.")
                    Write-AuditLog "Manually deleted video: $($filename) from user $($query.'from'.id)"
                }
                catch {
                    $err = $_.Exception
                    if (Test-PermissionError $err) {
                        [void](Send-TgReply $query.message "❌ Cannot delete $($filename) - file is currently in use.")
                        Write-AuditLog "Delete blocked (file in use): $($filename) from user $($query.'from'.id)"
                    }
                    else {
                        [void](Send-TgReply $query.message "❌ Delete failed.")
                        Write-AuditLog "Delete failed: $($filename) | Error: $((Get-RootException $err).Message) | User $($query.'from'.id)"
                    }
                }
            }
        }

        # MAIN MENU
        elseif ($data -ceq "main_menu") {
            $context["current_page"] = 0
            $context["mode"] = "camera"
            Show-MainMenu $query $context
            return
        }
    }
    finally {
        # Reset User
        $user_processing.Remove($user_id)
        if ($last_markup) {
            try {
                [void](Invoke-TgApi 'editMessageReplyMarkup' ([ordered]@{
                    chat_id      = [long]$query.message.chat.id
                    message_id   = [long]$query.message.message_id
                    reply_markup = (New-RawJson (ConvertTo-JsonText $last_markup))
                }))
            }
            catch { if (-not (Test-IsTgError $_.Exception)) { throw } }
        }
    }

    # PAGE NAVIGATION
    if (Test-StartsWith $data "page|") {
        $page = [int]$data.Split([char]'|')[1]
        Show-Page $query $context $page
    }

}

# =============== Main ===============
# ====================================
# app.run_polling():  initialize -> post_init -> delete_webhook -> getUpdates loop
try {
    [void](Invoke-TgApi 'getMe')
    [void](Invoke-TgApi 'deleteWebhook' ([ordered]@{ drop_pending_updates = $false }))
    Send-StartMenu
}
catch {
    $errorMessage = "❌ Startup failed: $($_.Exception.Message)"
    Write-AuditLog $errorMessage
    throw
}
Write-AuditLog "✅ DATA Server has started Running..."

$offset = $null
$pollFailureCount = 0
if ([System.IO.File]::Exists($UPDATE_OFFSET_PATH)) {
    $savedOffset = [System.IO.File]::ReadAllText($UPDATE_OFFSET_PATH).Trim()
    if ($savedOffset -match '^\d+$') {
        $offset = [long]$savedOffset
    }
    else {
        $errorMessage = "⚠️ Invalid saved Telegram update offset; starting without a checkpoint."
        Write-AuditLog $errorMessage
    }
}

while ($true) {
    try {
        $p = [ordered]@{ timeout = 10; limit = 100 }
        if ($null -ne $offset) { $p['offset'] = $offset }
        $updates = @(Invoke-TgApi 'getUpdates' $p 70)
    }
    catch {
        $pollFailureCount++
        $pollException = Get-RootException $_.Exception
        $pollErrorKind = $pollException.Data['Kind']

        if ($pollErrorKind -ceq 'Timeout' -or
            $pollException -is [System.TimeoutException] -or
            $pollException -is [System.Threading.Tasks.TaskCanceledException]) {
            if ($pollFailureCount -eq 1 -or ($pollFailureCount % 5) -eq 0) {
                Write-AuditLog "Telegram long-poll timeout (consecutive failures: $($pollFailureCount)); retrying."
            }
            $retryDelay = [math]::Min(30, [math]::Pow(2, [math]::Min($pollFailureCount - 1, 5)))
            Start-Sleep -Seconds ([int]$retryDelay)
        }
        else {
            $errorMessage = "⚠️ Polling error: $($pollException.Message)"
            Write-AuditLog $errorMessage
            Start-Sleep -Seconds 3
        }
        continue
    }

    if ($pollFailureCount -gt 0) {
        Write-AuditLog "✅ Telegram polling recovered after $($pollFailureCount) consecutive failure(s)."
        $pollFailureCount = 0
    }

    foreach ($u in $updates) {
        $script:CurrentUpdateId = [long]$u.update_id
        try {
            # Samo CallbackQuery handler-ite se registrirani
            if ($null -ne $u.callback_query) {
                $ctx = Get-UserData ([long]$u.callback_query.'from'.id)
                Invoke-ButtonHandler $u $ctx
            }
        }
        catch {
            Write-AuditLog "❌ Error while handling update: $($_.Exception.Message)"
        }
        finally {
            $offset = [long]$u.update_id + 1
            Save-UpdateOffset $offset
            $script:CurrentUpdateId = $null
        }
    }
}

############################################################################################################ End File Storage.