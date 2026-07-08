# paranoid-tray.ps1 — нативный system-tray агент Windows поверх тех же подписанных PowerShell-портов
# Paranoid Tools (Фаза B). Зеркало macOS ParanoidBar.
#
# ЧЕСТНОСТЬ (как у Фазы A): tray секретов НЕ держит и крипту НЕ добавляет. Показывает статус и
# запускает те же CLI (securetrash / panic / paranoid) в НОВОМ окне консоли — вывод и ввод пароля
# идут в сам CLI, не через GUI. Convenience-слой, не новый инструмент.
#
# Запуск (Windows, pwsh 7): pwsh -File paranoid-tray.ps1   (живёт в трее до «Quit»).
# Логику меню/статуса можно дот-сорсить под ST_NO_MAIN=1 для Pester (WinForms-цикл не стартует).

# --- статус (только чтение) ---
function Get-PtVaultMount {
    if ($env:ST_VAULT_VOLUME) { return $env:ST_VAULT_VOLUME }
    $home = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
    if (-not $home) { return $null }
    $sidecar = Join-Path $home 'SecureVault.vhdx.mount'
    if (Test-Path -LiteralPath $sidecar) { $m = (Get-Content -LiteralPath $sidecar -Raw).Trim(); if ($m) { return $m } }
    return $null
}
function Get-PtVaultState {
    $m = Get-PtVaultMount
    if ($m -and (Test-Path -LiteralPath $m)) { return 'open' }
    $home = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
    if ($home -and (Test-Path -LiteralPath (Join-Path $home 'SecureVault.vhdx'))) { return 'closed' }
    return 'none'
}

# --- локализация: словарь в коде, зеркало macOS `strings` (ключи 1:1, паритет — Pester).
# Честные формулировки («at risk») переводим без смягчения. ---
$script:PtStrings = @{
    en = @{
        vault_label='Vault:'; vault_open_risk='OPEN — at risk'; vault_closed='closed'; vault_not_setup='not set up'
        fv_label='BitLocker:'; fv_on='ON'; fv_off='off / unknown'
        status_item='Status — full read-only check'; panic_item='PANIC NOW — hide & lock'
        vault_menu='Vault'; vault_close='Close the vault'; vault_open='Open the vault'; vault_create='Create a vault'
        vault_empty='Empty — wipe contents, keep the vault'; vault_destroy='Destroy the vault (irreversible)'
        launcher_item='Open the full launcher (paranoid)'; settings_item='Settings…'; login_item='Start at login'
        setup_item='Setup guide…'; quit_item='Quit Paranoid Bar'
        ttl_expired='TTL expired'; auto_exit_in='auto-exit in'; watching_no_ttl='watching (no TTL)'
        tip_open='Vault is OPEN — at risk while open'; tip_closed='Vault closed'
        notif_ttl_warn='Vault auto-closes in {0}'; notif_ttl_expired='vaultwatch TTL expired — vault is still OPEN'
        notif_long_open='Vault open for 30+ minutes (no vaultwatch)'; notif_panic_arm='Press again to PANIC'
        notif_hotkey_fail='Panic hotkey unavailable (taken by another app)'
        set_vol='Vault volume:'; set_poll='Poll interval (s):'; set_lang='Language:'; set_hotkey='Panic hotkey:'
        set_save='Save'; set_setup_btn='Show setup guide'; hk_off='Off'
        ob_title='Paranoid Bar — Welcome'
        ob_sub='A status bar over the same signed CLIs. Secrets never pass through the GUI.'
        ob_cli_ok='CLIs installed (securetrash, panic, vaultwatch)'; ob_cli_missing='CLIs not found — install first'
        ob_vault_ok='Vault created'; ob_vault_missing='No vault yet'; ob_create_btn='Create vault…'
        ob_hotkey_line='Panic hotkey'; ob_login_line='Start at login'; ob_enable_btn='Enable'
        ob_risk='An open vault is always "at risk" — the GUI never hides that.'; ob_done='Done'
    }
    ru = @{
        vault_label='Сейф:'; vault_open_risk='ОТКРЫТ — под риском'; vault_closed='закрыт'; vault_not_setup='не создан'
        fv_label='BitLocker:'; fv_on='включён'; fv_off='выкл / неизвестно'
        status_item='Статус — полная read-only проверка'; panic_item='ПАНИКА — спрятать и заблокировать'
        vault_menu='Сейф'; vault_close='Закрыть сейф'; vault_open='Открыть сейф'; vault_create='Создать сейф'
        vault_empty='Очистить — стереть содержимое, сейф оставить'; vault_destroy='Уничтожить сейф (необратимо)'
        launcher_item='Открыть полный лаунчер (paranoid)'; settings_item='Настройки…'; login_item='Запускать при входе'
        setup_item='Гид по настройке…'; quit_item='Выйти из Paranoid Bar'
        ttl_expired='TTL истёк'; auto_exit_in='авто-выход через'; watching_no_ttl='наблюдение (без TTL)'
        tip_open='Сейф ОТКРЫТ — под риском, пока открыт'; tip_closed='Сейф закрыт'
        notif_ttl_warn='Сейф авто-закроется через {0}'; notif_ttl_expired='TTL vaultwatch истёк — сейф всё ещё ОТКРЫТ'
        notif_long_open='Сейф открыт дольше 30 минут (без vaultwatch)'; notif_panic_arm='Нажмите ещё раз для ПАНИКИ'
        notif_hotkey_fail='Хоткей паники недоступен (занят другим приложением)'
        set_vol='Том сейфа:'; set_poll='Интервал опроса (с):'; set_lang='Язык:'; set_hotkey='Хоткей паники:'
        set_save='Сохранить'; set_setup_btn='Показать гид'; hk_off='Выкл'
        ob_title='Paranoid Bar — Добро пожаловать'
        ob_sub='Панель статуса поверх тех же подписанных CLI. Секреты через GUI не проходят.'
        ob_cli_ok='CLI установлены (securetrash, panic, vaultwatch)'; ob_cli_missing='CLI не найдены — сначала установите'
        ob_vault_ok='Сейф создан'; ob_vault_missing='Сейф ещё не создан'; ob_create_btn='Создать сейф…'
        ob_hotkey_line='Хоткей паники'; ob_login_line='Запускать при входе'; ob_enable_btn='Включить'
        ob_risk='Открытый сейф всегда «под риском» — GUI этого не прячет.'; ob_done='Готово'
    }
}
# Примечание: fv_label на Windows = BitLocker (честность платформы), на macOS = FileVault.
# Ключ один и тот же — паритет ключей сохранён, значения платформенные.
# notif_hotkey_fail — зеркало macOS-ключа (добавлен ревью T3): честный статус хоткея.

