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

    It 'installs the launcher into lib\ and its .cmd shim next to the tools' {
        $umbrella = New-FakeClone -Root $script:Clone
        & $script:PwshExe -NoProfile -File $umbrella 1> $null 2> $null

        Test-Path -LiteralPath (Join-Path $script:Dest 'lib\paranoid.ps1') | Should -BeTrue
        $shim = Join-Path $script:Dest 'paranoid.cmd'
        Test-Path -LiteralPath $shim | Should -BeTrue
        (Get-Content -LiteralPath $shim -Raw) | Should -Match 'lib\\paranoid\.ps1'
    }

    It 'leaves no .ps1 on PATH, so a bare `paranoid` resolves to the shim' {
        # The whole point of lib\: PowerShell resolves a bare command name to a .ps1 in a
        # PATH directory BEFORE a .cmd of the same name, and then the default ExecutionPolicy
        # refuses to load it. A .ps1 here means the command is broken for the user.
        $umbrella = New-FakeClone -Root $script:Clone
        & $script:PwshExe -NoProfile -File $umbrella 1> $null 2> $null

        @(Get-ChildItem -LiteralPath $script:Dest -Filter *.ps1 -File) | Should -HaveCount 0
    }

    It 'runs the launcher through pwsh with the ExecutionPolicy bypassed for that process' {
        # Without the bypass the shim still fails on a machine left at Restricted, which is
        # the Windows default - the user would have to change a security setting to run us.
        $umbrella = New-FakeClone -Root $script:Clone
        & $script:PwshExe -NoProfile -File $umbrella 1> $null 2> $null

        (Get-Content -LiteralPath (Join-Path $script:Dest 'paranoid.cmd') -Raw) |
            Should -Match '-ExecutionPolicy Bypass'
    }

    It 'removes a pre-lib launcher left next to the shim' {
        # An upgrade over an older install must take that copy away: PowerShell would keep
        # picking it over the shim, and the user would see no change at all.
        New-Item -ItemType Directory -Path $script:Dest -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Dest 'paranoid.ps1') -Value '# old layout'
        $umbrella = New-FakeClone -Root $script:Clone

        & $script:PwshExe -NoProfile -File $umbrella 1> $null 2> $null

        Test-Path -LiteralPath (Join-Path $script:Dest 'paranoid.ps1') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Dest 'lib\paranoid.ps1') | Should -BeTrue
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

    It 'takes back exactly what it installed when run with -Uninstall' {
        # Removal parity with `bash install.sh --uninstall` on macOS: without it a Windows
        # user has to edit their own PATH by hand to get rid of the toolkit.
        $umbrella = New-FakeClone -Root $script:Clone
        New-Item -ItemType Directory -Path $script:Dest -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Dest 'lib') -Force | Out-Null
        foreach ($name in @('securetrash', 'vaultwatch', 'panic', 'ghostdraft', 'seedsplit', 'paranoid')) {
            Set-Content -LiteralPath (Join-Path $script:Dest "lib\$name.ps1") -Value '# installed'
            Set-Content -LiteralPath (Join-Path $script:Dest "$name.cmd") -Value '@echo off'
        }

        & $script:PwshExe -NoProfile -File $umbrella -Uninstall 1> $null 2> $null
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath $script:Dest | Should -BeFalse
    }

    It 'leaves a non-empty directory (and anything of the user in it) alone on -Uninstall' {
        $umbrella = New-FakeClone -Root $script:Clone
        New-Item -ItemType Directory -Path $script:Dest -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Dest 'securetrash.ps1') -Value '# installed'
        $mine = Join-Path $script:Dest 'notes.txt'
        Set-Content -LiteralPath $mine -Value 'not ours'

        & $script:PwshExe -NoProfile -File $umbrella -Uninstall 1> $null 2> $null
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:Dest 'securetrash.ps1') | Should -BeFalse
        Test-Path -LiteralPath $mine | Should -BeTrue
    }

    It 'says so and exits clean when there is nothing to uninstall' {
        $umbrella = New-FakeClone -Root $script:Clone

        & $script:PwshExe -NoProfile -File $umbrella -Uninstall 1> $null 2> $null
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

# What makes `paranoid` (or any of the five) answer at all in a terminal. Two Windows rules
# decide it, and both bite silently: PowerShell resolves a bare command name to a .ps1 in a
# PATH directory BEFORE a .cmd of the same name, and the default ExecutionPolicy (Restricted)
# refuses to load a .ps1 at all. So the script must NOT sit on PATH, and the shim that does
# must start pwsh with the policy bypassed for its own process. Checked across all six
# installers at once: each one writes its own shim, and one of them drifting is the bug.
Describe 'the shim contract, in every installer' {
    # A plain assignment, not BeforeAll: Pester expands -ForEach during discovery, when
    # nothing from a BeforeAll block has run yet. The two phases have separate scopes, so
    # $RepoRoot is resolved again inside BeforeAll rather than handed over from here.
    $Installers = @('windows\install.ps1') + @(
        'securetrash', 'vaultwatch', 'panic', 'ghostdraft', 'seedsplit' |
            ForEach-Object { "$_\windows\install.ps1" }
    )
    BeforeAll { $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

    It '<_> writes a shim that points into lib\ and bypasses the ExecutionPolicy' -ForEach $Installers {
        $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot $_) -Raw
        $text | Should -Match 'pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\\'
    }

    It '<_> takes away a pre-lib script left next to the shim' -ForEach $Installers {
        # Without this an upgrade over an older install is invisible: the old .ps1 keeps
        # winning the name, and the user still cannot run the tool.
        $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot $_) -Raw
        $text | Should -Match 'Remove-Item -LiteralPath \$legacy'
    }

    It 'ships install.cmd, so installing needs no knowledge of pwsh or of the policy' {
        $cmd = Join-Path $script:RepoRoot 'windows\install.cmd'
        Test-Path -LiteralPath $cmd | Should -BeTrue
        $text = Get-Content -LiteralPath $cmd -Raw
        $text | Should -Match 'pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install\.ps1"'
        # No pwsh must not look like a broken installer: it must name the one command to run.
        $text | Should -Match 'winget install --id Microsoft\.PowerShell'
    }
}
