# Pester 5 tests for securetrash.ps1 (Windows port, BETA).
# All Windows-specific cmdlets/exes are mocked — only the dispatcher,
# i18n and branching are checked. Real BitLocker/VHDX/VeraCrypt behavior is NOT verified.

BeforeAll {
    $env:ST_NO_MAIN = '1'   # disable the dispatcher on dot-source
    $script:ScriptPath = Join-Path $PSScriptRoot '..\securetrash.ps1'
    . $script:ScriptPath

    # Write-StWarn/Write-StErr write directly to [Console]::Error (parity with bash warn/err >&2),
    # and PowerShell redirection does not catch that output. The helper swaps the console stderr
    # for a StringWriter and returns stdout+information stream+stderr as a single string.
    function global:Get-StCombinedOutput {
        param([scriptblock]$Body)
        $sw = New-Object System.IO.StringWriter
        $orig = [Console]::Error
        [Console]::SetError($sw)
        try { $out = & $Body 6>&1 } finally { [Console]::SetError($orig) }
        return ((@($out) -join "`n") + "`n" + $sw.ToString())
    }
}

AfterAll {
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}

# --- P0-1: securetrash.ps1 must respect ST_VAULT_PATH (the destructive target = container) ---
# Otherwise the GUI/tray/launcher show one vault (via ST_VAULT_*) while destroy/reset/open
# hit the hardcoded default. Parity with bash securetrash.
Describe 'vault container path env override (P0-1)' {
    AfterEach { Remove-Item Env:\ST_VAULT_PATH -ErrorAction SilentlyContinue }

    It 'Get-StVaultPath honors ST_VAULT_PATH when set' {
        $env:ST_VAULT_PATH = 'C:\custom\myvault.vhdx'
        Get-StVaultPath | Should -Be 'C:\custom\myvault.vhdx'
    }

    It 'Get-StVaultPath falls back to the default when ST_VAULT_PATH is unset' {
        Remove-Item Env:\ST_VAULT_PATH -ErrorAction SilentlyContinue
        Get-StVaultPath | Should -Match 'SecureVault\.vhdx$'
    }
}

Describe 'dispatcher' {

    BeforeEach {
        $env:ST_ASSUME_YES = '1'
        Remove-Item Env:\ST_LANG -ErrorAction SilentlyContinue
        $script:ST_LOCALE = 'en'
    }

    It 'no-arg shows usage and exits non-zero' {
        # Invoke-Main with empty arguments must show usage and exit with code 1.
        $code = & pwsh -NoProfile -Command "`$env:ST_NO_MAIN='1'; . '$script:ScriptPath'; Invoke-Main -Argv @()"
        $LASTEXITCODE | Should -Be 1
        ($code -join "`n") | Should -Match 'Usage:'
    }

    It 'unknown command exits non-zero with message' {
        # 2>&1: the error message goes to stderr (parity with bash), usage to stdout.
        $out = & pwsh -NoProfile -Command "`$env:ST_NO_MAIN='1'; . '$script:ScriptPath'; Invoke-Main -Argv @('bogus')" 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'Unknown command'
    }

    It 'version prints beta label' {
        $out = Invoke-StVersion 6>&1
        ($out -join "`n") | Should -Match 'Windows, beta'
        # The version is not pinned — check the semver format, not a specific number.
        ($out -join "`n") | Should -Match '\d+\.\d+\.\d+'
    }

    It 'usage documents the --yes flag' {
        $out = (Show-StUsage 6>&1) -join "`n"
        $out | Should -Match '--yes'
    }

    It 'usage lists vault status and destroy-old (bash parity)' {
        $out = (Show-StUsage 6>&1) -join "`n"
        $out | Should -Match 'status'
        $out | Should -Match 'destroy-old'
    }

    It 'accepts -v/--version and -h/--help aliases (bash parity)' {
        foreach ($flag in @('-v', '--version')) {
            $out = & pwsh -NoProfile -Command "`$env:ST_NO_MAIN='1'; . '$script:ScriptPath'; Invoke-Main -Argv @('$flag')"
            $LASTEXITCODE | Should -Be 0 -Because "$flag must not be an unknown command"
            ($out -join "`n") | Should -Match 'securetrash \d+\.\d+\.\d+'
        }
        foreach ($flag in @('-h', '--help')) {
            $out = & pwsh -NoProfile -Command "`$env:ST_NO_MAIN='1'; . '$script:ScriptPath'; Invoke-Main -Argv @('$flag')"
            $LASTEXITCODE | Should -Be 0 -Because "$flag must not be an unknown command"
            ($out -join "`n") | Should -Match 'Usage:'
        }
    }

    It 'writes info to stdout, not to the host (launcher/redirect parity)' {
        # 1>&1 does not merge the information stream: if the message went to Write-Host, this would be empty.
        $out = & pwsh -NoProfile -Command "`$env:ST_NO_MAIN='1'; . '$script:ScriptPath'; Write-StInfo 'hello' 6>`$null"
        ($out -join "`n") | Should -Match 'hello'
    }

    It 'writes warn/err to stderr, not to stdout (bash parity)' {
        $out = & pwsh -NoProfile -Command "`$env:ST_NO_MAIN='1'; . '$script:ScriptPath'; Write-StWarn 'warned'; Write-StErr 'failed'" 2>$null
        ($out -join "`n") | Should -Not -Match 'warned'
        ($out -join "`n") | Should -Not -Match 'failed'
    }
}

Describe 'size units — bash parity (P2-8)' {

    It 'accepts the hdiutil-style suffixes bash accepts' {
        Convert-StSizeToMb -Size '1g'   | Should -Be 1024
        Convert-StSizeToMb -Size '512'  | Should -Be 512      # bare number = MB
        Convert-StSizeToMb -Size '512m' | Should -Be 512
        Convert-StSizeToMb -Size '1t'   | Should -Be 1048576
        Convert-StSizeToMb -Size '2048k'| Should -Be 2
        Convert-StSizeToMb -Size '1500k'| Should -Be 2        # rounds up, not down to 1 MB
    }

    It 'rejects an absurdly long number instead of throwing a raw overflow' {
        $huge = ('9' * 40) + 't'
        Convert-StSizeToMb -Size $huge | Should -Be 0
        { Assert-StValidSize -Size $huge 6>$null } | Should -Throw -ExceptionType ([StExit])
    }

    It 'rejects zero and garbage exactly like bash' {
        { Assert-StValidSize -Size '0'  6>$null } | Should -Throw
        { Assert-StValidSize -Size '0g' 6>$null } | Should -Throw
        { Assert-StValidSize -Size '1x' 6>$null } | Should -Throw
        { Assert-StValidSize -Size ''   6>$null } | Should -Throw
        { Assert-StValidSize -Size '5g' 6>$null } | Should -Not -Throw
    }
}

Describe 'Get-StBitLockerState — tri-state, зеркало macOS _fv_state (F5)' {
    BeforeAll {
        # Pester mocks only existing commands; on a runner without the BitLocker module — a stub.
        if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
            function script:Get-BitLockerVolume { [CmdletBinding()] param($MountPoint) }
        }
    }
    It 'ProtectionStatus On -> on' {
        Mock Get-BitLockerVolume { [pscustomobject]@{ ProtectionStatus = 'On' } }
        Get-StBitLockerState | Should -Be 'on'
    }
    It 'ProtectionStatus Off -> off' {
        Mock Get-BitLockerVolume { [pscustomobject]@{ ProtectionStatus = 'Off' } }
        Get-StBitLockerState | Should -Be 'off'
    }
    It 'ProtectionStatus Unknown -> unknown' {
        Mock Get-BitLockerVolume { [pscustomobject]@{ ProtectionStatus = 'Unknown' } }
        Get-StBitLockerState | Should -Be 'unknown'
    }
    It 'cmdlet бросает (Windows Home, нет Get-BitLockerVolume) -> unknown, не ложный off' {
        Mock Get-BitLockerVolume { throw 'not available' }
        Get-StBitLockerState | Should -Be 'unknown'
    }
}

