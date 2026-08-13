# Pester 5 — install.ps1 (Windows-порт panic). Проверяем integrity- и signature-gate без сети:
# PANIC_BASE_URL указывает на локальный каталог-«релиз», установка идёт во временный
# каталог, правка PATH отключена. Покрытие integrity: happy-path, провал на расхождении хеша,
# провал при отсутствии записи в SHA256SUMS (fail-closed). Покрытие signature: валидная/битая
# подпись, отсутствие .sig, отсутствие ssh-keygen — через мок-шим ssh-keygen в PATH.
#
# Integrity-тесты гоняются с PT_ALLOW_HASH_ONLY='1' (фикстура без .sig): цель — только хеш-гейт;
# сам signature-гейт покрыт отдельным Describe.

BeforeAll {
    $script:InstallScript = Join-Path $PSScriptRoot '..\install.ps1'
}

Describe 'install.ps1 integrity gate' {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_inst_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Target  = Join-Path $script:Work 'target'
        New-Item -ItemType Directory -Path $script:Release -Force | Out-Null

        # Полезная нагрузка-«скрипт» + корректный SHA256SUMS.
        $payload = "Write-Output 'payload-ok'`n"
        $script:ScriptFile = Join-Path $script:Release 'panic.ps1'
        Set-Content -LiteralPath $script:ScriptFile -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $script:ScriptFile -Algorithm SHA256).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  panic.ps1"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs the script when the checksum matches' {
        # Установщик гоняем в дочернем pwsh: env-настройки выставляем внутри -Command,
        # чтобы не протекали в тест-сессию.
        & pwsh -NoProfile -Command "`$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; `$env:PT_ALLOW_HASH_ONLY='1'; & '$($script:InstallScript)'" *> $null
        (Test-Path (Join-Path $script:Target 'panic.ps1')) | Should -BeTrue
        (Test-Path (Join-Path $script:Target 'panic.cmd')) | Should -BeTrue
    }

    It 'fails closed when the checksum does not match' {
        # Портим SHA256SUMS — хеш не сойдётся.
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value ("0"*64 + "  panic.ps1")
        & pwsh -NoProfile -Command "`$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; `$env:PT_ALLOW_HASH_ONLY='1'; & '$($script:InstallScript)'" *> $null
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'panic.ps1')) | Should -BeFalse
    }

    It 'fails closed when SHA256SUMS lacks the panic.ps1 entry' {
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value ("deadbeef  somethingelse.txt")
        & pwsh -NoProfile -Command "`$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; `$env:PT_ALLOW_HASH_ONLY='1'; & '$($script:InstallScript)'" *> $null
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'panic.ps1')) | Should -BeFalse
    }
}

