# seedsplit.ps1 — распределить секрет на доли (Shamir Secret Sharing), Windows-порт (BETA).
# Зеркало macOS-версии (bash). Baseline: Windows PowerShell 5.1 (без PS7-only синтаксиса).
#
# Совместимость с bash-версией — БАЙТ-В-БАЙТ: тот же формат доли SSS2, те же таблицы GF(256)
# (генератор 0x03, редуцирующий многочлен 0x11b), та же обёртка целостности
# (0x55 | len(2B BE) | secret | tag(16B = первые 16 байт sha256)). Доля, созданная на macOS,
# собирается на Windows и наоборот — KAT-набор из bash-тестов проверяет это в Pester.
#
# ЧЕСТНО (как и в bash-версии): качество долей = качество ГСЧ (берём crypto-RNG ОС, не самопал);
# секрет читается из stdin/--file, НИКОГДА из argv (argv виден в списке процессов); доли
# безопасны ровно настолько, насколько безопасно ты их ХРАНИШЬ и РАЗНОСИШЬ; совместимости со
# SLIP-39 / аппаратными кошельками ПОКА НЕТ. См. README «Scope & limitations».
#
# BETA: логика покрыта Pester (включая KAT-кросс-совместимость с macOS-долями); поведение на
# реальном железе с экзотическими локалями/консолями широко не обкатано.
#
# Вывод данных (доли, секрет, версия) идёт в stdout через Write-Output / raw-stream — чтобы
# `seedsplit split > shares.txt` и пайпы работали (Write-Host в PS 5.1 не попадает в stdout).

$VERSION = '0.4.1'

# --- locale: en по умолчанию; ru — если ST_LANG или системная UI-локаль начинаются с 'ru' ---
function Get-SsLocale {
    $want = $env:ST_LANG
    if ($want) {
        if ($want -match '^(?i)ru') { return 'ru' } else { return 'en' }
    }
    if ($PSUICulture -and ($PSUICulture -match '^(?i)ru')) { return 'ru' }
    return 'en'
}
$script:SS_LOCALE = if ($env:ST_LOCALE) { $env:ST_LOCALE } else { Get-SsLocale }

# --- output helpers: ошибки/предупреждения в stderr, данные — через Write-Output у вызывающего ---
function Write-SsWarn { param([string]$Msg) [Console]::Error.WriteLine("[!] $Msg") }
# SS_QUIET_ERR: глушилка для внутреннего self-check'а split (зеркало bash `2>/dev/null`) —
# диагностика combine-путей не должна утекать в stderr при проверке СГЕНЕРИРОВАННЫХ долей.
function Write-SsErr  { param([string]$Msg) if ($script:SS_QUIET_ERR) { return }; [Console]::Error.WriteLine("[x] $Msg") }

# --- exit через исключение (Pester-safe: не убивает host-сессию) ---
class SsExit : System.Exception {
    [int]$Code
    SsExit([int]$code) : base("SsExit:$code") { $this.Code = $code }
}
function Stop-SsCommand { param([int]$Code = 1) throw [SsExit]::new($Code) }

