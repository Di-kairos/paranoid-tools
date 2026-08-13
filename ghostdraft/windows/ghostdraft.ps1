# ghostdraft.ps1 — ephemeral draft for sensitive text (Paranoid Tools),
# Windows port (BETA). Mirror of the macOS version (bash). Baseline: Windows PowerShell 5.1.
#
# Write/view a seed/password/key so that after closing, as few traces as possible
# remain in the usual places (editor backups, recent docs, clipboard).
#
# HONESTLY (easy to slide into snake oil — we do NOT promise "zero traces"):
#   - Windows has NO built-in RAM disk (unlike macOS hdiutil ram://). So the
#     fallback draft lands in a TEMPORARY FILE ON DISK (ACL for the current user only) +
#     best-effort overwrite-shred. On an SSD overwriting is NO guarantee (wear-leveling).
#     Real ephemerality exists only inside an open securetrash vault (BitLocker VHDX:
#     closing = crypto-shred). Hence the priority: GHOSTDRAFT_DIR → open vault → on-disk fallback.
#   - the OS may keep the pagefile (swap) and console scrollback — we list them honestly.
#   - --clipboard for a seed is dangerous (Win+V clipboard history + Cloud Clipboard sync into
#     the Microsoft account) — OFF by default, with a warning. There is NO background auto-clear
#     (on Windows it is unreliable: clipboard cmdlets need STA, a background job doesn't provide
#     it) — clear it manually.
#
# BETA: the logic is covered by Pester (external effects — editor/shred/clipboard — are mocked);
# behavior on real hardware with exotic editors/locales is not widely road-tested.

$VERSION = '0.1.18'

# --- configurable primitives (mirror of bash GHOSTDRAFT_*/ST_VAULT_VOLUME) ---
# Root of the open securetrash vault. securetrash.ps1 mounts the VHDX on the FIRST FREE
# letter (not a fixed V:) and writes it into the <vault>.mount sidecar — we read it the
# same way windows/paranoid.ps1 does. Otherwise a draft with a secret silently drifted into
# the on-disk fallback while a live vault was open (AUDIT_2026-08-03 P0-3). ST_VAULT_VOLUME
# overrides manually.
function Get-GdVaultVolume {
    if ($env:ST_VAULT_VOLUME) { return $env:ST_VAULT_VOLUME }
    $vaultPath = if ($env:ST_VAULT_PATH) { $env:ST_VAULT_PATH } else {
        $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $null }
        if ($homeDir) { Join-Path $homeDir 'SecureVault.vhdx' } else { $null }
    }
    if ($vaultPath) {
        $sidecar = "$vaultPath.mount"
        try {
            if (Test-Path -LiteralPath $sidecar) {
                $m = (Get-Content -LiteralPath $sidecar -Raw -ErrorAction Stop).Trim()
                # The sidecar is a hint, not proof: it could have survived a rough detach,
                # with the letter reused by an unrelated volume. Trust only with an attached VHDX.
                if ($m -and (Test-GdVaultAttached -VaultPath $vaultPath)) { return $m }
            }
        } catch { }   # unreadable sidecar = no hint; the normal fallback below
    }
    return 'V:\'   # legacy default: vaults created before the sidecar existed
}

# Is the VHDX attached right now — best-effort: without Get-DiskImage (non-Windows test run)
# or on error we cannot disprove it → trust the sidecar (no worse than the old V:\ heuristic).
function Test-GdVaultAttached {
    param([string]$VaultPath)
    if (-not $VaultPath -or -not (Test-Path -LiteralPath $VaultPath)) { return $false }
    if (-not (Get-Command Get-DiskImage -ErrorAction SilentlyContinue)) { return $true }
    try { return [bool](Get-DiskImage -ImagePath $VaultPath -ErrorAction Stop).Attached } catch { return $true }
}

# --- locale: en by default; ru — if ST_LANG or the system UI locale starts with 'ru' ---
function Get-GdLocale {
    $want = $env:ST_LANG
    if ($want) {
        if ($want -match '^(?i)ru') { return 'ru' } else { return 'en' }
    }
    if ($PSUICulture -and ($PSUICulture -match '^(?i)ru')) { return 'ru' }
    return 'en'
}
$script:GD_LOCALE = if ($env:ST_LOCALE) { $env:ST_LOCALE } else { Get-GdLocale }

# --- output helpers: data — stdout (Write-Output); warnings/errors — stderr ---
function Write-GdInfo { param([string]$Msg) Write-Output "[+] $Msg" }
function Write-GdWarn { param([string]$Msg) [Console]::Error.WriteLine("[!] $Msg") }
function Write-GdErr  { param([string]$Msg) [Console]::Error.WriteLine("[x] $Msg") }

