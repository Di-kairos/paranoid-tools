# vaultwatch.ps1 — an honest guard for an open vault (Paranoid Tools), Windows port (BETA).
# Mirror of the macOS version (bash). Requires PowerShell 7+ (pwsh): the TTL task and hooks
# call pwsh.exe and do not work under Windows PowerShell 5.1 — startup is fail-closed (see Assert-VwPs7).
#
# Active ONLY while the vault is mounted: narrows the leak channels for open plaintext and
# restores everything on close. Started/stopped by the securetrash vault open/close hooks.
#
# macOS → Windows mapping (see README "What maps to what"):
#   - Spotlight off (mdutil)      → exclusion from Windows Search via the directory attribute
#                                    NotContentIndexed (reversible; removed on stop if we set it).
#   - --ttl auto-detach (launchd) → a one-shot Task Scheduler task (Register-ScheduledTask),
#                                    on expiry it calls `vaultwatch _ttl_fire <mount>`.
#   - cloud check (pgrep+folders) → Get-Process (OneDrive/Dropbox/GoogleDriveFS) + folder heuristic.
#   - Time Machine / snapshots    → HONEST: Windows offers no clean CLI way to exclude a backup. So
#                                    we make NO active exclusion — we REPORT existing
#                                    VSS shadow copies (vssadmin) that may have captured plaintext.
#   - FileVault                   → BitLocker (Get-BitLockerVolume).
#
# HONEST: vaultwatch does NOT wipe the pagefile (swap) and does NOT teleport data out of clouds —
# it makes reversible exclusions for the duration of the session and honestly reports its limits.
# BETA: the logic is covered by Pester (system effects are mocked); behavior on real hardware has
# not been widely field-tested.

$VERSION = '0.1.15'

# --- configurable paths (mirror of bash VW_*/ST_HOOK_DIR; overridable in tests) ---
$script:VW_STATE_DIR = if ($env:VW_STATE_DIR) { $env:VW_STATE_DIR } else {
    Join-Path $env:USERPROFILE '.vaultwatch\sessions'
}
$script:ST_HOOK_DIR = if ($env:ST_HOOK_DIR) { $env:ST_HOOK_DIR } else {
    Join-Path $env:USERPROFILE '.securetrash\hooks'
}
$script:VW_HOOK_SIGNATURE = '# managed-by: vaultwatch'

# Known cloud daemons: process name | label | folders (';'-separated).
$script:VW_CLOUD_TABLE = @(
    @{ Proc = 'OneDrive';      Label = 'OneDrive';      Folders = @($env:OneDrive, (Join-Path $env:USERPROFILE 'OneDrive')) }
    @{ Proc = 'Dropbox';       Label = 'Dropbox';       Folders = @((Join-Path $env:USERPROFILE 'Dropbox')) }
    @{ Proc = 'GoogleDriveFS'; Label = 'Google Drive';  Folders = @((Join-Path $env:USERPROFILE 'Google Drive')) }
)

# --- locale ---
function Get-VwLocale {
    $want = $env:ST_LANG
    if ($want) { if ($want -match '^(?i)ru') { return 'ru' } else { return 'en' } }
    if ($PSUICulture -and ($PSUICulture -match '^(?i)ru')) { return 'ru' }
    return 'en'
}
$script:VW_LOCALE = if ($env:ST_LOCALE) { $env:ST_LOCALE } else { Get-VwLocale }

# --- output helpers ---
function Write-VwInfo { param([string]$Msg) Write-Output "[+] $Msg" }
function Write-VwWarn { param([string]$Msg) [Console]::Error.WriteLine("[!] $Msg") }
function Write-VwErr  { param([string]$Msg) [Console]::Error.WriteLine("[x] $Msg") }

# --- exit via an exception (Pester-safe) ---
class VwExit : System.Exception {
    [int]$Code
    VwExit([int]$code) : base("VwExit:$code") { $this.Code = $code }
}
function Stop-VwCommand { param([int]$Code = 1) throw [VwExit]::new($Code) }

# --- confirm ---
function Confirm-Vw {
    param([string]$Prompt)
    if ($env:ST_ASSUME_YES -eq '1') { return $true }
    $suffix = if ($script:VW_LOCALE -eq 'ru') { '[введите yes]' } else { '[type yes]' }
    return ((Read-Host "$Prompt $suffix") -eq 'yes')
}