Describe 'check' {

    BeforeEach {
        Remove-Item Env:\ST_LANG -ErrorAction SilentlyContinue
        $script:ST_LOCALE = 'en'
    }

    It 'SSD + BitLocker ON -> honest SSD line + native vault availability (EN)' {
        Mock Get-StDiskKind { 'ssd' }
        Mock Get-StBitLockerState { 'on' }
        Mock Get-StBitLockerCapable { $true }
        Mock Get-StVeraCryptPath { $null }

        $out = Get-StCombinedOutput { Invoke-StCheck }
        $out | Should -Match 'BitLocker: ON'
        $out | Should -Match 'NO guarantees'
        $out | Should -Match 'native BitLocker VHDX available'
    }

    It 'BitLocker OFF -> loud English warning' {
        Mock Get-StDiskKind { 'ssd' }
        Mock Get-StBitLockerState { 'off' }
        Mock Get-StBitLockerCapable { $true }
        Mock Get-StVeraCryptPath { $null }

        $out = Get-StCombinedOutput { Invoke-StCheck }
        $out | Should -Match 'BitLocker is OFF'
        $out | Should -Match 'main protection is missing'
    }

    It 'BitLocker unknown -> honest "unknown", not a false OFF (mirror of macOS F5)' {
        Mock Get-StDiskKind { 'ssd' }
        Mock Get-StBitLockerState { 'unknown' }
        Mock Get-StBitLockerCapable { $false }
        Mock Get-StVeraCryptPath { $null }

        $out = Get-StCombinedOutput { Invoke-StCheck }
        $out | Should -Match 'BitLocker: unknown'
        $out | Should -Match 'NOT protected'
        $out | Should -Not -Match 'BitLocker is OFF'
    }

    # On real hardware the unknown verdict came from missing rights, not from a broken query:
    # Get-BitLockerVolume refuses without elevation, and an elevated re-run answered at once.
    It 'BitLocker unknown without elevation -> names the elevated prompt as the missing piece' {
        Mock Get-StDiskKind { 'ssd' }
        Mock Get-StBitLockerState { 'unknown' }
        Mock Get-StBitLockerCapable { $true }
        Mock Get-StVeraCryptPath { $null }
        Mock Test-StElevated { $false }

        $out = Get-StCombinedOutput { Invoke-StCheck }
        $out | Should -Match 'elevated prompt'
        $out | Should -Match 'NOT protected'
    }

    It 'BitLocker unknown WITH elevation -> plain unknown, no misleading elevation advice' {
        Mock Get-StDiskKind { 'ssd' }
        Mock Get-StBitLockerState { 'unknown' }
        Mock Get-StBitLockerCapable { $true }
        Mock Get-StVeraCryptPath { $null }
        Mock Test-StElevated { $true }

        $out = Get-StCombinedOutput { Invoke-StCheck }
        $out | Should -Match 'could not determine status'
    }

    It 'i18n: ST_LANG=ru -> Russian substring' {
        $env:ST_LANG = 'ru'
        $script:ST_LOCALE = Get-StLocale
        Mock Get-StDiskKind { 'ssd' }
        Mock Get-StBitLockerState { 'on' }
        Mock Get-StBitLockerCapable { $true }
        Mock Get-StVeraCryptPath { $null }

        $out = Get-StCombinedOutput { Invoke-StCheck }
        $out | Should -Match 'ВКЛЮЧЕН'
        Remove-Item Env:\ST_LANG -ErrorAction SilentlyContinue
        $script:ST_LOCALE = 'en'
    }

    It 'i18n: pre-set ST_LOCALE is respected by the script itself (subprocess)' {
        $out = & pwsh -NoProfile -Command @"
`$env:ST_NO_MAIN='1'; `$env:ST_LOCALE='ru'; . '$script:ScriptPath'
Write-Output `$script:ST_LOCALE
"@ 2>&1
        ($out -join "`n").Trim() | Should -Be 'ru'
    }

    It 'unknown disk type -> honest "could not be determined", not an HDD claim' {
        Mock Get-StDiskKind { 'unknown' }
        Mock Get-StBitLockerState { 'on' }
        Mock Get-StBitLockerCapable { $true }
        Mock Get-StVeraCryptPath { $null }

        $out = Get-StCombinedOutput { Invoke-StCheck }
        $out | Should -Match 'could not be determined'
        $out | Should -Match 'NO guarantee'
        $out | Should -Not -Match 'Disk: HDD'
    }
}

