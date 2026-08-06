# install.ps1 — установщик seedsplit для Windows (BETA) с проверкой целостности.
#
# Тянет seedsplit.ps1 и SHA256SUMS из РЕЛИЗНОГО тега (не из ветки main) и сверяет SHA256
# ДО установки. Закрывает supply-chain риск «irm|iex из main без проверки»: содержимое
# релизного тега неизменно (в отличие от подвижной main), хеш ловит повреждение, частичную/
# кэш-подмену и рассинхрон с публикацией. Поверх целостности проверяется ПОДПИСЬ релиза
# (SHA256SUMS.sig, ed25519 через ssh-keygen -Y verify) — зеркало install.sh. FAIL-CLOSED:
# неверная/отсутствующая подпись или отсутствие ssh-keygen прерывают установку, если явно
# не выставлен PT_ALLOW_HASH_ONLY=1 (тогда — только целостность по SHA256, с предупреждением).
#
# Использование (рекомендуется verify-then-run, см. windows/README.md):
#   irm https://github.com/Di-kairos/seedsplit/releases/latest/download/install.ps1 -OutFile install.ps1
#   irm https://github.com/Di-kairos/seedsplit/releases/latest/download/SHA256SUMS  -OutFile SHA256SUMS
#   # сверить хеш install.ps1 вручную, прочитать скрипт, затем:
#   pwsh -File install.ps1
#
# Переменные окружения:
#   SEEDSPLIT_VERSION     — конкретный тег (напр. 0.3.2). По умолчанию latest.
#   SEEDSPLIT_BASE_URL    — источник целиком: http(s) URL ИЛИ локальный каталог (тесты/форки).
#   SEEDSPLIT_INSTALL_DIR — каталог установки. По умолчанию %LOCALAPPDATA%\Programs\seedsplit.
#   SEEDSPLIT_SKIP_PATH   — '1' пропускает правку PATH (для тестов).
#   PT_ALLOW_HASH_ONLY    — '1' разрешает установку без проверки подписи (только целостность):
#                           для старых/неподписанных релизов или без ssh-keygen. Неверная подпись
#                           всё равно прерывает установку — этот флаг её НЕ обходит.
#
# ВНИМАНИЕ: BETA-порт. Логика (включая KAT-кросс-совместимость долей с macOS) проверена
# через Pester; поведение на широком парке Windows-консолей/локалей не обкатано.

$ErrorActionPreference = 'Stop'

$Repo = 'Di-kairos/seedsplit'

# Источник: явный SEEDSPLIT_BASE_URL → конкретный тег SEEDSPLIT_VERSION → latest-релиз.
if ($env:SEEDSPLIT_BASE_URL) {
    $BaseUrl = $env:SEEDSPLIT_BASE_URL
} elseif ($env:SEEDSPLIT_VERSION) {
    $BaseUrl = "https://github.com/$Repo/releases/download/v$($env:SEEDSPLIT_VERSION)"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/latest/download"
}

$InstallDir = if ($env:SEEDSPLIT_INSTALL_DIR) { $env:SEEDSPLIT_INSTALL_DIR } else {
    Join-Path $env:LOCALAPPDATA 'Programs\seedsplit'
}
$ScriptPath = Join-Path $InstallDir 'seedsplit.ps1'
$ShimPath   = Join-Path $InstallDir 'seedsplit.cmd'

