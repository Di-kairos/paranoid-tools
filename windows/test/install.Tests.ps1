# Pester 5 — install.ps1 (Windows-порт vaultwatch). Integrity-gate без сети:
# VAULTWATCH_BASE_URL → локальный каталог-«релиз», установка во временный каталог,
# правка PATH отключена. Покрытие: happy-path, провал на расхождении хеша, провал
# при отсутствии записи в SHA256SUMS (fail-closed).

BeforeAll {
    $script:InstallScript = Join-Path $PSScriptRoot '..\install.ps1'
}

Describe 'install.ps1 integrity gate' {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("vw_inst_" + [Guid]::NewGuid().ToString('N'))
        $script:Release = Join-Path $script:Work 'release'
        $script:Target  = Join-Path $script:Work 'target'
        New-Item -ItemType Directory -Path $script:Release -Force | Out-Null

        $payload = "Write-Output 'payload-ok'`n"
        $script:ScriptFile = Join-Path $script:Release 'vaultwatch.ps1'
        Set-Content -LiteralPath $script:ScriptFile -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $script:ScriptFile -Algorithm SHA256).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  vaultwatch.ps1"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs the script when the checksum matches' {
        # PT_ALLOW_HASH_ONLY=1: локальный «релиз» без Ed25519-подписи — этот тест проверяет
        # именно integrity-гейт (проверка подписи покрыта отдельным Describe ниже).
        & pwsh -NoProfile -Command "`$env:PT_ALLOW_HASH_ONLY='1'; `$env:VAULTWATCH_BASE_URL='$($script:Release)'; `$env:VAULTWATCH_INSTALL_DIR='$($script:Target)'; `$env:VAULTWATCH_SKIP_PATH='1'; & '$($script:InstallScript)'" *> $null
        (Test-Path (Join-Path $script:Target 'vaultwatch.ps1')) | Should -BeTrue
        (Test-Path (Join-Path $script:Target 'vaultwatch.cmd')) | Should -BeTrue
    }

    It 'fails closed when the checksum does not match' {
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value ("0"*64 + "  vaultwatch.ps1")
        & pwsh -NoProfile -Command "`$env:VAULTWATCH_BASE_URL='$($script:Release)'; `$env:VAULTWATCH_INSTALL_DIR='$($script:Target)'; `$env:VAULTWATCH_SKIP_PATH='1'; & '$($script:InstallScript)'" *> $null
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'vaultwatch.ps1')) | Should -BeFalse
    }

    It 'fails closed when SHA256SUMS lacks the vaultwatch.ps1 entry' {
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value ("deadbeef  somethingelse.txt")
        & pwsh -NoProfile -Command "`$env:VAULTWATCH_BASE_URL='$($script:Release)'; `$env:VAULTWATCH_INSTALL_DIR='$($script:Target)'; `$env:VAULTWATCH_SKIP_PATH='1'; & '$($script:InstallScript)'" *> $null
        $LASTEXITCODE | Should -Not -Be 0
        (Test-Path (Join-Path $script:Target 'vaultwatch.ps1')) | Should -BeFalse
    }
}

