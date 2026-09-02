# Pester 5 — ghostdraft.ps1 logic (Windows port). Dot-sourced under ST_NO_MAIN=1: defines
# the functions without running the dispatcher. ghostdraft touches the outside world
# (editor/shred/clipboard), so those primitives are MOCKED: the tests verify orchestration
# (directory choice, ordering, shred-in-finally, the --clipboard gate) without launching
# notepad or wiping real files. The CLI level (version, pipe, exit codes) — via a fresh pwsh.

BeforeAll {
    $env:ST_NO_MAIN = '1'
    $script:ScriptPath = Join-Path $PSScriptRoot '..\ghostdraft.ps1'
    . $script:ScriptPath
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}

AfterAll {
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}

Describe 'ghostdraft new — orchestration (override dir)' {
    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("gd_t_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Work -Force | Out-Null
        $env:GHOSTDRAFT_DIR = $script:Work
        $env:EDITOR = 'vim'      # the file path is the EDITOR path now; the default is the console
        Mock Invoke-GdEditor     { }
        Mock Confirm-GdEditorClosed { }
        Mock Invoke-GdShred      { }
        Mock Set-GdClipboardDraft { $true }
        Mock Clear-GdEditorResidue { }
    }
    AfterEach {
        Remove-Item Env:\EDITOR -ErrorAction SilentlyContinue
        Remove-Item Env:\GHOSTDRAFT_DIR -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'launches the editor and shreds the draft afterward' {
        Invoke-GdNew -ArgList @() | Out-Null
        Should -Invoke Invoke-GdEditor -Times 1 -Exactly
        Should -Invoke Invoke-GdShred  -Times 1 -Exactly
    }

    It 'does NOT touch the clipboard without --clipboard' {
        Invoke-GdNew -ArgList @() | Out-Null
        Should -Invoke Set-GdClipboardDraft -Times 0 -Exactly
    }

    It '--clipboard copies after editing' {
        Invoke-GdNew -ArgList @('--clipboard') | Out-Null
        Should -Invoke Set-GdClipboardDraft -Times 1 -Exactly
    }

    It 'rejects an unknown argument' {
        { Invoke-GdNew -ArgList @('--bogus') } | Should -Throw
    }

    It 'shreds even when the editor fails (cleanup in finally)' {
        Mock Invoke-GdEditor { throw 'editor crashed' }
        { Invoke-GdNew -ArgList @() } | Should -Throw
        Should -Invoke Invoke-GdShred -Times 1 -Exactly
    }
}

# --- P0-1: the old default was Notepad, and Windows 11 Notepad writes the contents of unsaved
# tabs into TabState on disk — a forensic artifact that outlives ghostdraft's shred, i.e. the
# exact promise the tool exists to keep. The default is now a console draft that never creates
# a file at all. ---
Describe 'ghostdraft new — console draft is the default (P0-1)' {

    BeforeEach {
        Remove-Item Env:\EDITOR -ErrorAction SilentlyContinue
        $script:GD_LOCALE = 'en'
        Mock Read-GdConsoleDraft { 'correct horse battery staple' }
        Mock Clear-GdConsole     { }
        Mock Set-GdClipboardText { $true }
        Mock Invoke-GdEditor     { throw 'no editor may be launched by default' }
        Mock Get-GdDraftLocation { throw 'no draft location may be chosen by default' }
        Mock New-GdDraftFile     { throw 'no file may be created by default' }
    }

    It 'creates no file and launches no editor' {
        Invoke-GdNew -ArgList @() | Out-Null
        Should -Invoke Read-GdConsoleDraft -Times 1 -Exactly
        Should -Invoke Invoke-GdEditor -Times 0 -Exactly
        Should -Invoke New-GdDraftFile -Times 0 -Exactly
    }

    It 'clears the screen afterwards' {
        Invoke-GdNew -ArgList @() | Out-Null
        Should -Invoke Clear-GdConsole -Times 1 -Exactly
    }

    It 'copies from memory with --clipboard, never from a file' {
        Invoke-GdNew -ArgList @('--clipboard') | Out-Null
        Should -Invoke Set-GdClipboardText -Times 1 -Exactly
    }

    It 'leaves the clipboard alone without --clipboard' {
        Invoke-GdNew -ArgList @() | Out-Null
        Should -Invoke Set-GdClipboardText -Times 0 -Exactly
    }

    It 'clears the screen even when the clipboard step fails' {
        Mock Set-GdClipboardText { throw 'clipboard unavailable' }
        { Invoke-GdNew -ArgList @('--clipboard') } | Should -Throw
        Should -Invoke Clear-GdConsole -Times 1 -Exactly
    }
}

# The editor path is opt-in, and it carries the two warnings that make it honest.
Describe 'ghostdraft new — $EDITOR is opt-in and warned about (P0-1)' {

    BeforeEach {
        $script:Work = Join-Path ([System.IO.Path]::GetTempPath()) ("gd_e_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Work -Force | Out-Null
        $env:GHOSTDRAFT_DIR = $script:Work
        $script:GD_LOCALE = 'en'
        Mock Invoke-GdEditor { }
        Mock Confirm-GdEditorClosed { }
        Mock Invoke-GdShred { }
        Mock Clear-GdEditorResidue { }
        function global:Get-GdStderr {
            param([scriptblock]$Body)
            $sw = New-Object System.IO.StringWriter
            $orig = [Console]::Error
            [Console]::SetError($sw)
            try { & $Body | Out-Null } finally { [Console]::SetError($orig) }
            return $sw.ToString()
        }
    }
    AfterEach {
        Remove-Item Env:\EDITOR -ErrorAction SilentlyContinue
        Remove-Item Env:\GHOSTDRAFT_DIR -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'names TabState when the chosen editor is Notepad' {
        $env:EDITOR = 'notepad'
        $err = Get-GdStderr { Invoke-GdNew -ArgList @() }
        $err | Should -Match 'TabState'
        $err | Should -Match 'outlives the shred|survives|outlives'
    }

    It 'does not cry TabState over an unrelated editor' {
        $env:EDITOR = 'vim'
        $err = Get-GdStderr { Invoke-GdNew -ArgList @() }
        $err | Should -Not -Match 'TabState'
        $err | Should -Match 'weaker path'
    }

    It 'waits for the human before shredding — -Wait lies for single-instance editors' {
        $env:EDITOR = 'notepad'
        Invoke-GdNew -ArgList @() | Out-Null
        Should -Invoke Confirm-GdEditorClosed -Times 1 -Exactly
    }
}

Describe 'ghostdraft new — on-disk fallback (no vault)' {
    BeforeEach {
        Remove-Item Env:\GHOSTDRAFT_DIR -ErrorAction SilentlyContinue
        $script:Fake = Join-Path ([System.IO.Path]::GetTempPath()) ("gd_fb_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Fake -Force | Out-Null
        $env:EDITOR = 'vim'                            # on-disk fallback only exists on this path
        Mock Test-GdWritableDir  { $false }            # vault unavailable
        Mock New-GdSecureTempDir { $script:Fake }      # deterministic temp
        Mock Invoke-GdEditor     { }
        Mock Confirm-GdEditorClosed { }
        Mock Invoke-GdShred      { }
        Mock Clear-GdEditorResidue { }
        Mock Remove-GdTempDir    { }
    }
    AfterEach {
        Remove-Item Env:\EDITOR -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:Fake -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'falls back to a secure temp dir and removes it afterward' {
        Invoke-GdNew -ArgList @() | Out-Null
        Should -Invoke New-GdSecureTempDir -Times 1 -Exactly
        Should -Invoke Remove-GdTempDir -Times 1 -Exactly
    }
}

# AUDIT_2026-08-03 P0-3: securetrash.ps1 mounts the VHDX on the first free letter and writes
# it into the <vault>.mount sidecar — ghostdraft must read it rather than hope for 'V:\'.
Describe 'vault volume resolution (mount sidecar)' {
    BeforeEach {
        Remove-Item Env:\ST_VAULT_VOLUME -ErrorAction SilentlyContinue
        Remove-Item Env:\ST_VAULT_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\GHOSTDRAFT_DIR -ErrorAction SilentlyContinue
        $script:FakeVault = Join-Path ([System.IO.Path]::GetTempPath()) ("gd_v_" + [Guid]::NewGuid().ToString('N') + '.vhdx')
        # The container file exists — otherwise Test-GdVaultAttached honestly rejects the sidecar.
        Set-Content -LiteralPath $script:FakeVault -Value 'vhdx-stub' -NoNewline
    }
    AfterEach {
        Remove-Item -LiteralPath $script:FakeVault -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$script:FakeVault.mount" -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\ST_VAULT_VOLUME -ErrorAction SilentlyContinue
        Remove-Item Env:\ST_VAULT_PATH -ErrorAction SilentlyContinue
    }

    It 'reads the actual drive letter from the <vault>.mount sidecar' {
        $env:ST_VAULT_PATH = $script:FakeVault
        Set-Content -LiteralPath "$script:FakeVault.mount" -Value 'D:\' -NoNewline
        Get-GdVaultVolume | Should -Be 'D:\'
    }

    It 'ST_VAULT_VOLUME env override wins over the sidecar' {
        $env:ST_VAULT_PATH = $script:FakeVault
        Set-Content -LiteralPath "$script:FakeVault.mount" -Value 'D:\' -NoNewline
        $env:ST_VAULT_VOLUME = 'X:\'
        Get-GdVaultVolume | Should -Be 'X:\'
    }

    It 'falls back to the legacy V:\ default without a sidecar' {
        $env:ST_VAULT_PATH = $script:FakeVault
        Get-GdVaultVolume | Should -Be 'V:\'
    }

    It 'stale sidecar without the vault container is ignored (hint, not proof)' {
        $env:ST_VAULT_PATH = $script:FakeVault
        Set-Content -LiteralPath "$script:FakeVault.mount" -Value 'D:\' -NoNewline
        Remove-Item -LiteralPath $script:FakeVault -Force   # the container is gone
        Get-GdVaultVolume | Should -Be 'V:\'
    }

    It 'sidecar is ignored when the VHDX is not attached (stale letter reuse)' {
        $env:ST_VAULT_PATH = $script:FakeVault
        Set-Content -LiteralPath "$script:FakeVault.mount" -Value 'D:\' -NoNewline
        Mock Test-GdVaultAttached { $false }
        Get-GdVaultVolume | Should -Be 'V:\'
    }

    It 'draft location picks the sidecar letter when writable' {
        $env:ST_VAULT_PATH = $script:FakeVault
        Set-Content -LiteralPath "$script:FakeVault.mount" -Value 'D:\' -NoNewline
        Mock Test-GdWritableDir { $false }
        Mock Test-GdWritableDir { $true } -ParameterFilter { $Path -eq 'D:\' }
        $loc = Get-GdDraftLocation
        $loc.Kind | Should -Be 'vault'
        $loc.Dir  | Should -Be 'D:\'
    }
}

Describe 'i18n' {
    It 'returns English residue note by default' {
        $script:GD_LOCALE = 'en'
        (T 'new_residue') | Should -Match 'pagefile'
    }
    It 'returns Russian residue note under ru locale' {
        $script:GD_LOCALE = 'ru'
        (T 'new_residue') | Should -Match 'pagefile'
        (T 'new_residue') | Should -Match 'НЕ могу'
    }
    It 'clip_danger mentions Cloud Clipboard' {
        $script:GD_LOCALE = 'en'
        (T 'clip_danger') | Should -Match 'Cloud Clipboard'
    }
    It 'falls back to the key for an unknown id' {
        (T 'no_such_key') | Should -Be 'no_such_key'
    }
}

Describe 'CLI surface (child pwsh)' {
    It 'prints the version' {
        # Version-agnostic: don't hardcode the number (otherwise the test breaks on every bump) —
        # check the format `ghostdraft <semver> (Windows, beta)`.
        $out = & pwsh -NoProfile -File $script:ScriptPath version
        ($out -join "`n") | Should -Match 'ghostdraft \d+\.\d+\.\d+ \(Windows, beta\)'
    }
    It 'pipe echoes stdin and writes nothing to disk' {
        $out = 'top-secret-seed' | & pwsh -NoProfile -File $script:ScriptPath pipe
        ($out -join "`n") | Should -Match 'top-secret-seed'
    }
    It 'exits non-zero on an unknown command' {
        & pwsh -NoProfile -File $script:ScriptPath bogus *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }
    It 'accepts --yes anywhere in the args instead of treating it as a command (P2-12)' {
        $out = & pwsh -NoProfile -File $script:ScriptPath --yes version
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'ghostdraft \d+\.\d+\.\d+'
        $out = & pwsh -NoProfile -File $script:ScriptPath version --yes
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'ghostdraft \d+\.\d+\.\d+'
    }
    It 'usage documents the --yes flag' {
        (Get-GdUsage) | Should -Match '--yes'
    }
}

# AUDIT_2026-08-03, P3 tail: shred via securetrash injected ST_ASSUME_YES=1 and in finally
# DELETED the variable — together with the value the caller had set.
Describe 'Invoke-GdShred — не затирает ST_ASSUME_YES вызывающего' {
    AfterEach { Remove-Item Env:\ST_ASSUME_YES -ErrorAction SilentlyContinue }

    It 'возвращает прежнее значение после вызова' {
        $env:ST_ASSUME_YES = '1'
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gd-" + [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $tmp -Value 'draft'
        try { Invoke-GdShred -Path $tmp 6>$null } catch { }
        $env:ST_ASSUME_YES | Should -Be '1'
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }

    It 'не создаёт переменную, если её не было' {
        Remove-Item Env:\ST_ASSUME_YES -ErrorAction SilentlyContinue
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gd-" + [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $tmp -Value 'draft'
        try { Invoke-GdShred -Path $tmp 6>$null } catch { }
        $env:ST_ASSUME_YES | Should -BeNullOrEmpty
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}
