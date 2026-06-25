# paranoid.ps1 — интерактивный лаунчер экосистемы Paranoid Tools, Windows-зеркало (BETA).
# Зеркало macOS-версии (bash `paranoid`). Baseline: Windows PowerShell 5.1.
#
# ЧЕСТНО: тонкий лаунчер, не новый инструмент. Не содержит крипты и НЕ трогает секреты —
# секреты вводятся напрямую в нужный CLI. Запускает те же пять подписанных PowerShell-портов
# (через .cmd-шимы на PATH) и показывает их вывод как есть (Scope & limitations и вердикты
# `check` не прячет). Глобального хоткея/демона тут нет — это Фаза B (нативный tray).
#
# Зависимостей — ноль сверх PowerShell. Установленные тулы ищутся на PATH по имени; отсутствующий
# тул показывается «(not installed)» с хинтом, а не подделывается.
#
# Запуск через .cmd-шим = pwsh 7 (UTF-8 по умолчанию), как и у пяти портов. Синтаксис держим
# 5.1-совместимым. Дашборд — ТЕКСТОВЫЙ (без ANSI-цвета): честность несёт текст («at risk»,
# «(not installed)»), а цветные dot'ы macOS-версии — полировка Фазы B, не дрейф.

$PARANOID_VERSION = '0.1.0'

# Активный том vault. securetrash на Windows выбирает ПЕРВУЮ СВОБОДНУЮ букву динамически
# (Get-StFreeDriveLetter — не хардкод V:) и пишет её в sidecar <vault>.vhdx.mount при open.
# Резолвим реальную букву оттуда; ST_VAULT_VOLUME переопределяет вручную. $null = vault закрыт.
function Get-PnVaultMount {
    if ($env:ST_VAULT_VOLUME) { return $env:ST_VAULT_VOLUME }
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
    if (-not $homeDir) { return $null }
    $sidecar = Join-Path $homeDir 'SecureVault.vhdx.mount'
    if (Test-Path -LiteralPath $sidecar) {
        $m = (Get-Content -LiteralPath $sidecar -Raw).Trim()
        if ($m) { return $m }
    }
    return $null
}
$script:VAULT_VOLUME = Get-PnVaultMount

# --- locale ---
function Get-PnLocale {
    $want = $env:ST_LANG
    if ($want) { if ($want -match '^(?i)ru') { return 'ru' } else { return 'en' } }
    if ($PSUICulture -and ($PSUICulture -match '^(?i)ru')) { return 'ru' }
    return 'en'
}
$script:PN_LOCALE = if ($env:ST_LOCALE) { $env:ST_LOCALE } else { Get-PnLocale }

