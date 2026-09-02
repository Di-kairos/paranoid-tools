# install.ps1 — installer for the WHOLE Paranoid Tools ecosystem on Windows (BETA).
#
# The mirror of the top-level `install.sh` on macOS: one command installs all five tools
# (securetrash, vaultwatch, panic, ghostdraft, seedsplit) plus the `paranoid` launcher —
# instead of running five per-tool one-liners by hand.
#
# It is a WRAPPER, not a second delivery channel: every tool is installed by its own
# `<tool>/windows/install.ps1` from this clone, and that installer is the one that pulls the
# signed release and verifies it (SHA256 + the Ed25519 signature over SHA256SUMS, fail-closed).
# So the verification chain is unchanged; this script only points all five at ONE directory
# and edits PATH once instead of five times.
#
# Usage (from the clone root) - windows\install.cmd is the documented entry point, because
# it needs nothing of the user: it finds pwsh and sets the ExecutionPolicy for its own process.
#   windows\install.cmd              # install/update all five + the launcher
#   windows\install.cmd -Uninstall   # remove them (data and vaults are untouched)
#
# Environment variables:
#   PT_INSTALL_DIR — install directory for all five + the launcher.
#                    Defaults to %LOCALAPPDATA%\Programs\ParanoidTools.
#   PT_SKIP_PATH   — '1' skips the PATH edit (for tests).
#   PT_ALLOW_PARTIAL — '1' lets the run finish with a zero exit code when some tools failed.
#   Per-tool variables are passed straight through to the per-tool installers, so a version
#   is pinned the same way as before: ST_VERSION, VAULTWATCH_VERSION, PANIC_VERSION,
#   GHOSTDRAFT_VERSION, SEEDSPLIT_VERSION (and PT_ALLOW_HASH_ONLY, which they all read).
#   `<TOOL>_INSTALL_DIR` and `<TOOL>_SKIP_PATH` are set BY this script and are overwritten.
#
# WARNING: BETA port, like the five tools themselves.

param(
    # Removes the tools and the launcher installed by this script. Vaults, notes and any
    # other data stay where they are — this only takes back what the installer put there.
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# $env:OS, not $IsWindows: the latter is undefined in Windows PowerShell 5.1.
if ($env:OS -ne 'Windows_NT') {
    Write-Error 'This installer is for Windows. On macOS use install.sh from the repository root.'
    exit 1
}

# Each per-tool installer reads its OWN env prefix — they are not uniform (ST_, VAULTWATCH_, ...).
$Tools = @(
    @{ Name = 'securetrash'; Prefix = 'ST' },
    @{ Name = 'vaultwatch';  Prefix = 'VAULTWATCH' },
    @{ Name = 'panic';       Prefix = 'PANIC' },
    @{ Name = 'ghostdraft';  Prefix = 'GHOSTDRAFT' },
    @{ Name = 'seedsplit';   Prefix = 'SEEDSPLIT' }
)

# Repo root = the parent of windows/ — so the script works from any current directory.
$Root = Split-Path -Parent $PSScriptRoot

$InstallDir = if ($env:PT_INSTALL_DIR) { $env:PT_INSTALL_DIR } else {
    Join-Path $env:LOCALAPPDATA 'Programs\ParanoidTools'
}

if ($Uninstall) {
    Write-Host "Removing Paranoid Tools from $InstallDir"
    if (-not (Test-Path -LiteralPath $InstallDir)) {
        Write-Host 'Nothing to remove: that directory does not exist.'
        exit 0
    }
    # The shims sit in $InstallDir, the scripts in $InstallDir\lib - and an install from
    # before lib\ left the scripts next to the shims, so both places are cleaned.
    $names = @()
    foreach ($tool in $Tools) { $names += @("$($tool.Name).ps1", "$($tool.Name).cmd", "lib\$($tool.Name).ps1") }
    $names += @('paranoid.ps1', 'paranoid.cmd', 'lib\paranoid.ps1')
    $removed = 0
    foreach ($name in $names) {
        $path = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
            Write-Host "  removed $name"
            $removed++
        }
    }
    # Same rule as for the install directory below: only an empty lib\ is deleted.
    $libDir = Join-Path $InstallDir 'lib'
    if ((Test-Path -LiteralPath $libDir) -and -not (Get-ChildItem -LiteralPath $libDir -Force)) {
        Remove-Item -LiteralPath $libDir -Force
    }
    # Only an empty directory is deleted: anything else in there is the user's, not ours.
    if (-not (Get-ChildItem -LiteralPath $InstallDir -Force)) {
        Remove-Item -LiteralPath $InstallDir -Force
    } else {
        Write-Warning "$InstallDir is not empty — left in place with whatever else is inside it."
    }
    if ($env:PT_SKIP_PATH -ne '1') {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath) {
            $kept = $userPath.Split(';') | Where-Object { $_ -ne '' -and $_ -ne $InstallDir }
            if (($kept -join ';') -ne $userPath) {
                [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
                Write-Host "Removed from user PATH: $InstallDir"
            }
        }
    }
    # A per-tool install (the one-liner from a tool's README) uses its own directory, so the
    # umbrella cannot know about it — but a leftover copy there would still answer on PATH.
    $strays = @()
    foreach ($tool in $Tools) {
        if (-not $env:LOCALAPPDATA) { break }
        $own = Join-Path $env:LOCALAPPDATA (Join-Path 'Programs' $tool.Name)
        if ($own -ne $InstallDir -and (Test-Path -LiteralPath $own)) { $strays += $own }
    }
    if ($strays.Count -gt 0) {
        Write-Host ''
        Write-Host 'Installed separately earlier, still on disk (delete by hand if you no longer want them):'
        foreach ($dir in $strays) { Write-Host "  $dir" }
    }
    Write-Host ''
    Write-Host "Done: $removed file(s) removed. Vaults, notes and shares were NOT touched."
    exit 0
}