# --- i18n (таксономия сообщений seedsplit; зеркало bash t()) ---
function T {
    param([string]$Key, [string]$A, [string]$B)
    $loc = $script:SS_LOCALE
    switch ("${loc}:${Key}") {
        'en:unknown_cmd'          { return "Unknown command: $A" }
        'ru:unknown_cmd'          { return "Unknown command: $A" }
        'en:split_bad_arg'        { return "split: unknown argument: $A" }
        'ru:split_bad_arg'        { return "split: неизвестный аргумент: $A" }
        'en:split_file_unreadable'{ return "split: file not readable: $A" }
        'ru:split_file_unreadable'{ return "split: файл недоступен: $A" }
        'en:split_empty_secret'   { return 'split: empty secret (feed it via stdin or --file)' }
        'ru:split_empty_secret'   { return 'split: пустой секрет (подай через stdin или --file)' }
        'en:split_nt_not_num'     { return 'split: -n/-t must be numbers' }
        'ru:split_nt_not_num'     { return 'split: -n/-t должны быть числами' }
        'en:split_t_min'          { return 'split: threshold -t must be >=2 (else a share equals the whole secret)' }
        'ru:split_t_min'          { return 'split: порог -t должен быть >=2 (иначе доля = весь секрет)' }
        'en:split_n_lt_t'         { return "split: number of shares -n ($A) must be >= threshold -t ($B)" }
        'ru:split_n_lt_t'         { return "split: число долей -n ($A) должно быть >= порога -t ($B)" }
        'en:split_n_max'          { return 'split: -n cannot exceed 255 (GF(256) evaluation points)' }
        'ru:split_n_max'          { return 'split: -n не может превышать 255 (точки оценки GF(256))' }
        'en:split_secret_big'     { return 'split: secret too large (>65535 bytes)' }
        'ru:split_secret_big'     { return 'split: секрет слишком большой (>65535 байт)' }
        'en:split_selfcheck_fail' { return 'split: internal self-check FAILED — the generated shares do not reconstruct the secret. Nothing was printed; do NOT rely on any partial output. Please re-run and report this.' }
        'ru:split_selfcheck_fail' { return 'split: внутренняя self-проверка НЕ ПРОШЛА — сгенерированные доли не собирают секрет. Ничего не напечатано; НЕ полагайся на частичный вывод. Перезапусти и сообщи об этом.' }
        'en:combine_not_sss2'     { return "combine: line does not look like an SSS2 share: $A" }
        'ru:combine_not_sss2'     { return "combine: строка не похожа на долю формата SSS2: $A" }
        'en:combine_corrupt'      { return "combine: share corrupted (checksum mismatch): x=$A" }
        'ru:combine_corrupt'      { return "combine: доля повреждена (контрольная сумма не сошлась): x=$A" }
        'en:combine_bad_x'        { return "combine: invalid share index x=$A" }
        'ru:combine_bad_x'        { return "combine: недопустимый номер доли x=$A" }
        'en:combine_diff_splits'  { return "combine: shares from DIFFERENT splits (set-id mismatch: $A != $B)" }
        'ru:combine_diff_splits'  { return "combine: доли от РАЗНЫХ сплитов (set-id не совпал: $A != $B)" }
        'en:combine_diff_t'       { return "combine: shares declare a different threshold T ($A != $B) — incompatible set" }
        'ru:combine_diff_t'       { return "combine: доли заявляют разный порог T ($A != $B) — несовместимый набор" }
        'en:combine_dup'          { return "combine: duplicate share x=$A" }
        'ru:combine_dup'          { return "combine: повторяющаяся доля x=$A" }
        'en:combine_diff_len'     { return 'combine: shares of different length — incompatible set' }
        'ru:combine_diff_len'     { return 'combine: доли разной длины — несовместимый набор' }
        'en:combine_no_shares'    { return 'combine: no shares provided' }
        'ru:combine_no_shares'    { return 'combine: не подано ни одной доли' }
        'en:combine_below'        { return "combine: below threshold — need at least $A shares, got $B" }
        'ru:combine_below'        { return "combine: ниже порога — нужно минимум $A долей, подано $B" }
        'en:combine_coincident'   { return 'combine: coincident share points' }
        'ru:combine_coincident'   { return 'combine: совпадающие точки долей' }
        'en:combine_integrity'    { return 'combine: reconstruction failed the integrity check (corrupted shares or incompatible set)' }
        'ru:combine_integrity'    { return 'combine: восстановление не прошло проверку целостности (повреждение долей или несовместимый набор)' }
        'en:verify_ok'            { return "verify: shares are consistent, the secret is recoverable ($A bytes). The secret is NOT shown." }
        'ru:verify_ok'            { return "verify: доли согласованы, секрет восстановим ($A байт). Секрет НЕ показан." }
        'en:pp_sealed_win'        { return 'These shares are passphrase-encrypted (openssl AES-256-CBC/PBKDF2, created with -p). The bytes below are the SEALED container, NOT the secret — decrypt them: ... | openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000' }
        'ru:pp_sealed_win'        { return 'Доли зашифрованы passphrase (openssl AES-256-CBC/PBKDF2, сделаны с -p). Байты ниже — ЗАПЕЧАТАННЫЙ контейнер, НЕ секрет — расшифруй: ... | openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000' }
        default                   { return $Key }
    }
}

