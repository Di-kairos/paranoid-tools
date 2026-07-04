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
