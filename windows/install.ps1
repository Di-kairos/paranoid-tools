# install.ps1 — установщик securetrash для Windows (BETA) с проверкой целостности.
#
# Тянет securetrash.ps1, SHA256SUMS и SHA256SUMS.sig из РЕЛИЗНОГО тега (не из ветки
# main), сверяет SHA256 ДО установки И проверяет ed25519-подпись SHA256SUMS вшитым
# pubkey (`ssh-keygen -Y verify`, тот же ключ и та же fail-closed логика, что в
# install.sh). Закрывает supply-chain риск «irm|iex из main без проверки»: хеш ловит
# повреждение/кэш-подмену, а подпись — подмену САМОГО релиза (переписаны оба файла),
# т.к. атакующий без приватного ключа не подделает валидную .sig.
# Fail-closed: нет ssh-keygen / нет .sig / подпись не сошлась → установка прервана.
# Обход только явным $env:PT_ALLOW_HASH_ONLY='1' (остаётся только целостность SHA256).
#
# Использование (рекомендуется verify-then-run, см. windows/README.md):
#   irm https://github.com/Di-kairos/securetrash/releases/latest/download/install.ps1 -OutFile install.ps1
#   irm https://github.com/Di-kairos/securetrash/releases/latest/download/SHA256SUMS  -OutFile SHA256SUMS
#   # сверить хеш install.ps1 вручную, прочитать скрипт, затем:
#   pwsh -File install.ps1
#
# Переменные окружения:
#   ST_VERSION      — конкретный тег (напр. 0.4.0). По умолчанию latest.
#   ST_BASE_URL     — источник целиком: http(s) URL ИЛИ локальный каталог (тесты/форки).
#   ST_INSTALL_DIR  — каталог установки. По умолчанию %LOCALAPPDATA%\Programs\securetrash.
#   ST_SKIP_PATH    — '1' пропускает правку PATH (для тестов).
#   PT_ALLOW_HASH_ONLY — '1' разрешает установку без проверки подписи (только SHA256).
#                        Небезопасный обход fail-closed: аутентичность НЕ подтверждена.
#
# ВНИМАНИЕ: BETA-порт. Логика проверена через Pester, поведение
# BitLocker/VHDX/VeraCrypt на реальном железе НЕ валидировано.

$ErrorActionPreference = 'Stop'

$Repo = 'Di-kairos/securetrash'

# Источник: явный ST_BASE_URL → конкретный тег ST_VERSION → latest-релиз.
if ($env:ST_BASE_URL) {
    $BaseUrl = $env:ST_BASE_URL
} elseif ($env:ST_VERSION) {
    $BaseUrl = "https://github.com/$Repo/releases/download/v$($env:ST_VERSION)"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/latest/download"
}

$InstallDir = if ($env:ST_INSTALL_DIR) { $env:ST_INSTALL_DIR } else {
    Join-Path $env:LOCALAPPDATA 'Programs\securetrash'
}
$ScriptPath = Join-Path $InstallDir 'securetrash.ps1'
$ShimPath   = Join-Path $InstallDir 'securetrash.cmd'

