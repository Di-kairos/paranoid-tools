# paranoid-tray.ps1 — native Windows system-tray agent on top of the same signed PowerShell ports
# of Paranoid Tools (Phase B). Mirror of the macOS ParanoidBar.
#
# HONESTY (as in Phase A): the tray holds NO secrets and adds NO crypto. It shows status and
# launches the same CLIs (securetrash / panic / paranoid) in a NEW console window — output and
# password input go into the CLI itself, not through the GUI. A convenience layer, not a new tool.
#
# Launch (Windows, pwsh 7): pwsh -File paranoid-tray.ps1   (lives in the tray until "Quit").
# Menu/status logic can be dot-sourced under ST_NO_MAIN=1 for Pester (the WinForms loop won't start).

# --- status (read-only) ---
function Get-PtVaultMount {
    if ($env:ST_VAULT_VOLUME) { return $env:ST_VAULT_VOLUME }
    # The sidecar sits next to the container ITSELF (`<vault>.mount`), not in the profile: with
    # ST_VAULT_PATH an open custom vault would otherwise show as closed (found by Codex).
    $container = Get-PtVaultContainer
    if (-not $container) { return $null }
    $sidecar = "$container.mount"
    if (Test-Path -LiteralPath $sidecar) { $m = (Get-Content -LiteralPath $sidecar -Raw).Trim(); if ($m) { return $m } }
    return $null
}
# Vault container. ST_VAULT_PATH is the same override the CLI honors (AUDIT_2026-07-03 P0-1):
# without it the tray would show "vault not set up" next to an existing custom vault.
function Get-PtVaultContainer {
    if ($env:ST_VAULT_PATH) { return $env:ST_VAULT_PATH }
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
    if (-not $homeDir) { return $null }
    return (Join-Path $homeDir 'SecureVault.vhdx')
}
# Mount points of all volumes — drive letters AND folder mount points (`C:\Vault\`).
# Wrapper for Mock. $null = the table could not be read (no CIM, WMI refusal, no rights).
function Get-PtMountPoints {
    try {
        $vols = Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop
        if ($null -eq $vols) { return $null }
        return @($vols | ForEach-Object { $_.Name } | Where-Object { $_ })
    } catch { return $null }
}
function Get-PtVaultState {
    # open / closed / none / unknown. We ask the volume table, not `Test-Path`: a vault
    # mounted into a folder leaves that folder in place after eject — the tray would write
    # "OPEN — at risk" over a closed vault (mirror of the launcher and bash `_status_vault`).
    $m = Get-PtVaultMount
    if ($m) {
        $points = Get-PtMountPoints
        if ($null -eq $points) { return 'unknown' }
        $needle = ([string]$m).TrimEnd('\', '/')
        foreach ($p in $points) {
            if ($p.TrimEnd('\', '/') -ieq $needle) { return 'open' }
        }
    }
    $container = Get-PtVaultContainer
    if ($container -and (Test-Path -LiteralPath $container)) { return 'closed' }
    return 'none'
}
# BitLocker status (platform honesty, mirror of macOS fileVaultOn). Get-BitLockerVolume requires
# the BitLocker module (not on every Windows SKU) and can throw without admin rights — we catch
# and treat it as "unknown" (fv_off covers both cases: 'off / unknown', which is honestly true).
function Test-PtBitLocker {
    param([string]$MountPoint = $env:SystemDrive)
    try {
        $v = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
        return ($v.ProtectionStatus -eq 'On')
    } catch { return $false }
}

# --- localization: dictionary in code, mirror of macOS `strings` (keys 1:1, parity — Pester).
# Honest wording ("at risk") is translated without softening. ---
$script:PtStrings = @{
    en = @{
        vault_label='Vault:'; vault_open_risk='OPEN — at risk'; vault_closed='closed'; vault_not_setup='not set up'
        vault_unknown='state unknown — volume table unreadable'; vault_ask='Ask securetrash for the vault state'
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
        set_title='Paranoid Bar — Settings'
        set_vol='Vault volume:'; set_poll='Poll interval (s):'; set_lang='Language:'; set_hotkey='Panic hotkey:'
        set_save='Save'; set_cancel='Cancel'; set_setup_btn='Show setup guide'; hk_off='Off'; lang_system='System'
        ob_title='Paranoid Bar — Welcome'
        ob_sub='A status bar over the same signed CLIs. Secrets never pass through the GUI.'
        ob_cli_ok='CLIs installed (all 5 tools + launcher)'; ob_cli_missing='CLIs not found — install first'
        ob_vault_ok='Vault created'; ob_vault_missing='No vault yet'; ob_create_btn='Create vault…'
        ob_hotkey_line='Panic hotkey'; ob_login_line='Start at login'; ob_enable_btn='Enable'
        ob_risk='An open vault is always "at risk" — the GUI never hides that.'; ob_done='Done'
    }
    ru = @{
        vault_label='Сейф:'; vault_open_risk='ОТКРЫТ — под риском'; vault_closed='закрыт'; vault_not_setup='не создан'
        vault_unknown='состояние неизвестно — таблица томов недоступна'; vault_ask='Спросить securetrash о состоянии сейфа'
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
        set_title='Paranoid Bar — Настройки'
        set_vol='Том сейфа:'; set_poll='Интервал опроса (с):'; set_lang='Язык:'; set_hotkey='Хоткей паники:'
        set_save='Сохранить'; set_cancel='Отмена'; set_setup_btn='Показать гид'; hk_off='Выкл'; lang_system='Системный'
        ob_title='Paranoid Bar — Добро пожаловать'
        ob_sub='Панель статуса поверх тех же подписанных CLI. Секреты через GUI не проходят.'
        ob_cli_ok='CLI установлены (все 5 инструментов + лаунчер)'; ob_cli_missing='CLI не найдены — сначала установите'
        ob_vault_ok='Сейф создан'; ob_vault_missing='Сейф ещё не создан'; ob_create_btn='Создать сейф…'
        ob_hotkey_line='Хоткей паники'; ob_login_line='Запускать при входе'; ob_enable_btn='Включить'
        ob_risk='Открытый сейф всегда «под риском» — GUI этого не прячет.'; ob_done='Готово'
    }
}
# Note: fv_label on Windows = BitLocker (platform honesty), on macOS = FileVault.
# The key itself is identical — key parity is preserved, the values are platform-specific.
# notif_hotkey_fail mirrors the macOS key (added by review T3): honest hotkey status.

function Resolve-PtLang {
    param([string]$Override = 'system', [string]$SystemLang = (Get-Culture).TwoLetterISOLanguageName)
    if ($Override -in @('en', 'ru')) { return $Override }
    if ($SystemLang -like 'ru*') { return 'ru' } else { return 'en' }
}
function Get-PtL {
    param([Parameter(Mandatory)][string]$Key, [string]$Lang)
    # Language is a settings field (Task 10), default 'system' → Resolve-PtLang picks en/ru by culture.
    if (-not $Lang) { $Lang = Resolve-PtLang -Override ((Get-PtSettings).Language) }
    $t = $script:PtStrings[$Lang]
    if ($t -and $t.ContainsKey($Key)) { return $t[$Key] } else { return $Key }
}

# Menu specification (label + CLI command). As a separate function → Pester checks the structure
# WITHOUT WinForms. '' in Command = separator; $null = submenu header (expanded below).
function Get-PtMenuSpec {
    # -Lang: one language resolve per call (not 12 settings reads inside Get-PtL) + determinism
    # in tests regardless of the CI host's culture.
    param([string]$VaultState = (Get-PtVaultState),
          [string]$Lang = (Resolve-PtLang -Override ((Get-PtSettings).Language)),
          [bool]$FvOn = (Test-PtBitLocker))
    # On 'unknown' the item promises no action: opening/closing/creating blindly is guessing,
    # so we call the read-only `vault status` and label it exactly that.
    $vaultToggle = switch ($VaultState) { 'open' { 'securetrash vault close' } 'closed' { 'securetrash vault open' } 'unknown' { 'securetrash vault status' } default { 'securetrash vault create' } }
    $vaultLabel  = switch ($VaultState) { 'open' { Get-PtL 'vault_close' -Lang $Lang } 'closed' { Get-PtL 'vault_open' -Lang $Lang } 'unknown' { Get-PtL 'vault_ask' -Lang $Lang } default { Get-PtL 'vault_create' -Lang $Lang } }
    # Empty/Destroy only make sense with an existing container (open|closed) — on 'none' we
    # grey them out so the destructive actions aren't active "into the void" (P2-7). Same on
    # 'unknown': we don't offer the irreversible on top of a state we don't know.
    $hasVault = $VaultState -in @('open', 'closed')
    # Honest status header at the top of the menu (P1, mirror of macOS rebuildMenu header() lines) —
    # without it the tray stayed silent about "vault open"/BitLocker-off risk, unlike macOS.
    $vaultStatusText = switch ($VaultState) { 'open' { Get-PtL 'vault_open_risk' -Lang $Lang } 'closed' { Get-PtL 'vault_closed' -Lang $Lang } 'unknown' { Get-PtL 'vault_unknown' -Lang $Lang } default { Get-PtL 'vault_not_setup' -Lang $Lang } }
    $fvText = if ($FvOn) { Get-PtL 'fv_on' -Lang $Lang } else { Get-PtL 'fv_off' -Lang $Lang }
    return @(
        [pscustomobject]@{ Label = ((Get-PtL 'vault_label' -Lang $Lang) + ' ' + $vaultStatusText); Command = ''; Enabled = $false }
        [pscustomobject]@{ Label = ((Get-PtL 'fv_label' -Lang $Lang) + ' ' + $fvText);              Command = ''; Enabled = $false }
        [pscustomobject]@{ Label = '-';                              Command = '';                  Enabled = $true }
        [pscustomobject]@{ Label = (Get-PtL 'status_item' -Lang $Lang);   Command = 'securetrash check'; Enabled = $true }
        # --hard = parity with the launcher's "PANIC NOW" (hide&lock + cloud daemons + recents)
        [pscustomobject]@{ Label = (Get-PtL 'panic_item' -Lang $Lang);    Command = 'panic now --hard';  Enabled = $true }
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

# --- autostart at login (HKCU Run; no admin rights/signature needed) ---
# Registry key spec as a separate function → Pester checks it WITHOUT writing to the registry.
function Get-PtAutostartSpec {
    $script = Join-Path $PSScriptRoot 'paranoid-tray.ps1'
    # Full path to pwsh, not bare `pwsh`: at login PATH may not contain pwsh (especially with
    # WindowStyle Hidden and no shell initialization) → autostart silently broke. The path is
    # quoted (Program Files\PowerShell\7 contains a space). Fallback to 'pwsh' if resolve failed.
    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) { $pwshPath = 'pwsh' }
    return [pscustomobject]@{
        Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        Name  = 'ParanoidTray'
        Value = "`"$pwshPath`" -WindowStyle Hidden -File `"$script`""
    }
}
function Test-PtAutostart {
    # ON only if the stored value matches the CURRENT spec: a stale entry (the script/pwsh
    # moved) is a broken autostart and does not deserve the "on" checkmark.
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

# --- vaultwatch status (read-only over the same session files the vaultwatch CLI writes) ---
function Get-PtVwStateDir {
    if ($env:VW_STATE_DIR) { return $env:VW_STATE_DIR }
    # $homeDir — see Get-PtVaultMount: assigning to the automatic $HOME throws an exception.
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
    if (-not $homeDir) { return $null }
    return (Join-Path $homeDir '.vaultwatch\sessions')
}
# Same format as the vaultwatch CLI (Format-VwDuration): "1h 5m 9s" / "5m 9s".
function Format-PtDuration {
    param([int]$S)
    $h = [math]::Floor($S / 3600); $m = [math]::Floor(($S % 3600) / 60); $sec = $S % 60
    if ($h -gt 0) { return "${h}h ${m}m ${sec}s" } else { return "${m}m ${sec}s" }
}
# NotifyIcon.Text on .NET Framework (PS 5.1) throws ArgumentException at >63 characters
# (on .NET Core the limit is 127, but we keep 63 — the common denominator). RU worst-case
# tooltip («…под риском… - авто-выход через 23h 59m 59s») = 68 chars. Truncate with ellipsis.
function Limit-PtTrayText {
    param([string]$Text, [int]$Max = 63)
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, $Max - 1) + [char]0x2026
}
# Parse key=value session files (mount/started/ttl_secs). remaining = started+ttl_secs-now;
# $null when ttl_secs=0 (a session without TTL). -Now is parameterized for deterministic tests.
function Get-PtVaultwatchSessions {
    param([int]$Now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $dir = Get-PtVwStateDir
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return @() }
    $out = @()
    foreach ($f in (Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        # Per-file try/catch: the file may have been deleted between listing and reading
        # (vaultwatch stop), or written partially/corrupted. One such file must NOT bring
        # down the whole menu/timer rebuild — we simply skip it.
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
# Mount point normalization for comparison (P1): a stale session file of ANOTHER volume would
# otherwise forever mute long_open/ttl of the current vault (sessions weren't scoped). Trim the
# trailing slash (both styles) + lowercase (the Windows FS is case-insensitive).
function Normalize-PtMount {
    param([string]$Mount)
    if (-not $Mount) { return '' }
    return $Mount.TrimEnd('\', '/').ToLowerInvariant()
}

# --- notifications: pure decision engine (Pester), delivery via NotifyIcon.ShowBalloonTip.
# Rules = spec §2, mirror of Swift decideNotifications: each event fires once per "vault
# open" episode; closing the vault resets the episode; a fresh/extended vaultwatch session
# (TTL >= 120s) re-arms the ttl warnings. Event names mirror macOS — do not change.
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
        # new/extended session -> re-arm (mirror of the Swift re-arm, review T2)
        if ($Ttl -ge 120) { $s.TtlWarned = $false; $s.TtlExpiredWarned = $false }
        if ($Ttl -gt 0 -and $Ttl -lt 120 -and -not $s.TtlWarned) { $events += 'ttl_warn'; $s.TtlWarned = $true }
        if ($Ttl -eq 0 -and -not $s.TtlExpiredWarned) { $events += 'ttl_expired'; $s.TtlExpiredWarned = $true }
    }
    if (-not $HasSessions -and ($Now - $s.OpenSince) -gt 1800 -and -not $s.LongOpenWarned) {
        $events += 'long_open'; $s.LongOpenWarned = $true
    }
    return [pscustomobject]@{ Events = $events; State = $s }
}

# --- global panic hotkey: RegisterHotKey + a hidden message window (WM_HOTKEY=0x0312).
# Double press within 2s (inclusive) → panic now --hard WITHOUT confirm (double-press = the confirmation;
# --hard = parity with the launcher's "PANIC NOW": hide&lock + cloud daemons + recents); a single —
# arm + balloon. Pure logic (2s window, preset mapping) — Pester; registration — the GUI path.
# RegisterHotKey's result isn't swallowed (mirror of the macOS honesty fix): fail → notif_hotkey_fail. ---
function Test-PtPanicShouldFire {
    param([double]$Now, [object]$ArmedAt, [double]$Window = 2.0)
    if ($null -eq $ArmedAt) { return $false }
    # Clock-jump guard (P2): the system clock may jump backwards (NTP correction/sleep) — the
    # delta is then negative. That's NOT a valid double-press window but a clock artifact, not "instant".
    $d = $Now - [double]$ArmedAt
    return ($d -ge 0 -and $d -le $Window)
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

# --- onboarding: pure helpers for the Welcome window checklist (mirror of macOS checklistLine/clisInstalled) ---
# The checklist line is pure for Pester (mirror of Swift checklistLine): ✅+okKey / ❌+missKey.
function Get-PtChecklistLine {
    param([bool]$Ok, [string]$OkKey, [string]$MissKey, [string]$Lang)
    if ($Ok) { return ([char]0x2705 + ' ' + (Get-PtL -Key $OkKey -Lang $Lang)) }
    return ([char]0x274C + ' ' + (Get-PtL -Key $MissKey -Lang $Lang))
}
# The CLI set the tray works on top of: the installer ships them together, so "ready" means
# all five. The `paranoid` launcher is here too — the tray menu calls exactly it, and without
# it the green check would be a lie (only three of the five tools were checked before). macOS mirror.
$script:PtEcosystemClis = @('securetrash', 'vaultwatch', 'panic', 'ghostdraft', 'seedsplit', 'paranoid')
function Test-PtClisInstalled {
    foreach ($t in $script:PtEcosystemClis) {
        if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { return $false }
    }
    return $true
}

# --- tray settings (vault mount point override + poll interval + Phase B: language/hotkey/onboarding) ---
# JSON in %APPDATA%\ParanoidTools\settings.json; the path is overridable via PT_SETTINGS_FILE (tests).

# ComboBox values by index (mirror of macOS langValues/hotkeyValues) — a single source of truth
# for the form (Show-PtSettingsForm) and for sanitization in Get/Set-PtSettings.
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
            # -eq $true, not [bool]: a hand-written "Onboarded":"false" (string) via [bool] would yield $true
            if ($null -ne $j.Onboarded)   { $s.Onboarded = ($j.Onboarded -eq $true) }
        } catch { }   # corrupted file → defaults
    }
    # Clamp to [5, 3600]: a PollSeconds > 3600 hand-written into the JSON otherwise threw on
    # NumericUpDown.Value (Maximum=3600) when opening the settings panel.
    if ($s.PollSeconds -lt 5) { $s.PollSeconds = 5 } elseif ($s.PollSeconds -gt 3600) { $s.PollSeconds = 3600 }
    # Sanitization: junk from hand-edited JSON (or an outdated version) → defaults, by the same
    # principle as the PollSeconds clamp. Lowercase BEFORE -notin: -notin is case-insensitive,
    # Array.IndexOf in the form is not ("RU" would otherwise survive sanitization, yet the form would show System).
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
    # Same sanitization + lowercase as in Get-PtSettings: canonical lowercase always goes into the JSON.
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

# Launch a CLI in a NEW console window (pwsh) — output and secret input go into the CLI itself, not the tray.
function Invoke-PtTool {
    param([string]$Command)
    if (-not $Command -or $Command -eq '__quit__' -or $Command -eq '__autostart__' -or $Command -eq '__settings__' -or $Command -eq '__setup__') { return }
    # The command is fixed (from Get-PtMenuSpec), not from user input → no injection possible.
    Start-Process -FilePath 'pwsh' -ArgumentList @('-NoExit', '-Command', $Command) | Out-Null
}

# WinForms settings dialog (GUI path only; the Get/Set-PtSettings logic is tested separately).
# Returns the applied settings on Save, otherwise $null. Never touches secrets — only paths/interval.
function Show-PtSettingsForm {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $cur = Get-PtSettings
    # One language resolve for the whole form (consistency with T7: not N settings reads in Get-PtL).
    $lang = Resolve-PtLang -Override $cur.Language

    $form = New-Object System.Windows.Forms.Form
    $form.Text = (Get-PtL set_title -Lang $lang)
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
    [void]$cbLang.Items.AddRange(@((Get-PtL lang_system -Lang $lang), 'English', 'Русский'))
    $cbLang.SelectedIndex = [math]::Max(0, $script:PtLangValues.IndexOf($cur.Language))

    $lblHk = New-Object System.Windows.Forms.Label
    $lblHk.Text = (Get-PtL set_hotkey -Lang $lang); $lblHk.SetBounds(12, 120, 110, 20)
    $cbHk = New-Object System.Windows.Forms.ComboBox
    $cbHk.DropDownStyle = 'DropDownList'; $cbHk.SetBounds(130, 117, 150, 22)
    [void]$cbHk.Items.AddRange(@('Ctrl+Alt+Shift+P', 'Ctrl+Alt+Shift+L', (Get-PtL hk_off -Lang $lang)))
    $cbHk.SelectedIndex = [math]::Max(0, $script:PtHotkeyValues.IndexOf($cur.PanicHotkey))

    # Setup guide (Show-PtWelcomeForm, Task 11) — opens the Welcome checklist right from Settings.
    $setup = New-Object System.Windows.Forms.Button
    $setup.Text = (Get-PtL set_setup_btn -Lang $lang); $setup.SetBounds(12, 185, 150, 28)
    $setup.Add_Click({ Show-PtWelcomeForm })

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = (Get-PtL set_save -Lang $lang); $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK; $ok.SetBounds(190, 190, 80, 28)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = (Get-PtL set_cancel -Lang $lang); $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $cancel.SetBounds(280, 190, 80, 28)

    $form.Controls.AddRange(@($lblVol, $tbVol, $lblPoll, $nudPoll, $lblLang, $cbLang, $lblHk, $cbHk, $setup, $ok, $cancel))
    $form.AcceptButton = $ok; $form.CancelButton = $cancel

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # Onboarded — from FRESH settings, not from $cur: while the form was open, Welcome (the
        # Setup button, T11) may have set Onboarded=true — Save with a stale $cur would resurrect onboarding.
        Set-PtSettings -VaultVolume ($tbVol.Text.Trim()) -PollSeconds ([int]$nudPoll.Value) `
            -Language $script:PtLangValues[([math]::Max(0, $cbLang.SelectedIndex))] `
            -PanicHotkey $script:PtHotkeyValues[([math]::Max(0, $cbHk.SelectedIndex))] `
            -Onboarded ((Get-PtSettings).Onboarded)
        return (Get-PtSettings)
    }
    return $null
}

# Welcome window (spec §3, mirror of macOS doWelcome/rebuildWelcome): live checklist + action buttons.
# Buttons redraw the form (close + reopen — acceptable for a dialog). Never touches secrets.
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
        # -Width 448 (instead of the default 330) — for lines WITHOUT a button on the right
        # (ob_sub/ob_risk): long EN/RU captions (~74-78 chars) got clipped at 330px.
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
    # hotkey: label by the ACTUAL preset (P/L), readiness = preset enabled AND registration really
    # succeeded ($script:hotkeyRegistered, T9) — mirror of the macOS T4 honesty fix (don't swallow RegisterHotKey).
    $preset = $cur.PanicHotkey
    $hkLabel = if ($preset -eq 'ctrl-alt-shift-l') { 'Ctrl+Alt+Shift+L' } else { 'Ctrl+Alt+Shift+P' }
    $hkOn = ($null -ne (Get-PtHotkeySpec -Preset $preset)) -and $script:hotkeyRegistered
    $mark = if ($hkOn) { [char]0x2705 } else { [char]0x2B1C }
    $hkY = $y
    Add-PtObLabel $form ("$mark " + (Get-PtL ob_hotkey_line -Lang $lang) + ": $hkLabel (" + [char]0x00D7 + '2)') ([ref]$y)
    if (-not $hkOn) {
        Add-PtObButton $form (Get-PtL ob_enable_btn -Lang $lang) $hkY {
            # ASSUMPTION (mirror of macOS obEnableHotkey): Enable always turns on the default P;
            # restoring the previous preset is Settings territory.
            $s = Get-PtSettings
            Set-PtSettings -VaultVolume $s.VaultVolume -PollSeconds $s.PollSeconds -Language $s.Language `
                -PanicHotkey 'ctrl-alt-shift-p' -Onboarded $s.Onboarded
            # $script:hotkeyWin only exists inside a running tray (Start-PtTray) — Welcome is
            # always opened from that context (first-run/menu/Settings), so it is in place.
            $ok = $false
            if ($script:hotkeyWin) {
                $spec = Get-PtHotkeySpec -Preset 'ctrl-alt-shift-p'
                $ok = $script:hotkeyWin.Register($spec.Modifiers, $spec.Vk)
                $script:hotkeyRegistered = $ok
            }
            # Resync an open Settings combo (mirror of macOS obEnableHotkey → hotkeyPopup):
            # Welcome opened from Settings → its Save would otherwise silently roll back the new preset.
            # Index 0 = 'ctrl-alt-shift-p' in $script:PtHotkeyValues.
            $cb = Get-Variable cbHk -ValueOnly -ErrorAction SilentlyContinue
            if ($cb) { $cb.SelectedIndex = 0 }
            # Registration failure isn't swallowed (mirror of macOS notify): a balloon via the
            # tray's $notify, if it is in scope (Welcome opened from a live Start-PtTray).
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

# --- WinForms tray (starts only as a standalone script; not under ST_NO_MAIN=1) ---
function Start-PtTray {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Shield
    $notify.Text = 'Paranoid Tools'
    $notify.Visible = $true

    # A hidden NativeWindow catches WM_HOTKEY (RegisterHotKey requires a window; NotifyIcon has none).
    # Primitives: on .NET 10+ the Message type is forwarded to System.Windows.Forms.Primitives (CS1069 without it).
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Windows.Forms.Primitives -TypeDefinition @'
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
    # Honest registration status (mirror of macOS hotkeyRegistered, T4/T9): the Welcome checklist
    # (Show-PtWelcomeForm) reads it — the readiness gate = a valid preset AND a registration that really stuck.
    $script:hotkeyRegistered = $false
    $script:hotkeyWin.add_HotkeyPressed({
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
        if (Test-PtPanicShouldFire -Now $now -ArmedAt $script:panicArmedAt) {
            $script:panicArmedAt = $null
            Invoke-PtTool -Command 'panic now --hard'
        } else {
            $script:panicArmedAt = $now
            $notify.ShowBalloonTip(3000, 'Paranoid Tools', (Get-PtL notif_panic_arm), [System.Windows.Forms.ToolTipIcon]::Warning)
        }
    })
    # PanicHotkey is a settings field (Task 10), default ctrl-alt-shift-p → the hotkey is active
    # out of the box (parity with macOS).
    $hkSpec = Get-PtHotkeySpec -Preset ((Get-PtSettings).PanicHotkey)
    if ($hkSpec) {
        $script:hotkeyRegistered = $script:hotkeyWin.Register($hkSpec.Modifiers, $hkSpec.Vk)
        if (-not $script:hotkeyRegistered) {
            $notify.ShowBalloonTip(5000, 'Paranoid Tools', (Get-PtL notif_hotkey_fail), [System.Windows.Forms.ToolTipIcon]::Warning)
        }
    }

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    # Settings: mount point override (via the env var Get-PtVaultMount honors) + interval.
    $settings = Get-PtSettings
    if ($settings.VaultVolume) { $env:ST_VAULT_VOLUME = $settings.VaultVolume }
    # First-run: Welcome once (mirror of macOS didOnboard) — AFTER the hotkey block (the checklist
    # sees the current $script:hotkeyRegistered), BEFORE Application::Run. Onboarded=true is written
    # BEFORE showing the form, as on macOS: closing without Done must not show Welcome again on the next start.
    if (-not $settings.Onboarded) {
        Set-PtSettings -VaultVolume $settings.VaultVolume -PollSeconds $settings.PollSeconds `
            -Language $settings.Language -PanicHotkey $settings.PanicHotkey -Onboarded $true
        Show-PtWelcomeForm
    }
    # Periodic polling — the tooltip used to refresh only when the menu opened; now it is live.
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [math]::Max(5, $settings.PollSeconds) * 1000
    $script:notifyState = New-PtNotifyState

    $rebuild = {
        $menu.Items.Clear()
        # One language resolve for the whole rebuild (one settings read), then -Lang $lang everywhere.
        $lang = Resolve-PtLang -Override ((Get-PtSettings).Language)
        $state = Get-PtVaultState
        $vol = Get-PtVaultMount
        $sessions = Get-PtVaultwatchSessions
        # Scope to the CURRENT volume (P1): a stale session file of a FOREIGN volume (moved/old
        # vault) would otherwise forever mute long_open/ttl of the current vault. The full $sessions
        # list below in the menu stays as is (informational — show all active vaultwatch watches).
        $vaultSessions = @($sessions | Where-Object { (Normalize-PtMount $_.Mount) -eq (Normalize-PtMount $vol) })
        # TTL in the main status — ONLY when the vault is really open: an orphaned session file
        # would otherwise draw "auto-exit in …" over a closed vault (P2-10).
        $ttl = if ($state -eq 'open') {
            ($vaultSessions | Where-Object { $null -ne $_.Remaining } | ForEach-Object { $_.Remaining } | Measure-Object -Minimum).Minimum
        } else { $null }
        $notify.Text = Limit-PtTrayText $(
            if ($state -eq 'open' -and $null -ne $ttl -and $ttl -eq 0) { "$(Get-PtL 'tip_open' -Lang $lang) - $(Get-PtL 'ttl_expired' -Lang $lang)" }
            elseif ($state -eq 'open' -and $null -ne $ttl)              { "$(Get-PtL 'tip_open' -Lang $lang) - $(Get-PtL 'auto_exit_in' -Lang $lang) $(Format-PtDuration $ttl)" }
            elseif ($state -eq 'open')                                  { (Get-PtL 'tip_open' -Lang $lang) }
            else                                                        { (Get-PtL 'tip_closed' -Lang $lang) })
        # vaultwatch sessions — disabled headers at the top of the menu (mount point + TTL countdown).
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
            if ($null -ne $entry.Enabled) { $it.Enabled = [bool]$entry.Enabled }   # grey-out per spec (P2-7)
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
                        # Re-arm the hotkey per the new preset — Register's result isn't swallowed
                        # (honesty, T9): fail → the same balloon as at tray startup.
                        $hkSpec = Get-PtHotkeySpec -Preset $s.PanicHotkey
                        if ($hkSpec) {
                            $script:hotkeyRegistered = $script:hotkeyWin.Register($hkSpec.Modifiers, $hkSpec.Vk)
                            if (-not $script:hotkeyRegistered) {
                                $notify.ShowBalloonTip(5000, 'Paranoid Tools', (Get-PtL notif_hotkey_fail), [System.Windows.Forms.ToolTipIcon]::Warning)
                            }
                        } else { $script:hotkeyWin.Unregister(); $script:hotkeyRegistered = $false }
                        # Language change: & $rebuild below re-reads Get-PtSettings.Language into
                        # $lang at the start of the block by itself — no separate step needed.
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
        # notifications: the engine decides, BalloonTip delivers (10s; text carries no secrets)
        $now = [int64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $nr = Get-PtNotifyEvents -Open ($state -eq 'open') -Ttl $ttl -HasSessions ($vaultSessions.Count -gt 0) -Now $now -State $script:notifyState
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
    $timer.Add_Tick($rebuild)     # live status/TTL polling at the interval from settings
    & $rebuild
    $menu.Add_Opening($rebuild)   # plus an immediate rebuild when the menu opens
    $notify.ContextMenuStrip = $menu
    $timer.Start()

    [System.Windows.Forms.Application]::Run()
    $timer.Stop()
}

if (-not $env:ST_NO_MAIN) {
    # The tray is pwsh 7 and pwsh 7 only: the hotkey helper compiles with a reference to
    # System.Windows.Forms.Primitives, and .NET Framework (Windows PowerShell 5.1) has no such
    # assembly. Without this check a 5.1 launch dumped a C# compiler error instead of an answer.
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        [Console]::Error.WriteLine("[x] paranoid-tray requires PowerShell 7+ (pwsh); running under $($PSVersionTable.PSVersion). Start it with: pwsh -File paranoid-tray.ps1")
        exit 1
    }
    Start-PtTray
}
