# Pester — логика system-tray агента (paranoid-tray.ps1). Дот-сорс под ST_NO_MAIN=1: определяет
# функции, НЕ запуская WinForms-цикл. WinForms на Linux/macOS-CI недоступен, поэтому тестируем
# чистую логику: спецификацию меню (динамический пункт сейфа по состоянию) и диспетчер CLI.

BeforeAll {
    $env:ST_NO_MAIN = '1'
    . (Join-Path $PSScriptRoot '..\paranoid-tray.ps1')
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}
AfterAll { Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue }

Describe 'Get-PtMenuSpec — структура меню' {
    It 'содержит ключевые действия (status / panic / empty / destroy / launcher / quit)' {
        $labels = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en').Label -join '|'
        $labels | Should -Match 'Status'
        $labels | Should -Match 'PANIC'
        $labels | Should -Match 'Empty'
        $labels | Should -Match 'Destroy'
        $labels | Should -Match 'launcher'
        $labels | Should -Match 'Quit'
    }
    It 'пункт сейфа: closed → Open the vault / securetrash vault open' {
        $vault = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en')[6]
        $vault.Label   | Should -Be (Get-PtL -Key 'vault_open' -Lang 'en')
        $vault.Command | Should -Be 'securetrash vault open'
    }
    It 'пункт сейфа: open → Close the vault / securetrash vault close' {
        $vault = (Get-PtMenuSpec -VaultState 'open' -Lang 'en')[6]
        $vault.Label   | Should -Be (Get-PtL -Key 'vault_close' -Lang 'en')
        $vault.Command | Should -Be 'securetrash vault close'
    }
    It 'пункт сейфа: none → Create a vault / securetrash vault create' {
        $vault = (Get-PtMenuSpec -VaultState 'none' -Lang 'en')[6]
        $vault.Label   | Should -Be (Get-PtL -Key 'vault_create' -Lang 'en')
        $vault.Command | Should -Be 'securetrash vault create'
    }
    It 'empty = securetrash vault reset (crypto-shred)' {
        $empty = (Get-PtMenuSpec -VaultState 'open' -Lang 'en') | Where-Object { $_.Label -match 'Empty' }
        $empty.Command | Should -Be 'securetrash vault reset'
    }
    It 'Empty/Destroy enabled когда сейф есть (open|closed), disabled при none (P2-7)' {
        foreach ($st in 'open', 'closed') {
            $spec = Get-PtMenuSpec -VaultState $st -Lang 'en'
            ($spec | Where-Object { $_.Label -match 'Empty'   }).Enabled | Should -BeTrue
            ($spec | Where-Object { $_.Label -match 'Destroy' }).Enabled | Should -BeTrue
        }
        $none = Get-PtMenuSpec -VaultState 'none' -Lang 'en'
        ($none | Where-Object { $_.Label -match 'Empty'   }).Enabled | Should -BeFalse
        ($none | Where-Object { $_.Label -match 'Destroy' }).Enabled | Should -BeFalse
    }
    It 'содержит пункт автостарта (Start at login / __autostart__)' {
        $auto = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en') | Where-Object { $_.Label -match 'Start at login' }
        $auto.Command | Should -Be '__autostart__'
    }
    It 'содержит пункт настроек (Settings / __settings__)' {
        $set = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en') | Where-Object { $_.Label -match 'Settings' }
        $set.Command | Should -Be '__settings__'
    }
    It 'пункт сейфа остаётся на индексе 6 после добавления статус-заголовков/автостарта/настроек' {
        (Get-PtMenuSpec -VaultState 'closed' -Lang 'en')[6].Command | Should -Be 'securetrash vault open'
    }
    It 'первые два пункта — disabled статус-заголовки Vault/BitLocker (честность, P1)' {
        $spec = Get-PtMenuSpec -VaultState 'open' -Lang 'en' -FvOn $false
        $spec[0].Enabled | Should -BeFalse
        $spec[0].Label   | Should -Match ([regex]::Escape((Get-PtL -Key 'vault_label' -Lang 'en')))
        $spec[0].Label   | Should -Match ([regex]::Escape((Get-PtL -Key 'vault_open_risk' -Lang 'en')))
        $spec[1].Enabled | Should -BeFalse
        $spec[1].Label   | Should -Match ([regex]::Escape((Get-PtL -Key 'fv_label' -Lang 'en')))
        $spec[1].Label   | Should -Match ([regex]::Escape((Get-PtL -Key 'fv_off' -Lang 'en')))
    }
    It 'BitLocker-заголовок честно отражает FvOn=true' {
        $spec = Get-PtMenuSpec -VaultState 'closed' -Lang 'en' -FvOn $true
        $spec[1].Label | Should -Match ([regex]::Escape((Get-PtL -Key 'fv_on' -Lang 'en')))
    }
}

