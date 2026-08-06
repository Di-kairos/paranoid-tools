# Pester 5 — install.ps1 (Windows-порт seedsplit). Проверяем integrity- и signature-gate без сети:
# SEEDSPLIT_BASE_URL указывает на локальный каталог-«релиз», установка идёт во временный
# каталог, правка PATH отключена. Покрытие: happy-path, провал на расхождении хеша,
# провал при отсутствии записи в SHA256SUMS, а также подпись релиза (valid/invalid/
# missing-sig/missing-verifier) — все fail-closed с обходом только по PT_ALLOW_HASH_ONLY=1.

BeforeAll {
    $script:InstallScript = Join-Path $PSScriptRoot '..\install.ps1'

    # Мок ssh-keygen: кладём подставной исполняемый файл в каталог, который тест префиксует к PATH,
    # чтобы он затенил реальный ssh-keygen. Стаб дренирует stdin (чтобы pipe не оборвался) и
    # выходит с заданным кодом (0 = подпись верна, !=0 = подпись не прошла). Кроссплатформенно:
    # .cmd для Windows-CI + shell-скрипт без расширения для macOS/Linux-разработки.
    function script:New-SshKeygenStub {
        param([string]$Dir, [int]$ExitCode)
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        # Windows: ssh-keygen.cmd (резолвится через PATHEXT).
        $cmd = "@echo off`r`nmore 1>nul 2>nul`r`nexit /b $ExitCode`r`n"
        Set-Content -LiteralPath (Join-Path $Dir 'ssh-keygen.cmd') -Value $cmd -Encoding ascii -NoNewline
        # macOS/Linux: ssh-keygen (исполняемый shell-скрипт).
        $sh = "#!/bin/sh`ncat >/dev/null 2>&1`nexit $ExitCode`n"
        $shPath = Join-Path $Dir 'ssh-keygen'
        Set-Content -LiteralPath $shPath -Value $sh -Encoding ascii -NoNewline
        if (-not $IsWindows) { & chmod +x $shPath }
    }

    # Мок ssh-keygen, который СОХРАНЯЕТ полученный stdin в файл (путь — в PT_TEST_STDIN_CAPTURE).
    # Нужен, чтобы проверить не «позвали верификатор», а ЧТО именно в него уехало: подписанные
    # данные обязаны дойти байт-в-байт. Сам стаб — pwsh-скрипт (одинаковый на всех платформах),
    # обёрнутый в .cmd/sh, потому что PATH ищет исполняемый файл, а не .ps1.
    function script:New-SshKeygenCaptureStub {
        param([string]$Dir)
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        $capture = Join-Path $Dir 'capture.ps1'
        Set-Content -LiteralPath $capture -Encoding ascii -Value @'
$fs = [IO.File]::Create($env:PT_TEST_STDIN_CAPTURE)
try { [Console]::OpenStandardInput().CopyTo($fs) } finally { $fs.Close() }
exit 0
'@
        $cmd = "@echo off`r`npwsh -NoProfile -File `"$capture`"`r`nexit /b %ERRORLEVEL%`r`n"
        Set-Content -LiteralPath (Join-Path $Dir 'ssh-keygen.cmd') -Value $cmd -Encoding ascii -NoNewline
        $sh = "#!/bin/sh`nexec pwsh -NoProfile -File '$capture'`n"
        $shPath = Join-Path $Dir 'ssh-keygen'
        Set-Content -LiteralPath $shPath -Value $sh -Encoding ascii -NoNewline
        if (-not $IsWindows) { & chmod +x $shPath }
    }

    # Болтливый стаб: сыплет в stdout/stderr заведомо больше буфера трубы и выходит с 0.
    # Если установщик перенаправил потоки и не вычитывает их, верификатор встанет на записи,
    # а `WaitForExit` будет ждать его вечно — установка молча зависнет.
    function script:New-SshKeygenNoisyStub {
        param([string]$Dir)
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        $noisy = Join-Path $Dir 'noisy.ps1'
        Set-Content -LiteralPath $noisy -Encoding ascii -Value @'
$null = [Console]::OpenStandardInput().CopyTo([IO.Stream]::Null)
$chunk = 'x' * 4096
for ($i = 0; $i -lt 64; $i++) { [Console]::Out.WriteLine($chunk); [Console]::Error.WriteLine($chunk) }
exit 0
'@
        $cmd = "@echo off`r`npwsh -NoProfile -File `"$noisy`"`r`nexit /b %ERRORLEVEL%`r`n"
        Set-Content -LiteralPath (Join-Path $Dir 'ssh-keygen.cmd') -Value $cmd -Encoding ascii -NoNewline
        $sh = "#!/bin/sh`nexec pwsh -NoProfile -File '$noisy'`n"
        $shPath = Join-Path $Dir 'ssh-keygen'
        Set-Content -LiteralPath $shPath -Value $sh -Encoding ascii -NoNewline
        if (-not $IsWindows) { & chmod +x $shPath }
    }

    # Запуск установщика в дочернем pwsh: env-настройки внутри -Command, чтобы не текли в тест-сессию.
    # $ExtraEnv — доп. присваивания ($env:...) перед вызовом (напр. PT_ALLOW_HASH_ONLY, PATH).
    function script:Invoke-Installer {
        param([string]$Release, [string]$Target, [string]$ExtraEnv = '')
        $cmd = "`$env:SEEDSPLIT_BASE_URL='$Release'; `$env:SEEDSPLIT_INSTALL_DIR='$Target'; " +
               "`$env:SEEDSPLIT_SKIP_PATH='1'; $ExtraEnv & '$($script:InstallScript)'"
        & pwsh -NoProfile -Command $cmd *> $null
    }

    # PATH с префиксом каталога-стаба: затеняет реальный ssh-keygen подставным.
    function script:PrefixPathEnv([string]$Dir) {
        $sep = [System.IO.Path]::PathSeparator
        "`$env:PATH='$Dir'+'$sep'+`$env:PATH; "
    }
    # PATH только из указанного каталога: ssh-keygen не найдётся (сценарий «нет верификатора»).
    function script:OnlyPathEnv([string]$Dir) { "`$env:PATH='$Dir'; " }
}

