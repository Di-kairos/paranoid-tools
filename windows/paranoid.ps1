# paranoid.ps1 — interactive launcher for the Paranoid Tools ecosystem, Windows mirror (BETA).
# Mirror of the macOS version (bash `paranoid`). Baseline: Windows PowerShell 5.1.
#
# HONESTLY: a thin launcher, not a new tool. Contains no crypto and does NOT touch secrets —
# secrets are entered directly into the relevant CLI. It runs the same five signed PowerShell
# ports (via .cmd shims on PATH) and shows their output as is (Scope & limitations and `check`
# verdicts are not hidden). No global hotkey/daemon here — that is Phase B (native tray).
#
# Zero dependencies beyond PowerShell. Installed tools are looked up on PATH by name; a missing
# tool is shown as "(not installed)" with a hint, not faked.
#
# Launch via the .cmd shim = pwsh 7 (UTF-8 by default), same as the five ports. The syntax is kept
# 5.1-compatible. The dashboard is TEXT-ONLY (no ANSI color): honesty is carried by the text
# ("at risk", "(not installed)"), and the colored dots of the macOS version are Phase B polish, not drift.

$PARANOID_VERSION = '0.1.0'

# Active vault volume. On Windows securetrash picks the FIRST FREE drive letter dynamically
# (Get-StFreeDriveLetter — not a hardcoded V:) and writes it to the sidecar <vault>.vhdx.mount on open.
# We resolve the real letter from there; ST_VAULT_VOLUME overrides it manually. $null = vault closed.
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

