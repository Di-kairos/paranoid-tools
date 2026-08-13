# install.ps1 — ghostdraft installer for Windows (BETA) with an integrity check.
#
# Pulls ghostdraft.ps1 and SHA256SUMS from a RELEASE tag (not the main branch) and verifies
# the SHA256 BEFORE installing. Closes the "irm|iex from main without verification"
# supply-chain risk: a release tag's contents are immutable (unlike the moving main), the hash
# catches corruption, partial/cache tampering, and desync with the publication. HONESTLY: the
# checksum and the script arrive over the same channel — this does not protect against the
# RELEASE ITSELF being replaced; authenticity requires a signature (SHA256SUMS.sig).
#
# Usage (verify-then-run recommended, see windows/README.md):
#   irm https://github.com/Di-kairos/paranoid-tools/releases/download/ghostdraft-v0.1.19/install.ps1 -OutFile install.ps1
#   irm https://github.com/Di-kairos/paranoid-tools/releases/download/ghostdraft-v0.1.19/SHA256SUMS  -OutFile SHA256SUMS
#   # verify the install.ps1 hash manually, read the script, then:
#   pwsh -File install.ps1
#
# Environment variables:
#   GHOSTDRAFT_VERSION     — a specific tag (e.g. 0.1.6). Default: latest.
#   GHOSTDRAFT_BASE_URL    — the source entirely: an http(s) URL OR a local directory (tests/forks).
#   GHOSTDRAFT_INSTALL_DIR — install directory. Default: %LOCALAPPDATA%\Programs\ghostdraft.
#   GHOSTDRAFT_SKIP_PATH   — '1' skips the PATH edit (for tests).
#   PT_ALLOW_HASH_ONLY     — '1' allows installing on SHA256 alone when the release signature
#                            is unavailable (no .sig OR no ssh-keygen). A BAD signature is still
#                            fatal. Loud warning. Only for old/fork releases.
#   GHOSTDRAFT_TEST_SIGNING_PUBKEY — for tests ONLY: replaces the trusted release pubkey.
#     Using it prints a loud warning — a normal install does not need this variable.
#   GHOSTDRAFT_SSH_KEYGEN     — ssh-keygen path/name (default 'ssh-keygen'; for tests).
#
# WARNING: BETA port. The logic is verified via Pester (external effects are mocked);
# behavior across the wide fleet of Windows consoles/locales/editors is not road-tested.

$ErrorActionPreference = 'Stop'

$Repo = 'Di-kairos/paranoid-tools'
# Default release of this tool; kept in lockstep with the ghostdraft-vX.Y.Z tag by a
# release.yml gate. In the monorepo `releases/latest` is the latest release of ANY
# tool, so nothing here uses `latest` — the tag is always pinned.
$GHOSTDRAFT_VERSION_DEFAULT = '0.1.19'
# Source: explicit GHOSTDRAFT_BASE_URL → GHOSTDRAFT_VERSION override → the baked-in default tag.
if ($env:GHOSTDRAFT_BASE_URL) {
    $BaseUrl = $env:GHOSTDRAFT_BASE_URL
} elseif ($env:GHOSTDRAFT_VERSION) {
    $BaseUrl = "https://github.com/$Repo/releases/download/ghostdraft-v$($env:GHOSTDRAFT_VERSION)"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/download/ghostdraft-v$GHOSTDRAFT_VERSION_DEFAULT"
}

$InstallDir = if ($env:GHOSTDRAFT_INSTALL_DIR) { $env:GHOSTDRAFT_INSTALL_DIR } else {
    Join-Path $env:LOCALAPPDATA 'Programs\ghostdraft'
}
$ScriptPath = Join-Path $InstallDir 'ghostdraft.ps1'
$ShimPath   = Join-Path $InstallDir 'ghostdraft.cmd'

