# install.ps1 — seedsplit installer for Windows (BETA) with an integrity check.
#
# Pulls seedsplit.ps1 and SHA256SUMS from a RELEASE tag (not the main branch) and verifies
# the SHA256 BEFORE installing. Closes the "irm|iex from main without verification"
# supply-chain risk: a release tag's contents are immutable (unlike the moving main), the hash
# catches corruption, partial/cache tampering, and desync with the publication. On top of
# integrity the release SIGNATURE is verified (SHA256SUMS.sig, ed25519 via ssh-keygen -Y
# verify) — a mirror of install.sh. FAIL-CLOSED: a bad/missing signature or a missing
# ssh-keygen aborts the install unless PT_ALLOW_HASH_ONLY=1 is explicitly set (then only
# SHA256 integrity remains, with a warning).
#
# Usage (verify-then-run recommended, see windows/README.md):
#   irm https://github.com/Di-kairos/paranoid-tools/releases/download/seedsplit-v0.5.7/install.ps1 -OutFile install.ps1
#   irm https://github.com/Di-kairos/paranoid-tools/releases/download/seedsplit-v0.5.7/SHA256SUMS  -OutFile SHA256SUMS
#   # verify the install.ps1 hash manually, read the script, then:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File install.ps1
#
# Environment variables:
#   SEEDSPLIT_VERSION     — a specific tag (e.g. 0.3.2). Default: latest.
#   SEEDSPLIT_BASE_URL    — the source entirely: an http(s) URL OR a local directory (tests/forks).
#   SEEDSPLIT_INSTALL_DIR — install directory. Default: %LOCALAPPDATA%\Programs\seedsplit.
#   SEEDSPLIT_SKIP_PATH   — '1' skips the PATH edit (for tests).
#   PT_ALLOW_HASH_ONLY    — '1' allows installing without signature verification (integrity
#                           only): for old/unsigned releases or without ssh-keygen. A bad
#                           signature still aborts the install — this flag does NOT bypass it.
#
# WARNING: BETA port. The logic (including KAT cross-compatibility of shares with macOS) is
# verified via Pester; behavior across the wide fleet of Windows consoles/locales is not road-tested.

$ErrorActionPreference = 'Stop'

$Repo = 'Di-kairos/paranoid-tools'
# Default release of this tool; kept in lockstep with the seedsplit-vX.Y.Z tag by a
# release.yml gate. In the monorepo `releases/latest` is the latest release of ANY
# tool, so nothing here uses `latest` — the tag is always pinned.
$SEEDSPLIT_VERSION_DEFAULT = '0.5.7'
# Source: explicit SEEDSPLIT_BASE_URL → SEEDSPLIT_VERSION override → the baked-in default tag.
if ($env:SEEDSPLIT_BASE_URL) {
    $BaseUrl = $env:SEEDSPLIT_BASE_URL
} elseif ($env:SEEDSPLIT_VERSION) {
    $BaseUrl = "https://github.com/$Repo/releases/download/seedsplit-v$($env:SEEDSPLIT_VERSION)"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/download/seedsplit-v$SEEDSPLIT_VERSION_DEFAULT"
}

$InstallDir = if ($env:SEEDSPLIT_INSTALL_DIR) { $env:SEEDSPLIT_INSTALL_DIR } else {
    Join-Path $env:LOCALAPPDATA 'Programs\seedsplit'
}
# The script itself lives in lib\, NOT next to the shim. PowerShell resolves a bare
# `seedsplit` on PATH to a .ps1 BEFORE a .cmd of the same name, and a .ps1 is refused
# outright under the default ExecutionPolicy (Restricted) — so a .ps1 on PATH means
# the command fails in PowerShell no matter what the shim does. With only the shim
# visible, the command works from cmd, Windows PowerShell 5.1 and pwsh 7 alike.
$LibDir     = Join-Path $InstallDir 'lib'
$ScriptPath = Join-Path $LibDir 'seedsplit.ps1'
$ShimPath   = Join-Path $InstallDir 'seedsplit.cmd'

Write-Host 'seedsplit (Windows, BETA) installer'
Write-Host '-----------------------------------'

