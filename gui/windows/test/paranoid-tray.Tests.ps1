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
        $labels = (Get-PtMenuSpec -VaultState 'closed').Label -join '|'
        $labels | Should -Match 'Status'
        $labels | Should -Match 'PANIC'
        $labels | Should -Match 'Empty'
        $labels | Should -Match 'Destroy'
        $labels | Should -Match 'launcher'
        $labels | Should -Match 'Quit'
    }
    It 'пункт сейфа: closed → Open the vault / securetrash vault open' {
        $vault = (Get-PtMenuSpec -VaultState 'closed')[3]
        $vault.Label   | Should -Be 'Open the vault'
        $vault.Command | Should -Be 'securetrash vault open'
    }
    It 'пункт сейфа: open → Close the vault / securetrash vault close' {
        $vault = (Get-PtMenuSpec -VaultState 'open')[3]
        $vault.Label   | Should -Be 'Close the vault'
        $vault.Command | Should -Be 'securetrash vault close'
    }
    It 'пункт сейфа: none → Create a vault / securetrash vault create' {
        $vault = (Get-PtMenuSpec -VaultState 'none')[3]
        $vault.Label   | Should -Be 'Create a vault'
        $vault.Command | Should -Be 'securetrash vault create'
    }
    It 'empty = securetrash vault reset (crypto-shred)' {
        $empty = (Get-PtMenuSpec -VaultState 'open') | Where-Object { $_.Label -match 'Empty' }
        $empty.Command | Should -Be 'securetrash vault reset'
    }
    It 'содержит пункт автостарта (Start at login / __autostart__)' {
        $auto = (Get-PtMenuSpec -VaultState 'closed') | Where-Object { $_.Label -match 'Start at login' }
        $auto.Command | Should -Be '__autostart__'
    }
    It 'содержит пункт настроек (Settings / __settings__)' {
        $set = (Get-PtMenuSpec -VaultState 'closed') | Where-Object { $_.Label -match 'Settings' }
        $set.Command | Should -Be '__settings__'
    }
    It 'пункт сейфа остаётся на индексе 3 после добавления автостарта/настроек' {
        (Get-PtMenuSpec -VaultState 'closed')[3].Command | Should -Be 'securetrash vault open'
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
    It 'битый JSON → дефолты, без исключения' {
        Set-Content -LiteralPath $env:PT_SETTINGS_FILE -Value '{ not valid json'
        $s = Get-PtSettings
        $s.PollSeconds | Should -Be 15
    }
}
