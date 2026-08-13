# Pester 5 — install.ps1 (Windows-порт ghostdraft). Проверяем integrity-gate + signature-gate
# без сети: GHOSTDRAFT_BASE_URL указывает на локальный каталог-«релиз», установка идёт во
# временный каталог, правка PATH отключена. Покрытие: happy-path, провал на расхождении хеша,
# провал при отсутствии записи в SHA256SUMS, и полный набор для подписи релиза (fail-closed).

BeforeAll {
    $script:InstallScript = Join-Path $PSScriptRoot '..\install.ps1'

    # Запуск install.ps1 в дочернем pwsh с заданным окружением. Возвращает $LASTEXITCODE.
    function Invoke-Install {
        param([hashtable]$Env)
        $prelude = ($Env.GetEnumerator() | ForEach-Object {
            "`$env:$($_.Key)='$($_.Value)'"
        }) -join '; '
        & pwsh -NoProfile -Command "$prelude; & '$($script:InstallScript)'" *> $null
        return $LASTEXITCODE
    }
}

Describe 'install.ps1 integrity gate' {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("gd_inst_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Target  = Join-Path $script:Work 'target'
        New-Item -ItemType Directory -Path $script:Release -Force | Out-Null

        # Полезная нагрузка-«скрипт» + корректный SHA256SUMS.
        $payload = "Write-Output 'payload-ok'`n"
        $script:ScriptFile = Join-Path $script:Release 'ghostdraft.ps1'
        Set-Content -LiteralPath $script:ScriptFile -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $script:ScriptFile -Algorithm SHA256).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  ghostdraft.ps1"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Эти тесты проверяют хеш-гейт, а не подпись → PT_ALLOW_HASH_ONLY=1 (релиз без .sig).
    It 'installs the script when the checksum matches' {
        Invoke-Install @{ GHOSTDRAFT_BASE_URL=$script:Release; GHOSTDRAFT_INSTALL_DIR=$script:Target; GHOSTDRAFT_SKIP_PATH='1'; PT_ALLOW_HASH_ONLY='1' } | Out-Null
        (Test-Path (Join-Path $script:Target 'ghostdraft.ps1')) | Should -BeTrue
        (Test-Path (Join-Path $script:Target 'ghostdraft.cmd')) | Should -BeTrue
    }

    It 'fails closed when the checksum does not match' {
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value ("0"*64 + "  ghostdraft.ps1")
        $code = Invoke-Install @{ GHOSTDRAFT_BASE_URL=$script:Release; GHOSTDRAFT_INSTALL_DIR=$script:Target; GHOSTDRAFT_SKIP_PATH='1'; PT_ALLOW_HASH_ONLY='1' }
        $code | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'ghostdraft.ps1')) | Should -BeFalse
    }

    It 'fails closed when SHA256SUMS lacks the ghostdraft.ps1 entry' {
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value ("deadbeef  somethingelse.txt")
        $code = Invoke-Install @{ GHOSTDRAFT_BASE_URL=$script:Release; GHOSTDRAFT_INSTALL_DIR=$script:Target; GHOSTDRAFT_SKIP_PATH='1'; PT_ALLOW_HASH_ONLY='1' }
        $code | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'ghostdraft.ps1')) | Should -BeFalse
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

    It 'never pipes the signed data into the verifier (bytes must reach it unchanged)' {
        # Конвейер PowerShell перекодирует текст (BOM, CRLF) и дописывает перевод строки, поэтому
        # верификатор увидел бы НЕ те байты, что подписаны: валидная подпись читается как
        # «incorrect signature», и fail-closed рубит установку с настоящего релиза. Так уже
        # ломался seedsplit. Канон — сырой поток файла в stdin через ProcessStartInfo.
        $src = Get-Content -Raw -LiteralPath $script:InstallScript
        $src | Should -Match 'ProcessStartInfo'
        $src | Should -Not -Match '(?m)Get-Content[^\r\n]*\|\s*&'
    }

    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("gd_sig_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Target  = Join-Path $script:Work 'target'
        New-Item -ItemType Directory -Path $script:Release -Force | Out-Null

        $payload = "Write-Output 'payload-ok'`n"
        $script:ScriptFile = Join-Path $script:Release 'ghostdraft.ps1'
        Set-Content -LiteralPath $script:ScriptFile -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $script:ScriptFile -Algorithm SHA256).Hash.ToLower()
        $script:Sums = Join-Path $script:Release 'SHA256SUMS'
        Set-Content -LiteralPath $script:Sums -Value "$hash  ghostdraft.ps1"

        # Тестовый ed25519-ключ + подпись SHA256SUMS (namespace 'file', как в release.yml).
        $script:Key = Join-Path $script:Work 'signing_key'
        # Windows PowerShell 5.1 теряет пустой аргумент при вызове нативной программы:
        # `-N ''` до ssh-keygen не доходит, тот уходит спрашивать парольную фразу, ключ
        # не создаётся и дальше падает Get-Content на .pub. В дочернем pwsh пустая строка
        # доезжает как есть.
        & pwsh -NoProfile -Command "& ssh-keygen -t ed25519 -N '' -C 'gd-test' -f '$($script:Key)'" *> $null
        Push-Location $script:Release
        & ssh-keygen -Y sign -f $script:Key -n file 'SHA256SUMS' *> $null
        Pop-Location
        # Публичный ключ БЕЗ комментария: 'ssh-ed25519 <base64>' (формат allowed_signers).
        $pubRaw = (Get-Content -LiteralPath "$($script:Key).pub" -Raw).Trim() -split '\s+'
        $script:PubKey = "$($pubRaw[0]) $($pubRaw[1])"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs when the release signature is valid' {
        Invoke-Install @{ GHOSTDRAFT_BASE_URL=$script:Release; GHOSTDRAFT_INSTALL_DIR=$script:Target; GHOSTDRAFT_SKIP_PATH='1'; GHOSTDRAFT_TEST_SIGNING_PUBKEY=$script:PubKey } | Out-Null
        (Test-Path (Join-Path $script:Target 'ghostdraft.ps1')) | Should -BeTrue
    }

    It 'fails closed when the signature is invalid/corrupt' {
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS.sig') -Value 'not-a-real-signature' -NoNewline
        $code = Invoke-Install @{ GHOSTDRAFT_BASE_URL=$script:Release; GHOSTDRAFT_INSTALL_DIR=$script:Target; GHOSTDRAFT_SKIP_PATH='1'; GHOSTDRAFT_TEST_SIGNING_PUBKEY=$script:PubKey }
        $code | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'ghostdraft.ps1')) | Should -BeFalse
    }

    It 'treats a bad signature as fatal even with PT_ALLOW_HASH_ONLY=1' {
        # Плохая подпись — активный признак подмены; hash-only её НЕ спасает.
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS.sig') -Value 'not-a-real-signature' -NoNewline
        $code = Invoke-Install @{ GHOSTDRAFT_BASE_URL=$script:Release; GHOSTDRAFT_INSTALL_DIR=$script:Target; GHOSTDRAFT_SKIP_PATH='1'; GHOSTDRAFT_TEST_SIGNING_PUBKEY=$script:PubKey; PT_ALLOW_HASH_ONLY='1' }
        $code | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'ghostdraft.ps1')) | Should -BeFalse
    }

    It 'fails closed when SHA256SUMS.sig is missing' {
        Remove-Item -LiteralPath (Join-Path $script:Release 'SHA256SUMS.sig') -Force
        $code = Invoke-Install @{ GHOSTDRAFT_BASE_URL=$script:Release; GHOSTDRAFT_INSTALL_DIR=$script:Target; GHOSTDRAFT_SKIP_PATH='1'; GHOSTDRAFT_TEST_SIGNING_PUBKEY=$script:PubKey }
        $code | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'ghostdraft.ps1')) | Should -BeFalse
    }

    It 'installs with PT_ALLOW_HASH_ONLY=1 when the signature is missing (hash-only)' {
        Remove-Item -LiteralPath (Join-Path $script:Release 'SHA256SUMS.sig') -Force
        Invoke-Install @{ GHOSTDRAFT_BASE_URL=$script:Release; GHOSTDRAFT_INSTALL_DIR=$script:Target; GHOSTDRAFT_SKIP_PATH='1'; GHOSTDRAFT_TEST_SIGNING_PUBKEY=$script:PubKey; PT_ALLOW_HASH_ONLY='1' } | Out-Null
        (Test-Path (Join-Path $script:Target 'ghostdraft.ps1')) | Should -BeTrue
    }

    It 'fails closed when ssh-keygen verifier is unavailable' {
        $code = Invoke-Install @{ GHOSTDRAFT_BASE_URL=$script:Release; GHOSTDRAFT_INSTALL_DIR=$script:Target; GHOSTDRAFT_SKIP_PATH='1'; GHOSTDRAFT_TEST_SIGNING_PUBKEY=$script:PubKey; GHOSTDRAFT_SSH_KEYGEN='gd-no-such-verifier' }
        $code | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'ghostdraft.ps1')) | Should -BeFalse
    }

    It 'installs with PT_ALLOW_HASH_ONLY=1 when the verifier is unavailable' {
        Invoke-Install @{ GHOSTDRAFT_BASE_URL=$script:Release; GHOSTDRAFT_INSTALL_DIR=$script:Target; GHOSTDRAFT_SKIP_PATH='1'; GHOSTDRAFT_TEST_SIGNING_PUBKEY=$script:PubKey; GHOSTDRAFT_SSH_KEYGEN='gd-no-such-verifier'; PT_ALLOW_HASH_ONLY='1' } | Out-Null
        (Test-Path (Join-Path $script:Target 'ghostdraft.ps1')) | Should -BeTrue
    }
}