function Get-SsUsage {
    if ($script:SS_LOCALE -eq 'ru') {
        return @'
Usage: seedsplit <command> [args]

Commands:
  split [-n N] [-t T] [--file F]   Разбить секрет (из stdin или --file) на N долей;
                                   любые T восстанавливают его. По умолчанию: -n 3 -t 2.
  combine [FILE...]                Восстановить секрет из >=T долей
                                   (читает из stdin по строке на долю, либо из FILE).
  verify  [FILE...]                Проверить восстановимость из >=T долей БЕЗ печати секрета.
  version                          Показать версию

Секрет читается из stdin/--file, НИКОГДА из argv (argv виден в списке процессов).
seedsplit ПОКА не совместим со SLIP-39 / аппаратными кошельками — решение на будущий пак.
Доли безопасны ровно настолько, насколько безопасно ты их хранишь.
'@
    }
    return @'
Usage: seedsplit <command> [args]

Commands:
  split [-n N] [-t T] [--file F]   Split a secret (from stdin or --file) into N
                                   shares; any T reconstruct it. Default: -n 3 -t 2.
  combine [FILE...]                Reconstruct the secret from >=T shares
                                   (read from stdin, one per line, or from FILEs).
  verify  [FILE...]                Check that >=T shares reconstruct WITHOUT printing the secret.
  version                          Show the version

Secret is read from stdin/--file, NEVER argv (argv is visible in the process list).
seedsplit does NOT yet interoperate with SLIP-39 / hardware wallets — a later scope decision.
Shares are only as safe as where you store them.
'@
}

# === примитивы байтов/хеша ===

# Все байты stdin (raw, без трансляции переводов строк). Секрет может быть бинарным.
function Read-SsStdinBytes {
    $stdin = [Console]::OpenStandardInput()
    $ms = New-Object System.IO.MemoryStream
    try {
        $buf = New-Object byte[] 4096
        while ($true) {
            $read = $stdin.Read($buf, 0, $buf.Length)
            if ($read -le 0) { break }
            $ms.Write($buf, 0, $read)
        }
        return ,$ms.ToArray()
    } finally { $ms.Dispose() }
}

# Raw-байты в stdout без перевода строки/перекодировки (важно для бинарного секрета).
function Write-SsStdoutBytes {
    param([byte[]]$Bytes)
    $stdout = [Console]::OpenStandardOutput()
    if ($Bytes.Length -gt 0) { $stdout.Write($Bytes, 0, $Bytes.Length) }
    $stdout.Flush()
}

# sha256(bytes) → строчный hex (как shasum/sha256sum).
function Get-SsSha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $h = $sha.ComputeHash($Bytes)
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $h) { [void]$sb.Append($b.ToString('x2')) }
        return $sb.ToString()
    } finally { $sha.Dispose() }
}

function ConvertTo-SsHex {
    param([byte[]]$Bytes)
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $Bytes) { [void]$sb.Append($b.ToString('x2')) }
    return $sb.ToString()
}

