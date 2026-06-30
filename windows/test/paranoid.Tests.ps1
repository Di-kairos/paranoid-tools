# Pester 5 — логика paranoid.ps1 (Windows-зеркало лаунчера). Дот-сорс под ST_NO_MAIN=1:
# определяет функции, не запуская интерактивный цикл. paranoid — тонкий лаунчер: он сам
# ничего не делает с секретами, а только диспетчеризует пять CLI. Поэтому МОКАЮТСЯ сидячие
# места (Invoke-PnTool, Read-PnLine, *-State), а тест проверяет оркестровку: какой тул с
# какими аргументами вызван, мгновенную панику (now --hard), open/close сейфа, ttl у watch.
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

Describe 'Get-PnVaultMenu — dynamic item 1 + empty/destroy gating + watch toggle' {
    BeforeEach {
        $script:PN_LOCALE = 'en'
        Mock Get-PnVaultwatchState { 'idle' }
        Mock Get-PnVaultMount { $null }
        Mock Test-PnTool { $true }
    }

    It 'item 1 reads "Create a vault" when none' {
        Mock Get-PnVaultState { 'none' }
        ((Get-PnVaultMenu) -split "`n" | Where-Object { $_ -match '1\)' }) | Should -Match 'Create a vault'
    }
    It 'item 1 reads "Open the vault" when closed' {
        Mock Get-PnVaultState { 'closed' }
        ((Get-PnVaultMenu) -split "`n" | Where-Object { $_ -match '1\)' }) | Should -Match 'Open the vault'
    }
    It 'item 1 reads "Close the vault" when open' {
        Mock Get-PnVaultState { 'open' }
        ((Get-PnVaultMenu) -split "`n" | Where-Object { $_ -match '1\)' }) | Should -Match 'Close the vault'
    }
    It 'empty (2) is live when a vault exists' {
        Mock Get-PnVaultState { 'closed' }
        ((Get-PnVaultMenu) -split "`n" | Where-Object { $_ -match '2\)' }) | Should -Match 'Empty'
        ((Get-PnVaultMenu) -split "`n" | Where-Object { $_ -match '2\)' }) | Should -Not -Match 'no vault'
    }
    It 'empty (2) greyed (no vault) when none' {
        Mock Get-PnVaultState { 'none' }
        ((Get-PnVaultMenu) -split "`n" | Where-Object { $_ -match '2\)' }) | Should -Match 'no vault'
    }
    It 'destroy (3) greyed (not installed) when securetrash absent' {
        Mock Test-PnTool { $false } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'closed' }
        ((Get-PnVaultMenu) -split "`n" | Where-Object { $_ -match '3\)' }) | Should -Match 'not installed'
    }
    It 'watch (4) shows "Watch vault" when idle' {
        Mock Get-PnVaultState { 'closed' }
        Mock Get-PnVaultwatchState { 'idle' }
        ((Get-PnVaultMenu) -split "`n" | Where-Object { $_ -match '4\)' }) | Should -Match 'Watch vault'
    }
    It 'watch (4) shows "Stop watching" when active' {
        Mock Get-PnVaultState { 'closed' }
        Mock Get-PnVaultwatchState { 'active' }
        ((Get-PnVaultMenu) -split "`n" | Where-Object { $_ -match '4\)' }) | Should -Match 'Stop watching'
    }
}

