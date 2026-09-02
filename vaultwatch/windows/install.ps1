# install.ps1 — vaultwatch installer for Windows (BETA) with an integrity check.
#
# Pulls vaultwatch.ps1 and SHA256SUMS from a RELEASE tag (not the main branch) and checks the
# SHA256 BEFORE installing. Closes the "irm|iex from main without verification" supply-chain
# risk: a release tag's contents are immutable (unlike the moving main), the hash catches
# corruption, partial/cache tampering, and drift from the publication. HONEST: the checksum and
# the script arrive over the same channel — this does not protect against the RELEASE ITSELF
# being replaced; authenticity requires a signature (SHA256SUMS.sig).
#
# Usage (verify-then-run recommended, see windows/README.md):
#   irm https://github.com/Di-kairos/paranoid-tools/releases/download/vaultwatch-v0.1.15/install.ps1 -OutFile install.ps1
#   irm https://github.com/Di-kairos/paranoid-tools/releases/download/vaultwatch-v0.1.15/SHA256SUMS  -OutFile SHA256SUMS
#   # verify install.ps1's hash manually, read the script, then:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File install.ps1
#
# Environment variables:
#   VAULTWATCH_VERSION     — a specific tag (e.g. 0.1.3). Defaults to latest.
#   VAULTWATCH_BASE_URL    — the source as a whole: http(s) URL OR a local directory (tests/forks).
#   VAULTWATCH_INSTALL_DIR — install directory. Defaults to %LOCALAPPDATA%\Programs\vaultwatch.
#   VAULTWATCH_SKIP_PATH   — '1' skips the PATH edit (for tests).
#   PT_ALLOW_HASH_ONLY     — '1' allows installing on SHA256 integrity alone, when the signature
#                            cannot be verified (no ssh-keygen OR the release has no .sig). A bad
#                            signature ALWAYS aborts the install, the bypass does not apply.
#
# WARNING: BETA port. The logic is verified via Pester (system effects are mocked);
# behavior across the wide fleet of Windows configs (Search/VSS/Task Scheduler) is not field-tested.

$ErrorActionPreference = 'Stop'

$Repo = 'Di-kairos/paranoid-tools'
# Default release of this tool; kept in lockstep with the vaultwatch-vX.Y.Z tag by a
# release.yml gate. In the monorepo `releases/latest` is the latest release of ANY
# tool, so nothing here uses `latest` — the tag is always pinned.
$VAULTWATCH_VERSION_DEFAULT = '0.1.15'
# Source: explicit VAULTWATCH_BASE_URL → VAULTWATCH_VERSION override → the baked-in default tag.
if ($env:VAULTWATCH_BASE_URL) {
    $BaseUrl = $env:VAULTWATCH_BASE_URL
} elseif ($env:VAULTWATCH_VERSION) {
    $BaseUrl = "https://github.com/$Repo/releases/download/vaultwatch-v$($env:VAULTWATCH_VERSION)"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/download/vaultwatch-v$VAULTWATCH_VERSION_DEFAULT"
}

$InstallDir = if ($env:VAULTWATCH_INSTALL_DIR) { $env:VAULTWATCH_INSTALL_DIR } else {
    Join-Path $env:LOCALAPPDATA 'Programs\vaultwatch'
}
# The script itself lives in lib\, NOT next to the shim. PowerShell resolves a bare
# `vaultwatch` on PATH to a .ps1 BEFORE a .cmd of the same name, and a .ps1 is refused
# outright under the default ExecutionPolicy (Restricted) — so a .ps1 on PATH means
# the command fails in PowerShell no matter what the shim does. With only the shim
# visible, the command works from cmd, Windows PowerShell 5.1 and pwsh 7 alike.
$LibDir     = Join-Path $InstallDir 'lib'
$ScriptPath = Join-Path $LibDir 'vaultwatch.ps1'
$ShimPath   = Join-Path $InstallDir 'vaultwatch.cmd'

function Get-ReleaseFile {
    param([string]$Name, [string]$OutFile)
    if ($BaseUrl -match '^https?://') {
        Invoke-RestMethod -Uri "$BaseUrl/$Name" -OutFile $OutFile
    } else {
        Copy-Item -Path (Join-Path $BaseUrl $Name) -Destination $OutFile -Force
    }
}

