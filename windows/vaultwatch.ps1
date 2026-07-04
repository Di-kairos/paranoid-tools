# vaultwatch.ps1 — честный сторож открытого vault (Paranoid Tools), Windows-порт (BETA).
# Зеркало macOS-версии (bash). Требует PowerShell 7+ (pwsh): TTL-таск и хуки зовут pwsh.exe,
# под Windows PowerShell 5.1 не работают — старт fail-closed (см. Assert-VwPs7).
#
# Активен ТОЛЬКО пока vault примонтирован: сужает каналы утечки открытого plaintext и
# восстанавливает всё при закрытии. Стартует/гаснет из хуков securetrash vault open/close.
#
# Маппинг macOS → Windows (см. README «What maps to what»):
#   - Spotlight off (mdutil)      → исключение из Windows Search через атрибут каталога
#                                    NotContentIndexed (обратимо; на stop снимаем, если ставили мы).
#   - --ttl авто-detach (launchd) → одноразовая задача Task Scheduler (Register-ScheduledTask),
#                                    по истечении вызывает `vaultwatch _ttl_fire <mount>`.
#   - cloud-чек (pgrep+папки)     → Get-Process (OneDrive/Dropbox/GoogleDriveFS) + эвристика папок.
#   - Time Machine / снапшоты     → ЧЕСТНО: Windows не даёт чисто исключить backup из CLI. Поэтому
#                                    активного исключения НЕ делаем — РЕПОРТИМ существующие
#                                    VSS shadow copies (vssadmin), которые могли захватить plaintext.
#   - FileVault                   → BitLocker (Get-BitLockerVolume).
#
# ЧЕСТНО: vaultwatch НЕ чистит pagefile (swap) и НЕ телепортирует данные из облаков — делает
# обратимые исключения на время сессии и честно отчитывается о пределах. BETA: логика покрыта
# Pester (системные эффекты мокаются); поведение на реальном железе широко не обкатано.

$VERSION = '0.1.5'

# --- настраиваемые пути (зеркало bash VW_*/ST_HOOK_DIR; переопределяемы в тестах) ---
$script:VW_STATE_DIR = if ($env:VW_STATE_DIR) { $env:VW_STATE_DIR } else {
    Join-Path $env:USERPROFILE '.vaultwatch\sessions'
}
$script:ST_HOOK_DIR = if ($env:ST_HOOK_DIR) { $env:ST_HOOK_DIR } else {
    Join-Path $env:USERPROFILE '.securetrash\hooks'
}
$script:VW_HOOK_SIGNATURE = '# managed-by: vaultwatch'

# Известные cloud-демоны: имя процесса | метка | папки (через ';').
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

# --- exit через исключение (Pester-safe) ---
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

# --- i18n (зеркало bash t(), Windows-адаптация) ---
function T {
    param([string]$Key, [string]$A)
    switch ("$($script:VW_LOCALE):$Key") {
        'en:unknown_cmd'   { return "Unknown command: $A" }
        'ru:unknown_cmd'   { return "Unknown command: $A" }
        'en:need_ps7'      { return "vaultwatch requires PowerShell 7+ (pwsh); running under $A. TTL auto-dismount and hooks call pwsh.exe and will not fire on Windows PowerShell 5.1. Install PowerShell 7: https://aka.ms/powershell" }
        'ru:need_ps7'      { return "vaultwatch требует PowerShell 7+ (pwsh); запущен под $A. TTL-авторазмонтирование и хуки зовут pwsh.exe и НЕ сработают на Windows PowerShell 5.1. Установи PowerShell 7: https://aka.ms/powershell" }
        'en:need_mount'    { return 'this command needs a mountpoint argument.' }
        'ru:need_mount'    { return 'команде нужен аргумент — точка монтирования.' }
        'en:mount_missing' { return "mountpoint not found: $A" }
        'ru:mount_missing' { return "точка монтирования не найдена: $A" }
        'en:watching'      { return "watching $A (Windows Search excluded; backup snapshots reported, not removed)." }
        'ru:watching'      { return "слежу за $A (исключён из Windows Search; backup-снапшоты репортятся, не удаляются)." }
        'en:already_watching' { return "already watching $A — run vaultwatch stop first (a repeat start would lose the saved pre-session state)." }
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
        'ru:restore_incomplete' { return "Состояние сохранено для $A — восстановление неполное. Перемонтируй vault и запусти vaultwatch stop." }
        'en:rep_header'    { return 'vaultwatch — session report' }
        'ru:rep_header'    { return 'vaultwatch — session report' }
        'en:rep_duration'  { return "  duration:        $A" }
        'ru:rep_duration'  { return "  длительность:    $A" }
        'en:rep_search_on' { return "  Windows Search:  indexing re-enabled for $A" }
        'ru:rep_search_on' { return "  Windows Search:  индексация снова включена для $A" }
        'en:rep_search_keep' { return '  Windows Search:  was already excluded before session — left as-is' }
        'ru:rep_search_keep' { return '  Windows Search:  было исключено до сессии — оставлено как есть' }
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

start/stop are normally invoked by the securetrash vault open/close hooks.
'@
}

# === системные примитивы (обёртки — мокаются в Pester) ===

# Состояние индексации каталога: 'enabled' (индексируется) | 'disabled' (NotContentIndexed) | 'unknown'.
function Get-VwSearchState {
    param([string]$Path)
    try {
        $attrs = (Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Attributes
        if ($attrs -band [System.IO.FileAttributes]::NotContentIndexed) { return 'disabled' }
        return 'enabled'
    } catch { return 'unknown' }
}

# Исключить каталог из Windows Search (выставить NotContentIndexed). Best-effort.
function Disable-VwSearchIndex {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::NotContentIndexed
    } catch { }
}

# Вернуть индексацию каталога (снять NotContentIndexed). Возвращает $true при успехе.
function Enable-VwSearchIndex {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $item.Attributes = $item.Attributes -band (-bnot [System.IO.FileAttributes]::NotContentIndexed)
        return $true
    } catch { return $false }
}