# --- i18n (mirror of bash t(), Windows adaptation) ---
function T {
    param([string]$Key, [string]$A)
    switch ("$($script:VW_LOCALE):$Key") {
        'en:unknown_cmd'   { return "Unknown command: $A" }
        'ru:unknown_cmd'   { return "Неизвестная команда: $A" }
        'en:need_ps7'      { return "vaultwatch requires PowerShell 7+ (pwsh); running under $A. TTL auto-dismount and hooks call pwsh.exe and will not fire on Windows PowerShell 5.1. Install PowerShell 7: https://aka.ms/powershell" }
        'ru:need_ps7'      { return "vaultwatch требует PowerShell 7+ (pwsh); запущен под $A. TTL-авторазмонтирование и хуки зовут pwsh.exe и НЕ сработают на Windows PowerShell 5.1. Установи PowerShell 7: https://aka.ms/powershell" }
        'en:need_admin'    { return 'vaultwatch start needs an administrator console. The TTL auto-dismount calls Lock-BitLocker and the scheduled tasks register at the highest run level - both are administrator-only, and without rights the guard would register and then silently never fire. Nothing was started. Open PowerShell as administrator and try again.' }
        'ru:need_admin'    { return 'vaultwatch start требует консоли администратора. TTL-авторазмонтирование зовёт Lock-BitLocker, а задачи регистрируются с наивысшими правами — и то и другое доступно только администратору, а без прав сторож зарегистрировался бы и молча никогда не сработал. Ничего не запущено. Открой PowerShell от имени администратора и повтори.' }
        'en:need_mount'    { return 'this command needs a mountpoint argument.' }
        'ru:need_mount'    { return 'команде нужен аргумент — точка монтирования.' }
        'en:mount_missing' { return "mountpoint not found: $A" }
        'ru:mount_missing' { return "точка монтирования не найдена: $A" }
        'en:watching'      { return "watching $A (Windows Search excluded; backup snapshots reported, not removed)." }
        'ru:watching'      { return "слежу за $A (исключён из Windows Search; backup-снапшоты репортятся, не удаляются)." }
        'en:already_watching' { return "already watching $A — run vaultwatch stop first (a repeat start would lose the saved pre-session state)." }
        'en:restore_finished' { return "indexing restored for $A — the previous session could not do it (the volume was already gone) and kept the debt until now." }
        'ru:restore_finished' { return "индексация восстановлена для $A — прошлая сессия не смогла (том уже был отмонтирован) и держала долг до сих пор." }
        'ru:already_watching' { return "уже слежу за $A — сначала vaultwatch stop (повторный start потерял бы сохранённое до-сессионное состояние)." }
        'en:cloud_outside' { return "$A active — vault is OUTSIDE its sync folder" }
        'ru:cloud_outside' { return "$A активен — vault ВНЕ его синк-папки" }
        'en:cloud_inside'  { return "$A active — vault is INSIDE its sync folder (!)" }
        'ru:cloud_inside'  { return "$A активен — vault ВНУТРИ его синк-папки (!)" }
        'en:no_session'    { return "no active vaultwatch session for $A (nothing to restore)." }
        'ru:no_session'    { return "нет активной сессии vaultwatch для $A (нечего восстанавливать)." }
        'en:ttl_bad'       { return "bad --ttl duration: $A (use 30m, 2h, 45s, 1d or bare seconds)." }
        'ru:ttl_bad'       { return "неверная длительность --ttl: $A (формат: 30m, 2h, 45s, 1d или секунды)." }
        'en:ttl_scheduled' { return "auto-exit scheduled in $A." }
        'ru:ttl_scheduled' { return "авто-выход запланирован через $A." }
        'en:ttl_sched_fail'{ return 'TTL: scheduled task registration failed — auto-exit will NOT fire.' }
        'ru:ttl_sched_fail'{ return 'TTL: не удалось зарегистрировать задачу — авто-выход НЕ сработает.' }
        'en:guard_sched_fail'{ return 'unmount-guard: scheduled task registration failed — eject past stop will NOT auto-restore.' }
        'ru:guard_sched_fail'{ return 'unmount-guard: не удалось зарегистрировать задачу — eject мимо stop НЕ восстановит исключение.' }
        'en:ttl_busy'      { return "TTL expired but $A has open files — NOT dismounted (use --force to override)." }
        'ru:ttl_busy'      { return "TTL истёк, но в $A открыты файлы — НЕ размонтирую (--force чтобы форсировать)." }
        'en:ttl_force_confirm' { return "force-dismount $A with open files? data corruption risk" }
        'ru:ttl_force_confirm' { return "форсировать dismount $A при открытых файлах? риск повредить данные" }
        'en:ttl_detach_fail' { return "TTL: dismount $A failed — vault may still be open. Session state kept." }
        'ru:ttl_detach_fail' { return "TTL: dismount $A не удался — vault может быть открыт. Состояние сохранено." }
        'en:restore_incomplete' { return "Session state kept for $A — restore incomplete. Re-mount vault and run vaultwatch stop." }
        'en:restore_search_fail' { return "could not bring indexing back for $A — the debt is carried into this session and will be settled when it stops." }
        'ru:restore_search_fail' { return "не удалось вернуть индексацию для $A — долг перенесён в эту сессию и будет погашен при её остановке." }
        'ru:restore_incomplete' { return "Состояние сохранено для $A — восстановление неполное. Перемонтируй vault и запусти vaultwatch stop." }
        'en:rep_header'    { return 'vaultwatch — session report' }
        'ru:rep_header'    { return 'vaultwatch — session report' }
        'en:rep_duration'  { return "  duration:        $A" }
        'ru:rep_duration'  { return "  длительность:    $A" }
        'en:rep_search_on' { return "  Windows Search:  indexing re-enabled for $A" }
        'ru:rep_search_on' { return "  Windows Search:  индексация снова включена для $A" }
        'en:rep_search_keep' { return '  Windows Search:  was already excluded before session — left as-is' }
        'ru:rep_search_keep' { return '  Windows Search:  было исключено до сессии — оставлено как есть' }
        'en:rep_search_na' { return '  Windows Search:  NOT re-enabled yet — the volume is not mounted. NotContentIndexed lives on the volume itself, so the session is kept: open the vault again (or mount it and run "vaultwatch stop") and indexing comes back.' }
        'ru:rep_search_na' { return '  Windows Search:  ПОКА не включена обратно — том не смонтирован. NotContentIndexed живёт на самом томе, поэтому сессия сохранена: открой сейф снова (или смонтируй том и выполни "vaultwatch stop") — индексация вернётся.' }
        'en:rep_cloud_none' { return '  cloud daemons:   none active' }
        'ru:rep_cloud_none' { return '  cloud daemons:   активных нет' }
        'en:rep_snap_none' { return '  VSS shadows:     none observed (vssadmin list shadows)' }
        'ru:rep_snap_none' { return '  VSS shadows:     не обнаружено (vssadmin list shadows)' }
        'en:rep_snap_some' { return "  VSS shadows:     $A present — vaultwatch does NOT delete them (see limitations)" }
        'ru:rep_snap_some' { return "  VSS shadows:     есть ($A) — vaultwatch их НЕ удаляет (см. limitations)" }
        'en:rep_swap'      { return '  pagefile (swap): NOT addressed (see limitations)' }
        'ru:rep_swap'      { return '  pagefile (swap): не затрагивается (см. limitations)' }
        'en:status_no_sessions' { return 'vaultwatch: no active sessions.' }
        'ru:status_no_sessions' { return 'vaultwatch: нет активных сессий.' }
        'en:status_session' { return "session: $A" }
        'ru:status_session' { return "сессия: $A" }
        'en:status_search' { return "  Windows Search: was $A before session — currently EXCLUDED" }
        'ru:status_search' { return "  Windows Search: был $A до сессии — сейчас ИСКЛЮЧЁН" }
        'en:status_ttl'    { return "  TTL:            auto-exit in $A" }
        'ru:status_ttl'    { return "  TTL:            авто-выход через $A" }
        'en:hooks_installed' { return "Hooks installed in $A (post-open, post-close)." }
        'ru:hooks_installed' { return "Хуки установлены в $A (post-open, post-close)." }
        'en:hook_skip_foreign' { return "Skipped ${A}: exists and is not managed by vaultwatch (left untouched)." }
        'ru:hook_skip_foreign' { return "Пропуск ${A}: существует и не управляется vaultwatch (не трогаю)." }
        'en:hooks_removed' { return "Removed managed hooks from $A." }
        'ru:hooks_removed' { return "Удалены managed-хуки из $A." }
        'en:hook_skip_rm'  { return "Skipped ${A}: not managed by vaultwatch." }
        'ru:hook_skip_rm'  { return "Пропуск ${A}: не управляется vaultwatch." }
        default            { return $Key }
    }
}