Describe 'install.ps1 integrity gate' {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("ss_inst_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Target  = Join-Path $script:Work 'target'
        New-Item -ItemType Directory -Path $script:Release -Force | Out-Null

        # Полезная нагрузка-«скрипт» + корректный SHA256SUMS.
        $payload = "Write-Output 'payload-ok'`n"
        $script:ScriptFile = Join-Path $script:Release 'seedsplit.ps1'
        Set-Content -LiteralPath $script:ScriptFile -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $script:ScriptFile -Algorithm SHA256).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  seedsplit.ps1"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Эти тесты — про целостность; подпись здесь не в фокусе, поэтому PT_ALLOW_HASH_ONLY=1
    # (релиз-каталог без SHA256SUMS.sig, иначе signature-gate прервал бы happy-path).
    It 'installs the script when the checksum matches' {
        Invoke-Installer -Release $script:Release -Target $script:Target -ExtraEnv "`$env:PT_ALLOW_HASH_ONLY='1'; "
        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeTrue
        (Test-Path (Join-Path $script:Target 'seedsplit.cmd')) | Should -BeTrue
    }

    It 'fails closed when the checksum does not match' {
        # Портим SHA256SUMS — хеш не сойдётся.
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value ("0"*64 + "  seedsplit.ps1")
        Invoke-Installer -Release $script:Release -Target $script:Target -ExtraEnv "`$env:PT_ALLOW_HASH_ONLY='1'; "
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeFalse
    }

    It 'fails closed when SHA256SUMS lacks the seedsplit.ps1 entry' {
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value ("deadbeef  somethingelse.txt")
        Invoke-Installer -Release $script:Release -Target $script:Target -ExtraEnv "`$env:PT_ALLOW_HASH_ONLY='1'; "
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeFalse
    }
}