Describe 'diskpart input validation (#3)' {

    BeforeEach { $script:ST_LOCALE = 'en' }

    It 'rejects a non-numeric size' {
        { Assert-StValidSize -Size '10; rm -rf' 6>$null } | Should -Throw
        { Assert-StValidSize -Size 'abc' 6>$null } | Should -Throw
    }

    It 'accepts a numeric size' {
        { Assert-StValidSize -Size '1024' } | Should -Not -Throw
    }

    It 'rejects a multi-char / non-letter drive letter' {
        { Assert-StValidDriveLetter -DriveLetter 'VV' 6>$null } | Should -Throw
        { Assert-StValidDriveLetter -DriveLetter '1' 6>$null } | Should -Throw
    }

    It 'accepts a single A-Z drive letter' {
        { Assert-StValidDriveLetter -DriveLetter 'V' } | Should -Not -Throw
    }

    It 'rejects a path containing CRLF or double-quote (diskpart injection)' {
        { Assert-StValidVaultPath -Path "C:\a`"`nattach vdisk" 6>$null } | Should -Throw
        { Assert-StValidVaultPath -Path "C:\a`r`nfoo" 6>$null } | Should -Throw
    }

    It 'accepts a normal path' {
        { Assert-StValidVaultPath -Path 'C:\Users\x\SecureVault.vhdx' } | Should -Not -Throw
    }

    It 'Invoke-StDiskpart throws on non-zero exit code' {
        # Replace diskpart with a function that sets $LASTEXITCODE != 0.
        Mock Set-Content { }
        function diskpart { $global:LASTEXITCODE = 1 }
        { Invoke-StDiskpart -Script 'noop' 6>$null } | Should -Throw
    }
}

Describe 'free drive letter (#3)' {

    It 'picks the first letter not already in use' {
        Mock Get-PSDrive {
            @(
                [pscustomobject]@{ Name = 'C' },
                [pscustomobject]@{ Name = 'D' },
                [pscustomobject]@{ Name = 'E' }
            )
        }
        Get-StFreeDriveLetter | Should -Be 'F'
    }
}

Describe 'vault create branching' {

    BeforeEach {
        $env:ST_ASSUME_YES = '1'
        $env:ST_VAULT_PASS = 'testpass123'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StFreeDriveLetter { 'W' }
        Mock Set-StPrivateAcl { }
        Mock Write-StVaultBackend { }
    }

    AfterEach {
        Remove-Item Env:\ST_VAULT_PASS -ErrorAction SilentlyContinue
    }

    It 'BitLocker capable -> native VHDX path invoked + backend recorded' {
        Mock Get-StBitLockerCapable { $true }
        Mock Get-StVeraCryptPath { $null }
        Mock New-StBitLockerVault { }

        Invoke-StVault -VaultArgs @('create') 6>&1 | Out-Null
        Should -Invoke New-StBitLockerVault -Times 1 -Exactly
        Should -Invoke Write-StVaultBackend -Times 1 -Exactly -ParameterFilter { $Backend -eq 'bitlocker' }
    }

    It 'no BitLocker + VeraCrypt -> GUI-only message, NO automated create, NO password on argv' {
        Mock Get-StBitLockerCapable { $false }
        Mock Get-StVeraCryptPath { 'C:\Program Files\VeraCrypt\VeraCrypt.exe' }
        Mock New-StBitLockerVault { }

        # #2: automated VeraCrypt create is forbidden -> honest refusal (StExit) + GUI instructions.
        $out = ''
        $threw = $false
        try { $out = (Invoke-StVault -VaultArgs @('create') 6>&1) -join "`n" }
        catch [StExit] { $threw = $true; $out = $_.TargetObject }
        $threw | Should -BeTrue
        Should -Invoke New-StBitLockerVault -Times 0 -Exactly
    }

    It 'neither -> honest failure (StExit thrown), no BitLocker create' {
        Mock Get-StBitLockerCapable { $false }
        Mock Get-StVeraCryptPath { $null }
        Mock New-StBitLockerVault { }

        { Invoke-StVault -VaultArgs @('create') 6>$null } | Should -Throw
        Should -Invoke New-StBitLockerVault -Times 0 -Exactly
    }

    It 'neither -> non-zero exit + honest message through dispatcher (subprocess)' {
        $out = & pwsh -NoProfile -Command @"
`$env:ST_NO_MAIN='1'; `$env:ST_LANG='en'; `$env:ST_VAULT_PASS='x'; . '$script:ScriptPath'
function Get-StBitLockerCapable { `$false }
function Get-StVeraCryptPath { `$null }
function Get-StVaultPath { '/tmp/st_nonexistent_vault.vhdx' }
Invoke-Main -Argv @('vault','create')
"@ 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'unavailable'
    }
}

Describe 'new vault password: length floor + confirmation' {

    BeforeEach {
        Remove-Item Env:\ST_VAULT_PASS -ErrorAction SilentlyContinue
        $script:ST_LOCALE = 'en'
    }

    It 'refuses a password below the minimum (StExit thrown, no second prompt)' {
        Mock Read-Host { ConvertTo-SecureString -String 'short' -AsPlainText -Force }
        { Get-StVaultPasswordNewSecure 6>$null } | Should -Throw
        Should -Invoke Read-Host -Times 1 -Exactly
    }

    It 'refuses a mismatched confirmation' {
        $script:calls = 0
        Mock Read-Host {
            $script:calls++
            $v = if ($script:calls -eq 1) { 'correct-horse-battery' } else { 'correct-horse-batteru' }
            ConvertTo-SecureString -String $v -AsPlainText -Force
        }
        { Get-StVaultPasswordNewSecure 6>$null } | Should -Throw
    }

    It 'accepts a confirmed password of sufficient length' {
        Mock Read-Host { ConvertTo-SecureString -String 'correct-horse-battery' -AsPlainText -Force }
        $sec = Get-StVaultPasswordNewSecure
        $sec | Should -BeOfType [System.Security.SecureString]
        $sec.Length | Should -Be 21
    }

    It 'comparison is case-sensitive' {
        $script:calls = 0
        Mock Read-Host {
            $script:calls++
            $v = if ($script:calls -eq 1) { 'correct-horse-battery' } else { 'Correct-horse-battery' }
            ConvertTo-SecureString -String $v -AsPlainText -Force
        }
        { Get-StVaultPasswordNewSecure 6>$null } | Should -Throw
    }

    It 'ST_VAULT_PASS bypasses both prompts (test-only hook)' {
        $env:ST_VAULT_PASS = 'x'
        Mock Read-Host { throw 'must not prompt' }
        (Get-StVaultPasswordNewSecure).Length | Should -Be 1
        Should -Invoke Read-Host -Times 0 -Exactly
        Remove-Item Env:\ST_VAULT_PASS -ErrorAction SilentlyContinue
    }
}

Describe 'VeraCrypt never receives a password on argv (#2)' {

    It 'New-StVeraCryptVault no longer exists (automated VeraCrypt removed)' {
        # The function that passed /password on argv was removed entirely.
        (Get-Command New-StVeraCryptVault -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'script source contains no /password argv usage' {
        $src = Get-Content -LiteralPath $script:ScriptPath -Raw
        $src | Should -Not -Match '/password'
    }

    It 'VeraCrypt manual message points to the GUI and explains the argv leak' {
        $script:ST_LOCALE = 'en'
        $msg = T 'vault_vc_manual'
        $msg | Should -Match 'GUI'
        $msg | Should -Match 'command line'
    }
}

Describe 'vault open: BitLocker unlock + verify (#9, #10)' {

    BeforeEach {
        $env:ST_VAULT_PASS = 'testpass123'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StFreeDriveLetter { 'W' }
        Mock Invoke-StDiskpart { }
        Mock Show-StVaultInExplorer { }
    }

    AfterEach { Remove-Item Env:\ST_VAULT_PASS -ErrorAction SilentlyContinue }

    It 'attaches, unlocks BitLocker and prints mounted when unlock verified' {
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Unlock-StBitLockerVault { $true }

        $out = (Invoke-StVault -VaultArgs @('open') 6>&1) -join "`n"
        Should -Invoke Unlock-StBitLockerVault -Times 1 -Exactly
        $out | Should -Match 'Mounted'
    }

    It 'honest error (StExit) when BitLocker unlock not verified' {
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Unlock-StBitLockerVault { $false }

        { Invoke-StVault -VaultArgs @('open') 6>$null } | Should -Throw
        Should -Invoke Unlock-StBitLockerVault -Times 1 -Exactly
    }

    It 'veracrypt backend -> GUI-only (StExit), never auto-mounts, never unlocks BitLocker' {
        Mock Read-StVaultBackend { 'veracrypt' }
        Mock Unlock-StBitLockerVault { $true }

        { Invoke-StVault -VaultArgs @('open') 6>$null } | Should -Throw
        Should -Invoke Unlock-StBitLockerVault -Times 0 -Exactly
    }
}

Describe 'vault lifecycle hooks (F1)' {

    BeforeEach {
        $env:ST_VAULT_PASS = 'testpass123'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StFreeDriveLetter { 'W' }
        Mock Invoke-StDiskpart { }
        Mock Write-StVaultMount { }
        Mock Read-StVaultMount { 'W:\' }
        Mock Remove-StVaultMount { }
        Mock Invoke-StVaultHook { }
        Mock Show-StVaultInExplorer { }
    }

    AfterEach { Remove-Item Env:\ST_VAULT_PASS -ErrorAction SilentlyContinue }

    It 'open: records the mount sidecar and fires post-open hook with the mount' {
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Unlock-StBitLockerVault { $true }

        Invoke-StVault -VaultArgs @('open') 6>&1 | Out-Null
        Should -Invoke Write-StVaultMount -Times 1 -Exactly -ParameterFilter { $Mount -eq 'W:\' }
        Should -Invoke Invoke-StVaultHook -Times 1 -Exactly -ParameterFilter { $Event -eq 'post-open' -and $Mount -eq 'W:\' }
    }

    It 'open: failed BitLocker unlock does NOT record mount nor fire post-open hook' {
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Unlock-StBitLockerVault { $false }

        { Invoke-StVault -VaultArgs @('open') 6>$null } | Should -Throw
        Should -Invoke Write-StVaultMount -Times 0 -Exactly
        Should -Invoke Invoke-StVaultHook -Times 0 -Exactly
    }

    It 'close: fires post-close hook with the recorded mount and clears the sidecar' {
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Dismount-StVault { }

        Invoke-StVault -VaultArgs @('close') 6>&1 | Out-Null
        Should -Invoke Invoke-StVaultHook -Times 1 -Exactly -ParameterFilter { $Event -eq 'post-close' -and $Mount -eq 'W:\' }
        Should -Invoke Remove-StVaultMount -Times 1 -Exactly
    }

    It 'close: veracrypt backend never fires hooks (GUI-only, StExit)' {
        Mock Read-StVaultBackend { 'veracrypt' }
        Mock Dismount-StVault { }

        { Invoke-StVault -VaultArgs @('close') 6>$null } | Should -Throw
        Should -Invoke Invoke-StVaultHook -Times 0 -Exactly
    }
}

Describe 'vault status — bash parity (P2-8)' {

    BeforeEach {
        $script:ST_LOCALE = 'en'
        Mock Test-StAsidePresent { $false }
    }

    It 'reports OPEN with the real mount point when the container is attached' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StVaultState { 'mounted' }
        Mock Get-StMountedVaultRoot { 'W:\' }

        $out = (Invoke-StVault -VaultArgs @('status') 6>&1) -join "`n"
        $out | Should -Match 'OPEN'
        $out | Should -Match 'W:'
    }

    It 'reports CLOSED when the container exists but is not attached' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StVaultState { 'unmounted' }

        $out = (Invoke-StVault -VaultArgs @('status') 6>&1) -join "`n"
        $out | Should -Match 'CLOSED'
    }

    It 'says "could not be determined" instead of CLOSED when the state is unknown' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StVaultState { 'unknown' }

        Mock Stop-StCommand { }   # the wording is what this test is about; the exit code has its own
        $out = Get-StCombinedOutput { Invoke-StVault -VaultArgs @('status') }
        $out | Should -Match 'NOT be determined'
        $out | Should -Not -Match 'is CLOSED \(not mounted\)'   # a false "closed" is exactly what must not appear here
    }

    It 'an undetermined state also exits non-zero, so a script is not told "closed" either' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StVaultState { 'unknown' }

        { Invoke-StVault -VaultArgs @('status') 6>$null 3>$null } | Should -Throw
    }

    It 'fails with a non-zero exit when there is no container at all' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        { Invoke-StVault -VaultArgs @('status') 6>$null } | Should -Throw
    }

    It 'status never mounts, unmounts or destroys anything (read-only)' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StVaultState { 'unmounted' }
        Mock Invoke-StDiskpart { }
        Mock Dismount-StVault { }
        Mock Remove-StVaultContainer { }

        Invoke-StVault -VaultArgs @('status') 6>&1 | Out-Null
        Should -Invoke Invoke-StDiskpart -Times 0 -Exactly
        Should -Invoke Dismount-StVault -Times 0 -Exactly
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
    }
}

