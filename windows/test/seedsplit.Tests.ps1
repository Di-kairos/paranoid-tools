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
    It 'corrupted share (Y damaged past what parity fixes, stale chk) is rejected' {
        # Раньше тест собирал SSS2-строку из полей SSS3 и ловил лишь отказ парсера.
        # Теперь портим тело по-настоящему — восемь байт, вчетверо больше, чем чинит parity.
        $sh = Split-ToShares (Utf8 'integrity-matters') 3 2
        $p = $sh[0] -split '-'   # SSS3 setid T x Y par chk
        $y = $p[4]
        $corrupt = "SSS3-$($p[1])-$($p[2])-$($p[3])-$('ff' * 8)$($y.Substring(16))-$($p[5])-$($p[6])"
        { Get-SsRecoveredSecret ($corrupt + "`n" + $sh[1]) 6>$null } | Should -Throw
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

# --- SSS3: RS-коррекция опечаток (Pack C). Зеркало bats-тестов bash-версии. ---
Describe 'SSS3 — parity и коррекция опечаток' {

    It 'parity совпадает с bash байт-в-байт (KAT-вектор)' {
        # Тот же вектор в test/shamir.bats: расхождение здесь = доли, нарезанные на одной
        # платформе, не соберутся на другой.
        Get-SsRsParityHex '55000c6c6567616c2077696e6e6572deadbeefcafe00112233445566778899aa' |
            Should -Be '36e2117b'
    }

    It 'split печатает формат SSS3 с полем parity' {
        $sh = Split-ToShares (Utf8 'legal winner thank year wave') 3 2
        $sh.Count | Should -Be 3
        $sh[0] | Should -Match '^SSS3-[0-9a-f]{8}-2-1-[0-9a-f]+-[0-9a-f]{8}-[0-9a-f]{4}$'
    }

    It 'одна опечатка чинится, секрет возвращается целым' {
        $secret = 'legal winner thank year wave'
        $sh = Split-ToShares (Utf8 $secret) 3 2
        $ch = $sh[0][30]; $alt = if ($ch -eq 'a') { 'b' } else { 'a' }
        $bad = $sh[0].Substring(0, 30) + $alt + $sh[0].Substring(31)
        FromUtf8 (Get-SsRecoveredSecret ($bad + "`n" + $sh[1]) 6>$null) | Should -Be $secret
    }

    It 'две опечатки в разных байтах тоже чинятся' {
        $secret = 'legal winner thank year wave'
        $sh = Split-ToShares (Utf8 $secret) 3 2
        $bad = $sh[0]
        foreach ($pos in 30, 44) {
            $ch = $bad[$pos]; $alt = if ($ch -eq 'a') { 'b' } else { 'a' }
            $bad = $bad.Substring(0, $pos) + $alt + $bad.Substring($pos + 1)
        }
        FromUtf8 (Get-SsRecoveredSecret ($bad + "`n" + $sh[1]) 6>$null) | Should -Be $secret
    }

    It 'сверх двух повреждённых байт combine отказывает, а не выдумывает секрет' {
        $secret = 'legal winner thank year wave'
        $sh = Split-ToShares (Utf8 $secret) 3 2
        $bad = $sh[0]
        foreach ($pos in 30, 36, 44, 50, 56) {
            $ch = $bad[$pos]; $alt = if ($ch -eq 'a') { 'b' } else { 'a' }
            $bad = $bad.Substring(0, $pos) + $alt + $bad.Substring($pos + 1)
        }
        { Get-SsRecoveredSecret ($bad + "`n" + $sh[1]) 6>$null } | Should -Throw
    }

    It 'KAT: замороженный SSS3-набор из bash собирается здесь' {
        $s1 = 'SSS3-de3006a6-2-1-8078e43fb71f926eabbe001af8802beabe7bbc4b9e6cd7b48d92f566d4214fc5e1e7a3683487e4640e35077b-a6effc9d-ebc2'
        $s2 = 'SSS3-de3006a6-2-2-e4f0f8eed6a89c6efcdcac5477aae77bf296de35bbb820dca4a95e50d93393c16b24ad6868acc44668047d71-4118ad84-4213'
        FromUtf8 (Get-SsRecoveredSecret ($s1 + "`n" + $s2)) | Should -Be 'paranoid tools kat secret'
    }

    It 'KAT: опечатка в замороженном наборе чинится до того же секрета' {
        $s1 = 'SSS3-de3006a6-2-1-8078e43fb71f926eabbe001af8802beabe7bbc4b9e6cd7b48d92f566d4214fc5e1e7a3683487e4640e35077b-a6effc9d-ebc2'
        $s2 = 'SSS3-de3006a6-2-2-e4f0f8eed6a89c6efcdcac5477aae77bf296de35bbb820dca4a95e50d93393c16b24ad6868acc44668047d71-4118ad84-4213'
        $alt = if ($s1[25] -eq 'a') { 'b' } else { 'a' }
        $bad = $s1.Substring(0, 25) + $alt + $s1.Substring(26)
        FromUtf8 (Get-SsRecoveredSecret ($bad + "`n" + $s2) 6>$null) | Should -Be 'paranoid tools kat secret'
    }

    It 'старые SSS2-доли (распечатки до 0.5.0) по-прежнему собираются' {
        $s1 = 'SSS2-c8854057-2-1-7f68df20a655723629706e8be2e0741a33c4df7ac2ca982951c438ff3f707f6c15ce9b9c50-f201'
        $s2 = 'SSS2-c8854057-2-2-01d0939d945693f9fd4f70984f6f53a81109f5a1cfa0b44e7dbc279aa76b64da2932a07193-49a0'
        (Get-SsRecoveredSecret ($s1 + "`n" + $s2)).Length | Should -BeGreaterThan 0
    }
    It 'опечатка ВНУТРИ поля parity тоже чинится (находка Codex)' {
        $secret = 'legal winner thank year wave'
        $sh = Split-ToShares (Utf8 $secret) 3 2
        $p = $sh[0] -split '-'
        $par = $p[5]
        $alt = if ($par[2] -eq 'a') { 'b' } else { 'a' }
        $badPar = $par.Substring(0, 2) + $alt + $par.Substring(3)
        $bad = "SSS3-$($p[1])-$($p[2])-$($p[3])-$($p[4])-$badPar-$($p[6])"
        FromUtf8 (Get-SsRecoveredSecret ($bad + "`n" + $sh[1]) 6>$null) | Should -Be $secret
    }

    It 'многочанковая нагрузка: parity на каждый чанк, чинится ошибка во втором' {
        # >251 байта нагрузки → parity из нескольких блоков (зеркало bats-теста bash).
        $secret = ('x' * 600)
        $sh = Split-ToShares (Utf8 $secret) 3 2
        $p = $sh[0] -split '-'
        $p[5].Length | Should -Be 24          # 619 байт → 3 чанка × 4 байта parity
        FromUtf8 (Get-SsRecoveredSecret (($sh[0], $sh[1]) -join "`n")) | Should -Be $secret
        $y = $p[4]
        $alt = if ($y[520] -eq 'a') { 'b' } else { 'a' }
        $badY = $y.Substring(0, 520) + $alt + $y.Substring(521)
        $bad = "SSS3-$($p[1])-$($p[2])-$($p[3])-$badY-$($p[5])-$($p[6])"
        FromUtf8 (Get-SsRecoveredSecret ($bad + "`n" + $sh[1]) 6>$null) | Should -Be $secret
    }

    It 'parity неверной длины: доля читается, но честно помечается непочинимой' {
        $secret = 'legal winner thank year wave'
        $sh = Split-ToShares (Utf8 $secret) 3 2
        $p = $sh[0] -split '-'
        $shortPar = $p[5].Substring(0, 4)
        $body = "SSS3-$($p[1])-$($p[2])-$($p[3])-$($p[4])-$shortPar"
        $chk = (Get-SsSha256Hex ([System.Text.Encoding]::ASCII.GetBytes($body))).Substring(0, 4)
        { Get-SsRecoveredSecret (("$body-$chk") + "`n" + $sh[1]) 6>$null } | Should -Throw
    }
}
