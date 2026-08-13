# install.ps1 — установщик ghostdraft для Windows (BETA) с проверкой целостности.
#
# Тянет ghostdraft.ps1 и SHA256SUMS из РЕЛИЗНОГО тега (не из ветки main) и сверяет SHA256
# ДО установки. Закрывает supply-chain риск «irm|iex из main без проверки»: содержимое
# релизного тега неизменно (в отличие от подвижной main), хеш ловит повреждение, частичную/
# кэш-подмену и рассинхрон с публикацией. ЧЕСТНО: сумма и скрипт приходят по одному каналу —
# от подмены САМОГО релиза это не защищает; для подлинности нужна подпись (SHA256SUMS.sig).
#
# Использование (рекомендуется verify-then-run, см. windows/README.md):
#   irm https://github.com/Di-kairos/ghostdraft/releases/latest/download/install.ps1 -OutFile install.ps1
#   irm https://github.com/Di-kairos/ghostdraft/releases/latest/download/SHA256SUMS  -OutFile SHA256SUMS
#   # сверить хеш install.ps1 вручную, прочитать скрипт, затем:
#   pwsh -File install.ps1
#
# Переменные окружения:
#   GHOSTDRAFT_VERSION     — конкретный тег (напр. 0.1.6). По умолчанию latest.
#   GHOSTDRAFT_BASE_URL    — источник целиком: http(s) URL ИЛИ локальный каталог (тесты/форки).
#   GHOSTDRAFT_INSTALL_DIR — каталог установки. По умолчанию %LOCALAPPDATA%\Programs\ghostdraft.
#   GHOSTDRAFT_SKIP_PATH   — '1' пропускает правку PATH (для тестов).
#   PT_ALLOW_HASH_ONLY     — '1' разрешает установку по одной SHA256, если подпись релиза
#                            недоступна (нет .sig ИЛИ нет ssh-keygen). ПЛОХАЯ подпись всё равно
#                            фатальна. Громкое предупреждение. Только для старых/форк-релизов.
#   GHOSTDRAFT_TEST_SIGNING_PUBKEY — ТОЛЬКО для тестов: подменяет доверенный release-pubkey.
#     Использование печатает громкое предупреждение — обычной установке эта переменная не нужна.
#   GHOSTDRAFT_SSH_KEYGEN     — путь/имя ssh-keygen (по умолчанию 'ssh-keygen'; для тестов).
#
# ВНИМАНИЕ: BETA-порт. Логика проверена через Pester (внешние эффекты мокаются);
# поведение на широком парке Windows-консолей/локалей/editor'ов не обкатано.

$ErrorActionPreference = 'Stop'

$Repo = 'Di-kairos/ghostdraft'

# Источник: явный GHOSTDRAFT_BASE_URL → конкретный тег GHOSTDRAFT_VERSION → latest-релиз.
if ($env:GHOSTDRAFT_BASE_URL) {
    $BaseUrl = $env:GHOSTDRAFT_BASE_URL
} elseif ($env:GHOSTDRAFT_VERSION) {
    $BaseUrl = "https://github.com/$Repo/releases/download/v$($env:GHOSTDRAFT_VERSION)"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/latest/download"
}

$InstallDir = if ($env:GHOSTDRAFT_INSTALL_DIR) { $env:GHOSTDRAFT_INSTALL_DIR } else {
    Join-Path $env:LOCALAPPDATA 'Programs\ghostdraft'
}
$ScriptPath = Join-Path $InstallDir 'ghostdraft.ps1'
$ShimPath   = Join-Path $InstallDir 'ghostdraft.cmd'