function Get-VwUsage {
    if ($script:VW_LOCALE -eq 'ru') {
        return @'
Usage: vaultwatch <command> [args]

Commands:
  start [--ttl D] [--force] <mount>
                      Сторожить открытый vault (Windows Search off, cloud-чек, VSS-репорт).
                      --ttl D  авто-dismount через D (напр. 30m, 2h, 45s); --force
                      форсирует dismount при открытых файлах (риск потери данных).
  status              Показать активные сессии (только чтение)
  stop <mount>        Восстановить всё и показать session report
  install-hooks       Подключить vaultwatch к securetrash vault open/close
  uninstall-hooks     Удалить хуки vaultwatch (только свои, managed)
  version             Показать версию

start/stop обычно вызываются хуками securetrash vault open/close.
'@
    }
    return @'
Usage: vaultwatch <command> [args]

Commands:
  start [--ttl D] [--force] <mount>
                      Guard an open vault (Windows Search off, cloud check, VSS report).
                      --ttl D  auto-dismount after D (e.g. 30m, 2h, 45s); --force
                      allows dismount even with open files (risk of data loss).
  status              Show active sessions (read-only)
  stop <mount>        Restore everything and print a session report
  install-hooks       Wire vaultwatch into securetrash vault open/close
  uninstall-hooks     Remove vaultwatch hooks (only those it manages)
  version             Show the version

Flags:
  --yes               Skip confirmation prompts (same as ST_ASSUME_YES=1)

start/stop are normally invoked by the securetrash vault open/close hooks.
'@
}

# === system primitives (wrappers — mocked in Pester) ===

# Directory indexing state: 'enabled' (indexed) | 'disabled' (NotContentIndexed) | 'unknown'.
function Get-VwSearchState {
    param([string]$Path)
    try {
        $attrs = (Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Attributes
        if ($attrs -band [System.IO.FileAttributes]::NotContentIndexed) { return 'disabled' }
        return 'enabled'
    } catch { return 'unknown' }
}

# Exclude a directory from Windows Search (set NotContentIndexed). Best-effort.
function Disable-VwSearchIndex {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::NotContentIndexed
    } catch { }
}

# Bring back directory indexing (clear NotContentIndexed). Returns $true on success.
function Enable-VwSearchIndex {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $item.Attributes = $item.Attributes -band (-bnot [System.IO.FileAttributes]::NotContentIndexed)
        return $true
    } catch { return $false }
}

# Count of existing VSS shadow copies (honest analog of tmutil listlocalsnapshots). Best-effort.
function Get-VwShadowCount {
    try {
        $out = & vssadmin list shadows 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $out) { return 0 }
        return @($out | Where-Object { $_ -match 'Shadow Copy ID' }).Count
    } catch { return 0 }
}

