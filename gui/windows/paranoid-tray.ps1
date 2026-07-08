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
    # ASSUMPTION: поле Language появится в Task 10; до этого $null -> '' -> system-ветка (StrictMode в репо не используется)
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

# --- настройки трея (override точки монтирования vault + интервал опроса) ---
# JSON в %APPDATA%\ParanoidTools\settings.json; путь переопределяем через PT_SETTINGS_FILE (тесты).
function Get-PtSettingsFile {
    if ($env:PT_SETTINGS_FILE) { return $env:PT_SETTINGS_FILE }
    $base = if ($env:APPDATA) { $env:APPDATA } elseif ($env:HOME) { Join-Path $env:HOME '.config' } else { $null }
    if (-not $base) { return $null }
    return (Join-Path $base 'ParanoidTools\settings.json')
}
function Get-PtSettings {
    $s = [pscustomobject]@{ VaultVolume = ''; PollSeconds = 15 }
    $f = Get-PtSettingsFile
    if ($f -and (Test-Path -LiteralPath $f)) {
        try {
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            if ($null -ne $j.VaultVolume) { $s.VaultVolume = [string]$j.VaultVolume }
            if ($null -ne ($j.PollSeconds -as [int])) { $s.PollSeconds = [int]$j.PollSeconds }
        } catch { }   # битый файл → дефолты
    }
    # Clamp в [5, 3600]: руками вписанный в JSON PollSeconds > 3600 иначе бросал на
    # NumericUpDown.Value (Maximum=3600) при открытии settings-панели.
    if ($s.PollSeconds -lt 5) { $s.PollSeconds = 5 } elseif ($s.PollSeconds -gt 3600) { $s.PollSeconds = 3600 }
    return $s
}
function Set-PtSettings {
    param([string]$VaultVolume = '', [int]$PollSeconds = 15)
    if ($PollSeconds -lt 5) { $PollSeconds = 5 } elseif ($PollSeconds -gt 3600) { $PollSeconds = 3600 }
    $f = Get-PtSettingsFile
    if (-not $f) { return }
    $dir = Split-Path -Parent $f
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [pscustomobject]@{ VaultVolume = $VaultVolume; PollSeconds = $PollSeconds } | ConvertTo-Json | Set-Content -LiteralPath $f
}

# Запустить CLI в НОВОМ окне консоли (pwsh) — вывод и ввод секретов идут в сам CLI, не через tray.
function Invoke-PtTool {
    param([string]$Command)
    if (-not $Command -or $Command -eq '__quit__' -or $Command -eq '__autostart__' -or $Command -eq '__settings__') { return }
    # Команда фиксирована (из Get-PtMenuSpec), не из пользовательского ввода → инъекций нет.
    Start-Process -FilePath 'pwsh' -ArgumentList @('-NoExit', '-Command', $Command) | Out-Null
}

# WinForms-диалог настроек (только GUI-путь; логика Get/Set-PtSettings тестируется отдельно).
# Возвращает применённые настройки при Save, иначе $null. Секретов не касается — только пути/интервал.
function Show-PtSettingsForm {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $cur = Get-PtSettings

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Paranoid Tools - Settings'
    $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.StartPosition = 'CenterScreen'; $form.ClientSize = New-Object System.Drawing.Size(380, 150)

    $lblVol = New-Object System.Windows.Forms.Label
    $lblVol.Text = 'Vault volume:'; $lblVol.SetBounds(12, 18, 110, 20)
    $tbVol = New-Object System.Windows.Forms.TextBox
    $tbVol.SetBounds(130, 15, 235, 22); $tbVol.Text = $cur.VaultVolume

    $lblPoll = New-Object System.Windows.Forms.Label
    $lblPoll.Text = 'Poll interval (s):'; $lblPoll.SetBounds(12, 52, 110, 20)
    $nudPoll = New-Object System.Windows.Forms.NumericUpDown
    $nudPoll.SetBounds(130, 49, 70, 22); $nudPoll.Minimum = 5; $nudPoll.Maximum = 3600; $nudPoll.Value = $cur.PollSeconds

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Save'; $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK; $ok.SetBounds(190, 110, 80, 28)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $cancel.SetBounds(280, 110, 80, 28)

    $form.Controls.AddRange(@($lblVol, $tbVol, $lblPoll, $nudPoll, $ok, $cancel))
    $form.AcceptButton = $ok; $form.CancelButton = $cancel

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-PtSettings -VaultVolume ($tbVol.Text.Trim()) -PollSeconds ([int]$nudPoll.Value)
        return (Get-PtSettings)
    }
    return $null
}

# --- WinForms tray (стартует только как самостоятельный скрипт; под ST_NO_MAIN=1 — нет) ---
function Start-PtTray {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Shield
    $notify.Text = 'Paranoid Tools'
    $notify.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    # Настройки: override точки монтирования (через env, который чтит Get-PtVaultMount) + интервал.
    $settings = Get-PtSettings
    if ($settings.VaultVolume) { $env:ST_VAULT_VOLUME = $settings.VaultVolume }
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
                    }
                    & $rebuild
                }.GetNewClosure())
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