# Download a file from the release: http(s) → Invoke-RestMethod; local directory → copy.
# The local path is supported so tests can exercise the hash check without the network.
function Get-ReleaseFile {
    param([string]$Name, [string]$OutFile)
    if ($BaseUrl -match '^https?://') {
        Invoke-RestMethod -Uri "$BaseUrl/$Name" -OutFile $OutFile
    } else {
        Copy-Item -Path (Join-Path $BaseUrl $Name) -Destination $OutFile -Force
    }
}

# Temporary directory for the download; cleaned up in any case.
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("seedsplit-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
    $tmpScript = Join-Path $Tmp 'seedsplit.ps1'
    $tmpSums   = Join-Path $Tmp 'SHA256SUMS'

    Write-Host 'Downloading seedsplit.ps1 + SHA256SUMS from release...'
    Get-ReleaseFile -Name 'seedsplit.ps1' -OutFile $tmpScript
    Get-ReleaseFile -Name 'SHA256SUMS'    -OutFile $tmpSums

    # Expected hash for seedsplit.ps1 from SHA256SUMS (format: '<hash>  name').
    $expected = $null
    foreach ($line in Get-Content -Path $tmpSums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $fname = $parts[1].Trim().TrimStart('*')
            if ($fname -eq 'seedsplit.ps1') { $expected = $parts[0].Trim().ToLower() }
        }
    }
    if (-not $expected) {
        Write-Error 'SHA256SUMS has no entry for seedsplit.ps1 — installation aborted.'
        exit 1
    }

    $actual = (Get-FileHash -Path $tmpScript -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        Write-Error "Checksum MISMATCH (possible tampering) — installation aborted.`nexpected: $expected`nactual:   $actual"
        exit 1
    }
    Write-Host 'Checksum OK.'

    # --- Release SIGNATURE verification (authenticity on top of integrity) ---
    # Mirrors install.sh: releases are signed with the ecosystem's dedicated ed25519 key
    # (`ssh-keygen -Y verify` over SHA256SUMS). The embedded pubkey matches install.sh and SECURITY.md.
    # FAIL-CLOSED: a bad signature ALWAYS aborts the install (a clear sign of tampering — no bypass).
    # A missing signature OR a missing ssh-keygen aborts the install unless PT_ALLOW_HASH_ONLY=1
    # is explicitly set — then only SHA256 integrity remains (with a loud warning).
    $ReleaseSigningPubkey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9DVd0vNOwa5hyr9gShaCWoNOVnUsrdHVO/WE0wCZkT'
    $SignPrincipal = 'releases@paranoid-tools'
    $AllowHashOnly = ($env:PT_ALLOW_HASH_ONLY -eq '1')

    $sshKeygen = Get-Command 'ssh-keygen' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sshKeygen) {
        if ($AllowHashOnly) {
            Write-Warning 'ssh-keygen not found — the release signature was NOT verified, SHA256 integrity only (PT_ALLOW_HASH_ONLY=1).'
        } else {
            Write-Error 'ssh-keygen not found — there is nothing to check the release signature with, installation aborted. Install OpenSSH or run with PT_ALLOW_HASH_ONLY=1 (integrity only).'
            exit 1
        }
    } else {
        $tmpSig  = Join-Path $Tmp 'SHA256SUMS.sig'
        $haveSig = $false
        try { Get-ReleaseFile -Name 'SHA256SUMS.sig' -OutFile $tmpSig; $haveSig = Test-Path -LiteralPath $tmpSig } catch { $haveSig = $false }
        if (-not $haveSig) {
            if ($AllowHashOnly) {
                Write-Warning 'The release signature (SHA256SUMS.sig) is unavailable — continuing on integrity alone (PT_ALLOW_HASH_ONLY=1).'
            } else {
                Write-Error 'The release signature (SHA256SUMS.sig) is missing — installation aborted. Unsigned/old release: run with PT_ALLOW_HASH_ONLY=1.'
                exit 1
            }
        } else {
            # Same principle as in install.sh: write the embedded pubkey into allowed_signers, namespace 'file'.
            $allowedSigners = Join-Path $Tmp 'allowed_signers'
            Set-Content -LiteralPath $allowedSigners -Value ('{0} namespaces="file" {1}' -f $SignPrincipal, $ReleaseSigningPubkey) -Encoding ascii -NoNewline
            Write-Host 'Verifying release signature...'
            # SHA256SUMS is fed to stdin as EXACT bytes (the analog of `< SHA256SUMS` in install.sh):
            # a PowerShell pipe would re-encode the content (BOM, CRLF) and a valid signature
            # would fall over as 'incorrect signature'. We copy the raw file stream.
            # Mirror of the securetrash/windows/install.ps1 canon — if you edit here, edit in all five.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $sshKeygen.Source
            $vArgs = @('-Y','verify','-f',$allowedSigners,'-I',$SignPrincipal,'-n','file','-s',$tmpSig)
            # `ArgumentList` only appeared in .NET Core (PowerShell 7). Windows PowerShell 5.1 —
            # the stock Windows shell and exactly the one people run the README one-liner in —
            # does not have it: touching it would crash the install at the signature-check step.
            # There we build the string ourselves. Every argument is quoted (TEMP can contain a
            # space), trailing backslashes are doubled — otherwise a slash escapes the closing quote.
            if ($psi.PSObject.Properties.Name -contains 'ArgumentList') {
                foreach ($a in $vArgs) { $psi.ArgumentList.Add($a) }
            } else {
                $psi.Arguments = (($vArgs | ForEach-Object { '"' + (($_ -replace '(\\*)"','$1$1\"') -replace '(\\+)$','$1$1') + '"' }) -join ' ')
            }
            $psi.RedirectStandardInput  = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute        = $false
            $proc = [System.Diagnostics.Process]::Start($psi)
            # We drain stdout/stderr ASYNCHRONOUSLY and BEFORE WaitForExit: a redirected but
            # unread stream runs into the pipe buffer — the verifier stalls, and the installer
            # waits for it forever. A silently hanging installer is worse than an honest refusal.
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
            # The verifier may exit without reading stdin to the end (bad arguments, a foreign
            # binary under the same name). Writing into a closed pipe is not our emergency: the
            # verdict is still given by the exit code, and the user must see an honest
            # "signature did not verify", not an unhandled installer exception.
            $fs = [System.IO.File]::OpenRead($tmpSums)
            try { $fs.CopyTo($proc.StandardInput.BaseStream) } catch [System.IO.IOException] { } finally { $fs.Close() }
            try { $proc.StandardInput.Close() } catch [System.IO.IOException] { }
            $null = $outTask.Result
            $null = $errTask.Result
            $proc.WaitForExit()
            if ($proc.ExitCode -eq 0) {
                Write-Host 'Signature OK (authenticity verified).'
            } else {
                Write-Error 'The release signature FAILED verification — installation aborted (possible tampering). There is no bypass.'
                exit 1
            }
        }
    }

    # Hash is correct → install.
    if (-not (Test-Path $LibDir)) {
        New-Item -ItemType Directory -Path $LibDir -Force | Out-Null
    }
    Copy-Item -Path $tmpScript -Destination $ScriptPath -Force
    Write-Host "Installed: $ScriptPath"
}
finally {
    Remove-Item -Path $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# .cmd shim so that `seedsplit <command>` can be called plainly from cmd/PowerShell.
$shim = @"
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\seedsplit.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
Set-Content -Path $ShimPath -Value $shim -Encoding ASCII
Write-Host "Shim created: $ShimPath"

# An install from before lib\ left the script next to the shim, and PowerShell picks
# THAT one for a bare command name — so an upgrade would change nothing until it goes.
$legacyScript = Join-Path $InstallDir 'seedsplit.ps1'
if (Test-Path -LiteralPath $legacyScript) {
    Remove-Item -LiteralPath $legacyScript -Force
    Write-Host "Removed the older copy next to the shim: $legacyScript"
}

# Add the directory to the user PATH (idempotent). SEEDSPLIT_SKIP_PATH=1 — skip.
if ($env:SEEDSPLIT_SKIP_PATH -ne '1') {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    $paths = $userPath.Split(';') | Where-Object { $_ -ne '' }
    if ($paths -notcontains $InstallDir) {
        $newPath = (($paths + $InstallDir) -join ';')
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "Added to user PATH: $InstallDir"
    } else {
        Write-Host 'Already on user PATH.'
    }
}

Write-Host ''
Write-Host 'Done. NEXT STEPS:'
Write-Host '  1) Open a NEW terminal (so PATH refreshes).'
Write-Host '  2) Run:  seedsplit version'
Write-Host '  3) Try:  "my secret" | seedsplit split -n 3 -t 2'
Write-Host ''
Write-Host 'NOTE: BETA port. Shares are byte-compatible with the macOS build, but verify on a'
Write-Host 'throwaway secret before trusting it with a real seed phrase.'