function ConvertFrom-SsHex {
    param([string]$Hex)
    $n = [int]($Hex.Length / 2)
    $bytes = New-Object byte[] $n
    for ($i = 0; $i -lt $n; $i++) {
        $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    return ,$bytes
}

# === GF(256): GF_EXP[i]=g^i (g=3), GF_LOG[v]=i. Редуцирующий многочлен 0x11b (AES). ===
$script:GF_EXP = $null
$script:GF_LOG = $null
function Initialize-SsGF {
    $script:GF_EXP = New-Object int[] 256
    $script:GF_LOG = New-Object int[] 256
    $x = 1
    for ($i = 0; $i -lt 255; $i++) {
        $script:GF_EXP[$i] = $x
        $script:GF_LOG[$x] = $i
        $tt = ($x -shl 1) -band 0xff           # xtime(x) = x*2 в GF
        if ($x -band 0x80) { $tt = $tt -bxor 0x1b }
        $x = $tt -bxor $x                        # x*3 = xtime(x) XOR x
    }
}
function Get-SsGFMul {
    param([int]$A, [int]$B)
    if ($A -eq 0 -or $B -eq 0) { return 0 }
    return $script:GF_EXP[($script:GF_LOG[$A] + $script:GF_LOG[$B]) % 255]
}
function Get-SsGFInv {
    param([int]$A)   # A != 0 гарантирует вызывающий (проверка совпадающих точек)
    return $script:GF_EXP[(255 - $script:GF_LOG[$A]) % 255]
}

# === split ===
function Invoke-SsSplit {
    param([string[]]$ArgList)
    $n = 3; $t = 2; $file = ''
    $i = 0
    while ($i -lt $ArgList.Count) {
        switch ($ArgList[$i]) {
            { $_ -in '-n','--shares' }    { $n = $ArgList[$i + 1]; $i += 2 }
            { $_ -in '-t','--threshold' } { $t = $ArgList[$i + 1]; $i += 2 }
            '--file'                      { $file = $ArgList[$i + 1]; $i += 2 }
            default { Write-SsErr (T 'split_bad_arg' $ArgList[$i]); Stop-SsCommand 1 }
        }
    }

    # Секрет — из stdin или --file. Никогда из argv.
    [byte[]]$secret = $null
    if ($file) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            Write-SsErr (T 'split_file_unreadable' $file); Stop-SsCommand 1
        }
        try { $secret = [System.IO.File]::ReadAllBytes($file) }
        catch { Write-SsErr (T 'split_file_unreadable' $file); Stop-SsCommand 1 }
    } else {
        $secret = Read-SsStdinBytes
    }
    if ($null -eq $secret -or $secret.Length -eq 0) {
        Write-SsErr (T 'split_empty_secret'); Stop-SsCommand 1
    }

    if (-not ("$n" -match '^[0-9]+$') -or -not ("$t" -match '^[0-9]+$')) {
        Write-SsErr (T 'split_nt_not_num'); Stop-SsCommand 1
    }
    $n = [int]$n; $t = [int]$t
    if ($t -lt 2)   { Write-SsErr (T 'split_t_min'); Stop-SsCommand 1 }
    if ($n -lt $t)  { Write-SsErr (T 'split_n_lt_t' "$n" "$t"); Stop-SsCommand 1 }
    if ($n -gt 255) { Write-SsErr (T 'split_n_max'); Stop-SsCommand 1 }

    $L = $secret.Length
    if ($L -gt 65535) { Write-SsErr (T 'split_secret_big'); Stop-SsCommand 1 }

    # Случайный set-id (4-байтный nonce) — НЕ производный от секрета (иначе confirmation-оракул).
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $setidBytes = New-Object byte[] 4
        $rng.GetBytes($setidBytes)
        $setidHex = ConvertTo-SsHex $setidBytes

        # Обёртка целостности: 0x55 | len(2B BE) | secret | tag(16B = первые 16 байт sha256(core)).
        $hi = [int]($L -shr 8); $lo = [int]($L -band 0xff)
        $core = New-Object 'System.Collections.Generic.List[byte]'
        $core.Add([byte]0x55); $core.Add([byte]$hi); $core.Add([byte]$lo)
        $core.AddRange($secret)
        $coreArr = $core.ToArray()
        $tagHex = (Get-SsSha256Hex $coreArr).Substring(0, 32)
        $payloadHex = (ConvertTo-SsHex $coreArr) + $tagHex
        $P = ConvertFrom-SsHex $payloadHex
        $PL = $P.Length

        if ($null -eq $script:GF_EXP) { Initialize-SsGF }

        # (t-1) случайных байт на каждый байт payload — старшие коэффициенты многочленов.
        $need = ($t - 1) * $PL
        $rand = New-Object byte[] ([Math]::Max($need, 1))
        if ($need -gt 0) { $rng.GetBytes($rand) }

        # Y[x] копит hex-строку каждой доли x=1..n.
        $Y = New-Object string[] ($n + 1)
        for ($x = 1; $x -le $n; $x++) { $Y[$x] = '' }

        $ri = 0
        for ($k = 0; $k -lt $PL; $k++) {
            # Коэффициенты многочлена байта k: C[0]=секрет, C[1..t-1]=случайные.
            $C = New-Object int[] $t
            $C[0] = [int]$P[$k]
            for ($j = 1; $j -lt $t; $j++) { $C[$j] = [int]$rand[$ri]; $ri++ }
            for ($x = 1; $x -le $n; $x++) {
                # Горнер: ev = C[t-1]; ev = ev*x XOR C[j], j=t-2..0.
                # ВАЖНО: PowerShell регистронезависим к именам — скаляр НЕ называть $y,
                # иначе он схлопнется с массивом долей $Y и затрёт его (в bash регистр значим).
                $ev = $C[$t - 1]
                for ($j = $t - 2; $j -ge 0; $j--) {
                    $ev = Get-SsGFMul $ev $x
                    $ev = $ev -bxor $C[$j]
                }
                $Y[$x] += ([int]$ev).ToString('x2')
            }
        }

        # Доля: SSS2-<setid>-<T>-<x>-<hexY>-<chk4>. chk = sha256(body)[:4]; ловит опечатку в доле.
        $shares = New-Object 'System.Collections.Generic.List[string]'
        for ($x = 1; $x -le $n; $x++) {
            $body = "SSS2-$setidHex-$t-$x-$($Y[$x])"
            $chk = (Get-SsSha256Hex ([System.Text.Encoding]::ASCII.GetBytes($body))).Substring(0, 4)
            $shares.Add("$body-$chk")
        }

        # Round-trip self-check ДО печати (зеркало bash seedsplit): собрать секрет ровно тем же
        # путём, что combine, из первых T долей и сверить с исходным. Ловит любую поломку
        # генерации/GF-математики РАНЬШЕ, чем юзер раздаст доли и сотрёт оригинал сида
        # (AUDIT_2026-08-03 P0-2).
        $scOk = $false
        $script:SS_QUIET_ERR = $true
        try {
            $rec = Get-SsRecoveredSecret -Raw (($shares | Select-Object -First $t) -join "`n")
            $scOk = ((ConvertTo-SsHex $rec) -eq (ConvertTo-SsHex $secret))
        } catch { $scOk = $false } finally { $script:SS_QUIET_ERR = $false }
        if (-not $scOk) { Write-SsErr (T 'split_selfcheck_fail'); Stop-SsCommand 1 }

        foreach ($s in $shares) { Write-Output $s }
    } finally { $rng.Dispose() }
}