Describe 'Get-PtAutostartSpec — спецификация автозапуска' {
    It 'указывает на HKCU Run и запускает сам tray-скрипт через pwsh' {
        $s = Get-PtAutostartSpec
        $s.Path  | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $s.Name  | Should -Be 'ParanoidTray'
        $s.Value | Should -Match 'pwsh'
        $s.Value | Should -Match 'paranoid-tray\.ps1'
    }
}

Describe 'Format-PtDuration — формат как у vaultwatch CLI' {
    It '3909s → 1h 5m 9s' { Format-PtDuration 3909 | Should -Be '1h 5m 9s' }
    It '309s → 5m 9s'     { Format-PtDuration 309  | Should -Be '5m 9s' }
    It '0s → 0m 0s'       { Format-PtDuration 0    | Should -Be '0m 0s' }
}

Describe 'Get-PtVaultwatchSessions — чтение session-файлов vaultwatch' {
    BeforeAll {
        $script:vwDir = Join-Path $TestDrive 'vw-sessions'
        New-Item -ItemType Directory -Path $vwDir -Force | Out-Null
        $env:VW_STATE_DIR = $vwDir
    }
    AfterAll { Remove-Item Env:\VW_STATE_DIR -ErrorAction SilentlyContinue }
    BeforeEach { Get-ChildItem -LiteralPath $vwDir | Remove-Item -Force -ErrorAction SilentlyContinue }

    It 'TTL-сессия: remaining = started + ttl_secs - now' {
        Set-Content -LiteralPath (Join-Path $vwDir '_Volumes_SecretVault') -Value @(
            'mount=/Volumes/SecretVault', 'started=1000', 'ttl_secs=3600', 'ttl_force=0')
        $s = Get-PtVaultwatchSessions -Now 1900
        $s.Count        | Should -Be 1
        $s[0].Mount     | Should -Be '/Volumes/SecretVault'
        $s[0].Remaining | Should -Be 2700
    }
    It 'сессия без TTL (ttl_secs=0) → Remaining = $null' {
        Set-Content -LiteralPath (Join-Path $vwDir 's2') -Value @('mount=/Volumes/V', 'started=1000', 'ttl_secs=0')
        (Get-PtVaultwatchSessions -Now 1900)[0].Remaining | Should -BeNullOrEmpty
    }
    It 'истёкший TTL → Remaining = 0 (не отрицательное)' {
        Set-Content -LiteralPath (Join-Path $vwDir 's3') -Value @('mount=/Volumes/V', 'started=1000', 'ttl_secs=100')
        (Get-PtVaultwatchSessions -Now 5000)[0].Remaining | Should -Be 0
    }
    It 'пустой каталог → пусто' {
        (Get-PtVaultwatchSessions -Now 1900).Count | Should -Be 0
    }
    It 'битый файл (нечисловые started/ttl) не валит чтение остальных сессий' {
        # Раньше `[int]'garbage'` бросал → падал весь rebuild меню/таймера. Теперь TryParse
        # гасит, валидная сессия всё равно возвращается.
        Set-Content -LiteralPath (Join-Path $vwDir 'a_good') -Value @('mount=/Volumes/Good', 'started=1000', 'ttl_secs=3600')
        Set-Content -LiteralPath (Join-Path $vwDir 'b_bad')  -Value @('mount=/Volumes/Bad', 'started=xxx', 'ttl_secs=yyy')
        $s = @(Get-PtVaultwatchSessions -Now 1900)
        ($s | Where-Object { $_.Mount -eq '/Volumes/Good' }).Remaining | Should -Be 2700
        # битый: started/ttl не распарсились → ttl=0 → Remaining null, но без исключения
        { Get-PtVaultwatchSessions -Now 1900 } | Should -Not -Throw
    }
    It 'файл, исчезнувший между листингом и чтением, пропускается (race-safe)' {
        Set-Content -LiteralPath (Join-Path $vwDir 'a_good') -Value @('mount=/Volumes/Good', 'started=1000', 'ttl_secs=0')
        # Get-Content бросает на одном файле (имитация удаления vaultwatch stop) → не валит rebuild.
        # Mock без ParameterFilter: Pester 6 (runner image) перестал звать оригинал на не совпавших
        # фильтром вызовах (на 5.x было зелено) → ветвим внутри мока, оригинал — module-qualified.
        Mock Get-Content {
            if ($LiteralPath -like '*z_gone*') { throw [System.IO.FileNotFoundException]::new('gone') }
            Microsoft.PowerShell.Management\Get-Content -LiteralPath $LiteralPath -ErrorAction Stop
        }
        Set-Content -LiteralPath (Join-Path $vwDir 'z_gone') -Value @('mount=/Volumes/Gone', 'started=1', 'ttl_secs=0')
        { Get-PtVaultwatchSessions -Now 1900 } | Should -Not -Throw
        (@(Get-PtVaultwatchSessions -Now 1900) | Where-Object { $_.Mount -eq '/Volumes/Good' }).Count | Should -Be 1
    }
}

