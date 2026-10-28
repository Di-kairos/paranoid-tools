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
        'en:elev_ask'     { return 'This needs administrator rights - Windows will ask now. Confirm, and the action runs in its own window.' }
        'ru:elev_ask'     { return 'Для этого нужны права администратора — Windows сейчас спросит. Подтверди, и действие выполнится в отдельном окне.' }
        'en:elev_declined' { return 'The rights prompt was declined - nothing was done. On Windows the vault runs on diskpart and BitLocker, and those need administrator rights.' }
        'ru:elev_declined' { return 'Запрос прав отклонён — ничего не сделано. На Windows сейф работает через diskpart и BitLocker, а им нужны права администратора.' }
        'en:elev_back'    { return 'The elevated window has closed - the state below is re-read now.' }
        'ru:elev_back'    { return 'Окно с правами закрыто — состояние ниже перечитано.' }
        'en:elev_close'   { return 'Press Enter to close this window' }
        'ru:elev_close'   { return 'Нажми Enter, чтобы закрыть это окно' }
        'en:vw_active'    { return 'active' }       'ru:vw_active'    { return 'активен' }
        'en:vw_idle'      { return 'idle' }         'ru:vw_idle'      { return 'нет сессий' }
        # Prefix of the TTL suffix on the vaultwatch line. Read straight from the session file
        # now, so the wording is ours rather than a line scraped out of `vaultwatch status`.
        'en:vw_ttl_left'  { return 'auto-close in' }  'ru:vw_ttl_left'  { return 'авто-закрытие через' }
        'en:panic_declined_partial' { return 'Rights declined - running what needs none: clipboard and screen lock. Encrypted volumes stay as they are; run panic from an administrator console to close them.' }
        'ru:panic_declined_partial' { return 'В правах отказано — делаю то, для чего они не нужны: буфер и блокировка экрана. Шифр-тома остаются как есть; чтобы закрыть их, запусти panic из консоли администратора.' }
        'en:update_avail' { return 'update available:' } 'ru:update_avail' { return 'доступно обновление:' }
        # Shown under the "update available" banner. The Update menu item does the same thing;
        # this line is for someone who wants to run it themselves. (Homebrew is macOS-only, and
        # this used to advertise `brew upgrade` on Windows.)
        'en:update_how'   { return 'to update: pick 6) Update' }
        'ru:update_how'   { return 'обновить: пункт 6) Обновить' }
        # --- consent to the update check (asked once, toggled with item 7) ---
        'en:consent_q'    { return 'Check for updates once a day? That is one request to github.com for the list of releases. GitHub sees your IP address, as with any visit; nothing else is sent. You can change this later with item 7 of the menu.' }
        'ru:consent_q'    { return 'Проверять обновления раз в сутки? Это один запрос к github.com за списком релизов. GitHub видит твой IP-адрес, как при любом заходе на сайт; больше ничего не отправляется. Поменять можно потом — пункт 7 меню.' }
        'en:consent_ask'  { return 'Check for updates? [y/N]' }
        'ru:consent_ask'  { return 'Проверять обновления? [y/N]' }
        'en:m_updchk_on'  { return 'Update check   on: once a day, one request to github.com' }
        'ru:m_updchk_on'  { return 'Автопроверка   вкл: раз в сутки, один запрос к github.com' }
        'en:m_updchk_off' { return 'Update check   off' }
        'ru:m_updchk_off' { return 'Автопроверка   выкл' }
        'en:updchk_env'   { return "PARANOID_UPDATE_CHECK=$A is set in the environment and overrides this switch - change or remove it there." }
        'ru:updchk_env'   { return "В окружении задано PARANOID_UPDATE_CHECK=$A, и оно сильнее этого переключателя — поменяй или убери его там." }
        'en:m_status'     { return 'Status — full read-only check' }
        'ru:m_status'     { return 'Статус — полная проверка (только чтение)' }
        'en:m_panic'      { return 'PANIC NOW — hide & lock everything, hard mode (instant, no confirm)' }
        'ru:m_panic'      { return 'ПАНИКА — спрятать и запереть всё, жёсткий режим (мгновенно, без подтверждения)' }
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
        'en:m_unwatch'    { return 'Stop watching the vault (vaultwatch)' }
        'ru:m_unwatch'    { return 'Снять охрану сейфа (vaultwatch)' }
        'en:m_quit'       { return 'Quit' }         'ru:m_quit'       { return 'Выход' }
        'en:m_update'     { return 'Update         re-run the installer from your clone' }
        'ru:m_update'     { return 'Обновить       перезапустить установщик из твоего клона' }
        'en:upd_src_none' { return 'Cannot find your copy of the repository, and updating runs the installer from it. Get one and install from it once - after that this item works by itself:  git clone https://github.com/Di-kairos/paranoid-tools  then  paranoid-tools\windows\install.cmd  (already have a clone elsewhere? run windows\install.cmd from it, or set PARANOID_SRC to its path).' }
        'ru:upd_src_none' { return 'Не нахожу твою копию репозитория, а обновление запускает установщик именно из неё. Скачай её и один раз поставь оттуда — дальше этот пункт будет работать сам:  git clone https://github.com/Di-kairos/paranoid-tools  затем  paranoid-tools\windows\install.cmd  (клон уже лежит в другом месте? запусти windows\install.cmd из него или укажи путь в PARANOID_SRC).' }
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
        'en:m_t_vault'   { return 'Vault >        open / delete / watch' }
        'ru:m_t_vault'   { return 'Сейф >         открыть / удалить / сторожить' }
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
        'en:m_delete'     { return 'Delete the vault' }
        'ru:m_delete'     { return 'Удалить сейф' }
        'en:delete_na'    { return 'no vault' }       'ru:delete_na'    { return 'нет сейфа' }
        'en:delete_none'  { return 'No vault to delete — create one first.' }
        'ru:delete_none'  { return 'Удалять нечего — сначала создай сейф.' }
        'en:delete_hint'  { return 'Deleting destroys the vault with everything inside. Files are not wiped one by one: on an SSD the old key would still decrypt their leftovers, so the whole container goes, key and all. securetrash will ask you to confirm with "yes".' }
        'ru:delete_hint'  { return 'Удаление уничтожает сейф со всем содержимым. Файлы не стираются по одному: на SSD старый ключ всё ещё расшифрует их остатки, поэтому уходит весь контейнер вместе с ключом. securetrash попросит подтвердить словом «yes».' }
        'en:delete_renew' { return 'Create a new empty vault in its place, with a new password? [Y/n]' }
        'ru:delete_renew' { return 'Создать на его месте новый пустой сейф с новым паролем? [Y/n]' }
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
# The volume table, as cheaply as it can be had. DriveInfo is a .NET call that answers in
# milliseconds; Get-CimInstance Win32_Volume spins up WMI and costs seconds on a cold session -
# and this runs on every redraw of the dashboard, which is what made the menu take five to
# seven seconds to appear (live Windows run, s45). CIM stays as the fallback: it also sees
# volumes mounted into a folder, which DriveInfo does not enumerate.
# $null still means "could not read the table" - the contract's R3, unknown and never closed.
function Get-PnMountPoints {
    # The vault is normally a drive LETTER (securetrash attaches the VHDX to a free one), and a
    # letter is answered by GetLogicalDrives in microseconds - a string list out of the OS, with
    # no device touched. DriveInfo would be nearly as cheap except for .IsReady, which polls the
    # device and can block on an empty optical or a dead network drive - precisely the machine
    # where a panic menu must not stall. Get-CimInstance Win32_Volume spins up WMI and costs
    # seconds on a cold session, and this runs on every redraw: that was most of the five to
    # seven seconds the menu took to appear (live Windows run, s45).
    #
    # CIM is still used, and must be, when the vault is mounted into a FOLDER: GetLogicalDrives
    # does not list those, and answering "closed" over an open vault is the one direction we are
    # never allowed to be wrong in. So the cheap path is taken only for a drive-letter mount.
    $target = [string]$script:VAULT_VOLUME
    $isLetterMount = $target -match '^[A-Za-z]:\\?$'
    if ($isLetterMount -or -not $target) {
        try {
            $names = [System.IO.Directory]::GetLogicalDrives()
            if ($names -and @($names).Count -gt 0) { return @($names) }
        } catch { }
    }
    try {
        $vols = Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop
        if ($null -eq $vols) { return $null }
        return @($vols | ForEach-Object { $_.Name } | Where-Object { $_ })
    } catch { return $null }
}
# A letter in the volume table does not mean the vault is open. Locking a BitLocker volume
# leaves the letter and the table entry exactly where they were - the data goes, the letter
# stays. That is the contract's R5, and the Windows suites had it backwards: their fixtures
# assumed a locked volume drops out of the table. On the live run the dashboard and the tray
# both announced an OPEN vault over a volume panic had just locked (s46).
# One DriveInfo probe of the vault's own letter answers it. .IsReady is the call the table
# enumeration deliberately avoids - it polls the device and can block on an empty optical or a
# dead network drive - but that argument is about asking it of EVERY drive on every redraw, not
# once about the one letter we already care about. Unreadable -> treated as open: announcing
# 'closed' over a live vault is the one direction we are never allowed to be wrong in.
function Test-PnMountUsable {
    param([string]$Mount)
    try {
        if ($Mount -notmatch '^[A-Za-z]:\\?$') { return $true }   # folder mount: nothing cheap to ask
        return ([System.IO.DriveInfo]::new($Mount)).IsReady
    } catch { return $true }
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
            if ($p.TrimEnd('\', '/') -ieq $needle) {
                if (Test-PnMountUsable -Mount $script:VAULT_VOLUME) { return 'open' }
                break   # attached but locked — R5, and the container check below answers 'closed'
            }
        }
    }
    $container = Get-PnVaultContainer
    if ($container -and (Test-Path -LiteralPath $container)) { return 'closed' }
    return 'none'
}
# --- the tray: started by the launcher, so the tools are visibly there ---
# Until s47 nothing started the tray: the installer did not ship it and the launcher did not
# know it existed, so a user who ran `paranoid` saw no icon and could not tell whether Paranoid
# Tools was on the machine at all (Mr.Di, live Windows run). Now `paranoid` brings one up when
# there is none. The tray holds this named mutex for its whole life (gui/windows/paranoid-tray.ps1)
# - asking for it is how we know, in microseconds and without WMI, whether one is already up.
$script:PN_TRAY_MUTEX = 'Local\ParanoidTools.Tray'
function Test-PnTrayRunning {
    try {
        $m = $null
        if ([System.Threading.Mutex]::TryOpenExisting($script:PN_TRAY_MUTEX, [ref]$m)) { $m.Dispose(); return $true }
        return $false
    } catch [System.UnauthorizedAccessException] {
        return $true    # it exists: an elevated tray (login autostart WITH rights) owns it
    } catch {
        return $false
    }
}
# Where the tray script is: next to us when installed (lib\), or in the clone's gui\windows when
# the launcher is run straight from the repository.
function Get-PnTrayScript {
    $candidates = @(
        (Join-Path $PSScriptRoot 'paranoid-tray.ps1'),
        (Join-Path (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'gui') 'windows') 'paranoid-tray.ps1')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}
