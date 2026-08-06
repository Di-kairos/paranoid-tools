# Pester 5 тесты install.ps1: ставит securetrash.ps1 только при совпадении SHA256
# И валидной ed25519-подписи; fail-closed отказывается при подмене/отсутствии суммы,
# отсутствии/невалидности подписи или отсутствии верификатора (ssh-keygen).
#
# ssh-keygen подменяется фейком в отдельном каталоге на PATH (кросс-процессный мок,
# как в bats): установщик запускается дочерним pwsh, поэтому Pester-Mock не подходит.

BeforeAll {
    $script:Installer = Join-Path $PSScriptRoot '..\install.ps1'
    # Абсолютный путь к pwsh — чтобы звать установщик при урезанном PATH.
    $script:PwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

    # Кладёт фейковый ssh-keygen с заданным кодом выхода в каталог $Dir.
    # Windows: файл без расширения — не Application для Get-Command (PATHEXT), поэтому
    # sh-фейк установщик не находил вовсе и happy-path падал fail-closed'ом (красный
    # ci с v0.4.11). Кладём .cmd — честно исполняемый фейк для обеих веток verify.
    function New-FakeSshKeygen {
        param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][int]$ExitCode)
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        # $env:OS, не $IsWindows: последний не определён в Windows PowerShell 5.1.
        if ($env:OS -eq 'Windows_NT') {
            Set-Content -LiteralPath (Join-Path $Dir 'ssh-keygen.cmd') -Value "@exit /b $ExitCode"
        } else {
            $p = Join-Path $Dir 'ssh-keygen'
            Set-Content -LiteralPath $p -Value "#!/bin/sh`nexit $ExitCode`n" -NoNewline
            & chmod +x $p
        }
    }
}

Describe 'install.ps1 integrity + signature' {
    It 'can still verify under Windows PowerShell 5.1 (no ArgumentList there)' {
        # `ArgumentList` есть только в .NET Core (PowerShell 7). Windows PowerShell 5.1 —
        # штатный шелл Windows и ровно тот, в котором выполняют однострочник из README;
        # без запасного пути установка падала бы на шаге проверки подписи.
        $src = Get-Content -Raw -LiteralPath $script:Installer
        $src | Should -Match "PSObject\.Properties\.Name -contains 'ArgumentList'"
        $src | Should -Match '\$psi\.Arguments ='
    }

    It 'never pipes the signed data into the verifier (bytes must reach it unchanged)' {
        # Конвейер PowerShell перекодирует текст (BOM, CRLF) и дописывает перевод строки, поэтому
        # верификатор увидел бы НЕ те байты, что подписаны: валидная подпись читается как
        # «incorrect signature», и fail-closed рубит установку с настоящего релиза. Так уже
        # ломался seedsplit. Канон — сырой поток файла в stdin через ProcessStartInfo.
        $src = Get-Content -Raw -LiteralPath $script:Installer
        $src | Should -Match 'ProcessStartInfo'
        $src | Should -Not -Match '(?m)Get-Content[^\r\n]*\|\s*&'
    }


    BeforeEach {
        $script:Work    = Join-Path ([System.IO.Path]::GetTempPath()) ("st_inst_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Dest    = Join-Path $script:Work 'install'
        $script:Bin     = Join-Path $script:Work 'bin'   # каталог с фейковым ssh-keygen
        New-Item -ItemType Directory -Path $script:Release -Force | Out-Null
        New-Item -ItemType Directory -Path $script:Bin -Force | Out-Null

        # Полезная нагрузка-заглушка + корректный SHA256SUMS.
        $payload = "Write-Host 'payload-ok'`n"
        $scriptFile = Join-Path $script:Release 'securetrash.ps1'
        Set-Content -Path $scriptFile -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $scriptFile -Algorithm SHA256).Hash.ToLower()
        Set-Content -Path (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  securetrash.ps1"
        # .sig-заглушка: реальная криптопроверка мокается ssh-keygen'ом.
        Set-Content -Path (Join-Path $script:Release 'SHA256SUMS.sig') -Value "dummy-signature"

        $script:OrigPath = $env:PATH
        $env:ST_BASE_URL    = $script:Release
        $env:ST_INSTALL_DIR = $script:Dest
        $env:ST_SKIP_PATH   = '1'
    }

    AfterEach {
        $env:PATH = $script:OrigPath
        Remove-Item Env:\ST_BASE_URL, Env:\ST_INSTALL_DIR, Env:\ST_SKIP_PATH, Env:\PT_ALLOW_HASH_ONLY -ErrorAction SilentlyContinue
        Remove-Item -Path $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs when checksum matches and signature is valid' {
        New-FakeSshKeygen -Dir $script:Bin -ExitCode 0
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeTrue
    }

    It 'fails closed on checksum mismatch' {
        # Подменяем нагрузку ПОСЛЕ генерации SHA256SUMS — хеш не сходится (до подписи не доходит).
        Set-Content -Path (Join-Path $script:Release 'securetrash.ps1') -Value "Write-Host 'TAMPERED'`n" -NoNewline
        New-FakeSshKeygen -Dir $script:Bin -ExitCode 0
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
    }

    It 'fails closed when SHA256SUMS lacks the entry' {
        Set-Content -Path (Join-Path $script:Release 'SHA256SUMS') -Value "deadbeef  something-else"
        New-FakeSshKeygen -Dir $script:Bin -ExitCode 0
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
    }

    It 'fails closed when the signature is INVALID' {
        New-FakeSshKeygen -Dir $script:Bin -ExitCode 1   # ssh-keygen -Y verify != 0
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
    }

    It 'fails closed when the signature is MISSING' {
        Remove-Item -Path (Join-Path $script:Release 'SHA256SUMS.sig') -Force
        New-FakeSshKeygen -Dir $script:Bin -ExitCode 0
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
    }

    It 'fails closed when the verifier (ssh-keygen) is missing' {
        # $script:Bin пуст — ssh-keygen недоступен на урезанном PATH.
        $env:PATH = $script:Bin
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
    }

    It 'PT_ALLOW_HASH_ONLY=1 allows install when verifier is missing (loud escape)' {
        $env:PATH = $script:Bin              # ssh-keygen отсутствует
        $env:PT_ALLOW_HASH_ONLY = '1'
        & $script:PwshExe -NoProfile -File $script:Installer 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        Test-Path (Join-Path $script:Dest 'securetrash.ps1') | Should -BeTrue
    }
}
