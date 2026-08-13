# ghostdraft.ps1 — эфемерный черновик для чувствительного текста (Paranoid Tools),
# Windows-порт (BETA). Зеркало macOS-версии (bash). Baseline: Windows PowerShell 5.1.
#
# Написать/просмотреть seed/пароль/ключ так, чтобы после закрытия следов осталось как
# можно меньше в обычных местах (editor backups, recent docs, буфер).
#
# ЧЕСТНО (легко скатиться в снейкойл — НЕ обещаем «ноль следов»):
#   - на Windows НЕТ встроенного RAM-диска (в отличие от macOS hdiutil ram://). Поэтому
#     fallback-черновик ложится во ВРЕМЕННЫЙ ФАЙЛ НА ДИСКЕ (ACL только для текущего юзера) +
#     best-effort overwrite-shred. На SSD перезапись НЕ гарантия (wear-leveling). Реальная
#     эфемерность — только внутри открытого vault securetrash (BitLocker VHDX: закрытие =
#     crypto-shred). Поэтому приоритет: GHOSTDRAFT_DIR → открытый vault → on-disk fallback.
#   - pagefile (swap) и scrollback консоли ОС может оставить — перечисляем честно.
#   - --clipboard для seed опасен (история буфера Win+V + Cloud Clipboard sync в аккаунт
#     Microsoft) — по умолчанию ВЫКЛ, с предупреждением. Авто-очистки в фоне НЕТ (на Windows
#     это ненадёжно: clipboard-cmdlet'ам нужен STA, фон-job его не даёт) — чистить вручную.
#
# BETA: логика покрыта Pester (внешние эффекты — editor/shred/clipboard — мокаются);
# поведение на реальном железе с экзотическими editor'ами/локалями широко не обкатано.

$VERSION = '0.1.18'

# --- настраиваемые примитивы (зеркало bash GHOSTDRAFT_*/ST_VAULT_VOLUME) ---
# Корень открытого vault securetrash. securetrash.ps1 монтирует VHDX на ПЕРВУЮ СВОБОДНУЮ
# букву (не фиксированную V:) и пишет её в sidecar <vault>.mount — читаем его, как это
# делает windows/paranoid.ps1. Иначе черновик с секретом молча уезжал в on-disk fallback
# при живом открытом vault (AUDIT_2026-08-03 P0-3). ST_VAULT_VOLUME переопределяет вручную.
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
                # Sidecar — подсказка, не доказательство: он мог пережить грубое отключение,
                # а букву переиспользовал посторонний том. Доверяем только при attached VHDX.
                if ($m -and (Test-GdVaultAttached -VaultPath $vaultPath)) { return $m }
            }
        } catch { }   # нечитаемый sidecar = подсказки нет; штатный fallback ниже
    }
    return 'V:\'   # legacy-дефолт: сейфы, созданные до sidecar'а
}

# Attached ли VHDX сейчас — best-effort: без Get-DiskImage (не-Windows прогон тестов)
# или при ошибке опровергнуть не можем → доверяем sidecar'у (не хуже прежней V:\-эвристики).
function Test-GdVaultAttached {
    param([string]$VaultPath)
    if (-not $VaultPath -or -not (Test-Path -LiteralPath $VaultPath)) { return $false }
    if (-not (Get-Command Get-DiskImage -ErrorAction SilentlyContinue)) { return $true }
    try { return [bool](Get-DiskImage -ImagePath $VaultPath -ErrorAction Stop).Attached } catch { return $true }
}

# --- locale: en по умолчанию; ru — если ST_LANG или системная UI-локаль начинаются с 'ru' ---
function Get-GdLocale {
    $want = $env:ST_LANG
    if ($want) {
        if ($want -match '^(?i)ru') { return 'ru' } else { return 'en' }
    }
    if ($PSUICulture -and ($PSUICulture -match '^(?i)ru')) { return 'ru' }
    return 'en'
}
$script:GD_LOCALE = if ($env:ST_LOCALE) { $env:ST_LOCALE } else { Get-GdLocale }

# --- output helpers: данные — stdout (Write-Output); предупреждения/ошибки — stderr ---
function Write-GdInfo { param([string]$Msg) Write-Output "[+] $Msg" }
function Write-GdWarn { param([string]$Msg) [Console]::Error.WriteLine("[!] $Msg") }
function Write-GdErr  { param([string]$Msg) [Console]::Error.WriteLine("[x] $Msg") }

# --- exit через исключение (Pester-safe: не убивает host-сессию) ---
class GdExit : System.Exception {
    [int]$Code
    GdExit([int]$code) : base("GdExit:$code") { $this.Code = $code }
}
function Stop-GdCommand { param([int]$Code = 1) throw [GdExit]::new($Code) }