# Число существующих VSS shadow copies (честный аналог tmutil listlocalsnapshots). Best-effort.
function Get-VwShadowCount {
    try {
        $out = & vssadmin list shadows 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $out) { return 0 }
        return @($out | Where-Object { $_ -match 'Shadow Copy ID' }).Count
    } catch { return 0 }
}

# Cloud-детект: вернуть массив @{ Sev='ok'|'warn'; Text=... } по активным демонам.
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

# Зарегистрировать одноразовую задачу авто-выхода. Возвращает label (или '' при провале).
function Register-VwTtlTask {
    param([string]$Mount, [int]$Seconds, [string]$Self)
    $label = 'vaultwatch-ttl-' + (($Mount -replace '[^a-zA-Z0-9]', '_'))
    try {
        $arg = "-NoProfile -File `"$Self`" _ttl_fire `"$Mount`""
        $action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument $arg
        $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds($Seconds))
        Register-ScheduledTask -TaskName $label -Action $action -Trigger $trigger -Force -ErrorAction Stop | Out-Null
        return $label
    } catch {
        Write-VwWarn (T 'ttl_sched_fail')
        return ''
    }
}

# Снять задачу авто-выхода (идемпотентно).
function Unregister-VwTtlTask {
    param([string]$Label)
    if (-not $Label) { return }
    try { Unregister-ScheduledTask -TaskName $Label -Confirm:$false -ErrorAction Stop } catch { }
}

# --- unmount-guard: авто-restore Search-exclusion, если том исчезает мимо `vaultwatch stop` ---
# Зачем: eject VHDX через Explorer (или detach в обход securetrash post-close hook) оставляет
# NotContentIndexed висеть бессрочно. macOS ловит это событийно (launchd WatchPaths). На Windows
# надёжного и проверяемого события removal для VHDX нет, поэтому guard — ПОЛЛИНГ: повторяющаяся
# задача Task Scheduler раз в минуту зовёт `vaultwatch _guard_fire <mount>`. Тот восстанавливает
# ТОЛЬКО если том реально исчез (иначе no-op). Отличие от macOS: латентность до ~1 минуты (честно
# задокументировано в README). Требует PS7 (как и весь тул, см. Assert-VwPs7).
function Get-VwGuardLabel {
    param([string]$Mount)
    return 'vaultwatch-guard-' + (($Mount -replace '[^a-zA-Z0-9]', '_'))
}

# Зарегистрировать поллинг-guard. Возвращает label (или '' при провале). Системный адаптер
# (New-ScheduledTask*/Register-ScheduledTask) — как Register-VwTtlTask, логика покрыта на _guard_fire.
function Register-VwGuardTask {
    param([string]$Mount, [string]$Self)
    $label = Get-VwGuardLabel -Mount $Mount
    try {
        $arg = "-NoProfile -File `"$Self`" _guard_fire `"$Mount`""
        $action  = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument $arg
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                     -RepetitionInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $label -Action $action -Trigger $trigger -Force -ErrorAction Stop | Out-Null
        return $label
    } catch {
        Write-VwWarn (T 'guard_sched_fail')
        return ''
    }
}

# Снять guard-задачу по mount (идемпотентно, race-safe: label выводится из mount, не из state).
function Unregister-VwGuardTask {
    param([string]$Mount)
    if (-not $Mount) { return }
    $label = Get-VwGuardLabel -Mount $Mount
    try { Unregister-ScheduledTask -TaskName $label -Confirm:$false -ErrorAction Stop } catch { }
}

