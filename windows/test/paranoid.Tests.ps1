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

Describe 'Get-PnDashboard — destroy item (4) gating' {
    BeforeEach {
        $script:PN_LOCALE = 'en'
        Mock Get-PnBitLockerState  { 'unknown' }
        Mock Get-PnVaultwatchState { 'idle' }
    }

    It 'shows the destroy item live when a vault exists and securetrash is present' {
        Mock Test-PnTool { $true }
        Mock Get-PnVaultState { 'closed' }
        $out = Get-PnDashboard
        ($out -split "`n" | Where-Object { $_ -match '4\)' }) | Should -Match 'Destroy the vault'
        ($out -split "`n" | Where-Object { $_ -match '4\)' }) | Should -Not -Match 'no vault'
        ($out -split "`n" | Where-Object { $_ -match '4\)' }) | Should -Not -Match 'not installed'
    }
    It 'greys the destroy item with (no vault) when no container exists' {
        Mock Test-PnTool { $true }
        Mock Get-PnVaultState { 'none' }
        $out = Get-PnDashboard
        ($out -split "`n" | Where-Object { $_ -match '4\)' }) | Should -Match 'no vault'
    }
    It 'greys the destroy item with (not installed) when securetrash is absent' {
        Mock Test-PnTool { $false } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Test-PnTool { $true }
        Mock Get-PnVaultState { 'closed' }
        $out = Get-PnDashboard
        ($out -split "`n" | Where-Object { $_ -match '4\)' }) | Should -Match 'not installed'
    }
}

Describe 'Get-PnDashboard — watch item (8) toggle label' {
    BeforeEach {
        $script:PN_LOCALE = 'en'
        Mock Get-PnBitLockerState { 'unknown' }
        Mock Test-PnTool { $true }
        Mock Get-PnVaultState { 'closed' }
    }

    It 'shows "Watch vault" when vaultwatch is idle' {
        Mock Get-PnVaultwatchState { 'idle' }
        $out = Get-PnDashboard
        ($out -split "`n" | Where-Object { $_ -match '8\)' }) | Should -Match 'Watch vault'
    }
    It 'shows "Stop watching" when vaultwatch is active' {
        Mock Get-PnVaultwatchState { 'active' }
        Mock Get-PnVaultwatchTtl { '' }
        $out = Get-PnDashboard
        ($out -split "`n" | Where-Object { $_ -match '8\)' }) | Should -Match 'Stop watching'
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

Describe 'Get-PnVaultState (3-state: open / closed / none)' {
    AfterEach { Remove-Item Env:\ST_VAULT_PATH -ErrorAction SilentlyContinue }

    It 'reports open when the vault volume exists' {
        $script:VAULT_VOLUME = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_v_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:VAULT_VOLUME -Force | Out-Null
        try { (Get-PnVaultState) | Should -Be 'open' }
        finally { Remove-Item -LiteralPath $script:VAULT_VOLUME -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'reports closed when the container exists but is not mounted' {
        $script:VAULT_VOLUME = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_v_" + [Guid]::NewGuid().ToString('N'))
        $container = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_c_" + [Guid]::NewGuid().ToString('N') + ".vhdx")
        Set-Content -LiteralPath $container -Value 'x' -NoNewline
        $env:ST_VAULT_PATH = $container
        try { (Get-PnVaultState) | Should -Be 'closed' }
        finally { Remove-Item -LiteralPath $container -Force -ErrorAction SilentlyContinue }
    }
    It 'reports none when neither the volume nor the container exists' {
        $script:VAULT_VOLUME = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_v_" + [Guid]::NewGuid().ToString('N'))
        $env:ST_VAULT_PATH = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_c_" + [Guid]::NewGuid().ToString('N') + ".vhdx")
        (Get-PnVaultState) | Should -Be 'none'
    }
    It 'reports none (no throw) when the vault volume is null and no container' {
        $script:VAULT_VOLUME = $null
        $env:ST_VAULT_PATH = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_c_" + [Guid]::NewGuid().ToString('N') + ".vhdx")
        (Get-PnVaultState) | Should -Be 'none'
    }
}

Describe 'Get-PnVaultMount (F2: dynamic drive letter)' {
    AfterEach { Remove-Item Env:\ST_VAULT_VOLUME -ErrorAction SilentlyContinue }

    It 'honors the ST_VAULT_VOLUME override' {
        $env:ST_VAULT_VOLUME = 'X:\'
        (Get-PnVaultMount) | Should -Be 'X:\'
    }

    It 'reads the active drive letter from the securetrash mount sidecar' {
        $tmpHome = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_home_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmpHome -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $tmpHome 'SecureVault.vhdx.mount') -Value 'E:\' -NoNewline
        $savedUP = $env:USERPROFILE; $savedHOME = $env:HOME
        try {
            $env:USERPROFILE = $tmpHome; $env:HOME = $tmpHome
            (Get-PnVaultMount) | Should -Be 'E:\'
        } finally {
            $env:USERPROFILE = $savedUP; $env:HOME = $savedHOME
            Remove-Item -LiteralPath $tmpHome -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns $null when no sidecar and no override (vault closed)' {
        $tmpHome = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_home_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmpHome -Force | Out-Null
        $savedUP = $env:USERPROFILE; $savedHOME = $env:HOME
        try {
            $env:USERPROFILE = $tmpHome; $env:HOME = $tmpHome
            (Get-PnVaultMount) | Should -BeNullOrEmpty
        } finally {
            $env:USERPROFILE = $savedUP; $env:HOME = $savedHOME
            Remove-Item -LiteralPath $tmpHome -Recurse -Force -ErrorAction SilentlyContinue
        }
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

    It 'creates the vault when none exists yet' {
        Mock Get-PnVaultState { 'none' }
        Invoke-PnDispatch '3' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'vault') -and ($ToolArgs -contains 'create')
        }
    }
}

Describe 'dispatch — status, split, combine (choices 1/5/6)' {
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

    It 'choice 5 runs seedsplit split' {
        Invoke-PnDispatch '5' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'seedsplit' -and ($ToolArgs -contains 'split')
        }
    }

    It 'choice 6 runs seedsplit combine' {
        Invoke-PnDispatch '6' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'seedsplit' -and ($ToolArgs -contains 'combine')
        }
    }
}

Describe 'dispatch — destroy (choice 4)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        $script:PN_LOCALE = 'en'
    }

    It 'runs securetrash vault destroy when a vault exists' {
        Mock Test-PnTool { $true } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'closed' }
        Invoke-PnDispatch '4' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'vault') -and ($ToolArgs -contains 'destroy')
        }
    }

    It 'destroys an open vault too (securetrash gates the mounted case)' {
        Mock Test-PnTool { $true } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'open' }
        Invoke-PnDispatch '4' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'destroy')
        }
    }

    It 'does nothing when there is no vault (none state)' {
        Mock Test-PnTool { $true } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'none' }
        Invoke-PnDispatch '4' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }

    It 'when securetrash is absent, runs nothing and does not read vault state' {
        Mock Test-PnTool { $false } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'closed' }
        Invoke-PnDispatch '4' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
}