# --- exit via an exception (Pester-safe: does not kill the host session) ---
class GdExit : System.Exception {
    [int]$Code
    GdExit([int]$code) : base("GdExit:$code") { $this.Code = $code }
}
function Stop-GdCommand { param([int]$Code = 1) throw [GdExit]::new($Code) }

# --- confirm: true only on an exact 'yes'; ST_ASSUME_YES=1 bypasses (tests/scripts) ---
function Confirm-Gd {
    param([string]$Prompt)
    if ($env:ST_ASSUME_YES -eq '1') { return $true }
    $suffix = if ($script:GD_LOCALE -eq 'ru') { '[введите yes]' } else { '[type yes]' }
    $ans = Read-Host "$Prompt $suffix"
    return ($ans -eq 'yes')
}

# --- i18n (ghostdraft string table; mirror of bash t(), trace locations adapted for Windows) ---
function T {
    param([string]$Key, [string]$A)
    $loc = $script:GD_LOCALE
    switch ("${loc}:${Key}") {
        'en:unknown_cmd'    { return "Unknown command: $A" }
        'ru:unknown_cmd'    { return "Неизвестная команда: $A" }
        'en:pipe_scrollback'{ return 'Shown above. Nothing written to disk — but the console buffer still holds it; clear it (close the window / Clear-Host) when done.' }
        'ru:pipe_scrollback'{ return 'Показано выше. На диск ничего не записано — но в буфере консоли текст остаётся; очисти его (закрой окно / Clear-Host), когда закончишь.' }
        'en:new_loc_vault'  { return "Draft inside the open securetrash vault ($A) — encrypted; closing the vault crypto-shreds it." }
        'ru:new_loc_vault'  { return "Черновик внутри открытого vault securetrash ($A) — зашифрован; закрытие vault даёт crypto-shred." }
        'en:new_loc_override'{ return "Draft in GHOSTDRAFT_DIR ($A) — you chose this path; its on-disk safety is on you." }
        'ru:new_loc_override'{ return "Черновик в GHOSTDRAFT_DIR ($A) — путь выбран тобой; безопасность на диске на твоей совести." }
        'en:new_loc_fallback'{ return "No open vault — falling back to an ON-DISK temp file ($A), ACL-locked to you. Windows has no built-in RAM disk, so this is NOT real ephemeral memory: shred is best-effort overwrite (no guarantee on SSD). For a real guarantee, open a securetrash vault first." }
        'ru:new_loc_fallback'{ return "Vault не открыт — fallback во ВРЕМЕННЫЙ ФАЙЛ НА ДИСКЕ ($A), ACL только для тебя. На Windows нет встроенного RAM-диска, так что это НЕ настоящая эфемерная память: shred — best-effort overwrite (на SSD без гарантии). Для реальной гарантии сначала открой vault securetrash." }
        'en:new_residue'    { return 'Draft shredded and editor backups cleaned. CANNOT scrub: console scrollback, the OS pagefile (swap), and a vim ~/.viminfo if you used vim — handle those yourself.' }
        'ru:new_residue'    { return 'Черновик удалён, editor-бэкапы вычищены. НЕ могу вычистить: scrollback консоли, pagefile (swap) ОС и ~/.viminfo от vim (если использовал vim) — это на тебе.' }
        'en:clip_danger'    { return 'DANGER: --clipboard copies the secret to the system clipboard. Clipboard history (Win+V) keeps copies, and Cloud Clipboard syncs it to your Microsoft account / other devices. There is NO background auto-clear on Windows — clear it yourself.' }
        'ru:clip_danger'    { return 'ОПАСНО: --clipboard кладёт секрет в системный буфер. История буфера (Win+V) хранит копии, а Cloud Clipboard синкает его в твой аккаунт Microsoft / на другие устройства. Фоновой авто-очистки на Windows НЕТ — чисти сам.' }
        'en:clip_confirm'   { return 'Copy to clipboard anyway?' }
        'ru:clip_confirm'   { return 'Всё равно скопировать в буфер?' }
        'en:clip_set'       { return 'Copied to clipboard. Clear it yourself when done (Win+V history is NOT auto-purged).' }
        'ru:clip_set'       { return 'Скопировано в буфер. Очисти сам, когда закончишь (история Win+V НЕ чистится автоматически).' }
        'en:clip_cancelled' { return 'Clipboard skipped.' }
        'ru:clip_cancelled' { return 'Буфер пропущен.' }
        default             { return $Key }
    }
}

