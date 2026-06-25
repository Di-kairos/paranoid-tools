# Pester 5 — логика paranoid.ps1 (Windows-зеркало лаунчера). Дот-сорс под ST_NO_MAIN=1:
# определяет функции, не запуская интерактивный цикл. paranoid — тонкий лаунчер: он сам
# ничего не делает с секретами, а только диспетчеризует пять CLI. Поэтому МОКАЮТСЯ сидячие
# места (Invoke-PnTool, Read-PnLine, Confirm-Pn, *-State), а тест проверяет оркестровку:
# какой тул с какими аргументами вызван, гейт --hard у паники, open/close сейфа, ttl у watch.
# CLI-уровень (version, exit-коды) — через свежий pwsh.

BeforeAll {
    $env:ST_NO_MAIN = '1'
    $script:ScriptPath = Join-Path $PSScriptRoot '..\paranoid.ps1'
    . $script:ScriptPath
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}

AfterAll {
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}

Describe 'i18n' {
    It 'returns English chrome by default' {
        $script:PN_LOCALE = 'en'
        (T 'm_panic')      | Should -Match 'PANIC NOW'
        (T 'vault_open')   | Should -Be 'OPEN'
        (T 'vault_closed') | Should -Be 'closed'
    }
    It 'returns Russian chrome under ru locale' {
        $script:PN_LOCALE = 'ru'
        (T 'm_panic')      | Should -Match 'ПАНИКА'
        (T 'vault_open')   | Should -Be 'ОТКРЫТ'
        (T 'vault_closed') | Should -Be 'закрыт'
    }
    It 'falls back to the key for an unknown id' {
        (T 'no_such_key') | Should -Be 'no_such_key'
    }
}

Describe 'Get-PnDashboard — read-only status text' {
    BeforeEach {
        $script:PN_LOCALE = 'en'
        # vaultwatch/bitlocker не должны лезть в реальную систему из dashboard.
        Mock Get-PnBitLockerState  { 'unknown' }
        Mock Get-PnVaultwatchState { 'idle' }
        Mock Test-PnTool { $true }
    }

    It 'shows OPEN and the at-risk text when the vault is open' {
        Mock Get-PnVaultState { 'open' }
        $out = Get-PnDashboard
        $out | Should -Match 'OPEN'
        $out | Should -Match 'at risk while open'
    }

    It 'shows the closed label when the vault is closed' {
        Mock Get-PnVaultState { 'closed' }
        $out = Get-PnDashboard
        $out | Should -Match 'closed'
    }

    It 'marks the panic line (not installed) when panic is absent' {
        Mock Get-PnVaultState { 'closed' }
        Mock Test-PnTool { $false } -ParameterFilter { $Tool -eq 'panic' }
        $out = Get-PnDashboard
        ($out -split "`n" | Where-Object { $_ -match 'PANIC NOW' }) | Should -Match 'not installed'
    }

    It 'does not mark the panic line (not installed) when panic is present' {
        Mock Get-PnVaultState { 'closed' }
        Mock Test-PnTool { $true } -ParameterFilter { $Tool -eq 'panic' }
        $out = Get-PnDashboard
        ($out -split "`n" | Where-Object { $_ -match 'PANIC NOW' }) | Should -Not -Match 'not installed'
    }
}

Describe 'Format-PnMenuItem' {
    BeforeEach { $script:PN_LOCALE = 'en' }

    It 'renders a bare item without a tool gate' {
        (Format-PnMenuItem 1 'Status') | Should -Be '  1) Status'
    }
    It 'appends (not installed) when the gating tool is absent' {
        Mock Test-PnTool { $false }
        (Format-PnMenuItem 4 'Split' 'seedsplit') | Should -Match 'not installed'
    }
    It 'omits (not installed) when the gating tool is present' {
        Mock Test-PnTool { $true }
        (Format-PnMenuItem 4 'Split' 'seedsplit') | Should -Not -Match 'not installed'
    }
}

