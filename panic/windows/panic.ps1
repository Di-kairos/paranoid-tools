# panic.ps1 — one-step kill-switch (Paranoid Tools), Windows port (BETA).
# Mirror of the macOS (bash) version. Baseline: Windows PowerShell 5.1 (no PS7-only syntax).
#
# Scenario: border crossing / coercion / "someone is coming". A single `panic now` HIDES and
# LOCKS: locks unlocked BitLocker volumes, dismounts VeraCrypt volumes, clears the
# clipboard and locks the screen (P/Invoke `user32!LockWorkStation`). `--hard` also
# kills cloud daemons (OneDrive/Dropbox/Google Drive) and clears Recent items.
#
# HONESTLY (as in the bash version): panic HIDES and LOCKS, but does NOT destroy and does NOT wipe
# the pagefile (for destruction — securetrash). Forced locking/dismounting with open files
# may corrupt data — a deliberate panic-mode trade-off (hiding matters more). BitLocker lock
# requires admin and works only for data volumes with auto-unlock disabled (not the system drive);
# VeraCrypt dismount requires veracrypt.exe on PATH. A missing mechanism is not an error
# (best-effort, like pkill in bash). The full core comes in later packs; see README "Scope & limitations".
#
# BETA: logic is covered by Pester (system primitives are mocked); behavior on real hardware with
# exotic locales/BitLocker/VeraCrypt configurations is not widely field-tested.

$VERSION = '0.1.16'

# --- configurable primitives (mirror of bash PANIC_*; overridable for tests) ---
# VeraCrypt CLI process name (on PATH). Cloud daemons and the Recent items directory are below.
$script:PN_VERACRYPT = if ($env:PANIC_VERACRYPT) { $env:PANIC_VERACRYPT } else { 'VeraCrypt' }
# Cloud daemon process names for Stop-Process (Windows equivalents of bird/Dropbox/...).
$script:PN_CLOUD_DAEMONS = @('OneDrive', 'Dropbox', 'GoogleDriveFS')
# Global Recent items directory (jump-list shortcuts). Overridden for tests.
$script:PN_RECENT_DIR = if ($env:PANIC_RECENT_DIR) { $env:PANIC_RECENT_DIR } else {
    Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
}

# --- locale: en by default; ru — if ST_LANG or the system UI locale starts with 'ru' ---
function Get-PnLocale {
    $want = $env:ST_LANG
    if ($want) {
        if ($want -match '^(?i)ru') { return 'ru' } else { return 'en' }
    }
    if ($PSUICulture -and ($PSUICulture -match '^(?i)ru')) { return 'ru' }
    return 'en'
}
$script:PN_LOCALE = if ($env:ST_LOCALE) { $env:ST_LOCALE } else { Get-PnLocale }

# --- output helpers: data/reports — Write-Output (stdout); warnings/errors — stderr ---
function Write-PnInfo { param([string]$Msg) Write-Output "[+] $Msg" }
function Write-PnWarn { param([string]$Msg) [Console]::Error.WriteLine("[!] $Msg") }
function Write-PnErr  { param([string]$Msg) [Console]::Error.WriteLine("[x] $Msg") }

# --- exit via exception (Pester-safe: does not kill the host session) ---
class PnExit : System.Exception {
    [int]$Code
    PnExit([int]$code) : base("PnExit:$code") { $this.Code = $code }
}
function Stop-PnCommand { param([int]$Code = 1) throw [PnExit]::new($Code) }