# === восстановление: парсинг + ВСЕ проверки + интерполяция Лагранжа в нуле ===
# Возвращает [byte[]] секрет; при любой ошибке печатает err и Stop-SsCommand 1.
function Get-SsRecoveredSecret {
    param([string]$Raw)
    if ($null -eq $script:GF_EXP) { Initialize-SsGF }

    $XS = New-Object 'System.Collections.Generic.List[int]'
    $YS = New-Object 'System.Collections.Generic.List[string]'
    $ylen = $null; $tDecl = $null; $setidSeen = $null; $cnt = 0

    foreach ($line in ($Raw -split "`r?`n")) {
        if ([string]::IsNullOrEmpty($line)) { continue }
        if ($line -notmatch '^SSS2-([0-9a-f]{8})-([0-9]+)-([0-9]+)-([0-9a-f]+)-([0-9a-f]{4})$') {
            Write-SsErr (T 'combine_not_sss2' $line); Stop-SsCommand 1
        }
        $sid = $Matches[1]; $Tstr = $Matches[2]; $xstr = $Matches[3]; $yh = $Matches[4]; $chk = $Matches[5]
        $body = "SSS2-$sid-$Tstr-$xstr-$yh"
        $want = (Get-SsSha256Hex ([System.Text.Encoding]::ASCII.GetBytes($body))).Substring(0, 4)
        if ($chk -ne $want) { Write-SsErr (T 'combine_corrupt' $xstr); Stop-SsCommand 1 }
        $x = [int]$xstr
        if ($x -lt 1 -or $x -gt 255) { Write-SsErr (T 'combine_bad_x' $xstr); Stop-SsCommand 1 }
        if ($null -eq $setidSeen) { $setidSeen = $sid }
        elseif ($sid -ne $setidSeen) { Write-SsErr (T 'combine_diff_splits' $sid $setidSeen); Stop-SsCommand 1 }
        if ($null -eq $tDecl) { $tDecl = $Tstr }
        elseif ($Tstr -ne $tDecl) { Write-SsErr (T 'combine_diff_t' $Tstr $tDecl); Stop-SsCommand 1 }
        if ($XS.Contains($x)) { Write-SsErr (T 'combine_dup' $xstr); Stop-SsCommand 1 }
        if ($null -eq $ylen) { $ylen = $yh.Length }
        if ($yh.Length -ne $ylen) { Write-SsErr (T 'combine_diff_len'); Stop-SsCommand 1 }
        $XS.Add($x); $YS.Add($yh); $cnt++
    }

    if ($cnt -lt 1) { Write-SsErr (T 'combine_no_shares'); Stop-SsCommand 1 }
    if ($null -ne $tDecl -and $cnt -lt [int]$tDecl) {
        Write-SsErr (T 'combine_below' "$tDecl" "$cnt"); Stop-SsCommand 1
    }

    # Веса Лагранжа в нуле: w_i = prod_{j!=i} x_j * inv(x_i XOR x_j).
    $m = $cnt
    $W = New-Object int[] $m
    for ($i = 0; $i -lt $m; $i++) {
        $num = 1; $xi = $XS[$i]
        for ($j = 0; $j -lt $m; $j++) {
            if ($j -eq $i) { continue }
            $xj = $XS[$j]; $den = $xi -bxor $xj
            if ($den -eq 0) { Write-SsErr (T 'combine_coincident'); Stop-SsCommand 1 }
            $num = Get-SsGFMul $num $xj
            $num = Get-SsGFMul $num (Get-SsGFInv $den)
        }
        $W[$i] = $num
    }

    # Восстановление каждого байта payload: acc = XOR_i ( y_i[p] * w_i ).
    $PL = [int]($ylen / 2)
    $payload = New-Object byte[] $PL
    for ($p = 0; $p -lt $PL; $p++) {
        $acc = 0
        for ($i = 0; $i -lt $m; $i++) {
            $yb = [Convert]::ToInt32($YS[$i].Substring($p * 2, 2), 16)
            if ($yb -ne 0) { $acc = $acc -bxor (Get-SsGFMul $yb $W[$i]) }
        }
        $payload[$p] = [byte]$acc
    }

    # Обёртка: magic(0x55) | len(2) | secret | tag(16).
    $failMsg = T 'combine_integrity'
    if ($PL -lt 20) { Write-SsErr $failMsg; Stop-SsCommand 1 }
    if ($payload[0] -ne 0x55) { Write-SsErr $failMsg; Stop-SsCommand 1 }
    $len = ([int]$payload[1] -shl 8) -bor [int]$payload[2]
    if ($PL -ne $len + 19) { Write-SsErr $failMsg; Stop-SsCommand 1 }
    $core = New-Object byte[] ($len + 3)
    [Array]::Copy($payload, 0, $core, 0, $len + 3)
    $tagHave = (ConvertTo-SsHex $payload).Substring(($PL * 2) - 32, 32)
    $tagWant = (Get-SsSha256Hex $core).Substring(0, 32)
    if ($tagHave -ne $tagWant) { Write-SsErr $failMsg; Stop-SsCommand 1 }

    $secret = New-Object byte[] $len
    [Array]::Copy($payload, 3, $secret, 0, $len)
    return ,$secret
}

