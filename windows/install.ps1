# install.ps1 — установщик vaultwatch для Windows (BETA) с проверкой целостности.
#
# Тянет vaultwatch.ps1 и SHA256SUMS из РЕЛИЗНОГО тега (не из ветки main) и сверяет SHA256
# ДО установки. Закрывает supply-chain риск «irm|iex из main без проверки»: содержимое
# релизного тега неизменно (в отличие от подвижной main), хеш ловит повреждение, частичную/
# кэш-подмену и рассинхрон с публикацией. ЧЕСТНО: сумма и скрипт приходят по одному каналу —
# от подмены САМОГО релиза это не защищает; для подлинности нужна подпись (SHA256SUMS.sig).
#
# Использование (рекомендуется verify-then-run, см. windows/README.md):
#   irm https://github.com/Di-kairos/vaultwatch/releases/latest/download/install.ps1 -OutFile install.ps1
#   irm https://github.com/Di-kairos/vaultwatch/releases/latest/download/SHA256SUMS  -OutFile SHA256SUMS
#   # сверить хеш install.ps1 вручную, прочитать скрипт, затем:
#   pwsh -File install.ps1
#
# Переменные окружения:
#   VAULTWATCH_VERSION     — конкретный тег (напр. 0.1.3). По умолчанию latest.
#   VAULTWATCH_BASE_URL    — источник целиком: http(s) URL ИЛИ локальный каталог (тесты/форки).
#   VAULTWATCH_INSTALL_DIR — каталог установки. По умолчанию %LOCALAPPDATA%\Programs\vaultwatch.
#   VAULTWATCH_SKIP_PATH   — '1' пропускает правку PATH (для тестов).
#   PT_ALLOW_HASH_ONLY     — '1' разрешает установку по одной целостности SHA256, когда подпись
#                            проверить нельзя (нет ssh-keygen ИЛИ у релиза нет .sig). Плохая
#                            подпись прерывает установку ВСЕГДА, обход не действует.
#
# ВНИМАНИЕ: BETA-порт. Логика проверена через Pester (системные эффекты мокаются);
# поведение на широком парке Windows-конфигов (Search/VSS/Task Scheduler) не обкатано.

$ErrorActionPreference = 'Stop'

$Repo = 'Di-kairos/vaultwatch'

if ($env:VAULTWATCH_BASE_URL) {
    $BaseUrl = $env:VAULTWATCH_BASE_URL
} elseif ($env:VAULTWATCH_VERSION) {
    $BaseUrl = "https://github.com/$Repo/releases/download/v$($env:VAULTWATCH_VERSION)"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/latest/download"
}

$InstallDir = if ($env:VAULTWATCH_INSTALL_DIR) { $env:VAULTWATCH_INSTALL_DIR } else {
    Join-Path $env:LOCALAPPDATA 'Programs\vaultwatch'
}
$ScriptPath = Join-Path $InstallDir 'vaultwatch.ps1'
$ShimPath   = Join-Path $InstallDir 'vaultwatch.cmd'

function Get-ReleaseFile {
    param([string]$Name, [string]$OutFile)
    if ($BaseUrl -match '^https?://') {
        Invoke-RestMethod -Uri "$BaseUrl/$Name" -OutFile $OutFile
    } else {
        Copy-Item -Path (Join-Path $BaseUrl $Name) -Destination $OutFile -Force
    }
}

# --- Проверка ПОДПИСИ релиза (аутентичность поверх целостности) — порт install.sh ---
# Релизы подписаны выделенным Ed25519-ключом экосистемы (ssh-keygen -Y). Pubkey вшит ниже.
# Windows поставляется с OpenSSH (ssh-keygen). FAIL-CLOSED, зеркалит install.sh:
#   - ssh-keygen недоступен ИЛИ .sig отсутствует → установка прервана, ЕСЛИ не задан
#     PT_ALLOW_HASH_ONLY=1 (тогда громкое предупреждение: проверена только целостность SHA256);
#   - .sig есть и НЕ сошёлся → жёсткий отказ БЕЗ обхода (явный признак подмены; как в install.sh).
$script:ReleaseSigningPubkey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U'
$script:SignPrincipal = 'releases@paranoid-tools'

function Get-VwVerifier {
    # Путь к ssh-keygen (или $null). Вынесено отдельной функцией ради мокабельности в Pester.
    (Get-Command ssh-keygen -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1).Source
}

function Invoke-VwVerifier {
    # Обёртка над `ssh-keygen -Y verify` — вынесена, чтобы её можно было замокать в тестах.
    # Windows OpenSSH ssh-keygen читает подписанные данные из stdin; возвращаем exit-код.
    param([string]$AllowedSigners, [string]$Principal, [string]$SigFile, [string]$SumsFile)
    # Байты SHA256SUMS передаём КАК ЕСТЬ: пайп PowerShell перекодирует текст (BOM, CRLF),
    # и валидная подпись отвалилась бы как «incorrect signature» (зеркало ghostdraft).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-VwVerifier)
    $vArgs = @('-Y','verify','-f',$AllowedSigners,'-I',$Principal,'-n','file','-s',$SigFile)
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
    $fs = [System.IO.File]::OpenRead($SumsFile)
    try { $fs.CopyTo($proc.StandardInput.BaseStream) } catch [System.IO.IOException] { } finally { $fs.Close() }
    try { $proc.StandardInput.Close() } catch [System.IO.IOException] { }
    $null = $outTask.Result
    $null = $errTask.Result
    $proc.WaitForExit()
    return $proc.ExitCode
}

