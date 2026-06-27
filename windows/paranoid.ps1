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
        'en:m_destroy'    { return 'Destroy the vault (irreversible)' }
        'ru:m_destroy'    { return 'Уничтожить сейф (необратимо)' }
        'en:destroy_na'   { return 'no vault' }       'ru:destroy_na'   { return 'нет сейфа' }
        'en:destroy_hint' { return 'This permanently destroys the vault and everything inside it. securetrash will ask you to confirm with "yes".' }
        'ru:destroy_hint' { return 'Это безвозвратно уничтожит сейф и всё, что внутри. securetrash попросит подтвердить словом «yes».' }
        'en:destroy_none' { return 'No vault to destroy — create one first (menu item 3).' }
        'ru:destroy_none' { return 'Уничтожать нечего — сначала создай сейф (пункт 3).' }
        'en:m_split'      { return 'Split a secret (seedsplit)' }
        'ru:m_split'      { return 'Разбить секрет (seedsplit)' }
        'en:m_combine'    { return 'Combine shares (seedsplit)' }
        'ru:m_combine'    { return 'Собрать из долей (seedsplit)' }
        'en:m_ghost'      { return 'Ghostdraft — ephemeral note / pipe' }
        'ru:m_ghost'      { return 'Ghostdraft — эфемерная заметка / pipe' }
        'en:m_watch'      { return 'Watch vault — guard + TTL (vaultwatch)' }
        'ru:m_watch'      { return 'Сторожить сейф — guard + TTL (vaultwatch)' }
        'en:m_unwatch'    { return 'Stop watching the vault (vaultwatch)' }
        'ru:m_unwatch'    { return 'Снять охрану сейфа (vaultwatch)' }
        'en:m_quit'       { return 'Quit' }         'ru:m_quit'       { return 'Выход' }
        # --- top-level group items (открывают подменю) ---
        'en:m_t_vault'   { return 'Vault >        open / empty / destroy / watch' }
        'ru:m_t_vault'   { return 'Сейф >         открыть / очистить / уничтожить / сторожить' }
        'en:m_t_notepad' { return 'Notepad >      ghostdraft: ephemeral note / clipboard' }
        'ru:m_t_notepad' { return 'Блокнот >      ghostdraft: эфемерная заметка / буфер' }
        'en:m_t_secrets' { return 'Secrets >      seedsplit: split / combine' }
        'ru:m_t_secrets' { return 'Секреты >      seedsplit: разбить / собрать' }
        'en:back'        { return 'Back' }          'ru:back'        { return 'Назад' }
        # --- подменю-заголовки ---
        'en:h_vault'     { return 'Vault — encrypted container' }
        'ru:h_vault'     { return 'Сейф — зашифрованный контейнер' }
        'en:h_notepad'   { return 'Notepad — ephemeral text (ghostdraft)' }
        'ru:h_notepad'   { return 'Блокнот — эфемерный текст (ghostdraft)' }
        'en:h_secrets'   { return 'Secrets — Shamir shares (seedsplit)' }
        'ru:h_secrets'   { return 'Секреты — доли Шамира (seedsplit)' }
        # --- vault submenu: динамический пункт 1 по состоянию ---
        'en:m_v_create'  { return 'Create a vault' }  'ru:m_v_create'  { return 'Создать сейф' }
        'en:m_v_open'    { return 'Open the vault' }   'ru:m_v_open'    { return 'Открыть сейф' }
        'en:m_v_close'   { return 'Close the vault' }  'ru:m_v_close'   { return 'Закрыть сейф' }
        # --- empty (= securetrash vault reset) ---
        'en:m_empty'     { return 'Empty — wipe contents, keep the vault (crypto-shred)' }
        'ru:m_empty'     { return 'Очистить — стереть содержимое, сейф оставить (crypto-shred)' }
        'en:empty_na'    { return 'no vault' }        'ru:empty_na'    { return 'нет сейфа' }
        'en:empty_none'  { return 'No vault to empty — create one first.' }
        'ru:empty_none'  { return 'Очищать нечего — сначала создай сейф.' }
        'en:empty_hint'  { return 'This destroys everything inside and recreates an EMPTY vault — a real crypto-shred guarantee (unlike wiping files in place). securetrash will ask you to confirm with "yes" and set a password for the fresh vault.' }
        'ru:empty_hint'  { return 'Это уничтожит всё внутри и создаст ПУСТОЙ сейф заново — настоящая crypto-shred гарантия (в отличие от перезаписи файлов на месте). securetrash попросит подтвердить «yes» и задать пароль нового сейфа.' }
        # --- выбор размера (Windows: МБ для diskpart; cap, не резерв) ---
        'en:size_prompt' { return 'Vault size cap in MB (e.g. 1024 = 1 GB; empty = default 1024 MB). A ceiling, not reserved space — the VHDX grows as you add files:' }
        'ru:size_prompt' { return 'Потолок размера сейфа в МБ (напр. 1024 = 1 ГБ; пусто = по умолчанию 1024 МБ). Это лимит, не резерв — VHDX растёт по мере добавления файлов:' }
        'en:size_bad'    { return 'Invalid size — use a whole number of megabytes (e.g. 1024, 5120). Cancelled.' }
        'ru:size_bad'    { return 'Неверный размер — целое число мегабайт (напр. 1024, 5120). Отменено.' }
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
        # Windows clipboard НЕ авто-чистится (история Win+V + Cloud Clipboard) — подпись
        # честно отличается от macOS-варианта «auto-wipes after ~20s». Сам ghostdraft Win-порт
        # дополнительно показывает DANGER и просит confirm перед записью в буфер.
        'en:ghost_new_clip' { return 'new + copy to clipboard (no auto-clear on Windows)' }
        'ru:ghost_new_clip' { return 'new + скопировать в буфер (на Windows без авто-очистки)' }
        'en:ghost_clip_hint' { return 'On exit the draft is copied to the clipboard (after a confirmation). Windows has NO auto-clear — Win+V history and Cloud Clipboard keep it — so clear it yourself.' }
        'ru:ghost_clip_hint' { return 'По выходу черновик копируется в буфер (после подтверждения). На Windows авто-очистки НЕТ — история Win+V и Cloud Clipboard его хранят — чисти сам.' }
        # Подсказки ввода (паритет с bash). На Windows конец ввода — Ctrl-Z затем Enter (НЕ Ctrl-D).
        'en:split_prompt'    { return 'Paste the secret, then press Ctrl-Z and Enter:' }
        'ru:split_prompt'    { return 'Вставь секрет, затем нажми Ctrl-Z и Enter:' }
        'en:combine_prompt'  { return 'Paste the shares — one per line — then press Ctrl-Z and Enter:' }
        'ru:combine_prompt'  { return 'Вставь доли — по одной на строку — затем нажми Ctrl-Z и Enter:' }
        'en:ghost_pipe_hint' { return 'Paste text, then Ctrl-Z and Enter — nothing is written to disk:' }
        'ru:ghost_pipe_hint' { return 'Вставь текст, затем Ctrl-Z и Enter — на диск ничего не пишется:' }
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
    # Группы-подменю (3–5). Top-level короткий: чтение (1) и тревога (2) — мгновенно наверху;
    # остальное сгруппировано. Пункты внутри подменю гасятся при отсутствии тула, поэтому
    # группы тут всегда активны. $v/$vw используются в рендере подменю, не здесь.
    $lines += "  3) $(T 'm_t_vault')"
    $lines += "  4) $(T 'm_t_notepad')"
    $lines += "  5) $(T 'm_t_secrets')"
    $lines += "  0) $(T 'm_quit')"
    $lines += ''
    return ($lines -join "`n")
}