# Том занят открытыми файлами? Best-effort: Get-SmbOpenFile ловит только СЕТЕВЫЕ (SMB) открытия
# файлов на этом хосте; локальные хэндлы Windows дёшево не перечислить. Потому детект positive-only:
# $true только если точно нашли открытый файл на диске тома, иначе $false. Жёсткий fail-closed для
# локальных хэндлов даёт сам Invoke-VwDismount (без -Force BitLocker откажется запирать занятый том).
# Паритет с bash `lsof` — частичный и честно ограничен (манифест > фичи).
function Test-VwMountBusy {
    param([string]$Mount)
    if ($Mount.Length -lt 2) { return $false }
    $drive = $Mount.Substring(0, 2)   # "V:" из "V:\"
    try {
        $open = @(Get-SmbOpenFile -ErrorAction Stop | Where-Object {
            $_.Path -and $_.Path.StartsWith($drive, [System.StringComparison]::OrdinalIgnoreCase)
        })
        return ($open.Count -gt 0)
    } catch {
        return $false   # детект недоступен — safety держит Invoke-VwDismount
    }
}

# Размонтировать/запереть vault. С -Force → BitLocker -ForceDismount (рвёт открытые хэндлы,
# риск data-loss — только по явному --force + подтверждению). Без -Force → обычный Lock-BitLocker:
# BitLocker сам ОТКАЖЕТСЯ запирать занятый том (fail-closed, паритет с bash `hdiutil detach` без -force).
# Возвращает $true при успехе.
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

# Том всё ещё примонтирован/доступен?
function Test-VwMounted { param([string]$Mount) return (Test-Path -LiteralPath $Mount) }

# === state helpers ===

function Get-VwStateFile {
    param([string]$Mount)
    $safe = ($Mount -replace '[^a-zA-Z0-9]', '_')
    return (Join-Path $script:VW_STATE_DIR $safe)
}

# Прочитать state-файл в hashtable (key=value построчно).
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

# Длительность ("30m"/"2h"/"45s"/"1d"/секунды) → секунды; $null при мусоре.
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

# Секунды → "Hh Mm Ss" / "Mm Ss".
function Format-VwDuration {
    param([int]$S)
    $h = [math]::Floor($S / 3600); $m = [math]::Floor(($S % 3600) / 60); $sec = $S % 60
    if ($h -gt 0) { return "${h}h ${m}m ${sec}s" } else { return "${m}m ${sec}s" }
}

function Get-VwNow { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

# Валидировать/канонизировать аргумент-точку монтирования (для start: должен существовать).
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

# === команды ===

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

    # Уже есть сессия для этого mount? Повторный start перезаписал бы сохранённое до-сессионное
    # состояние текущим (Search уже excluded) → stop не восстановит исходное (Search OFF навсегда).
    # Идемпотентно отказываемся (P2-6, паритет с bash).
    if (Test-Path -LiteralPath (Get-VwStateFile -Mount $mount)) {
        Write-VwWarn (T 'already_watching' $mount); return
    }

    # Windows Search: запомнить состояние, затем исключить каталог.
    $searchWas = Get-VwSearchState -Path $mount
    $searchSet = 0
    if ($searchWas -ne 'disabled') { Disable-VwSearchIndex -Path $mount; $searchSet = 1 }

    # Состояние сессии.
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

    # TTL авто-выход через Task Scheduler. VW_NO_SPAWN=1 подавляет (юнит-тесты state).
    if ($ttlSecs -gt 0 -and $env:VW_NO_SPAWN -ne '1') {
        $label = Register-VwTtlTask -Mount $mount -Seconds $ttlSecs -Self $Self
        $lines += "ttl_label=$label"
    }

    # unmount-guard: всегда (не только при TTL) — чтобы eject мимо stop авто-восстановил
    # Search-exclusion. VW_NO_SPAWN=1 подавляет реальную регистрацию (юнит-тесты). Паритет с bash.
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
    # На close vault уже размонтирован — каталога может не быть; не требуем существования.
    $mount = Resolve-VwMount -Raw $raw -MustExist $false
    $sf = Get-VwStateFile -Mount $mount
    if (-not (Test-Path -LiteralPath $sf)) { Write-VwWarn (T 'no_session' $mount); return }

    $st = Read-VwState -Path $sf
    $started = [int]($st['started']); if (-not $started) { $started = Get-VwNow }
    $searchWas = $st['search_was']
    $searchSet = $st['search_set']
    $ttlLabel = $st['ttl_label']

    # Снять таймер авто-выхода (закрыт вручную раньше TTL, либо вызов из _ttl_fire).
    if ($ttlLabel) { Unregister-VwTtlTask -Label $ttlLabel }
    # Снять unmount-guard безусловно по mount (race-safe: даже если guard_label не успел лечь в state).
    Unregister-VwGuardTask -Mount $mount

    # Восстановить РОВНО изменённое.
    $restoreOk = $true
    if ($searchSet -eq '1') {
        if (-not (Enable-VwSearchIndex -Path $mount)) { $restoreOk = $false }
    }

    # --- session report ---
    $dur = [int]((Get-VwNow) - $started)
    Write-Output (T 'rep_header')
    Write-Output (T 'rep_duration' (Format-VwDuration $dur))
    if ($searchSet -eq '1') { Write-Output (T 'rep_search_on' $mount) }
    else { Write-Output (T 'rep_search_keep') }
    $cloud = @(Get-VwCloudLines -Mount $mount)
    if ($cloud.Count -gt 0) {
        foreach ($c in $cloud) { Write-Output "  cloud daemons:   $($c.Text)" }
    } else { Write-Output (T 'rep_cloud_none') }
    $nsnap = Get-VwShadowCount
    if ($nsnap -gt 0) { Write-Output (T 'rep_snap_some' "$nsnap") } else { Write-Output (T 'rep_snap_none') }
    Write-Output (T 'rep_swap')

    if ($restoreOk) { Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue }
    else { Write-VwWarn (T 'restore_incomplete' $mount) }
}