# --- i18n (panic string table; mirror of bash t()) ---
function T {
    param([string]$Key, [string]$A)
    $loc = $script:PN_LOCALE
    switch ("${loc}:${Key}") {
        'en:unknown_cmd'      { return "Unknown command: $A" }
        'ru:unknown_cmd'      { return "Неизвестная команда: $A" }
        'en:hotkey_no_win'    { return "hotkey is macOS-only: it is bound through skhd, which has no Windows counterpart, and panic will not leave a background process resident just to watch the keyboard. Windows binds hotkeys on the shortcut itself: create a shortcut to panic.cmd (Start menu or Desktop), open Properties, put the cursor in 'Shortcut key' and press Ctrl+Alt+P. Windows then runs it from anywhere. Nothing here is installed or removed on your behalf." }
        'ru:hotkey_no_win'    { return "hotkey — только для macOS: там он вешается через skhd, аналога которому в Windows нет, а держать фоновый процесс ради слежения за клавиатурой panic не станет. В Windows горячая клавиша живёт на самом ярлыке: сделай ярлык на panic.cmd (меню «Пуск» или рабочий стол), открой «Свойства», поставь курсор в поле «Быстрый вызов» и нажми Ctrl+Alt+P. Дальше Windows запускает его откуда угодно. Ничего за тебя тут не ставится и не удаляется." }
        'en:no_admin_lock'    { return 'NOT an administrator console: encrypted volumes canNOT be locked from here (BitLocker is administrator-only), so an open vault stays OPEN. The clipboard and the screen lock still work. For the full kill-switch run panic from an administrator PowerShell.' }
        'ru:no_admin_lock'    { return 'Консоль БЕЗ прав администратора: запереть шифр-тома отсюда НЕЛЬЗЯ (BitLocker доступен только администратору) — открытый сейф останется ОТКРЫТ. Буфер и блокировка экрана работают. Для полного kill-switch запусти panic из PowerShell от имени администратора.' }
        'en:status_admin_no'  { return '  administrator: NO — `panic now` will not be able to lock encrypted volumes' }
        'ru:status_admin_no'  { return '  администратор: НЕТ — `panic now` не сможет запереть шифр-тома' }
        'en:status_admin_yes' { return '  administrator: yes — volume locking is available' }
        'ru:status_admin_yes' { return '  администратор: да — запирание томов доступно' }
        'en:status_header'    { return 'panic status — read-only preflight (no changes made)' }
        'ru:status_header'    { return 'panic status — только чтение, предпросмотр (изменений нет)' }
        'en:status_vols'      { return "  encrypted volumes unlocked: $A — would be locked/dismounted by ``panic now``" }
        'ru:status_vols'      { return "  разблокированных шифр-томов: $A — будут заперты/размонтированы ``panic now``" }
        'en:status_no_vols'   { return '  encrypted volumes: none unlocked (or no BitLocker/VeraCrypt access)' }
        'ru:status_no_vols'   { return '  шифр-томов: ни одного разблокированного (или нет доступа к BitLocker/VeraCrypt)' }
        'en:status_clip_has'  { return '  clipboard: non-empty — would be cleared' }
        'ru:status_clip_has'  { return '  буфер обмена: не пуст — будет очищен' }
        'en:status_clip_empty'{ return '  clipboard: empty' }
        'ru:status_clip_empty'{ return '  буфер обмена: пуст' }
        'en:status_bl_on'     { return '  BitLocker (system drive): ON — data at rest is encrypted' }
        'ru:status_bl_on'     { return '  BitLocker (системный диск): ВКЛ — данные на диске зашифрованы' }
        'en:status_bl_off'    { return '  BitLocker (system drive): OFF — disk not encrypted (data at risk if drive seized)' }
        'ru:status_bl_off'    { return '  BitLocker (системный диск): ВЫКЛ — диск не зашифрован (данные под угрозой при изъятии)' }
        'en:status_cloud'     { return "  cloud daemon running: $A — would be killed by ``panic now --hard``" }
        'ru:status_cloud'     { return "  cloud-демон запущен: $A — будет убит ``panic now --hard``" }
        'en:dismount_fail'    { return "could not lock/dismount $A (may have open files, or needs admin)." }
        'ru:dismount_fail'    { return "не удалось запереть/размонтировать $A (открыты файлы или нужен admin)." }
        'en:now_hard'         { return 'panic --hard: cloud daemons killed, recent items cleared.' }
        'ru:now_hard'         { return 'panic --hard: cloud-демоны убиты, recent items очищены.' }
        'en:now_report'       { return "panic: locked/dismounted $A encrypted volume(s), cleared clipboard." }
        'ru:now_report'       { return "panic: заперто/размонтировано шифр-томов: $A, буфер очищен." }
        'en:lock_ok'          { return 'screen locked.' }
        'ru:lock_ok'          { return 'экран заперт.' }
        'en:lock_fail'        { return 'could NOT lock the screen — lock it now (Win+L).' }
        'ru:lock_fail'        { return 'НЕ удалось заблокировать экран — заблокируйте вручную (Win+L).' }
        default               { return $Key }
    }
}