# --- i18n (launcher chrome only; the tools localize their own output themselves) ---
function T {
    param([string]$Key, [string]$A, [string]$B)
    switch ("$($script:PN_LOCALE):$Key") {
        'en:title'        { return 'PARANOID TOOLS' }
        'ru:title'        { return 'PARANOID TOOLS' }
        'en:vault'        { return 'Vault:' }       'ru:vault'        { return 'Сейф:' }
        'en:vault_open'   { return 'OPEN' }         'ru:vault_open'   { return 'ОТКРЫТ' }
        'en:vault_closed' { return 'closed' }       'ru:vault_closed' { return 'закрыт' }
        'en:vault_none'   { return 'not set up' }    'ru:vault_none'   { return 'не создан' }
        'en:vault_unknown' { return 'state could not be determined (volume table unreadable)' }
        'ru:vault_unknown' { return 'состояние определить не удалось (таблица томов недоступна)' }
        'en:vault_state_na' { return 'vault state unknown' }
        'ru:vault_state_na' { return 'состояние сейфа неизвестно' }
        'en:vault_unknown_act' { return 'Refusing to guess: the volume table could not be read, so the vault could be open or closed. Run "securetrash vault status" directly.' }
        'ru:vault_unknown_act' { return 'Не гадаю: таблицу томов прочитать не удалось, сейф может быть и открыт, и закрыт. Спроси напрямую: "securetrash vault status".' }
        'en:vault_setup_hint' { return 'No vault yet — creating one (securetrash will ask for size & password).' }
        'ru:vault_setup_hint' { return 'Сейфа ещё нет — создаём (securetrash спросит размер и пароль).' }
        'en:vault_risk'   { return 'at risk while open' } 'ru:vault_risk' { return 'под угрозой, пока открыт' }
        'en:bl'           { return 'BitLocker:' }   'ru:bl'           { return 'BitLocker:' }
        'en:on'           { return 'ON' }           'ru:on'           { return 'ВКЛ' }
        'en:off'          { return 'OFF' }          'ru:off'          { return 'ВЫКЛ' }
        'en:unknown'      { return 'unknown' }      'ru:unknown'      { return 'неизвестно' }
        'en:vw'           { return 'vaultwatch:' }  'ru:vw'           { return 'vaultwatch:' }
        'en:admin'        { return 'Admin:' }        'ru:admin'        { return 'Админ:' }
        'en:admin_yes'    { return 'yes' }           'ru:admin_yes'    { return 'да' }
        'en:admin_no'     { return 'no - vault actions ask Windows for rights when you pick them (one prompt, one click)' }
        'ru:admin_no'     { return 'нет - действия с сейфом сами запросят права у Windows (один запрос, один клик)' }
        'en:elev_ask'     { return 'This needs administrator rights - Windows will ask now. Confirm, and the action runs in its own window; type the vault password there.' }
        'ru:elev_ask'     { return 'Для этого нужны права администратора — Windows сейчас спросит. Подтверди, и действие выполнится в отдельном окне; пароль сейфа вводи там.' }
        'en:elev_declined' { return 'The rights prompt was declined - nothing was done. On Windows the vault runs on diskpart and BitLocker, and those need administrator rights.' }
        'ru:elev_declined' { return 'Запрос прав отклонён — ничего не сделано. На Windows сейф работает через diskpart и BitLocker, а им нужны права администратора.' }
        'en:elev_back'    { return 'The elevated window has closed - the state below is re-read now.' }
        'ru:elev_back'    { return 'Окно с правами закрыто — состояние ниже перечитано.' }
        'en:elev_close'   { return 'Press Enter to close this window' }
        'ru:elev_close'   { return 'Нажми Enter, чтобы закрыть это окно' }
        'en:vw_active'    { return 'active' }       'ru:vw_active'    { return 'активен' }
        'en:vw_idle'      { return 'idle' }         'ru:vw_idle'      { return 'нет сессий' }
        'en:update_avail' { return 'update available:' } 'ru:update_avail' { return 'доступно обновление:' }
        # Shown under the "update available" banner. The Update menu item does the same thing;
        # this line is for someone who wants to run it themselves. (Homebrew is macOS-only, and
        # this used to advertise `brew upgrade` on Windows.)
        'en:update_how'   { return 'to update: git pull in the clone, then windows\install.cmd' }
        'ru:update_how'   { return 'обновить: git pull в клоне, затем windows\install.cmd' }
        'en:m_status'     { return 'Status — full read-only check' }
        'ru:m_status'     { return 'Статус — полная проверка (только чтение)' }
        'en:m_panic'      { return 'PANIC NOW — hide & lock everything, hard mode (instant, no confirm)' }
        'ru:m_panic'      { return 'ПАНИКА — спрятать и запереть всё, жёсткий режим (мгновенно, без подтверждения)' }
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
        'en:m_update'     { return 'Update         re-run the installer from your clone' }
        'ru:m_update'     { return 'Обновить       перезапустить установщик из твоего клона' }
        'en:upd_src_none' { return 'Cannot find the installer. Run it once from your clone of the repo (windows\install.cmd) - after that this menu item will work. Or point PARANOID_SRC at the clone.' }
        'ru:upd_src_none' { return 'Не нахожу установщик. Запусти его один раз из клона репозитория (windows\install.cmd) — после этого пункт меню заработает. Или укажи путь к клону в PARANOID_SRC.' }
        'en:upd_src'      { return "Installer: $A" }
        'ru:upd_src'      { return "Установщик: $A" }
        'en:upd_confirm'  { return 'Pull the latest sources and reinstall all tools?' }
        'ru:upd_confirm'  { return 'Подтянуть свежие исходники и переустановить все тулы?' }
        'en:upd_cancel'   { return 'Cancelled.' }
        'ru:upd_cancel'   { return 'Отменено.' }
        'en:upd_pull'     { return 'Updating the clone...' }
        'ru:upd_pull'     { return 'Обновляю клон…' }
        'en:upd_pull_fail' { return 'git pull did not succeed - see the message above. Continuing with the clone in its current state.' }
        'ru:upd_pull_fail' { return 'git pull не прошёл — причина выше. Продолжаю с клоном в текущем состоянии.' }
        'en:upd_nogit'    { return 'Not a git clone (or git is not on PATH) - reinstalling from the local copy as it is.' }
        'ru:upd_nogit'    { return 'Это не git-клон (или git не в PATH) — переустанавливаю из локальной копии как есть.' }
        'en:upd_run'      { return 'Running the installer from that directory. Downloaded releases are signature-verified; anything already present in the clone is installed as-is.' }
        'ru:upd_run'      { return 'Запускаю установщик из этого каталога. Скачанные релизы проверяются по подписи; то, что уже лежит в клоне, ставится как есть.' }
        'en:upd_stale_src' { return 'Note: the clone itself was not updated - what got installed came from its current state.' }
        'ru:upd_stale_src' { return 'Учти: сам клон обновить не удалось — установилось то, что в нём сейчас.' }
        'en:upd_done'     { return 'Update finished. This launcher process still runs the old code - quit and start it again; an already-open vault also keeps the old script until you close and reopen it.' }
        'ru:upd_done'     { return 'Обновление завершено. Этот процесс лаунчера всё ещё на старом коде — выйди и запусти заново; уже открытый сейф тоже держит старый скрипт, пока не закроешь и не откроешь его.' }
        'en:upd_fail'     { return 'The installer exited with an error - nothing was silently half-done, see the output above.' }
        'ru:upd_fail'     { return 'Установщик завершился с ошибкой — молчаливой полуустановки нет, смотри вывод выше.' }
        # --- top-level group items (open submenus) ---
        'en:m_t_vault'   { return 'Vault >        open / empty / destroy / watch' }
        'ru:m_t_vault'   { return 'Сейф >         открыть / очистить / уничтожить / сторожить' }
        'en:m_t_notepad' { return 'Notepad >      ghostdraft: ephemeral note / clipboard' }
        'ru:m_t_notepad' { return 'Блокнот >      ghostdraft: эфемерная заметка / буфер' }
        'en:m_t_secrets' { return 'Secrets >      seedsplit: split / combine' }
        'ru:m_t_secrets' { return 'Секреты >      seedsplit: разбить / собрать' }
        'en:back'        { return 'Back' }          'ru:back'        { return 'Назад' }
        # --- submenu headers ---
        'en:h_vault'     { return 'Vault — encrypted container' }
        'ru:h_vault'     { return 'Сейф — зашифрованный контейнер' }
        'en:h_notepad'   { return 'Notepad — ephemeral text (ghostdraft)' }
        'ru:h_notepad'   { return 'Блокнот — эфемерный текст (ghostdraft)' }
        'en:h_secrets'   { return 'Secrets — Shamir shares (seedsplit)' }
        'ru:h_secrets'   { return 'Секреты — доли Шамира (seedsplit)' }
        # --- vault submenu: item 1 is dynamic, driven by state ---
        'en:m_v_create'  { return 'Create a vault' }  'ru:m_v_create'  { return 'Создать сейф' }
        'en:m_v_open'    { return 'Open the vault' }   'ru:m_v_open'    { return 'Открыть сейф' }
        'en:m_v_close'   { return 'Close the vault' }  'ru:m_v_close'   { return 'Закрыть сейф' }
        'en:m_v_unknown' { return 'Vault state unknown — ask securetrash' }
        'ru:m_v_unknown' { return 'Состояние сейфа неизвестно — спросить securetrash' }
        # --- empty (= securetrash vault reset) ---
        'en:m_empty'     { return 'Empty — wipe contents, keep the vault (crypto-shred)' }
        'ru:m_empty'     { return 'Очистить — стереть содержимое, сейф оставить (crypto-shred)' }
        'en:empty_na'    { return 'no vault' }        'ru:empty_na'    { return 'нет сейфа' }
        'en:empty_none'  { return 'No vault to empty — create one first.' }
        'ru:empty_none'  { return 'Очищать нечего — сначала создай сейф.' }
        'en:empty_hint'  { return 'This destroys everything inside and recreates an EMPTY vault — a real crypto-shred guarantee (unlike wiping files in place). It runs "securetrash vault reset", NOT "securetrash empty" (that one only clears the ~/SecureTrash drop folder). securetrash will ask you to confirm with "yes" and set a password for the fresh vault.' }
        'ru:empty_hint'  { return 'Это уничтожит всё внутри и создаст ПУСТОЙ сейф заново — настоящая crypto-shred гарантия (в отличие от перезаписи файлов на месте). Запускается «securetrash vault reset», а НЕ «securetrash empty» (та команда лишь чистит папку-приёмник ~/SecureTrash). securetrash попросит подтвердить «yes» и задать пароль нового сейфа.' }
        # --- size choice (Windows: MB for diskpart; a cap, not a reserve) ---
        'en:size_prompt' { return 'Vault size cap in MB (e.g. 1024 = 1 GB; empty = default 1024 MB). A ceiling, not reserved space — the VHDX grows as you add files:' }
        'ru:size_prompt' { return 'Потолок размера сейфа в МБ (напр. 1024 = 1 ГБ; пусто = по умолчанию 1024 МБ). Это лимит, не резерв — VHDX растёт по мере добавления файлов:' }
        'en:size_bad'    { return 'Invalid size — use a whole number of megabytes (e.g. 1024, 5120). Cancelled.' }
        'ru:size_bad'    { return 'Неверный размер — целое число мегабайт (напр. 1024, 5120). Отменено.' }
        'en:not_installed'{ return 'not installed' } 'ru:not_installed'{ return 'не установлен' }
        'en:install_hint' { return "Install ${A}: $B" }   'ru:install_hint' { return "Установить ${A}: $B" }
        'en:choose'       { return 'Choose' }       'ru:choose'       { return 'Выбор' }
        'en:press_enter'  { return 'Press Enter to continue' }
        'ru:press_enter'  { return 'Нажми Enter, чтобы продолжить' }
        'en:ask_ttl'      { return 'Auto-exit after (e.g. 30m, 2h; empty = no timer):' }
        'ru:ask_ttl'      { return 'Авто-выход через (напр. 30m, 2h; пусто = без таймера):' }
        'en:ghost_note'   { return 'note — write, edit, copy; vanishes on exit (clipboard: no auto-clear on Windows)' }
        'ru:ghost_note'   { return 'заметка — написать, править, скопировать; на выходе исчезает (буфер: на Windows без авто-очистки)' }
        'en:ghost_pipe'   { return 'show clipboard — paste & view, write nothing to disk' }
        'ru:ghost_pipe'   { return 'показать буфер — вставь и посмотри, на диск ничего' }
        # The Windows clipboard is NOT auto-cleared (Win+V history + Cloud Clipboard) — the label
        # honestly differs from the macOS variant "auto-wipes after ~20s". The ghostdraft Win port
        # itself additionally shows DANGER and asks for confirm before writing to the clipboard.
        'en:ghost_clip_hint' { return 'On exit the draft is copied to the clipboard (after a confirmation). Windows has NO auto-clear — Win+V history and Cloud Clipboard keep it — so clear it yourself.' }
        'ru:ghost_clip_hint' { return 'По выходу черновик копируется в буфер (после подтверждения). На Windows авто-очистки НЕТ — история Win+V и Cloud Clipboard его хранят — чисти сам.' }
        # Input hints (parity with bash). On Windows end-of-input is Ctrl-Z then Enter (NOT Ctrl-D).
        'en:combine_prompt'  { return 'Paste the shares — one per line — then press Ctrl-Z and Enter:' }
        'ru:combine_prompt'  { return 'Вставь доли — по одной на строку — затем нажми Ctrl-Z и Enter:' }
        'en:ghost_pipe_hint' { return 'Paste text, then Ctrl-Z and Enter — nothing is written to disk:' }
        'ru:ghost_pipe_hint' { return 'Вставь текст, затем Ctrl-Z и Enter — на диск ничего не пишется:' }
        default           { return $Key }
    }
}