# Текст подменю «Сейф» (Pester проверяет динамический пункт 1, гейтинг empty/destroy, toggle).
function Get-PnVaultMenu {
    $script:VAULT_VOLUME = Get-PnVaultMount
    $v  = Get-PnVaultState
    $vw = Get-PnVaultwatchState
    $lines = @()
    $lines += ''
    $lines += "  $(T 'h_vault')"
    $lines += ''
    # 1 — динамический по состоянию (нет → создать; закрыт → открыть; открыт → закрыть)
    switch ($v) {
        'none'   { $lines += (Format-PnMenuItem 1 (T 'm_v_create') 'securetrash') }
        'closed' { $lines += (Format-PnMenuItem 1 (T 'm_v_open')   'securetrash') }
        'open'   { $lines += (Format-PnMenuItem 1 (T 'm_v_close')  'securetrash') }
    }
    # 2 Empty (reset) — серый при отсутствии securetrash / сейфа
    if (-not (Test-PnTool 'securetrash')) {
        $lines += "  2) $(T 'm_empty') ($(T 'not_installed'))"
    } elseif ($v -eq 'none') {
        $lines += "  2) $(T 'm_empty') ($(T 'empty_na'))"
    } else {
        $lines += "  2) $(T 'm_empty')"
    }
    # 3 Destroy — серый при отсутствии securetrash / сейфа
    if (-not (Test-PnTool 'securetrash')) {
        $lines += "  3) $(T 'm_destroy') ($(T 'not_installed'))"
    } elseif ($v -eq 'none') {
        $lines += "  3) $(T 'm_destroy') ($(T 'destroy_na'))"
    } else {
        $lines += "  3) $(T 'm_destroy')"
    }
    # 4 Watch — toggle
    if ($vw -eq 'active') {
        $lines += (Format-PnMenuItem 4 (T 'm_unwatch') 'vaultwatch')
    } else {
        $lines += (Format-PnMenuItem 4 (T 'm_watch')   'vaultwatch')
    }
    $lines += "  0) $(T 'back')"
    $lines += ''
    return ($lines -join "`n")
}

