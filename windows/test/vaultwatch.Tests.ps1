# Pester 5 — логика vaultwatch.ps1 (Windows-порт). Дот-сорс под ST_NO_MAIN=1: определяет
# функции, не запуская диспетчер. vaultwatch трогает Search/Task Scheduler/BitLocker/VSS,
# поэтому эти примитивы МОКАЮТСЯ: тест проверяет оркестровку (state write/read на start/stop/
# status, TTL-планирование, restore, _ttl_fire, парсинг длительности, hooks). CLI — через pwsh.

BeforeAll {
    $env:ST_NO_MAIN = '1'
    $script:ScriptPath = Join-Path $PSScriptRoot '..\vaultwatch.ps1'
    . $script:ScriptPath
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}

AfterAll {
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}

Describe 'duration parsing' {
    It 'parses units and bare seconds' {
        (ConvertFrom-VwDuration '30m') | Should -Be 1800
        (ConvertFrom-VwDuration '2h')  | Should -Be 7200
        (ConvertFrom-VwDuration '45s') | Should -Be 45
        (ConvertFrom-VwDuration '1d')  | Should -Be 86400
        (ConvertFrom-VwDuration '90')  | Should -Be 90
    }
    It 'returns null on garbage' {
        (ConvertFrom-VwDuration 'abc') | Should -Be $null
        (ConvertFrom-VwDuration '3x')  | Should -Be $null
    }
}