Describe 'Get-PnDashboard — top-level submenu groups' {
    BeforeEach {
        $script:PN_LOCALE = 'en'
        Mock Get-PnBitLockerState { 'unknown' }
        Mock Get-PnVaultwatchState { 'idle' }
        Mock Get-PnVaultState { 'closed' }
        Mock Test-PnTool { $true }
    }
    It 'shows the three submenu groups (Vault / Notepad / Secrets)' {
        $out = Get-PnDashboard
        $out | Should -Match 'Vault >'
        $out | Should -Match 'Notepad >'
        $out | Should -Match 'Secrets >'
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

    It 'dispatches panic now --hard instantly (no confirm)' {
        # Паника мгновенна и всегда --hard: кнопка, требующая «yes», теряет смысл.
        Invoke-PnDispatch '2' | Should -BeFalse
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'panic' -and ($ToolArgs -contains 'now') -and ($ToolArgs -contains '--hard')
        }
    }

    It 'when panic is absent, runs nothing' {
        Mock Test-PnTool { $false } -ParameterFilter { $Tool -eq 'panic' }
        Invoke-PnDispatch '2' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
}

Describe 'top dispatch routes groups to submenu loops (3/4/5)' {
    BeforeEach {
        Mock Invoke-PnMenuVault { }
        Mock Invoke-PnMenuNotepad { }
        Mock Invoke-PnMenuSecrets { }
    }
    It 'choice 3 opens the vault submenu' {
        Invoke-PnDispatch '3' | Should -BeFalse
        Should -Invoke Invoke-PnMenuVault -Times 1 -Exactly
    }
    It 'choice 4 opens the notepad submenu' {
        Invoke-PnDispatch '4' | Out-Null
        Should -Invoke Invoke-PnMenuNotepad -Times 1 -Exactly
    }
    It 'choice 5 opens the secrets submenu' {
        Invoke-PnDispatch '5' | Out-Null
        Should -Invoke Invoke-PnMenuSecrets -Times 1 -Exactly
    }
}

Describe 'vault submenu dispatch — open/close/create smart (item 1) + size' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        $script:PN_LOCALE = 'en'
    }

    It 'closes the vault when it is open' {
        Mock Get-PnVaultState { 'open' }
        Invoke-PnVaultDispatch '1' | Should -BeFalse
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'vault') -and ($ToolArgs -contains 'close')
        }
    }
    It 'opens the vault when it is closed' {
        Mock Get-PnVaultState { 'closed' }
        Invoke-PnVaultDispatch '1' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'vault') -and ($ToolArgs -contains 'open')
        }
    }
    It 'creates the vault (default size) when none and size empty' {
        Mock Get-PnVaultState { 'none' }
        Mock Read-PnLine { '' }
        Invoke-PnVaultDispatch '1' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and (($ToolArgs -join ' ') -eq 'vault create')
        }
    }
    It 'creates the vault with a chosen MB size cap' {
        Mock Get-PnVaultState { 'none' }
        Mock Read-PnLine { '5120' }
        Invoke-PnVaultDispatch '1' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'create') -and ($ToolArgs -contains '5120')
        }
    }
    It 'invalid size cancels create (nothing dispatched)' {
        Mock Get-PnVaultState { 'none' }
        Mock Read-PnLine { 'big' }
        Invoke-PnVaultDispatch '1' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
}

Describe 'vault submenu dispatch — empty=reset (item 2)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        $script:PN_LOCALE = 'en'
    }

    It 'runs securetrash vault reset (default size) when a vault exists' {
        Mock Test-PnTool { $true } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'closed' }
        Mock Read-PnLine { '' }
        Invoke-PnVaultDispatch '2' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and (($ToolArgs -join ' ') -eq 'vault reset')
        }
    }
    It 'passes a chosen size to reset' {
        Mock Test-PnTool { $true } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'closed' }
        Mock Read-PnLine { '2048' }
        Invoke-PnVaultDispatch '2' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'reset') -and ($ToolArgs -contains '2048')
        }
    }
    It 'is a no-op when there is no vault' {
        Mock Test-PnTool { $true } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'none' }
        Invoke-PnVaultDispatch '2' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
    It 'when securetrash is absent, runs nothing' {
        Mock Test-PnTool { $false } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'closed' }
        Invoke-PnVaultDispatch '2' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
}

Describe 'vault submenu dispatch — destroy (item 3)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        $script:PN_LOCALE = 'en'
    }

    It 'runs securetrash vault destroy when a vault exists' {
        Mock Test-PnTool { $true } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'closed' }
        Invoke-PnVaultDispatch '3' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'destroy')
        }
    }
    It 'is a no-op when there is no vault' {
        Mock Test-PnTool { $true } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'none' }
        Invoke-PnVaultDispatch '3' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
    It 'when securetrash absent, runs nothing' {
        Mock Test-PnTool { $false } -ParameterFilter { $Tool -eq 'securetrash' }
        Mock Get-PnVaultState { 'closed' }
        Invoke-PnVaultDispatch '3' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
}

