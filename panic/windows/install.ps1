# install.ps1 — установщик panic для Windows (BETA) с проверкой целостности.
#
# Тянет panic.ps1 и SHA256SUMS из РЕЛИЗНОГО тега (не из ветки main) и сверяет SHA256
# ДО установки. Закрывает supply-chain риск «irm|iex из main без проверки»: содержимое
# релизного тега неизменно (в отличие от подвижной main), хеш ловит повреждение, частичную/
# кэш-подмену и рассинхрон с публикацией. Поверх целостности проверяется ПОДПИСЬ релиза
# (ed25519 через `ssh-keygen -Y verify` над SHA256SUMS, зеркало install.sh) — это доказывает
# ПОДЛИННОСТЬ (кто опубликовал), а не только совпадение хеша по одному каналу.
#
# Использование (рекомендуется verify-then-run, см. windows/README.md):
#   irm https://github.com/Di-kairos/panic/releases/latest/download/install.ps1 -OutFile install.ps1
#   irm https://github.com/Di-kairos/panic/releases/latest/download/SHA256SUMS  -OutFile SHA256SUMS
#   # сверить хеш install.ps1 вручную, прочитать скрипт, затем:
#   pwsh -File install.ps1
#
# Переменные окружения:
#   PANIC_VERSION       — конкретный тег (напр. 0.1.3). По умолчанию latest.
#   PANIC_BASE_URL      — источник целиком: http(s) URL ИЛИ локальный каталог (тесты/форки).
#   PANIC_INSTALL_DIR   — каталог установки. По умолчанию %LOCALAPPDATA%\Programs\panic.
#   PANIC_SKIP_PATH     — '1' пропускает правку PATH (для тестов).
#   PT_ALLOW_HASH_ONLY  — '1' разрешает установку ТОЛЬКО по хешу, если подпись нельзя проверить
#                         (нет ssh-keygen или нет .sig). Громкое предупреждение. По умолчанию
#                         fail-closed: без проверки подписи установка прерывается.
#
# ВНИМАНИЕ: BETA-порт. Логика проверена через Pester (системные примитивы мокаются);
# поведение на широком парке Windows-консолей/локалей/конфигов BitLocker не обкатано.

$ErrorActionPreference = 'Stop'

$Repo = 'Di-kairos/panic'

# Источник: явный PANIC_BASE_URL → конкретный тег PANIC_VERSION → latest-релиз.
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

# Скачать файл из релиза: http(s) → Invoke-RestMethod; локальный каталог → копия.
# Локальный путь поддержан, чтобы тесты гоняли проверку хеша без сети.
function Get-ReleaseFile {
    param([string]$Name, [string]$OutFile)
    if ($BaseUrl -match '^https?://') {
        Invoke-RestMethod -Uri "$BaseUrl/$Name" -OutFile $OutFile
    } else {
        Copy-Item -Path (Join-Path $BaseUrl $Name) -Destination $OutFile -Force
    }
}

# Временный каталог под загрузку; чистим в любом случае.
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("panic-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
    $tmpScript = Join-Path $Tmp 'panic.ps1'
    $tmpSums   = Join-Path $Tmp 'SHA256SUMS'

    Write-Host 'Downloading panic.ps1 + SHA256SUMS from release...'
    Get-ReleaseFile -Name 'panic.ps1'  -OutFile $tmpScript
    Get-ReleaseFile -Name 'SHA256SUMS' -OutFile $tmpSums

    # Ожидаемый хеш для panic.ps1 из SHA256SUMS (формат: '<hash>  имя').
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

    # --- Проверка ПОДПИСИ релиза (аутентичность поверх целостности) ---
    # Зеркалит install.sh: вшитый ed25519-pubkey → allowed_signers → `ssh-keygen -Y verify`
    # над SHA256SUMS. FAIL-CLOSED: нет ssh-keygen ИЛИ нет .sig → отказ, кроме PT_ALLOW_HASH_ONLY=1
    # (громкое предупреждение, ставим только по целостности). Подпись ЕСТЬ, но НЕ сошлась —
    # всегда жёсткий отказ (явный признак подмены), без обхода.
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
            # SHA256SUMS подаётся на stdin ТОЧНЫМИ байтами (аналог `< SHA256SUMS` в install.sh):
            # пайп PowerShell перекодировал бы содержимое (BOM, CRLF) и валидная подпись
            # отвалилась бы как «incorrect signature». Копируем сырой поток файла.
            # Зеркало канона securetrash/windows/install.ps1 — правишь здесь, правь во всех пяти.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $sshKeygen.Source
            $vArgs = @('-Y','verify','-f',$allowedSigners,'-I',$SignPrincipal,'-n','file','-s',$tmpSig)
            # `ArgumentList` появился только в .NET Core (PowerShell 7). Windows PowerShell 5.1 —
            # штатный шелл Windows и ровно тот, в котором выполняют однострочник из README —
            # его не имеет: обращение к нему уронило бы установку на шаге проверки подписи.
            # Там кладём строку сами. Каждый аргумент в кавычках (TEMP бывает с пробелом),
            # хвостовые обратные слэши удваиваются — иначе слэш экранирует закрывающую кавычку.
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
            # stdout/stderr вычитываем АСИНХРОННО и ДО WaitForExit: перенаправленный, но не
            # прочитанный поток упирается в буфер трубы — верификатор встаёт, а установщик
            # ждёт его вечно. Тихо висящий установщик хуже честного отказа.
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
            # Верификатор может завершиться, не дочитав stdin (кривые аргументы, чужой бинарь под
            # тем же именем). Запись в закрытую трубу — это не наша авария: вердикт всё равно
            # даёт код возврата, и пользователь должен увидеть честное «подпись не сошлась»,
            # а не необработанное исключение установщика.
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

    # Хеш верный → устанавливаем.
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    Copy-Item -Path $tmpScript -Destination $ScriptPath -Force
    Write-Host "Installed: $ScriptPath"
}
finally {
    Remove-Item -Path $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# .cmd-шим, чтобы вызывать просто `panic <command>` из cmd/PowerShell.
$shim = @"
@echo off
pwsh -NoProfile -File "%~dp0panic.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
Set-Content -Path $ShimPath -Value $shim -Encoding ASCII
Write-Host "Shim created: $ShimPath"

# Добавить каталог в пользовательский PATH (idempotent). PANIC_SKIP_PATH=1 — пропустить.
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