Write-Host 'ghostdraft (Windows, BETA) installer'
Write-Host '------------------------------------'

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
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ghostdraft-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
    $tmpScript = Join-Path $Tmp 'ghostdraft.ps1'
    $tmpSums   = Join-Path $Tmp 'SHA256SUMS'

    Write-Host 'Downloading ghostdraft.ps1 + SHA256SUMS from release...'
    Get-ReleaseFile -Name 'ghostdraft.ps1' -OutFile $tmpScript
    Get-ReleaseFile -Name 'SHA256SUMS'     -OutFile $tmpSums

    # Ожидаемый хеш для ghostdraft.ps1 из SHA256SUMS (формат: '<hash>  имя').
    $expected = $null
    foreach ($line in Get-Content -Path $tmpSums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $fname = $parts[1].Trim().TrimStart('*')
            if ($fname -eq 'ghostdraft.ps1') { $expected = $parts[0].Trim().ToLower() }
        }
    }
    if (-not $expected) {
        Write-Error 'SHA256SUMS не содержит записи для ghostdraft.ps1 — установка прервана.'
        exit 1
    }

    $actual = (Get-FileHash -Path $tmpScript -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        Write-Error "Контрольная сумма НЕ совпала (возможна подмена) — установка прервана.`nexpected: $expected`nactual:   $actual"
        exit 1
    }
    Write-Host 'Checksum OK.'

    # --- Проверка ПОДПИСИ релиза (аутентичность поверх целостности) ---
    # Релизы подписаны выделенным ed25519-ключом экосистемы (ssh-keygen -Y sign, namespace 'file').
    # Pubkey вшит ниже (тот же, что в install.sh). Fail-closed:
    #   - нет ssh-keygen ИЛИ нет .sig → отказ, если только PT_ALLOW_HASH_ONLY=1 (громкий warn);
    #   - .sig есть и НЕ сошёлся → ЖЁСТКИЙ отказ ВСЕГДА (активный признак подмены; hash-only не спасает).
    # Подмена доверенного ключа — test-only и ГРОМКАЯ: молча доверять чужому ключу значит
    # обесценить всю проверку подписи (остальные 4 тула такой переменной не имеют вовсе).
    $ReleaseSigningPubkey = if ($env:GHOSTDRAFT_TEST_SIGNING_PUBKEY) {
        Write-Warning 'GHOSTDRAFT_TEST_SIGNING_PUBKEY задан: подпись проверяется ЧУЖИМ ключом, а не ключом релизов ghostdraft. Это режим тестов — в обычной установке так быть не должно.'
        $env:GHOSTDRAFT_TEST_SIGNING_PUBKEY
    } else {
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U'
    }
    $SignPrincipal = 'releases@paranoid-tools'
    $HashOnly = ($env:PT_ALLOW_HASH_ONLY -eq '1')
    $KeygenName = if ($env:GHOSTDRAFT_SSH_KEYGEN) { $env:GHOSTDRAFT_SSH_KEYGEN } else { 'ssh-keygen' }
    $Keygen = Get-Command $KeygenName -ErrorAction SilentlyContinue

    if (-not $Keygen) {
        # ssh-keygen недоступен → подпись проверить нечем.
        if ($HashOnly) {
            Write-Warning 'ssh-keygen недоступен — подпись релиза НЕ проверена (PT_ALLOW_HASH_ONLY=1, только целостность по SHA256).'
        } else {
            Write-Error 'ssh-keygen недоступен — не могу проверить подпись релиза. Установи OpenSSH (Add-WindowsCapability OpenSSH.Client) или, для старого/неподписанного релиза, запусти с PT_ALLOW_HASH_ONLY=1 (только целостность).'
            exit 1
        }
    } else {
        $tmpSig = Join-Path $Tmp 'SHA256SUMS.sig'
        $haveSig = $false
        try {
            Get-ReleaseFile -Name 'SHA256SUMS.sig' -OutFile $tmpSig
            $haveSig = (Test-Path $tmpSig)
        } catch {
            $haveSig = $false
        }
        if (-not $haveSig) {
            # У релиза нет .sig.
            if ($HashOnly) {
                Write-Warning 'Подпись релиза (SHA256SUMS.sig) отсутствует — продолжаю (PT_ALLOW_HASH_ONLY=1, только целостность по SHA256).'
            } else {
                Write-Error 'Подпись релиза (SHA256SUMS.sig) отсутствует — установка прервана. Релизы подписаны; для старого/неподписанного релиза: PT_ALLOW_HASH_ONLY=1.'
                exit 1
            }
        } else {
            $allowedSigners = Join-Path $Tmp 'allowed_signers'
            Set-Content -LiteralPath $allowedSigners -Value ("$SignPrincipal namespaces=`"file`" $ReleaseSigningPubkey") -NoNewline
            Write-Host 'Verifying release signature...'
            # ssh-keygen -Y verify читает подписанные данные (SHA256SUMS) из stdin. Кормим ТОЧНЫЕ
            # байты файла через .NET Process (пайп PowerShell / Start-Process перекодировали бы
            # контент → 'incorrect signature'); копируем сырой поток файла в stdin.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $Keygen.Source
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
                # Плохая подпись — фатально ВСЕГДА, PT_ALLOW_HASH_ONLY не обходит.
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

# .cmd-шим, чтобы вызывать просто `ghostdraft <command>` из cmd/PowerShell.
$shim = @"
@echo off
pwsh -NoProfile -File "%~dp0ghostdraft.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
Set-Content -Path $ShimPath -Value $shim -Encoding ASCII
Write-Host "Shim created: $ShimPath"

# Добавить каталог в пользовательский PATH (idempotent). GHOSTDRAFT_SKIP_PATH=1 — пропустить.
if ($env:GHOSTDRAFT_SKIP_PATH -ne '1') {
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
Write-Host '  2) Run:  ghostdraft version'
Write-Host '  3) Try:  Get-Clipboard | ghostdraft pipe'
Write-Host ''
Write-Host 'NOTE: BETA port. For a REAL ephemeral guarantee, open a securetrash vault first —'
Write-Host 'Windows has no built-in RAM disk, so the no-vault fallback writes an on-disk temp file.'
