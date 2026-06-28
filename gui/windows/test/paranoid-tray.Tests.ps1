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
}