# Found on real Windows hardware (2026-08-13), invisible to every mocked test until now:
# `vault create 50m` died inside Enable-BitLocker AFTER diskpart had created, attached and
# formatted the vhdx — and `vault status` then reported "[ok] Container is OPEN (mounted at
# E:\)" for a volume that Get-BitLockerVolume showed as FullyDecrypted / ProtectionStatus Off.
Describe 'vault: attached is not open, and a failed create leaves nothing behind' {

    BeforeEach {
        $script:ST_LOCALE = 'en'
        $env:ST_ASSUME_YES = '1'
        $env:ST_VAULT_PASS = 'testpass123'
        Mock Test-StAsidePresent { $false }
        Mock Get-StBitLockerCapable { $true }
        Mock Get-StVeraCryptPath { $null }
        Mock Get-StFreeDriveLetter { 'W' }
        Mock Set-StPrivateAcl { }
        Mock Write-StVaultBackend { }
    }

    AfterEach {
        Remove-Item Env:\ST_VAULT_PASS -ErrorAction SilentlyContinue
        Remove-Item Env:\ST_ASSUME_YES -ErrorAction SilentlyContinue
    }

    It 'a locked volume is reported as LOCKED, never as OPEN' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StVaultState { 'mounted' }
        Mock Get-StMountedVaultRoot { 'E:\' }
        Mock Get-StVaultProtection { 'locked' }

        $out = Get-StCombinedOutput { Invoke-StVault -VaultArgs @('status') }
        $out | Should -Match 'LOCKED'
        $out | Should -Not -Match 'is OPEN'
    }

    It 'an unencrypted volume is reported as NOT encrypted, never as OPEN' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StVaultState { 'mounted' }
        Mock Get-StMountedVaultRoot { 'E:\' }
        Mock Get-StVaultProtection { 'unencrypted' }

        $out = Get-StCombinedOutput { Invoke-StVault -VaultArgs @('status') }
        $out | Should -Match 'NOT encrypted'
        $out | Should -Not -Match 'is OPEN'
    }

    It 'a protected volume is still reported as OPEN' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StVaultState { 'mounted' }
        Mock Get-StMountedVaultRoot { 'E:\' }
        Mock Get-StVaultProtection { 'protected' }

        $out = Get-StCombinedOutput { Invoke-StVault -VaultArgs @('status') }
        $out | Should -Match 'OPEN'
        $out | Should -Match 'E:'
    }

    It 'a create that dies inside Enable-BitLocker detaches and deletes the half-made container' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock New-StBitLockerVault { throw 'The drive is too small to be protected using BitLocker Drive Encryption. (0x8031006F)' }
        Mock Dismount-StVault { }
        Mock Remove-StVaultContainer { }

        { Invoke-StVault -VaultArgs @('create', '200m') 6>$null } | Should -Throw
        Should -Invoke Dismount-StVault -Times 1 -Exactly
        Should -Invoke Remove-StVaultContainer -Times 1 -Exactly
        # A failed create records no backend: a leftover sidecar would make `open` promise BitLocker.
        Should -Invoke Write-StVaultBackend -Times 0 -Exactly
    }

    # An interrupted reset leaves a .old container on disk. It belongs to the user's data and has
    # nothing to do with a plain create, so it must not suppress the cleanup above — otherwise the
    # unencrypted mounted volume survives exactly as it did before that cleanup existed.
    It 'still deletes the half-made container when an unrelated .old is on disk' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock New-StBitLockerVault { throw 'The drive is too small to be protected using BitLocker Drive Encryption. (0x8031006F)' }
        Mock Dismount-StVault { }
        Mock Remove-StVaultContainer { }
        Mock Test-StAsidePresent { $true }   # a leftover from an interrupted reset

        { Invoke-StVault -VaultArgs @('create', '200m') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 1 -Exactly
    }

    It 'a wrong password gives our message and leaves no attached volume behind' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StVaultState { 'unmounted' }
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Invoke-StDiskpart { }
        Mock Dismount-StVault { }
        # Unlock-BitLocker throws on a wrong key (0x80310027) instead of returning false.
        Mock Unlock-StBitLockerVault { throw 'The drive cannot be unlocked with the key provided. (0x80310027)' }

        $out = ''
        try { $out = Get-StCombinedOutput { Invoke-StVault -VaultArgs @('open') } } catch [StExit] { $out = $_.TargetObject }
        Should -Invoke Dismount-StVault -Times 1 -Exactly
    }

    # macOS parity: `hdiutil create` does not attach, so a freshly created vault is closed there.
    # On Windows diskpart leaves the vhdx attached and BitLocker returns it unlocked.
    It 'a successful create leaves the vault CLOSED, not sitting open' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock New-StBitLockerVault { }
        Mock Dismount-StVault { }

        Invoke-StVault -VaultArgs @('create', '200m') 6>&1 3>&1 | Out-Null
        Should -Invoke Dismount-StVault -Times 1 -Exactly
    }

    It 'a size below the BitLocker minimum is refused before diskpart touches the disk' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock New-StBitLockerVault { }

        { Invoke-StVault -VaultArgs @('create', '50m') 6>$null } | Should -Throw
        Should -Invoke New-StBitLockerVault -Times 0 -Exactly
    }
}