function Get-GdUsage {
    if ($script:GD_LOCALE -eq 'ru') {
        return @'
Usage: ghostdraft <command> [args]

Commands:
  new [--clipboard]   Редактировать эфемерный черновик (в открытом vault / on-disk fallback),
                      по выходу — shred + чистка editor-истории.
  pipe                Читать stdin, печатать в терминал, на диск НЕ писать ничего
                      (напр. Get-Clipboard | ghostdraft pipe).
  version             Показать версию

ghostdraft НЕ обещает «ноль следов» там, где ОС может оставить копию (pagefile,
scrollback консоли) — перечисляем честно. --clipboard по умолчанию ВЫКЛ.
'@
    }
    return @'
Usage: ghostdraft <command> [args]

Commands:
  new [--clipboard]   Edit an ephemeral draft (in an open vault / on-disk fallback), then
                      shred it and clean editor history on exit.
  pipe                Read stdin, print to the terminal, write NOTHING to disk
                      (e.g. Get-Clipboard | ghostdraft pipe).
  version             Show the version

Flags:
  --yes               Skip confirmation prompts (same as ST_ASSUME_YES=1)

ghostdraft does NOT promise "zero traces" where the OS may keep a copy (pagefile,
console scrollback) — those are listed honestly. --clipboard is OFF by default.
'@
}

# === pipe — read stdin, print to the terminal, write NOTHING to disk ===
# The safest mode: nothing is created on disk. We honestly warn that the console scrollback
# still holds the text. We print raw (no extra newline) — pipe fidelity.
function Invoke-GdPipe {
    param([string]$Text)
    if ($null -ne $Text -and $Text.Length -gt 0) { [Console]::Out.Write($Text) }
    Write-GdWarn (T 'pipe_scrollback')
}

# === new: ephemeral draft + shred + editor-residue cleanup ===