Write-Host 'SecureTrash (Windows, BETA) installer'
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
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("securetrash-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
    $tmpScript = Join-Path $Tmp 'securetrash.ps1'
    $tmpSums   = Join-Path $Tmp 'SHA256SUMS'

    Write-Host "Downloading securetrash.ps1 + SHA256SUMS from release..."
    Get-ReleaseFile -Name 'securetrash.ps1' -OutFile $tmpScript
    Get-ReleaseFile -Name 'SHA256SUMS'      -OutFile $tmpSums

    # Ожидаемый хеш для securetrash.ps1 из SHA256SUMS (формат: '<hash>  имя').
    $expected = $null
    foreach ($line in Get-Content -Path $tmpSums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $fname = $parts[1].Trim().TrimStart('*')
            if ($fname -eq 'securetrash.ps1') { $expected = $parts[0].Trim().ToLower() }
        }
    }
    if (-not $expected) {
        Write-Error 'SHA256SUMS не содержит записи для securetrash.ps1 — установка прервана.'
        exit 1
    }

    $actual = (Get-FileHash -Path $tmpScript -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        Write-Error "Контрольная сумма НЕ совпала (возможна подмена) — установка прервана.`nexpected: $expected`nactual:   $actual"
        exit 1
    }
    Write-Host 'Checksum OK.'

    # --- Проверка ПОДПИСИ релиза (аутентичность поверх целостности) ---
    # Порт fail-closed логики install.sh. Релизы подписаны выделенным ed25519-ключом
    # (`ssh-keygen -Y`). Pubkey вшит ниже — ТОТ ЖЕ, что в install.sh; меняется только
    # при ротации ключа. ssh-keygen поставляется с Windows OpenSSH client.
    #   * нет ssh-keygen           → отказ (аутентичность непроверяема);
    #   * .sig отсутствует         → отказ (релизы v0.4.2+ всегда подписаны);
    #   * .sig есть, но НЕ сошёлся  → отказ (явный признак подмены).
    # Единственный обход — $env:PT_ALLOW_HASH_ONLY='1' (громкое предупреждение,
    # остаётся только целостность по SHA256; аутентичность НЕ подтверждена).
    $SigningPubkey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U'
    $SignPrincipal = 'releases@paranoid-tools'
    $hashOnly = ($env:PT_ALLOW_HASH_ONLY -eq '1')

    $sshKeygen = Get-Command ssh-keygen -CommandType Application -ErrorAction SilentlyContinue |
                 Select-Object -First 1
    if (-not $sshKeygen) {
        if ($hashOnly) {
            Write-Warning 'ssh-keygen недоступен — подпись релиза НЕ проверена (PT_ALLOW_HASH_ONLY=1, только целостность SHA256).'
        } else {
            Write-Error ('ssh-keygen (OpenSSH) недоступен — подпись релиза не проверить, установка прервана. ' +
                'Установи OpenSSH client (Settings → Optional features) или, приняв риск, задай $env:PT_ALLOW_HASH_ONLY=''1''.')
            exit 1
        }
    } else {
        $tmpSig = Join-Path $Tmp 'SHA256SUMS.sig'
        $gotSig = $false
        try {
            Get-ReleaseFile -Name 'SHA256SUMS.sig' -OutFile $tmpSig
            $gotSig = (Test-Path $tmpSig)
        } catch { $gotSig = $false }

        if (-not $gotSig) {
            if ($hashOnly) {
                Write-Warning 'Подпись релиза недоступна — продолжаю (PT_ALLOW_HASH_ONLY=1, только целостность SHA256).'
            } else {
                Write-Error ('Подпись релиза (SHA256SUMS.sig) отсутствует — установка прервана. ' +
                    'Релизы v0.4.2+ всегда подписаны. Обход (на свой риск): $env:PT_ALLOW_HASH_ONLY=''1''.')
                exit 1
            }
        } else {
            # allowed_signers: тот же формат, что и в install.sh
            # (`<principal> namespaces="file" <pubkey>`).
            $allowedSigners = Join-Path $Tmp 'allowed_signers'
            Set-Content -Path $allowedSigners -Value "$SignPrincipal namespaces=`"file`" $SigningPubkey" -Encoding ascii
            Write-Host 'Verifying release signature...'
            # SHA256SUMS подаётся на stdin ТОЧНЫМИ байтами (аналог `< SHA256SUMS` в install.sh):
            # пайп PowerShell перекодировал бы содержимое (BOM, CRLF) и валидная подпись
            # отвалилась бы как «incorrect signature». Копируем сырой поток файла.
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

# .cmd-шим, чтобы вызывать просто `securetrash <command>` из cmd/PowerShell.
$shim = @"
@echo off
pwsh -NoProfile -File "%~dp0securetrash.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
Set-Content -Path $ShimPath -Value $shim -Encoding ASCII
Write-Host "Shim created: $ShimPath"

# Добавить каталог в пользовательский PATH (idempotent). ST_SKIP_PATH=1 — пропустить.
if ($env:ST_SKIP_PATH -ne '1') {
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
Write-Host '  2) Run:  securetrash check'
Write-Host '  3) Then: securetrash setup'
Write-Host ''
Write-Host 'NOTE: BETA port. Verify behavior on a test container before trusting it with real secrets.'