# Доли — из FILE-аргументов (склейка) или из stdin (текст по строке на долю).
function Read-SsCombineInput {
    param([string[]]$ArgList)
    if ($ArgList -and $ArgList.Count -ge 1) {
        $parts = @()
        foreach ($f in $ArgList) {
            if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
                Write-SsErr (T 'split_file_unreadable' $f); Stop-SsCommand 1
            }
            $parts += [System.IO.File]::ReadAllText($f)
        }
        return ($parts -join "`n")
    }
    $bytes = Read-SsStdinBytes
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Invoke-SsCombine {
    param([string[]]$ArgList)
    $raw = Read-SsCombineInput $ArgList
    $secret = Get-SsRecoveredSecret $raw
    # Контейнер passphrase-режима (-p, macOS/Linux): первые 8 байт = "Salted__" (openssl). На
    # Windows авто-расшифровку не делаем (без жёсткой зависимости от openssl) — честно
    # предупреждаем и отдаём контейнер как есть, чтобы расшифровать его openssl-конвейером.
    if ($secret.Length -ge 8 -and
        $secret[0] -eq 0x53 -and $secret[1] -eq 0x61 -and $secret[2] -eq 0x6C -and $secret[3] -eq 0x74 -and
        $secret[4] -eq 0x65 -and $secret[5] -eq 0x64 -and $secret[6] -eq 0x5F -and $secret[7] -eq 0x5F) {
        Write-SsWarn (T 'pp_sealed_win')
    }
    Write-SsStdoutBytes $secret
}