# Is the volume mounted and writable? (directory + writable). Crude but honest:
# we do not write to a path that merely looks like a vault.
function Test-GdWritableDir {
    param([string]$Path)
    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    # Write probe: create and delete a zero-byte file.
    $probe = Join-Path $Path (".gd-probe-" + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType File -Path $probe -Force -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

# Pick a directory for the draft. Returns @{ Dir; Kind } (kind: override|vault|fallback).
# Priority: GHOSTDRAFT_DIR → open vault (ST_VAULT_VOLUME) → on-disk secure-temp fallback.
function Get-GdDraftLocation {
    $ov = $env:GHOSTDRAFT_DIR
    if ($ov) {
        New-Item -ItemType Directory -Path $ov -Force -ErrorAction SilentlyContinue | Out-Null
        if (Test-GdWritableDir $ov) { return @{ Dir = $ov; Kind = 'override' } }
    }
    $vaultVol = Get-GdVaultVolume
    if (Test-GdWritableDir $vaultVol) {
        return @{ Dir = $vaultVol; Kind = 'vault' }
    }
    $tmp = New-GdSecureTempDir
    return @{ Dir = $tmp; Kind = 'fallback' }
}

# Create a temp directory with an ACL for the current user only (inheritance disabled).
# Best-effort: if the ACL could not be set — the directory is still created (with a warning).
function New-GdSecureTempDir {
    $dir = Join-Path $env:TEMP ("ghostdraft-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $acl = Get-Acl -LiteralPath $dir
        $acl.SetAccessRuleProtection($true, $false)   # disable inheritance, drop inherited rules
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $me, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $dir -AclObject $acl
    } catch {
        Write-GdWarn "ACL on the temp dir could not be tightened (continuing): $dir"
    }
    return $dir
}

# Create the draft file in the directory (zero-byte, ACL inherited from the protected directory).
function New-GdDraftFile {
    param([string]$Dir)
    $f = Join-Path $Dir (".ghostdraft." + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType File -Path $f -Force | Out-Null
    return $f
}

# Launch the editor on the file, wait for it to close (mocked in tests).
function Invoke-GdEditor {
    param([string]$Path)
    $editor = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }
    Start-Process -FilePath $editor -ArgumentList $Path -Wait -NoNewWindow
}

# Overwrite and delete a file. We prefer securetrash shred (its honest logic);
# otherwise fallback: overwrite with random bytes + delete (best-effort on SSD, no guarantee).
function Invoke-GdShred {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $st = Get-Command 'securetrash' -ErrorAction SilentlyContinue
    if ($st) {
        # Save and restore the user's value: previously finally removed the variable
        # entirely, so ST_ASSUME_YES=1 set by the caller vanished after the shred.
        $prevAssumeYes = $env:ST_ASSUME_YES
        try {
            $env:ST_ASSUME_YES = '1'
            & securetrash shred $Path 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { return }
        } catch { } finally {
            if ($null -eq $prevAssumeYes) { Remove-Item Env:\ST_ASSUME_YES -ErrorAction SilentlyContinue }
            else { $env:ST_ASSUME_YES = $prevAssumeYes }
        }
    }
    try {
        $len = (Get-Item -LiteralPath $Path).Length
        if ($len -gt 0) {
            $buf = New-Object byte[] $len
            (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($buf)
            [System.IO.File]::WriteAllBytes($Path, $buf)
        }
    } catch { }
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

# Remove editor residue next to the draft: vim swap/undo, nano backup. HONESTLY: ~/.viminfo,
# the pagefile and the scrollback we CANNOT selectively scrub (see new_residue).
function Clear-GdEditorResidue {
    param([string]$Path)
    if (-not $Path) { return }
    $dir = Split-Path -Parent $Path
    $base = Split-Path -Leaf $Path
    $cands = @(".$base.swp", ".$base.swo", ".$base.swn", ".$base.un~", "$base~")
    foreach ($c in $cands) {
        Remove-Item -LiteralPath (Join-Path $dir $c) -Force -ErrorAction SilentlyContinue
    }
}

# Put the draft into the system clipboard with an explicit confirmation (dangerous). $false —
# clipboard untouched (the caller proceeds with the shred). On Windows there is NO background auto-clear.
function Set-GdClipboardDraft {
    param([string]$Path)
    Write-GdWarn (T 'clip_danger')
    if (-not (Confirm-Gd (T 'clip_confirm'))) { Write-GdWarn (T 'clip_cancelled'); return $false }
    $content = Get-Content -LiteralPath $Path -Raw
    Set-Clipboard -Value $content
    Write-GdInfo (T 'clip_set')
    return $true
}

# Remove the fallback temp directory entirely (after the file shred).
function Remove-GdTempDir {
    param([string]$Dir)
    if ($Dir -and (Test-Path -LiteralPath $Dir)) {
        Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-GdNew {
    param([string[]]$ArgList)
    $useClip = $false
    foreach ($a in $ArgList) {
        switch ($a) {
            '--clipboard' { $useClip = $true }
            default { Write-GdErr (T 'unknown_cmd' $a); Stop-GdCommand 1 }
        }
    }

    $loc = Get-GdDraftLocation
    $dir = $loc.Dir
    $kind = $loc.Kind
    $tempDirToRemove = if ($kind -eq 'fallback') { $dir } else { $null }
    $f = New-GdDraftFile -Dir $dir

    switch ($kind) {
        'vault'    { Write-GdInfo (T 'new_loc_vault' $dir) }
        'override' { Write-GdWarn (T 'new_loc_override' $dir) }
        'fallback' { Write-GdWarn (T 'new_loc_fallback' $dir) }
    }

    try {
        Invoke-GdEditor -Path $f
        if ($useClip) { Set-GdClipboardDraft -Path $f | Out-Null }
        Write-GdWarn (T 'new_residue')
    } finally {
        Invoke-GdShred -Path $f
        Clear-GdEditorResidue -Path $f
        Remove-GdTempDir -Dir $tempDirToRemove
    }
}

function Invoke-GdVersion { Write-Output "ghostdraft $VERSION (Windows, beta)" }

function Invoke-GdMain {
    param([string[]]$Argv)
    try {
        # --yes anywhere in the arguments == ST_ASSUME_YES=1 (the securetrash contract).
        # After `--` arguments are literal (mirror of bash).
        if ($Argv -and ($Argv -contains '--yes')) {
            $kept = @(); $literal = $false
            foreach ($a in $Argv) {
                if (-not $literal -and $a -eq '--yes') { $env:ST_ASSUME_YES = '1'; continue }
                if ($a -eq '--') { $literal = $true }
                $kept += $a
            }
            $Argv = $kept
        }
        $cmd = if ($Argv -and $Argv.Count -ge 1) { $Argv[0] } else { '' }
        if (-not $cmd) { Write-Output (Get-GdUsage); exit 1 }
        $rest = @(if ($Argv.Count -ge 2) { $Argv[1..($Argv.Count - 1)] } else { @() })
        switch ($cmd) {
            { $_ -in 'version', '-v', '--version' } { Invoke-GdVersion }
            { $_ -in 'help', '--help', '-h' }       { Write-Output (Get-GdUsage) }
            'pipe' {
                # Read the whole of stdin from the console (redirect-safe); empty → warn only.
                Invoke-GdPipe -Text ([Console]::In.ReadToEnd())
            }
            'new'  { Invoke-GdNew -ArgList $rest }
            default { Write-GdErr (T 'unknown_cmd' $cmd); [Console]::Error.WriteLine((Get-GdUsage)); exit 1 }
        }
    } catch [GdExit] {
        exit $_.Exception.Code
    }
}

# Dot-source guard: under `. ghostdraft.ps1` (Pester) main does NOT run; ST_NO_MAIN=1 silences it too.
if ($MyInvocation.InvocationName -ne '.' -and -not $env:ST_NO_MAIN) {
    Invoke-GdMain -Argv $args
}
