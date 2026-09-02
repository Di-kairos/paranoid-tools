# Pester 5 — install.ps1 (Windows port of panic). We verify the integrity and signature gates
# without the network: PANIC_BASE_URL points at a local "release" directory, installation goes
# into a temp directory, PATH editing is disabled. Integrity coverage: happy path, failure on
# hash mismatch, failure when the SHA256SUMS entry is missing (fail-closed). Signature coverage:
# valid/broken signature, missing .sig, missing ssh-keygen — via a mock ssh-keygen shim in PATH.
#
# Integrity tests run with PT_ALLOW_HASH_ONLY='1' (fixture has no .sig): the goal is the hash gate
# only; the signature gate itself is covered by a separate Describe.

BeforeAll {
    $script:InstallScript = Join-Path $PSScriptRoot '..\install.ps1'
}

Describe 'install.ps1 integrity gate' {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_inst_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Target  = Join-Path $script:Work 'target'
        New-Item -ItemType Directory -Path $script:Release -Force | Out-Null

        # The payload "script" + a correct SHA256SUMS.
        $payload = "Write-Output 'payload-ok'`n"
        $script:ScriptFile = Join-Path $script:Release 'panic.ps1'
        Set-Content -LiteralPath $script:ScriptFile -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $script:ScriptFile -Algorithm SHA256).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  panic.ps1"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs the script when the checksum matches' {
        # Run the installer in a child pwsh: env settings are set inside -Command
        # so they don't leak into the test session.
        & pwsh -NoProfile -Command "`$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; `$env:PT_ALLOW_HASH_ONLY='1'; & '$($script:InstallScript)'" *> $null
        (Test-Path (Join-Path $script:Target 'lib\panic.ps1')) | Should -BeTrue
        (Test-Path (Join-Path $script:Target 'panic.cmd')) | Should -BeTrue
    }

    It 'fails closed when the checksum does not match' {
        # Corrupt SHA256SUMS — the hash won't match.
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value ("0"*64 + "  panic.ps1")
        & pwsh -NoProfile -Command "`$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; `$env:PT_ALLOW_HASH_ONLY='1'; & '$($script:InstallScript)'" *> $null
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'lib\panic.ps1')) | Should -BeFalse
    }

    It 'fails closed when SHA256SUMS lacks the panic.ps1 entry' {
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value ("deadbeef  somethingelse.txt")
        & pwsh -NoProfile -Command "`$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; `$env:PT_ALLOW_HASH_ONLY='1'; & '$($script:InstallScript)'" *> $null
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'lib\panic.ps1')) | Should -BeFalse
    }
}