# --- ecosystem tools: repo for the install hint ---
# After the monorepo migration all tools live in a single repository.
function Get-PnToolRepo {
    param([string]$Tool)
    # Unknown names still return empty — the tests pin that contract.
    switch ($Tool) {
        'securetrash' { 'https://github.com/Di-kairos/paranoid-tools' }
        'vaultwatch'  { 'https://github.com/Di-kairos/paranoid-tools' }
        'panic'       { 'https://github.com/Di-kairos/paranoid-tools' }
        'seedsplit'   { 'https://github.com/Di-kairos/paranoid-tools' }
        'ghostdraft'  { 'https://github.com/Di-kairos/paranoid-tools' }
        default       { '' }
    }
}

function Test-PnTool { param([string]$Tool) [bool](Get-Command $Tool -ErrorAction SilentlyContinue) }

# Run a tool (via its .cmd shim on PATH) without crashing the loop. No tool → hint. Mocked in Pester.
function Invoke-PnTool {
    param([string]$Tool, [string[]]$ToolArgs = @())
    if (-not (Test-PnTool $Tool)) {
        [Console]::Error.WriteLine((T 'install_hint' $Tool (Get-PnToolRepo $Tool)))
        return
    }
    # Out-Host, not a bare call: the child's stdout would otherwise land in this function's
    # success stream and be eaten by the `if` further up (see Write-PnScreen). Interactive
    # prompts are unaffected — Read-Host in the tool writes to its own host, not to stdout.
    & $Tool @ToolArgs | Out-Host
}