function Resolve-PtLang {
    param([string]$Override = 'system', [string]$SystemLang = (Get-Culture).TwoLetterISOLanguageName)
    if ($Override -in @('en', 'ru')) { return $Override }
    if ($SystemLang -like 'ru*') { return 'ru' } else { return 'en' }
}
function Get-PtL {
    param([Parameter(Mandatory)][string]$Key, [string]$Lang)
    # Language — поле настроек (Task 10), дефолт 'system' → Resolve-PtLang сам решит en/ru по культуре.
    if (-not $Lang) { $Lang = Resolve-PtLang -Override ((Get-PtSettings).Language) }
    $t = $script:PtStrings[$Lang]
    if ($t -and $t.ContainsKey($Key)) { return $t[$Key] } else { return $Key }
}

# Спецификация меню (label + команда CLI). Отдельной функцией → Pester проверяет структуру
# БЕЗ WinForms. '' в Command = разделитель; $null = подменю-заголовок (раскрытие ниже).
function Get-PtMenuSpec {
    # -Lang: один резолв языка на вызов (не 12 чтений settings внутри Get-PtL) + детерминизм
    # в тестах независимо от культуры CI-хоста.
    param([string]$VaultState = (Get-PtVaultState),
          [string]$Lang = (Resolve-PtLang -Override ((Get-PtSettings).Language)))
    $vaultToggle = switch ($VaultState) { 'open' { 'securetrash vault close' } 'closed' { 'securetrash vault open' } default { 'securetrash vault create' } }
    $vaultLabel  = switch ($VaultState) { 'open' { Get-PtL 'vault_close' -Lang $Lang } 'closed' { Get-PtL 'vault_open' -Lang $Lang } default { Get-PtL 'vault_create' -Lang $Lang } }
    # Empty/Destroy имеют смысл только при существующем контейнере (open|closed) — при 'none'
    # грей-аутим, чтобы деструктив не был активен «в пустоту» (P2-7).
    $hasVault = $VaultState -in @('open', 'closed')
    return @(
        [pscustomobject]@{ Label = (Get-PtL 'status_item' -Lang $Lang);   Command = 'securetrash check'; Enabled = $true }
        [pscustomobject]@{ Label = (Get-PtL 'panic_item' -Lang $Lang);    Command = 'panic now';         Enabled = $true }
        [pscustomobject]@{ Label = '-';                              Command = '';                  Enabled = $true }
        [pscustomobject]@{ Label = $vaultLabel;                      Command = $vaultToggle;        Enabled = $true }
        [pscustomobject]@{ Label = (Get-PtL 'vault_empty' -Lang $Lang);   Command = 'securetrash vault reset';   Enabled = $hasVault }
        [pscustomobject]@{ Label = (Get-PtL 'vault_destroy' -Lang $Lang); Command = 'securetrash vault destroy'; Enabled = $hasVault }
        [pscustomobject]@{ Label = '-';                              Command = '';                  Enabled = $true }
        [pscustomobject]@{ Label = (Get-PtL 'launcher_item' -Lang $Lang); Command = 'paranoid';       Enabled = $true }
        [pscustomobject]@{ Label = '-';                              Command = '';                  Enabled = $true }
        [pscustomobject]@{ Label = (Get-PtL 'login_item' -Lang $Lang);    Command = '__autostart__';     Enabled = $true }
        [pscustomobject]@{ Label = (Get-PtL 'settings_item' -Lang $Lang); Command = '__settings__';      Enabled = $true }
        [pscustomobject]@{ Label = (Get-PtL 'setup_item' -Lang $Lang);    Command = '__setup__';         Enabled = $true }
        [pscustomobject]@{ Label = '-';                              Command = '';                  Enabled = $true }
        [pscustomobject]@{ Label = (Get-PtL 'quit_item' -Lang $Lang);     Command = '__quit__';          Enabled = $true }
    )
}