Describe 'install.ps1 signature gate' {
    It 'can still verify under Windows PowerShell 5.1 (no ArgumentList there)' {
        # `ArgumentList` есть только в .NET Core (PowerShell 7). Windows PowerShell 5.1 —
        # штатный шелл Windows и ровно тот, в котором выполняют однострочник из README;
        # без запасного пути установка падала бы на шаге проверки подписи.
        $src = Get-Content -Raw -LiteralPath $script:InstallScript
        $src | Should -Match "PSObject\.Properties\.Name -contains 'ArgumentList'"
        $src | Should -Match '\$psi\.Arguments ='
    }

    # Хеш всегда валиден (это покрыто выше); варьируем ТОЛЬКО подпись. `ssh-keygen` подменяем
    # мок-шимом в PATH: результат verify задаём его кодом выхода (0=валидна, 1=битая). Реальный
    # ключ/подпись не нужны — проверяем оркестровку fail-closed, а не саму криптографию ssh.
    BeforeAll {
        $script:InstallScript = Join-Path $PSScriptRoot '..\install.ps1'

        # Кладёт мок-ssh-keygen с заданным кодом выхода в $ShimDir; Windows-CI — .cmd, иначе — bash-шим.
        # Шим, СОХРАНЯЮЩИЙ полученный stdin в файл (путь — в PT_TEST_STDIN_CAPTURE): проверяем
        # не «позвали верификатор», а ЧТО в него уехало. Сам шим — pwsh-скрипт (одинаковый на
        # всех платформах), обёрнутый в .cmd/sh, потому что PATH ищет исполняемый файл, не .ps1.
        function New-SshKeygenCaptureShim {
            $capture = Join-Path $script:ShimDir 'capture.ps1'
            Set-Content -LiteralPath $capture -Encoding ascii -Value @'
$fs = [IO.File]::Create($env:PT_TEST_STDIN_CAPTURE)
try { [Console]::OpenStandardInput().CopyTo($fs) } finally { $fs.Close() }
exit 0
'@
            # $env:OS, не $IsWindows: последняя определена только в PowerShell 6+, под Windows
            # PowerShell 5.1 она $null — и тест уходил в Unix-ветку прямо на Windows.
            if ($env:OS -eq 'Windows_NT') {
                Set-Content -LiteralPath (Join-Path $script:ShimDir 'ssh-keygen.cmd') -Encoding ASCII `
                    -Value "@echo off`r`npwsh -NoProfile -File `"$capture`"`r`nexit /b %ERRORLEVEL%`r`n"
            } else {
                $shim = Join-Path $script:ShimDir 'ssh-keygen'
                Set-Content -LiteralPath $shim -Value "#!/bin/sh`nexec pwsh -NoProfile -File '$capture'`n" -NoNewline
                & chmod +x $shim
            }
        }

        # Болтливый шим: сыплет в stdout/stderr заведомо больше буфера трубы и выходит с 0.
        # Если установщик перенаправил потоки и не вычитывает их, верификатор встанет на записи,
        # а `WaitForExit` будет ждать его вечно — установка молча зависнет.
        function New-SshKeygenNoisyShim {
            $noisy = Join-Path $script:ShimDir 'noisy.ps1'
            Set-Content -LiteralPath $noisy -Encoding ascii -Value @'
$null = [Console]::OpenStandardInput().CopyTo([IO.Stream]::Null)
$chunk = 'x' * 4096
for ($i = 0; $i -lt 64; $i++) { [Console]::Out.WriteLine($chunk); [Console]::Error.WriteLine($chunk) }
exit 0
'@
            if ($env:OS -eq 'Windows_NT') {
                Set-Content -LiteralPath (Join-Path $script:ShimDir 'ssh-keygen.cmd') -Encoding ASCII `
                    -Value "@echo off`r`npwsh -NoProfile -File `"$noisy`"`r`nexit /b %ERRORLEVEL%`r`n"
            } else {
                $shim = Join-Path $script:ShimDir 'ssh-keygen'
                Set-Content -LiteralPath $shim -Value "#!/bin/sh`nexec pwsh -NoProfile -File '$noisy'`n" -NoNewline
                & chmod +x $shim
            }
        }

        function New-SshKeygenShim([int]$ExitCode) {
            if ($env:OS -eq 'Windows_NT') {
                $shim = Join-Path $script:ShimDir 'ssh-keygen.cmd'
                Set-Content -LiteralPath $shim -Value "@echo off`r`nexit /b $ExitCode`r`n" -Encoding ASCII
            } else {
                $shim = Join-Path $script:ShimDir 'ssh-keygen'
                Set-Content -LiteralPath $shim -Value "#!/usr/bin/env bash`nexit $ExitCode`n" -NoNewline
                & chmod +x $shim
            }
        }

        # Создаёт .sig-заглушку в релизе (содержимое неважно — verify мокается шимом).
        function New-SigFile {
            Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS.sig') -Value 'dummy-signature' -NoNewline
        }

        # Запуск установщика с prepended $ShimDir в PATH (мок-ssh-keygen находится первым).
        function Invoke-Installer([string]$ExtraEnv = '') {
            $withShim = "`$env:PATH='$($script:ShimDir)' + [IO.Path]::PathSeparator + `$env:PATH; "
            & pwsh -NoProfile -Command "$withShim`$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; $ExtraEnv & '$($script:InstallScript)'" *> $null
        }
    }

    BeforeEach {
        $script:Work    = Join-Path ([System.IO.Path]::GetTempPath()) ("pn_sig_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Target  = Join-Path $script:Work 'target'
        $script:ShimDir = Join-Path $script:Work 'bin'
        $script:EmptyDir = Join-Path $script:Work 'empty'
        New-Item -ItemType Directory -Path $script:Release  -Force | Out-Null
        New-Item -ItemType Directory -Path $script:ShimDir  -Force | Out-Null
        New-Item -ItemType Directory -Path $script:EmptyDir -Force | Out-Null

        # Корректная нагрузка + SHA256SUMS (хеш сходится).
        $payload = "Write-Output 'payload-ok'`n"
        $sf = Join-Path $script:Release 'panic.ps1'
        Set-Content -LiteralPath $sf -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $sf -Algorithm SHA256).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  panic.ps1"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs when the signature verifies' {
        New-SshKeygenShim 0
        New-SigFile
        Invoke-Installer
        $LASTEXITCODE | Should -Be 0
        (Test-Path (Join-Path $script:Target 'panic.ps1')) | Should -BeTrue
    }

    It 'does not hang when the verifier is noisy (redirected streams must be drained)' {
        New-SshKeygenNoisyShim
        New-SigFile
        $job = Start-Job -ScriptBlock {
            param($InstallScript, $Release, $Target, $ShimDir, $Sep)
            $env:PATH = $ShimDir + $Sep + $env:PATH
            $env:PANIC_BASE_URL = $Release
            $env:PANIC_INSTALL_DIR = $Target
            $env:PANIC_SKIP_PATH = '1'
            & pwsh -NoProfile -File $InstallScript *> $null
        } -ArgumentList $script:InstallScript, $script:Release, $script:Target, $script:ShimDir, ([IO.Path]::PathSeparator)
        $finished = Wait-Job -Job $job -Timeout 90
        Remove-Job -Job $job -Force
        $finished | Should -Not -BeNullOrEmpty -Because 'установщик обязан завершиться, а не ждать верификатор вечно'
        (Test-Path (Join-Path $script:Target 'panic.ps1')) | Should -BeTrue
    }

    It 'hands the verifier the signed bytes unchanged (CRLF survives, nothing appended)' {
        # Регрессия, которая уже случалась в экосистеме: SHA256SUMS уходил в ssh-keygen через
        # конвейер PowerShell, а тот перекодирует текст (BOM, CRLF) и дописывает перевод строки.
        # Подпись валидна, но верификатор видит ДРУГИЕ байты → «incorrect signature» → fail-closed
        # рубит установку с НАСТОЯЩЕГО релиза. Файл здесь намеренно с CRLF: так его отдаёт
        # любой генератор, запущенный на Windows.
        $sums = Join-Path $script:Release 'SHA256SUMS'
        $hash = (Get-FileHash -Path (Join-Path $script:Release 'panic.ps1') -Algorithm SHA256).Hash.ToLower()
        [IO.File]::WriteAllBytes($sums, [Text.Encoding]::ASCII.GetBytes("$hash  panic.ps1`r`n"))
        $expected = [IO.File]::ReadAllBytes($sums)

        New-SshKeygenCaptureShim
        New-SigFile
        $capture = Join-Path $script:Work 'stdin.bin'
        Invoke-Installer "`$env:PT_TEST_STDIN_CAPTURE='$capture'; "

        (Test-Path $capture) | Should -BeTrue
        [IO.File]::ReadAllBytes($capture) | Should -Be $expected
    }

    It 'fails closed when the signature is invalid' {
        New-SshKeygenShim 1
        New-SigFile
        Invoke-Installer
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'panic.ps1')) | Should -BeFalse
    }

    It 'fails closed when the signature file is missing' {
        New-SshKeygenShim 0   # verifier есть, но .sig нет
        Invoke-Installer
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'panic.ps1')) | Should -BeFalse
    }

    It 'installs a missing signature only with PT_ALLOW_HASH_ONLY=1' {
        New-SshKeygenShim 0
        Invoke-Installer "`$env:PT_ALLOW_HASH_ONLY='1'; "
        $LASTEXITCODE | Should -Be 0
        (Test-Path (Join-Path $script:Target 'panic.ps1')) | Should -BeTrue
    }

    It 'fails closed when ssh-keygen is unavailable' {
        # PATH без ssh-keygen (пустой каталог) → verifier не найден → отказ.
        New-SigFile
        & pwsh -NoProfile -Command "`$env:PATH='$($script:EmptyDir)'; `$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; & '$($script:InstallScript)'" *> $null
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'panic.ps1')) | Should -BeFalse
    }

    It 'installs without a verifier only with PT_ALLOW_HASH_ONLY=1' {
        New-SigFile
        & pwsh -NoProfile -Command "`$env:PATH='$($script:EmptyDir)'; `$env:PANIC_BASE_URL='$($script:Release)'; `$env:PANIC_INSTALL_DIR='$($script:Target)'; `$env:PANIC_SKIP_PATH='1'; `$env:PT_ALLOW_HASH_ONLY='1'; & '$($script:InstallScript)'" *> $null
        $LASTEXITCODE | Should -Be 0
        (Test-Path (Join-Path $script:Target 'panic.ps1')) | Should -BeTrue
    }
}
