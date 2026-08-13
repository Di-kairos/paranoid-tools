# Pester 5 — логика ghostdraft.ps1 (Windows-порт). Дот-сорс под ST_NO_MAIN=1: определяет
# функции, не запуская диспетчер. ghostdraft трогает внешний мир (editor/shred/clipboard),
# поэтому эти примитивы МОКАЮТСЯ: тест проверяет оркестровку (выбор каталога, порядок,
# shred-в-finally, --clipboard-гейт), не запуская notepad и не стирая реальные файлы.
# CLI-уровень (version, pipe, exit-коды) — через свежий pwsh.

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
        Mock Invoke-GdEditor     { }
        Mock Invoke-GdShred      { }
        Mock Set-GdClipboardDraft { $true }
        Mock Clear-GdEditorResidue { }
    }
    AfterEach {
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

Describe 'ghostdraft new — on-disk fallback (no vault)' {
    BeforeEach {
        Remove-Item Env:\GHOSTDRAFT_DIR -ErrorAction SilentlyContinue
        $script:Fake = Join-Path ([System.IO.Path]::GetTempPath()) ("gd_fb_" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Fake -Force | Out-Null
        Mock Test-GdWritableDir  { $false }            # vault недоступен
        Mock New-GdSecureTempDir { $script:Fake }      # детерминированный temp
        Mock Invoke-GdEditor     { }
        Mock Invoke-GdShred      { }
        Mock Clear-GdEditorResidue { }
        Mock Remove-GdTempDir    { }
    }
    AfterEach {
        Remove-Item -LiteralPath $script:Fake -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'falls back to a secure temp dir and removes it afterward' {
        Invoke-GdNew -ArgList @() | Out-Null
        Should -Invoke New-GdSecureTempDir -Times 1 -Exactly
        Should -Invoke Remove-GdTempDir -Times 1 -Exactly
    }
}

# AUDIT_2026-08-03 P0-3: securetrash.ps1 монтирует VHDX на первую свободную букву и пишет
# её в sidecar <vault>.mount — ghostdraft обязан читать его, а не надеяться на 'V:\'.
Describe 'vault volume resolution (mount sidecar)' {
    BeforeEach {
        Remove-Item Env:\ST_VAULT_VOLUME -ErrorAction SilentlyContinue
        Remove-Item Env:\ST_VAULT_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:\GHOSTDRAFT_DIR -ErrorAction SilentlyContinue
        $script:FakeVault = Join-Path ([System.IO.Path]::GetTempPath()) ("gd_v_" + [Guid]::NewGuid().ToString('N') + '.vhdx')
        # Файл контейнера существует — иначе Test-GdVaultAttached честно бракует sidecar.
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
        Remove-Item -LiteralPath $script:FakeVault -Force   # контейнера больше нет
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
        # Версия-агностично: не хардкодим число (иначе тест рвётся на каждом bump) —
        # проверяем формат `ghostdraft <semver> (Windows, beta)`.
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

# AUDIT_2026-08-03, P3-хвост: shred через securetrash подставлял ST_ASSUME_YES=1 и в finally
# УДАЛЯЛ переменную — вместе со значением, которое выставил вызывающий.
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