function Get-PnUsage {
    if ($script:PN_LOCALE -eq 'ru') {
        return @'
Usage: panic <command> [args]

Commands:
  status              Только чтение: что затронет `panic now` (безопасно, предпросмотр).
  now [--hard]        Спрятать и запереть сейчас: запереть BitLocker-тома, размонтировать
                      тома VeraCrypt, очистить буфер, заблокировать экран. --hard также
                      прибивает cloud-демоны и чистит Recent items.
  hotkey              Нет в Windows-порте — печатает, как повесить Ctrl+Alt+P средствами ОС.
  version             Показать версию

panic ПРЯЧЕТ и ЗАПИРАЕТ — НЕ уничтожает и НЕ чистит pagefile (для уничтожения —
securetrash). Принудительное запирание может повредить открытые файлы — осознанный trade-off.
'@
    }
    return @'
Usage: panic <command> [args]

Commands:
  status              Read-only preflight: show what `panic now` would affect.
  now [--hard]        Hide & lock now: lock BitLocker volumes, dismount VeraCrypt
                      volumes, clear clipboard, lock screen. --hard also kills cloud
                      daemons and clears recent items.
  hotkey              Not in the Windows port - prints how to bind Ctrl+Alt+P with the OS itself.
  version             Show the version

panic HIDES and LOCKS — it does NOT destroy or wipe the pagefile (use securetrash to
destroy). Forced locking may corrupt open files — a deliberate panic trade-off.
'@
}

# === system primitives (wrappers — mocked in Pester; best-effort on hardware) ===

# Unlocked BitLocker data volumes that can be locked (not the system drive,
# protection on, status Unlocked). Empty if the module/access is missing (best-effort).
function Get-PnBitLockerUnlocked {
    try {
        $vols = Get-BitLockerVolume -ErrorAction Stop
    } catch { return @() }
    return @($vols | Where-Object {
        $_.VolumeType -ne 'OperatingSystem' -and
        $_.ProtectionStatus -eq 'On' -and
        $_.LockStatus -eq 'Unlocked'
    } | ForEach-Object { $_.MountPoint })
}

# Lock a BitLocker volume (force-dismount closes open handles). Throws on failure.
function Invoke-PnLockBitLocker {
    param([string]$MountPoint)
    Lock-BitLocker -MountPoint $MountPoint -ForceDismount -ErrorAction Stop | Out-Null
}

# Mounted VeraCrypt volumes (drive letters). Empty if veracrypt.exe is not on PATH.
# We parse `VeraCrypt /l`: lines like "1: \Device\... F: ...". We take the drive letter (3rd field).
function Get-PnVeraCryptMounted {
    $exe = Get-Command $script:PN_VERACRYPT -ErrorAction SilentlyContinue
    if (-not $exe) { return @() }
    $out = & $script:PN_VERACRYPT '/l' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return @() }
    return @($out | ForEach-Object {
        if ($_ -match '\b([A-Za-z]):') { $matches[1] + ':' }
    } | Where-Object { $_ })
}

# Dismount ALL VeraCrypt volumes (force, quiet). Throws on failure.
function Invoke-PnDismountVeraCrypt {
    & $script:PN_VERACRYPT '/q' '/d' '/f' 2>$null
    if ($LASTEXITCODE -ne 0) { throw "VeraCrypt dismount exit $LASTEXITCODE" }
}