# --- i18n (только chrome лаунчера; вывод тулов локализуют они сами) ---
function T {
    param([string]$Key, [string]$A, [string]$B)
    switch ("$($script:PN_LOCALE):$Key") {
        'en:title'        { return 'PARANOID TOOLS' }
        'ru:title'        { return 'PARANOID TOOLS' }
        'en:vault'        { return 'Vault:' }       'ru:vault'        { return 'Сейф:' }
        'en:vault_open'   { return 'OPEN' }         'ru:vault_open'   { return 'ОТКРЫТ' }
        'en:vault_closed' { return 'closed' }       'ru:vault_closed' { return 'закрыт' }
        'en:vault_none'   { return 'not set up' }    'ru:vault_none'   { return 'не создан' }
        'en:vault_setup_hint' { return 'No vault yet — creating one (securetrash will ask for size & password).' }
        'ru:vault_setup_hint' { return 'Сейфа ещё нет — создаём (securetrash спросит размер и пароль).' }
        'en:vault_risk'   { return 'at risk while open' } 'ru:vault_risk' { return 'под угрозой, пока открыт' }
        'en:bl'           { return 'BitLocker:' }   'ru:bl'           { return 'BitLocker:' }
        'en:on'           { return 'ON' }           'ru:on'           { return 'ВКЛ' }
        'en:off'          { return 'OFF' }          'ru:off'          { return 'ВЫКЛ' }
        'en:unknown'      { return 'unknown' }      'ru:unknown'      { return 'неизвестно' }
        'en:vw'           { return 'vaultwatch:' }  'ru:vw'           { return 'vaultwatch:' }
        'en:vw_active'    { return 'active' }       'ru:vw_active'    { return 'активен' }
        'en:vw_idle'      { return 'idle' }         'ru:vw_idle'      { return 'нет сессий' }
        'en:m_status'     { return 'Status — full read-only check' }
        'ru:m_status'     { return 'Статус — полная проверка (только чтение)' }
        'en:m_panic'      { return 'PANIC NOW — hide & lock (confirm)' }
        'ru:m_panic'      { return 'ПАНИКА — спрятать и запереть (подтвердить)' }
        'en:m_vault'      { return 'Vault — create / open / close' }
        'ru:m_vault'      { return 'Сейф — создать / открыть / закрыть' }
        'en:m_split'      { return 'Split a secret (seedsplit)' }
        'ru:m_split'      { return 'Разбить секрет (seedsplit)' }
        'en:m_combine'    { return 'Combine shares (seedsplit)' }
        'ru:m_combine'    { return 'Собрать из долей (seedsplit)' }
        'en:m_ghost'      { return 'Ghostdraft — ephemeral note / pipe' }
        'ru:m_ghost'      { return 'Ghostdraft — эфемерная заметка / pipe' }
        'en:m_watch'      { return 'Watch vault — guard + TTL (vaultwatch)' }
        'ru:m_watch'      { return 'Сторожить сейф — guard + TTL (vaultwatch)' }
        'en:m_quit'       { return 'Quit' }         'ru:m_quit'       { return 'Выход' }
        'en:not_installed'{ return 'not installed' } 'ru:not_installed'{ return 'не установлен' }
        'en:install_hint' { return "Install ${A}: $B" }   'ru:install_hint' { return "Установить ${A}: $B" }
        'en:choose'       { return 'Choose' }       'ru:choose'       { return 'Выбор' }
        'en:press_enter'  { return 'Press Enter to continue' }
        'ru:press_enter'  { return 'Нажми Enter, чтобы продолжить' }
        'en:confirm_panic'{ return 'Run panic now? This hides & locks everything.' }
        'ru:confirm_panic'{ return 'Запустить панику? Это спрячет и запрёт всё.' }
        'en:ask_hard'     { return 'Also kill cloud daemons & clear recent items (--hard)?' }
        'ru:ask_hard'     { return 'Также прибить cloud-демоны и очистить recent (--hard)?' }
        'en:ask_ttl'      { return 'Auto-exit after (e.g. 30m, 2h; empty = no timer):' }
        'ru:ask_ttl'      { return 'Авто-выход через (напр. 30m, 2h; пусто = без таймера):' }
        'en:cancelled'    { return 'Cancelled.' }   'ru:cancelled'    { return 'Отменено.' }
        'en:ghost_new'    { return 'new — edit an ephemeral draft' }
        'ru:ghost_new'    { return 'new — редактировать эфемерный черновик' }
        'en:ghost_pipe'   { return 'pipe — paste, view, write nothing to disk' }
        'ru:ghost_pipe'   { return 'pipe — вставить, посмотреть, на диск ничего' }
        'en:type_yes'     { return '[type yes]' }   'ru:type_yes'     { return '[введите yes]' }
        default           { return $Key }
    }
}

# --- инструменты экосистемы: репо для хинта ---
function Get-PnToolRepo {
    param([string]$Tool)
    switch ($Tool) {
        'securetrash' { 'https://github.com/Di-kairos/securetrash' }
        'vaultwatch'  { 'https://github.com/Di-kairos/vaultwatch' }
        'panic'       { 'https://github.com/Di-kairos/panic' }
        'seedsplit'   { 'https://github.com/Di-kairos/seedsplit' }
        'ghostdraft'  { 'https://github.com/Di-kairos/ghostdraft' }
        default       { '' }
    }
}

function Test-PnTool { param([string]$Tool) [bool](Get-Command $Tool -ErrorAction SilentlyContinue) }

# Запустить тул (через .cmd-шим на PATH), не роняя цикл. Нет тула → хинт. Мокается в Pester.
function Invoke-PnTool {
    param([string]$Tool, [string[]]$ToolArgs = @())
    if (-not (Test-PnTool $Tool)) {
        [Console]::Error.WriteLine((T 'install_hint' $Tool (Get-PnToolRepo $Tool)))
        return
    }
    & $Tool @ToolArgs
}