# --- Release SIGNATURE verification (authenticity on top of integrity) — port of install.sh ---
# Releases are signed with the ecosystem's dedicated Ed25519 key (ssh-keygen -Y). Pubkey embedded below.
# Windows ships with OpenSSH (ssh-keygen). FAIL-CLOSED, mirrors install.sh:
#   - ssh-keygen unavailable OR .sig missing → install aborted, UNLESS PT_ALLOW_HASH_ONLY=1
#     is set (then a loud warning: only SHA256 integrity was verified);
#   - .sig present and does NOT verify → hard refusal with NO bypass (a clear sign of tampering; as in install.sh).
$script:ReleaseSigningPubkey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9DVd0vNOwa5hyr9gShaCWoNOVnUsrdHVO/WE0wCZkT'
$script:SignPrincipal = 'releases@paranoid-tools'

function Get-VwVerifier {
    # Path to ssh-keygen (or $null). Split into its own function for mockability in Pester.
    (Get-Command ssh-keygen -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1).Source
}

function Invoke-VwVerifier {
    # Wrapper over `ssh-keygen -Y verify` — split out so it can be mocked in tests.
    # Windows OpenSSH ssh-keygen reads the signed data from stdin; we return the exit code.
    param([string]$AllowedSigners, [string]$Principal, [string]$SigFile, [string]$SumsFile)
    # The SHA256SUMS bytes are passed AS IS: a PowerShell pipe re-encodes text (BOM, CRLF),
    # and a valid signature would bounce as "incorrect signature" (mirror of ghostdraft).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-VwVerifier)
    $vArgs = @('-Y','verify','-f',$AllowedSigners,'-I',$Principal,'-n','file','-s',$SigFile)
    # `ArgumentList` only appeared in .NET Core (PowerShell 7). Windows PowerShell 5.1 —
    # the stock Windows shell and exactly the one people run the README one-liner in —
    # does not have it: touching it would crash the install at the signature-check step.
    # There we build the string ourselves. Every argument is quoted (TEMP can contain a
    # space), trailing backslashes are doubled — otherwise a backslash escapes the closing quote.
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
    # stdout/stderr are drained ASYNCHRONOUSLY and BEFORE WaitForExit: a redirected but
    # unread stream hits the pipe buffer limit — the verifier stalls, and the installer
    # waits on it forever. A silently hanging installer is worse than an honest refusal.
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    # The verifier may exit without reading stdin to the end (mangled arguments, a foreign
    # binary under the same name). Writing into a closed pipe is not our emergency: the
    # verdict is still given by the exit code, and the user must see an honest "signature
    # did not verify", not an unhandled installer exception.
    $fs = [System.IO.File]::OpenRead($SumsFile)
    try { $fs.CopyTo($proc.StandardInput.BaseStream) } catch [System.IO.IOException] { } finally { $fs.Close() }
    try { $proc.StandardInput.Close() } catch [System.IO.IOException] { }
    $null = $outTask.Result
    $null = $errTask.Result
    $proc.WaitForExit()
    return $proc.ExitCode
}