# --- confirm: 0/false только при точном 'yes'; ST_ASSUME_YES=1 обходит (тесты/скрипты) ---
function Confirm-Gd {
    param([string]$Prompt)
    if ($env:ST_ASSUME_YES -eq '1') { return $true }
    $suffix = if ($script:GD_LOCALE -eq 'ru') { '[введите yes]' } else { '[type yes]' }
    $ans = Read-Host "$Prompt $suffix"
    return ($ans -eq 'yes')
}

# --- i18n (таблица строк ghostdraft; зеркало bash t(), Windows-адаптация мест следов) ---
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

# === pipe — прочитать stdin, напечатать в терминал, на диск НЕ писать ничего ===
# Самый безопасный режим: ничего не создаём на диске. Честно предупреждаем, что scrollback
# консоли всё равно держит текст. Печатаем raw (без лишнего перевода строки) — fidelity пайпа.
function Invoke-GdPipe {
    param([string]$Text)
    if ($null -ne $Text -and $Text.Length -gt 0) { [Console]::Out.Write($Text) }
    Write-GdWarn (T 'pipe_scrollback')
}

# === new: эфемерный черновик + shred + чистка editor-следов ===

# Том примонтирован и доступен на запись? (директория + writable). Грубо, но честно:
# не пишем в путь, который лишь выглядит как vault.
function Test-GdWritableDir {
    param([string]$Path)
    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    # Проба записи: создаём и удаляем zero-byte файл.
    $probe = Join-Path $Path (".gd-probe-" + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType File -Path $probe -Force -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

# Выбрать каталог для черновика. Возвращает @{ Dir; Kind } (kind: override|vault|fallback).
# Приоритет: GHOSTDRAFT_DIR → открытый vault (ST_VAULT_VOLUME) → on-disk secure-temp fallback.
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

# Создать temp-каталог с ACL только для текущего юзера (наследование выключено).
# Best-effort: если ACL не выставился — каталог всё равно создаётся (с предупреждением).
function New-GdSecureTempDir {
    $dir = Join-Path $env:TEMP ("ghostdraft-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $acl = Get-Acl -LiteralPath $dir
        $acl.SetAccessRuleProtection($true, $false)   # выключить наследование, снять inherited
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

# Создать файл черновика в каталоге (zero-byte, ACL наследует от защищённого каталога).
function New-GdDraftFile {
    param([string]$Dir)
    $f = Join-Path $Dir (".ghostdraft." + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType File -Path $f -Force | Out-Null
    return $f
}

# Запустить editor на файле, дождаться закрытия (мокается в тестах).
function Invoke-GdEditor {
    param([string]$Path)
    $editor = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }
    Start-Process -FilePath $editor -ArgumentList $Path -Wait -NoNewWindow
}

# Затереть и удалить файл. Предпочитаем securetrash shred (его честная логика);
# иначе fallback: overwrite случайными байтами + delete (на SSD best-effort, не гарантия).
function Invoke-GdShred {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $st = Get-Command 'securetrash' -ErrorAction SilentlyContinue
    if ($st) {
        # Значение пользователя сохраняем и возвращаем: раньше finally удалял переменную
        # целиком, так что ST_ASSUME_YES=1, выставленный вызывающим, пропадал после shred.
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

# Удалить editor-следы рядом с черновиком: vim swap/undo, nano backup. ЧЕСТНО: ~/.viminfo,
# pagefile и scrollback выборочно вычистить НЕ можем (см. new_residue).
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

# Положить черновик в системный буфер с явным подтверждением (опасно). Код $false —
# буфер не тронут (вызывающий продолжает shred). На Windows фоновой авто-очистки НЕТ.
function Set-GdClipboardDraft {
    param([string]$Path)
    Write-GdWarn (T 'clip_danger')
    if (-not (Confirm-Gd (T 'clip_confirm'))) { Write-GdWarn (T 'clip_cancelled'); return $false }
    $content = Get-Content -LiteralPath $Path -Raw
    Set-Clipboard -Value $content
    Write-GdInfo (T 'clip_set')
    return $true
}

# Удалить временный каталог fallback'а целиком (после shred файла).
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
        # --yes где угодно в аргументах == ST_ASSUME_YES=1 (контракт securetrash).
        # После `--` аргументы литеральные (зеркало bash).
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
                # Весь stdin читаем целиком из консоли (redirect-safe); пусто → только warn.
                Invoke-GdPipe -Text ([Console]::In.ReadToEnd())
            }
            'new'  { Invoke-GdNew -ArgList $rest }
            default { Write-GdErr (T 'unknown_cmd' $cmd); [Console]::Error.WriteLine((Get-GdUsage)); exit 1 }
        }
    } catch [GdExit] {
        exit $_.Exception.Code
    }
}

# Dot-source guard: при `. ghostdraft.ps1` (Pester) main НЕ запускается; ST_NO_MAIN=1 тоже глушит.
if ($MyInvocation.InvocationName -ne '.' -and -not $env:ST_NO_MAIN) {
    Invoke-GdMain -Argv $args
}