Describe 'dispatch — ghost submenu (choice 7)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        $script:PN_LOCALE = 'en'
    }

    It 'submenu 1 runs ghostdraft new' {
        Mock Read-PnLine { '1' }
        Invoke-PnDispatch '7' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'ghostdraft' -and ($ToolArgs -contains 'new') -and (-not ($ToolArgs -contains '--clipboard'))
        }
    }

    It 'submenu 2 runs ghostdraft pipe' {
        Mock Read-PnLine { '2' }
        Invoke-PnDispatch '7' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'ghostdraft' -and ($ToolArgs -contains 'pipe')
        }
    }

    It 'submenu 3 runs ghostdraft new --clipboard' {
        Mock Read-PnLine { '3' }
        Invoke-PnDispatch '7' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'ghostdraft' -and ($ToolArgs -contains 'new') -and ($ToolArgs -contains '--clipboard')
        }
    }

    It 'an unknown submenu choice runs nothing' {
        Mock Read-PnLine { 'x' }
        Invoke-PnDispatch '7' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
}

Describe 'dispatch — watch toggle (choice 8)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        # Через override: Invoke-PnActWatch рефрешит $script:VAULT_VOLUME = Get-PnVaultMount,
        # а Get-PnVaultMount читает ST_VAULT_VOLUME первым — так refresh не затирает 'V:\'.
        $env:ST_VAULT_VOLUME = 'V:\'
    }
    AfterEach { Remove-Item Env:\ST_VAULT_VOLUME -ErrorAction SilentlyContinue }

    It 'passes --ttl when a duration is entered (idle → start)' {
        Mock Get-PnVaultwatchState { 'idle' }
        Mock Read-PnLine { '30m' }
        Invoke-PnDispatch '8' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'vaultwatch' -and ($ToolArgs -contains 'start') -and
            ($ToolArgs -contains '--ttl') -and ($ToolArgs -contains '30m') -and
            ($ToolArgs -contains 'V:\')
        }
    }

    It 'omits --ttl when the duration is empty (idle → start)' {
        Mock Get-PnVaultwatchState { 'idle' }
        Mock Read-PnLine { '' }
        Invoke-PnDispatch '8' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'vaultwatch' -and ($ToolArgs -contains 'start') -and
            ($ToolArgs -contains 'V:\') -and (-not ($ToolArgs -contains '--ttl'))
        }
    }

    It 'stops the watch when one is already active (active → stop, no TTL prompt)' {
        Mock Get-PnVaultwatchState { 'active' }
        Mock Read-PnLine { '30m' }   # не должен спрашиваться при активной охране
        Invoke-PnDispatch '8' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'vaultwatch' -and ($ToolArgs -contains 'stop') -and ($ToolArgs -contains 'V:\')
        }
        Should -Invoke Read-PnLine -Times 0 -Exactly
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