# --- автостарт при логине (HKCU Run; без админ-прав/подписи) ---
# Спецификация ключа реестра отдельной функцией → Pester проверяет её БЕЗ записи в реестр.
function Get-PtAutostartSpec {
    $script = Join-Path $PSScriptRoot 'paranoid-tray.ps1'
    # Полный путь к pwsh, не голый `pwsh`: при логине PATH может не содержать pwsh (особенно
    # WindowStyle Hidden без shell-инициализации) → автостарт тихо ломался. Путь в кавычках
    # (Program Files\PowerShell\7 содержит пробел). Fallback на 'pwsh', если резолв не удался.
    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { $pwshPath = 'pwsh' }
    return [pscustomobject]@{
        Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        Name  = 'ParanoidTray'
        Value = "`"$pwshPath`" -WindowStyle Hidden -File `"$script`""
    }
}
function Test-PtAutostart {
    # ВКЛ только если записанное значение совпадает с ТЕКУЩЕЙ спекой: устаревшая запись
    # (скрипт/pwsh переехал) — это сломанный автостарт, галочку «вкл» он не заслуживает.
    $s = Get-PtAutostartSpec
    $v = (Get-ItemProperty -LiteralPath $s.Path -Name $s.Name -ErrorAction SilentlyContinue).$($s.Name)
    return ($v -eq $s.Value)
}
function Enable-PtAutostart {
    $s = Get-PtAutostartSpec
    Set-ItemProperty -LiteralPath $s.Path -Name $s.Name -Value $s.Value
}
function Disable-PtAutostart {
    $s = Get-PtAutostartSpec
    Remove-ItemProperty -LiteralPath $s.Path -Name $s.Name -ErrorAction SilentlyContinue
}

