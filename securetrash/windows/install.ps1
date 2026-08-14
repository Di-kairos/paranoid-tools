# install.ps1 — securetrash installer for Windows (BETA) with an integrity check.
#
# Pulls securetrash.ps1, SHA256SUMS and SHA256SUMS.sig from the RELEASE tag (not from
# the main branch), verifies SHA256 BEFORE installing AND checks the ed25519 signature
# of SHA256SUMS with an embedded pubkey (`ssh-keygen -Y verify`, same key and same
# fail-closed logic as install.sh). Closes the "irm|iex from main without verification"
# supply-chain risk: the hash catches corruption/cache substitution, and the signature —
# substitution of the RELEASE ITSELF (both files rewritten),
# since an attacker without the private key cannot forge a valid .sig.
# Fail-closed: no ssh-keygen / no .sig / signature mismatch → install aborted.
# Bypass only via an explicit $env:PT_ALLOW_HASH_ONLY='1' (only SHA256 integrity remains).
#
# Usage (verify-then-run recommended, see windows/README.md):
#   irm https://github.com/Di-kairos/paranoid-tools/releases/download/securetrash-v0.5.7/install.ps1 -OutFile install.ps1
#   irm https://github.com/Di-kairos/paranoid-tools/releases/download/securetrash-v0.5.7/SHA256SUMS  -OutFile SHA256SUMS
#   # verify install.ps1's hash by hand, read the script, then:
#   pwsh -File install.ps1
#
# Environment variables:
#   ST_VERSION      — a specific tag (e.g. 0.4.0). Defaults to latest.
#   ST_BASE_URL     — the source as a whole: http(s) URL OR a local directory (tests/forks).
#   ST_INSTALL_DIR  — install directory. Defaults to %LOCALAPPDATA%\Programs\securetrash.
#   ST_SKIP_PATH    — '1' skips the PATH edit (for tests).
#   PT_ALLOW_HASH_ONLY — '1' allows installing without signature verification (SHA256 only).
#                        Unsafe fail-closed bypass: authenticity is NOT confirmed.
#
# WARNING: BETA port. Logic is tested via Pester; BitLocker/VHDX/VeraCrypt
# behavior is NOT validated on real hardware.

$ErrorActionPreference = 'Stop'

$Repo = 'Di-kairos/paranoid-tools'
# Default release of this tool; kept in lockstep with the securetrash-vX.Y.Z tag by a
# release.yml gate. In the monorepo `releases/latest` is the latest release of ANY
# tool, so nothing here uses `latest` — the tag is always pinned.
$ST_VERSION_DEFAULT = '0.5.7'
# Source: explicit ST_BASE_URL → ST_VERSION override → the baked-in default tag.
if ($env:ST_BASE_URL) {
    $BaseUrl = $env:ST_BASE_URL
} elseif ($env:ST_VERSION) {
    $BaseUrl = "https://github.com/$Repo/releases/download/securetrash-v$($env:ST_VERSION)"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/download/securetrash-v$ST_VERSION_DEFAULT"
}

$InstallDir = if ($env:ST_INSTALL_DIR) { $env:ST_INSTALL_DIR } else {
    Join-Path $env:LOCALAPPDATA 'Programs\securetrash'
}
$ScriptPath = Join-Path $InstallDir 'securetrash.ps1'
$ShimPath   = Join-Path $InstallDir 'securetrash.cmd'

Write-Host 'SecureTrash (Windows, BETA) installer'
Write-Host '------------------------------------'

# Download a file from the release: http(s) → Invoke-RestMethod; local directory → copy.
# The local path is supported so tests can exercise the hash check without a network.
function Get-ReleaseFile {
    param([string]$Name, [string]$OutFile)
    if ($BaseUrl -match '^https?://') {
        Invoke-RestMethod -Uri "$BaseUrl/$Name" -OutFile $OutFile
    } else {
        Copy-Item -Path (Join-Path $BaseUrl $Name) -Destination $OutFile -Force
    }
}