Describe 'install.ps1 signature gate' {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("ss_sig_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Target  = Join-Path $script:Work 'target'
        $script:StubDir = Join-Path $script:Work 'stub'
        New-Item -ItemType Directory -Path $script:Release -Force | Out-Null

        $payload = "Write-Output 'payload-ok'`n"
        Set-Content -LiteralPath (Join-Path $script:Release 'seedsplit.ps1') -Value $payload -NoNewline
        $hash = (Get-FileHash -Path (Join-Path $script:Release 'seedsplit.ps1') -Algorithm SHA256).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  seedsplit.ps1"
        # Содержимое .sig неважно — реальный ssh-keygen затенён стабом; вердикт задаёт код выхода стаба.
        $script:SigFile = Join-Path $script:Release 'SHA256SUMS.sig'
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs when the release signature verifies' {
        Set-Content -LiteralPath $script:SigFile -Value 'dummy-signature'
        script:New-SshKeygenStub -Dir $script:StubDir -ExitCode 0
        Invoke-Installer -Release $script:Release -Target $script:Target -ExtraEnv (script:PrefixPathEnv $script:StubDir)
        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeTrue
    }

    It 'says the signature did not verify when the verifier quits without reading stdin' {
        # Верификатор вправе выйти, не дочитав подписанные данные (кривые аргументы, чужой
        # ssh-keygen в PATH). Запись в уже закрытую трубу роняла установщик исключением, и
        # вместо честного «подпись не сошлась» пользователь получал аварию. SHA256SUMS здесь
        # намеренно большой: иначе копирование успевает пролезть в буфер трубы до её закрытия,
        # и гонка не воспроизводится (так этот дефект и прошёл мимо macOS-прогона).
        $sums = Join-Path $script:Release 'SHA256SUMS'
        $hash = (Get-FileHash -Path (Join-Path $script:Release 'seedsplit.ps1') -Algorithm SHA256).Hash.ToLower()
        $filler = (1..20000 | ForEach-Object { "$hash  filler-$_" }) -join "`n"
        Set-Content -LiteralPath $sums -Value "$hash  seedsplit.ps1`n$filler" -NoNewline

        Set-Content -LiteralPath $script:SigFile -Value 'dummy-signature'
        # Стаб выходит сразу, stdin не дренирует.
        New-Item -ItemType Directory -Path $script:StubDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:StubDir 'ssh-keygen.cmd') -Encoding ascii -NoNewline `
            -Value "@echo off`r`nexit /b 1`r`n"
        $shPath = Join-Path $script:StubDir 'ssh-keygen'
        Set-Content -LiteralPath $shPath -Value "#!/bin/sh`nexit 1`n" -Encoding ascii -NoNewline
        if (-not $IsWindows) { & chmod +x $shPath }

        $out = & pwsh -NoProfile -Command (
            (script:PrefixPathEnv $script:StubDir) +
            "`$env:SEEDSPLIT_BASE_URL='$($script:Release)'; `$env:SEEDSPLIT_INSTALL_DIR='$($script:Target)'; " +
            "`$env:SEEDSPLIT_SKIP_PATH='1'; & '$($script:InstallScript)'") 2>&1 | Out-String

        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeFalse
        $out | Should -Match 'Подпись релиза НЕ прошла проверку'
    }

    It 'does not hang when the verifier is noisy (redirected streams must be drained)' {
        Set-Content -LiteralPath $script:SigFile -Value 'dummy-signature'
        script:New-SshKeygenNoisyStub -Dir $script:StubDir
        $job = Start-Job -ScriptBlock {
            param($InstallScript, $Release, $Target, $StubDir, $Sep)
            $env:PATH = $StubDir + $Sep + $env:PATH
            $env:SEEDSPLIT_BASE_URL = $Release
            $env:SEEDSPLIT_INSTALL_DIR = $Target
            $env:SEEDSPLIT_SKIP_PATH = '1'
            & pwsh -NoProfile -File $InstallScript *> $null
        } -ArgumentList $script:InstallScript, $script:Release, $script:Target, $script:StubDir, ([IO.Path]::PathSeparator)
        $finished = Wait-Job -Job $job -Timeout 90
        Remove-Job -Job $job -Force
        $finished | Should -Not -BeNullOrEmpty -Because 'установщик обязан завершиться, а не ждать верификатор вечно'
        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeTrue
    }

    It 'hands the verifier the signed bytes unchanged (CRLF survives, nothing appended)' {
        # Регрессия, которая уже случалась: SHA256SUMS шёл в ssh-keygen через конвейер PowerShell,
        # а тот перекодирует текст (BOM, CRLF) и добавляет перевод строки. Подпись валидна, но
        # верификатор видит ДРУГИЕ байты → «incorrect signature» → fail-closed рубит установку
        # с настоящего релиза. Файл здесь намеренно с CRLF: так его отдаёт любой генератор,
        # запущенный на Windows.
        $sums = Join-Path $script:Release 'SHA256SUMS'
        $hash = (Get-FileHash -Path (Join-Path $script:Release 'seedsplit.ps1') -Algorithm SHA256).Hash.ToLower()
        [IO.File]::WriteAllBytes($sums, [Text.Encoding]::ASCII.GetBytes("$hash  seedsplit.ps1`r`n"))
        $expected = [IO.File]::ReadAllBytes($sums)

        Set-Content -LiteralPath $script:SigFile -Value 'dummy-signature'
        script:New-SshKeygenCaptureStub -Dir $script:StubDir
        $capture = Join-Path $script:Work 'stdin.bin'
        Invoke-Installer -Release $script:Release -Target $script:Target `
            -ExtraEnv ((script:PrefixPathEnv $script:StubDir) + "`$env:PT_TEST_STDIN_CAPTURE='$capture'; ")

        (Test-Path $capture) | Should -BeTrue
        [IO.File]::ReadAllBytes($capture) | Should -Be $expected
    }

    It 'fails closed on an invalid signature (no bypass, even with PT_ALLOW_HASH_ONLY)' {
        Set-Content -LiteralPath $script:SigFile -Value 'tampered-signature'
        script:New-SshKeygenStub -Dir $script:StubDir -ExitCode 1
        # Даже с PT_ALLOW_HASH_ONLY=1 неверная подпись = жёсткий отказ.
        Invoke-Installer -Release $script:Release -Target $script:Target `
            -ExtraEnv ((script:PrefixPathEnv $script:StubDir) + "`$env:PT_ALLOW_HASH_ONLY='1'; ")
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeFalse
    }

    It 'fails closed when the signature is missing and hash-only is not allowed' {
        # .sig отсутствует; верификатор есть.
        script:New-SshKeygenStub -Dir $script:StubDir -ExitCode 0
        Invoke-Installer -Release $script:Release -Target $script:Target -ExtraEnv (script:PrefixPathEnv $script:StubDir)
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeFalse
    }

    It 'installs on a missing signature when PT_ALLOW_HASH_ONLY=1' {
        script:New-SshKeygenStub -Dir $script:StubDir -ExitCode 0
        Invoke-Installer -Release $script:Release -Target $script:Target `
            -ExtraEnv ((script:PrefixPathEnv $script:StubDir) + "`$env:PT_ALLOW_HASH_ONLY='1'; ")
        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeTrue
    }

    It 'fails closed when ssh-keygen is missing and hash-only is not allowed' {
        Set-Content -LiteralPath $script:SigFile -Value 'dummy-signature'
        New-Item -ItemType Directory -Path $script:StubDir -Force | Out-Null   # пустой каталог, без ssh-keygen
        Invoke-Installer -Release $script:Release -Target $script:Target -ExtraEnv (script:OnlyPathEnv $script:StubDir)
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeFalse
    }

    It 'installs without a verifier when PT_ALLOW_HASH_ONLY=1' {
        Set-Content -LiteralPath $script:SigFile -Value 'dummy-signature'
        New-Item -ItemType Directory -Path $script:StubDir -Force | Out-Null
        Invoke-Installer -Release $script:Release -Target $script:Target `
            -ExtraEnv ((script:OnlyPathEnv $script:StubDir) + "`$env:PT_ALLOW_HASH_ONLY='1'; ")
        (Test-Path (Join-Path $script:Target 'seedsplit.ps1')) | Should -BeTrue
    }
}