# Cloud detection: return an array of @{ Sev='ok'|'warn'; Text=... } for active daemons.
function Get-VwCloudLines {
    param([string]$Mount)
    $lines = @()
    foreach ($d in $script:VW_CLOUD_TABLE) {
        if (-not (Get-Process -Name $d.Proc -ErrorAction SilentlyContinue)) { continue }
        $inside = $false
        foreach ($f in $d.Folders) {
            if (-not $f) { continue }
            try { $cf = (Resolve-Path -LiteralPath $f -ErrorAction Stop).Path } catch { continue }
            $m = $Mount.TrimEnd('\')
            $c = $cf.TrimEnd('\')
            if ($m -eq $c -or $m.StartsWith($c + '\')) { $inside = $true; break }
        }
        if ($inside) { $lines += @{ Sev = 'warn'; Text = (T 'cloud_inside' $d.Label) } }
        else         { $lines += @{ Sev = 'ok';   Text = (T 'cloud_outside' $d.Label) } }
    }
    return $lines
}

# Argument for a Windows command line: trailing backslashes before the closing quote escape
# it (CommandLineToArgvW), so a volume path like 'V:\' turned into 'V:"' and the task got a
# broken argument. Only trailing backslashes are doubled — inside the path they escape nothing.
function ConvertTo-VwArgvSafe {
    param([string]$Value)
    return ($Value -replace '(\\+)$', '$1$1')
}

# Both tasks run as THIS user, elevated. Without -RunLevel Highest the task registers happily
# and then fails at fire time: Lock-BitLocker is administrator-only, so the TTL would expire
# with the vault still open and nothing to show for it. Interactive logon (not S4U) because the
# task acts on a volume the logged-on user has mounted, and it needs that session to exist.
function New-VwTaskPrincipal {
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    return (New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest)
}

# Register the one-shot auto-exit task. Returns the label (or '' on failure).
function Register-VwTtlTask {
    param([string]$Mount, [int]$Seconds, [string]$Self)
    $label = 'vaultwatch-ttl-' + (($Mount -replace '[^a-zA-Z0-9]', '_'))
    try {
        $arg = "-NoProfile -WindowStyle Hidden -File `"$(ConvertTo-VwArgvSafe $Self)`" _ttl_fire `"$(ConvertTo-VwArgvSafe $Mount)`""
        $action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument $arg
        $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds($Seconds))
        Register-ScheduledTask -TaskName $label -Action $action -Trigger $trigger `
            -Principal (New-VwTaskPrincipal) -Force -ErrorAction Stop | Out-Null
        return $label
    } catch {
        Write-VwWarn (T 'ttl_sched_fail')
        return ''
    }
}

# Remove the auto-exit task (idempotent).
function Unregister-VwTtlTask {
    param([string]$Label)
    if (-not $Label) { return }
    try { Unregister-ScheduledTask -TaskName $Label -Confirm:$false -ErrorAction Stop } catch { }
}

# --- unmount-guard: auto-restore of the Search exclusion when the volume vanishes bypassing `vaultwatch stop` ---
# Why: ejecting a VHDX via Explorer (or a detach bypassing the securetrash post-close hook) leaves
# NotContentIndexed hanging indefinitely. macOS catches this with an event (launchd WatchPaths). On
# Windows there is no reliable, verifiable removal event for a VHDX, so the guard is POLLING: a
# repeating Task Scheduler task calls `vaultwatch _guard_fire <mount>` once a minute. That one
# restores ONLY if the volume is really gone (otherwise no-op). Difference from macOS: latency of
# up to ~1 minute (honestly documented in the README). Requires PS7 (like the whole tool, see Assert-VwPs7).
function Get-VwGuardLabel {
    param([string]$Mount)
    return 'vaultwatch-guard-' + (($Mount -replace '[^a-zA-Z0-9]', '_'))
}

# Register the polling guard. Returns the label (or '' on failure). System adapter
# (New-ScheduledTask*/Register-ScheduledTask) — like Register-VwTtlTask, logic is covered via _guard_fire.
function Register-VwGuardTask {
    param([string]$Mount, [string]$Self)
    $label = Get-VwGuardLabel -Mount $Mount
    try {
        $arg = "-NoProfile -WindowStyle Hidden -File `"$(ConvertTo-VwArgvSafe $Self)`" _guard_fire `"$(ConvertTo-VwArgvSafe $Mount)`""
        $action  = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument $arg
        # -RepetitionDuration is MANDATORY: without it -RepetitionInterval registers as a one-shot
        # (fires once immediately, while the volume is still mounted → no-op — and never repeats
        # again, the guard is silently dead). 10 years = practically indefinite polling;
        # stop/_guard_fire remove it sooner.
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                     -RepetitionInterval (New-TimeSpan -Minutes 1) `
                     -RepetitionDuration (New-TimeSpan -Days 3650)
        Register-ScheduledTask -TaskName $label -Action $action -Trigger $trigger `
            -Principal (New-VwTaskPrincipal) -Force -ErrorAction Stop | Out-Null
        return $label
    } catch {
        Write-VwWarn (T 'guard_sched_fail')
        return ''
    }
}

# Remove the guard task by mount (idempotent, race-safe: the label is derived from the mount, not from state).
function Unregister-VwGuardTask {
    param([string]$Mount)
    if (-not $Mount) { return }
    $label = Get-VwGuardLabel -Mount $Mount
    try { Unregister-ScheduledTask -TaskName $label -Confirm:$false -ErrorAction Stop } catch { }
}

# Is the volume busy with open files? Best-effort: Get-SmbOpenFile only catches NETWORK (SMB)
# file opens on this host; Windows local handles cannot be enumerated cheaply. Hence the detection
# is positive-only: $true only if we definitely found an open file on the volume's drive, else
# $false. The hard fail-closed for local handles comes from Invoke-VwDismount itself (without
# -Force BitLocker will refuse to lock a busy volume).
# Parity with bash `lsof` is partial and honestly limited (manifesto > features).
function Test-VwMountBusy {
    param([string]$Mount)
    if ($Mount.Length -lt 2) { return $false }
    $drive = $Mount.Substring(0, 2)   # "V:" out of "V:\"
    try {
        $open = @(Get-SmbOpenFile -ErrorAction Stop | Where-Object {
            $_.Path -and $_.Path.StartsWith($drive, [System.StringComparison]::OrdinalIgnoreCase)
        })
        return ($open.Count -gt 0)
    } catch {
        return $false   # detection unavailable — safety is held by Invoke-VwDismount
    }
}

# Dismount/lock the vault. With -Force → BitLocker -ForceDismount (tears open handles,
# data-loss risk — only via an explicit --force + confirmation). Without -Force → plain
# Lock-BitLocker: BitLocker itself REFUSES to lock a busy volume (fail-closed, parity with
# bash `hdiutil detach` without -force). Returns $true on success.
function Invoke-VwDismount {
    param([string]$Mount, [bool]$Force)
    try {
        if ($Force) {
            Lock-BitLocker -MountPoint $Mount -ForceDismount -ErrorAction Stop | Out-Null
        } else {
            Lock-BitLocker -MountPoint $Mount -ErrorAction Stop | Out-Null
        }
        return $true
    } catch { return $false }
}

# Mountpoints of all volumes — drive letters AND folder mount points (`C:\Vault\`).
# A wrapper for Mock. $null means "could not read the table": no CIM cmdlets
# (non-Windows test run), WMI refusal, or missing privileges — that is NOT "nothing is mounted".
function Get-VwMountPoints {
    try {
        $vols = Get-CimInstance -ClassName Win32_Volume -ErrorAction Stop
        if ($null -eq $vols) { return $null }
        return @($vols | ForEach-Object { $_.Name } | Where-Object { $_ })
    } catch { return $null }
}

# Is the volume DEFINITELY gone? We ask the volume table, not for directory existence: a vault
# mounted into a folder (`C:\Vault`) leaves the folder itself in place after an eject, and
# `Test-Path` treated such a vault as open. The cost of a mistake is maximal: the guard stayed
# silent, NotContentIndexed was NEVER cleared, and the session hung around, blocking the next
# start (mirror of bash `_vault_gone`).
#
# "Could not read" is treated as "might be open": removing protection from a volume we
# know nothing about is not allowed.
function Test-VwVaultGone {
    param([string]$Mount)
    if (-not $Mount) { return $false }
    $points = Get-VwMountPoints
    if ($null -eq $points) { return $false }
    $needle = $Mount.TrimEnd('\', '/')
    foreach ($p in $points) {
        if ($p.TrimEnd('\', '/') -ieq $needle) { return $false }
    }
    return $true
}

# === state helpers ===

function Get-VwStateFile {
    param([string]$Mount)
    $safe = ($Mount -replace '[^a-zA-Z0-9]', '_')
    return (Join-Path $script:VW_STATE_DIR $safe)
}

# Read the state file into a hashtable (key=value per line).
function Read-VwState {
    param([string]$Path)
    $h = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $h }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $kv = $line -split '=', 2
        if ($kv.Count -eq 2) { $h[$kv[0]] = $kv[1] }
    }
    return $h
}

# Duration ("30m"/"2h"/"45s"/"1d"/seconds) → seconds; $null on garbage.
function ConvertFrom-VwDuration {
    param([string]$S)
    if ($S -notmatch '^([0-9]+)([smhd]?)$') { return $null }
    $n = [int]$matches[1]; $u = $matches[2]
    switch ($u) {
        's'      { return $n }
        ''       { return $n }
        'm'      { return $n * 60 }
        'h'      { return $n * 3600 }
        'd'      { return $n * 86400 }
    }
}

# Seconds → "Hh Mm Ss" / "Mm Ss".
function Format-VwDuration {
    param([int]$S)
    $h = [math]::Floor($S / 3600); $m = [math]::Floor(($S % 3600) / 60); $sec = $S % 60
    if ($h -gt 0) { return "${h}h ${m}m ${sec}s" } else { return "${m}m ${sec}s" }
}

function Get-VwNow { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

# Validate/canonicalize the mountpoint argument (for start: it must exist).
function Resolve-VwMount {
    param([string]$Raw, [bool]$MustExist = $true)
    if (-not $Raw) { Write-VwErr (T 'need_mount'); Stop-VwCommand 1 }
    if ($MustExist -and -not (Test-Path -LiteralPath $Raw -PathType Container)) {
        Write-VwErr (T 'mount_missing' $Raw); Stop-VwCommand 1
    }
    try { return (Resolve-Path -LiteralPath $Raw -ErrorAction Stop).Path } catch { return $Raw }
}

# === hooks ===

function Write-VwHook {
    param([string]$Name, [string]$Action, [string]$Self)
    $path = Join-Path $script:ST_HOOK_DIR $Name
    if ((Test-Path -LiteralPath $path) -and -not (Select-String -LiteralPath $path -SimpleMatch $script:VW_HOOK_SIGNATURE -Quiet)) {
        Write-VwWarn (T 'hook_skip_foreign' $path)
        return
    }
    $body = @"
@echo off
$script:VW_HOOK_SIGNATURE
pwsh -NoProfile -File "$Self" $Action %*
"@
    Set-Content -LiteralPath $path -Value $body -Encoding ASCII
}

function Invoke-VwInstallHooks {
    param([string]$Self)
    New-Item -ItemType Directory -Path $script:ST_HOOK_DIR -Force | Out-Null
    Write-VwHook -Name 'post-open.cmd'  -Action 'start' -Self $Self
    Write-VwHook -Name 'post-close.cmd' -Action 'stop'  -Self $Self
    Write-VwInfo (T 'hooks_installed' $script:ST_HOOK_DIR)
}

function Invoke-VwUninstallHooks {
    $removed = $false
    foreach ($name in @('post-open.cmd', 'post-close.cmd')) {
        $path = Join-Path $script:ST_HOOK_DIR $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        if (Select-String -LiteralPath $path -SimpleMatch $script:VW_HOOK_SIGNATURE -Quiet) {
            Remove-Item -LiteralPath $path -Force; $removed = $true
        } else {
            Write-VwWarn (T 'hook_skip_rm' $path)
        }
    }
    if ($removed) { Write-VwInfo (T 'hooks_removed' $script:ST_HOOK_DIR) }
}

# === commands ===

function Invoke-VwStart {
    param([string[]]$ArgList, [string]$Self)
    $ttlSecs = 0; $ttlForce = $false; $raw = ''
    for ($i = 0; $i -lt $ArgList.Count; $i++) {
        switch ($ArgList[$i]) {
            '--ttl' {
                $i++
                $d = ConvertFrom-VwDuration ([string]$ArgList[$i])
                if ($null -eq $d) { Write-VwErr (T 'ttl_bad' ([string]$ArgList[$i])); Stop-VwCommand 1 }
                $ttlSecs = $d
            }
            '--force' { $ttlForce = $true }
            default {
                if ($ArgList[$i] -like '-*') { Write-VwErr (T 'unknown_cmd' $ArgList[$i]); Stop-VwCommand 1 }
                $raw = $ArgList[$i]
            }
        }
    }
    $mount = Resolve-VwMount -Raw $raw -MustExist $true

    # Session already exists for this mount? A repeated start would overwrite the saved
    # pre-session state with the current one (Search already excluded) → stop would not restore
    # the original (Search OFF forever). We refuse idempotently (P2-6, parity with bash).
    $carrySearchEnabled = $false
    $sfExisting = Get-VwStateFile -Mount $mount
    if (Test-Path -LiteralPath $sfExisting) {
        # Session with an unfinished restore: the previous stop could not bring indexing back
        # because the volume had already been unmounted by then (the normal path — securetrash
        # closes the vault BEFORE invoking the post-close hook). The attribute lives on the
        # volume itself and survives remounting, so the debt has been waiting for exactly this
        # moment: the volume is in front of us again. Pay it off and continue with a normal
        # start — otherwise the exclusion would remain forever and the ghost session would
        # block watching. Mirror of bash.
        $stPending = Read-VwState -Path $sfExisting
        if ($stPending['pending_restore'] -eq '1' -and -not (Test-VwVaultGone -Mount $mount)) {
            if (Enable-VwSearchIndex -Path $mount) {
                Write-VwInfo (T 'restore_finished' $mount)
            } else {
                # Could not pay it off. We do NOT lose the debt: before us, indexing was
                # ENABLED, and the new session must carry that knowledge — otherwise its stop
                # would "restore" a "was disabled" state, and NotContentIndexed would stay on
                # the volume forever, silently.
                Write-VwWarn (T 'restore_search_fail' $mount)
                $carrySearchEnabled = $true
            }
            Remove-Item -LiteralPath $sfExisting -Force -ErrorAction SilentlyContinue
        } else {
            Write-VwWarn (T 'already_watching' $mount); return
        }
    }

    # Windows Search: remember the state, then exclude the directory.
    $searchWas = Get-VwSearchState -Path $mount
    # An unpaid debt trumps what we observe now: it reads "excluded" now precisely because
    # we excluded it and could not clear it.
    if ($carrySearchEnabled) { $searchWas = 'enabled' }
    $searchSet = 0
    if ($searchWas -ne 'disabled') { Disable-VwSearchIndex -Path $mount; $searchSet = 1 }

    # Session state.
    New-Item -ItemType Directory -Path $script:VW_STATE_DIR -Force | Out-Null
    $sf = Get-VwStateFile -Mount $mount
    $lines = @(
        "mount=$mount"
        "started=$(Get-VwNow)"
        "search_was=$searchWas"
        "search_set=$searchSet"
        "ttl_secs=$ttlSecs"
        "ttl_force=$([int]$ttlForce)"
    )

    # TTL auto-exit via Task Scheduler. VW_NO_SPAWN=1 suppresses it (state unit tests).
    if ($ttlSecs -gt 0 -and $env:VW_NO_SPAWN -ne '1') {
        $label = Register-VwTtlTask -Mount $mount -Seconds $ttlSecs -Self $Self
        $lines += "ttl_label=$label"
    }

    # unmount-guard: always (not only with TTL) — so an eject bypassing stop also auto-restores
    # the Search exclusion. VW_NO_SPAWN=1 suppresses the actual registration (unit tests). Parity with bash.
    if ($env:VW_NO_SPAWN -ne '1') {
        $glabel = Register-VwGuardTask -Mount $mount -Self $Self
        if ($glabel) { $lines += "guard_label=$glabel" }
    }
    Set-Content -LiteralPath $sf -Value $lines

    Write-VwInfo (T 'watching' $mount)
    if ($ttlSecs -gt 0) { Write-VwInfo (T 'ttl_scheduled' (Format-VwDuration $ttlSecs)) }
    foreach ($c in (Get-VwCloudLines -Mount $mount)) {
        if ($c.Sev -eq 'warn') { Write-VwWarn $c.Text } else { Write-VwInfo $c.Text }
    }
}

function Invoke-VwStop {
    param([string[]]$ArgList)
    $raw = [string]$ArgList[0]
    if (-not $raw) { Write-VwErr (T 'need_mount'); Stop-VwCommand 1 }
    # On close the vault is already unmounted — the directory may be absent; existence not required.
    $mount = Resolve-VwMount -Raw $raw -MustExist $false
    $sf = Get-VwStateFile -Mount $mount
    if (-not (Test-Path -LiteralPath $sf)) {
        Unregister-VwGuardTask -Mount $mount   # remove a possible orphaned guard even without a session (LOW-2)
        Write-VwWarn (T 'no_session' $mount); return
    }

    $st = Read-VwState -Path $sf
    $started = [int]($st['started']); if (-not $started) { $started = Get-VwNow }
    $searchWas = $st['search_was']
    $searchSet = $st['search_set']
    $ttlLabel = $st['ttl_label']

    # Remove the auto-exit timer (closed manually before the TTL, or called from _ttl_fire).
    if ($ttlLabel) { Unregister-VwTtlTask -Label $ttlLabel }
    # Remove the unmount-guard unconditionally by mount (race-safe: even if guard_label never made it into state).
    Unregister-VwGuardTask -Mount $mount

    # Restore EXACTLY what was changed.
    $restoreOk = $true
    $searchNa = $false
    if ($searchSet -eq '1') {
        if (Test-VwVaultGone -Mount $mount) {
            $searchNa = $true   # nothing to re-enable — but claiming "re-enabled" is off-limits too (see report below)
            # The volume is already unmounted (e.g. Explorer eject → guard invoked stop) — there
            # is NOTHING to index, restore is N/A, and that is NOT an error (mirror of bash).
            # Otherwise a stale state file would block the next start forever: the guard is
            # already removed, yet the session "hangs" (AUDIT_2026-08-03 P0-4). A mountpoint
            # folder left behind after an eject lands here too.
        } elseif (-not (Enable-VwSearchIndex -Path $mount)) {
            # TOCTOU: the volume could vanish BETWEEN the check and Enable — recheck; gone →
            # the same N/A branch, otherwise an honest restore failure (Codex review P0-4).
            if (-not (Test-VwVaultGone -Mount $mount)) { $restoreOk = $false }
        }
    }

    # --- session report ---
    $dur = [int]((Get-VwNow) - $started)
    Write-Output (T 'rep_header')
    Write-Output (T 'rep_duration' (Format-VwDuration $dur))
    # "Re-enabled" — only if we truly re-enabled it. The attribute would survive the volume
    # being remounted, so for an unmounted volume the report says outright that indexing is still off.
    if ($searchSet -ne '1') { Write-Output (T 'rep_search_keep') }
    elseif ($searchNa) { Write-Output (T 'rep_search_na') }
    else { Write-Output (T 'rep_search_on' $mount) }
    $cloud = @(Get-VwCloudLines -Mount $mount)
    if ($cloud.Count -gt 0) {
        foreach ($c in $cloud) { Write-Output "  cloud daemons:   $($c.Text)" }
    } else { Write-Output (T 'rep_cloud_none') }
    $nsnap = Get-VwShadowCount
    if ($nsnap -gt 0) { Write-Output (T 'rep_snap_some' "$nsnap") } else { Write-Output (T 'rep_snap_none') }
    Write-Output (T 'rep_swap')

    if ($searchNa) {
        # The restore is still owed: we were the ones who set the exclusion, and it can only be
        # cleared on a mounted volume. We do NOT delete the session — otherwise the report's
        # advice is unactionable, the next start knows nothing about the debt, and the attribute
        # stays on the volume forever. We rewrite the file: the timer and the guard are already
        # removed, only the debt itself remains. Mirror of bash.
        Set-Content -LiteralPath $sf -Encoding utf8 -Value @(
            "mount=$mount"
            "started=$started"
            "search_was=enabled"
            "search_set=1"
            "pending_restore=1"
        )
    }
    elseif ($restoreOk) { Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue }
    else {
        # A non-zero exit code is mandatory: a stop that failed to restore the exclusions is
        # not a success. Otherwise the securetrash post-close hook and the scheduler would
        # consider the session closed, while the volume's indexing is still off and the
        # state file is alive (mirror of bash).
        Write-VwWarn (T 'restore_incomplete' $mount)
        Stop-VwCommand 1
    }
}

# Internal command: fires when --ttl expires (from the Task Scheduler task).
function Invoke-VwTtlFire {
    param([string[]]$ArgList)
    $raw = [string]$ArgList[0]; if (-not $raw) { return }
    $mount = Resolve-VwMount -Raw $raw -MustExist $false
    $sf = Get-VwStateFile -Mount $mount
    if (-not (Test-Path -LiteralPath $sf)) { return }   # no session (closed manually) — stay quiet

    $st = Read-VwState -Path $sf
    $ttlForce = ($st['ttl_force'] -eq '1')

    if (Test-VwMountBusy -Mount $mount) {
        if ($ttlForce -and (Confirm-Vw (T 'ttl_force_confirm' $mount))) {
            Invoke-VwDismount -Mount $mount -Force $true | Out-Null
        } else {
            Write-VwWarn (T 'ttl_busy' $mount); return
        }
    } else {
        Invoke-VwDismount -Mount $mount -Force $false | Out-Null
    }

    if (-not (Test-VwVaultGone -Mount $mount)) {
        Write-VwWarn (T 'ttl_detach_fail' $mount); Stop-VwCommand 1
    }
    Invoke-VwStop -ArgList @($mount)
}

# Internal command: fires from the guard's polling task. Restores the exclusion ONLY if the
# volume is really gone (eject bypassing stop); while the volume is in place — no-op (mirror of bash cmd_guard_fire).
function Invoke-VwGuardFire {
    param([string[]]$ArgList)
    $raw = [string]$ArgList[0]; if (-not $raw) { return }
    $mount = Resolve-VwMount -Raw $raw -MustExist $false
    if (-not (Test-VwVaultGone -Mount $mount)) { return }   # volume in place (or unknown) → no-op
    Invoke-VwStop -ArgList @($mount)                # volume gone → restore + session cleanup (+ guard removal)
}

function Invoke-VwStatus {
    $found = $false
    if (Test-Path -LiteralPath $script:VW_STATE_DIR) {
        foreach ($sf in (Get-ChildItem -LiteralPath $script:VW_STATE_DIR -File -ErrorAction SilentlyContinue)) {
            $found = $true
            $st = Read-VwState -Path $sf.FullName
            $mount = $st['mount']
            $started = [int]($st['started'])
            $searchWas = $st['search_was']
            $ttlSecs = [int]($st['ttl_secs'])
            $now = Get-VwNow
            Write-VwInfo ((T 'status_session' $mount) + " (running $(Format-VwDuration ([int]($now - $started))))")
            Write-VwInfo (T 'status_search' $searchWas)
            if ($ttlSecs -gt 0) {
                $remaining = [int]($started + $ttlSecs - $now)
                if ($remaining -gt 0) { Write-VwInfo (T 'status_ttl' (Format-VwDuration $remaining)) }
            }
        }
    }
    if (-not $found) { Write-VwInfo (T 'status_no_sessions') }
}

function Invoke-VwVersion { Write-Output "vaultwatch $VERSION (Windows, beta)" }

# Require PowerShell 7+: the TTL task (Register-ScheduledTask -Execute pwsh.exe) and the .cmd
# hooks call pwsh.exe. Under Windows PowerShell 5.1 they silently fail to start → auto-dismount
# and the Search exclusion never fire, without a single error. Fail-closed with a clear message (P2-8).
function Assert-VwPs7 {
    param([version]$Version = $PSVersionTable.PSVersion)
    if ($Version.Major -lt 7) {
        Write-VwErr (T 'need_ps7' ([string]$Version))
        Stop-VwCommand 1
    }
}

# Administrator rights in this session (wrapper for Mock).
function Test-VwElevated {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# Fail-closed on `start` only, and for the same reason as the PS7 gate: everything a session
# is FOR happens later, in a scheduled task, where a failure is invisible. Unelevated, the TTL
# task cannot Lock-BitLocker and cannot register at the highest run level - the vault would sit
# open past its timer with a session file claiming it was guarded. stop/status stay ungated:
# tearing a session down and reading it are not privileged, and refusing there would strand the
# Search exclusion on the volume.
# ST_ASSUME_ELEVATED=1 is a TEST-ONLY hook (Pester runs these paths on macOS); it grants
# nothing - without real rights the scheduler and BitLocker refuse exactly as before.
function Assert-VwElevated {
    if ($env:ST_ASSUME_ELEVATED -eq '1') { return }
    if (Test-VwElevated) { return }
    Write-VwErr (T 'need_admin')
    Stop-VwCommand 1
}

function Invoke-VwMain {
    param([string[]]$Argv)
    try {
        Assert-VwPs7
        $self = $PSCommandPath
        # --yes anywhere in the arguments == ST_ASSUME_YES=1 (securetrash contract).
        # After `--` arguments are literal: `stop -- --yes` is a mountpoint with that
        # name, not a flag (mirror of bash).
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
        if (-not $cmd) { Write-Output (Get-VwUsage); exit 1 }
        $rest = @(if ($Argv.Count -ge 2) { $Argv[1..($Argv.Count - 1)] } else { @() })
        switch ($cmd) {
            { $_ -in 'version', '-v', '--version' } { Invoke-VwVersion }
            { $_ -in 'help', '--help', '-h' }       { Write-Output (Get-VwUsage) }
            'install-hooks'   { Invoke-VwInstallHooks -Self $self }
            'uninstall-hooks' { Invoke-VwUninstallHooks }
            'status'          { Invoke-VwStatus }
            'start'           { Assert-VwElevated; Invoke-VwStart -ArgList $rest -Self $self }
            'stop'            { Invoke-VwStop -ArgList $rest }
            '_ttl_fire'       { Invoke-VwTtlFire -ArgList $rest }
            '_guard_fire'     { Invoke-VwGuardFire -ArgList $rest }
            default { Write-VwErr (T 'unknown_cmd' $cmd); [Console]::Error.WriteLine((Get-VwUsage)); exit 1 }
        }
    } catch [VwExit] {
        exit $_.Exception.Code
    }
}

# Dot-source guard: under `. vaultwatch.ps1` (Pester) main is NOT run; ST_NO_MAIN=1 silences it too.
if ($MyInvocation.InvocationName -ne '.' -and -not $env:ST_NO_MAIN) {
    Invoke-VwMain -Argv $args
}