# --- статус для dashboard (только чтение; деградирует в unknown, не угадывает) ---
# Файл-контейнер vault (securetrash default: ~/SecureVault.vhdx). Отличает «закрыт» от «не создан».
function Get-PnVaultContainer {
    if ($env:ST_VAULT_PATH) { return $env:ST_VAULT_PATH }
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
    if (-not $homeDir) { return $null }
    return (Join-Path $homeDir 'SecureVault.vhdx')
}
function Get-PnVaultState {
    # Трёхсостоянийно: open = том примонтирован (буква из sidecar/override); closed = контейнер
    # есть, но не смонтирован; none = контейнера ещё нет. Guard на $null/пустое (Test-Path '' кидает).
    if ($script:VAULT_VOLUME -and (Test-Path -LiteralPath $script:VAULT_VOLUME)) { return 'open' }
    $container = Get-PnVaultContainer
    if ($container -and (Test-Path -LiteralPath $container)) { return 'closed' }
    return 'none'
}
function Get-PnBitLockerState {
    try {
        $sys = Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.VolumeType -eq 'OperatingSystem' }
        if ($sys -and $sys.ProtectionStatus -eq 'On') { return 'on' }
        if ($sys) { return 'off' }
        return 'unknown'
    } catch { return 'unknown' }
}
function Get-PnVaultwatchState {
    if (-not (Test-PnTool 'vaultwatch')) { return 'absent' }
    try {
        $out = & vaultwatch status 2>$null
        if ($out -match '(?i)session:|сессия:') { return 'active' } else { return 'idle' }
    } catch { return 'idle' }
}
# TTL-строка активной сессии (для dashboard). Отдельная функция — чтобы Pester мог замокать
# и рендер дашборда не дёргал реальный vaultwatch. Пусто, если строки TTL нет/тула нет.
function Get-PnVaultwatchTtl {
    try {
        $m = & vaultwatch status 2>$null | Select-String -Pattern 'TTL|auto-exit|авто-выход' | Select-Object -First 1
        if ($m) { return $m.ToString().Trim() }
    } catch { }
    return ''
}

# --- текст dashboard отдельной функцией (Pester проверяет строки без запуска цикла) ---
function Get-PnDashboard {
    # Перечитываем активный том перется каждым рендером — буква могла появиться/исчезнуть
    # (securetrash open/close между тиками). Тесты задают $script:VAULT_VOLUME напрямую и
    # мокают Get-PnVaultState, поэтому refresh их вердикты не трогает.
    $script:VAULT_VOLUME = Get-PnVaultMount
    $v  = Get-PnVaultState
    $bl = Get-PnBitLockerState
    $vw = Get-PnVaultwatchState
    $lines = @()
    $lines += ''
    $lines += "  $(T 'title')                          Windows"
    $lines += ''
    if ($v -eq 'open') {
        $lines += "  $(T 'vault')      $(T 'vault_open')  ($($script:VAULT_VOLUME))   ! $(T 'vault_risk')"
    } elseif ($v -eq 'none') {
        $lines += "  $(T 'vault')      $(T 'vault_none')"
    } else {
        $lines += "  $(T 'vault')      $(T 'vault_closed')"
    }
    switch ($bl) {
        'on'  { $lines += "  $(T 'bl')  $(T 'on')" }
        'off' { $lines += "  $(T 'bl')  $(T 'off')" }
        default { $lines += "  $(T 'bl')  $(T 'unknown')" }
    }
    switch ($vw) {
        'active' {
            $ttl = Get-PnVaultwatchTtl
            $suffix = if ($ttl) { " — $ttl" } else { '' }
            $lines += "  $(T 'vw') $(T 'vw_active')$suffix"
        }
        'idle' { $lines += "  $(T 'vw') $(T 'vw_idle')" }
        default { }  # absent → строку не показываем
    }
    $lines += ''
    $lines += (Format-PnMenuItem 1 (T 'm_status'))
    if (Test-PnTool 'panic') {
        $lines += "  2) $(T 'm_panic')"
    } else {
        $lines += "  2) $(T 'm_panic') ($(T 'not_installed'))"
    }
    $lines += (Format-PnMenuItem 3 (T 'm_vault')   'securetrash')
    $lines += (Format-PnMenuItem 4 (T 'm_split')   'seedsplit')
    $lines += (Format-PnMenuItem 5 (T 'm_combine') 'seedsplit')
    $lines += (Format-PnMenuItem 6 (T 'm_ghost')   'ghostdraft')
    $lines += (Format-PnMenuItem 7 (T 'm_watch')   'vaultwatch')
    $lines += "  0) $(T 'm_quit')"
    $lines += ''
    return ($lines -join "`n")
}

# Один пункт меню: «(not installed)», если тул отсутствует.
function Format-PnMenuItem {
    param([string]$Num, [string]$Label, [string]$Tool = '')
    if ($Tool -and -not (Test-PnTool $Tool)) {
        return "  $Num) $Label ($(T 'not_installed'))"
    }
    return "  $Num) $Label"
}

# --- ввод (мокается в Pester) ---
function Read-PnLine { param([string]$Prompt) return (Read-Host -Prompt $Prompt) }
function Invoke-PnPause { Read-PnLine "  $(T 'press_enter')" | Out-Null }
function Confirm-Pn {
    param([string]$Prompt)
    return ((Read-PnLine "  $Prompt $(T 'type_yes')") -eq 'yes')
}