Describe 'Normalize-PtMount — скоуп vaultwatch-сессий к текущему тому (P1)' {
    It 'одинаковые пути (без нормализации) совпадают' {
        Normalize-PtMount 'C:\Vault' | Should -Be (Normalize-PtMount 'C:\Vault')
    }
    It 'конечный слэш (обоих стилей) игнорируется' {
        Normalize-PtMount 'C:\Vault\'      | Should -Be (Normalize-PtMount 'C:\Vault')
        Normalize-PtMount '/Volumes/Vault/' | Should -Be (Normalize-PtMount '/Volumes/Vault')
    }
    It 'регистр игнорируется' {
        Normalize-PtMount 'C:\VAULT' | Should -Be (Normalize-PtMount 'c:\vault')
    }
    It 'разные тома не совпадают' {
        Normalize-PtMount 'C:\Vault' | Should -Not -Be (Normalize-PtMount 'D:\Vault')
    }
    It 'пусто/$null → пустая строка' {
        Normalize-PtMount $null | Should -Be ''
        Normalize-PtMount ''    | Should -Be ''
    }
}

Describe 'Test-PtAutostart — честная проверка автозапуска' {
    It 'true только при совпадении с текущей спекой' {
        $spec = Get-PtAutostartSpec
        Mock Get-ItemProperty { [pscustomobject]@{ ParanoidTray = $spec.Value } }
        Test-PtAutostart | Should -BeTrue
    }
    It 'устаревшее значение (скрипт переехал) → false, а не «вкл»' {
        Mock Get-ItemProperty { [pscustomobject]@{ ParanoidTray = 'pwsh -File C:\old\paranoid-tray.ps1' } }
        Test-PtAutostart | Should -BeFalse
    }
    It 'нет записи → false' {
        Mock Get-ItemProperty { $null }
        Test-PtAutostart | Should -BeFalse
    }
}