# Текст подменю «Блокнот» (ghostdraft).
function Get-PnNotepadMenu {
    $lines = @()
    $lines += ''
    $lines += "  $(T 'h_notepad')"
    $lines += ''
    $lines += (Format-PnMenuItem 1 (T 'ghost_new')      'ghostdraft')
    $lines += (Format-PnMenuItem 2 (T 'ghost_pipe')     'ghostdraft')
    $lines += (Format-PnMenuItem 3 (T 'ghost_new_clip') 'ghostdraft')
    $lines += "  0) $(T 'back')"
    $lines += ''
    return ($lines -join "`n")
}

# Текст подменю «Секреты» (seedsplit).
function Get-PnSecretsMenu {
    $lines = @()
    $lines += ''
    $lines += "  $(T 'h_secrets')"
    $lines += ''
    $lines += (Format-PnMenuItem 1 (T 'm_split')   'seedsplit')
    $lines += (Format-PnMenuItem 2 (T 'm_combine') 'seedsplit')
    $lines += "  0) $(T 'back')"
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
# Спросить потолок размера нового сейфа (Windows: целое МБ для diskpart). Возвращает строку
# размера; '' = дефолт тула; $null = неверный ввод (caller отменяет create/reset). VHDX тонкий
# → это лимит, не резерв. Мокается в Pester.
function Read-PnVaultSize {
    $size = Read-PnLine "  $(T 'size_prompt')"
    if (-not $size) { return '' }
    if ($size -notmatch '^\d+$') {
        # ВАЖНО: сообщение в stderr, НЕ Write-Output — иначе строка попала бы в пайплайн
        # возврата и $sz стал бы массивом @(msg,$null), а не $null (caller не отменил бы create).
        [Console]::Error.WriteLine("  $(T 'size_bad')")
        return $null
    }
    return $size
}
function Invoke-PnActVault {
    # Трёхсостоянийно: нет контейнера → создать (спросив размер-cap); закрыт → открыть; открыт → закрыть.
    switch (Get-PnVaultState) {
        'open'   { Invoke-PnTool 'securetrash' @('vault', 'close') }
        'closed' { Invoke-PnTool 'securetrash' @('vault', 'open') }
        'none'   {
            Write-Output "  $(T 'vault_setup_hint')"
            $sz = Read-PnVaultSize
            if ($null -ne $sz) {
                $a = @('vault', 'create'); if ($sz) { $a += $sz }
                Invoke-PnTool 'securetrash' $a
            }
        }
    }
    Invoke-PnPause
}
# Уничтожение сейфа — необратимо. Лаунчер предупреждает, но реальное подтверждение (yes)
# и отказ при смонтированном томе с открытыми файлами — на стороне securetrash.
function Invoke-PnActDestroy {
    if (-not (Test-PnTool 'securetrash')) {
        [Console]::Error.WriteLine((T 'install_hint' 'securetrash' (Get-PnToolRepo 'securetrash')))
        Invoke-PnPause; return
    }
    if ((Get-PnVaultState) -eq 'none') {
        Write-Output "  $(T 'destroy_none')"; Invoke-PnPause; return
    }
    Write-Output "  $(T 'destroy_hint')"
    Invoke-PnTool 'securetrash' @('vault', 'destroy')
    Invoke-PnPause
}
# Очистить сейф = securetrash vault reset (crypto-shred + создать пустой заново). Честная
# гарантия безвозвратности (in-place перезапись на SSD — best-effort: тот же ключ). Запрос
# размера нового сейфа; реальный yes-confirm и пароль — на стороне securetrash.
function Invoke-PnActEmpty {
    if (-not (Test-PnTool 'securetrash')) {
        [Console]::Error.WriteLine((T 'install_hint' 'securetrash' (Get-PnToolRepo 'securetrash')))
        Invoke-PnPause; return
    }
    if ((Get-PnVaultState) -eq 'none') {
        Write-Output "  $(T 'empty_none')"; Invoke-PnPause; return
    }
    Write-Output "  $(T 'empty_hint')"
    $sz = Read-PnVaultSize
    if ($null -ne $sz) {
        $a = @('vault', 'reset'); if ($sz) { $a += $sz }
        Invoke-PnTool 'securetrash' $a
    }
    Invoke-PnPause
}
# seedsplit split/combine молча читают stdin — без подсказки новичок видит пустой курсор
# и не знает, что вставлять и чем завершить ввод (паритет с bash).
function Invoke-PnActSplit   { Write-Output "  $(T 'split_prompt')";   Invoke-PnTool 'seedsplit' @('split');   Invoke-PnPause }
function Invoke-PnActCombine { Write-Output "  $(T 'combine_prompt')"; Invoke-PnTool 'seedsplit' @('combine'); Invoke-PnPause }
# Ghost-действия (из notepad-подменю). new --clipboard: ghostdraft сам показывает DANGER +
# confirm; на Windows авто-очистки буфера НЕТ — лаунчер дублирует caveat честной подписью.
function Invoke-PnActGhostNew  { Invoke-PnTool 'ghostdraft' @('new') }
# pipe читает stdin — подсказываем, что вставить и чем завершить (паритет с bash).
function Invoke-PnActGhostPipe { Write-Output "  $(T 'ghost_pipe_hint')"; Invoke-PnTool 'ghostdraft' @('pipe') }
function Invoke-PnActGhostClip { Write-Output "  $(T 'ghost_clip_hint')"; Invoke-PnTool 'ghostdraft' @('new', '--clipboard') }
function Invoke-PnActWatch {
    # Перечитываем активную букву прямо здесь (как делает Get-PnDashboard): на Windows том
    # монтируется на ПЕРВУЮ свободную букву динамически, и она могла появиться/смениться с
    # прошлого рендера. Без рефреша start/stop рискуют получить устаревший/$null mount.
    $script:VAULT_VOLUME = Get-PnVaultMount
    # Охрана уже активна → действие работает как «снять» (toggle). Иначе из меню её было
    # не выключить (тупик: только старт, без стопа).
    if ((Get-PnVaultwatchState) -eq 'active') {
        Invoke-PnTool 'vaultwatch' @('stop', $script:VAULT_VOLUME)
        Invoke-PnPause; return
    }
    $ttl = Read-PnLine "  $(T 'ask_ttl')"
    if ($ttl) { Invoke-PnTool 'vaultwatch' @('start', '--ttl', $ttl, $script:VAULT_VOLUME) }
    else { Invoke-PnTool 'vaultwatch' @('start', $script:VAULT_VOLUME) }
    Invoke-PnPause
}

# --- диспетчеры подменю (Pester зовёт напрямую). Возвращают $true = «назад». ---
function Invoke-PnVaultDispatch {
    param([string]$Choice)
    switch ($Choice) {
        '1' { Invoke-PnActVault }
        '2' { Invoke-PnActEmpty }
        '3' { Invoke-PnActDestroy }
        '4' { Invoke-PnActWatch }
        { $_ -in '0', 'q', 'Q' } { return $true }
        default { }
    }
    return $false
}
function Invoke-PnNotepadDispatch {
    param([string]$Choice)
    switch ($Choice) {
        '1' { Invoke-PnActGhostNew;  Invoke-PnPause }
        '2' { Invoke-PnActGhostPipe; Invoke-PnPause }
        '3' { Invoke-PnActGhostClip; Invoke-PnPause }
        { $_ -in '0', 'q', 'Q' } { return $true }
        default { }
    }
    return $false
}
function Invoke-PnSecretsDispatch {
    param([string]$Choice)
    switch ($Choice) {
        '1' { Invoke-PnActSplit }
        '2' { Invoke-PnActCombine }
        { $_ -in '0', 'q', 'Q' } { return $true }
        default { }
    }
    return $false
}

# --- циклы подменю (рендер + read + dispatch до «назад»/EOF) ---
function Invoke-PnMenuVault {
    while ($true) {
        Clear-Host
        Write-Output (Get-PnVaultMenu)
        $c = Read-PnLine "  $(T 'choose')"
        if ($null -eq $c) { break }
        if (Invoke-PnVaultDispatch $c) { break }
    }
}
function Invoke-PnMenuNotepad {
    while ($true) {
        Clear-Host
        Write-Output (Get-PnNotepadMenu)
        $c = Read-PnLine "  $(T 'choose')"
        if ($null -eq $c) { break }
        if (Invoke-PnNotepadDispatch $c) { break }
    }
}
function Invoke-PnMenuSecrets {
    while ($true) {
        Clear-Host
        Write-Output (Get-PnSecretsMenu)
        $c = Read-PnLine "  $(T 'choose')"
        if ($null -eq $c) { break }
        if (Invoke-PnSecretsDispatch $c) { break }
    }
}

# Топ-диспетчер (Pester зовёт напрямую). Возвращает $true, если пора выходить.
function Invoke-PnDispatch {
    param([string]$Choice)
    switch ($Choice) {
        '1' { Invoke-PnActStatus }
        '2' { Invoke-PnActPanic }
        '3' { Invoke-PnMenuVault }
        '4' { Invoke-PnMenuNotepad }
        '5' { Invoke-PnMenuSecrets }
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