Describe 'install.ps1 signature gate' {
    It 'can still verify under Windows PowerShell 5.1 (no ArgumentList there)' {
        # `ArgumentList` exists only in .NET Core (PowerShell 7). Windows PowerShell 5.1 is
        # the stock Windows shell and exactly the one people run the README one-liner in;
        # without the fallback path the install would fail at the signature-verification step.
        $src = Get-Content -Raw -LiteralPath $script:InstallScript
        $src | Should -Match "PSObject\.Properties\.Name -contains 'ArgumentList'"
        $src | Should -Match '\$psi\.Arguments ='
    }

    # The hash is always valid (covered above); we vary ONLY the signature. `ssh-keygen` is replaced
    # with a mock shim in PATH: the verify result is set by its exit code (0=valid, 1=broken). No real
    # key/signature needed — we test the fail-closed orchestration, not ssh cryptography itself.
    BeforeAll {
        $script:InstallScript = Join-Path $PSScriptRoot '..\install.ps1'

        # Drops a mock ssh-keygen with a given exit code into $ShimDir; Windows CI — .cmd, otherwise a bash shim.
        # A shim that SAVES the received stdin to a file (path in PT_TEST_STDIN_CAPTURE): we verify
        # not "the verifier was called" but WHAT was sent into it. The shim itself is a pwsh script
        # (identical on all platforms) wrapped in .cmd/sh, because PATH looks for an executable, not a .ps1.
        function New-SshKeygenCaptureShim {
            $capture = Join-Path $script:ShimDir 'capture.ps1'
            Set-Content -LiteralPath $capture -Encoding ascii -Value @'
$fs = [IO.File]::Create($env:PT_TEST_STDIN_CAPTURE)
try { [Console]::OpenStandardInput().CopyTo($fs) } finally { $fs.Close() }
exit 0
'@
            # $env:OS, not $IsWindows: the latter is defined only in PowerShell 6+; under Windows
            # PowerShell 5.1 it is $null — and the test took the Unix branch right on Windows.
            if ($env:OS -eq 'Windows_NT') {
                Set-Content -LiteralPath (Join-Path $script:ShimDir 'ssh-keygen.cmd') -Encoding ASCII `
                    -Value "@echo off`r`npwsh -NoProfile -File `"$capture`"`r`nexit /b %ERRORLEVEL%`r`n"
            } else {
                $shim = Join-Path $script:ShimDir 'ssh-keygen'
                Set-Content -LiteralPath $shim -Value "#!/bin/sh`nexec pwsh -NoProfile -File '$capture'`n" -NoNewline
                & chmod +x $shim
            }
        }

        # Noisy shim: floods stdout/stderr with deliberately more than the pipe buffer and exits 0.
        # If the installer redirected the streams and doesn't drain them, the verifier blocks on write
        # and `WaitForExit` waits for it forever — the install hangs silently.
        function New-SshKeygenNoisyShim {
            $noisy = Join-Path $script:ShimDir 'noisy.ps1'
            Set-Content -LiteralPath $noisy -Encoding ascii -Value @'
$null = [Console]::OpenStandardInput().CopyTo([IO.Stream]::Null)
$chunk = 'x' * 4096
for ($i = 0; $i -lt 64; $i++) { [Console]::Out.WriteLine($chunk); [Console]::Error.WriteLine($chunk) }
exit 0
'@
            if ($env:OS -eq 'Windows_NT') {
                Set-Content -LiteralPath (Join-Path $script:ShimDir 'ssh-keygen.cmd') -Encoding ASCII `
                    -Value "@echo off`r`npwsh -NoProfile -File `"$noisy`"`r`nexit /b %ERRORLEVEL%`r`n"
            } else {
                $shim = Join-Path $script:ShimDir 'ssh-keygen'
                Set-Content -LiteralPath $shim -Value "#!/bin/sh`nexec pwsh -NoProfile -File '$noisy'`n" -NoNewline
                & chmod +x $shim
            }
        }

        function New-SshKeygenShim([int]$ExitCode) {
            if ($env:OS -eq 'Windows_NT') {
                $shim = Join-Path $script:ShimDir 'ssh-keygen.cmd'
                Set-Content -LiteralPath $shim -Value "@echo off`r`nexit /b $ExitCode`r`n" -Encoding ASCII
            } else {
                $shim = Join-Path $script:ShimDir 'ssh-keygen'
                Set-Content -LiteralPath $shim -Value "#!/usr/bin/env bash`nexit $ExitCode`n" -NoNewline
                & chmod +x $shim
            }
        }

        # Creates a .sig placeholder in the release (content irrelevant — verify is mocked by the shim).
        function New-SigFile {
            Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS.sig') -Value 'dummy-signature' -NoNewline
        }

        # Run the installer with $ShimDir prepended to PATH (the mock ssh-keygen is found first).
        function Invoke-Installer([string]$ExtraEnv = '') {
            $withShim = "`$env:PATH='$($script:ShimDir)' + [IO.Path]::PathSeparator + `$env:PATH; "
            & pwsh -NoProfile -Command "$withShim`$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; $ExtraEnv & '$($script:InstallScript)'" *> $null
        }
    }

    BeforeEach {
        $script:Work    = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_sig_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Target  = Join-Path $script:Work 'target'
        $script:ShimDir = Join-Path $script:Work 'bin'
        $script:EmptyDir = Join-Path $script:Work 'empty'
        New-Item -ItemType Directory -Path $script:Release  -Force | Out-Null
        New-Item -ItemType Directory -Path $script:ShimDir  -Force | Out-Null
        New-Item -ItemType Directory -Path $script:EmptyDir -Force | Out-Null

        # Correct payload + SHA256SUMS (the hash matches).
        $payload = "Write-Output 'payload-ok'`n"
        $sf = Join-Path $script:Release 'panic.ps1'
        Set-Content -LiteralPath $sf -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $sf -Algorithm SHA256).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  panic.ps1"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs when the signature verifies' {
        New-SshKeygenShim 0
        New-SigFile
        Invoke-Installer
        $LASTEXITCODE | Should -Be 0
        (Test-Path (Join-Path $script:Target 'lib\panic.ps1')) | Should -BeTrue
    }

    It 'does not hang when the verifier is noisy (redirected streams must be drained)' {
        New-SshKeygenNoisyShim
        New-SigFile
        $job = Start-Job -ScriptBlock {
            param($InstallScript, $Release, $Target, $ShimDir, $Sep)
            $env:PATH = $ShimDir + $Sep + $env:PATH
            $env:PANIC_BASE_URL = $Release
            $env:PANIC_INSTALL_DIR = $Target
            $env:PANIC_SKIP_PATH = '1'
            & pwsh -NoProfile -File $InstallScript *> $null
        } -ArgumentList $script:InstallScript, $script:Release, $script:Target, $script:ShimDir, ([IO.Path]::PathSeparator)
        $finished = Wait-Job -Job $job -Timeout 90
        Remove-Job -Job $job -Force
        $finished | Should -Not -BeNullOrEmpty -Because 'установщик обязан завершиться, а не ждать верификатор вечно'
        (Test-Path (Join-Path $script:Target 'lib\panic.ps1')) | Should -BeTrue
    }

    It 'hands the verifier the signed bytes unchanged (CRLF survives, nothing appended)' {
        # A regression that has already happened in this ecosystem: SHA256SUMS went to ssh-keygen
        # through the PowerShell pipeline, which re-encodes text (BOM, CRLF) and appends a newline.
        # The signature is valid, but the verifier sees DIFFERENT bytes → "incorrect signature" →
        # fail-closed kills an install from a GENUINE release. The file here deliberately has CRLF:
        # that is what any generator run on Windows produces.
        $sums = Join-Path $script:Release 'SHA256SUMS'
        $hash = (Get-FileHash -Path (Join-Path $script:Release 'panic.ps1') -Algorithm SHA256).Hash.ToLower()
        [IO.File]::WriteAllBytes($sums, [Text.Encoding]::ASCII.GetBytes("$hash  panic.ps1`r`n"))
        $expected = [IO.File]::ReadAllBytes($sums)

        New-SshKeygenCaptureShim
        New-SigFile
        $capture = Join-Path $script:Work 'stdin.bin'
        Invoke-Installer "`$env:PT_TEST_STDIN_CAPTURE='$capture'; "

        (Test-Path $capture) | Should -BeTrue
        [IO.File]::ReadAllBytes($capture) | Should -Be $expected
    }

    It 'fails closed when the signature is invalid' {
        New-SshKeygenShim 1
        New-SigFile
        Invoke-Installer
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'lib\panic.ps1')) | Should -BeFalse
    }

    It 'fails closed when the signature file is missing' {
        New-SshKeygenShim 0   # verifier present, but no .sig
        Invoke-Installer
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'lib\panic.ps1')) | Should -BeFalse
    }

    It 'installs a missing signature only with PT_ALLOW_HASH_ONLY=1' {
        New-SshKeygenShim 0
        Invoke-Installer "`$env:PT_ALLOW_HASH_ONLY='1'; "
        $LASTEXITCODE | Should -Be 0
        (Test-Path (Join-Path $script:Target 'lib\panic.ps1')) | Should -BeTrue
    }

    It 'fails closed when ssh-keygen is unavailable' {
        # PATH without ssh-keygen (empty directory) → verifier not found → refuse.
        New-SigFile
        & pwsh -NoProfile -Command "`$env:PATH='$($script:EmptyDir)'; `$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; & '$($script:InstallScript)'" *> $null
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'lib\panic.ps1')) | Should -BeFalse
    }

    It 'installs without a verifier only with PT_ALLOW_HASH_ONLY=1' {
        New-SigFile
        & pwsh -NoProfile -Command "`$env:PATH='$($script:EmptyDir)'; `$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; `$env:PT_ALLOW_HASH_ONLY='1'; & '$($script:InstallScript)'" *> $null
        $LASTEXITCODE | Should -Be 0
        (Test-Path (Join-Path $script:Target 'lib\panic.ps1')) | Should -BeTrue
    }
}