# Best effort and silent: the launcher is the thing the user asked for, and a tray that cannot
# start must not stand in its way. PARANOID_NO_TRAY=1 turns it off (tests, headless sessions).
function Start-PnTray {
    if ($env:PARANOID_NO_TRAY -eq '1') { return }
    if (Test-PnTrayRunning) { return }
    $tray = Get-PnTrayScript
    if (-not $tray) { return }
    try {
        Start-Process -FilePath 'pwsh' -WindowStyle Hidden `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tray) | Out-Null
    } catch { }
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
function Get-PnBitLockerProtection {
    # Explorer's property system knows the protection state of a volume, answers with no rights
    # and in a millisecond (Get-BitLockerVolume: five seconds to refuse, unelevated - measured on
    # the live VM, s48). 1 = on, 2 = off, 6 = on and locked; anything else is in between.
    # Wrapper for Mock.
    param([string]$MountPoint)
    try { return (New-Object -ComObject Shell.Application).NameSpace($MountPoint).Self.ExtendedProperty('System.Volume.BitLockerProtection') }
    catch { return $null }
}
function Get-PnBitLockerState {
    # A real answer without rights first - the dashboard used to print "unknown" to everyone who
    # did not start it as administrator, which is nearly everyone.
    $p = Get-PnBitLockerProtection -MountPoint $env:SystemDrive
    if ($p -in @(1, 6)) { return 'on' }
    if ($p -eq 2) { return 'off' }
    # Encrypting, decrypting, suspended: in between, and the cmdlet may still say "On" for it.
    # Only a missing answer falls through to the cmdlet (review, s48).
    if ($null -ne $p -and "$p" -ne '') { return 'unknown' }
    # Unelevated, Get-BitLockerVolume cannot answer - it refuses or returns nothing - and it
    # takes its time about it: the BitLocker WMI provider is one of the slow ones, and the
    # dashboard paid for it on every redraw only to print "unknown" anyway. Same verdict,
    # without the wait. Elevated, the call is made and the answer is real.
    if ((Get-PnAdminState) -ne 'yes') { return 'unknown' }
    try {
        $sys = Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.VolumeType -eq 'OperatingSystem' }
        if ($sys -and $sys.ProtectionStatus -eq 'On') { return 'on' }
        if ($sys) { return 'off' }
        return 'unknown'
    } catch { return 'unknown' }
}
# Where vaultwatch keeps its session files (mirror of the tray's Get-PtVwStateDir and of the
# macOS app: all three read the same key=value files the CLI writes).
function Get-PnVwStateDir {
    if ($env:VW_STATE_DIR) { return $env:VW_STATE_DIR }
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
    if (-not $homeDir) { return $null }
    return (Join-Path $homeDir '.vaultwatch\sessions')
}

# Read the sessions directly. This used to run `vaultwatch status` - a whole pwsh process, half
# a second to a second and a half - and then Get-PnVaultwatchTtl ran it a SECOND time for the
# TTL line. Two process starts on every redraw of a menu that is supposed to appear instantly.
# The files are the same source the CLI prints from, and the tray has read them this way since
# it was written. Returns @() when there is no directory or nothing in it.
function Get-PnVaultwatchSessions {
    param([int]$Now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $dir = Get-PnVwStateDir
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return @() }
    $out = @()
    foreach ($f in (Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        # Per-file try/catch: vaultwatch stop may delete a file between listing and reading, and
        # a half-written file must not take the whole dashboard down with it.
        try {
            $kv = @{}
            foreach ($line in (Get-Content -LiteralPath $f.FullName -ErrorAction Stop)) {
                if ($line -match '^\s*([A-Za-z_]+)=(.*)$') { $kv[$Matches[1]] = $Matches[2].Trim() }
            }
            if (-not $kv.ContainsKey('mount')) { continue }
            $ttl = 0; $started = 0
            [void][int]::TryParse([string]$kv['ttl_secs'], [ref]$ttl)
            [void][int]::TryParse([string]$kv['started'], [ref]$started)
            $remaining = if ($ttl -gt 0 -and $started -gt 0) { $started + $ttl - $Now } else { $null }
            $out += [pscustomobject]@{ Mount = $kv['mount']; Remaining = $remaining }
        } catch { }
    }
    return $out
}

function Get-PnVaultwatchState {
    if (-not (Test-PnTool 'vaultwatch')) { return 'absent' }
    try {
        if ((Get-PnVaultwatchSessions).Count -gt 0) { return 'active' } else { return 'idle' }
    } catch { return 'idle' }
}
# TTL line of the active session (for the dashboard). A separate function — so Pester can mock
# it and the dashboard render does not hit the real vaultwatch. Empty if no TTL line / no tool.
function Get-PnVaultwatchTtl {
    try {
        $s = @(Get-PnVaultwatchSessions | Where-Object { $null -ne $_.Remaining }) | Select-Object -First 1
        if (-not $s) { return '' }
        $left = [int]$s.Remaining
        if ($left -lt 0) { $left = 0 }
        $h = [math]::Floor($left / 3600); $m = [math]::Floor(($left % 3600) / 60); $sec = $left % 60
        $span = if ($h -gt 0) { "${h}h ${m}m ${sec}s" } else { "${m}m ${sec}s" }
        return "$(T 'vw_ttl_left') $span"
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

# Where the launcher keeps its own small state: the consent answer and the update cache.
function Get-PnStateDir {
    if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'paranoid-tools') }
    if ($env:HOME) { return (Join-Path $env:HOME '.cache/paranoid-tools') }
    return $null
}

# Consent to the update check: 'on' | 'off' | '' (never asked). PARANOID_UPDATE_CHECK=1/0
# overrides the saved answer both ways, so a managed setup can pin it without the file.
function Get-PnUpdateConsent {
    switch ($env:PARANOID_UPDATE_CHECK) { '1' { return 'on' } '0' { return 'off' } }
    $dir = Get-PnStateDir
    if ($dir) {
        $f = Join-Path $dir 'update-consent'
        if (Test-Path -LiteralPath $f) {
            $v = ([string](Get-Content -LiteralPath $f -TotalCount 1 -ErrorAction SilentlyContinue)).Trim()
            if ($v -in 'on', 'off') { return $v }
        }
    }
    return ''
}

function Set-PnUpdateConsent {
    param([ValidateSet('on', 'off')][string]$Value)
    $dir = Get-PnStateDir
    if (-not $dir) { return }
    try {
        New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'update-consent') -Value $Value -NoNewline -ErrorAction Stop
        # The cached summary was computed under the previous answer.
        Remove-Item -LiteralPath (Join-Path $dir 'update-check') -Force -ErrorAction SilentlyContinue
    } catch { }
}

# Asked once, on the first interactive start. Anything but an explicit yes is a no: the network
# stays off unless the person turns it on. EOF records nothing, so the question comes back.
function Request-PnUpdateConsent {
    if ((Get-PnUpdateConsent) -ne '') { return }
    Write-PnScreen ''
    Write-PnScreen "  $(T 'consent_q')"
    $a = Read-PnLine "  $(T 'consent_ask')"
    if ($null -eq $a) { return }
    $on = ([string]$a).Trim().ToLower() -in 'y', 'yes', 'д', 'да'
    Set-PnUpdateConsent $(if ($on) { 'on' } else { 'off' })
}

# Item 7: flips the saved answer. An environment override would silently win, so we say so.
function Invoke-PnActUpdateCheck {
    if ($env:PARANOID_UPDATE_CHECK -in '1', '0') {
        Write-PnScreen "  $(T 'updchk_env' $env:PARANOID_UPDATE_CHECK)"
        Invoke-PnPause; return
    }
    Set-PnUpdateConsent $(if ((Get-PnUpdateConsent) -eq 'on') { 'off' } else { 'on' })
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
# is not consented to, everything is fresh, or the network is unavailable. The result is cached for 24h.
function Get-PnUpdateSummary {
    if ((Get-PnUpdateConsent) -ne 'on') { return '' }
    $cacheDir = Get-PnStateDir
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
# Time one probe, in milliseconds, and remember it when PARANOID_TIMING=1. The dashboard is
# rebuilt on every keystroke of the menu loop, so "the menu is slow" is always a statement about
# these four calls - and a number settles in one run what a screen recording cannot settle at
# all (live Windows run, s45). Off by default: zero cost, zero output, no timing on the screen
# of someone who did not ask for it.
function Measure-PnProbe {
    param([string]$Name, [scriptblock]$Body)
    if ($env:PARANOID_TIMING -ne '1') { return (& $Body) }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = & $Body
    $sw.Stop()
    if ($null -eq $script:PN_TIMINGS) { $script:PN_TIMINGS = @() }
    $script:PN_TIMINGS += [pscustomobject]@{ Name = $Name; Ms = [int]$sw.Elapsed.TotalMilliseconds }
    return $result
}

function Get-PnDashboard {
    # Re-read the active volume before every render — the letter could have appeared/vanished
    # (securetrash open/close between ticks). Tests set $script:VAULT_VOLUME directly and
    # mock Get-PnVaultState, so the refresh does not affect their verdicts.
    $script:PN_TIMINGS = @()
    $script:VAULT_VOLUME = Measure-PnProbe 'vault mount'   { Get-PnVaultMount }
    $v  = Measure-PnProbe 'vault state'      { Get-PnVaultState }
    $bl = Measure-PnProbe 'bitlocker'        { Get-PnBitLockerState }
    $vw = Measure-PnProbe 'vaultwatch'       { Get-PnVaultwatchState }
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
    # Optional updates line (only with consent and when something newer exists).
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
    $lines += "  7) $(T $(if ((Get-PnUpdateConsent) -eq 'on') { 'm_updchk_on' } else { 'm_updchk_off' }))"
    $lines += "  0) $(T 'm_quit')"
    $lines += ''
    # PARANOID_TIMING=1: what the four state probes cost on THIS machine, in milliseconds.
    # "The menu is slow" is a statement about exactly these, and one line of numbers settles in
    # a single run what a screen recording cannot settle at all.
    if ($env:PARANOID_TIMING -eq '1' -and $script:PN_TIMINGS) {
        $total = ($script:PN_TIMINGS | Measure-Object -Property Ms -Sum).Sum
        $lines += '  timing: ' + (($script:PN_TIMINGS | ForEach-Object { "$($_.Name) $($_.Ms)ms" }) -join ', ') + ", total ${total}ms"
        $lines += ''
    }
    return ($lines -join "`n")
}

# Text of the "Vault" submenu (Pester checks the dynamic item 1, delete gating, toggle).
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
    # 2 Delete — greyed out when securetrash / the vault is missing / state is unknown
    if (-not (Test-PnTool 'securetrash')) {
        $lines += "  2) $(T 'm_delete') ($(T 'not_installed'))"
    } elseif ($v -eq 'none') {
        $lines += "  2) $(T 'm_delete') ($(T 'delete_na'))"
    } elseif ($v -eq 'unknown') {
        $lines += "  2) $(T 'm_delete') ($(T 'vault_state_na'))"
    } else {
        $lines += "  2) $(T 'm_delete')"
    }
    # 3 Watch — toggle
    # 4 Watch — toggle
    if ($vw -eq 'active') {
        $lines += (Format-PnMenuItem 3 (T 'm_unwatch') 'vaultwatch')
    } else {
        $lines += (Format-PnMenuItem 3 (T 'm_watch')   'vaultwatch')
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
    # Rights are asked for, because only an elevated run can close encrypted volumes. They are
    # not a precondition for pressing the button: see the declined branch below.
    # The moment of the press is handed to panic so its report covers the whole path the person
    # waited through - this launcher, the elevated re-launch and the UAC prompt included; its
    # own stopwatch starts after all of that and would flatter us (audit §16.4). One stamp for
    # whichever path ends up running.
    $trig = Get-PnTriggerMs
    $panicArgs = @('now', '--hard', '--trigger-ms', $trig)
    if ((Get-PnAdminState) -eq 'yes') {
        Invoke-PnTool -Tool 'panic' -ToolArgs $panicArgs
        Invoke-PnPause; return
    }
    Write-PnScreen "  $(T 'elev_ask')"
    if (Invoke-PnToolElevated -Tool 'panic' -ToolArgs $panicArgs) {
        Write-PnScreen "  $(T 'elev_back')"
        Invoke-PnPause; return
    }
    # Declined - and for THIS command "nothing was done" is the wrong answer. Clearing the
    # clipboard and locking the screen need no rights at all; only closing BitLocker volumes
    # does. Refusing the prompt used to leave the machine exactly as it was, screen included,
    # which is the opposite of what someone pressing PANIC wants (live Windows run, s45).
    # So the unelevated run happens anyway, and says plainly which half it could not do.
    Write-PnScreen "  $(T 'panic_declined_partial')"
    Invoke-PnTool -Tool 'panic' -ToolArgs $panicArgs
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
# Deleting the vault, in one item. By default a new empty vault takes its place = securetrash
# vault reset (the old container is set aside, the new one created, only then the old one is
# crypto-shredded — no moment without a vault). "n" = securetrash vault destroy, nothing left.
# Two separate items used to lead to the same result (Destroy, then Create), which read as a
# broken menu. The real yes-confirm and the password prompt are on the securetrash side.
function Invoke-PnActDelete {
    if (-not (Test-PnTool 'securetrash')) {
        [Console]::Error.WriteLine((T 'install_hint' 'securetrash' (Get-PnToolRepo 'securetrash')))
        Invoke-PnPause; return
    }
    $v = Get-PnVaultState
    if ($v -eq 'none') {
        Write-PnScreen "  $(T 'delete_none')"; Invoke-PnPause; return
    }
    # An irreversible operation on top of a state we do not know is not our choice.
    if ($v -eq 'unknown') {
        Write-PnScreen "  $(T 'vault_unknown_act')"; Invoke-PnPause; return
    }
    Write-PnScreen "  $(T 'delete_hint')"
    $renew = Read-PnLine "  $(T 'delete_renew')"
    if ($null -eq $renew) { Invoke-PnPause; return }
    if ($renew.Trim() -in @('n', 'no', 'н', 'нет')) {
        Invoke-PnToolAdmin 'securetrash' @('vault', 'destroy')
    } else {
        $sz = Read-PnVaultSize
        if ($null -ne $sz) {
            $a = @('vault', 'reset'); if ($sz) { $a += $sz }
            Invoke-PnToolAdmin 'securetrash' $a
        }
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

# Wall-clock milliseconds, for handing `panic` the moment the person actually asked.
# Wall clock and not a stopwatch: the number has to survive into another process.
function Get-PnTriggerMs {
    return [string][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
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
    # With rights in hand this is the old path exactly, missing-tool hint included: that check
    # lives in Invoke-PnTool, and repeating it here would only add a second place to keep true.
    if ((Get-PnAdminState) -eq 'yes') { Invoke-PnTool -Tool $Tool -ToolArgs $ToolArgs; return }
    # On the elevated path it has to be checked before the prompt: raising UAC to run a command
    # that does not exist asks the user for rights and then wastes them.
    if (-not (Test-PnTool $Tool)) {
        [Console]::Error.WriteLine((T 'install_hint' $Tool (Get-PnToolRepo $Tool)))
        return
    }
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
        '2' { Invoke-PnActDelete }
        '3' { Invoke-PnActWatch }
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
        '7' { Invoke-PnActUpdateCheck }
        { $_ -in '0', 'q', 'Q' } { return $true }
        default { }   # invalid input → redraw the menu
    }
    return $false
}

# --- exposure: the read-only report "where a copy of a secret may already be" ---
#
# Mirror of the macOS `paranoid exposure`, over the channels THREAT-MODEL.md maps in "Where
# Windows copies your text". The one place in the launcher with logic of its own rather than a
# tool call, and still read-only: every probe reads a state and reports it. Nothing is deleted,
# disabled or "fixed", and no ecosystem tool is run — none of the five is read-only.
#
# Each row has exactly one of three states:
#   clear  — nothing of yours is in that channel
#   action — it is there and you can do something about it (the step is named)
#   stuck  — it is there and neither we nor you can take it back; here is why
# A probe that cannot read its state reports `stuck` with "could not read", never `clear`.

# Report copy. Kept out of T() like the macOS _exp_t: T() is launcher chrome, this is long prose.
# RU is written, not translated.
function Get-PnExpText {
    param([string]$Key, [string]$A, [string]$B, [string]$C)
    switch ("$($script:PN_LOCALE):$Key") {
        'en:title'   { return 'PARANOID EXPOSURE — where a copy of a secret may already be on this PC' }
        'ru:title'   { return 'PARANOID EXPOSURE — где на этом компьютере уже может лежать копия секрета' }
        'en:sub'     { return 'Read-only: this report changes nothing. It only says what is already there.' }
        'ru:sub'     { return 'Только чтение: отчёт ничего не меняет. Он лишь называет то, что уже лежит.' }
        'en:sum'     { return ('{0} clear · {1} you can still fix · {2} cannot be taken back' -f $A, $B, $C) }
        'ru:sum'     { return ('чисто: {0} · можно убрать: {1} · уже не вернуть: {2}' -f $A, $B, $C) }
        'en:closing' { return 'The answer to most lines above is the same: a secret that was never outside the vault.' }
        'ru:closing' { return 'Ответ почти на все строки выше один: секрет, который никогда не выходил из сейфа.' }

        'en:bl'      { return 'BitLocker (system drive)' }   'ru:bl' { return 'BitLocker (системный диск)' }
        'en:bl_on'   { return 'on — with the PC powered off the system drive is ciphertext.' }
        'ru:bl_on'   { return 'включён — у выключенного компьютера системный диск лежит шифротекстом.' }
        'en:bl_off'  { return 'off — the whole system drive is plaintext to anyone holding this PC, and every line below is moot until it is on: Settings → Privacy & security → Device encryption (or BitLocker on Pro). Windows Home without device encryption has no switch for this at all.' }
        'ru:bl_off'  { return 'выключен — весь системный диск открыт любому, кто держит этот компьютер, и до включения остальные строки не имеют смысла: «Параметры» → «Конфиденциальность и защита» → «Шифрование устройства» (или BitLocker на Pro). У Windows Home без шифрования устройства такого переключателя нет вовсе.' }
        'en:bl_na'   { return 'could not read the BitLocker state (it is in between — encrypting, decrypting, suspended — or this console has no rights to ask) — treat the drive as plaintext until you have checked: manage-bde -status C: from an administrator console.' }
        'ru:bl_na'   { return 'состояние BitLocker прочитать не удалось (оно промежуточное — шифруется, расшифровывается, приостановлено — или у этой консоли нет прав спросить) — считай диск открытым, пока не проверишь: manage-bde -status C: из консоли администратора.' }

        'en:pf'      { return 'Pagefile' }                    'ru:pf' { return 'Файл подкачки' }
        'en:pf_enc'  { return 'encrypted (EncryptPagingFile) — plaintext paged out of RAM lands there as ciphertext.' }
        'ru:pf_enc'  { return 'зашифрован (EncryptPagingFile) — то, что выгрузили из памяти, попадает туда шифротекстом.' }
        'en:pf_bl'   { return 'sits on the BitLocker-protected system drive — whatever was paged out of RAM is ciphertext while the PC is off. While it runs, anything with administrator rights can read it.' }
        'ru:pf_bl'   { return 'лежит на системном диске под BitLocker — всё, что выгрузили из памяти, у выключенного компьютера шифротекст. Пока он работает, файл может прочитать любой процесс с правами администратора.' }
        'en:pf_pt'   { return 'not encrypted — anything that was in RAM while you worked, a typed secret included, can sit in pagefile.sys in the clear. No userland tool reaches in there; the lever is BitLocker, a system setting none of these tools flips for you.' }
        'ru:pf_pt'   { return 'не зашифрован — всё, что было в памяти во время работы, включая набранный секрет, может лежать в pagefile.sys открытым текстом. Из пользовательского режима туда не дотянуться; рычаг — BitLocker, системная настройка, которую ни один из инструментов за тебя не переключает.' }
        'en:pf_na'   { return 'could not tell whether the pagefile is protected (the BitLocker state is unknown) — assume it is not.' }
        'ru:pf_na'   { return 'понять, защищён ли файл подкачки, не удалось (состояние BitLocker неизвестно) — считай, что нет.' }

        'en:vss'      { return 'Volume Shadow Copies' }       'ru:vss' { return 'Теневые копии (VSS)' }
        'en:vss_none' { return 'none on this machine right now.' }
        'ru:vss_none' { return 'сейчас их нет.' }
        'en:vss_some' { return ('{0} on this machine. A file that sat outside the vault when one was taken is still inside it in full — and a single file cannot be taken out of a shadow copy, only whole copies go (vssadmin delete shadows, from an administrator console), together with the restore point they are for.' -f $A) }
        'ru:vss_some' { return ('их {0}. Файл, лежавший вне сейфа в момент снимка, всё ещё внутри целиком — и вынуть из теневой копии один файл нельзя, удаляются только копии целиком (vssadmin delete shadows, из консоли администратора), вместе с точкой восстановления.' -f $A) }
        'en:vss_na'   { return 'could not count them: Windows lists shadow copies to administrators only, and without rights it answers with an empty list. Do not read that as "none" — run this report from an administrator console to know.' }
        'ru:vss_na'   { return 'посчитать не удалось: Windows показывает теневые копии только администраторам, а без прав отвечает пустым списком. Это не то же самое, что «их нет» — запусти отчёт из консоли администратора, чтобы знать.' }

        'en:srch'     { return 'Windows Search index' }       'ru:srch' { return 'Индекс Windows Search' }
        'en:srch_off' { return 'the indexing service is not running.' }
        'ru:srch_off' { return 'служба индексации не запущена.' }
        'en:srch_on'  { return 'running — names and content of files indexed while they were outside the vault are in the index, and stopping the service now does not remove what is already in it. vaultwatch keeps an open vault out of future indexing; the past is past.' }
        'ru:srch_on'  { return 'работает — имена и содержимое файлов, попавших в индекс, пока они лежали вне сейфа, уже там, и остановка службы сейчас их оттуда не убирает. vaultwatch держит открытый сейф вне будущей индексации; прошлое остаётся прошлым.' }
        'en:srch_na'  { return 'could not read the state of the indexing service (WSearch).' }
        'ru:srch_na'  { return 'состояние службы индексации (WSearch) прочитать не удалось.' }

        'en:od'       { return 'OneDrive' }                   'ru:od' { return 'OneDrive' }
        'en:od_none'  { return 'not set up on this account.' }
        'ru:od_none'  { return 'на этой учётной записи не настроен.' }
        'en:od_on'    { return 'in use — anything you put in the OneDrive folder has left this PC, and no command here reaches the copy on the server or on your other devices.' }
        'ru:od_on'    { return 'используется — всё, что попало в папку OneDrive, уже ушло с этого компьютера, и ни одна здешняя команда не дотянется до копии на сервере и на других устройствах.' }
        'en:od_kfm'   { return ('in use, and {0} live inside it — a file dropped there for a minute was uploaded within that minute. No command here reaches the copy on the server or on your other devices.' -f $A) }
        'ru:od_kfm'   { return ('используется, причём {0} лежат внутри него — файл, брошенный туда на минуту, за эту минуту уехал наверх. Ни одна здешняя команда до копии на сервере и на других устройствах не дотянется.' -f $A) }
        'en:od_desk'  { return 'the Desktop' }                'ru:od_desk' { return 'Рабочий стол' }
        'en:od_docs'  { return 'Documents' }                  'ru:od_docs' { return 'Документы' }
        'en:od_and'   { return ' and ' }                      'ru:od_and'  { return ' и ' }

        'en:hist'      { return 'PowerShell history' }        'ru:hist' { return 'История PowerShell' }
        'en:hist_none' { return 'no PSReadLine history file found.' }
        'ru:hist_none' { return 'файла истории PSReadLine не нашёл.' }
        'en:hist_some' { return ('{0} commands kept in plaintext ({1}). A secret ever pasted into a command line is in there verbatim; the file is readable by anything running as you. Clearing it is yours to do — the launcher will not wipe your history for you.' -f $A, $B) }
        'ru:hist_some' { return ('команд в открытом виде: {0} ({1}). Секрет, однажды вставленный в командную строку, лежит там дословно, и файл читает всё, что запущено от твоего имени. Чистить — твоё решение: лаунчер историю за тебя не стирает.' -f $A, $B) }

        'en:clip'       { return 'Clipboard' }                'ru:clip' { return 'Буфер обмена' }
        'en:clip_off'   { return 'clipboard history (Win+V) is off — Windows keeps only the last copy.' }
        'ru:clip_off'   { return 'журнал буфера (Win+V) выключен — Windows держит только последнюю копию.' }
        'en:clip_hist'  { return 'clipboard history (Win+V) is on — every copy you made, not just the last one, including anything copied out of the vault. Clear it: Win+V → Clear all (pinned items stay; unpin them first), or turn it off in Settings → System → Clipboard. panic now clears it too.' }
        'ru:clip_hist'  { return 'журнал буфера (Win+V) включён — там всё, что ты копировал, а не только последнее, включая скопированное из сейфа. Очистить: Win+V → «Очистить всё» (закреплённые остаются — сначала открепи), или выключить в «Параметры» → «Система» → «Буфер обмена». panic now тоже его чистит.' }
        'en:clip_cloud' { return 'clipboard history syncs across devices (Cloud Clipboard) — what you copied has gone to your Microsoft account and your other devices, and no command here reaches those copies. Turn it off in Settings → System → Clipboard so the next copy stays here.' }
        'ru:clip_cloud' { return 'журнал буфера синхронизируется между устройствами (облачный буфер) — скопированное ушло в учётную запись Microsoft и на другие устройства, и ни одна здешняя команда до тех копий не дотянется. Выключи в «Параметры» → «Система» → «Буфер обмена», чтобы следующая копия осталась здесь.' }

        'en:np'      { return 'Notepad unsaved tabs' }        'ru:np' { return 'Несохранённые вкладки «Блокнота»' }
        'en:np_none' { return 'none held on disk.' }
        'ru:np_none' { return 'на диске их нет.' }
        'en:np_some' { return ('{0} held on disk (TabState) with their full text, surviving reboots — a standard forensic artifact. Close them in Notepad, or turn off Settings → Opening files → Open content from the previous session. Nothing here deletes them: they hold your other notes too.' -f $A) }
        'ru:np_some' { return ('на диске их {0} (TabState), с полным текстом, и они переживают перезагрузку — стандартный форензик-артефакт. Закрой их в «Блокноте» или выключи «Параметры» → «Открытие файлов» → «Открывать содержимое предыдущего сеанса». Отсюда их никто не удаляет: там же лежат твои другие заметки.' -f $A) }
        'en:np_na'   { return 'could not read the Notepad package folder.' }
        'ru:np_na'   { return 'папку пакета «Блокнота» прочитать не удалось.' }

        'en:disk'     { return 'Overwriting on this disk' }   'ru:disk' { return 'Перезапись на этом диске' }
        'en:disk_ssd' { return 'SSD — overwriting a file in place does not reliably destroy the old copy: wear levelling has already moved blocks the controller will not let anyone address. And on NTFS a file under roughly 700 bytes — a seed phrase, a key — lives inside its MFT record, which cipher /w never touches. The real answer is to create the secret inside the vault, never outside it.' }
        'ru:disk_ssd' { return 'SSD — перезапись файла на месте не уничтожает старую копию надёжно: выравнивание износа уже увело блоки, к которым контроллер никого не пустит. А на NTFS файл меньше ~700 байт — seed-фраза, ключ — живёт прямо в своей записи MFT, куда cipher /w не заходит. Настоящий ответ — создавать секрет внутри сейфа, а не снаружи.' }
        'en:disk_hdd' { return 'not an SSD — overwriting in place does what it says, except for one case: on NTFS a file under roughly 700 bytes — a seed phrase, a key — lives inside its MFT record, and cipher /w never touches the MFT. The answer for those is to create them inside the vault.' }
        'ru:disk_hdd' { return 'не SSD — перезапись на месте делает то, что обещает, кроме одного случая: на NTFS файл меньше ~700 байт — seed-фраза, ключ — живёт прямо в записи MFT, а cipher /w MFT не трогает. Для таких файлов ответ — создавать их внутри сейфа.' }
        'en:disk_na'  { return 'could not read the disk type — assume SSD, it is the common case.' }
        'ru:disk_na'  { return 'тип диска прочитать не удалось — считай, что SSD: так чаще всего и есть.' }

        'en:vlt'        { return 'Vault' }                    'ru:vlt' { return 'Сейф' }
        'en:vlt_none'   { return 'not created yet. Everything above describes a machine where secrets live as ordinary files; the vault is the part that ends that. Create it: paranoid → Vault.' }
        'ru:vlt_none'   { return 'ещё не создан. Всё выше описывает машину, где секреты лежат обычными файлами; сейф — это то, что прекращает такое. Создать: paranoid → Сейф.' }
        'en:vlt_closed' { return 'created and closed — its contents are ciphertext right now.' }
        'ru:vlt_closed' { return 'создан и закрыт — его содержимое сейчас шифротекст.' }
        'en:vlt_open'   { return 'open right now. While it is open its files are ordinary files: indexable, shadow-copied, copyable. Close it when you are done: paranoid → Vault.' }
        'ru:vlt_open'   { return 'сейчас открыт. Пока он открыт, его файлы — обычные файлы: их индексируют, захватывают теневые копии, копируют. Закрой, когда закончишь: paranoid → Сейф.' }
        'en:vlt_na'     { return 'state could not be determined (the volume table could not be read).' }
        'ru:vlt_na'     { return 'состояние определить не удалось (таблица томов недоступна).' }
        default { return $Key }
    }
}

# --- probe seams (each wraps one system call for Mock; none of them changes anything) ---

# One registry value, or $null when the key or the value is absent.
function Get-PnRegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}
# Shadow copies: a count, or 'unknown'. Mirror of securetrash's Get-StSnapshotCount — without
# administrator rights the VSS provider returns an EMPTY list rather than an error, and counting
# that as "none" would be lying in the most dangerous direction.
function Get-PnShadowCount {
    if ((Get-PnAdminState) -ne 'yes') { return 'unknown' }
    try { return @(Get-CimInstance -ClassName Win32_ShadowCopy -OperationTimeoutSec 10 -ErrorAction Stop).Count }
    catch { return 'unknown' }
}
function Get-PnSearchState {
    try {
        $s = Get-Service -Name 'WSearch' -ErrorAction Stop
        if ("$($s.Status)" -eq 'Running') { return 'on' } else { return 'off' }
    } catch { return 'unknown' }
}
function Get-PnKnownFolder { param([string]$Name) try { return [Environment]::GetFolderPath($Name) } catch { return '' } }
# PSReadLine keeps one history file per host (ConsoleHost_history.txt, the VS Code host's, ...).
function Get-PnHistoryFiles {
    if (-not $env:APPDATA) { return @() }
    $dir = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -File -Filter '*_history.txt' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
}
# Mirror of panic's Get-PnNotepadTabStateCount: 0 = none / feature off, -1 = could not read.
function Get-PnNotepadTabCount {
    try {
        if (-not $env:LOCALAPPDATA) { return 0 }
        $pkg = Join-Path $env:LOCALAPPDATA 'Packages'
        if (-not (Test-Path -LiteralPath $pkg)) { return 0 }
        $n = 0
        foreach ($d in @(Get-ChildItem -LiteralPath $pkg -Directory -Force -ErrorAction Stop |
                         Where-Object { $_.Name -like 'Microsoft.WindowsNotepad_*' })) {
            $ts = Join-Path $d.FullName 'LocalState\TabState'
            if (-not (Test-Path -LiteralPath $ts)) { continue }
            $n += @(Get-ChildItem -LiteralPath $ts -File -Force -Filter '*.bin' -ErrorAction SilentlyContinue).Count
        }
        return $n
    } catch { return -1 }
}
# Mirror of securetrash's Get-StDiskKind: an unspecified MediaType is 'unknown', never 'hdd'.
function Get-PnDiskKind {
    try {
        $kinds = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object { "$($_.MediaType)" })
        if ($kinds -contains 'SSD') { return 'ssd' }
        if ($kinds -contains 'HDD') { return 'hdd' }
        return 'unknown'
    } catch { return 'unknown' }
}

# --- the rows, in reading order: what protects the disk, what keeps copies, what you typed,
# and finally the vault — the answer to most of the lines above ---
function Get-PnExposureRows {
    $rows = New-Object System.Collections.ArrayList
    function Add-Row([string]$Id, [string]$State, [string]$TitleKey, [string]$Detail) {
        [void]$rows.Add([pscustomobject]@{ id = $Id; state = $State; title = (Get-PnExpText $TitleKey); detail = $Detail })
    }

    $bl = Get-PnBitLockerState
    switch ($bl) {
        'on'    { Add-Row 'bitlocker' 'clear'  'bl' (Get-PnExpText 'bl_on') }
        'off'   { Add-Row 'bitlocker' 'action' 'bl' (Get-PnExpText 'bl_off') }
        default { Add-Row 'bitlocker' 'stuck'  'bl' (Get-PnExpText 'bl_na') }
    }

    # The pagefile lives on the system drive, so BitLocker covers it at rest. EncryptPagingFile
    # (`fsutil behavior set EncryptPagingFile 1`) is the other way to the same place.
    $epf = Get-PnRegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsEncryptPagingFile'
    if ("$epf" -eq '1')    { Add-Row 'pagefile' 'clear' 'pf' (Get-PnExpText 'pf_enc') }
    elseif ($bl -eq 'on')  { Add-Row 'pagefile' 'clear' 'pf' (Get-PnExpText 'pf_bl') }
    elseif ($bl -eq 'off') { Add-Row 'pagefile' 'stuck' 'pf' (Get-PnExpText 'pf_pt') }
    else                   { Add-Row 'pagefile' 'stuck' 'pf' (Get-PnExpText 'pf_na') }

    $vss = Get-PnShadowCount
    if ("$vss" -eq 'unknown') { Add-Row 'shadowcopies' 'stuck' 'vss' (Get-PnExpText 'vss_na') }
    elseif ([int]$vss -gt 0)  { Add-Row 'shadowcopies' 'stuck' 'vss' (Get-PnExpText 'vss_some' "$vss") }
    else                      { Add-Row 'shadowcopies' 'clear' 'vss' (Get-PnExpText 'vss_none') }

    switch (Get-PnSearchState) {
        'on'    { Add-Row 'search' 'stuck' 'srch' (Get-PnExpText 'srch_on') }
        'off'   { Add-Row 'search' 'clear' 'srch' (Get-PnExpText 'srch_off') }
        default { Add-Row 'search' 'stuck' 'srch' (Get-PnExpText 'srch_na') }
    }

    # OneDrive sets these for the signed-in accounts. Known Folder Move shows up as the Desktop
    # or Documents path resolving INSIDE one of them.
    $odRoots = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique)
    if ($odRoots.Count -eq 0) { Add-Row 'onedrive' 'clear' 'od' (Get-PnExpText 'od_none') }
    else {
        $moved = @()
        foreach ($f in @(@('Desktop', 'od_desk'), @('MyDocuments', 'od_docs'))) {
            $p = Get-PnKnownFolder $f[0]
            foreach ($r in $odRoots) { if ($p -and $p.StartsWith("$r\", [StringComparison]::OrdinalIgnoreCase)) { $moved += (Get-PnExpText $f[1]); break } }
        }
        if ($moved.Count -gt 0) { Add-Row 'onedrive' 'stuck' 'od' (Get-PnExpText 'od_kfm' ($moved -join (Get-PnExpText 'od_and'))) }
        else                    { Add-Row 'onedrive' 'stuck' 'od' (Get-PnExpText 'od_on') }
    }

    $total = 0; $names = @()
    foreach ($h in (Get-PnHistoryFiles)) {
        $n = 0
        try { $n = @(Get-Content -LiteralPath $h -ErrorAction Stop).Count } catch { }
        if ($n -le 0) { continue }
        $total += $n
        $names += ($h -replace [regex]::Escape("$env:APPDATA"), '%APPDATA%')
    }
    if ($total -gt 0) { Add-Row 'history' 'action' 'hist' (Get-PnExpText 'hist_some' "$total" ($names -join ', ')) }
    else              { Add-Row 'history' 'clear'  'hist' (Get-PnExpText 'hist_none') }

    # Absent values are the Windows defaults: history off, cloud sync off.
    $clipKey = 'HKCU:\Software\Microsoft\Clipboard'
    if ("$(Get-PnRegValue $clipKey 'EnableCloudClipboard')" -eq '1')       { Add-Row 'clipboard' 'stuck'  'clip' (Get-PnExpText 'clip_cloud') }
    elseif ("$(Get-PnRegValue $clipKey 'EnableClipboardHistory')" -eq '1') { Add-Row 'clipboard' 'action' 'clip' (Get-PnExpText 'clip_hist') }
    else                                                                    { Add-Row 'clipboard' 'clear'  'clip' (Get-PnExpText 'clip_off') }

    $tabs = Get-PnNotepadTabCount
    if ($tabs -lt 0)     { Add-Row 'notepad' 'stuck'  'np' (Get-PnExpText 'np_na') }
    elseif ($tabs -gt 0) { Add-Row 'notepad' 'action' 'np' (Get-PnExpText 'np_some' "$tabs") }
    else                 { Add-Row 'notepad' 'clear'  'np' (Get-PnExpText 'np_none') }

    # Stuck on either disk kind: the MFT-resident case holds on NTFS whatever is under it.
    switch (Get-PnDiskKind) {
        'ssd'   { Add-Row 'disk' 'stuck' 'disk' (Get-PnExpText 'disk_ssd') }
        'hdd'   { Add-Row 'disk' 'stuck' 'disk' (Get-PnExpText 'disk_hdd') }
        default { Add-Row 'disk' 'stuck' 'disk' (Get-PnExpText 'disk_na') }
    }

    switch (Get-PnVaultState) {
        'open'   { Add-Row 'vault' 'action' 'vlt' (Get-PnExpText 'vlt_open') }
        'closed' { Add-Row 'vault' 'clear'  'vlt' (Get-PnExpText 'vlt_closed') }
        'none'   { Add-Row 'vault' 'action' 'vlt' (Get-PnExpText 'vlt_none') }
        default  { Add-Row 'vault' 'stuck'  'vlt' (Get-PnExpText 'vlt_na') }
    }
    return , $rows.ToArray()
}

function Get-PnExposureSummary {
    param([object[]]$Rows)
    $c = @{ clear = 0; action = 0; stuck = 0 }
    foreach ($r in $Rows) { $c[$r.state]++ }
    return $c
}

function Get-PnExposureJson {
    param([object[]]$Rows)
    $s = Get-PnExposureSummary $Rows
    return ([ordered]@{
        tool = 'paranoid'; report = 'exposure'; version = $PARANOID_VERSION; platform = 'windows'
        rows = @($Rows | ForEach-Object { [ordered]@{ id = $_.id; state = $_.state; title = $_.title; detail = $_.detail } })
        summary = [ordered]@{ clear = $s.clear; action = $s.action; stuck = $s.stuck }
    } | ConvertTo-Json -Depth 4 -Compress)
}

# Word-wrap by characters. PowerShell strings count UTF-16 units, so Cyrillic wraps at the
# width the console shows (the reason the macOS twin avoids `fold`).
function Format-PnWrap {
    param([string]$Text, [string]$Indent = '    ', [int]$Width = 76)
    $out = @(); $line = ''
    foreach ($w in ($Text -split ' ' | Where-Object { $_ })) {
        if (-not $line) { $line = $w }
        elseif (($line.Length + 1 + $w.Length) -le $Width) { $line = "$line $w" }
        else { $out += "$Indent$line"; $line = $w }
    }
    if ($line) { $out += "$Indent$line" }
    return $out
}

function Get-PnExposureText {
    param([object[]]$Rows)
    $lines = @('', "  $(Get-PnExpText 'title')", "  $(Get-PnExpText 'sub')", '')
    foreach ($r in $Rows) {
        $sym = switch ($r.state) { 'clear' { '✓' } 'action' { '→' } default { '✕' } }
        $lines += "  $sym $($r.title)"
        $lines += (Format-PnWrap $r.detail)
        $lines += ''
    }
    $s = Get-PnExposureSummary $Rows
    $lines += "  $(Get-PnExpText 'sum' "$($s.clear)" "$($s.action)" "$($s.stuck)")"
    $lines += "  $(Get-PnExpText 'closing')"
    $lines += ''
    return ($lines -join [Environment]::NewLine)
}

# The report as one string, or $null on an unknown option (named on stderr).
function Get-PnExposure {
    param([string[]]$ExpArgs = @())
    $json = $false
    foreach ($a in $ExpArgs) {
        if ($a -eq '--json') { $json = $true }
        else { [Console]::Error.WriteLine("exposure: unknown option: $a"); return $null }
    }
    $rows = Get-PnExposureRows
    if ($json) { return (Get-PnExposureJson $rows) }
    return (Get-PnExposureText $rows)
}

function Get-PnUsage {
    return @"
paranoid $PARANOID_VERSION — interactive launcher for the Paranoid Tools ecosystem (Windows).

Usage: paranoid            launch the interactive dashboard
       paranoid exposure   report where a copy of a secret may already be on this PC
                           (read-only; --json for the same report as data)
       paranoid update     re-run the installer from your clone (same as item 6)
       paranoid delete-vault delete the vault (same as Vault → 2)
       paranoid version    print the version
       paranoid help       show this help

A thin launcher over the five PowerShell ports (securetrash, vaultwatch, panic,
seedsplit, ghostdraft). It holds no secrets and adds no crypto — it runs the same
signed tools and shows their output (limits and verdicts included) unaltered. The one
exception is exposure, which reads this machine's own state and reports it.
"@
}

function Invoke-PnMain {
    param([string[]]$Argv)
    $cmd = if ($Argv -and $Argv.Count -ge 1) { $Argv[0] } else { '' }
    switch ($cmd) {
        { $_ -in 'version', '-v', '--version' } { Write-Output "paranoid $PARANOID_VERSION"; return }
        { $_ -in 'help', '-h', '--help' }       { Write-Output (Get-PnUsage); return }
        'exposure' {
            $expArgs = @(if ($Argv.Count -ge 2) { $Argv[1..($Argv.Count - 1)] } else { @() })
            $report = Get-PnExposure -ExpArgs $expArgs
            if ($null -eq $report) { exit 1 }
            Write-Output $report
            return
        }
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
        # The tray's "Update available" item opens a console on exactly this.
        'update' { Invoke-PnActUpdate; return }
        # The tray's "Delete the vault…" item, for the same reason: the question lives here.
        'delete-vault' { Invoke-PnActDelete; return }
        # Internal: the tray's background check. Respects the consent like the dashboard does,
        # prints nothing; the result lands in the cache the tray reads.
        '_update-check' { Get-PnUpdateSummary | Out-Null; return }
        '' { }
        default { [Console]::Error.WriteLine("Unknown command: $cmd"); [Console]::Error.WriteLine((Get-PnUsage)); exit 1 }
    }
    # Only the interactive launcher starts the tray - not `version`/`help`, and not the
    # _elevated re-entry above, which would otherwise bring up a tray with administrator rights
    # nobody chose to give it.
    Start-PnTray
    Request-PnUpdateConsent
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
