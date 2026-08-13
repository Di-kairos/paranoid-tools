# install.ps1 — panic installer for Windows (BETA) with an integrity check.
#
# Pulls panic.ps1 and SHA256SUMS from a RELEASE tag (not the main branch) and checks the SHA256
# BEFORE installing. Closes the "irm|iex from main, unverified" supply-chain risk: release-tag
# content is immutable (unlike the moving main), the hash catches corruption, partial/
# cache substitution and publication desync. On top of integrity, the release SIGNATURE is
# verified (ed25519 via `ssh-keygen -Y verify` over SHA256SUMS, mirror of install.sh) — this
# proves AUTHENTICITY (who published), not just a hash match over a single channel.
#
# Usage (verify-then-run recommended, see windows/README.md):
#   irm https://github.com/Di-kairos/panic/releases/latest/download/install.ps1 -OutFile install.ps1
#   irm https://github.com/Di-kairos/panic/releases/latest/download/SHA256SUMS  -OutFile SHA256SUMS
#   # check install.ps1's hash manually, read the script, then:
#   pwsh -File install.ps1
#
# Environment variables:
#   PANIC_VERSION       — a specific tag (e.g. 0.1.3). Defaults to latest.
#   PANIC_BASE_URL      — the source in full: an http(s) URL OR a local directory (tests/forks).
#   PANIC_INSTALL_DIR   — install directory. Defaults to %LOCALAPPDATA%\Programs\panic.
#   PANIC_SKIP_PATH     — '1' skips the PATH edit (for tests).
#   PT_ALLOW_HASH_ONLY  — '1' allows a hash-ONLY install when the signature cannot be verified
#                         (no ssh-keygen or no .sig). Loud warning. Default is
#                         fail-closed: without signature verification the install aborts.
#
# WARNING: BETA port. Logic is tested via Pester (system primitives are mocked);
# behavior across the wide fleet of Windows consoles/locales/BitLocker configs is not field-tested.

$ErrorActionPreference = 'Stop'

$Repo = 'Di-kairos/panic'

# Source: explicit PANIC_BASE_URL → specific tag PANIC_VERSION → latest release.
if ($env:PANIC_BASE_URL) {
    $BaseUrl = $env:PANIC_BASE_URL
} elseif ($env:PANIC_VERSION) {
    $BaseUrl = "https://github.com/$Repo/releases/download/v$($env:PANIC_VERSION)"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/latest/download"
}

$InstallDir = if ($env:PANIC_INSTALL_DIR) { $env:PANIC_INSTALL_DIR } else {
    Join-Path $env:LOCALAPPDATA 'Programs\panic'
}
$ScriptPath = Join-Path $InstallDir 'panic.ps1'
$ShimPath   = Join-Path $InstallDir 'panic.cmd'

Write-Host 'panic (Windows, BETA) installer'
Write-Host '-------------------------------'

# Download a release file: http(s) → Invoke-RestMethod; local directory → copy.
# The local path is supported so tests can exercise the hash check without network.
function Get-ReleaseFile {
    param([string]$Name, [string]$OutFile)
    if ($BaseUrl -match '^https?://') {
        Invoke-RestMethod -Uri "$BaseUrl/$Name" -OutFile $OutFile
    } else {
        Copy-Item -Path (Join-Path $BaseUrl $Name) -Destination $OutFile -Force
    }
}