# Clear the clipboard (mirror of `pbcopy </dev/null`).
function Invoke-PnClearClipboard {
    try { Set-Clipboard -Value '' -ErrorAction Stop } catch { }
}

# Is the clipboard non-empty? (for the status preflight).
function Test-PnClipboardNonEmpty {
    try {
        $c = Get-Clipboard -Raw -ErrorAction Stop
        return [bool]($c -and $c.Length -gt 0)
    } catch { return $false }
}

# Lock the screen down to the sign-in screen (mirror of _lock_screen). Honestly returns its status.
# P/Invoke user32!LockWorkStation instead of `rundll32 ...,LockWorkStation`: rundll32's exit code
# is the helper process's status, NOT the lock's result (it could return 0 even with the lock not accepted).
# LockWorkStation returns the API's own bool → an honest "lock request accepted" signal.
function Invoke-PnLockScreen {
    try {
        if (-not ('PnNative.User32' -as [type])) {
            Add-Type -Namespace PnNative -Name User32 -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
public static extern bool LockWorkStation();
'@
        }
        return [bool][PnNative.User32]::LockWorkStation()
    } catch { return $false }
}

# Administrator rights in THIS session (wrapper for Mock). Lock-BitLocker is administrator-only,
# and without rights Get-BitLockerVolume throws — which the enumeration catches and reports as
# "no unlocked volumes". So an unelevated `panic now` printed "locked 0 volumes" over a vault
# that was standing wide open. The rights have to be named, not inferred from an empty list.
function Test-PnElevated {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# Is BitLocker on for the system drive? (mirror of filevault_on).
function Test-PnBitLockerOn {
    try {
        $sys = Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.VolumeType -eq 'OperatingSystem' }
        return [bool]($sys -and $sys.ProtectionStatus -eq 'On')
    } catch { return $false }
}

# --hard: kill cloud daemons (best-effort, a missing process is not an error).
function Invoke-PnKillCloudDaemons {
    foreach ($name in $script:PN_CLOUD_DAEMONS) {
        try { Stop-Process -Name $name -Force -ErrorAction Stop } catch { }
    }
}

# Running cloud daemons (for the status preflight).
function Get-PnRunningCloudDaemons {
    @($script:PN_CLOUD_DAEMONS | Where-Object {
        Get-Process -Name $_ -ErrorAction SilentlyContinue
    })
}