# --- действия ---
function Invoke-PnActStatus {
    Invoke-PnTool 'securetrash' @('check')
    if (Test-PnTool 'vaultwatch') { Write-Output ''; Invoke-PnTool 'vaultwatch' @('status') }
    Invoke-PnPause
}
function Invoke-PnActPanic {
    if (-not (Test-PnTool 'panic')) {
        [Console]::Error.WriteLine((T 'install_hint' 'panic' (Get-PnToolRepo 'panic')))
        Invoke-PnPause; return
    }
    if (-not (Confirm-Pn (T 'confirm_panic'))) { Write-Output "  $(T 'cancelled')"; Invoke-PnPause; return }
    $pargs = @('now')
    if (Confirm-Pn (T 'ask_hard')) { $pargs += '--hard' }
    Invoke-PnTool 'panic' $pargs
    Invoke-PnPause
}
function Invoke-PnActVault {
    # Трёхсостоянийно: нет контейнера → создать (иначе пользователь упирался в тупик
    # «нет контейнера» без видимого пути к созданию). securetrash сама спросит размер/пароль.
    switch (Get-PnVaultState) {
        'open'   { Invoke-PnTool 'securetrash' @('vault', 'close') }
        'closed' { Invoke-PnTool 'securetrash' @('vault', 'open') }
        'none'   { Write-Output "  $(T 'vault_setup_hint')"; Invoke-PnTool 'securetrash' @('vault', 'create') }
    }
    Invoke-PnPause
}
function Invoke-PnActSplit   { Invoke-PnTool 'seedsplit' @('split');   Invoke-PnPause }
function Invoke-PnActCombine { Invoke-PnTool 'seedsplit' @('combine'); Invoke-PnPause }
function Invoke-PnActGhost {
    Write-Output "  1) $(T 'ghost_new')"
    Write-Output "  2) $(T 'ghost_pipe')"
    switch (Read-PnLine "  $(T 'choose')") {
        '1' { Invoke-PnTool 'ghostdraft' @('new') }
        '2' { Invoke-PnTool 'ghostdraft' @('pipe') }
        default { }
    }
    Invoke-PnPause
}
function Invoke-PnActWatch {
    $ttl = Read-PnLine "  $(T 'ask_ttl')"
    if ($ttl) { Invoke-PnTool 'vaultwatch' @('start', '--ttl', $ttl, $script:VAULT_VOLUME) }
    else { Invoke-PnTool 'vaultwatch' @('start', $script:VAULT_VOLUME) }
    Invoke-PnPause
}

# Диспетчер одного выбора (Pester зовёт напрямую). Возвращает $true, если пора выходить.
function Invoke-PnDispatch {
    param([string]$Choice)
    switch ($Choice) {
        '1' { Invoke-PnActStatus }
        '2' { Invoke-PnActPanic }
        '3' { Invoke-PnActVault }
        '4' { Invoke-PnActSplit }
        '5' { Invoke-PnActCombine }
        '6' { Invoke-PnActGhost }
        '7' { Invoke-PnActWatch }
        { $_ -in '0', 'q', 'Q' } { return $true }
        default { }   # неверный ввод → перерисовать меню
    }
    return $false
}

function Get-PnUsage {
    return @"
paranoid $PARANOID_VERSION — interactive launcher for the Paranoid Tools ecosystem (Windows).

Usage: paranoid            launch the interactive dashboard
       paranoid version    print the version
       paranoid help       show this help

A thin launcher over the five PowerShell ports (securetrash, vaultwatch, panic,
seedsplit, ghostdraft). It holds no secrets and adds no crypto — it runs the same
signed tools and shows their output (limits and verdicts included) unaltered.
"@
}

function Invoke-PnMain {
    param([string[]]$Argv)
    $cmd = if ($Argv -and $Argv.Count -ge 1) { $Argv[0] } else { '' }
    switch ($cmd) {
        { $_ -in 'version', '-v', '--version' } { Write-Output "paranoid $PARANOID_VERSION"; return }
        { $_ -in 'help', '-h', '--help' }       { Write-Output (Get-PnUsage); return }
        '' { }
        default { [Console]::Error.WriteLine("Unknown command: $cmd"); [Console]::Error.WriteLine((Get-PnUsage)); exit 1 }
    }
    while ($true) {
        Clear-Host
        Write-Output (Get-PnDashboard)
        $choice = Read-PnLine "  $(T 'choose')"
        if ($null -eq $choice) { break }   # EOF/закрытый stdin → чистый выход, не крутимся
        if (Invoke-PnDispatch $choice) { break }
    }
}

# Dot-source guard: при `. paranoid.ps1` (Pester) main НЕ запускается; ST_NO_MAIN=1 тоже глушит.
if ($MyInvocation.InvocationName -ne '.' -and -not $env:ST_NO_MAIN) {
    Invoke-PnMain -Argv $args
}