# Temporary download directory; cleaned up regardless.
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("panic-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
    $tmpScript = Join-Path $Tmp 'panic.ps1'
    $tmpSums   = Join-Path $Tmp 'SHA256SUMS'

    Write-Host 'Downloading panic.ps1 + SHA256SUMS from release...'
    Get-ReleaseFile -Name 'panic.ps1'  -OutFile $tmpScript
    Get-ReleaseFile -Name 'SHA256SUMS' -OutFile $tmpSums

    # Expected hash for panic.ps1 from SHA256SUMS (format: '<hash>  name').
    $expected = $null
    foreach ($line in Get-Content -Path $tmpSums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $fname = $parts[1].Trim().TrimStart('*')
            if ($fname -eq 'panic.ps1') { $expected = $parts[0].Trim().ToLower() }
        }
    }
    if (-not $expected) {
        Write-Error 'SHA256SUMS не содержит записи для panic.ps1 — установка прервана.'
        exit 1
    }

    $actual = (Get-FileHash -Path $tmpScript -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        Write-Error "Контрольная сумма НЕ совпала (возможна подмена) — установка прервана.`nexpected: $expected`nactual:   $actual"
        exit 1
    }
    Write-Host 'Checksum OK.'

    # --- Release SIGNATURE check (authenticity on top of integrity) ---
    # Mirrors install.sh: embedded ed25519 pubkey → allowed_signers → `ssh-keygen -Y verify`
    # over SHA256SUMS. FAIL-CLOSED: no ssh-keygen OR no .sig → refuse, except PT_ALLOW_HASH_ONLY=1
    # (loud warning, install on integrity only). Signature PRESENT but NOT matching —
    # always a hard refusal (a clear sign of substitution), no bypass.
    $SigningPubkey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U'
    $SignPrincipal = 'releases@paranoid-tools'

    $sshKeygen = Get-Command ssh-keygen -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sshKeygen) {
        if ($env:PT_ALLOW_HASH_ONLY -eq '1') {
            Write-Warning 'ssh-keygen недоступен — подпись релиза НЕ проверена (PT_ALLOW_HASH_ONLY=1, только целостность по SHA256).'
        } else {
            Write-Error 'ssh-keygen недоступен — подпись релиза не проверить, установка прервана. Установи OpenSSH-клиент или задай PT_ALLOW_HASH_ONLY=1 (только целостность). См. SECURITY.md.'
            exit 1
        }
    } else {
        $tmpSig  = Join-Path $Tmp 'SHA256SUMS.sig'
        $haveSig = $false
        try { Get-ReleaseFile -Name 'SHA256SUMS.sig' -OutFile $tmpSig; $haveSig = Test-Path $tmpSig } catch { $haveSig = $false }
        if (-not $haveSig) {
            if ($env:PT_ALLOW_HASH_ONLY -eq '1') {
                Write-Warning 'Подпись релиза (SHA256SUMS.sig) недоступна — продолжаю (PT_ALLOW_HASH_ONLY=1, только целостность).'
            } else {
                Write-Error 'Подпись релиза отсутствует — установка прервана. Для установки только по хешу: PT_ALLOW_HASH_ONLY=1. См. SECURITY.md.'
                exit 1
            }
        } else {
            $allowedSigners = Join-Path $Tmp 'allowed_signers'
            Set-Content -LiteralPath $allowedSigners -Value "$SignPrincipal namespaces=`"file`" $SigningPubkey" -NoNewline
            Write-Host 'Verifying release signature...'
            # SHA256SUMS is fed to stdin as EXACT bytes (analog of `< SHA256SUMS` in install.sh):
            # a PowerShell pipe would re-encode the content (BOM, CRLF) and a valid signature
            # would fall over as "incorrect signature". We copy the raw file stream.
            # Mirror of the securetrash/windows/install.ps1 canon — edit here, edit in all five.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $sshKeygen.Source
            $vArgs = @('-Y','verify','-f',$allowedSigners,'-I',$SignPrincipal,'-n','file','-s',$tmpSig)
            # `ArgumentList` only appeared in .NET Core (PowerShell 7). Windows PowerShell 5.1 —
            # the stock Windows shell and exactly the one the README one-liner runs in —
            # does not have it: touching it would crash the install at the signature-check step.
            # There we build the string ourselves. Every argument is quoted (TEMP can contain a
            # space), trailing backslashes are doubled — otherwise a backslash would escape the closing quote.
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
            # unread stream runs into the pipe buffer — the verifier stalls, and the installer
            # waits for it forever. A silently hanging installer is worse than an honest refusal.
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
            # The verifier may exit without reading stdin to the end (bad arguments, a foreign
            # binary under the same name). Writing into a closed pipe is not our emergency: the
            # verdict still comes from the exit code, and the user must see an honest "signature
            # did not match", not an unhandled installer exception.
            $fs = [System.IO.File]::OpenRead($tmpSums)
            try { $fs.CopyTo($proc.StandardInput.BaseStream) } catch [System.IO.IOException] { } finally { $fs.Close() }
            try { $proc.StandardInput.Close() } catch [System.IO.IOException] { }
            $null = $outTask.Result
            $null = $errTask.Result
            $proc.WaitForExit()
            if ($proc.ExitCode -eq 0) {
                Write-Host 'Signature OK (authenticity verified).'
            } else {
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

# A .cmd shim so you can call just `panic <command>` from cmd/PowerShell.
$shim = @"
@echo off
pwsh -NoProfile -File "%~dp0panic.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
Set-Content -Path $ShimPath -Value $shim -Encoding ASCII
Write-Host "Shim created: $ShimPath"

# Add the directory to the user PATH (idempotent). PANIC_SKIP_PATH=1 — skip.
if ($env:PANIC_SKIP_PATH -ne '1') {
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
Write-Host '  2) Run:  panic version'
Write-Host '  3) Preview (read-only):  panic status'
Write-Host ''
Write-Host 'NOTE: BETA port. `panic now` LOCKS/dismounts encrypted volumes and locks the screen —'
Write-Host 'run `panic status` first to see what it would touch. Forced locking may corrupt open files.'
