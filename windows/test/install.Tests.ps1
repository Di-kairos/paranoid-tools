# Pester 5 — the orchestration of the umbrella windows/install.ps1.
#
# The umbrella installs nothing itself: it hands each per-tool installer a shared directory,
# switches its PATH edit off, and turns its exit code into the run's verdict. So the fixture is
# a FAKE clone — five per-tool `install.ps1` stubs that only record the env they were given —
# and the tests assert exactly that contract. The signature/checksum chain lives in the per-tool
# installers and is tested there (e.g. securetrash/windows/test/install.Tests.ps1).

BeforeAll {
    $script:RealUmbrella = Join-Path $PSScriptRoot '..\install.ps1'
    $script:PwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    # The per-tool env prefixes are NOT uniform — that mapping is the thing worth testing.
    $script:ToolPrefixes = [ordered]@{
        securetrash = 'ST'
        vaultwatch  = 'VAULTWATCH'
        panic       = 'PANIC'
        ghostdraft  = 'GHOSTDRAFT'
        seedsplit   = 'SEEDSPLIT'
    }

    # Builds a fake clone under $Root and returns the path to the umbrella copied into it.
    # $FailTool — that tool's stub exits 1; $OmitTools — those stubs are not created at all.
    function New-FakeClone {
        param(
            [Parameter(Mandatory)][string]$Root,
            [string]$FailTool = '',
            [string[]]$OmitTools = @()
        )
        foreach ($name in $script:ToolPrefixes.Keys) {
            if ($OmitTools -contains $name) { continue }
            $dir = Join-Path $Root (Join-Path $name 'windows')
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $prefix = $script:ToolPrefixes[$name]
            $code = if ($name -eq $FailTool) { 1 } else { 0 }
            $body = @"
`$log = Join-Path `$env:UMB_TEST_LOG '$name.txt'
Set-Content -LiteralPath `$log -Value "`$env:${prefix}_INSTALL_DIR|`$env:${prefix}_SKIP_PATH"
exit $code
"@
            Set-Content -LiteralPath (Join-Path $dir 'install.ps1') -Value $body
        }
        $win = Join-Path $Root 'windows'
        New-Item -ItemType Directory -Path $win -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $win 'paranoid.ps1') -Value "Write-Host 'fake launcher'"
        Copy-Item -LiteralPath $script:RealUmbrella -Destination (Join-Path $win 'install.ps1') -Force
        return (Join-Path $win 'install.ps1')
    }
}

Describe 'windows/install.ps1 (umbrella)' {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("pt_umb_" + [Guid]::NewGuid().ToString('N'))
        $script:Clone = Join-Path $script:Work 'clone'
        $script:Dest  = Join-Path $script:Work 'dest'
        $script:Log   = Join-Path $script:Work 'log'
        New-Item -ItemType Directory -Path $script:Log -Force | Out-Null
        $env:PT_INSTALL_DIR = $script:Dest
        $env:PT_SKIP_PATH   = '1'
        $env:UMB_TEST_LOG   = $script:Log
    }

    AfterEach {
        Remove-Item Env:\PT_INSTALL_DIR, Env:\PT_SKIP_PATH, Env:\UMB_TEST_LOG, Env:\PT_ALLOW_PARTIAL `
            -ErrorAction SilentlyContinue
        Remove-Item -Path $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'runs all five installers, all pointed at one directory with their PATH edit off' {
        $umbrella = New-FakeClone -Root $script:Clone
        $pathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')

        & $script:PwshExe -NoProfile -File $umbrella 1> $null 2> $null
        $LASTEXITCODE | Should -Be 0

        foreach ($name in $script:ToolPrefixes.Keys) {
            $log = Join-Path $script:Log "$name.txt"
            Test-Path -LiteralPath $log | Should -BeTrue -Because "$name must have been installed"
            (Get-Content -LiteralPath $log -Raw).Trim() | Should -Be "$($script:Dest)|1"
        }
        # PT_SKIP_PATH=1 must be honoured: the user PATH is not a test fixture.
        [Environment]::GetEnvironmentVariable('Path', 'User') | Should -Be $pathBefore
    }

    It 'installs the launcher and its .cmd shim next to the tools' {
        $umbrella = New-FakeClone -Root $script:Clone
        & $script:PwshExe -NoProfile -File $umbrella 1> $null 2> $null

        Test-Path -LiteralPath (Join-Path $script:Dest 'paranoid.ps1') | Should -BeTrue
        $shim = Join-Path $script:Dest 'paranoid.cmd'
        Test-Path -LiteralPath $shim | Should -BeTrue
        (Get-Content -LiteralPath $shim -Raw) | Should -Match 'paranoid\.ps1'
    }

    It 'exits non-zero when one tool refuses, and still installs the other four' {
        # A fail-closed refusal in one installer (bad signature, no network) must not be
        # reported as a successful ecosystem install.
        $umbrella = New-FakeClone -Root $script:Clone -FailTool 'panic'

        & $script:PwshExe -NoProfile -File $umbrella 1> $null 2> $null
        $LASTEXITCODE | Should -Not -Be 0

        foreach ($name in @('securetrash', 'vaultwatch', 'ghostdraft', 'seedsplit')) {
            Test-Path -LiteralPath (Join-Path $script:Log "$name.txt") | Should -BeTrue
        }
    }

    It 'accepts a partial install only under PT_ALLOW_PARTIAL=1' {
        $umbrella = New-FakeClone -Root $script:Clone -FailTool 'panic'
        $env:PT_ALLOW_PARTIAL = '1'

        & $script:PwshExe -NoProfile -File $umbrella 1> $null 2> $null
        $LASTEXITCODE | Should -Be 0
    }

    It 'skips a missing per-tool installer instead of dying on it' {
        # An incomplete clone (or a tool added later) must not abort the whole run.
        $umbrella = New-FakeClone -Root $script:Clone -OmitTools @('seedsplit')

        & $script:PwshExe -NoProfile -File $umbrella 1> $null 2> $null
        $LASTEXITCODE | Should -Not -Be 0

        foreach ($name in @('securetrash', 'vaultwatch', 'panic', 'ghostdraft')) {
            Test-Path -LiteralPath (Join-Path $script:Log "$name.txt") | Should -BeTrue
        }
        Test-Path -LiteralPath (Join-Path $script:Log 'seedsplit.txt') | Should -BeFalse
    }
}