# Порт Ed25519-проверки подписи из install.sh (P1-2). Дот-сорсим install.ps1 под
# VAULTWATCH_NO_MAIN=1 (определяет функции, не запуская установку) и мокаем внешние примитивы:
# Get-VwVerifier (наличие ssh-keygen), Get-ReleaseFile (загрузка .sig), Invoke-VwVerifier
# (ssh-keygen -Y verify). Покрытие: valid / invalid / missing-sig / missing-verifier + fail-closed.
Describe 'install.ps1 signature verification (P1-2)' {
    BeforeAll {
        $env:VAULTWATCH_NO_MAIN = '1'
        # LOCALAPPDATA нет на macOS-хосте → задаём InstallDir явно, иначе config-блок падает на Join-Path.
        $env:VAULTWATCH_INSTALL_DIR = Join-Path ([System.IO.Path]::GetTempPath()) 'vw_sig_noop'
        . (Join-Path $PSScriptRoot '..\install.ps1')
        Remove-Item Env:\VAULTWATCH_NO_MAIN -ErrorAction SilentlyContinue
        Remove-Item Env:\VAULTWATCH_INSTALL_DIR -ErrorAction SilentlyContinue
    }
    AfterAll {
        Remove-Item Env:\VAULTWATCH_NO_MAIN -ErrorAction SilentlyContinue
        Remove-Item Env:\VAULTWATCH_INSTALL_DIR -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("vw_sig_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Tmp 'SHA256SUMS') -Value 'deadbeef  vaultwatch.ps1'
        Remove-Item Env:\PT_ALLOW_HASH_ONLY -ErrorAction SilentlyContinue
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\PT_ALLOW_HASH_ONLY -ErrorAction SilentlyContinue
    }

    It 'passes when the signature is valid' {
        Mock -CommandName Get-VwVerifier   -MockWith { 'ssh-keygen' }
        Mock -CommandName Get-ReleaseFile  -MockWith { param($Name, $OutFile) Set-Content -LiteralPath $OutFile -Value 'sig' }
        Mock -CommandName Invoke-VwVerifier -MockWith { 0 }
        { Assert-VwSignature -Tmp $script:Tmp } | Should -Not -Throw
        Should -Invoke Invoke-VwVerifier -Times 1 -Exactly
    }

    It 'writes allowed_signers with the pinned pubkey and principal' {
        Mock -CommandName Get-VwVerifier   -MockWith { 'ssh-keygen' }
        Mock -CommandName Get-ReleaseFile  -MockWith { param($Name, $OutFile) Set-Content -LiteralPath $OutFile -Value 'sig' }
        Mock -CommandName Invoke-VwVerifier -MockWith { 0 }
        Assert-VwSignature -Tmp $script:Tmp
        $al = Get-Content -LiteralPath (Join-Path $script:Tmp 'allowed_signers') -Raw
        $al | Should -Match 'releases@paranoid-tools'
        $al | Should -Match 'namespaces="file"'
        $al | Should -Match ([regex]::Escape('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U'))
    }

    It 'fails closed on an invalid signature (PT_ALLOW_HASH_ONLY does NOT bypass)' {
        Mock -CommandName Get-VwVerifier   -MockWith { 'ssh-keygen' }
        Mock -CommandName Get-ReleaseFile  -MockWith { param($Name, $OutFile) Set-Content -LiteralPath $OutFile -Value 'sig' }
        Mock -CommandName Invoke-VwVerifier -MockWith { 1 }
        { Assert-VwSignature -Tmp $script:Tmp } | Should -Throw
        $env:PT_ALLOW_HASH_ONLY = '1'
        { Assert-VwSignature -Tmp $script:Tmp } | Should -Throw
    }

    It 'fails closed when the signature is missing' {
        Mock -CommandName Get-VwVerifier  -MockWith { 'ssh-keygen' }
        Mock -CommandName Get-ReleaseFile -MockWith { throw 'not found' }
        { Assert-VwSignature -Tmp $script:Tmp } | Should -Throw
    }

    It 'allows hash-only when the signature is missing and PT_ALLOW_HASH_ONLY=1' {
        Mock -CommandName Get-VwVerifier  -MockWith { 'ssh-keygen' }
        Mock -CommandName Get-ReleaseFile -MockWith { throw 'not found' }
        $env:PT_ALLOW_HASH_ONLY = '1'
        { Assert-VwSignature -Tmp $script:Tmp } | Should -Not -Throw
    }

    It 'fails closed when the verifier (ssh-keygen) is missing' {
        Mock -CommandName Get-VwVerifier -MockWith { $null }
        { Assert-VwSignature -Tmp $script:Tmp } | Should -Throw
    }

    It 'allows hash-only when the verifier is missing and PT_ALLOW_HASH_ONLY=1' {
        Mock -CommandName Get-VwVerifier -MockWith { $null }
        $env:PT_ALLOW_HASH_ONLY = '1'
        { Assert-VwSignature -Tmp $script:Tmp } | Should -Not -Throw
    }
}
