# Pester 5 — panic.ps1 logic (Windows port). Dot-sourced under ST_NO_MAIN=1: defines
# the functions without running the dispatcher. panic is pure side effects (lock/dismount/kill),
# so every system primitive is wrapped in its own function and MOCKED: the tests verify
# the orchestration (what got called and how many times, counters, the --hard gate) without
# touching real BitLocker/VeraCrypt/screen. The CLI level (version, exit codes) — via a fresh pwsh.

BeforeAll {
    $env:ST_NO_MAIN = '1'
    $script:ScriptPath = Join-Path $PSScriptRoot '..\panic.ps1'
    . $script:ScriptPath
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}

AfterAll {
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}

Describe 'panic now — orchestration' {
    BeforeEach {
        # Two unlocked BitLocker volumes + one VeraCrypt → expect a counter of 3.
        Mock Get-PnBitLockerUnlocked { @('D:', 'E:') }
        Mock Get-PnVeraCryptMounted  { @('F:') }
        Mock Invoke-PnLockBitLocker     { }
        Mock Invoke-PnDismountVeraCrypt { }
        Mock Invoke-PnClearClipboard    { }
        Mock Invoke-PnLockScreen        { $true }
        Mock Invoke-PnKillCloudDaemons  { }
        Mock Invoke-PnClearRecentItems  { }
    }

    It 'locks each BitLocker volume, dismounts VeraCrypt, clears clipboard, locks screen' {
        $out = Invoke-PnNow -ArgList @()
        Should -Invoke Invoke-PnLockBitLocker -Times 2 -Exactly
        Should -Invoke Invoke-PnDismountVeraCrypt -Times 1 -Exactly
        Should -Invoke Invoke-PnClearClipboard -Times 1 -Exactly
        Should -Invoke Invoke-PnLockScreen -Times 1 -Exactly
        ($out -join "`n") | Should -Match '3'
    }

    It 'does NOT kill cloud daemons or clear recent items without --hard' {
        Invoke-PnNow -ArgList @() | Out-Null
        Should -Invoke Invoke-PnKillCloudDaemons -Times 0 -Exactly
        Should -Invoke Invoke-PnClearRecentItems -Times 0 -Exactly
    }

    It '--hard kills cloud daemons and clears recent items' {
        Invoke-PnNow -ArgList @('--hard') | Out-Null
        Should -Invoke Invoke-PnKillCloudDaemons -Times 1 -Exactly
        Should -Invoke Invoke-PnClearRecentItems -Times 1 -Exactly
    }

    It 'reports 0 when nothing is mounted/unlocked' {
        Mock Get-PnBitLockerUnlocked { @() }
        Mock Get-PnVeraCryptMounted  { @() }
        $out = Invoke-PnNow -ArgList @()
        Should -Invoke Invoke-PnDismountVeraCrypt -Times 0 -Exactly
        ($out -join "`n") | Should -Match '\b0\b'
    }

    It 'still clears clipboard and locks screen even with no volumes' {
        Mock Get-PnBitLockerUnlocked { @() }
        Mock Get-PnVeraCryptMounted  { @() }
        Invoke-PnNow -ArgList @() | Out-Null
        Should -Invoke Invoke-PnClearClipboard -Times 1 -Exactly
        Should -Invoke Invoke-PnLockScreen -Times 1 -Exactly
    }

    It 'a failed BitLocker lock does not abort the run (best-effort)' {
        Mock Invoke-PnLockBitLocker { throw 'access denied' }
        # Must not throw outward; clipboard+screen still run.
        { Invoke-PnNow -ArgList @() } | Should -Not -Throw
        Should -Invoke Invoke-PnClearClipboard -Times 1 -Exactly
        Should -Invoke Invoke-PnLockScreen -Times 1 -Exactly
    }

    It 'honestly reports a locked screen on success' {
        $out = Invoke-PnNow -ArgList @()
        ($out -join "`n") | Should -Match 'screen locked'
    }

    It 'does NOT claim a locked screen when the lock fails — and warns instead' {
        # Mirror of the bash regression: LockWorkStation failed → don't lie "locked", warn loudly.
        # warn goes to stderr via [Console]::Error (not captured by $out), so we mock
        # Write-PnWarn and verify the honest warning itself, with the lock_fail text.
        Mock Invoke-PnLockScreen { $false }
        Mock Write-PnWarn { }
        $out = Invoke-PnNow -ArgList @()
        ($out -join "`n") | Should -Not -Match 'screen locked\.'
        Should -Invoke Write-PnWarn -Times 1 -Exactly -ParameterFilter { $Msg -match 'could NOT lock' }
    }
}