Write-Host 'seedsplit (Windows, BETA) installer'
Write-Host '-----------------------------------'

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
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("seedsplit-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
    $tmpScript = Join-Path $Tmp 'seedsplit.ps1'
    $tmpSums   = Join-Path $Tmp 'SHA256SUMS'

    Write-Host 'Downloading seedsplit.ps1 + SHA256SUMS from release...'
    Get-ReleaseFile -Name 'seedsplit.ps1' -OutFile $tmpScript
    Get-ReleaseFile -Name 'SHA256SUMS'    -OutFile $tmpSums

    # Ожидаемый хеш для seedsplit.ps1 из SHA256SUMS (формат: '<hash>  имя').
    $expected = $null
    foreach ($line in Get-Content -Path $tmpSums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $fname = $parts[1].Trim().TrimStart('*')
            if ($fname -eq 'seedsplit.ps1') { $expected = $parts[0].Trim().ToLower() }
        }
    }
    if (-not $expected) {
        Write-Error 'SHA256SUMS не содержит записи для seedsplit.ps1 — установка прервана.'
        exit 1
    }

    $actual = (Get-FileHash -Path $tmpScript -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        Write-Error "Контрольная сумма НЕ совпала (возможна подмена) — установка прервана.`nexpected: $expected`nactual:   $actual"
        exit 1
    }
    Write-Host 'Checksum OK.'

    # --- Проверка ПОДПИСИ релиза (аутентичность поверх целостности) ---
    # Зеркалит install.sh: релизы подписаны выделенным ed25519-ключом экосистемы
    # (`ssh-keygen -Y verify` над SHA256SUMS). Вшитый pubkey совпадает с install.sh и SECURITY.md.
    # FAIL-CLOSED: неверная подпись ВСЕГДА прерывает установку (явный признак подмены — обхода нет).
    # Отсутствие подписи ИЛИ отсутствие ssh-keygen прерывает установку, если явно не выставлен
    # PT_ALLOW_HASH_ONLY=1 — тогда остаётся только целостность по SHA256 (с громким предупреждением).
    $ReleaseSigningPubkey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U'
    $SignPrincipal = 'releases@paranoid-tools'
    $AllowHashOnly = ($env:PT_ALLOW_HASH_ONLY -eq '1')

    $sshKeygen = Get-Command 'ssh-keygen' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sshKeygen) {
        if ($AllowHashOnly) {
            Write-Warning 'ssh-keygen не найден — подпись релиза НЕ проверена, только целостность по SHA256 (PT_ALLOW_HASH_ONLY=1).'
        } else {
            Write-Error 'ssh-keygen не найден — подпись релиза проверить нечем, установка прервана. Установи OpenSSH или запусти с PT_ALLOW_HASH_ONLY=1 (только целостность).'
            exit 1
        }
    } else {
        $tmpSig  = Join-Path $Tmp 'SHA256SUMS.sig'
        $haveSig = $false
        try { Get-ReleaseFile -Name 'SHA256SUMS.sig' -OutFile $tmpSig; $haveSig = Test-Path -LiteralPath $tmpSig } catch { $haveSig = $false }
        if (-not $haveSig) {
            if ($AllowHashOnly) {
                Write-Warning 'Подпись релиза (SHA256SUMS.sig) недоступна — продолжаю только по целостности (PT_ALLOW_HASH_ONLY=1).'
            } else {
                Write-Error 'Подпись релиза (SHA256SUMS.sig) отсутствует — установка прервана. Неподписанный/старый релиз: запусти с PT_ALLOW_HASH_ONLY=1.'
                exit 1
            }
        } else {
            # Тот же принцип, что в install.sh: пишем вшитый pubkey в allowed_signers, namespace 'file'.
            $allowedSigners = Join-Path $Tmp 'allowed_signers'
            Set-Content -LiteralPath $allowedSigners -Value ('{0} namespaces="file" {1}' -f $SignPrincipal, $ReleaseSigningPubkey) -Encoding ascii -NoNewline
            Write-Host 'Verifying release signature...'
            # SHA256SUMS подаётся на stdin ТОЧНЫМИ байтами (аналог `< SHA256SUMS` в install.sh):
            # пайп PowerShell перекодировал бы содержимое (BOM, CRLF) и валидная подпись
            # отвалилась бы как «incorrect signature». Копируем сырой поток файла.
            # Зеркало канона securetrash/windows/install.ps1 — правишь здесь, правь во всех пяти.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $sshKeygen.Source
            foreach ($a in @('-Y','verify','-f',$allowedSigners,'-I',$SignPrincipal,'-n','file','-s',$tmpSig)) {
                $psi.ArgumentList.Add($a)
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
                Write-Error 'Подпись релиза НЕ прошла проверку — установка прервана (возможна подмена). Обхода нет.'
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

# .cmd-шим, чтобы вызывать просто `seedsplit <command>` из cmd/PowerShell.
$shim = @"
@echo off
pwsh -NoProfile -File "%~dp0seedsplit.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
Set-Content -Path $ShimPath -Value $shim -Encoding ASCII
Write-Host "Shim created: $ShimPath"

# Добавить каталог в пользовательский PATH (idempotent). SEEDSPLIT_SKIP_PATH=1 — пропустить.
if ($env:SEEDSPLIT_SKIP_PATH -ne '1') {
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
Write-Host '  2) Run:  seedsplit version'
Write-Host '  3) Try:  "my secret" | seedsplit split -n 3 -t 2'
Write-Host ''
Write-Host 'NOTE: BETA port. Shares are byte-compatible with the macOS build, but verify on a'
Write-Host 'throwaway secret before trusting it with a real seed phrase.'