function Assert-VwSignature {
    param([string]$Tmp)
    $sumsFile = Join-Path $Tmp 'SHA256SUMS'
    $sigFile  = Join-Path $Tmp 'SHA256SUMS.sig'
    $allowHashOnly = ($env:PT_ALLOW_HASH_ONLY -eq '1')

    # 1) Is the verifier available?
    $verifier = Get-VwVerifier
    if (-not $verifier) {
        if ($allowHashOnly) {
            Write-Warning 'ssh-keygen unavailable — the release signature was NOT verified (SHA256 integrity only). PT_ALLOW_HASH_ONLY=1.'
            return
        }
        throw 'ssh-keygen unavailable — the release signature cannot be checked. Install OpenSSH, or reinstall with PT_ALLOW_HASH_ONLY=1 (integrity only). Installation aborted.'
    }

    # 2) Pull the .sig; its absence = fail-closed (bypass — PT_ALLOW_HASH_ONLY=1).
    try {
        Get-ReleaseFile -Name 'SHA256SUMS.sig' -OutFile $sigFile
    } catch {
        Remove-Item -LiteralPath $sigFile -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $sigFile)) {
        if ($allowHashOnly) {
            Write-Warning 'The release signature (SHA256SUMS.sig) is missing — continuing on integrity alone (PT_ALLOW_HASH_ONLY=1, for old releases only).'
            return
        }
        throw 'The release signature (SHA256SUMS.sig) is missing — installation aborted. Unsigned/old release: PT_ALLOW_HASH_ONLY=1 (integrity only).'
    }

    # 3) allowed_signers with the EMBEDDED pubkey (same format as in install.sh), then verify.
    $allowed = Join-Path $Tmp 'allowed_signers'
    Set-Content -LiteralPath $allowed -Encoding ASCII `
        -Value ('{0} namespaces="file" {1}' -f $script:SignPrincipal, $script:ReleaseSigningPubkey)
    Write-Host 'Verifying the release signature...'
    $rc = Invoke-VwVerifier -AllowedSigners $allowed -Principal $script:SignPrincipal -SigFile $sigFile -SumsFile $sumsFile
    if ($rc -eq 0) {
        Write-Host 'Release signature OK (authenticity confirmed).'
    } else {
        # Bad signature — hard refusal with NO bypass (as in install.sh): an active sign of tampering.
        throw 'The release signature FAILED verification — installation aborted (possible tampering).'
    }
}

# Main install flow. VAULTWATCH_NO_MAIN=1 → only define the functions (for Pester).
if ($env:VAULTWATCH_NO_MAIN -ne '1') {

Write-Host 'vaultwatch (Windows, BETA) installer'
Write-Host '------------------------------------'

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("vaultwatch-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
    $tmpScript = Join-Path $Tmp 'vaultwatch.ps1'
    $tmpSums   = Join-Path $Tmp 'SHA256SUMS'

    Write-Host 'Downloading vaultwatch.ps1 + SHA256SUMS from release...'
    Get-ReleaseFile -Name 'vaultwatch.ps1' -OutFile $tmpScript
    Get-ReleaseFile -Name 'SHA256SUMS'     -OutFile $tmpSums

    $expected = $null
    foreach ($line in Get-Content -Path $tmpSums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $fname = $parts[1].Trim().TrimStart('*')
            if ($fname -eq 'vaultwatch.ps1') { $expected = $parts[0].Trim().ToLower() }
        }
    }
    if (-not $expected) {
        Write-Error 'SHA256SUMS has no entry for vaultwatch.ps1 — installation aborted.'
        exit 1
    }

    $actual = (Get-FileHash -Path $tmpScript -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        Write-Error "Checksum MISMATCH (possible tampering) — installation aborted.`nexpected: $expected`nactual:   $actual"
        exit 1
    }
    Write-Host 'Checksum OK.'

    # Authenticity on top of integrity: verify the release signature (fail-closed).
    Assert-VwSignature -Tmp $Tmp

    if (-not (Test-Path $LibDir)) {
        New-Item -ItemType Directory -Path $LibDir -Force | Out-Null
    }
    Copy-Item -Path $tmpScript -Destination $ScriptPath -Force
    Write-Host "Installed: $ScriptPath"
}
finally {
    Remove-Item -Path $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$shim = @"
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\vaultwatch.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
Set-Content -Path $ShimPath -Value $shim -Encoding ASCII
Write-Host "Shim created: $ShimPath"

# An install from before lib\ left the script next to the shim, and PowerShell picks
# THAT one for a bare command name — so an upgrade would change nothing until it goes.
$legacyScript = Join-Path $InstallDir 'vaultwatch.ps1'
if (Test-Path -LiteralPath $legacyScript) {
    Remove-Item -LiteralPath $legacyScript -Force
    Write-Host "Removed the older copy next to the shim: $legacyScript"
}

if ($env:VAULTWATCH_SKIP_PATH -ne '1') {
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
Write-Host '  2) Run:  vaultwatch version'
Write-Host '  3) Guard a mounted vault:  vaultwatch start --ttl 30m V:\'
Write-Host ''
Write-Host 'NOTE: BETA port. Search exclusion + TTL auto-dismount work; backup snapshots (VSS) are'
Write-Host 'reported but NOT removed, and the pagefile is not addressed. See windows/README.md.'

}  # /if VAULTWATCH_NO_MAIN