Describe 'Invoke-PtTool — диспетчер CLI' {
    BeforeEach { Mock Start-Process { } }

    It 'запускает реальную команду в новом окне' {
        Invoke-PtTool -Command 'securetrash check'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains 'securetrash check' }
    }
    It 'разделитель ("") ничего не запускает' {
        Invoke-PtTool -Command ''
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It '__quit__ ничего не запускает (выход обрабатывает сам tray)' {
        Invoke-PtTool -Command '__quit__'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It '__autostart__ ничего не запускает (toggle обрабатывает сам tray)' {
        Invoke-PtTool -Command '__autostart__'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
    It '__settings__ ничего не запускает (диалог обрабатывает сам tray)' {
        Invoke-PtTool -Command '__settings__'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'Get-PtSettings / Set-PtSettings — хранилище настроек' {
    BeforeAll { $env:PT_SETTINGS_FILE = Join-Path $TestDrive 'settings.json' }
    AfterAll  { Remove-Item Env:\PT_SETTINGS_FILE -ErrorAction SilentlyContinue }
    BeforeEach { Remove-Item -LiteralPath $env:PT_SETTINGS_FILE -ErrorAction SilentlyContinue }

    It 'нет файла → дефолты (VaultVolume пуст, PollSeconds 15)' {
        $s = Get-PtSettings
        $s.VaultVolume | Should -BeNullOrEmpty
        $s.PollSeconds | Should -Be 15
    }
    It 'round-trip Set → Get' {
        Set-PtSettings -VaultVolume '/Volumes/X' -PollSeconds 30
        $s = Get-PtSettings
        $s.VaultVolume | Should -Be '/Volumes/X'
        $s.PollSeconds | Should -Be 30
    }
    It 'PollSeconds ниже 5 зажимается до 5' {
        Set-PtSettings -VaultVolume '' -PollSeconds 2
        (Get-PtSettings).PollSeconds | Should -Be 5
    }
    It 'PollSeconds выше 3600 зажимается до 3600 (иначе NumericUpDown.Value бросает)' {
        Set-PtSettings -VaultVolume '' -PollSeconds 99999
        (Get-PtSettings).PollSeconds | Should -Be 3600
    }
    It 'руками вписанный в JSON oversized PollSeconds читается зажатым' {
        Set-Content -LiteralPath $env:PT_SETTINGS_FILE -Value '{ "VaultVolume": "", "PollSeconds": 100000 }'
        (Get-PtSettings).PollSeconds | Should -Be 3600
    }
    It 'битый JSON → дефолты, без исключения' {
        Set-Content -LiteralPath $env:PT_SETTINGS_FILE -Value '{ not valid json'
        $s = Get-PtSettings
        $s.PollSeconds | Should -Be 15
    }
}

Describe 'Settings v2 (language/hotkey/onboarded)' {
    BeforeEach {
        $env:PT_SETTINGS_FILE = Join-Path $TestDrive 'settings.json'
        # чистый лист на каждый It: файл мог остаться от соседнего теста в том же TestDrive
        Remove-Item -LiteralPath $env:PT_SETTINGS_FILE -ErrorAction SilentlyContinue
    }
    AfterEach  { Remove-Item Env:\PT_SETTINGS_FILE -ErrorAction SilentlyContinue }
    It 'defaults: system language, hotkey on (ctrl-alt-shift-p), not onboarded' {
        $s = Get-PtSettings
        $s.Language | Should -Be 'system'
        $s.PanicHotkey | Should -Be 'ctrl-alt-shift-p'
        $s.Onboarded | Should -BeFalse
    }
    It 'round-trips new fields' {
        Set-PtSettings -VaultVolume 'X:' -PollSeconds 30 -Language 'ru' -PanicHotkey 'off' -Onboarded $true
        $s = Get-PtSettings
        $s.Language | Should -Be 'ru'
        $s.PanicHotkey | Should -Be 'off'
        $s.Onboarded | Should -BeTrue
    }
    It 'sanitizes garbage language/hotkey to defaults' {
        Set-PtSettings -Language 'xx' -PanicHotkey 'garbage'
        (Get-PtSettings).Language | Should -Be 'system'
        (Get-PtSettings).PanicHotkey | Should -Be 'ctrl-alt-shift-p'
    }
}

Describe 'Localization' {
    It 'returns en/ru strings and falls back to key' {
        Get-PtL -Key 'vault_closed' -Lang 'en' | Should -Be 'closed'
        Get-PtL -Key 'vault_closed' -Lang 'ru' | Should -Be 'закрыт'
        Get-PtL -Key 'no_such_key' -Lang 'en' | Should -Be 'no_such_key'
    }
    It 'resolves language: override beats system, system falls back to en' {
        Resolve-PtLang -Override 'ru' -SystemLang 'en' | Should -Be 'ru'
        Resolve-PtLang -Override 'system' -SystemLang 'ru' | Should -Be 'ru'
        Resolve-PtLang -Override 'system' -SystemLang 'fr' | Should -Be 'en'
    }
    It 'has identical key sets for en and ru' {
        ($PtStrings.en.Keys | Sort-Object) -join ',' | Should -Be (($PtStrings.ru.Keys | Sort-Object) -join ',')
    }
}

Describe 'Onboarding' {
    It 'builds checklist lines from readiness' {
        Get-PtChecklistLine -Ok $true -OkKey 'ob_cli_ok' -MissKey 'ob_cli_missing' -Lang 'en' |
            Should -Be ([char]0x2705 + ' ' + 'CLIs installed (securetrash, panic, vaultwatch)')
        Get-PtChecklistLine -Ok $false -OkKey 'ob_vault_ok' -MissKey 'ob_vault_missing' -Lang 'ru' |
            Should -Be ([char]0x274C + ' ' + 'Сейф ещё не создан')
    }
    It 'содержит пункт Setup guide (__setup__) в меню' {
        $set = (Get-PtMenuSpec -VaultState 'closed' -Lang 'en') | Where-Object { $_.Command -eq '__setup__' }
        $set.Label | Should -Be (Get-PtL -Key 'setup_item' -Lang 'en')
    }
    It 'Invoke-PtTool игнорирует __setup__ (форму открывает сам tray)' {
        Mock Start-Process { }
        Invoke-PtTool -Command '__setup__'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'Cross-platform l10n parity' {
    It 'ps1 key set equals Swift key set' {
        $swiftPath = Join-Path $PSScriptRoot '..' '..' 'macos' 'ParanoidBar.swift'
        $swift = Get-Content -LiteralPath $swiftPath -Raw
        $swiftKeys = [regex]::Matches($swift, '(?m)^\s*"([a-z0-9_]+)":\s*\(') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $psKeys = $PtStrings.en.Keys | Sort-Object -Unique
        ($psKeys -join ',') | Should -Be ($swiftKeys -join ',')
    }
}

Describe 'Panic hotkey' {
    It 'double-press fires only within 2s window' {
        Test-PtPanicShouldFire -Now 1000.0 -ArmedAt $null | Should -BeFalse
        Test-PtPanicShouldFire -Now 1001.5 -ArmedAt 1000.0 | Should -BeTrue
        Test-PtPanicShouldFire -Now 1002.0 -ArmedAt 1000.0 | Should -BeTrue
        Test-PtPanicShouldFire -Now 1002.5 -ArmedAt 1000.0 | Should -BeFalse
    }
    It 'clock-jump назад (Now < ArmedAt) не считается мгновенным двойным нажатием (P2)' {
        Test-PtPanicShouldFire -Now 995.0 -ArmedAt 1000.0 | Should -BeFalse
    }
    It 'maps presets to vk codes, off/garbage to $null' {
        (Get-PtHotkeySpec -Preset 'ctrl-alt-shift-p').Vk | Should -Be 0x50
        (Get-PtHotkeySpec -Preset 'ctrl-alt-shift-l').Vk | Should -Be 0x4C
        (Get-PtHotkeySpec -Preset 'ctrl-alt-shift-p').Modifiers | Should -Be 7
        Get-PtHotkeySpec -Preset 'off' | Should -BeNullOrEmpty
        Get-PtHotkeySpec -Preset 'garbage' | Should -BeNullOrEmpty
    }
    It 'compiles the PtHotkeyWindow helper (windows-only)' -Skip:(-not $IsWindows) {
        # тот же Add-Type сниппет, что в Start-PtTray (идемпотентен: тип уже загружен -> ловим и проверяем)
        try {
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
        } catch {
            if ($_.FullyQualifiedErrorId -notmatch 'TYPE_ALREADY_EXISTS') { throw }
        }
        [PtHotkeyWindow] | Should -Not -BeNullOrEmpty
        $w = New-Object PtHotkeyWindow
        $w.Unregister()   # smoke: instance + P/Invoke биндинг живы
    }
}

Describe 'Notification engine' {
    It 'fires each event once per episode and resets on close' {
        $s = New-PtNotifyState
        $r = Get-PtNotifyEvents -Open $true -Ttl 90 -HasSessions $true -Now 1000000 -State $s
        $r.Events | Should -Be @('ttl_warn')
        $r2 = Get-PtNotifyEvents -Open $true -Ttl 80 -HasSessions $true -Now 1000001 -State $r.State
        $r2.Events | Should -BeNullOrEmpty
        $r3 = Get-PtNotifyEvents -Open $true -Ttl 0 -HasSessions $true -Now 1000002 -State $r2.State
        $r3.Events | Should -Be @('ttl_expired')
        $r4 = Get-PtNotifyEvents -Open $false -Ttl $null -HasSessions $false -Now 1000003 -State $r3.State
        $r4.State.OpenSince | Should -BeNullOrEmpty
    }
    It 'warns once after 30 min open without vaultwatch' {
        $s = New-PtNotifyState
        $r = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $false -Now 1000000 -State $s
        $r.Events | Should -BeNullOrEmpty
        $r2 = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $false -Now 1001801 -State $r.State
        $r2.Events | Should -Be @('long_open')
        $r3 = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $false -Now 1003600 -State $r2.State
        $r3.Events | Should -BeNullOrEmpty
    }
    It 're-arms ttl warnings when a fresh/renewed session appears (>=120s)' {
        $s = New-PtNotifyState
        $r = Get-PtNotifyEvents -Open $true -Ttl 90 -HasSessions $true -Now 1000000 -State $s
        $r.Events | Should -Be @('ttl_warn')
        $r2 = Get-PtNotifyEvents -Open $true -Ttl 0 -HasSessions $true -Now 1000090 -State $r.State
        $r2.Events | Should -Be @('ttl_expired')
        $r3 = Get-PtNotifyEvents -Open $true -Ttl 300 -HasSessions $true -Now 1000100 -State $r2.State
        $r3.Events | Should -BeNullOrEmpty
        $r4 = Get-PtNotifyEvents -Open $true -Ttl 90 -HasSessions $true -Now 1000300 -State $r3.State
        $r4.Events | Should -Be @('ttl_warn')
    }
    It 'suppresses long_open while a vaultwatch session is alive' {
        $s = New-PtNotifyState
        $r = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $true -Now 1000000 -State $s
        $r2 = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $true -Now 1001801 -State $r.State
        $r2.Events | Should -BeNullOrEmpty
    }
}
