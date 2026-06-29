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

# Запустить CLI в НОВОМ окне консоли (pwsh) — вывод и ввод секретов идут в сам CLI, не через tray.
function Invoke-PtTool {
    param([string]$Command)
    if (-not $Command -or $Command -eq '__quit__' -or $Command -eq '__autostart__') { return }
    # Команда фиксирована (из Get-PtMenuSpec), не из пользовательского ввода → инъекций нет.
    Start-Process -FilePath 'pwsh' -ArgumentList @('-NoExit', '-Command', $Command) | Out-Null
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
    $rebuild = {
        $menu.Items.Clear()
        $state = Get-PtVaultState
        $notify.Text = if ($state -eq 'open') { 'Paranoid Tools - vault OPEN (at risk)' } else { 'Paranoid Tools' }
        foreach ($entry in (Get-PtMenuSpec -VaultState $state)) {
            if ($entry.Label -eq '-') { $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null; continue }
            $cmd = $entry.Command
            $it = New-Object System.Windows.Forms.ToolStripMenuItem($entry.Label)
            if ($cmd -eq '__quit__') {
                $it.Add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() }.GetNewClosure())
            } elseif ($cmd -eq '__autostart__') {
                $it.Checked = [bool](Test-PtAutostart)
                $it.Add_Click({ if (Test-PtAutostart) { Disable-PtAutostart } else { Enable-PtAutostart } }.GetNewClosure())
            } else {
                $it.Add_Click({ Invoke-PtTool -Command $cmd }.GetNewClosure())
            }
            $menu.Items.Add($it) | Out-Null
        }
    }
    & $rebuild
    $menu.Add_Opening($rebuild)   # перестраивать (статус/метки) при каждом открытии
    $notify.ContextMenuStrip = $menu

    [System.Windows.Forms.Application]::Run()
}

if (-not $env:ST_NO_MAIN) { Start-PtTray }