# Внутренняя команда: срабатывает по истечении --ttl (из задачи Task Scheduler).
function Invoke-VwTtlFire {
    param([string[]]$ArgList)
    $raw = [string]$ArgList[0]; if (-not $raw) { return }
    $mount = Resolve-VwMount -Raw $raw -MustExist $false
    $sf = Get-VwStateFile -Mount $mount
    if (-not (Test-Path -LiteralPath $sf)) { return }   # сессии нет (закрыт вручную) — тихо

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

    if (Test-VwMounted -Mount $mount) {
        Write-VwWarn (T 'ttl_detach_fail' $mount); Stop-VwCommand 1
    }
    Invoke-VwStop -ArgList @($mount)
}

# Внутренняя команда: срабатывает по поллинг-задаче guard'а. Восстанавливает исключение ТОЛЬКО
# если том реально исчез (eject мимо stop); пока том на месте — no-op (зеркало bash cmd_guard_fire).
function Invoke-VwGuardFire {
    param([string[]]$ArgList)
    $raw = [string]$ArgList[0]; if (-not $raw) { return }
    $mount = Resolve-VwMount -Raw $raw -MustExist $false
    if (Test-VwMounted -Mount $mount) { return }   # том на месте → поллинг дёрнулся зря, no-op
    Invoke-VwStop -ArgList @($mount)                # том исчез → restore + чистка сессии (+ снятие guard)
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

# Требуем PowerShell 7+: TTL-таск (Register-ScheduledTask -Execute pwsh.exe) и .cmd-хуки зовут
# pwsh.exe. Под Windows PowerShell 5.1 они молча не стартуют → auto-dismount и Search-exclusion не
# срабатывают без единой ошибки. Fail-closed с ясным сообщением (P2-8).
function Assert-VwPs7 {
    param([version]$Version = $PSVersionTable.PSVersion)
    if ($Version.Major -lt 7) {
        Write-VwErr (T 'need_ps7' ([string]$Version))
        Stop-VwCommand 1
    }
}

function Invoke-VwMain {
    param([string[]]$Argv)
    try {
        Assert-VwPs7
        $self = $PSCommandPath
        $cmd = if ($Argv -and $Argv.Count -ge 1) { $Argv[0] } else { '' }
        if (-not $cmd) { Write-Output (Get-VwUsage); exit 1 }
        $rest = @(if ($Argv.Count -ge 2) { $Argv[1..($Argv.Count - 1)] } else { @() })
        switch ($cmd) {
            { $_ -in 'version', '-v', '--version' } { Invoke-VwVersion }
            { $_ -in 'help', '--help', '-h' }       { Write-Output (Get-VwUsage) }
            'install-hooks'   { Invoke-VwInstallHooks -Self $self }
            'uninstall-hooks' { Invoke-VwUninstallHooks }
            'status'          { Invoke-VwStatus }
            'start'           { Invoke-VwStart -ArgList $rest -Self $self }
            'stop'            { Invoke-VwStop -ArgList $rest }
            '_ttl_fire'       { Invoke-VwTtlFire -ArgList $rest }
            '_guard_fire'     { Invoke-VwGuardFire -ArgList $rest }
            default { Write-VwErr (T 'unknown_cmd' $cmd); [Console]::Error.WriteLine((Get-VwUsage)); exit 1 }
        }
    } catch [VwExit] {
        exit $_.Exception.Code
    }
}

# Dot-source guard: при `. vaultwatch.ps1` (Pester) main НЕ запускается; ST_NO_MAIN=1 тоже глушит.
if ($MyInvocation.InvocationName -ne '.' -and -not $env:ST_NO_MAIN) {
    Invoke-VwMain -Argv $args
}
