# panic.ps1 — one-step kill-switch (Paranoid Tools), Windows-порт (BETA).
# Зеркало macOS-версии (bash). Baseline: Windows PowerShell 5.1 (без PS7-only синтаксиса).
#
# Сценарий: граница / принуждение / «кто-то идёт». Одной командой `panic now` ПРЯЧЕТ и
# ЗАПИРАЕТ: запирает разблокированные BitLocker-тома, размонтирует тома VeraCrypt, чистит
# буфер обмена и блокирует экран (P/Invoke `user32!LockWorkStation`). `--hard` также
# прибивает cloud-демоны (OneDrive/Dropbox/Google Drive) и чистит Recent items.
#
# ЧЕСТНО (как и в bash-версии): panic ПРЯЧЕТ и ЗАПИРАЕТ, но НЕ уничтожает и НЕ чистит pagefile
# (для уничтожения — securetrash). Принудительное запирание/размонтирование при открытых файлах
# может повредить данные — осознанный trade-off режима паники (спрятать важнее). BitLocker-lock
# требует admin и работает только для data-томов с отключённым auto-unlock (не системный диск);
# VeraCrypt-размонтирование требует veracrypt.exe в PATH. Отсутствие механизма — не ошибка
# (best-effort, как pkill в bash). Полное ядро — в следующих паках; см. README «Scope & limitations».
#
# BETA: логика покрыта Pester (системные примитивы мокаются); поведение на реальном железе с
# экзотическими локалями/конфигурациями BitLocker/VeraCrypt широко не обкатано.

$VERSION = '0.1.15'

# --- настраиваемые примитивы (зеркало bash PANIC_*; переопределяемы для тестов) ---
# Имя процесса VeraCrypt CLI (в PATH). Cloud-демоны и каталог Recent items — ниже.
$script:PN_VERACRYPT = if ($env:PANIC_VERACRYPT) { $env:PANIC_VERACRYPT } else { 'VeraCrypt' }
# Имена процессов cloud-демонов для Stop-Process (Windows-эквиваленты bird/Dropbox/...).
$script:PN_CLOUD_DAEMONS = @('OneDrive', 'Dropbox', 'GoogleDriveFS')
# Каталог глобальных Recent items (jump-list shortcuts). Переопределяем для тестов.
$script:PN_RECENT_DIR = if ($env:PANIC_RECENT_DIR) { $env:PANIC_RECENT_DIR } else {
    Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
}

# --- locale: en по умолчанию; ru — если ST_LANG или системная UI-локаль начинаются с 'ru' ---
function Get-PnLocale {
    $want = $env:ST_LANG
    if ($want) {
        if ($want -match '^(?i)ru') { return 'ru' } else { return 'en' }
    }
    if ($PSUICulture -and ($PSUICulture -match '^(?i)ru')) { return 'ru' }
    return 'en'
}
$script:PN_LOCALE = if ($env:ST_LOCALE) { $env:ST_LOCALE } else { Get-PnLocale }

# --- output helpers: данные/отчёты — Write-Output (stdout); предупреждения/ошибки — stderr ---
function Write-PnInfo { param([string]$Msg) Write-Output "[+] $Msg" }
function Write-PnWarn { param([string]$Msg) [Console]::Error.WriteLine("[!] $Msg") }
function Write-PnErr  { param([string]$Msg) [Console]::Error.WriteLine("[x] $Msg") }

# --- exit через исключение (Pester-safe: не убивает host-сессию) ---
class PnExit : System.Exception {
    [int]$Code
    PnExit([int]$code) : base("PnExit:$code") { $this.Code = $code }
}
function Stop-PnCommand { param([int]$Code = 1) throw [PnExit]::new($Code) }

