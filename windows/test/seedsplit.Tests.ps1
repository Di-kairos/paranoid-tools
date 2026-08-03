# Pester 5 — логика seedsplit.ps1 (Windows-порт). Дот-сорс под ST_NO_MAIN=1: определяет
# функции, не запуская диспетчер. Ядро Shamir/GF/обёртки тестируется напрямую (без stdin);
# CLI-уровень (версия, exit-коды) — через свежий pwsh.
#
# Главная гарантия совместимости: frozen SSS2-набор СГЕНЕРИРОВАН bash-версией (v0.3.0).
# Если Windows-порт собирает из него тот же секрет — поле/формат/обёртка байт-идентичны.

BeforeAll {
    # ST_NO_MAIN глушит диспетчер на время дот-сорса. Снимаем его СРАЗУ после: иначе
    # дочерние `& pwsh` в CLI-тестах унаследуют переменную и main у них не запустится
    # (для самого дот-сорса достаточно guard-а `$MyInvocation.InvocationName -eq '.'`).
    $env:ST_NO_MAIN = '1'
    $script:ScriptPath = Join-Path $PSScriptRoot '..\seedsplit.ps1'
    . $script:ScriptPath
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
    Initialize-SsGF

    # Помощник: разбить секрет из файла, вернуть массив строк-долей (без stdin).
    function Split-ToShares {
        param([byte[]]$Secret, [int]$N, [int]$T)
        $f = Join-Path ([System.IO.Path]::GetTempPath()) ("ss_" + [Guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllBytes($f, $Secret)
        try {
            $a = @('-n', "$N", '-t', "$T", '--file', $f)
            return @(Invoke-SsSplit -ArgList $a)
        } finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
    function Utf8 { param([string]$S) [System.Text.Encoding]::UTF8.GetBytes($S) }
    function FromUtf8 { param([byte[]]$B) [System.Text.Encoding]::UTF8.GetString($B) }
}

AfterAll {
    Remove-Item Env:\ST_NO_MAIN -ErrorAction SilentlyContinue
}

Describe 'GF(256) field' {
    It 'multiply matches FIPS-197 vectors (0x57*0x13=0xfe, 0x57*0x83=0xc1, 0x01*0xab=0xab)' {
        (Get-SsGFMul 0x57 0x13) | Should -Be 254
        (Get-SsGFMul 0x57 0x83) | Should -Be 193
        (Get-SsGFMul 0x01 0xab) | Should -Be 171
    }
    It 'inverse undoes multiply for all non-zero elements' {
        for ($a = 1; $a -le 255; $a++) {
            (Get-SsGFMul $a (Get-SsGFInv $a)) | Should -Be 1
        }
    }
}

Describe 'KAT: cross-compatibility with macOS (bash) shares' {
    # Эти доли созданы bash-версией v0.3.0; секрет = "KAT-seedsplit-v030".
    # В BeforeAll + $script: — иначе (Describe-scope) переменные не видны в It на run-фазе Pester 5.
    BeforeAll {
        $script:s1 = 'SSS2-c8854057-2-1-7f68df20a655723629706e8be2e0741a33c4df7ac2ca982951c438ff3f707f6c15ce9b9c50-f201'
        $script:s2 = 'SSS2-c8854057-2-2-01d0939d945693f9fd4f70984f6f53a81109f5a1cfa0b44e7dbc279aa76b64da2932a07193-49a0'
        $script:s3 = 'SSS2-c8854057-2-3-2bb85ef67357ccbcb15a7a60dde34ec60fbb1ae83d86599a9094dbb926626d413d66402ad2-8ca1'
    }

    It 'reconstructs the known secret from shares 1+2' {
        FromUtf8 (Get-SsRecoveredSecret ($s1 + "`n" + $s2)) | Should -Be 'KAT-seedsplit-v030'
    }
    It 'reconstructs from shares 1+3' {
        FromUtf8 (Get-SsRecoveredSecret ($s1 + "`n" + $s3)) | Should -Be 'KAT-seedsplit-v030'
    }
    It 'reconstructs from shares 2+3' {
        FromUtf8 (Get-SsRecoveredSecret ($s2 + "`n" + $s3)) | Should -Be 'KAT-seedsplit-v030'
    }
}

Describe 'split/combine round-trip' {
    It '2-of-3: every pair reconstructs' {
        $secret = 'correct horse battery staple'
        $sh = Split-ToShares (Utf8 $secret) 3 2
        $sh.Count | Should -Be 3
        foreach ($pair in @(@(0,1), @(0,2), @(1,2))) {
            $raw = $sh[$pair[0]] + "`n" + $sh[$pair[1]]
            FromUtf8 (Get-SsRecoveredSecret $raw) | Should -Be $secret
        }
    }
    It '3-of-5: a threshold subset reconstructs' {
        $secret = 'my-wallet-seed-phrase-words-here'
        $sh = Split-ToShares (Utf8 $secret) 5 3
        $raw = ($sh[1], $sh[3], $sh[4]) -join "`n"
        FromUtf8 (Get-SsRecoveredSecret $raw) | Should -Be $secret
    }
    It 'extra shares beyond T still reconstruct' {
        $secret = 'abc123'
        $sh = Split-ToShares (Utf8 $secret) 5 2
        FromUtf8 (Get-SsRecoveredSecret (($sh) -join "`n")) | Should -Be $secret
    }
    It 'T=N boundary round-trips' {
        $secret = 'all-needed'
        $sh = Split-ToShares (Utf8 $secret) 4 4
        FromUtf8 (Get-SsRecoveredSecret (($sh) -join "`n")) | Should -Be $secret
    }
    It 'binary secret with high bytes round-trips' {
        $secret = [byte[]](0x00, 0x01, 0xfe, 0xff, 0x80, 0x7f)
        $sh = Split-ToShares $secret 3 2
        $got = Get-SsRecoveredSecret (($sh[0], $sh[2]) -join "`n")
        ($got -join ',') | Should -Be ($secret -join ',')
    }
    It 'shares from two runs differ but both reconstruct (randomized)' {
        $secret = 'randomness-check'
        $a = Split-ToShares (Utf8 $secret) 3 2
        $b = Split-ToShares (Utf8 $secret) 3 2
        (($a) -join "`n") | Should -Not -Be (($b) -join "`n")
        FromUtf8 (Get-SsRecoveredSecret (($a[0], $a[1]) -join "`n")) | Should -Be $secret
        FromUtf8 (Get-SsRecoveredSecret (($b[0], $b[1]) -join "`n")) | Should -Be $secret
    }

    # AUDIT_2026-08-03 P0-2: round-trip self-check ДО печати долей (зеркало bash).
    # Сломанная реконструкция не должна выдать ни одной доли наружу — ни в stdout, ни частично.
    It 'self-check: prints NOTHING when reconstruction returns wrong bytes' {
        Mock Get-SsRecoveredSecret { [System.Text.Encoding]::UTF8.GetBytes('WRONG') }
        $out = @(); $threw = $false
        try { $out = @(Split-ToShares (Utf8 'real secret') 3 2) } catch { $threw = $true }
        $threw | Should -BeTrue
        @($out).Count | Should -Be 0
    }
    It 'self-check: prints NOTHING when reconstruction throws' {
        Mock Get-SsRecoveredSecret { throw 'gf-math-broken' }
        $out = @(); $threw = $false
        try { $out = @(Split-ToShares (Utf8 'real secret') 3 2) } catch { $threw = $true }
        $threw | Should -BeTrue
        @($out).Count | Should -Be 0
    }
}

Describe 'failure taxonomy (no secret leak)' {
    It 'below threshold is rejected' {
        $sh = Split-ToShares (Utf8 'needs-three') 5 3
        { Get-SsRecoveredSecret (($sh[0], $sh[1]) -join "`n") } | Should -Throw
    }
    It 'corrupted share (Y flipped, stale chk) is rejected' {
        $sh = Split-ToShares (Utf8 'integrity-matters') 3 2
        $p = $sh[0] -split '-'   # SSS2 setid T x Y chk
        $y = $p[4]
        $first = $y.Substring(0, 1)
        $nc = if ($first -eq '0') { '1' } else { '0' }
        $corrupt = "SSS2-$($p[1])-$($p[2])-$($p[3])-$nc$($y.Substring(1))-$($p[5])"
        { Get-SsRecoveredSecret ($corrupt + "`n" + $sh[1]) } | Should -Throw
    }
    It 'shares from different splits are rejected (set-id)' {
        $a = Split-ToShares (Utf8 'secret-A') 3 2
        $b = Split-ToShares (Utf8 'secret-B') 3 2
        { Get-SsRecoveredSecret ($a[0] + "`n" + $b[1]) } | Should -Throw
    }
    It 'duplicate share (same x) is rejected' {
        $sh = Split-ToShares (Utf8 'dup-check') 3 2
        { Get-SsRecoveredSecret ($sh[0] + "`n" + $sh[0]) } | Should -Throw
    }
    It 'non-SSS2 garbage line is rejected' {
        { Get-SsRecoveredSecret "not-a-share`nalso-not" } | Should -Throw
    }
}

Describe 'verify (no secret printed)' {
    It 'confirms a recoverable set without printing the secret' {
        $secret = 'do-not-print-me'
        $sh = Split-ToShares (Utf8 $secret) 3 2
        $f1 = Join-Path ([System.IO.Path]::GetTempPath()) ("v_" + [Guid]::NewGuid().ToString('N'))
        $f2 = Join-Path ([System.IO.Path]::GetTempPath()) ("v_" + [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $f1 -Value $sh[0] -NoNewline
        Set-Content -LiteralPath $f2 -Value $sh[1] -NoNewline
        try {
            $out = (Invoke-SsVerify -ArgList @($f1, $f2)) -join "`n"
            $out | Should -Match 'recoverable'
            $out | Should -Not -Match $secret
        } finally {
            Remove-Item -LiteralPath $f1, $f2 -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'i18n messages' {
    It 'English taxonomy strings render' {
        $script:SS_LOCALE = 'en'
        (T 'combine_below' '3' '2') | Should -Match 'below threshold'
        (T 'combine_corrupt' '1')   | Should -Match 'corrupted'
    }
    It 'Russian locale switches messages' {
        $script:SS_LOCALE = 'ru'
        (T 'combine_below' '3' '2') | Should -Match 'ниже порога'
        $script:SS_LOCALE = 'en'
    }
}

Describe 'CLI dispatch (fresh pwsh)' {
    It 'version prints the seedsplit + beta marker' {
        $out = & pwsh -NoProfile -File $script:ScriptPath 'version'
        $out | Should -Match 'seedsplit \d+\.\d+\.\d+ \(Windows, beta\)'
    }
    It 'no argument exits non-zero' {
        & pwsh -NoProfile -File $script:ScriptPath 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
    It 'unknown command exits non-zero' {
        & pwsh -NoProfile -File $script:ScriptPath 'frobnicate' 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
    It 'combine reads shares from FILE args and prints the secret (end-to-end)' {
        $secret = 'file-fed-seed'
        $sh = Split-ToShares (Utf8 $secret) 3 2
        $f = Join-Path ([System.IO.Path]::GetTempPath()) ("e2e_" + [Guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $f -Value (($sh[0], $sh[1]) -join "`n")
        try {
            $got = & pwsh -NoProfile -File $script:ScriptPath combine $f
            $got | Should -Be $secret
        } finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}
