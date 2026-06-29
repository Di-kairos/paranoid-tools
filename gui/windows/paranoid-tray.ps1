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

# Спецификация меню (label + команда CLI). Отдельной функцией → Pester проверяет структуру
# БЕЗ WinForms. '' в Command = разделитель; $null = подменю-заголовок (раскрытие ниже).
function Get-PtMenuSpec {
    param([string]$VaultState = (Get-PtVaultState))
    $vaultToggle = switch ($VaultState) { 'open' { 'securetrash vault close' } 'closed' { 'securetrash vault open' } default { 'securetrash vault create' } }
    $vaultLabel  = switch ($VaultState) { 'open' { 'Close the vault' } 'closed' { 'Open the vault' } default { 'Create a vault' } }
    return @(
        [pscustomobject]@{ Label = 'Status - full read-only check'; Command = 'securetrash check' }
        [pscustomobject]@{ Label = 'PANIC NOW - hide & lock';       Command = 'panic now' }
        [pscustomobject]@{ Label = '-';                              Command = '' }
        [pscustomobject]@{ Label = $vaultLabel;                      Command = $vaultToggle }
        [pscustomobject]@{ Label = 'Empty the vault (crypto-shred)'; Command = 'securetrash vault reset' }
        [pscustomobject]@{ Label = 'Destroy the vault (irreversible)'; Command = 'securetrash vault destroy' }
        [pscustomobject]@{ Label = '-';                              Command = '' }
        [pscustomobject]@{ Label = 'Open the full launcher (paranoid)'; Command = 'paranoid' }
        [pscustomobject]@{ Label = '-';                              Command = '' }
        [pscustomobject]@{ Label = 'Start at login';                 Command = '__autostart__' }
        [pscustomobject]@{ Label = 'Settings...';                    Command = '__settings__' }
        [pscustomobject]@{ Label = '-';                              Command = '' }
        [pscustomobject]@{ Label = 'Quit Paranoid Tray';            Command = '__quit__' }
    )
}

# --- автостарт при логине (HKCU Run; без админ-прав/подписи) ---
# Спецификация ключа реестра отдельной функцией → Pester проверяет её БЕЗ записи в реестр.
function Get-PtAutostartSpec {
    $script = Join-Path $PSScriptRoot 'paranoid-tray.ps1'
    return [pscustomobject]@{
        Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        Name  = 'ParanoidTray'
        Value = "pwsh -WindowStyle Hidden -File `"$script`""
    }
}
function Test-PtAutostart {
    $s = Get-PtAutostartSpec
    $v = (Get-ItemProperty -LiteralPath $s.Path -Name $s.Name -ErrorAction SilentlyContinue).$($s.Name)
    return [bool]$v
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
        $mount = ''; $started = 0; $ttl = 0
        foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
            $i = $line.IndexOf('=')
            if ($i -lt 1) { continue }
            $k = $line.Substring(0, $i); $v = $line.Substring($i + 1)
            switch ($k) {
                'mount'    { $mount = $v }
                'started'  { $started = [int]$v }
                'ttl_secs' { $ttl = [int]$v }
            }
        }
        if (-not $mount) { continue }
        $remaining = if ($ttl -gt 0) { [math]::Max(0, $started + $ttl - $Now) } else { $null }
        $out += [pscustomobject]@{ Mount = $mount; Remaining = $remaining }
    }
    return $out
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
    if ($s.PollSeconds -lt 5) { $s.PollSeconds = 5 }   # нижняя граница (батарея/CPU)
    return $s
}
function Set-PtSettings {
    param([string]$VaultVolume = '', [int]$PollSeconds = 15)
    if ($PollSeconds -lt 5) { $PollSeconds = 5 }
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

    $rebuild = {
        $menu.Items.Clear()
        $state = Get-PtVaultState
        $sessions = Get-PtVaultwatchSessions
        $ttl = ($sessions | Where-Object { $null -ne $_.Remaining } | ForEach-Object { $_.Remaining } | Measure-Object -Minimum).Minimum
        $notify.Text =
            if ($state -eq 'open' -and $null -ne $ttl) { "Paranoid Tools - vault OPEN, auto-exit in $(Format-PtDuration $ttl)" }
            elseif ($state -eq 'open')                 { 'Paranoid Tools - vault OPEN (at risk)' }
            elseif ($null -ne $ttl)                    { "Paranoid Tools - vaultwatch auto-exit in $(Format-PtDuration $ttl)" }
            else                                       { 'Paranoid Tools' }
        # vaultwatch-сессии — отключённые заголовки сверху меню (точка монтирования + TTL-отсчёт).
        foreach ($s in $sessions) {
            $name = Split-Path -Leaf $s.Mount
            $detail = if ($null -ne $s.Remaining) { "auto-exit in $(Format-PtDuration $s.Remaining)" } else { 'watching (no TTL)' }
            $h = New-Object System.Windows.Forms.ToolStripMenuItem("vaultwatch: $name - $detail")
            $h.Enabled = $false
            $menu.Items.Add($h) | Out-Null
        }
        if ($sessions.Count -gt 0) { $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null }
        foreach ($entry in (Get-PtMenuSpec -VaultState $state)) {
            if ($entry.Label -eq '-') { $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null; continue }
            $cmd = $entry.Command
            $it = New-Object System.Windows.Forms.ToolStripMenuItem($entry.Label)
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