Describe 'start — guards a vault and records session state' {
    BeforeEach {
        $script:Work  = Join-Path ([System.IO.Path]::GetTempPath()) ("vw_s_" + [Guid]::NewGuid().ToString('N'))
        $script:Mount = Join-Path $script:Work 'mount'
        New-Item -ItemType Directory -Path $script:Mount -Force | Out-Null
        $script:VW_STATE_DIR = Join-Path $script:Work 'state'
        $env:VW_NO_SPAWN = '1'
        Mock Get-VwSearchState  { 'enabled' }
        Mock Disable-VwSearchIndex { }
        Mock Get-VwCloudLines   { @() }
        Mock Register-VwTtlTask { 'vaultwatch-ttl-test' }
        Mock Register-VwGuardTask { 'vaultwatch-guard-test' }
    }
    AfterEach {
        Remove-Item Env:\VW_NO_SPAWN -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'excludes Windows Search and writes a state file' {
        Invoke-VwStart -ArgList @($script:Mount) -Self 'self.ps1' | Out-Null
        Should -Invoke Disable-VwSearchIndex -Times 1 -Exactly
        $files = @(Get-ChildItem -LiteralPath $script:VW_STATE_DIR -File)
        $files.Count | Should -Be 1
        ($files[0] | Get-Content -Raw) | Should -Match 'search_set=1'
    }

    It 'schedules a TTL task when --ttl is given (VW_NO_SPAWN off)' {
        Remove-Item Env:\VW_NO_SPAWN -ErrorAction SilentlyContinue
        Invoke-VwStart -ArgList @('--ttl', '30m', $script:Mount) -Self 'self.ps1' | Out-Null
        Should -Invoke Register-VwTtlTask -Times 1 -Exactly
        $f = @(Get-ChildItem -LiteralPath $script:VW_STATE_DIR -File)[0]
        ($f | Get-Content -Raw) | Should -Match 'ttl_label=vaultwatch-ttl-test'
        ($f | Get-Content -Raw) | Should -Match 'ttl_secs=1800'
    }

    It 'rejects a bad --ttl duration' {
        { Invoke-VwStart -ArgList @('--ttl', 'nope', $script:Mount) -Self 'x' } | Should -Throw
    }

    It 'registers an unmount-guard and records guard_label (VW_NO_SPAWN off, P2-4)' {
        Remove-Item Env:\VW_NO_SPAWN -ErrorAction SilentlyContinue
        Invoke-VwStart -ArgList @($script:Mount) -Self 'self.ps1' | Out-Null
        Should -Invoke Register-VwGuardTask -Times 1 -Exactly
        $f = @(Get-ChildItem -LiteralPath $script:VW_STATE_DIR -File)[0]
        ($f | Get-Content -Raw) | Should -Match 'guard_label=vaultwatch-guard-'
    }

    It 'registers no guard in unit-test mode (VW_NO_SPAWN=1, P2-4)' {
        Invoke-VwStart -ArgList @($script:Mount) -Self 'self.ps1' | Out-Null   # BeforeEach: VW_NO_SPAWN=1
        Should -Invoke Register-VwGuardTask -Times 0 -Exactly
        $f = @(Get-ChildItem -LiteralPath $script:VW_STATE_DIR -File)[0]
        ($f | Get-Content -Raw) | Should -Not -Match 'guard_label='
    }

    It 'does not overwrite pre-session state on a repeat start (P2-6)' {
        # Первый start: Search был ВКЛ → session должна восстановить его на stop.
        Invoke-VwStart -ArgList @($script:Mount) -Self 'self.ps1' | Out-Null
        # Повторный start: Search уже ВЫКЛ нами → НЕ должен переписать сохранённое исходное состояние.
        Mock Get-VwSearchState { 'disabled' }
        Invoke-VwStart -ArgList @($script:Mount) -Self 'self.ps1' | Out-Null
        $sf = Get-VwStateFile -Mount (Resolve-VwMount -Raw $script:Mount -MustExist $false)
        (Get-Content -LiteralPath $sf -Raw) | Should -Match 'search_was=enabled'
        (Get-Content -LiteralPath $sf -Raw) | Should -Match 'search_set=1'
    }
}

Describe 'stop — restores and reports' {
    BeforeEach {
        $script:Work  = Join-Path ([System.IO.Path]::GetTempPath()) ("vw_t_" + [Guid]::NewGuid().ToString('N'))
        $script:Mount = Join-Path $script:Work 'mount'
        New-Item -ItemType Directory -Path $script:Mount -Force | Out-Null
        $script:VW_STATE_DIR = Join-Path $script:Work 'state'
        New-Item -ItemType Directory -Path $script:VW_STATE_DIR -Force | Out-Null
        Mock Enable-VwSearchIndex { $true }
        Mock Get-VwShadowCount    { 0 }
        Mock Get-VwCloudLines     { @() }
        Mock Unregister-VwTtlTask { }
        Mock Unregister-VwGuardTask { }
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 're-enables search, prints a report, and clears the state file' {
        $sf = Get-VwStateFile -Mount (Resolve-Path $script:Mount).Path
        Set-Content -LiteralPath $sf -Value @("mount=$($script:Mount)", "started=1000", 'search_was=enabled', 'search_set=1', 'ttl_secs=0', 'ttl_force=0')
        $out = (Invoke-VwStop -ArgList @($script:Mount)) -join "`n"
        Should -Invoke Enable-VwSearchIndex -Times 1 -Exactly
        $out | Should -Match 'session report'
        (Test-Path -LiteralPath $sf) | Should -BeFalse
    }

    It 'warns and returns when there is no session' {
        { Invoke-VwStop -ArgList @($script:Mount) } | Should -Not -Throw
    }

    It 'removes an orphaned guard task even when there is no session file (LOW-2)' {
        # session-файла нет, но guard-задача могла осиротеть (провал Unregister) → stop всё равно чистит
        Invoke-VwStop -ArgList @($script:Mount) | Out-Null
        Should -Invoke Unregister-VwGuardTask -Times 1 -Exactly
    }

    It 'removes the unmount-guard task even if guard_label is missing from state (race-safe, P2-4)' {
        $sf = Get-VwStateFile -Mount (Resolve-Path $script:Mount).Path
        # намеренно БЕЗ guard_label в state — снятие должно опираться на mount, не на state
        Set-Content -LiteralPath $sf -Value @("mount=$($script:Mount)", 'started=1000', 'search_was=enabled', 'search_set=1', 'ttl_secs=0', 'ttl_force=0')
        Invoke-VwStop -ArgList @($script:Mount) | Out-Null
        Should -Invoke Unregister-VwGuardTask -Times 1 -Exactly
    }
}

Describe '_ttl_fire — auto-exit' {
    BeforeEach {
        $script:Work  = Join-Path ([System.IO.Path]::GetTempPath()) ("vw_f_" + [Guid]::NewGuid().ToString('N'))
        $script:Mount = Join-Path $script:Work 'mount'
        New-Item -ItemType Directory -Path $script:Mount -Force | Out-Null
        $script:VW_STATE_DIR = Join-Path $script:Work 'state'
        New-Item -ItemType Directory -Path $script:VW_STATE_DIR -Force | Out-Null
        $script:Sf = Get-VwStateFile -Mount (Resolve-Path $script:Mount).Path
        Mock Enable-VwSearchIndex { $true }
        Mock Get-VwShadowCount    { 0 }
        Mock Get-VwCloudLines     { @() }
        Mock Unregister-VwTtlTask { }
        Mock Unregister-VwGuardTask { }
        Mock Invoke-VwDismount    { $true }
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'dismounts when not busy, then runs stop' {
        Set-Content -LiteralPath $script:Sf -Value @("mount=$($script:Mount)", 'started=1000', 'search_was=enabled', 'search_set=1', 'ttl_secs=60', 'ttl_force=0')
        Mock Test-VwMountBusy { $false }
        Mock Test-VwMounted   { $false }
        Invoke-VwTtlFire -ArgList @($script:Mount) | Out-Null
        Should -Invoke Invoke-VwDismount -Times 1 -Exactly
        (Test-Path -LiteralPath $script:Sf) | Should -BeFalse   # stop очистил state
    }

    It 'does NOT dismount a busy mount without --force' {
        Set-Content -LiteralPath $script:Sf -Value @("mount=$($script:Mount)", 'started=1000', 'search_was=enabled', 'search_set=1', 'ttl_secs=60', 'ttl_force=0')
        Mock Test-VwMountBusy { $true }
        Invoke-VwTtlFire -ArgList @($script:Mount) | Out-Null
        Should -Invoke Invoke-VwDismount -Times 0 -Exactly
        (Test-Path -LiteralPath $script:Sf) | Should -BeTrue    # сессия сохранена
    }
}

Describe 'Invoke-VwDismount — force gate (не рвём открытые файлы без --force)' {
    BeforeAll {
        # Lock-BitLocker — системный cmdlet, на macOS-раннере его нет: определяем стаб,
        # чтобы Mock мог перехватить вызов и проверить переданные параметры.
        function Lock-BitLocker { param([string]$MountPoint, [switch]$ForceDismount) }
    }

    It 'does NOT pass -ForceDismount when Force is $false' {
        Mock Lock-BitLocker { }
        Invoke-VwDismount -Mount 'V:\' -Force $false | Out-Null
        Should -Invoke Lock-BitLocker -Times 1 -Exactly -ParameterFilter { -not $ForceDismount }
    }

    It 'passes -ForceDismount only when Force is $true' {
        Mock Lock-BitLocker { }
        Invoke-VwDismount -Mount 'V:\' -Force $true | Out-Null
        Should -Invoke Lock-BitLocker -Times 1 -Exactly -ParameterFilter { [bool]$ForceDismount }
    }
}

Describe 'Test-VwMountBusy — best-effort busy detect (SMB opens)' {
    BeforeAll {
        # Get-SmbOpenFile — системный cmdlet (SMB-модуль), на macOS-раннере отсутствует: стаб под Mock.
        function Get-SmbOpenFile { }
    }

    It 'reports busy when an SMB open file sits on the mount drive' {
        Mock Get-SmbOpenFile { @([pscustomobject]@{ Path = 'V:\secret.kdbx' }) }
        (Test-VwMountBusy -Mount 'V:\') | Should -BeTrue
    }

    It 'reports not busy when no open file matches the drive' {
        Mock Get-SmbOpenFile { @([pscustomobject]@{ Path = 'C:\Users\x\doc.txt' }) }
        (Test-VwMountBusy -Mount 'V:\') | Should -BeFalse
    }

    It 'falls back to not-busy when detection is unavailable (Invoke-VwDismount holds the hard gate)' {
        Mock Get-SmbOpenFile { throw 'not available' }
        (Test-VwMountBusy -Mount 'V:\') | Should -BeFalse
    }
}

Describe 'Assert-VwPs7 — требует PowerShell 7+ (P2-8, fail-closed)' {
    It 'throws on Windows PowerShell 5.1 (TTL/hooks would silently not fire)' {
        { Assert-VwPs7 -Version ([version]'5.1.19041.1') } | Should -Throw
    }
    It 'passes on PowerShell 7+' {
        { Assert-VwPs7 -Version ([version]'7.6.3') } | Should -Not -Throw
    }
}

Describe 'unmount-guard _guard_fire — restore только если том исчез (P2-4)' {
    BeforeEach {
        $script:Work  = Join-Path ([System.IO.Path]::GetTempPath()) ("vw_g_" + [Guid]::NewGuid().ToString('N'))
        $script:Mount = Join-Path $script:Work 'mount'
        New-Item -ItemType Directory -Path $script:Mount -Force | Out-Null
        $script:VW_STATE_DIR = Join-Path $script:Work 'state'
        New-Item -ItemType Directory -Path $script:VW_STATE_DIR -Force | Out-Null
        $script:Sf = Get-VwStateFile -Mount (Resolve-VwMount -Raw $script:Mount -MustExist $false)
        Mock Enable-VwSearchIndex   { $true }
        Mock Get-VwShadowCount      { 0 }
        Mock Get-VwCloudLines       { @() }
        Mock Unregister-VwTtlTask   { }
        Mock Unregister-VwGuardTask { }
    }
    AfterEach { Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue }

    It 'is a no-op while the mount still exists (fired on a write, not an eject)' {
        Set-Content -LiteralPath $script:Sf -Value @("mount=$($script:Mount)", 'started=1000', 'search_was=enabled', 'search_set=1', 'ttl_secs=0', 'ttl_force=0')
        Mock Test-VwMounted { $true }
        Invoke-VwGuardFire -ArgList @($script:Mount) | Out-Null
        Should -Invoke Enable-VwSearchIndex -Times 0 -Exactly   # ничего не восстанавливаем
        (Test-Path -LiteralPath $script:Sf) | Should -BeTrue    # сессия на месте
    }

    It 'restores and clears the session when the mount is gone (eject past stop)' {
        Set-Content -LiteralPath $script:Sf -Value @("mount=$($script:Mount)", 'started=1000', 'search_was=enabled', 'search_set=1', 'ttl_secs=0', 'ttl_force=0')
        Mock Test-VwMounted { $false }
        Invoke-VwGuardFire -ArgList @($script:Mount) | Out-Null
        Should -Invoke Enable-VwSearchIndex -Times 1 -Exactly   # restore прошёл
        (Test-Path -LiteralPath $script:Sf) | Should -BeFalse   # сессия снята
    }

    It 'with no session is a quiet success' {
        Mock Test-VwMounted { $false }
        { Invoke-VwGuardFire -ArgList @($script:Mount) } | Should -Not -Throw
    }
}

Describe 'status' {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("vw_st_" + [Guid]::NewGuid().ToString('N'))
        $script:VW_STATE_DIR = Join-Path $script:Work 'state'
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports no sessions when the state dir is empty' {
        ((Invoke-VwStatus) -join "`n") | Should -Match 'no active sessions'
    }

    It 'lists an active session' {
        New-Item -ItemType Directory -Path $script:VW_STATE_DIR -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:VW_STATE_DIR 'm') -Value @('mount=V:\', 'started=1000', 'search_was=enabled', 'search_set=1', 'ttl_secs=0')
        ((Invoke-VwStatus) -join "`n") | Should -Match 'V:'
    }
}

Describe 'hooks' {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("vw_h_" + [Guid]::NewGuid().ToString('N'))
        $script:ST_HOOK_DIR = Join-Path $script:Work 'hooks'
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs managed hooks and removes only its own' {
        Invoke-VwInstallHooks -Self 'C:\vw\vaultwatch.ps1' | Out-Null
        (Test-Path (Join-Path $script:ST_HOOK_DIR 'post-open.cmd')) | Should -BeTrue
        (Test-Path (Join-Path $script:ST_HOOK_DIR 'post-close.cmd')) | Should -BeTrue
        Invoke-VwUninstallHooks | Out-Null
        (Test-Path (Join-Path $script:ST_HOOK_DIR 'post-open.cmd')) | Should -BeFalse
    }

    It 'does not overwrite a foreign hook' {
        New-Item -ItemType Directory -Path $script:ST_HOOK_DIR -Force | Out-Null
        $foreign = Join-Path $script:ST_HOOK_DIR 'post-open.cmd'
        Set-Content -LiteralPath $foreign -Value 'echo user-owned'
        Invoke-VwInstallHooks -Self 'C:\vw\vaultwatch.ps1' | Out-Null
        (Get-Content -LiteralPath $foreign -Raw) | Should -Match 'user-owned'
    }
}

Describe 'i18n + CLI' {
    It 'returns English watching string by default' {
        $script:VW_LOCALE = 'en'
        (T 'watching' 'V:\') | Should -Match 'Windows Search'
    }
    It 'falls back to the key for an unknown id' {
        (T 'no_such_key') | Should -Be 'no_such_key'
    }
    It 'prints the version (child pwsh)' {
        $out = & pwsh -NoProfile -File $script:ScriptPath version
        # version-agnostic: не привязываемся к конкретному номеру (иначе рвётся на каждом bump)
        ($out -join "`n") | Should -Match 'vaultwatch \d+\.\d+\.\d+'
    }
    It 'exits non-zero on an unknown command (child pwsh)' {
        & pwsh -NoProfile -File $script:ScriptPath bogus *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
}