# --- статус vaultwatch (только чтение тех же session-файлов, что пишет vaultwatch CLI) ---
function Get-PtVwStateDir {
    if ($env:VW_STATE_DIR) { return $env:VW_STATE_DIR }
    $home = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
    if (-not $home) { return $null }
    return (Join-Path $home '.vaultwatch\sessions')
}
# Формат как у vaultwatch CLI (Format-VwDuration): "1h 5m 9s" / "5m 9s".
function Format-PtDuration {
    param([int]$S)
    $h = [math]::Floor($S / 3600); $m = [math]::Floor(($S % 3600) / 60); $sec = $S % 60
    if ($h -gt 0) { return "${h}h ${m}m ${sec}s" } else { return "${m}m ${sec}s" }
}
# Парсим key=value session-файлы (mount/started/ttl_secs). remaining = started+ttl_secs-now;
# $null если ttl_secs=0 (сессия без TTL). -Now параметризован для детерминированных тестов.
function Get-PtVaultwatchSessions {
    param([int]$Now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $dir = Get-PtVwStateDir
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return @() }
    $out = @()
    foreach ($f in (Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        # Per-file try/catch: файл могли удалить между листингом и чтением (vaultwatch stop),
        # либо он записан частично/битый. Один такой файл НЕ должен ронять весь rebuild
        # меню/таймера — просто пропускаем его.
        try {
            $mount = ''; $started = 0L; $ttl = 0L
            foreach ($line in (Get-Content -LiteralPath $f.FullName -ErrorAction Stop)) {
                $i = $line.IndexOf('=')
                if ($i -lt 1) { continue }
                $k = $line.Substring(0, $i); $v = $line.Substring($i + 1)
                switch ($k) {
                    'mount'    { $mount = $v }
                    'started'  { $n = 0L; if ([int64]::TryParse($v, [ref]$n)) { $started = $n } }
                    'ttl_secs' { $n = 0L; if ([int64]::TryParse($v, [ref]$n)) { $ttl = $n } }
                }
            }
            if (-not $mount) { continue }
            $remaining = if ($ttl -gt 0) { [math]::Max(0, $started + $ttl - $Now) } else { $null }
            $out += [pscustomobject]@{ Mount = $mount; Remaining = $remaining }
        } catch { continue }
    }
    return $out
}

# --- уведомления: чистый движок решений (Pester), доставка — NotifyIcon.ShowBalloonTip.
# Правила = спека §2, зеркало Swift decideNotifications: каждое событие один раз за эпизод
# «сейф открыт»; закрытие сейфа сбрасывает эпизод; свежая/продлённая vaultwatch-сессия
# (TTL >= 120с) перевзводит ttl-предупреждения. Имена событий зеркалят macOS — не менять.
function New-PtNotifyState {
    [pscustomobject]@{ TtlWarned = $false; TtlExpiredWarned = $false; LongOpenWarned = $false; OpenSince = $null }
}
function Get-PtNotifyEvents {
    param([bool]$Open, [object]$Ttl, [bool]$HasSessions, [int64]$Now, [Parameter(Mandatory)]$State)
    if (-not $Open) { return [pscustomobject]@{ Events = @(); State = (New-PtNotifyState) } }
    $s = [pscustomobject]@{ TtlWarned = $State.TtlWarned; TtlExpiredWarned = $State.TtlExpiredWarned
                            LongOpenWarned = $State.LongOpenWarned; OpenSince = $State.OpenSince }
    if ($null -eq $s.OpenSince) { $s.OpenSince = $Now }
    $events = @()
    if ($null -ne $Ttl) {
        # новая/продлённая сессия -> перевзвод (зеркало Swift re-arm, ревью T2)
        if ($Ttl -ge 120) { $s.TtlWarned = $false; $s.TtlExpiredWarned = $false }
        if ($Ttl -gt 0 -and $Ttl -lt 120 -and -not $s.TtlWarned) { $events += 'ttl_warn'; $s.TtlWarned = $true }
        if ($Ttl -eq 0 -and -not $s.TtlExpiredWarned) { $events += 'ttl_expired'; $s.TtlExpiredWarned = $true }
    }
    if (-not $HasSessions -and ($Now - $s.OpenSince) -gt 1800 -and -not $s.LongOpenWarned) {
        $events += 'long_open'; $s.LongOpenWarned = $true
    }
    return [pscustomobject]@{ Events = $events; State = $s }
}

# --- глобальный хоткей паники: RegisterHotKey + скрытое message-окно (WM_HOTKEY=0x0312).
# Двойное нажатие в 2с (включительно) → panic now БЕЗ confirm (panic обратим); одиночное —
# взвод + balloon. Чистая логика (окно 2с, маппинг пресетов) — Pester; регистрация — GUI-путь.
# Результат RegisterHotKey не глотаем (зеркало macOS honesty-фикса): фейл → notif_hotkey_fail. ---
function Test-PtPanicShouldFire {
    param([double]$Now, [object]$ArmedAt, [double]$Window = 2.0)
    if ($null -eq $ArmedAt) { return $false }
    return (($Now - [double]$ArmedAt) -le $Window)
}
# MOD_CONTROL=2 MOD_ALT=1 MOD_SHIFT=4 → 7; vk: P=0x50, L=0x4C.
function Get-PtHotkeySpec {
    param([string]$Preset)
    switch ($Preset) {
        'ctrl-alt-shift-p' { return [pscustomobject]@{ Modifiers = 7; Vk = 0x50 } }
        'ctrl-alt-shift-l' { return [pscustomobject]@{ Modifiers = 7; Vk = 0x4C } }
        default { return $null }
    }
}

# --- онбординг: чистые хелперы чеклиста Welcome-окна (зеркало macOS checklistLine/clisInstalled) ---
# Строка чеклиста — чистая для Pester (зеркало Swift checklistLine): ✅+okKey / ❌+missKey.
function Get-PtChecklistLine {
    param([bool]$Ok, [string]$OkKey, [string]$MissKey, [string]$Lang)
    if ($Ok) { return ([char]0x2705 + ' ' + (Get-PtL -Key $OkKey -Lang $Lang)) }
    return ([char]0x274C + ' ' + (Get-PtL -Key $MissKey -Lang $Lang))
}
# Все 3 CLI на PATH? (install.sh ставит комплектом — по одному не проверяем.)
function Test-PtClisInstalled {
    foreach ($t in @('securetrash', 'panic', 'vaultwatch')) {
        if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { return $false }
    }
    return $true
}

# --- настройки трея (override точки монтирования vault + интервал опроса + Фаза B: язык/хоткей/онбординг) ---
# JSON в %APPDATA%\ParanoidTools\settings.json; путь переопределяем через PT_SETTINGS_FILE (тесты).

# Значения ComboBox по индексу (зеркало macOS langValues/hotkeyValues) — один источник правды
# для формы (Show-PtSettingsForm) и для санации в Get/Set-PtSettings.
$script:PtLangValues = @('system', 'en', 'ru')
$script:PtHotkeyValues = @('ctrl-alt-shift-p', 'ctrl-alt-shift-l', 'off')

function Get-PtSettingsFile {
    if ($env:PT_SETTINGS_FILE) { return $env:PT_SETTINGS_FILE }
    $base = if ($env:APPDATA) { $env:APPDATA } elseif ($env:HOME) { Join-Path $env:HOME '.config' } else { $null }
    if (-not $base) { return $null }
    return (Join-Path $base 'ParanoidTools\settings.json')
}
function Get-PtSettings {
    $s = [pscustomobject]@{ VaultVolume = ''; PollSeconds = 15; Language = 'system'
                            PanicHotkey = 'ctrl-alt-shift-p'; Onboarded = $false }
    $f = Get-PtSettingsFile
    if ($f -and (Test-Path -LiteralPath $f)) {
        try {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            if ($null -ne $j.VaultVolume) { $s.VaultVolume = [string]$j.VaultVolume }
            if ($null -ne ($j.PollSeconds -as [int])) { $s.PollSeconds = [int]$j.PollSeconds }
            if ($null -ne $j.Language)    { $s.Language = [string]$j.Language }
            if ($null -ne $j.PanicHotkey) { $s.PanicHotkey = [string]$j.PanicHotkey }
            # -eq $true, не [bool]: рукописное "Onboarded":"false" (строка) через [bool] давало бы $true
            if ($null -ne $j.Onboarded)   { $s.Onboarded = ($j.Onboarded -eq $true) }
        } catch { }   # битый файл → дефолты
    }
    # Clamp в [5, 3600]: руками вписанный в JSON PollSeconds > 3600 иначе бросал на
    # NumericUpDown.Value (Maximum=3600) при открытии settings-панели.
    if ($s.PollSeconds -lt 5) { $s.PollSeconds = 5 } elseif ($s.PollSeconds -gt 3600) { $s.PollSeconds = 3600 }
    # Санация: мусор из руками правленного JSON (или устаревшая версия) → дефолты, тем же
    # принципом, что и clamp у PollSeconds. Lowercase ДО -notin: -notin регистронезависим,
    # а Array.IndexOf в форме — нет ("RU" иначе пережил бы санацию, но форма показала бы System).
    $s.Language = ([string]$s.Language).ToLowerInvariant()
    $s.PanicHotkey = ([string]$s.PanicHotkey).ToLowerInvariant()
    if ($s.Language -notin $script:PtLangValues) { $s.Language = 'system' }
    if ($s.PanicHotkey -notin $script:PtHotkeyValues) { $s.PanicHotkey = 'ctrl-alt-shift-p' }
    return $s
}
function Set-PtSettings {
    param([string]$VaultVolume = '', [int]$PollSeconds = 15, [string]$Language = 'system',
          [string]$PanicHotkey = 'ctrl-alt-shift-p', [bool]$Onboarded = $false)
    if ($PollSeconds -lt 5) { $PollSeconds = 5 } elseif ($PollSeconds -gt 3600) { $PollSeconds = 3600 }
    # Та же санация + lowercase, что в Get-PtSettings: в JSON всегда уходит канонический lowercase.
    $Language = $Language.ToLowerInvariant()
    $PanicHotkey = $PanicHotkey.ToLowerInvariant()
    if ($Language -notin $script:PtLangValues) { $Language = 'system' }
    if ($PanicHotkey -notin $script:PtHotkeyValues) { $PanicHotkey = 'ctrl-alt-shift-p' }
    $f = Get-PtSettingsFile
    if (-not $f) { return }
    $dir = Split-Path -Parent $f
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [pscustomobject]@{ VaultVolume = $VaultVolume; PollSeconds = $PollSeconds; Language = $Language
                       PanicHotkey = $PanicHotkey; Onboarded = $Onboarded } | ConvertTo-Json | Set-Content -LiteralPath $f
}

# Запустить CLI в НОВОМ окне консоли (pwsh) — вывод и ввод секретов идут в сам CLI, не через tray.
function Invoke-PtTool {
    param([string]$Command)
    if (-not $Command -or $Command -eq '__quit__' -or $Command -eq '__autostart__' -or $Command -eq '__settings__' -or $Command -eq '__setup__') { return }
    # Команда фиксирована (из Get-PtMenuSpec), не из пользовательского ввода → инъекций нет.
    Start-Process -FilePath 'pwsh' -ArgumentList @('-NoExit', '-Command', $Command) | Out-Null
}

# WinForms-диалог настроек (только GUI-путь; логика Get/Set-PtSettings тестируется отдельно).
# Возвращает применённые настройки при Save, иначе $null. Секретов не касается — только пути/интервал.
function Show-PtSettingsForm {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $cur = Get-PtSettings
    # Один резолв языка на всю форму (консистентность с T7: не N чтений settings в Get-PtL).
    $lang = Resolve-PtLang -Override $cur.Language

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Paranoid Tools - Settings'
    $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.StartPosition = 'CenterScreen'; $form.ClientSize = New-Object System.Drawing.Size(380, 230)

    $lblVol = New-Object System.Windows.Forms.Label
    $lblVol.Text = (Get-PtL set_vol -Lang $lang); $lblVol.SetBounds(12, 18, 110, 20)
    $tbVol = New-Object System.Windows.Forms.TextBox
    $tbVol.SetBounds(130, 15, 235, 22); $tbVol.Text = $cur.VaultVolume

    $lblPoll = New-Object System.Windows.Forms.Label
    $lblPoll.Text = (Get-PtL set_poll -Lang $lang); $lblPoll.SetBounds(12, 52, 110, 20)
    $nudPoll = New-Object System.Windows.Forms.NumericUpDown
    $nudPoll.SetBounds(130, 49, 70, 22); $nudPoll.Minimum = 5; $nudPoll.Maximum = 3600; $nudPoll.Value = $cur.PollSeconds

    $lblLang = New-Object System.Windows.Forms.Label
    $lblLang.Text = (Get-PtL set_lang -Lang $lang); $lblLang.SetBounds(12, 86, 110, 20)
    $cbLang = New-Object System.Windows.Forms.ComboBox
    $cbLang.DropDownStyle = 'DropDownList'; $cbLang.SetBounds(130, 83, 150, 22)
    [void]$cbLang.Items.AddRange(@('System', 'English', 'Русский'))
    $cbLang.SelectedIndex = [math]::Max(0, $script:PtLangValues.IndexOf($cur.Language))

    $lblHk = New-Object System.Windows.Forms.Label
    $lblHk.Text = (Get-PtL set_hotkey -Lang $lang); $lblHk.SetBounds(12, 120, 110, 20)
    $cbHk = New-Object System.Windows.Forms.ComboBox
    $cbHk.DropDownStyle = 'DropDownList'; $cbHk.SetBounds(130, 117, 150, 22)
    [void]$cbHk.Items.AddRange(@('Ctrl+Alt+Shift+P', 'Ctrl+Alt+Shift+L', (Get-PtL hk_off -Lang $lang)))
    $cbHk.SelectedIndex = [math]::Max(0, $script:PtHotkeyValues.IndexOf($cur.PanicHotkey))

    # Setup guide (Show-PtWelcomeForm, Task 11) — открывает Welcome-чеклист прямо из Settings.
    $setup = New-Object System.Windows.Forms.Button
    $setup.Text = (Get-PtL set_setup_btn -Lang $lang); $setup.SetBounds(12, 185, 150, 28)
    $setup.Add_Click({ Show-PtWelcomeForm })

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = (Get-PtL set_save -Lang $lang); $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK; $ok.SetBounds(190, 190, 80, 28)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $cancel.SetBounds(280, 190, 80, 28)

    $form.Controls.AddRange(@($lblVol, $tbVol, $lblPoll, $nudPoll, $lblLang, $cbLang, $lblHk, $cbHk, $setup, $ok, $cancel))
    $form.AcceptButton = $ok; $form.CancelButton = $cancel

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # Onboarded — из СВЕЖИХ настроек, не из $cur: пока форма открыта, Welcome (Setup-кнопка,
        # T11) мог выставить Onboarded=true — Save со stale $cur воскресил бы онбординг.
        Set-PtSettings -VaultVolume ($tbVol.Text.Trim()) -PollSeconds ([int]$nudPoll.Value) `
            -Language $script:PtLangValues[([math]::Max(0, $cbLang.SelectedIndex))] `
            -PanicHotkey $script:PtHotkeyValues[([math]::Max(0, $cbHk.SelectedIndex))] `
            -Onboarded ((Get-PtSettings).Onboarded)
        return (Get-PtSettings)
    }
    return $null
}

# Welcome-окно (спека §3, зеркало macOS doWelcome/rebuildWelcome): живой чеклист + кнопки-действия.
# Кнопки перерисовывают форму (close + reopen — приемлемо для диалога). Секретов не касается.
function Show-PtWelcomeForm {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $cur = Get-PtSettings
    $lang = Resolve-PtLang -Override $cur.Language

    $form = New-Object System.Windows.Forms.Form
    $form.Text = (Get-PtL ob_title -Lang $lang)
    $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.StartPosition = 'CenterScreen'; $form.ClientSize = New-Object System.Drawing.Size(480, 280)

    $y = 14
    function Add-PtObLabel {
        # -Width 448 (вместо дефолтных 330) — для строк БЕЗ кнопки справа (ob_sub/ob_risk):
        # длинные EN/RU подписи (~74-78 симв.) на 330px обрезались.
        param($Form, [string]$Text, [ref]$Y, [single]$Size = 9, [object]$Color = $null, [int]$Width = 330)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $Text; $l.AutoSize = $false
        $l.SetBounds(16, $Y.Value, $Width, 22)
        $l.Font = New-Object System.Drawing.Font('Segoe UI', $Size)
        if ($Color) { $l.ForeColor = $Color }
        $Form.Controls.Add($l); $Y.Value += 28
    }
    function Add-PtObButton {
        param($Form, [string]$Text, [int]$AtY, [scriptblock]$OnClick)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $Text; $b.SetBounds(352, $AtY - 2, 112, 24)
        $b.Add_Click($OnClick)
        $Form.Controls.Add($b)
    }

    Add-PtObLabel $form '🔒 Paranoid Bar' ([ref]$y) 11
    Add-PtObLabel $form (Get-PtL ob_sub -Lang $lang) ([ref]$y) 8 ([System.Drawing.Color]::Gray) -Width 448
    Add-PtObLabel $form (Get-PtChecklistLine -Ok (Test-PtClisInstalled) -OkKey 'ob_cli_ok' -MissKey 'ob_cli_missing' -Lang $lang) ([ref]$y)
    $hasVault = ((Get-PtVaultState) -ne 'none')
    $vaultY = $y
    Add-PtObLabel $form (Get-PtChecklistLine -Ok $hasVault -OkKey 'ob_vault_ok' -MissKey 'ob_vault_missing' -Lang $lang) ([ref]$y)
    if (-not $hasVault) {
        Add-PtObButton $form (Get-PtL ob_create_btn -Lang $lang) $vaultY { Invoke-PtTool -Command 'securetrash vault create' }
    }
    # хоткей: подпись по РЕАЛЬНОМУ пресету (P/L), готовность = пресет включён И регистрация реально
    # прошла ($script:hotkeyRegistered, T9) — зеркало honesty-фикса macOS T4 (не глотать RegisterHotKey).
    $preset = $cur.PanicHotkey
    $hkLabel = if ($preset -eq 'ctrl-alt-shift-l') { 'Ctrl+Alt+Shift+L' } else { 'Ctrl+Alt+Shift+P' }
    $hkOn = ($null -ne (Get-PtHotkeySpec -Preset $preset)) -and $script:hotkeyRegistered
    $mark = if ($hkOn) { [char]0x2705 } else { [char]0x2B1C }
    $hkY = $y
    Add-PtObLabel $form ("$mark " + (Get-PtL ob_hotkey_line -Lang $lang) + ": $hkLabel (" + [char]0x00D7 + '2)') ([ref]$y)
    if (-not $hkOn) {
        Add-PtObButton $form (Get-PtL ob_enable_btn -Lang $lang) $hkY {
            # ASSUMPTION (зеркало macOS obEnableHotkey): Enable всегда включает дефолт P;
            # восстановление прежнего пресета — территория Settings.
            $s = Get-PtSettings
            Set-PtSettings -VaultVolume $s.VaultVolume -PollSeconds $s.PollSeconds -Language $s.Language `
                -PanicHotkey 'ctrl-alt-shift-p' -Onboarded $s.Onboarded
            # $script:hotkeyWin существует только внутри работающего трея (Start-PtTray) — Welcome
            # всегда открывается из этого контекста (first-run/меню/Settings), так что он на месте.
            $ok = $false
            if ($script:hotkeyWin) {
                $spec = Get-PtHotkeySpec -Preset 'ctrl-alt-shift-p'
                $ok = $script:hotkeyWin.Register($spec.Modifiers, $spec.Vk)
                $script:hotkeyRegistered = $ok
            }
            # Ресинк открытого Settings-комбо (зеркало macOS obEnableHotkey → hotkeyPopup):
            # Welcome вызван из Settings → его Save иначе молча откатил бы новый пресет.
            # Индекс 0 = 'ctrl-alt-shift-p' в $script:PtHotkeyValues.
            $cb = Get-Variable cbHk -ValueOnly -ErrorAction SilentlyContinue
            if ($cb) { $cb.SelectedIndex = 0 }
            # Фейл регистрации не глотаем (зеркало macOS notify): balloon через $notify трея,
            # если он в области видимости (Welcome открыт из живого Start-PtTray).
            $n = Get-Variable notify -ValueOnly -ErrorAction SilentlyContinue
            if ($n -and -not $ok) {
                $n.ShowBalloonTip(5000, 'Paranoid Tools', (Get-PtL notif_hotkey_fail -Lang $lang), [System.Windows.Forms.ToolTipIcon]::Warning)
            }
            $form.Close(); Show-PtWelcomeForm
        }
    }
    $loginOn = [bool](Test-PtAutostart)
    $mark = if ($loginOn) { [char]0x2705 } else { [char]0x2B1C }
    $loginY = $y
    Add-PtObLabel $form ("$mark " + (Get-PtL ob_login_line -Lang $lang)) ([ref]$y)
    if (-not $loginOn) {
        Add-PtObButton $form (Get-PtL ob_enable_btn -Lang $lang) $loginY { Enable-PtAutostart; $form.Close(); Show-PtWelcomeForm }
    }
    Add-PtObLabel $form ([char]0x26A0 + ' ' + (Get-PtL ob_risk -Lang $lang)) ([ref]$y) 8 ([System.Drawing.Color]::DarkOrange) -Width 448

    $done = New-Object System.Windows.Forms.Button
    $done.Text = (Get-PtL ob_done -Lang $lang); $done.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $done.SetBounds(384, 238, 80, 28)
    $form.Controls.Add($done); $form.AcceptButton = $done
    [void]$form.ShowDialog()
}