function Invoke-SsVerify {
    param([string[]]$ArgList)
    $raw = Read-SsCombineInput $ArgList
    $secret = Get-SsRecoveredSecret $raw
    Write-Output (T 'verify_ok' "$($secret.Length)")
}

function Invoke-SsVersion { Write-Output "seedsplit $VERSION (Windows, beta)" }

function Invoke-SsMain {
    param([string[]]$Argv)
    try {
        $cmd = if ($Argv -and $Argv.Count -ge 1) { $Argv[0] } else { '' }
        if (-not $cmd) { Write-Output (Get-SsUsage); exit 1 }
        $rest = @(if ($Argv.Count -ge 2) { $Argv[1..($Argv.Count - 1)] } else { @() })
        switch ($cmd) {
            { $_ -in 'version','-v','--version' } { Invoke-SsVersion }
            { $_ -in 'help','--help','-h' }       { Write-Output (Get-SsUsage) }
            'split'   {
                # Доли пишем в stdout с переводом строки LF (\n), не CRLF: share-файл,
                # созданный на Windows, должен собираться bash-версией на macOS без правок
                # (bash `read -r` оставил бы \r и сломал regex доли). Функция возвращает
                # строки (Write-Output) — это удобно тестам; в CLI склеиваем их через \n.
                $lines = @(Invoke-SsSplit -ArgList $rest)
                if ($lines.Count -gt 0) {
                    $text = ($lines -join "`n") + "`n"
                    Write-SsStdoutBytes ([System.Text.Encoding]::ASCII.GetBytes($text))
                }
            }
            'combine' { Invoke-SsCombine -ArgList $rest }
            'verify'  { Invoke-SsVerify  -ArgList $rest }
            default   { Write-SsErr (T 'unknown_cmd' $cmd); [Console]::Error.WriteLine((Get-SsUsage)); exit 1 }
        }
    } catch [SsExit] {
        exit $_.Exception.Code
    }
}

# Dot-source guard: при `. seedsplit.ps1` (Pester) main НЕ запускается; ST_NO_MAIN=1 тоже глушит.
if ($MyInvocation.InvocationName -ne '.' -and -not $env:ST_NO_MAIN) {
    Invoke-SsMain -Argv $args
}