Write-Host 'ghostdraft (Windows, BETA) installer'
Write-Host '------------------------------------'

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
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ghostdraft-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
    $tmpScript = Join-Path $Tmp 'ghostdraft.ps1'
    $tmpSums   = Join-Path $Tmp 'SHA256SUMS'

    Write-Host 'Downloading ghostdraft.ps1 + SHA256SUMS from release...'
    Get-ReleaseFile -Name 'ghostdraft.ps1' -OutFile $tmpScript
    Get-ReleaseFile -Name 'SHA256SUMS'     -OutFile $tmpSums

    # Expected hash for ghostdraft.ps1 from SHA256SUMS (format: '<hash>  name').
    $expected = $null
    foreach ($line in Get-Content -Path $tmpSums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $fname = $parts[1].Trim().TrimStart('*')
            if ($fname -eq 'ghostdraft.ps1') { $expected = $parts[0].Trim().ToLower() }
        }
    }
    if (-not $expected) {
        Write-Error 'SHA256SUMS не содержит записи для ghostdraft.ps1 — установка прервана.'
        exit 1
    }

    $actual = (Get-FileHash -Path $tmpScript -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        Write-Error "Контрольная сумма НЕ совпала (возможна подмена) — установка прервана.`nexpected: $expected`nactual:   $actual"
        exit 1
    }
    Write-Host 'Checksum OK.'

    # --- Release SIGNATURE verification (authenticity on top of integrity) ---
    # Releases are signed with the ecosystem's dedicated ed25519 key (ssh-keygen -Y sign, namespace 'file').
    # Pubkey embedded below (same as in install.sh). Fail-closed:
    #   - no ssh-keygen OR no .sig → refusal, unless PT_ALLOW_HASH_ONLY=1 (loud warn);
    #   - .sig present and does NOT verify → HARD refusal ALWAYS (active sign of tampering; hash-only does not save you).
    # Replacing the trusted key is test-only and LOUD: silently trusting someone else's key
    # would devalue the whole signature check (the other 4 tools have no such variable at all).
    $ReleaseSigningPubkey = if ($env:GHOSTDRAFT_TEST_SIGNING_PUBKEY) {
        Write-Warning 'GHOSTDRAFT_TEST_SIGNING_PUBKEY задан: подпись проверяется ЧУЖИМ ключом, а не ключом релизов ghostdraft. Это режим тестов — в обычной установке так быть не должно.'
        $env:GHOSTDRAFT_TEST_SIGNING_PUBKEY
    } else {
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U'
    }
    $SignPrincipal = 'releases@paranoid-tools'
    $HashOnly = ($env:PT_ALLOW_HASH_ONLY -eq '1')
    $KeygenName = if ($env:GHOSTDRAFT_SSH_KEYGEN) { $env:GHOSTDRAFT_SSH_KEYGEN } else { 'ssh-keygen' }
    $Keygen = Get-Command $KeygenName -ErrorAction SilentlyContinue

    if (-not $Keygen) {
        # ssh-keygen is unavailable → nothing to verify the signature with.
        if ($HashOnly) {
            Write-Warning 'ssh-keygen недоступен — подпись релиза НЕ проверена (PT_ALLOW_HASH_ONLY=1, только целостность по SHA256).'
        } else {
            Write-Error 'ssh-keygen недоступен — не могу проверить подпись релиза. Установи OpenSSH (Add-WindowsCapability OpenSSH.Client) или, для старого/неподписанного релиза, запусти с PT_ALLOW_HASH_ONLY=1 (только целостность).'
            exit 1
        }
    } else {
        $tmpSig = Join-Path $Tmp 'SHA256SUMS.sig'
        $haveSig = $false
        try {
            Get-ReleaseFile -Name 'SHA256SUMS.sig' -OutFile $tmpSig
            $haveSig = (Test-Path $tmpSig)
        } catch {
            $haveSig = $false
        }
        if (-not $haveSig) {
            # The release has no .sig.
            if ($HashOnly) {
                Write-Warning 'Подпись релиза (SHA256SUMS.sig) отсутствует — продолжаю (PT_ALLOW_HASH_ONLY=1, только целостность по SHA256).'
            } else {
                Write-Error 'Подпись релиза (SHA256SUMS.sig) отсутствует — установка прервана. Релизы подписаны; для старого/неподписанного релиза: PT_ALLOW_HASH_ONLY=1.'
                exit 1
            }
        } else {
            $allowedSigners = Join-Path $Tmp 'allowed_signers'
            Set-Content -LiteralPath $allowedSigners -Value ("$SignPrincipal namespaces=`"file`" $ReleaseSigningPubkey") -NoNewline
            Write-Host 'Verifying release signature...'
            # ssh-keygen -Y verify reads the signed data (SHA256SUMS) from stdin. We feed the EXACT
            # bytes of the file via .NET Process (a PowerShell pipe / Start-Process would re-encode
            # the content → 'incorrect signature'); we copy the raw file stream into stdin.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $Keygen.Source
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
                # A bad signature is fatal ALWAYS; PT_ALLOW_HASH_ONLY does not bypass it.
                Write-Error 'Подпись релиза НЕ прошла проверку — установка прервана (возможна подмена).'
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

# .cmd shim so that `ghostdraft <command>` can be called plainly from cmd/PowerShell.
$shim = @"
@echo off
pwsh -NoProfile -File "%~dp0ghostdraft.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
Set-Content -Path $ShimPath -Value $shim -Encoding ASCII
Write-Host "Shim created: $ShimPath"

# Add the directory to the user PATH (idempotent). GHOSTDRAFT_SKIP_PATH=1 — skip.
if ($env:GHOSTDRAFT_SKIP_PATH -ne '1') {
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
Write-Host '  2) Run:  ghostdraft version'
Write-Host '  3) Try:  Get-Clipboard | ghostdraft pipe'
Write-Host ''
Write-Host 'NOTE: BETA port. For a REAL ephemeral guarantee, open a securetrash vault first —'
Write-Host 'Windows has no built-in RAM disk, so the no-vault fallback writes an on-disk temp file.'