Describe 'vault submenu dispatch — watch toggle (item 4)' {
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
        Invoke-PnVaultDispatch '4' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'vaultwatch' -and ($ToolArgs -contains 'start') -and
            ($ToolArgs -contains '--ttl') -and ($ToolArgs -contains '30m') -and ($ToolArgs -contains 'V:\')
        }
    }
    It 'omits --ttl when the duration is empty (idle → start)' {
        Mock Get-PnVaultwatchState { 'idle' }
        Mock Read-PnLine { '' }
        Invoke-PnVaultDispatch '4' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'vaultwatch' -and ($ToolArgs -contains 'start') -and
            ($ToolArgs -contains 'V:\') -and (-not ($ToolArgs -contains '--ttl'))
        }
    }
    It 'stops the watch when already active (active → stop, no TTL prompt)' {
        Mock Get-PnVaultwatchState { 'active' }
        Mock Read-PnLine { '30m' }
        Invoke-PnVaultDispatch '4' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'vaultwatch' -and ($ToolArgs -contains 'stop') -and ($ToolArgs -contains 'V:\')
        }
        Should -Invoke Read-PnLine -Times 0 -Exactly
    }
    It 'returns $true on back (0)' { (Invoke-PnVaultDispatch '0') | Should -BeTrue }
}

Describe 'notepad submenu dispatch (ghostdraft)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        $script:PN_LOCALE = 'en'
    }
    It '1 (unified note) runs ghostdraft new --clipboard (with a DANGER caveat first)' {
        # Заметка схлопнута в один пункт: пишешь/правишь/копируешь. На Windows честный
        # DANGER-caveat (нет авто-очистки буфера) печатается через Write-Output перед запуском,
        # поэтому проверяем сам вызов (Out-Null глушит подсказку), а не возврат.
        $out = (Invoke-PnNotepadDispatch '1' 6>&1) -join "`n"
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'ghostdraft' -and ($ToolArgs -contains 'new') -and ($ToolArgs -contains '--clipboard')
        }
        $out | Should -Match 'auto-clear'
    }
    It '2 runs ghostdraft pipe (and shows a paste hint first)' {
        $out = (Invoke-PnNotepadDispatch '2' 6>&1) -join "`n"
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'ghostdraft' -and ($ToolArgs -contains 'pipe')
        }
        $out | Should -Match 'nothing is written to disk'
    }
    It '3 runs nothing (third item collapsed away)' {
        Invoke-PnNotepadDispatch '3' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
    It 'unknown choice runs nothing' {
        Invoke-PnNotepadDispatch 'x' | Out-Null
        Should -Invoke Invoke-PnTool -Times 0 -Exactly
    }
    It 'returns $true on back (0)' { (Invoke-PnNotepadDispatch '0') | Should -BeTrue }
}

Describe 'secrets submenu dispatch (seedsplit) + status (top 1)' {
    BeforeEach {
        Mock Invoke-PnTool { }
        Mock Invoke-PnPause { }
        Mock Test-PnTool { $true }
    }
    It 'top choice 1 runs securetrash check (and vaultwatch status)' {
        Invoke-PnDispatch '1' | Out-Null
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'securetrash' -and ($ToolArgs -contains 'check')
        }
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'vaultwatch' -and ($ToolArgs -contains 'status')
        }
    }
    It 'secrets 1 runs seedsplit split (and shows a paste prompt first)' {
        $out = (Invoke-PnSecretsDispatch '1' 6>&1) -join "`n"
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'seedsplit' -and ($ToolArgs -contains 'split')
        }
        $out | Should -Match 'Paste the secret'
    }
    It 'secrets 2 runs seedsplit combine (and shows a one-per-line prompt)' {
        $out = (Invoke-PnSecretsDispatch '2' 6>&1) -join "`n"
        Should -Invoke Invoke-PnTool -Times 1 -Exactly -ParameterFilter {
            $Tool -eq 'seedsplit' -and ($ToolArgs -contains 'combine')
        }
        $out | Should -Match 'one per line'
    }
    It 'returns $true on back (0)' { (Invoke-PnSecretsDispatch '0') | Should -BeTrue }
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