# The tools' own .cmd shims call `pwsh`, and the ports are supported on PowerShell 7 — so the
# per-tool installers are run by pwsh too, even when this script was started by 5.1.
$pwshExe = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue |
           Select-Object -First 1
if (-not $pwshExe) {
    Write-Error 'PowerShell 7 (pwsh) was not found — install it first: winget install --id Microsoft.PowerShell -e'
    exit 1
}

Write-Host 'Paranoid Tools (Windows, BETA) — installing all five + the launcher'
Write-Host "Target directory: $InstallDir"
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

$installed = 0
foreach ($tool in $Tools) {
    $toolInstaller = Join-Path $Root (Join-Path $tool.Name 'windows\install.ps1')
    Write-Host ''
    Write-Host "--- $($tool.Name)"
    if (-not (Test-Path -LiteralPath $toolInstaller)) {
        Write-Warning "$($tool.Name): $toolInstaller is missing — skipped (is this a full clone?)."
        continue
    }
    # One directory for everything and no per-tool PATH edits: the five installers would
    # otherwise each append their own %LOCALAPPDATA%\Programs\<tool> to the user PATH.
    Set-Item -Path "Env:\$($tool.Prefix)_INSTALL_DIR" -Value $InstallDir
    Set-Item -Path "Env:\$($tool.Prefix)_SKIP_PATH"   -Value '1'
    # A child process, not a dot-source: a per-tool installer refuses fail-closed with
    # `exit 1`, and its exit code is the only honest verdict about that tool.
    & $pwshExe.Source -NoProfile -File $toolInstaller
    if ($LASTEXITCODE -eq 0) {
        $installed++
    } else {
        Write-Warning "$($tool.Name): its installer exited with code $LASTEXITCODE — not installed (see its output above)."
    }
}

# The launcher is versioned in this repo (it has no release of its own), so it is copied
# from the clone next to this script — the same way install.sh installs `paranoid` on macOS.
Write-Host ''
$launcherSrc = Join-Path $PSScriptRoot 'paranoid.ps1'
if (Test-Path -LiteralPath $launcherSrc) {
    # lib\, not $InstallDir: PowerShell resolves a bare `paranoid` on PATH to a .ps1 before
    # the .cmd, and the default ExecutionPolicy then refuses to load it - so a .ps1 on PATH
    # is what breaks the command. Only the shim is visible, and it works from any shell.
    $libDir = Join-Path $InstallDir 'lib'
    New-Item -ItemType Directory -Path $libDir -Force | Out-Null
    Copy-Item -LiteralPath $launcherSrc -Destination (Join-Path $libDir 'paranoid.ps1') -Force
    $shim = @"
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\paranoid.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
    Set-Content -Path (Join-Path $InstallDir 'paranoid.cmd') -Value $shim -Encoding ASCII
    # A pre-lib install left the launcher next to the shim, where PowerShell picks it first.
    $legacyLauncher = Join-Path $InstallDir 'paranoid.ps1'
    if (Test-Path -LiteralPath $legacyLauncher) { Remove-Item -LiteralPath $legacyLauncher -Force }
    Write-Host "Installed: $(Join-Path $libDir 'paranoid.ps1') (+ paranoid.cmd shim)"
} else {
    Write-Warning "paranoid.ps1 is missing next to this script — the launcher was not installed."
}

# Remember WHERE this was installed from: the launcher's Update item re-runs the installer from
# that directory. The copy in %LOCALAPPDATA% knows nothing about the clone it came from, so
# without this the menu item would have nothing to update. Mirror of install.sh's state file.
if ($env:LOCALAPPDATA) {
    $stateDir = Join-Path $env:LOCALAPPDATA 'paranoid-tools'
    try {
        New-Item -ItemType Directory -Path $stateDir -Force -ErrorAction Stop | Out-Null
        $stateFile = Join-Path $stateDir 'source'
        # Removed first: writing over a symlink would clobber whatever it points at.
        if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue }
        Set-Content -LiteralPath $stateFile -Value $Root -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Could not record the source directory ($stateDir\source) — the launcher's Update item will ask for PARANOID_SRC."
    }
}

# One PATH edit for the shared directory (idempotent). PT_SKIP_PATH=1 — skip.
if ($env:PT_SKIP_PATH -ne '1') {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    $paths = $userPath.Split(';') | Where-Object { $_ -ne '' }
    if ($paths -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable('Path', (($paths + $InstallDir) -join ';'), 'User')
        Write-Host "Added to user PATH: $InstallDir"
    } else {
        Write-Host 'Already on user PATH.'
    }
}

Write-Host ''
Write-Host "Tools installed: $installed/$($Tools.Count) (+ the paranoid launcher)."
Write-Host 'NEXT STEPS:'
Write-Host '  1) Open a NEW terminal (so PATH refreshes).'
Write-Host '  2) Run:  paranoid          (the interactive launcher)'
Write-Host '     or:   securetrash check'
Write-Host ''
Write-Host 'NOTE: BETA port. Verify behavior on test data before trusting it with real secrets.'

# A partial install is not a quiet success — same rule as install.sh (override: PT_ALLOW_PARTIAL=1).
if ($installed -lt $Tools.Count -and $env:PT_ALLOW_PARTIAL -ne '1') {
    Write-Error "Installation is incomplete ($installed/$($Tools.Count)) — exiting with an error. Override: `$env:PT_ALLOW_PARTIAL='1'."
    exit 1
}
