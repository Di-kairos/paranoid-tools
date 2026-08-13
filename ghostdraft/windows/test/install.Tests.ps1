# Pester 5 — install.ps1 (Windows port of ghostdraft). We verify the integrity gate + signature
# gate without the network: GHOSTDRAFT_BASE_URL points at a local "release" directory, installation
# goes into a temp directory, PATH editing is disabled. Coverage: happy path, failure on hash
# mismatch, failure when the SHA256SUMS entry is missing, and the full release-signature set (fail-closed).

BeforeAll {
    $script:InstallScript = Join-Path $PSScriptRoot '..\install.ps1'

    # Run install.ps1 in a child pwsh with the given environment. Returns $LASTEXITCODE.
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

        # The payload "script" + a correct SHA256SUMS.
        $payload = "Write-Output 'payload-ok'`n"
        $script:ScriptFile = Join-Path $script:Release 'ghostdraft.ps1'
        Set-Content -LiteralPath $script:ScriptFile -Value $payload -NoNewline
        $hash = (Get-FileHash -Path $script:ScriptFile -Algorithm SHA256).Hash.ToLower()
        Set-Content -LiteralPath (Join-Path $script:Release 'SHA256SUMS') -Value "$hash  ghostdraft.ps1"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    # These tests check the hash gate, not the signature → PT_ALLOW_HASH_ONLY=1 (release without .sig).
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
        # `ArgumentList` exists only in .NET Core (PowerShell 7). Windows PowerShell 5.1 is
        # the stock Windows shell and exactly the one people run the README one-liner in;
        # without the fallback path the install would fail at the signature-verification step.
        $src = Get-Content -Raw -LiteralPath $script:InstallScript
        $src | Should -Match "PSObject\.Properties\.Name -contains 'ArgumentList'"
        $src | Should -Match '\$psi\.Arguments ='
    }

    It 'never pipes the signed data into the verifier (bytes must reach it unchanged)' {
        # The PowerShell pipeline re-encodes text (BOM, CRLF) and appends a newline, so the
        # verifier would see bytes DIFFERENT from what was signed: a valid signature reads as
        # "incorrect signature", and fail-closed kills an install from a genuine release. This
        # already broke seedsplit. The canon — the file's raw stream into stdin via ProcessStartInfo.
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

        # Test ed25519 key + SHA256SUMS signature (namespace 'file', as in release.yml).
        $script:Key = Join-Path $script:Work 'signing_key'
        # Windows PowerShell 5.1 drops an empty argument when calling a native program:
        # `-N ''` never reaches ssh-keygen, which goes off to prompt for a passphrase, the key
        # is not created and Get-Content then fails on the .pub. In a child pwsh the empty
        # string arrives as is.
        & pwsh -NoProfile -Command "& ssh-keygen -t ed25519 -N '' -C 'gd-test' -f '$($script:Key)'" *> $null
        Push-Location $script:Release
        & ssh-keygen -Y sign -f $script:Key -n file 'SHA256SUMS' *> $null
        Pop-Location
        # Public key WITHOUT the comment: 'ssh-ed25519 <base64>' (allowed_signers format).
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
        # A bad signature is an active sign of tampering; hash-only does NOT excuse it.
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