# --- i18n (таблица строк panic; зеркало bash t()) ---
function T {
    param([string]$Key, [string]$A)
    $loc = $script:PN_LOCALE
    switch ("${loc}:${Key}") {
        'en:unknown_cmd'      { return "Unknown command: $A" }
        'ru:unknown_cmd'      { return "Неизвестная команда: $A" }
        'en:hotkey_no_win'    { return "hotkey is macOS-only: it is bound through skhd, which has no Windows counterpart, and panic will not leave a background process resident just to watch the keyboard. Windows binds hotkeys on the shortcut itself: create a shortcut to panic.cmd (Start menu or Desktop), open Properties, put the cursor in 'Shortcut key' and press Ctrl+Alt+P. Windows then runs it from anywhere. Nothing here is installed or removed on your behalf." }
        'ru:hotkey_no_win'    { return "hotkey — только для macOS: там он вешается через skhd, аналога которому в Windows нет, а держать фоновый процесс ради слежения за клавиатурой panic не станет. В Windows горячая клавиша живёт на самом ярлыке: сделай ярлык на panic.cmd (меню «Пуск» или рабочий стол), открой «Свойства», поставь курсор в поле «Быстрый вызов» и нажми Ctrl+Alt+P. Дальше Windows запускает его откуда угодно. Ничего за тебя тут не ставится и не удаляется." }
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

# === системные примитивы (обёртки — мокаются в Pester; на железе best-effort) ===

# Разблокированные BitLocker data-тома, которые можно запереть (не системный диск,
# защита включена, статус Unlocked). Пусто, если модуль/доступа нет (best-effort).
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

# Запереть BitLocker-том (force-dismount закрывает открытые хэндлы). Бросает при провале.
function Invoke-PnLockBitLocker {
    param([string]$MountPoint)
    Lock-BitLocker -MountPoint $MountPoint -ForceDismount -ErrorAction Stop | Out-Null
}

# Смонтированные тома VeraCrypt (буквы дисков). Пусто, если veracrypt.exe нет в PATH.
# Парсим `VeraCrypt /l`: строки вида "1: \Device\... F: ...". Берём букву диска (3-е поле).
function Get-PnVeraCryptMounted {
    $exe = Get-Command $script:PN_VERACRYPT -ErrorAction SilentlyContinue
    if (-not $exe) { return @() }
    $out = & $script:PN_VERACRYPT '/l' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return @() }
    return @($out | ForEach-Object {
        if ($_ -match '\b([A-Za-z]):') { $matches[1] + ':' }
    } | Where-Object { $_ })
}

# Размонтировать ВСЕ тома VeraCrypt (force, quiet). Бросает при провале.
function Invoke-PnDismountVeraCrypt {
    & $script:PN_VERACRYPT '/q' '/d' '/f' 2>$null
    if ($LASTEXITCODE -ne 0) { throw "VeraCrypt dismount exit $LASTEXITCODE" }
}

# Очистить буфер обмена (зеркало `pbcopy </dev/null`).
function Invoke-PnClearClipboard {
    try { Set-Clipboard -Value '' -ErrorAction Stop } catch { }
}

# Буфер обмена не пуст? (для status preflight).
function Test-PnClipboardNonEmpty {
    try {
        $c = Get-Clipboard -Raw -ErrorAction Stop
        return [bool]($c -and $c.Length -gt 0)
    } catch { return $false }
}

# Заблокировать экран до экрана входа (зеркало _lock_screen). Честно возвращает статус.
# P/Invoke user32!LockWorkStation вместо `rundll32 ...,LockWorkStation`: exit-код rundll32 —
# это статус helper-процесса, а НЕ результат лока (мог вернуть 0, даже если лок не принят).
# LockWorkStation возвращает bool самого API → честный сигнал «запрос на лок принят».
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

# BitLocker включён на системном диске? (зеркало filevault_on).
function Test-PnBitLockerOn {
    try {
        $sys = Get-BitLockerVolume -ErrorAction Stop | Where-Object { $_.VolumeType -eq 'OperatingSystem' }
        return [bool]($sys -and $sys.ProtectionStatus -eq 'On')
    } catch { return $false }
}

# --hard: прибить cloud-демоны (best-effort, отсутствие процесса — не ошибка).
function Invoke-PnKillCloudDaemons {
    foreach ($name in $script:PN_CLOUD_DAEMONS) {
        try { Stop-Process -Name $name -Force -ErrorAction Stop } catch { }
    }
}

# Запущенные cloud-демоны (для status preflight).
function Get-PnRunningCloudDaemons {
    @($script:PN_CLOUD_DAEMONS | Where-Object {
        Get-Process -Name $_ -ErrorAction SilentlyContinue
    })
}

# --hard: почистить глобальные Recent items (jump-list shortcuts). ЧЕСТНО: покрывает
# глобальный каталог Recent; per-app «недавние» внутри приложений этим не стираются.
function Invoke-PnClearRecentItems {
    if (Test-Path $script:PN_RECENT_DIR) {
        Get-ChildItem -Path $script:PN_RECENT_DIR -File -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

# === команды ===

# Kill-switch: спрятать и запереть. БЕЗ confirm — это режим паники (скорость важнее);
# защита от случайного запуска — явный verb `now`. Force при открытых файлах может
# повредить данные: осознанный trade-off (см. README «Scope & limitations»).
function Invoke-PnNow {
    param([string[]]$ArgList)
    $hard = $false
    foreach ($a in $ArgList) { if ($a -eq '--hard') { $hard = $true } }

    $n = 0

    # 1. Запереть разблокированные BitLocker data-тома.
    foreach ($mp in (Get-PnBitLockerUnlocked)) {
        try { Invoke-PnLockBitLocker -MountPoint $mp; $n++ }
        catch { Write-PnWarn (T 'dismount_fail' $mp) }
    }

    # 2. Размонтировать тома VeraCrypt (по числу смонтированных — единый force-dismount).
    $vc = @(Get-PnVeraCryptMounted)
    if ($vc.Count -gt 0) {
        try { Invoke-PnDismountVeraCrypt; $n += $vc.Count }
        catch { Write-PnWarn (T 'dismount_fail' ($vc -join ',')) }
    }

    # 3. Очистить буфер. 4. Заблокировать экран (честно — статус по факту).
    Invoke-PnClearClipboard
    $locked = Invoke-PnLockScreen

    # 5. --hard: прибить cloud-демоны + почистить Recent items.
    if ($hard) {
        Invoke-PnKillCloudDaemons
        Invoke-PnClearRecentItems
    }

    Write-PnInfo (T 'now_report' "$n")
    if ($locked) { Write-PnInfo (T 'lock_ok') } else { Write-PnWarn (T 'lock_fail') }
    if ($hard) { Write-PnInfo (T 'now_hard') }
}

function Invoke-PnStatus {
    Write-PnInfo (T 'status_header')

    # Разблокированные шифр-тома (BitLocker + VeraCrypt) — `panic now` запрёт/размонтирует.
    $vols = @(Get-PnBitLockerUnlocked) + @(Get-PnVeraCryptMounted)
    if ($vols.Count -gt 0) {
        Write-PnInfo (T 'status_vols' "$($vols.Count)")
        foreach ($v in $vols) { Write-Output "    $v" }
    } else {
        Write-PnInfo (T 'status_no_vols')
    }

    # Буфер обмена.
    if (Test-PnClipboardNonEmpty) {
        Write-PnInfo (T 'status_clip_has')
    } else {
        Write-PnInfo (T 'status_clip_empty')
    }

    # BitLocker системного диска — честный контекст.
    if (Test-PnBitLockerOn) {
        Write-PnInfo (T 'status_bl_on')
    } else {
        Write-PnWarn (T 'status_bl_off')
    }

    # Cloud-демоны (--hard убьёт).
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
            # README документирует `panic hotkey` — на Windows его нет. Молчаливое
            # «Unknown command» читалось бы как поломка установки, а не как честная граница
            # порта: называем причину и рабочий путь средствами самой ОС.
            'hotkey' { Write-PnErr (T 'hotkey_no_win'); exit 1 }
            default  { Write-PnErr (T 'unknown_cmd' $cmd); [Console]::Error.WriteLine((Get-PnUsage)); exit 1 }
        }
    } catch [PnExit] {
        exit $_.Exception.Code
    }
}

# Dot-source guard: при `. panic.ps1` (Pester) main НЕ запускается; ST_NO_MAIN=1 тоже глушит.
if ($MyInvocation.InvocationName -ne '.' -and -not $env:ST_NO_MAIN) {
    Invoke-PnMain -Argv $args
}
