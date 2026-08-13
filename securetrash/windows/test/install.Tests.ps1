# Pester 5 tests for install.ps1: installs securetrash.ps1 only when the SHA256 matches
# AND the ed25519 signature is valid; refuses fail-closed on tampering/missing checksum,
# a missing/invalid signature, or a missing verifier (ssh-keygen).
#
# ssh-keygen is replaced by a fake in a separate PATH directory (a cross-process mock,
# like in bats): the installer runs in a child pwsh, so Pester Mock does not apply.

BeforeAll {
    $script:Installer = Join-Path $PSScriptRoot '..\install.ps1'
    # Absolute path to pwsh — so the installer can be invoked with a trimmed PATH.
    $script:PwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

    # Puts a fake ssh-keygen with the given exit code into directory $Dir.
    # Windows: a file with no extension is not an Application for Get-Command (PATHEXT), so
    # the installer never found the sh fake and the happy path failed closed (red
    # CI since v0.4.11). We drop a .cmd — an honestly executable fake for both verify branches.
    function New-FakeSshKeygen {
        param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][int]$ExitCode)
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        # $env:OS, not $IsWindows: the latter is undefined in Windows PowerShell 5.1.
        if ($env:OS -eq 'Windows_NT') {
            Set-Content -LiteralPath (Join-Path $Dir 'ssh-keygen.cmd') -Value "@exit /b $ExitCode"
        } else {
            $p = Join-Path $Dir 'ssh-keygen'
            Set-Content -LiteralPath $p -Value "#!/bin/sh`nexit $ExitCode`n" -NoNewline
            & chmod +x $p
        }
    }
}

Describe 'install.ps1 integrity + signature' {
    It 'can still verify under Windows PowerShell 5.1 (no ArgumentList there)' {
        # `ArgumentList` exists only in .NET Core (PowerShell 7). Windows PowerShell 5.1 is
        # the stock Windows shell and exactly the one where the README one-liner is run;
        # without the fallback path the install would fail at the signature verification step.
        $src = Get-Content -Raw -LiteralPath $script:Installer
        $src | Should -Match "PSObject\.Properties\.Name -contains 'ArgumentList'"
        $src | Should -Match '\$psi\.Arguments ='
    }

    It 'never pipes the signed data into the verifier (bytes must reach it unchanged)' {
        # The PowerShell pipeline re-encodes text (BOM, CRLF) and appends a newline, so
        # the verifier would see bytes DIFFERENT from what was signed: a valid signature reads as
        # "incorrect signature", and fail-closed kills installs from a genuine release. seedsplit
        # already broke this way. The canon is the raw file stream into stdin via ProcessStartInfo.
        $src = Get-Content -Raw -LiteralPath $script:Installer
        $src | Should -Match 'ProcessStartInfo'
        $src | Should -Not -Match '(?m)Get-Content[^\r\n]*\|\s*&'
    }


    BeforeEach {
        $script:Work    = Join-Path ([System.IO.Path]::GetTempPath()) ("st_inst_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Dest    = Join-Path $script:Work 'install'
        $script:Bin     = Join-Path $script:Work 'bin'   # directory with the fake ssh-keygen
        New-Item -ItemType Directory -Path $script:Release -Force | Out-Null
        New-Item -ItemType Directory -Path $script:Bin -Force | Out-Null

        # Stub payload + a correct SHA256SUMS.
        $payload = "Write-Host 'payload-ok'`n"
        $scriptFile = Join-Path $script:Release 'securetrash.ps1'
        Set-Content -Path $scriptFile -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $scriptFile -Algorithm SHA256).Hash.ToLower()
        Set-Content -Path (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  securetrash.ps1"
        # Stub .sig: the real crypto check is mocked by ssh-keygen.
        Set-Content -Path (Join-Path $script:Release 'SHA256SUMS.sig') -Value "dummy-signature"

        $script:OrigPath = $env:PATH
        $env:ST_BASE_URL    = $script:Release
        $env:ST_INSTALL_DIR = $script:Dest
        $env:ST_SKIP_PATH   = '1'
    }

    AfterEach {
        $env:PATH = $script:OrigPath
        Remove-Item Env:\ST_BASE_URL, Env:\ST_INSTALL_DIR, Env:\ST_SKIP_PATH, Env:\PT_ALLOW_HASH_ONLY -ErrorAction SilentlyContinue
        Remove-Item -Path $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs when checksum matches and signature is valid' {
        New-FakeSshKeygen -Dir $script:Bin -ExitCode 0
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeTrue
    }

    It 'fails closed on checksum mismatch' {
        # Replace the payload AFTER SHA256SUMS is generated — the hash mismatches (never reaches the signature).
        Set-Content -Path (Join-Path $script:Release 'securetrash.ps1') -Value "Write-Host 'TAMPERED'`n" -NoNewline
        New-FakeSshKeygen -Dir $script:Bin -ExitCode 0
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
    }

    It 'fails closed when SHA256SUMS lacks the entry' {
        Set-Content -Path (Join-Path $script:Release 'SHA256SUMS') -Value "deadbeef  something-else"
        New-FakeSshKeygen -Dir $script:Bin -ExitCode 0
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
    }

    It 'fails closed when the signature is INVALID' {
        New-FakeSshKeygen -Dir $script:Bin -ExitCode 1   # ssh-keygen -Y verify != 0
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
    }

    It 'fails closed when the signature is MISSING' {
        Remove-Item -Path (Join-Path $script:Release 'SHA256SUMS.sig') -Force
        New-FakeSshKeygen -Dir $script:Bin -ExitCode 0
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
    }

    It 'fails closed when the verifier (ssh-keygen) is missing' {
        # $script:Bin is empty — ssh-keygen is unavailable on the trimmed PATH.
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
    }

    It 'PT_ALLOW_HASH_ONLY=1 allows install when verifier is missing (loud escape)' {
        $env:PATH = $script:Bin              # ssh-keygen is absent
        $env:PT_ALLOW_HASH_ONLY = '1'
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeTrue
    }
}
