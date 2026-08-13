# Pester 5 — логика panic.ps1 (Windows-порт). Дот-сорс под ST_NO_MAIN=1: определяет
# функции, не запуская диспетчер. panic — это сплошные side-effect'ы (lock/dismount/kill),
# поэтому каждый системный примитив обёрнут в свою функцию и МОКАЕТСЯ: тест проверяет
# оркестровку (что и сколько раз вызвано, счётчики, --hard-гейт), не трогая реальные
# BitLocker/VeraCrypt/экран. CLI-уровень (версия, exit-коды) — через свежий pwsh.

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
        # Два разблокированных BitLocker-тома + один VeraCrypt → ожидаем счётчик 3.
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
        # Не должно бросать наружу; clipboard+screen всё равно отрабатывают.
        { Invoke-PnNow -ArgList @() } | Should -Not -Throw
        Should -Invoke Invoke-PnClearClipboard -Times 1 -Exactly
        Should -Invoke Invoke-PnLockScreen -Times 1 -Exactly
    }

    It 'honestly reports a locked screen on success' {
        $out = Invoke-PnNow -ArgList @()
        ($out -join "`n") | Should -Match 'screen locked'
    }

    It 'does NOT claim a locked screen when the lock fails — and warns instead' {
        # Зеркало bash-регрессии: LockWorkStation упал → не врём «locked», а громко warn.
        # warn идёт в stderr через [Console]::Error (не ловится $out), поэтому мокаем
        # Write-PnWarn и проверяем сам факт честного предупреждения с текстом lock_fail.
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
        $out | Should -Match '2'           # счётчик томов
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
        # Version-agnostic: не хардкодим номер, чтобы bump версии не ронял тест.
        $out = & pwsh -NoProfile -File $script:ScriptPath version
        ($out -join "`n") | Should -Match 'panic \d+\.\d+\.\d+'
    }
    It 'exits non-zero on an unknown command' {
        & pwsh -NoProfile -File $script:ScriptPath bogus *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
    It 'names the missing hotkey instead of calling it an unknown command' {
        # README документирует `panic hotkey`, а Windows-порт его не несёт. «Unknown command»
        # тут читается как сломанная установка; пользователь должен получить причину и рабочий
        # обходной путь средствами самой ОС.
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