# --- status for the dashboard (read-only; degrades to unknown, never guesses) ---
# Vault container file (securetrash default: ~/SecureVault.vhdx). Tells "closed" apart from "not created".
function Get-PnVaultContainer {
    if ($env:ST_VAULT_PATH) { return $env:ST_VAULT_PATH }
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
    if (-not $homeDir) { return $null }
    return (Join-Path $homeDir 'SecureVault.vhdx')
}
# Mount points of all volumes — drive letters AND folder mount points (`C:\Vault\`).
# A wrapper for Mock. $null = the table could not be read (no CIM cmdlets, WMI refusal,
# insufficient rights) — this is NOT "nothing is mounted".
function Get-PnMountPoints {
    try {
        $vols = Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop
        if ($null -eq $vols) { return $null }
        return @($vols | ForEach-Object { $_.Name } | Where-Object { $_ })
    } catch { return $null }
}
function Get-PnVaultState {
    # Four states: open = the volume is actually in the volume table; closed = the container
    # exists but is not mounted; none = no container yet; unknown = the table could not be read.
    # We ask the table, not `Test-Path`: a vault mounted into a folder leaves the folder in
    # place after eject, and the dashboard would scare with "OPEN · data at risk" over a closed
    # vault (mirror of bash `_status_vault`). Guard against $null/empty (Test-Path '' throws).
    if ($script:VAULT_VOLUME) {
        $points = Get-PnMountPoints
        if ($null -eq $points) { return 'unknown' }
        $needle = ([string]$script:VAULT_VOLUME).TrimEnd('\', '/')
        foreach ($p in $points) {
            if ($p.TrimEnd('\', '/') -ieq $needle) { return 'open' }
        }
    }
    $container = Get-PnVaultContainer
    if ($container -and (Test-Path -LiteralPath $container)) { return 'closed' }
    return 'none'
}
# Administrator rights in this session (wrapper for Mock). Everything the vault menu offers runs
# on diskpart and BitLocker, which Windows gives to administrators only — so an unelevated
# launcher shows a full menu whose every item refuses. The dashboard says it once, up front.
function Get-PnAdminState {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ((New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
                [System.Security.Principal.WindowsBuiltInRole]::Administrator)) { return 'yes' }
        return 'no'
    } catch {
        return 'no'
    }
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
# TTL line of the active session (for the dashboard). A separate function — so Pester can mock
# it and the dashboard render does not hit the real vaultwatch. Empty if no TTL line / no tool.
function Get-PnVaultwatchTtl {
    try {
        $m = & vaultwatch status 2>$null | Select-String -Pattern 'TTL|auto-exit|авто-выход' | Select-Object -First 1
        if ($m) { return $m.ToString().Trim() }
    } catch { }
    return ''
}

# --- opt-in update check (OFF by default; network only with explicit consent) ---
# Privacy contract: no telemetry / background "phoning home". Runs ONLY if
# $env:PARANOID_UPDATE_CHECK='1', does nothing but one fetch of the monorepo's public
# releases.atom feed (covers all five tools in a single request), is throttled by a
# 24h cache and silently skips a tool on any network error.

# Installed tool version as x.y.z (empty if the tool is missing / the version cannot be parsed).
function Get-PnToolVersion {
    param([string]$Tool)
    if (-not (Test-PnTool $Tool)) { return '' }
    try {
        $out = (& $Tool version 2>$null) -join ' '
        if (-not $out) { $out = (& $Tool --version 2>$null) -join ' ' }
        $m = [regex]::Match($out, '\d+\.\d+\.\d+')
        if ($m.Success) { return $m.Value }
    } catch { }
    return ''
}

# The monorepo release feed, fetched at most once per process (one request
# covers all five tools; entries are newest-first). Short timeout: the render
# waits across all tools, the 24h cache makes the slow path rare.
$script:PnReleaseFeed = $null
function Get-PnReleaseFeed {
    if ($null -eq $script:PnReleaseFeed) {
        try {
            $r = Invoke-WebRequest -Uri 'https://github.com/Di-kairos/paranoid-tools/releases.atom' `
                -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
            $script:PnReleaseFeed = [string]$r.Content
        } catch { $script:PnReleaseFeed = '' }
    }
    return $script:PnReleaseFeed
}

# The tool's latest release tag (vX.Y.Z). In tests it is substituted by the
# $env:PARANOID_UPDATE_FEED file (`tool=vX.Y.Z` lines); otherwise the monorepo's
# releases.atom is scanned for the newest <tool>-vX.Y.Z entry.
function Get-PnLatestTag {
    param([string]$Tool)
    if ($env:PARANOID_UPDATE_FEED) {
        if (Test-Path -LiteralPath $env:PARANOID_UPDATE_FEED) {
            foreach ($line in Get-Content -LiteralPath $env:PARANOID_UPDATE_FEED) {
                $kv = $line -split '=', 2
                if ($kv.Count -eq 2 -and $kv[0] -eq $Tool) { return $kv[1].Trim() }
            }
        }
        return ''
    }
    $feed = Get-PnReleaseFeed
    if ($feed -match ('{0}-(v\d+\.\d+\.\d+)' -f [regex]::Escape($Tool))) { return $Matches[1] }
    return ''
}

# true if $Latest (x.y.z) is strictly newer than $Installed. Via [version] — equal is not newer.
function Test-PnVerGt {
    param([string]$Latest, [string]$Installed)
    try { return ([version]$Latest) -gt ([version]$Installed) } catch { return $false }
}

# A "tool inst→latest, …" summary over installed tools with a newer release. Empty if the check
# is disabled, everything is fresh, or the network is unavailable. The result is cached for 24h.
function Get-PnUpdateSummary {
    if ($env:PARANOID_UPDATE_CHECK -ne '1') { return '' }
    $cacheDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'paranoid-tools' }
                elseif ($env:HOME) { Join-Path $env:HOME '.cache/paranoid-tools' } else { $null }
    $cache = if ($cacheDir) { Join-Path $cacheDir 'update-check' } else { $null }
    # A fresh cache (<24h) is returned as is; feed mode (tests) never touches the cache — always recomputes.
    if (-not $env:PARANOID_UPDATE_FEED -and $cache -and (Test-Path -LiteralPath $cache)) {
        $age = (Get-Date) - (Get-Item -LiteralPath $cache).LastWriteTime
        if ($age.TotalSeconds -lt 86400) { return (Get-Content -LiteralPath $cache -Raw -ErrorAction SilentlyContinue) }
    }
    $parts = @()
    foreach ($tool in @('securetrash', 'vaultwatch', 'panic', 'seedsplit', 'ghostdraft')) {
        if (-not (Test-PnTool $tool)) { continue }
        $inst = Get-PnToolVersion $tool
        if (-not $inst) { continue }
        $latest = (Get-PnLatestTag $tool) -replace '^v', ''
        # Only a clean x.y.z: otherwise [version] deems 1.2.0 newer than 1.2 (a false "newer"). Parity with bash.
        if ($latest -notmatch '^\d+\.\d+\.\d+$') { continue }
        if (Test-PnVerGt $latest $inst) { $parts += "$tool $inst$([char]0x2192)$latest" }
    }
    $summary = $parts -join ', '
    if (-not $env:PARANOID_UPDATE_FEED -and $cacheDir) {
        try { New-Item -ItemType Directory -Force -Path $cacheDir -ErrorAction Stop | Out-Null
              Set-Content -LiteralPath $cache -Value $summary -NoNewline -ErrorAction Stop } catch { }
    }
    return $summary
}

# --- dashboard text as a separate function (Pester checks the lines without running the loop) ---
function Get-PnDashboard {
    # Re-read the active volume before every render — the letter could have appeared/vanished
    # (securetrash open/close between ticks). Tests set $script:VAULT_VOLUME directly and
    # mock Get-PnVaultState, so the refresh does not affect their verdicts.
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
    } elseif ($v -eq 'unknown') {
        # A green "closed" over an open vault is the worst possible lie, so the
        # unknown state is called by its name (mirror of the bash dashboard).
        $lines += "  $(T 'vault')      $(T 'vault_unknown')"
    } else {
        $lines += "  $(T 'vault')      $(T 'vault_closed')"
    }
    switch ($bl) {
        'on'  { $lines += "  $(T 'bl')  $(T 'on')" }
        'off' { $lines += "  $(T 'bl')  $(T 'off')" }
        default { $lines += "  $(T 'bl')  $(T 'unknown')" }
    }
    switch (Get-PnAdminState) {
        'yes'   { $lines += "  $(T 'admin')      $(T 'admin_yes')" }
        default { $lines += "  $(T 'admin')      $(T 'admin_no')" }
    }
    switch ($vw) {
        'active' {
            $ttl = Get-PnVaultwatchTtl
            $suffix = if ($ttl) { " — $ttl" } else { '' }
            $lines += "  $(T 'vw') $(T 'vw_active')$suffix"
        }
        'idle' { $lines += "  $(T 'vw') $(T 'vw_idle')" }
        default { }  # absent → do not show the line
    }
    # Optional updates line (only if PARANOID_UPDATE_CHECK=1 and something newer exists).
    $upd = Get-PnUpdateSummary
    if ($upd) {
        $lines += "  $([char]0x2B06) $(T 'update_avail') $upd"
        $lines += "    $(T 'update_how')"
    }
    $lines += ''
    $lines += (Format-PnMenuItem 1 (T 'm_status'))
    if (Test-PnTool 'panic') {
        $lines += "  2) $(T 'm_panic')"
    } else {
        $lines += "  2) $(T 'm_panic') ($(T 'not_installed'))"
    }
    # Submenu groups (3–5). The top level is short: reading (1) and alarm (2) sit right at the
    # top; the rest is grouped. Items inside a submenu are greyed out when a tool is missing,
    # so the groups here are always active. $v/$vw are used in the submenu render, not here.
    $lines += "  3) $(T 'm_t_vault')"
    $lines += "  4) $(T 'm_t_notepad')"
    $lines += "  5) $(T 'm_t_secrets')"
    $lines += "  6) $(T 'm_update')"
    $lines += "  0) $(T 'm_quit')"
    $lines += ''
    return ($lines -join "`n")
}

# Text of the "Vault" submenu (Pester checks the dynamic item 1, empty/destroy gating, toggle).
function Get-PnVaultMenu {
    $script:VAULT_VOLUME = Get-PnVaultMount
    $v  = Get-PnVaultState
    $vw = Get-PnVaultwatchState
    $lines = @()
    $lines += ''
    $lines += "  $(T 'h_vault')"
    $lines += ''
    # 1 — dynamic by state (none → create; closed → open; open → close)
    switch ($v) {
        'none'   { $lines += (Format-PnMenuItem 1 (T 'm_v_create') 'securetrash') }
        'closed' { $lines += (Format-PnMenuItem 1 (T 'm_v_open')   'securetrash') }
        'open'   { $lines += (Format-PnMenuItem 1 (T 'm_v_close')  'securetrash') }
        # State unknown — the item stays visible (otherwise the menu silently loses a line),
        # but it promises not an action, only an honest refusal to guess.
        'unknown' { $lines += (Format-PnMenuItem 1 (T 'm_v_unknown') 'securetrash') }
    }
    # 2 Empty (reset) — greyed out when securetrash / the vault is missing / state is unknown
    if (-not (Test-PnTool 'securetrash')) {
        $lines += "  2) $(T 'm_empty') ($(T 'not_installed'))"
    } elseif ($v -eq 'none') {
        $lines += "  2) $(T 'm_empty') ($(T 'empty_na'))"
    } elseif ($v -eq 'unknown') {
        $lines += "  2) $(T 'm_empty') ($(T 'vault_state_na'))"
    } else {
        $lines += "  2) $(T 'm_empty')"
    }
    # 3 Destroy — greyed out when securetrash / the vault is missing / state is unknown
    if (-not (Test-PnTool 'securetrash')) {
        $lines += "  3) $(T 'm_destroy') ($(T 'not_installed'))"
    } elseif ($v -eq 'none') {
        $lines += "  3) $(T 'm_destroy') ($(T 'destroy_na'))"
    } elseif ($v -eq 'unknown') {
        $lines += "  3) $(T 'm_destroy') ($(T 'vault_state_na'))"
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

# Text of the "Notepad" submenu (ghostdraft).
function Get-PnNotepadMenu {
    $lines = @()
    $lines += ''
    $lines += "  $(T 'h_notepad')"
    $lines += ''
    $lines += (Format-PnMenuItem 1 (T 'ghost_note') 'ghostdraft')
    $lines += (Format-PnMenuItem 2 (T 'ghost_pipe') 'ghostdraft')
    $lines += "  0) $(T 'back')"
    $lines += ''
    return ($lines -join "`n")
}

# Text of the "Secrets" submenu (seedsplit).
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

# A single menu item: "(not installed)" if the tool is missing.
function Format-PnMenuItem {
    param([string]$Num, [string]$Label, [string]$Tool = '')
    if ($Tool -and -not (Test-PnTool $Tool)) {
        return "  $Num) $Label ($(T 'not_installed'))"
    }
    return "  $Num) $Label"
}

# Write a line to the SCREEN, not to the pipeline. This is not a style choice: every menu and
# every action runs inside `if (Invoke-PnDispatch $choice) { break }`, and an `if` condition
# consumes the whole success stream of what it evaluates. Anything written with Write-Output
# from there is swallowed instead of shown — which is exactly what happened: the submenus
# rendered into nothing, and only Read-Host's prompt (which goes to the host directly) was
# visible. Console output bypasses the pipeline, so it reaches the user no matter who called.
function Write-PnScreen { param([string]$Text = '') [Console]::Out.WriteLine($Text) }

# --- input (mocked in Pester) ---
function Read-PnLine { param([string]$Prompt) return (Read-Host -Prompt $Prompt) }
function Invoke-PnPause { Read-PnLine "  $(T 'press_enter')" | Out-Null }

# --- actions ---
function Invoke-PnActStatus {
    Invoke-PnTool 'securetrash' @('check')
    if (Test-PnTool 'vaultwatch') { Write-PnScreen; Invoke-PnTool 'vaultwatch' @('status') }
    Invoke-PnPause
}
function Invoke-PnActPanic {
    if (-not (Test-PnTool 'panic')) {
        [Console]::Error.WriteLine((T 'install_hint' 'panic' (Get-PnToolRepo 'panic')))
        Invoke-PnPause; return
    }
    # Panic mode: INSTANT, no confirmations — speed is the whole point of the button. Always
    # --hard (hide/lock + kill cloud daemons + clear recents). The guard against an accidental
    # press is that the item is explicitly marked "instant", and `panic now` itself requires an explicit verb.
    # Panic is reversible: it is hide & lock, NOT data destruction (for destruction — securetrash).
    # Panic goes through the same path: without rights it cannot lock a single encrypted
    # volume, and a kill-switch that quietly does half its job is worse than one extra click.
    Invoke-PnToolAdmin 'panic' @('now', '--hard')
    Invoke-PnPause
}
# Ask for the size cap of the new vault (Windows: whole MB for diskpart). Returns the size
# string; '' = the tool's default; $null = invalid input (the caller cancels create/reset). The
# VHDX is thin → it is a limit, not a reserve. Mocked in Pester.
function Read-PnVaultSize {
    $size = Read-PnLine "  $(T 'size_prompt')"
    if (-not $size) { return '' }
    if ($size -notmatch '^\d+$') {
        # IMPORTANT: the message goes to stderr, NOT Write-Output — otherwise the line would land in
        # the return pipeline and $sz would become the array @(msg,$null), not $null (the caller would not cancel create).
        [Console]::Error.WriteLine("  $(T 'size_bad')")
        return $null
    }
    return $size
}
function Invoke-PnActVault {
    # Three-state: no container → create (asking for the size cap); closed → open; open → close.
    switch (Get-PnVaultState) {
        'open'   { Invoke-PnToolAdmin 'securetrash' @('vault', 'close') }
        'closed' { Invoke-PnToolAdmin 'securetrash' @('vault', 'open') }
        'unknown' { Write-PnScreen "  $(T 'vault_unknown_act')" }
        'none'   {
            Write-PnScreen "  $(T 'vault_setup_hint')"
            $sz = Read-PnVaultSize
            if ($null -ne $sz) {
                $a = @('vault', 'create'); if ($sz) { $a += $sz }
                Invoke-PnToolAdmin 'securetrash' $a
            }
        }
    }
    Invoke-PnPause
}
# Destroying the vault is irreversible. The launcher warns, but the actual confirmation (yes)
# and the refusal on a mounted volume with open files are on the securetrash side.
function Invoke-PnActDestroy {
    if (-not (Test-PnTool 'securetrash')) {
        [Console]::Error.WriteLine((T 'install_hint' 'securetrash' (Get-PnToolRepo 'securetrash')))
        Invoke-PnPause; return
    }
    $v = Get-PnVaultState
    if ($v -eq 'none') {
        Write-PnScreen "  $(T 'destroy_none')"; Invoke-PnPause; return
    }
    # An irreversible operation on top of a state we do not know is not our choice.
    if ($v -eq 'unknown') {
        Write-PnScreen "  $(T 'vault_unknown_act')"; Invoke-PnPause; return
    }
    Write-PnScreen "  $(T 'destroy_hint')"
    Invoke-PnToolAdmin 'securetrash' @('vault', 'destroy')
    Invoke-PnPause
}
# Emptying the vault = securetrash vault reset (crypto-shred + recreate empty). An honest
# irreversibility guarantee (in-place overwrite on an SSD is best-effort: same key). Asks for
# the new vault's size; the actual yes-confirm and password are on the securetrash side.
function Invoke-PnActEmpty {
    if (-not (Test-PnTool 'securetrash')) {
        [Console]::Error.WriteLine((T 'install_hint' 'securetrash' (Get-PnToolRepo 'securetrash')))
        Invoke-PnPause; return
    }
    $v = Get-PnVaultState
    if ($v -eq 'none') {
        Write-PnScreen "  $(T 'empty_none')"; Invoke-PnPause; return
    }
    if ($v -eq 'unknown') {
        Write-PnScreen "  $(T 'vault_unknown_act')"; Invoke-PnPause; return
    }
    Write-PnScreen "  $(T 'empty_hint')"
    $sz = Read-PnVaultSize
    if ($null -ne $sz) {
        $a = @('vault', 'reset'); if ($sz) { $a += $sz }
        Invoke-PnToolAdmin 'securetrash' $a
    }
    Invoke-PnPause
}
# seedsplit split/combine silently read stdin — without a hint a newcomer sees a blank cursor
# and does not know what to paste and how to end the input (parity with bash).
function Invoke-PnActSplit   { Invoke-PnTool 'seedsplit' @('split');   Invoke-PnPause }
function Invoke-PnActCombine { Write-PnScreen "  $(T 'combine_prompt')"; Invoke-PnTool 'seedsplit' @('combine'); Invoke-PnPause }
# Ghost actions (from the notepad submenu). new --clipboard: ghostdraft itself shows DANGER +
# confirm; on Windows there is NO clipboard auto-clear — the launcher mirrors the caveat with an honest label.
# pipe reads stdin — we hint what to paste and how to finish (parity with bash).
function Invoke-PnActGhostPipe { Write-PnScreen "  $(T 'ghost_pipe_hint')"; Invoke-PnTool 'ghostdraft' @('pipe') }
function Invoke-PnActGhostClip { Write-PnScreen "  $(T 'ghost_clip_hint')"; Invoke-PnTool 'ghostdraft' @('new', '--clipboard') }
function Invoke-PnActWatch {
    # Re-read the active letter right here (as Get-PnDashboard does): on Windows the volume
    # is mounted onto the FIRST free letter dynamically, and it could have appeared/changed
    # since the last render. Without the refresh start/stop risk getting a stale/$null mount.
    $script:VAULT_VOLUME = Get-PnVaultMount
    # The guard is already active → the action works as "stop watching" (toggle). Otherwise it
    # could not be turned off from the menu (a dead end: start only, no stop).
    if ((Get-PnVaultwatchState) -eq 'active') {
        Invoke-PnToolAdmin 'vaultwatch' @('stop', $script:VAULT_VOLUME)
        Invoke-PnPause; return
    }
    # Watching a volume we do not even know is mounted is a guard session around an empty
    # spot: the on-disk state would appear, yet there would be nothing to guard.
    if ((Get-PnVaultState) -eq 'unknown') {
        Write-PnScreen "  $(T 'vault_unknown_act')"; Invoke-PnPause; return
    }
    $ttl = Read-PnLine "  $(T 'ask_ttl')"
    if ($ttl) { Invoke-PnToolAdmin 'vaultwatch' @('start', '--ttl', $ttl, $script:VAULT_VOLUME) }
    else { Invoke-PnToolAdmin 'vaultwatch' @('start', $script:VAULT_VOLUME) }
    Invoke-PnPause
}

# pwsh for the elevated re-launch. The tools are supported on PowerShell 7, and the shim on
# PATH starts it anyway — so the elevated copy must be the same one.
function Get-PnPwshPath {
    $cmd = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return 'pwsh'
}

# Re-launch THIS launcher through UAC to run one tool command, and wait for it to finish.
# $true = the prompt was accepted and the run completed; $false = declined (or it could not
# start), and then nothing happened at all.
#
# Why re-launch ourselves instead of the tool directly: -File takes one known path
# ($PSCommandPath) and plain word arguments, so nothing has to survive a second round of
# quoting. Building a command line for cmd.exe or -Command with a %LOCALAPPDATA% path in it is
# exactly the kind of escaping that breaks on somebody's machine and not on ours.
# Wrapper for Mock — Pester must never open a real UAC prompt.
function Invoke-PnToolElevated {
    param([string]$Tool, [string[]]$ToolArgs = @())
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '_elevated', $Tool) + $ToolArgs
    try {
        Start-Process -FilePath (Get-PnPwshPath) -Verb RunAs -Wait -ArgumentList $argv -ErrorAction Stop | Out-Null
        return $true
    } catch {
        # Declining the UAC prompt surfaces here as a terminating error. Not an anomaly: it is
        # the user saying no, and the honest answer is that nothing was done.
        return $false
    }
}

# Run a tool that cannot work without administrator rights: straight through when this console
# already has them, otherwise through a single UAC prompt. The alternative — telling the user
# to close the window and reopen PowerShell by right-click — is a step nobody should have to
# learn to open their own vault.
function Invoke-PnToolAdmin {
    param([string]$Tool, [string[]]$ToolArgs = @())
    if (-not (Test-PnTool $Tool)) {
        [Console]::Error.WriteLine((T 'install_hint' $Tool (Get-PnToolRepo $Tool)))
        return
    }
    if ((Get-PnAdminState) -eq 'yes') { Invoke-PnTool -Tool $Tool -ToolArgs $ToolArgs; return }
    Write-PnScreen "  $(T 'elev_ask')"
    if (Invoke-PnToolElevated -Tool $Tool -ToolArgs $ToolArgs) {
        Write-PnScreen "  $(T 'elev_back')"
    } else {
        [Console]::Error.WriteLine("  $(T 'elev_declined')")
    }
}

# Does this directory look like our clone? A reparse point (symlink/junction) is refused: a
# substituted target would pass the check while the user still sees the trusted path.
# Mirror of bash _is_clone_dir, with the Windows entry points.
function Test-PnCloneDir {
    param([string]$Dir)
    if (-not $Dir) { return $false }
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return $false }
    foreach ($rel in @('windows\install.cmd', 'windows\install.ps1')) {
        $f = Join-Path $Dir $rel
        $item = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) { return $false }
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
    }
    return $true
}

# Where the installer lives. Order: explicit PARANOID_SRC → the path windows\install.ps1
# recorded at the last install → the directory this script sits in (when run straight from the
# clone). Empty when nothing matched: we say so instead of guessing. Mirror of bash.
function Get-PnUpdateSource {
    if (Test-PnCloneDir $env:PARANOID_SRC) { return $env:PARANOID_SRC }
    if ($env:LOCALAPPDATA) {
        $state = Join-Path $env:LOCALAPPDATA 'paranoid-tools\source'
        if (Test-Path -LiteralPath $state) {
            # Only the CR is stripped: trimming edge whitespace would change the path itself —
            # with a trailing space that is a different directory.
            $src = (Get-Content -LiteralPath $state -TotalCount 1 -ErrorAction SilentlyContinue)
            if ($src) {
                $src = ([string]$src).TrimEnd("`r")
                if (Test-PnCloneDir $src) { return $src }
            }
        }
    }
    # $PSScriptRoot is the installed copy's lib\ directory, so the clone is only found this way
    # when the launcher is run out of the clone itself.
    $own = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    if (Test-PnCloneDir $own) { return $own }
    return ''
}

# Wrappers so Pester can drive the update without a clone or a network. Kept separate on
# purpose: each is one external call, and the logic around them is what needs testing.
function Invoke-PnGitPull { param([string]$Src) & git -C $Src pull --ff-only | Out-Host; return ($LASTEXITCODE -eq 0) }
function Test-PnGitClone  { param([string]$Src)
    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
    & git -C $Src rev-parse --git-dir *> $null
    return ($LASTEXITCODE -eq 0)
}
function Invoke-PnInstaller { param([string]$Src)
    & (Join-Path $Src 'windows\install.cmd') | Out-Host
    return ($LASTEXITCODE -eq 0)
}

# Updating = re-running the installer from the clone: it pulls each tool's latest SIGNED release
# and verifies the signature itself. Deliberately no download logic of our own here — a second,
# unverified path next to the verified one is exactly what this project must not grow.
function Invoke-PnActUpdate {
    $src = Get-PnUpdateSource
    if (-not $src) {
        [Console]::Error.WriteLine("  $(T 'upd_src_none')")
        Invoke-PnPause; return
    }
    Write-PnScreen "  $(T 'upd_src' $src)"
    if ((Read-PnLine "  $(T 'upd_confirm') [yes]") -ne 'yes') {
        Write-PnScreen "  $(T 'upd_cancel')"; Invoke-PnPause; return
    }

    $pulled = $true
    if (Test-PnGitClone $src) {
        Write-PnScreen "  $(T 'upd_pull')"
        # --ff-only: silently overwriting the user's local edits is not allowed.
        if (-not (Invoke-PnGitPull $src)) {
            $pulled = $false
            [Console]::Error.WriteLine("  $(T 'upd_pull_fail')")
        }
    } else {
        $pulled = $false
        [Console]::Error.WriteLine("  $(T 'upd_nogit')")
    }

    Write-PnScreen "  $(T 'upd_run')"
    if (Invoke-PnInstaller $src) {
        # The "update available" banner is cached for a day — after the install it would lie.
        if ($env:LOCALAPPDATA) {
            Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'paranoid-tools\update-check') `
                -Force -ErrorAction SilentlyContinue
        }
        # No "all fresh" claim when the sources could not be pulled: the installer may have run
        # perfectly while the clone stayed exactly as it was.
        if (-not $pulled) { [Console]::Error.WriteLine("  $(T 'upd_stale_src')") }
        Write-PnScreen "  $(T 'upd_done')"
    } else {
        [Console]::Error.WriteLine("  $(T 'upd_fail')")
    }
    Invoke-PnPause
}

# --- submenu dispatchers (Pester calls them directly). They return $true = "back". ---
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
        # The single "note" = new --clipboard: you write/edit, on exit it offers a copy.
        # On Windows there is no clipboard auto-clear → GhostClip prints an honest DANGER caveat.
        '1' { Invoke-PnActGhostClip; Invoke-PnPause }
        '2' { Invoke-PnActGhostPipe; Invoke-PnPause }
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

# --- submenu loops (render + read + dispatch until "back"/EOF) ---
function Invoke-PnMenuVault {
    while ($true) {
        Clear-Host
        Write-PnScreen (Get-PnVaultMenu)
        $c = Read-PnLine "  $(T 'choose')"
        if ($null -eq $c) { break }
        if (Invoke-PnVaultDispatch $c) { break }
    }
}
function Invoke-PnMenuNotepad {
    while ($true) {
        Clear-Host
        Write-PnScreen (Get-PnNotepadMenu)
        $c = Read-PnLine "  $(T 'choose')"
        if ($null -eq $c) { break }
        if (Invoke-PnNotepadDispatch $c) { break }
    }
}
function Invoke-PnMenuSecrets {
    while ($true) {
        Clear-Host
        Write-PnScreen (Get-PnSecretsMenu)
        $c = Read-PnLine "  $(T 'choose')"
        if ($null -eq $c) { break }
        if (Invoke-PnSecretsDispatch $c) { break }
    }
}

# Top dispatcher (Pester calls it directly). Returns $true when it is time to quit.
function Invoke-PnDispatch {
    param([string]$Choice)
    switch ($Choice) {
        '1' { Invoke-PnActStatus }
        '2' { Invoke-PnActPanic }
        '3' { Invoke-PnMenuVault }
        '4' { Invoke-PnMenuNotepad }
        '5' { Invoke-PnMenuSecrets }
        '6' { Invoke-PnActUpdate }
        { $_ -in '0', 'q', 'Q' } { return $true }
        default { }   # invalid input → redraw the menu
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
        # Internal: this is the launcher re-entered through UAC by Invoke-PnToolElevated. It
        # runs exactly one tool command and then waits, so the window does not vanish with its
        # output — and so the vault password can be typed into it.
        '_elevated' {
            $tool = if ($Argv.Count -ge 2) { $Argv[1] } else { '' }
            if (-not $tool) { [Console]::Error.WriteLine('_elevated: no tool given'); exit 1 }
            $toolArgs = @(if ($Argv.Count -ge 3) { $Argv[2..($Argv.Count - 1)] } else { @() })
            Invoke-PnTool -Tool $tool -ToolArgs $toolArgs
            Read-PnLine "  $(T 'elev_close')" | Out-Null
            return
        }
        '' { }
        default { [Console]::Error.WriteLine("Unknown command: $cmd"); [Console]::Error.WriteLine((Get-PnUsage)); exit 1 }
    }
    while ($true) {
        Clear-Host
        Write-PnScreen (Get-PnDashboard)
        $choice = Read-PnLine "  $(T 'choose')"
        if ($null -eq $choice) { break }   # EOF/closed stdin → clean exit, do not spin
        if (Invoke-PnDispatch $choice) { break }
    }
}

# Dot-source guard: under `. paranoid.ps1` (Pester) main does NOT run; ST_NO_MAIN=1 also mutes it.
if ($MyInvocation.InvocationName -ne '.' -and -not $env:ST_NO_MAIN) {
    Invoke-PnMain -Argv $args
}