Describe 'panic status — read-only preflight' {
    It 'lists unlocked volumes and a non-empty clipboard' {
        Mock Get-PnBitLockerUnlocked  { @('D:') }
        Mock Get-PnVeraCryptMounted   { @('F:') }
        Mock Test-PnClipboardNonEmpty { $true }
        Mock Test-PnBitLockerOn       { $true }
        Mock Get-PnRunningCloudDaemons { @('OneDrive') }
        $out = (Invoke-PnStatus) -join "`n"
        $out | Should -Match '2'           # volume counter
        $out | Should -Match 'D:'
        $out | Should -Match 'F:'
        $out | Should -Match 'OneDrive'
    }

    It 'makes no changes (never calls a mutating primitive)' {
        Mock Get-PnBitLockerUnlocked  { @() }
        Mock Get-PnVeraCryptMounted   { @() }
        Mock Test-PnClipboardNonEmpty { $false }
        Mock Test-PnBitLockerOn       { $false }
        Mock Get-PnRunningCloudDaemons { @() }
        Mock Invoke-PnLockBitLocker     { }
        Mock Invoke-PnDismountVeraCrypt { }
        Mock Invoke-PnClearClipboard    { }
        Mock Invoke-PnLockScreen        { }
        Invoke-PnStatus | Out-Null
        Should -Invoke Invoke-PnLockBitLocker -Times 0 -Exactly
        Should -Invoke Invoke-PnDismountVeraCrypt -Times 0 -Exactly
        Should -Invoke Invoke-PnClearClipboard -Times 0 -Exactly
        Should -Invoke Invoke-PnLockScreen -Times 0 -Exactly
    }
}

Describe 'i18n' {
    It 'returns English status header by default' {
        $script:PN_LOCALE = 'en'
        (T 'status_header') | Should -Match 'read-only preflight'
    }
    It 'returns Russian status header under ru locale' {
        $script:PN_LOCALE = 'ru'
        (T 'status_header') | Should -Match 'только чтение'
    }
    It 'falls back to the key for an unknown id' {
        (T 'no_such_key') | Should -Be 'no_such_key'
    }
}

Describe 'CLI surface (child pwsh)' {
    It 'prints the version' {
        # Version-agnostic: don't hardcode the number so a version bump doesn't break the test.
        $out = & pwsh -NoProfile -File $script:ScriptPath version
        ($out -join "`n") | Should -Match 'panic \d+\.\d+\.\d+'
    }
    It 'exits non-zero on an unknown command' {
        & pwsh -NoProfile -File $script:ScriptPath bogus *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
    It 'names the missing hotkey instead of calling it an unknown command' {
        # The README documents `panic hotkey`, but the Windows port doesn't ship it. "Unknown command"
        # here reads like a broken install; the user should get the reason and a working
        # workaround using the OS itself.
        $err = (& pwsh -NoProfile -File $script:ScriptPath hotkey 2>&1 | Out-String)
        $LASTEXITCODE | Should -Not -Be 0
        $err | Should -Not -Match 'Unknown command'
        $err | Should -Match 'macOS-only'
        $err | Should -Match 'Ctrl\+Alt\+P'
    }
    It 'exits non-zero with no command (prints usage)' {
        & pwsh -NoProfile -File $script:ScriptPath *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
}