function Assert-VwSignature {
    param([string]$Tmp)
    $sumsFile = Join-Path $Tmp 'SHA256SUMS'
    $sigFile  = Join-Path $Tmp 'SHA256SUMS.sig'
    $allowHashOnly = ($env:PT_ALLOW_HASH_ONLY -eq '1')

    # 1) Верификатор доступен?
    $verifier = Get-VwVerifier
    if (-not $verifier) {
        if ($allowHashOnly) {
            Write-Warning 'ssh-keygen недоступен — подпись релиза НЕ проверена (только целостность SHA256). PT_ALLOW_HASH_ONLY=1.'
            return
        }
        throw 'ssh-keygen недоступен — подпись релиза не проверить. Установи OpenSSH или (только целостность) переустанови с PT_ALLOW_HASH_ONLY=1. Установка прервана.'
    }

    # 2) Тянем .sig; его отсутствие = fail-closed (обход — PT_ALLOW_HASH_ONLY=1).
    try {
        Get-ReleaseFile -Name 'SHA256SUMS.sig' -OutFile $sigFile
    } catch {
        Remove-Item -LiteralPath $sigFile -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $sigFile)) {
        if ($allowHashOnly) {
            Write-Warning 'Подпись релиза (SHA256SUMS.sig) отсутствует — продолжаю по целостности (PT_ALLOW_HASH_ONLY=1, только для старых релизов).'
            return
        }
        throw 'Подпись релиза (SHA256SUMS.sig) отсутствует — установка прервана. Неподписанный/старый релиз: PT_ALLOW_HASH_ONLY=1 (только целостность).'
    }

    # 3) allowed_signers c ВШИТЫМ pubkey (тот же формат, что в install.sh), затем verify.
    $allowed = Join-Path $Tmp 'allowed_signers'
    Set-Content -LiteralPath $allowed -Encoding ASCII `
        -Value ('{0} namespaces="file" {1}' -f $script:SignPrincipal, $script:ReleaseSigningPubkey)
    Write-Host 'Проверяю подпись релиза...'
    $rc = Invoke-VwVerifier -AllowedSigners $allowed -Principal $script:SignPrincipal -SigFile $sigFile -SumsFile $sumsFile
    if ($rc -eq 0) {
        Write-Host 'Подпись релиза верна (аутентичность подтверждена).'
    } else {
        # Плохая подпись — жёсткий отказ БЕЗ обхода (как install.sh): активный признак подмены.
        throw 'Подпись релиза НЕ прошла проверку — установка прервана (возможна подмена).'
    }
}

# Основной поток установки. VAULTWATCH_NO_MAIN=1 → только определить функции (для Pester).
if ($env:VAULTWATCH_NO_MAIN -ne '1') {

Write-Host 'vaultwatch (Windows, BETA) installer'
Write-Host '------------------------------------'

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("vaultwatch-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
    $tmpScript = Join-Path $Tmp 'vaultwatch.ps1'
    $tmpSums   = Join-Path $Tmp 'SHA256SUMS'

    Write-Host 'Downloading vaultwatch.ps1 + SHA256SUMS from release...'
    Get-ReleaseFile -Name 'vaultwatch.ps1' -OutFile $tmpScript
    Get-ReleaseFile -Name 'SHA256SUMS'     -OutFile $tmpSums

    $expected = $null
    foreach ($line in Get-Content -Path $tmpSums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $fname = $parts[1].Trim().TrimStart('*')
            if ($fname -eq 'vaultwatch.ps1') { $expected = $parts[0].Trim().ToLower() }
        }
    }
    if (-not $expected) {
        Write-Error 'SHA256SUMS не содержит записи для vaultwatch.ps1 — установка прервана.'
        exit 1
    }

    $actual = (Get-FileHash -Path $tmpScript -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        Write-Error "Контрольная сумма НЕ совпала (возможна подмена) — установка прервана.`nexpected: $expected`nactual:   $actual"
        exit 1
    }
    Write-Host 'Checksum OK.'

    # Аутентичность поверх целостности: проверяем подпись релиза (fail-closed).
    Assert-VwSignature -Tmp $Tmp

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    Copy-Item -Path $tmpScript -Destination $ScriptPath -Force
    Write-Host "Installed: $ScriptPath"
}
finally {
    Remove-Item -Path $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$shim = @"
@echo off
pwsh -NoProfile -File "%~dp0vaultwatch.ps1" %*
if errorlevel 1 exit /b %errorlevel%
"@
Set-Content -Path $ShimPath -Value $shim -Encoding ASCII
Write-Host "Shim created: $ShimPath"

if ($env:VAULTWATCH_SKIP_PATH -ne '1') {
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
Write-Host '  2) Run:  vaultwatch version'
Write-Host '  3) Guard a mounted vault:  vaultwatch start --ttl 30m V:\'
Write-Host ''
Write-Host 'NOTE: BETA port. Search exclusion + TTL auto-dismount work; backup snapshots (VSS) are'
Write-Host 'reported but NOT removed, and the pagefile is not addressed. See windows/README.md.'

}  # /if VAULTWATCH_NO_MAIN