# --- WinForms tray (стартует только как самостоятельный скрипт; под ST_NO_MAIN=1 — нет) ---
function Start-PtTray {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Shield
    $notify.Text = 'Paranoid Tools'
    $notify.Visible = $true

    # Скрытое NativeWindow ловит WM_HOTKEY (RegisterHotKey требует окно; у NotifyIcon его нет).
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class PtHotkeyWindow : NativeWindow {
    public event EventHandler HotkeyPressed;
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public PtHotkeyWindow() { CreateHandle(new CreateParams()); }
    public bool Register(uint mods, uint vk) { UnregisterHotKey(Handle, 1); return RegisterHotKey(Handle, 1, mods, vk); }
    public void Unregister() { UnregisterHotKey(Handle, 1); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312) { var h = HotkeyPressed; if (h != null) h(this, EventArgs.Empty); }
        base.WndProc(ref m);
    }
}
'@
    $script:hotkeyWin = New-Object PtHotkeyWindow
    $script:panicArmedAt = $null
    # Честный статус регистрации (зеркало macOS hotkeyRegistered, T4/T9): читает его Welcome-чеклист
    # (Show-PtWelcomeForm) — гейт готовности = валидный пресет И реально вставшая регистрация.
    $script:hotkeyRegistered = $false
    $script:hotkeyWin.add_HotkeyPressed({
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
        if (Test-PtPanicShouldFire -Now $now -ArmedAt $script:panicArmedAt) {
            $script:panicArmedAt = $null
            Invoke-PtTool -Command 'panic now'
        } else {
            $script:panicArmedAt = $now
            $notify.ShowBalloonTip(3000, 'Paranoid Tools', (Get-PtL notif_panic_arm), [System.Windows.Forms.ToolTipIcon]::Warning)
        }
    })
    # PanicHotkey — поле настроек (Task 10), дефолт ctrl-alt-shift-p → хоткей активен из коробки
    # (паритет с macOS).
    $hkSpec = Get-PtHotkeySpec -Preset ((Get-PtSettings).PanicHotkey)
    if ($hkSpec) {
        $script:hotkeyRegistered = $script:hotkeyWin.Register($hkSpec.Modifiers, $hkSpec.Vk)
        if (-not $script:hotkeyRegistered) {
            $notify.ShowBalloonTip(5000, 'Paranoid Tools', (Get-PtL notif_hotkey_fail), [System.Windows.Forms.ToolTipIcon]::Warning)
        }
    }

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    # Настройки: override точки монтирования (через env, который чтит Get-PtVaultMount) + интервал.
    $settings = Get-PtSettings
    if ($settings.VaultVolume) { $env:ST_VAULT_VOLUME = $settings.VaultVolume }
    # First-run: Welcome один раз (зеркало macOS didOnboard) — ПОСЛЕ хоткей-блока (чеклист видит
    # актуальный $script:hotkeyRegistered), ДО Application::Run. Onboarded=true пишем ДО показа формы,
    # как в macOS: закрытие без Done не должно снова показать Welcome на следующем запуске.
    if (-not $settings.Onboarded) {
        Set-PtSettings -VaultVolume $settings.VaultVolume -PollSeconds $settings.PollSeconds `
            -Language $settings.Language -PanicHotkey $settings.PanicHotkey -Onboarded $true
        Show-PtWelcomeForm
    }
    # Периодический опрос — раньше tooltip обновлялся только при открытии меню; теперь живой.
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [math]::Max(5, $settings.PollSeconds) * 1000
    $script:notifyState = New-PtNotifyState

    $rebuild = {
        $menu.Items.Clear()
        # Один резолв языка на весь rebuild (одно чтение settings), дальше -Lang $lang везде.
        $lang = Resolve-PtLang -Override ((Get-PtSettings).Language)
        $state = Get-PtVaultState
        $sessions = Get-PtVaultwatchSessions
        # TTL в главном статусе — ТОЛЬКО при реально открытом сейфе: осиротевший session-файл иначе
        # рисовал бы «auto-exit in …» при закрытом vault (P2-10).
        $ttl = if ($state -eq 'open') {
            ($sessions | Where-Object { $null -ne $_.Remaining } | ForEach-Object { $_.Remaining } | Measure-Object -Minimum).Minimum
        } else { $null }
        $notify.Text =
            if ($state -eq 'open' -and $null -ne $ttl -and $ttl -eq 0) { "$(Get-PtL 'tip_open' -Lang $lang) - $(Get-PtL 'ttl_expired' -Lang $lang)" }
            elseif ($state -eq 'open' -and $null -ne $ttl)              { "$(Get-PtL 'tip_open' -Lang $lang) - $(Get-PtL 'auto_exit_in' -Lang $lang) $(Format-PtDuration $ttl)" }
            elseif ($state -eq 'open')                                  { (Get-PtL 'tip_open' -Lang $lang) }
            else                                                        { (Get-PtL 'tip_closed' -Lang $lang) }
        # vaultwatch-сессии — отключённые заголовки сверху меню (точка монтирования + TTL-отсчёт).
        foreach ($s in $sessions) {
            $name = Split-Path -Leaf $s.Mount
            $detail = if ($null -ne $s.Remaining) { "$(Get-PtL 'auto_exit_in' -Lang $lang) $(Format-PtDuration $s.Remaining)" } else { (Get-PtL 'watching_no_ttl' -Lang $lang) }
            $h = New-Object System.Windows.Forms.ToolStripMenuItem("vaultwatch: $name - $detail")
            $h.Enabled = $false
            $menu.Items.Add($h) | Out-Null
        }
        if ($sessions.Count -gt 0) { $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null }
        foreach ($entry in (Get-PtMenuSpec -VaultState $state -Lang $lang)) {
            if ($entry.Label -eq '-') { $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null; continue }
            $cmd = $entry.Command
            $it = New-Object System.Windows.Forms.ToolStripMenuItem($entry.Label)
            if ($null -ne $entry.Enabled) { $it.Enabled = [bool]$entry.Enabled }   # грей-аут по спеку (P2-7)
            if ($cmd -eq '__quit__') {
                $it.Add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() }.GetNewClosure())
            } elseif ($cmd -eq '__autostart__') {
                $it.Checked = [bool](Test-PtAutostart)
                $it.Add_Click({ if (Test-PtAutostart) { Disable-PtAutostart } else { Enable-PtAutostart } }.GetNewClosure())
            } elseif ($cmd -eq '__settings__') {
                $it.Add_Click({
                    $s = Show-PtSettingsForm
                    if ($s) {
                        if ($s.VaultVolume) { $env:ST_VAULT_VOLUME = $s.VaultVolume }
                        else { Remove-Item Env:\ST_VAULT_VOLUME -ErrorAction SilentlyContinue }
                        $timer.Interval = [math]::Max(5, $s.PollSeconds) * 1000
                        # Перевзвод хоткея по новому пресету — результат Register не глотаем
                        # (честность, T9): фейл → тот же balloon, что при старте трея.
                        $hkSpec = Get-PtHotkeySpec -Preset $s.PanicHotkey
                        if ($hkSpec) {
                            $script:hotkeyRegistered = $script:hotkeyWin.Register($hkSpec.Modifiers, $hkSpec.Vk)
                            if (-not $script:hotkeyRegistered) {
                                $notify.ShowBalloonTip(5000, 'Paranoid Tools', (Get-PtL notif_hotkey_fail), [System.Windows.Forms.ToolTipIcon]::Warning)
                            }
                        } else { $script:hotkeyWin.Unregister(); $script:hotkeyRegistered = $false }
                        # Смена языка: & $rebuild ниже сам перечитывает Get-PtSettings.Language
                        # в $lang в начале блока — отдельного шага не нужно.
                    }
                    & $rebuild
                }.GetNewClosure())
            } elseif ($cmd -eq '__setup__') {
                $it.Add_Click({ Show-PtWelcomeForm }.GetNewClosure())
            } else {
                $it.Add_Click({ Invoke-PtTool -Command $cmd }.GetNewClosure())
            }
            $menu.Items.Add($it) | Out-Null
        }
        # уведомления: движок решает, BalloonTip доставляет (10с; текст без секретов)
        $now = [int64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $nr = Get-PtNotifyEvents -Open ($state -eq 'open') -Ttl $ttl -HasSessions ($sessions.Count -gt 0) -Now $now -State $script:notifyState
        $script:notifyState = $nr.State
        foreach ($e in $nr.Events) {
            $text = switch ($e) {
                'ttl_warn'    { (Get-PtL notif_ttl_warn -Lang $lang) -replace '\{0\}', (Format-PtDuration $ttl) }
                'ttl_expired' { Get-PtL notif_ttl_expired -Lang $lang }
                'long_open'   { Get-PtL notif_long_open -Lang $lang }
            }
            if ($text) { $notify.ShowBalloonTip(10000, 'Paranoid Tools', $text, [System.Windows.Forms.ToolTipIcon]::Warning) }
        }
    }
    $timer.Add_Tick($rebuild)     # живой опрос статуса/TTL по интервалу из настроек
    & $rebuild
    $menu.Add_Opening($rebuild)   # плюс мгновенный rebuild при открытии меню
    $notify.ContextMenuStrip = $menu
    $timer.Start()

    [System.Windows.Forms.Application]::Run()
    $timer.Stop()
}

if (-not $env:ST_NO_MAIN) { Start-PtTray }