Describe 'vault open: Explorer reveal (Windows parity of macOS `open`)' {

    BeforeEach {
        $env:ST_VAULT_PASS = 'testpass123'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StFreeDriveLetter { 'W' }
        Mock Invoke-StDiskpart { }
        Mock Write-StVaultMount { }
        Mock Invoke-StVaultHook { }
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Unlock-StBitLockerVault { $true }
    }

    AfterEach {
        Remove-Item Env:\ST_VAULT_PASS -ErrorAction SilentlyContinue
        Remove-Item Env:\ST_VAULT_NO_REVEAL -ErrorAction SilentlyContinue
    }

    It 'open reveals the mounted volume in Explorer after a verified unlock' {
        Mock Show-StVaultInExplorer { }
        Invoke-StVault -VaultArgs @('open') 6>&1 | Out-Null
        Should -Invoke Show-StVaultInExplorer -Times 1 -Exactly -ParameterFilter { $Mount -eq 'W:\' }
    }

    It 'failed BitLocker unlock never reveals (volume not really mounted)' {
        Mock Unlock-StBitLockerVault { $false }
        Mock Show-StVaultInExplorer { }
        { Invoke-StVault -VaultArgs @('open') 6>$null } | Should -Throw
        Should -Invoke Show-StVaultInExplorer -Times 0 -Exactly
    }

    It 'Show-StVaultInExplorer launches explorer.exe with the mount' {
        Mock Start-Process { }
        Show-StVaultInExplorer -Mount 'W:\'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'explorer.exe' -and $ArgumentList -eq 'W:\'
        }
    }

    It 'ST_VAULT_NO_REVEAL=1 opts out — Explorer is never launched' {
        $env:ST_VAULT_NO_REVEAL = '1'
        Mock Start-Process { }
        Show-StVaultInExplorer -Mount 'W:\'
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'reveal failure is best-effort — warns, does not throw (volume stays mounted)' {
        Mock Start-Process { throw 'no shell' }
        { Show-StVaultInExplorer -Mount 'W:\' 6>$null } | Should -Not -Throw
    }
}

Describe 'Invoke-StVaultHook (real)' {

    It 'is a no-op (no throw) when the hook file is absent' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*post-open.cmd' }
        { Invoke-StVaultHook -Event 'post-open' -Mount 'W:\' } | Should -Not -Throw
    }

    It 'honors ST_HOOK_DIR override for hook resolution' {
        $env:ST_HOOK_DIR = '/tmp/st_hooks_nonexistent'
        try {
            { Invoke-StVaultHook -Event 'post-open' -Mount 'W:\' } | Should -Not -Throw
        } finally {
            Remove-Item Env:\ST_HOOK_DIR -ErrorAction SilentlyContinue
        }
    }
}

Describe 'backend metadata routing (#10)' {

    It 'close on a veracrypt backend does not call diskpart dismount (StExit, GUI-only)' {
        $script:ST_LOCALE = 'en'
        Mock Read-StVaultBackend { 'veracrypt' }
        Mock Dismount-StVault { }

        { Invoke-StVault -VaultArgs @('close') 6>$null } | Should -Throw
        Should -Invoke Dismount-StVault -Times 0 -Exactly
    }

    It 'close on a bitlocker backend calls dismount' {
        $script:ST_LOCALE = 'en'
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Dismount-StVault { }

        Invoke-StVault -VaultArgs @('close') 6>&1 | Out-Null
        Should -Invoke Dismount-StVault -Times 1 -Exactly
    }
}

Describe 'vault destroy' {

    # The structural container check passes by default; the negative case mocks $false.
    BeforeEach { Mock Test-StVaultContainer { $true } }

    It 'refuses to destroy a path that is not our container (before confirm)' {
        $env:ST_ASSUME_YES = '1'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $false }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Test-StVaultContainer { $false }
        Mock Remove-StVaultContainer { }
        { Invoke-StVault -VaultArgs @('destroy') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
    }

    It 'honors ST_ASSUME_YES and calls remove-container mock (bitlocker backend)' {
        $env:ST_ASSUME_YES = '1'
        $script:ST_LOCALE = 'en'
        # Pester 6: a call outside the ParameterFilters (e.g. *.vhdx.mount) no longer falls
        # through to the real Test-Path — an explicit default mock is needed.
        Mock Test-Path { $false }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx.backend' }
        Mock Read-StVaultBackend { 'bitlocker' }
        # tri-state: mounted → dismount; the postcondition sees it unmounted.
        $script:vaultStates = [System.Collections.Queue]::new()
        $script:vaultStates.Enqueue('mounted'); $script:vaultStates.Enqueue('unmounted')
        Mock Get-StVaultState { if ($script:vaultStates.Count -gt 0) { $script:vaultStates.Dequeue() } else { 'unmounted' } }
        Mock Dismount-StVault { }
        Mock Remove-StVaultContainer { }

        Invoke-StVault -VaultArgs @('destroy') 6>&1 | Out-Null
        Should -Invoke Remove-StVaultContainer -Times 1 -Exactly
        Should -Invoke Dismount-StVault -Times 1 -Exactly
    }

    It 'fail-closed: refuses to delete when vault state is unknown (bitlocker)' {
        $env:ST_ASSUME_YES = '1'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx.backend' }
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Get-StVaultState { 'unknown' }
        Mock Dismount-StVault { }
        Mock Remove-StVaultContainer { }

        { Invoke-StVault -VaultArgs @('destroy') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
        Should -Invoke Dismount-StVault -Times 0 -Exactly
    }

    It 'fail-closed: refuses to delete when still mounted after dismount (bitlocker)' {
        $env:ST_ASSUME_YES = '1'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx.backend' }
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Get-StVaultState { 'mounted' }   # both before and after dismount — refuse
        Mock Dismount-StVault { }
        Mock Remove-StVaultContainer { }

        { Invoke-StVault -VaultArgs @('destroy') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
    }

    It 'destroy on veracrypt backend removes the file but does not diskpart-dismount' {
        $env:ST_ASSUME_YES = '1'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $false }   # Pester 6: default mock for calls outside the filters
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx.backend' }
        Mock Read-StVaultBackend { 'veracrypt' }
        Mock Dismount-StVault { }
        Mock Remove-StVaultContainer { }

        Invoke-StVault -VaultArgs @('destroy') 6>&1 | Out-Null
        Should -Invoke Remove-StVaultContainer -Times 1 -Exactly
        Should -Invoke Dismount-StVault -Times 0 -Exactly
    }

    It 'destroy prints honest (non-absolute) recovery wording' {
        $env:ST_ASSUME_YES = '1'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $false }   # Pester 6: default mock for calls outside the filters
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx.backend' }
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Get-StVaultState { 'unmounted' }
        Mock Dismount-StVault { }
        Mock Remove-StVaultContainer { }

        $out = (Invoke-StVault -VaultArgs @('destroy') 6>&1) -join "`n"
        $out | Should -Match 'crypto-shred'
        $out | Should -Match 'depends on password strength'
        $out | Should -Not -Match 'unrecoverable without the key'
    }
}

Describe 'vault reset (destroy + recreate, crypto-shred guarantee)' {

    BeforeEach {
        $env:ST_ASSUME_YES = '1'
        $env:ST_VAULT_PASS = 'testpass123'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $true }  -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx.backend' }
        Mock Test-StVaultContainer { $true }
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Dismount-StVault { }
        Mock Remove-StVaultContainer { }
        Mock Remove-StVaultMount { }
        # the create side (recreate)
        Mock Get-StBitLockerCapable { $true }
        Mock Get-StVeraCryptPath { $null }
        Mock Get-StFreeDriveLetter { 'W' }
        Mock Set-StPrivateAcl { }
        Mock Write-StVaultBackend { }
        Mock New-StBitLockerVault { }
        # create-then-swap: the old container moves to .old and is shredded only after success
        Mock Move-StVaultAside { }
        Mock Restore-StVaultAside { }
        Mock Test-StAsidePresent { $false }   # by default no set-aside container exists
    }

    AfterEach {
        Remove-Item Env:\ST_ASSUME_YES -ErrorAction SilentlyContinue
        Remove-Item Env:\ST_VAULT_PASS -ErrorAction SilentlyContinue
    }

    It 'crypto-shreds the old container then recreates a fresh one (unmounted)' {
        Mock Get-StVaultState { 'unmounted' }
        Invoke-StVault -VaultArgs @('reset') 6>&1 | Out-Null
        Should -Invoke Remove-StVaultContainer -Times 1 -Exactly
        Should -Invoke New-StBitLockerVault -Times 1 -Exactly
    }

    It 'detaches first when mounted, then recreates' {
        $script:vaultStates = [System.Collections.Queue]::new()
        $script:vaultStates.Enqueue('mounted'); $script:vaultStates.Enqueue('unmounted')
        Mock Get-StVaultState { if ($script:vaultStates.Count -gt 0) { $script:vaultStates.Dequeue() } else { 'unmounted' } }
        Invoke-StVault -VaultArgs @('reset') 6>&1 | Out-Null
        # Twice, and both are wanted: the old container is detached before it is shredded, and
        # the freshly created one is detached so reset ends with a CLOSED vault, like macOS.
        Should -Invoke Dismount-StVault -Times 2 -Exactly
        Should -Invoke Remove-StVaultContainer -Times 1 -Exactly
        Should -Invoke New-StBitLockerVault -Times 1 -Exactly
    }

    It 'fail-closed: state unknown -> neither destroys NOR recreates' {
        Mock Get-StVaultState { 'unknown' }
        { Invoke-StVault -VaultArgs @('reset') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
        Should -Invoke New-StBitLockerVault -Times 0 -Exactly
    }

    It 'refuses when no container exists (recreates nothing)' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Get-StVaultState { 'unmounted' }
        { Invoke-StVault -VaultArgs @('reset') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
        Should -Invoke New-StBitLockerVault -Times 0 -Exactly
    }

    It 'passes a custom size to the recreate step' {
        Mock Get-StVaultState { 'unmounted' }
        Invoke-StVault -VaultArgs @('reset', '2048') 6>&1 | Out-Null
        Should -Invoke New-StBitLockerVault -Times 1 -Exactly -ParameterFilter { $Size -eq '2048' }
    }

    It 'prints honest, non-absolute recovery wording' {
        Mock Get-StVaultState { 'unmounted' }
        $out = (Invoke-StVault -VaultArgs @('reset') 6>&1) -join "`n"
        $out | Should -Match 'crypto-shred'
        $out | Should -Match 'fresh empty vault'
    }

    # AUDIT_2026-08-03 P0-1: опечатка в размере не должна успеть уничтожить сейф —
    # валидация идёт ДО destroy (зеркало bash AUDIT_2026-07-03 P2-2).
    It 'invalid size fails BEFORE destroy: old vault survives a typo' {
        Mock Get-StVaultState { 'unmounted' }
        { Invoke-StVault -VaultArgs @('reset', '10gb') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
        Should -Invoke New-StBitLockerVault -Times 0 -Exactly
    }

    It 'size 0 fails BEFORE destroy (recreate would die in diskpart)' {
        Mock Get-StVaultState { 'unmounted' }
        { Invoke-StVault -VaultArgs @('reset', '0') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
        Should -Invoke New-StBitLockerVault -Times 0 -Exactly
    }

    It 'refuses to reset a path that is not our container (no destroy)' {
        Mock Get-StVaultState { 'unmounted' }
        Mock Test-StVaultContainer { $false }
        { Invoke-StVault -VaultArgs @('reset') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
        Should -Invoke New-StBitLockerVault -Times 0 -Exactly
    }

    # Окно потери данных: падение create после destroy оставляло пользователя без сейфа.
    # Теперь старый контейнер отставлен в .old и возвращается на место при любом провале.
    It 'restores the old container when the recreate step fails' {
        Mock Get-StVaultState { 'unmounted' }
        Mock New-StBitLockerVault { throw 'diskpart exploded' }
        { Invoke-StVault -VaultArgs @('reset') 6>$null } | Should -Throw
        Should -Invoke Move-StVaultAside -Times 1 -Exactly
        Should -Invoke Restore-StVaultAside -Times 1 -Exactly
        # старый сейф НЕ уничтожен: crypto-shred идёт только после успешного create
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
    }

    # Отмена внутри create (Stop-StCommand → StExit) — не исключение общего вида,
    # и раньше её проглотил бы catch. finally обязан откатить и здесь.
    It 'rolls back when the recreate step aborts via Stop-StCommand' {
        Mock Get-StVaultState { 'unmounted' }
        Mock Get-StBitLockerCapable { $false }
        Mock Get-StVeraCryptPath { $null }          # → vault_unavailable → Stop-StCommand
        { Invoke-StVault -VaultArgs @('reset') 6>$null } | Should -Throw
        Should -Invoke Restore-StVaultAside -Times 1 -Exactly
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
    }

    It 'refuses when a .old container is already there (keeps it, creates nothing)' {
        Mock Get-StVaultState { 'unmounted' }
        Mock Test-StAsidePresent { $true }
        { Invoke-StVault -VaultArgs @('reset') 6>$null } | Should -Throw
        Should -Invoke Move-StVaultAside -Times 0 -Exactly
        Should -Invoke New-StBitLockerVault -Times 0 -Exactly
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
    }

    # Предупреждение печатается до switch, поэтому ловим сам факт вызова: у ps1-порта
    # ещё нет `vault status` (разрыв паритета P2-8), и любой другой сабкоманде
    # понадобились бы свои моки.
    It 'warns about a leftover .old so the user knows where the data is' {
        Mock Get-StVaultState { 'unmounted' }
        Mock Test-StAsidePresent { $true }
        Mock Write-StWarn { }
        { Invoke-StVault -VaultArgs @('reset') 6>$null } | Should -Throw
        Should -Invoke Write-StWarn -Times 1 -Exactly -ParameterFilter { $Msg -like '*.old.vhdx*' }
    }

    It 'sets the old container aside BEFORE creating the new one' {
        Mock Get-StVaultState { 'unmounted' }
        Invoke-StVault -VaultArgs @('reset') 6>&1 | Out-Null
        Should -Invoke Move-StVaultAside -Times 1 -Exactly
        Should -Invoke Restore-StVaultAside -Times 0 -Exactly
    }

    It 'crypto-shreds the aside copy, not the live path, on success' {
        Mock Get-StVaultState { 'unmounted' }
        Invoke-StVault -VaultArgs @('reset') 6>&1 | Out-Null
        Should -Invoke Remove-StVaultContainer -Times 1 -Exactly -ParameterFilter { $Path -like '*.old.vhdx' }
    }

    It 'fail-closed: unmounted state is asserted before the container is moved aside' {
        Mock Get-StVaultState { 'unknown' }
        { Invoke-StVault -VaultArgs @('reset') 6>$null } | Should -Throw
        Should -Invoke Move-StVaultAside -Times 0 -Exactly
        Should -Invoke New-StBitLockerVault -Times 0 -Exactly
    }
}

# Прямые тесты структурной проверки контейнера (реальная FS, без моков).
Describe 'Test-StVaultContainer (structure check, AUDIT_2026-08-03 P0-1)' {
    BeforeEach {
        $script:Dir = Join-Path ([System.IO.Path]::GetTempPath()) ("st_vc_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'accepts a file with the VHDX magic' {
        $f = Join-Path $script:Dir 'v.vhdx'
        [System.IO.File]::WriteAllBytes($f, [System.Text.Encoding]::ASCII.GetBytes('vhdxfile-rest-of-header'))
        Test-StVaultContainer -Path $f | Should -BeTrue
    }

    It 'rejects an arbitrary file without the magic' {
        $f = Join-Path $script:Dir 'random.vhdx'
        Set-Content -LiteralPath $f -Value 'not a vault at all'
        Test-StVaultContainer -Path $f | Should -BeFalse
    }

    It 'rejects a directory' {
        Test-StVaultContainer -Path $script:Dir | Should -BeFalse
    }

    It 'rejects a truncated (<8 bytes) file' {
        $f = Join-Path $script:Dir 'tiny.vhdx'
        [System.IO.File]::WriteAllBytes($f, [System.Text.Encoding]::ASCII.GetBytes('vhdx'))
        Test-StVaultContainer -Path $f | Should -BeFalse
    }

    It 'accepts a veracrypt-backend file regardless of content (random bytes by design)' {
        $f = Join-Path $script:Dir 'vc.hc'
        Set-Content -LiteralPath $f -Value 'opaque-random-bytes'
        Set-Content -LiteralPath "$f.backend" -Value 'veracrypt' -NoNewline
        Test-StVaultContainer -Path $f | Should -BeTrue
    }

    It 'rejects a missing path' {
        Test-StVaultContainer -Path (Join-Path $script:Dir 'nope.vhdx') | Should -BeFalse
    }
}

Describe 'honest wording (#1, #11, #12)' {

    BeforeEach { $script:ST_LOCALE = 'en' }

    It 'hdd_note says best-effort and not a guarantee' {
        $note = T 'hdd_note'
        $note | Should -Match 'best-effort'
        $note | Should -Match 'NOT a guarantee'
    }

    It 'vault_preventive warns about mounted leak vectors' {
        $msg = T 'vault_preventive'
        $msg | Should -Match 'Windows Search'
        $msg | Should -Match 'pagefile'
        $msg | Should -Match 'VSS'
    }
}

Describe 'shred: LiteralPath + best-effort wipe (#1a, #7)' {

    # -Skip под Windows PowerShell 5.1 — расхождение платформ, не дыра в покрытии.
    # Тест берёт имя со звёздочкой, чтобы доказать: перечисляем через -LiteralPath и не
    # ловим лишнего. Но [System.IO.Path]::GetFullPath на .NET Framework (5.1) БРОСАЕТ на
    # `*`/`?`, а на .NET Core (7) — нет. Test-StProtectedPath ловит исключение и честно
    # закрывается (`return $true`), поэтому под 5.1 shred отказывает раньше Remove-Item.
    # Отказ безопасный, и в реальности недостижимый: NTFS запрещает `*` в имени файла.
    It 'shred enumerates with LiteralPath and calls cipher wipe' -Skip:($PSVersionTable.PSVersion.Major -lt 6) {
        $env:ST_ASSUME_YES = '1'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'C:\secret*.txt' }
        # Get-Item замокан: иначе Remove-StItemSafe видит $item=null (файла нет на раннере)
        # и выходит до Remove-Item. Отдаём обычный не-контейнерный, не-reparse элемент.
        Mock Get-Item { [pscustomobject]@{ Attributes = [System.IO.FileAttributes]::Normal; PSIsContainer = $false } } -ParameterFilter { $LiteralPath -eq 'C:\secret*.txt' }
        Mock Remove-Item { }
        Mock Invoke-StCipherWipe { }
        Mock Write-StHonestDiskNote { }

        Invoke-StShred -Paths @('C:\secret*.txt') 6>&1 | Out-Null
        # Имя с * не должно over-match: удаляем именно через LiteralPath.
        Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq 'C:\secret*.txt' }
        Should -Invoke Invoke-StCipherWipe -Times 1 -Exactly
    }
}

Describe 'shred: protected-path guard (#1)' {

    BeforeEach {
        $script:_oldDrive = $env:SystemDrive; $script:_oldRoot = $env:SystemRoot; $script:_oldProf = $env:USERPROFILE
        $env:SystemDrive = 'C:'; $env:SystemRoot = 'C:\Windows'; $env:USERPROFILE = 'C:\Users\me'
    }
    AfterEach {
        $env:SystemDrive = $script:_oldDrive; $env:SystemRoot = $script:_oldRoot; $env:USERPROFILE = $script:_oldProf
    }

    It 'flags drive roots and system trees as protected' {
        foreach ($p in @('C:\', 'D:\', 'C:\Windows', 'C:\Windows\System32',
                         'C:\Program Files', 'C:\Program Files (x86)\foo', 'C:\ProgramData',
                         'C:\Users', 'C:\Users\me', 'C:\Users\me\..\..\Windows')) {
            Test-StProtectedPath $p | Should -BeTrue -Because "$p must be protected"
        }
    }

    It 'allows files under a user profile and other normal paths' {
        foreach ($p in @('C:\Users\me\secret.txt', 'C:\Users\me\sub\f', 'C:\Users\other\f', 'C:\temp\x')) {
            Test-StProtectedPath $p | Should -BeFalse -Because "$p must be allowed"
        }
    }

    It 'shred refuses a protected path and deletes nothing' {
        $env:ST_ASSUME_YES = '1'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $true }
        Mock Remove-Item { }
        Mock Invoke-StCipherWipe { }
        Mock Write-StHonestDiskNote { }

        { Invoke-StShred -Paths @('C:\Windows') 6>$null } | Should -Throw
        Should -Invoke Remove-Item -Times 0 -Exactly
    }
}

Describe 'shred: reparse-point guard (junction/symlink)' {

    BeforeEach { $env:ST_ASSUME_YES = '1'; $script:ST_LOCALE = 'en' }

    It 'shred refuses when path is a junction/symlink (ReparsePoint attribute)' {
        Mock Test-Path { $true }
        Mock Test-StProtectedPath { $false }
        Mock Get-Item {
            $fake = [PSCustomObject]@{ Attributes = [System.IO.FileAttributes]::Directory -bor [System.IO.FileAttributes]::ReparsePoint }
            return $fake
        }
        Mock Remove-StItemSafe { }
        Mock Invoke-StCipherWipe { }
        Mock Write-StHonestDiskNote { }

        { Invoke-StShred -Paths @('C:\JunctionToTarget') 6>$null } | Should -Throw
        Should -Invoke Remove-StItemSafe -Times 0 -Exactly
    }

    It 'shred uses Remove-StItemSafe (not Remove-Item -Recurse) for normal paths' {
        Mock Test-Path { $true }
        Mock Test-StProtectedPath { $false }
        Mock Get-Item {
            $fake = [PSCustomObject]@{ Attributes = [System.IO.FileAttributes]::Directory }
            return $fake
        }
        Mock Remove-StItemSafe { }
        Mock Invoke-StCipherWipe { }
        Mock Write-StHonestDiskNote { }

        Invoke-StShred -Paths @('C:\Users\me\secret') 6>&1 | Out-Null
        Should -Invoke Remove-StItemSafe -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Users\me\secret' }
    }
}

Describe '--yes flag (#14)' {

    It 'sets the assume-yes flag and strips it from args' {
        # Подменяем команду, чтобы зафиксировать состояние флага во время выполнения.
        Mock Invoke-StVersion { $script:CapturedYes = $script:ST_ASSUME_YES_FLAG }
        Remove-Item Env:\ST_ASSUME_YES -ErrorAction SilentlyContinue
        $script:CapturedYes = $false

        # exit внутри Invoke-Main ловится только для StExit; version не кидает StExit,
        # значит дойдём до конца без выхода процесса (Pester-safe).
        Invoke-Main -Argv @('--yes','version') 6>&1 | Out-Null
        $script:CapturedYes | Should -BeTrue
    }
}

Describe 'setup' {

    It 'creates the trash dir, sets private ACL, is idempotent' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("st_test_" + [Guid]::NewGuid().ToString('N'))
        $oldProfile = $env:USERPROFILE
        $env:USERPROFILE = $tmp
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            Mock Get-StBitLockerOn { $true }
            Mock Set-StPrivateAcl { }
            $script:ST_LOCALE = 'en'

            Invoke-StSetup 6>&1 | Out-Null
            $trash = Join-Path $tmp 'SecureTrash'
            Test-Path $trash | Should -BeTrue
            Should -Invoke Set-StPrivateAcl -Times 1 -Exactly

            # второй вызов не падает (идемпотентность)
            { Invoke-StSetup 6>&1 | Out-Null } | Should -Not -Throw
            Test-Path $trash | Should -BeTrue
        } finally {
            $env:USERPROFILE = $oldProfile
            Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- P2-5: vault open идемпотентен (уже смонтирован → не attach повторно) ---
# Bash имеет 'already open → exit 0'; Windows раньше всегда звал diskpart attach → двойной
# attach + новая буква (AUDIT_2026-07-03 P2-5).
Describe 'vault open idempotency (P2-5)' {
    BeforeEach {
        $env:ST_VAULT_PASS = 'testpass123'
        $script:ST_LOCALE = 'en'
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*SecureVault.vhdx' }
        Mock Read-StVaultBackend { 'bitlocker' }
        Mock Invoke-StDiskpart { }
        Mock Unlock-StBitLockerVault { $true }
        Mock Get-StFreeDriveLetter { 'W' }
        Mock Write-StVaultMount { }
        Mock Invoke-StVaultHook { }
        Mock Show-StVaultInExplorer { }
    }
    AfterEach { Remove-Item Env:\ST_VAULT_PASS -ErrorAction SilentlyContinue }

    It 'open on an already-mounted vault does not attach again' {
        Mock Get-StVaultState { 'mounted' }
        Invoke-StVault -VaultArgs @('open') 6>&1 | Out-Null
        Should -Invoke Invoke-StDiskpart -Times 0 -Exactly
    }

    # AUDIT_2026-08-03 P0-3 (Codex): legacy-vault, смонтированный до появления sidecar'а,
    # оставлял ghostdraft/paranoid без реальной буквы — already-mounted ветка освежает sidecar.
    It 'open on an already-mounted vault refreshes the mount sidecar' {
        Mock Get-StVaultState { 'mounted' }
        Mock Get-StMountedVaultRoot { 'D:\' }
        Invoke-StVault -VaultArgs @('open') 6>&1 | Out-Null
        Should -Invoke Write-StVaultMount -Times 1 -Exactly -ParameterFilter { $Mount -eq 'D:\' }
    }

    It 'sidecar refresh is skipped when the current letter cannot be resolved' {
        Mock Get-StVaultState { 'mounted' }
        Mock Get-StMountedVaultRoot { $null }
        Invoke-StVault -VaultArgs @('open') 6>&1 | Out-Null
        Should -Invoke Write-StVaultMount -Times 0 -Exactly
    }

    It 'open on an unmounted vault proceeds to attach' {
        Mock Get-StVaultState { 'unmounted' }
        Invoke-StVault -VaultArgs @('open') 6>&1 | Out-Null
        Should -Invoke Invoke-StDiskpart -Times 1 -Exactly
    }
}

# Настоящие файловые операции, без Mock: моки скрывают именно те ошибки, ради
# которых эти функции существуют (Move-Item -Force в существующий КАТАЛОГ кладёт
# контейнер внутрь него и молчит).
Describe 'vault reset: aside/restore on a real filesystem' {

    BeforeEach {
        $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("st-aside-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tmp | Out-Null
        $script:vault = Join-Path $script:tmp 'SecureVault.vhdx'
        Set-Content -LiteralPath $script:vault -Value 'REAL-VAULT-BYTES' -NoNewline
    }

    AfterEach {
        Remove-Item -LiteralPath $script:tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'moves the container aside and leaves the live path empty' {
        Move-StVaultAside -VaultPath $script:vault
        Test-Path -LiteralPath $script:vault | Should -BeFalse
        (Get-Content -LiteralPath (Get-StAsidePath $script:vault) -Raw) | Should -Be 'REAL-VAULT-BYTES'
    }

    It 'refuses instead of nesting the vault inside an existing .old directory' {
        New-Item -ItemType Directory -Path (Get-StAsidePath $script:vault) | Out-Null
        { Move-StVaultAside -VaultPath $script:vault 6>$null } | Should -Throw
        # контейнер остался на месте и НЕ уехал внутрь каталога .old
        Test-Path -LiteralPath $script:vault | Should -BeTrue
        Test-Path -LiteralPath (Join-Path (Get-StAsidePath $script:vault) 'SecureVault.vhdx') | Should -BeFalse
    }

    It 'restores the container byte-for-byte, clearing a partially created new one' {
        Move-StVaultAside -VaultPath $script:vault
        Set-Content -LiteralPath $script:vault -Value 'HALF-BAKED' -NoNewline   # недоделанный новый
        Restore-StVaultAside -VaultPath $script:vault
        (Get-Content -LiteralPath $script:vault -Raw) | Should -Be 'REAL-VAULT-BYTES'
        Test-Path -LiteralPath (Get-StAsidePath $script:vault) | Should -BeFalse
    }

    It 'restore is a no-op when there is nothing set aside' {
        { Restore-StVaultAside -VaultPath $script:vault } | Should -Not -Throw
        (Get-Content -LiteralPath $script:vault -Raw) | Should -Be 'REAL-VAULT-BYTES'
    }
}

# Теневые копии VSS — Windows-аналог локальных снимков APFS: главный канал, по
# которому «стёртый» файл выживает. Инструмент обязан говорить о них сам.
Describe 'shadow copies (snapshot honesty)' {

    BeforeEach {
        $script:ST_LOCALE = 'en'
        Mock Get-StBitLockerState { 'on' }
        Mock Get-StBitLockerCapable { $true }
        Mock Get-StVeraCryptPath { $null }
        Mock Get-StDiskKind { 'ssd' }
        Mock Test-StElevated { $true }
    }

    It 'check reports shadow copies when they exist' {
        Mock Get-StSnapshotCount { 3 }
        $out = Get-StCombinedOutput { Invoke-StCheck }
        $out | Should -Match 'Volume Shadow Copies: 3'
        $out | Should -Match 'FULL copy'
    }

    It 'check says none when there are no shadow copies' {
        Mock Get-StSnapshotCount { 0 }
        $out = Get-StCombinedOutput { Invoke-StCheck }
        $out | Should -Match 'none right now'
    }

    It 'check stays honest when shadow copies cannot be read' {
        Mock Get-StSnapshotCount { 'unknown' }
        $out = Get-StCombinedOutput { Invoke-StCheck }
        $out | Should -Match 'Volume Shadow Copies: unknown'
    }

    # Без прав администратора VSS отдаёт пустой список, а не ошибку: посчитать это
    # за «копий нет» — соврать в самую опасную сторону.
    It 'reports unknown rather than zero when not elevated' {
        # Get-CimInstance нет на macOS-раннере, поэтому мокать его нельзя; проверяем,
        # что до него дело вообще не доходит — возвращается 'unknown'.
        Mock Test-StElevated { $false }
        Get-StSnapshotCount | Should -Be 'unknown'
    }

    It 'the post-shred note warns about shadow copies too' {
        Mock Get-StSnapshotCount { 2 }
        Mock Get-StBitLockerOn { $true }
        $out = Get-StCombinedOutput { Write-StHonestDiskNote }
        $out | Should -Match 'Volume Shadow Copies: 2'
    }
}

# destroy-old: убрать контейнер, отставленный прерванным reset. Отдельная цель,
# отдельное подтверждение — путать её с активным сейфом нельзя.
Describe 'vault destroy-old' {

    BeforeEach {
        $env:ST_ASSUME_YES = '1'
        $script:ST_LOCALE = 'en'
        Mock Test-StAsidePresent { $true }
        Mock Test-StVaultContainer { $true }
        Mock Get-StVaultState { 'unmounted' }
        Mock Remove-StVaultContainer { }
        Mock Read-StVaultBackend { 'bitlocker' }
    }

    AfterEach { Remove-Item Env:\ST_ASSUME_YES -ErrorAction SilentlyContinue }

    It 'crypto-shreds the set-aside container, not the live one' {
        Invoke-StVault -VaultArgs @('destroy-old') 6>&1 | Out-Null
        Should -Invoke Remove-StVaultContainer -Times 1 -Exactly -ParameterFilter { $Path -like '*.old.vhdx' }
    }

    It 'refuses when nothing is set aside' {
        Mock Test-StAsidePresent { $false }
        { Invoke-StVault -VaultArgs @('destroy-old') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
    }

    It 'refuses a path that is not our container' {
        Mock Test-StVaultContainer { $false }
        { Invoke-StVault -VaultArgs @('destroy-old') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
    }

    It 'fail-closed: refuses while the set-aside container looks mounted' {
        Mock Get-StVaultState { 'mounted' }
        { Invoke-StVault -VaultArgs @('destroy-old') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
    }

    It 're-checks the mounted state after the confirmation prompt' {
        # Между проверкой и удалением стоит интерактивный confirm — за это время
        # контейнер можно смонтировать; вторая проверка обязана это поймать.
        $script:oldStates = [System.Collections.Queue]::new()
        $script:oldStates.Enqueue('unmounted')   # до confirm
        $script:oldStates.Enqueue('mounted')     # после confirm
        Mock Get-StVaultState { if ($script:oldStates.Count -gt 0) { $script:oldStates.Dequeue() } else { 'mounted' } }
        { Invoke-StVault -VaultArgs @('destroy-old') 6>$null } | Should -Throw
        Should -Invoke Remove-StVaultContainer -Times 0 -Exactly
    }

    It 'puts .old before the extension so Get-DiskImage can still read it' {
        Get-StAsidePath 'C:\Users\x\SecureVault.vhdx' | Should -Be 'C:\Users\x\SecureVault.old.vhdx'
        Get-StAsidePath 'C:\Users\x\novault'          | Should -Be 'C:\Users\x\novault.old'
    }

    It 'the leftover notice names the command that removes it' {
        Mock Write-StWarn { }
        Invoke-StVault -VaultArgs @('destroy-old') 6>&1 | Out-Null
        Should -Invoke Write-StWarn -Times 1 -Exactly -ParameterFilter { $Msg -like '*destroy-old*' }
    }
}