# --hard: clear global Recent items (jump-list shortcuts). HONESTLY: covers the
# global Recent directory; per-app "recents" inside applications are not erased by this.
function Invoke-PnClearRecentItems {
    if (Test-Path $script:PN_RECENT_DIR) {
        Get-ChildItem -Path $script:PN_RECENT_DIR -File -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# === commands ===

# Kill-switch: hide and lock. NO confirm — this is panic mode (speed matters more);
# the guard against accidental runs is the explicit `now` verb. Force with open files may
# corrupt data: a deliberate trade-off (see README "Scope & limitations").
function Invoke-PnNow {
    param([string[]]$ArgList)
    $hard = $false
    foreach ($a in $ArgList) { if ($a -eq '--hard') { $hard = $true } }

    $n = 0

    # Said BEFORE the attempt, not after: panic is read in a hurry, and the one thing the user
    # must not carry away is "0 volumes locked" read as "there was nothing to lock".
    $elevated = Test-PnElevated
    if (-not $elevated) { Write-PnWarn (T 'no_admin_lock') }

    # 1. Lock unlocked BitLocker data volumes.
    foreach ($mp in (Get-PnBitLockerUnlocked)) {
        try { Invoke-PnLockBitLocker -MountPoint $mp; $n++ }
        catch { Write-PnWarn (T 'dismount_fail' $mp) }
    }

    # 2. Dismount VeraCrypt volumes (counted by mounted volumes — one single force-dismount).
    $vc = @(Get-PnVeraCryptMounted)
    if ($vc.Count -gt 0) {
        try { Invoke-PnDismountVeraCrypt; $n += $vc.Count }
        catch { Write-PnWarn (T 'dismount_fail' ($vc -join ',')) }
    }

    # 3. Clear the clipboard. 4. Lock the screen (honestly — the status as it actually happened).
    Invoke-PnClearClipboard
    $locked = Invoke-PnLockScreen

    # 5. --hard: kill cloud daemons + clear Recent items.
    if ($hard) {
        Invoke-PnKillCloudDaemons
        Invoke-PnClearRecentItems
    }

    Write-PnInfo (T 'now_report' "$n")
    # The report says how many volumes were locked; unelevated that number is zero for a reason
    # the user has to see next to it, not twenty lines above.
    if (-not $elevated) { Write-PnWarn (T 'no_admin_lock') }
    if ($locked) { Write-PnInfo (T 'lock_ok') } else { Write-PnWarn (T 'lock_fail') }
    if ($hard) { Write-PnInfo (T 'now_hard') }
}

function Invoke-PnStatus {
    Write-PnInfo (T 'status_header')

    # Unlocked encrypted volumes (BitLocker + VeraCrypt) — `panic now` would lock/dismount them.
    $vols = @(Get-PnBitLockerUnlocked) + @(Get-PnVeraCryptMounted)
    if ($vols.Count -gt 0) {
        Write-PnInfo (T 'status_vols' "$($vols.Count)")
        foreach ($v in $vols) { Write-Output "    $v" }
    } else {
        Write-PnInfo (T 'status_no_vols')
    }

    # Clipboard.
    if (Test-PnClipboardNonEmpty) {
        Write-PnInfo (T 'status_clip_has')
    } else {
        Write-PnInfo (T 'status_clip_empty')
    }

    # System-drive BitLocker — honest context.
    if (Test-PnBitLockerOn) {
        Write-PnInfo (T 'status_bl_on')
    } else {
        Write-PnWarn (T 'status_bl_off')
    }

    # Rights: the preflight exists to answer "what would `panic now` do", and without
    # administrator rights the answer for every encrypted volume is "nothing".
    if (Test-PnElevated) { Write-PnInfo (T 'status_admin_yes') }
    else { Write-PnWarn (T 'status_admin_no') }

    # Cloud daemons (--hard would kill them).
    foreach ($d in (Get-PnRunningCloudDaemons)) {
        Write-PnInfo (T 'status_cloud' $d)
    }
}

function Invoke-PnVersion { Write-Output "panic $VERSION (Windows, beta)" }

function Invoke-PnMain {
    param([string[]]$Argv)
    try {
        $cmd = if ($Argv -and $Argv.Count -ge 1) { $Argv[0] } else { '' }
        if (-not $cmd) { Write-Output (Get-PnUsage); exit 1 }
        $rest = @(if ($Argv.Count -ge 2) { $Argv[1..($Argv.Count - 1)] } else { @() })
        switch ($cmd) {
            { $_ -in 'version', '-v', '--version' } { Invoke-PnVersion }
            { $_ -in 'help', '--help', '-h' }       { Write-Output (Get-PnUsage) }
            'status' { Invoke-PnStatus }
            'now'    { Invoke-PnNow -ArgList $rest }
            # The README documents `panic hotkey` — Windows does not have it. A silent
            # "Unknown command" would read as a broken install, not as an honest boundary of
            # the port: we name the reason and a working path using the OS itself.
            'hotkey' { Write-PnErr (T 'hotkey_no_win'); exit 1 }
            default  { Write-PnErr (T 'unknown_cmd' $cmd); [Console]::Error.WriteLine((Get-PnUsage)); exit 1 }
        }
    } catch [PnExit] {
        exit $_.Exception.Code
    }
}

# Dot-source guard: under `. panic.ps1` (Pester) main does NOT run; ST_NO_MAIN=1 mutes it too.
if ($MyInvocation.InvocationName -ne '.' -and -not $env:ST_NO_MAIN) {
    Invoke-PnMain -Argv $args
}