# Temporary download directory; cleaned up no matter what.
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("securetrash-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
    $tmpScript = Join-Path $Tmp 'securetrash.ps1'
    $tmpSums   = Join-Path $Tmp 'SHA256SUMS'

    Write-Host "Downloading securetrash.ps1 + SHA256SUMS from release..."
    Get-ReleaseFile -Name 'securetrash.ps1' -OutFile $tmpScript
    Get-ReleaseFile -Name 'SHA256SUMS'      -OutFile $tmpSums

    # Expected hash for securetrash.ps1 from SHA256SUMS (format: '<hash>  name').
    $expected = $null
    foreach ($line in Get-Content -Path $tmpSums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $fname = $parts[1].Trim().TrimStart('*')
            if ($fname -eq 'securetrash.ps1') { $expected = $parts[0].Trim().ToLower() }
        }
    }
    if (-not $expected) {
        Write-Error 'SHA256SUMS has no entry for securetrash.ps1 — installation aborted.'
        exit 1
    }

    $actual = (Get-FileHash -Path $tmpScript -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        Write-Error "Checksum MISMATCH (possible tampering) — installation aborted.`nexpected: $expected`nactual:   $actual"
        exit 1
    }
    Write-Host 'Checksum OK.'

    # --- RELEASE SIGNATURE check (authenticity on top of integrity) ---
    # Port of install.sh's fail-closed logic. Releases are signed with a dedicated ed25519
    # key (`ssh-keygen -Y`). The pubkey embedded below is THE SAME as in install.sh; it
    # changes only on key rotation. ssh-keygen ships with the Windows OpenSSH client.
    #   * no ssh-keygen            → refusal (authenticity unverifiable);
    #   * .sig missing             → refusal (v0.4.2+ releases are always signed);
    #   * .sig present but does NOT verify → refusal (clear sign of substitution).
    # The only bypass is $env:PT_ALLOW_HASH_ONLY='1' (loud warning,
    # only SHA256 integrity remains; authenticity is NOT confirmed).
    $SigningPubkey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U'
    $SignPrincipal = 'releases@paranoid-tools'
    $hashOnly = ($env:PT_ALLOW_HASH_ONLY -eq '1')

    $sshKeygen = Get-Command ssh-keygen -CommandType Application -ErrorAction SilentlyContinue |
                 Select-Object -First 1
    if (-not $sshKeygen) {
        if ($hashOnly) {
            Write-Warning 'ssh-keygen unavailable — the release signature was NOT verified (PT_ALLOW_HASH_ONLY=1, SHA256 integrity only).'
        } else {
            Write-Error ('ssh-keygen (OpenSSH) is unavailable — the release signature cannot be checked, installation aborted. ' +
                'Install the OpenSSH client (Settings -> Optional features) or, accepting the risk, set $env:PT_ALLOW_HASH_ONLY=''1''.')
            exit 1
        }
    } else {
        $tmpSig = Join-Path $Tmp 'SHA256SUMS.sig'
        $gotSig = $false
        try {
            Get-ReleaseFile -Name 'SHA256SUMS.sig' -OutFile $tmpSig
            $gotSig = (Test-Path $tmpSig)
        } catch { $gotSig = $false }

        if (-not $gotSig) {
            if ($hashOnly) {
                Write-Warning 'The release signature is unavailable — continuing (PT_ALLOW_HASH_ONLY=1, SHA256 integrity only).'
            } else {
                Write-Error ('The release signature (SHA256SUMS.sig) is missing — installation aborted. ' +
                    'Releases v0.4.2+ are always signed. Bypass (at your own risk): $env:PT_ALLOW_HASH_ONLY=''1''.')
                exit 1
            }
        } else {
            # allowed_signers: same format as in install.sh
            # (`<principal> namespaces="file" <pubkey>`).
            $allowedSigners = Join-Path $Tmp 'allowed_signers'
            Set-Content -Path $allowedSigners -Value "$SignPrincipal namespaces=`"file`" $SigningPubkey" -Encoding ascii
            Write-Host 'Verifying release signature...'
            # SHA256SUMS is fed to stdin as EXACT bytes (analog of `< SHA256SUMS` in install.sh):
            # a PowerShell pipe would re-encode the content (BOM, CRLF) and a valid signature
            # would bounce as "incorrect signature". We copy the file's raw stream.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $sshKeygen.Source
            $vArgs = @('-Y','verify','-f',$allowedSigners,'-I',$SignPrincipal,'-n','file','-s',$tmpSig)
            # `ArgumentList` only appeared in .NET Core (PowerShell 7). Windows PowerShell 5.1 —
            # the stock Windows shell and exactly the one that runs the README one-liner —
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
            # stdout/stderr are drained ASYNCHRONOUSLY and BEFORE WaitForExit: a redirected but
            # unread stream hits the pipe buffer — the verifier stalls, and the installer
            # waits for it forever. A silently hanging installer is worse than an honest refusal.
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
            # The verifier may exit without reading stdin to the end (bad arguments, a foreign
            # binary under the same name). Writing into a closed pipe is not our emergency: the
            # verdict is still given by the exit code, and the user must see an honest "signature
            # mismatch", not an unhandled installer exception.
            $fs = [System.IO.File]::OpenRead($tmpSums)
            try { $fs.CopyTo($proc.StandardInput.BaseStream) } catch [System.IO.IOException] { } finally { $fs.Close() }
            try { $proc.StandardInput.Close() } catch [System.IO.IOException] { }
            $null = $outTask.Result
            $null = $errTask.Result
            $proc.WaitForExit()
            if ($proc.ExitCode -eq 0) {
                Write-Host 'Signature OK (authenticity verified).'
            } else {
                Write-Error 'The release signature FAILED verification — installation aborted (possible tampering).'
                exit 1
            }
        }
    }

    # Hash is correct → install.
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    Copy-Item -Path $tmpScript -Destination $ScriptPath -Force
    Write-Host "Installed: $ScriptPath"
}
finally {
    Remove-Item -Path $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# A .cmd shim so that plain `securetrash <command>` works from cmd/PowerShell.
$shim = @"
@echo off
pwsh -NoProfile -File "%~dp0securetrash.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
Set-Content -Path $ShimPath -Value $shim -Encoding ASCII
Write-Host "Shim created: $ShimPath"

# Add the directory to the user PATH (idempotent). ST_SKIP_PATH=1 — skip.
if ($env:ST_SKIP_PATH -ne '1') {
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
Write-Host '  2) Run:  securetrash check'
Write-Host '  3) Then: securetrash setup'
Write-Host ''
Write-Host 'NOTE: BETA port. Verify behavior on a test container before trusting it with real secrets.'