Describe 'Get-PnVaultState' {
    It 'reports open when the vault volume exists' {
        $script:VAULT_VOLUME = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_v_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:VAULT_VOLUME -Force | Out-Null
        try { (Get-PnVaultState) | Should -Be 'open' }
        finally { Remove-Item -LiteralPath $script:VAULT_VOLUME -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'reports closed when the vault volume is missing' {
        $script:VAULT_VOLUME = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_v_" + [Guid]::NewGuid().ToString('N'))
        (Get-PnVaultState) | Should -Be 'closed'
    }
}

Describe 'Get-PnToolRepo' {
    It 'returns the panic repo url' {
        (Get-PnToolRepo 'panic') | Should -Match 'github.com/Di-kairos/panic'
    }
    It 'returns empty for an unknown tool' {
        (Get-PnToolRepo 'nope') | Should -Be ''
    }
}

Describe 'dispatch — panic (choice 2)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        Mock Test-PnTool { $true } -ParameterFilter { $Tool -eq 'panic' }
    }

    It 'runs panic now --hard when both confirmations are yes' {
        Mock Confirm-Pn { $true }
        Invoke-PnDispatch '2' | Should -BeFalse
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'panic' -and ($ToolArgs -contains 'now') -and ($ToolArgs -contains '--hard')
        }
    }

    It 'runs panic now WITHOUT --hard when the hard confirmation is no' {
        # Первый Confirm-Pn (запуск) → yes, второй (--hard) → no.
        $script:calls = 0
        Mock Confirm-Pn { $script:calls++; if ($script:calls -eq 1) { $true } else { $false } }
        Invoke-PnDispatch '2' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'panic' -and ($ToolArgs -contains 'now') -and (-not ($ToolArgs -contains '--hard'))
        }
    }

    It 'does NOT run panic when the first confirmation is no' {
        Mock Confirm-Pn { $false }
        Invoke-PnDispatch '2' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }

    It 'when panic is absent, runs nothing and never asks for confirmation' {
        Mock Test-PnTool { $false } -ParameterFilter { $Tool -eq 'panic' }
        Mock Confirm-Pn { $true }
        Invoke-PnDispatch '2' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
        Should -Invoke Confirm-Pn -Times 0 -Exactly
    }
}

Describe 'dispatch — vault (choice 3)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
    }

    It 'closes the vault when it is open' {
        Mock Get-PnVaultState { 'open' }
        Invoke-PnDispatch '3' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'vault') -and ($ToolArgs -contains 'close')
        }
    }

    It 'opens the vault when it is closed' {
        Mock Get-PnVaultState { 'closed' }
        Invoke-PnDispatch '3' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'vault') -and ($ToolArgs -contains 'open')
        }
    }
}

Describe 'dispatch — status, split, combine (choices 1/4/5)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        Mock Test-PnTool { $true }
    }

    It 'choice 1 runs securetrash check (and vaultwatch status)' {
        Invoke-PnDispatch '1' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'check')
        }
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'vaultwatch' -and ($ToolArgs -contains 'status')
        }
    }

    It 'choice 4 runs seedsplit split' {
        Invoke-PnDispatch '4' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'seedsplit' -and ($ToolArgs -contains 'split')
        }
    }

    It 'choice 5 runs seedsplit combine' {
        Invoke-PnDispatch '5' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'seedsplit' -and ($ToolArgs -contains 'combine')
        }
    }
}

Describe 'dispatch — ghost submenu (choice 6)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        $script:PN_LOCALE = 'en'
    }

    It 'submenu 1 runs ghostdraft new' {
        Mock Read-PnLine { '1' }
        Invoke-PnDispatch '6' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'ghostdraft' -and ($ToolArgs -contains 'new')
        }
    }

    It 'submenu 2 runs ghostdraft pipe' {
        Mock Read-PnLine { '2' }
        Invoke-PnDispatch '6' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'ghostdraft' -and ($ToolArgs -contains 'pipe')
        }
    }

    It 'an unknown submenu choice runs nothing' {
        Mock Read-PnLine { 'x' }
        Invoke-PnDispatch '6' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
}

Describe 'dispatch — watch (choice 7)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        $script:VAULT_VOLUME = 'V:\'
    }

    It 'passes --ttl when a duration is entered' {
        Mock Read-PnLine { '30m' }
        Invoke-PnDispatch '7' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'vaultwatch' -and ($ToolArgs -contains 'start') -and
            ($ToolArgs -contains '--ttl') -and ($ToolArgs -contains '30m') -and
            ($ToolArgs -contains 'V:\')
        }
    }

    It 'omits --ttl when the duration is empty' {
        Mock Read-PnLine { '' }
        Invoke-PnDispatch '7' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'vaultwatch' -and ($ToolArgs -contains 'start') -and
            ($ToolArgs -contains 'V:\') -and (-not ($ToolArgs -contains '--ttl'))
        }
    }
}

Describe 'dispatch — quit and unknown' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
    }

    It 'returns $true for 0' { (Invoke-PnDispatch '0') | Should -BeTrue }
    It 'returns $true for q' { (Invoke-PnDispatch 'q') | Should -BeTrue }
    It 'returns $true for Q' { (Invoke-PnDispatch 'Q') | Should -BeTrue }
    It 'returns $false for an unknown choice (redraws the menu)' {
        (Invoke-PnDispatch 'zzz') | Should -BeFalse
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
}

Describe 'CLI surface (child pwsh)' {
    It 'prints the version' {
        $out = & pwsh -NoProfile -File $script:ScriptPath version
        ($out -join "`n") | Should -Match 'paranoid 0\.1\.0'
    }
    It 'exits non-zero on an unknown command' {
        & pwsh -NoProfile -File $script:ScriptPath bogus *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
}
