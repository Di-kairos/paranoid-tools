# Тесты ядра Shamir над GF(256): split/combine/verify, формат SSS3 (+ совместимость с SSS2).
# Спека корректности: round-trip всех подмножеств порога; отказ при <T долей;
# таксономия отказов (порча CRC / разные сплиты set-id / расходящийся T / целостность
# 16-байтного tag); бинарные секреты; границы N/T; KAT-векторы (GF + замороженный набор).
setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../seedsplit"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  export PATH="$STUBS:$PATH"
  export ST_ASSUME_YES=1
  export ST_LOCALE=en   # детерминируем локаль рантайм-сообщений (en — дефолт тула)
}

# --- помощник: разбить секрет, вернуть доли (по строке на долю) ---
_split() { # $1=secret $2=N $3=T
  printf '%s' "$1" | bash "$SCRIPT" split -n "$2" -t "$3"
}

@test "split outputs exactly N share lines" {
  run _split "topsecret" 5 3
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^SSS3-')" -eq 5 ]
}

@test "share lines carry the SSS3 wire format" {
  run _split "topsecret" 3 2
  [[ "$output" == SSS3-* ]]
}

@test "round-trip 2-of-3: every pair reconstructs the secret" {
  secret="correct horse battery staple"
  shares="$(_split "$secret" 3 2)"
  for pair in "1p;2p" "1p;3p" "2p;3p"; do
    sel="$(printf '%s\n' "$shares" | sed -n "$pair")"
    out="$(printf '%s\n' "$sel" | bash "$SCRIPT" combine)"
    [ "$out" = "$secret" ]
  done
}

@test "round-trip 3-of-5: a threshold subset reconstructs" {
  secret="my-wallet-seed-phrase-words-here"
  shares="$(_split "$secret" 5 3)"
  sel="$(printf '%s\n' "$shares" | sed -n '2p;4p;5p')"
  out="$(printf '%s\n' "$sel" | bash "$SCRIPT" combine)"
  [ "$out" = "$secret" ]
}

@test "more than T shares also reconstruct (extra shares are fine)" {
  secret="abc123"
  shares="$(_split "$secret" 5 2)"
  out="$(printf '%s\n' "$shares" | bash "$SCRIPT" combine)"   # all 5
  [ "$out" = "$secret" ]
}

@test "default params (no -n/-t) round-trip" {
  secret="default-params-secret"
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split)"
  n="$(printf '%s\n' "$shares" | grep -c '^SSS3-')"
  [ "$n" -ge 2 ]
  out="$(printf '%s\n' "$shares" | bash "$SCRIPT" combine)"
  [ "$out" = "$secret" ]
}

@test "fewer than T shares fails with below-threshold message (no secret leak)" {
  secret="needs-three"
  shares="$(_split "$secret" 5 3)"
  sel="$(printf '%s\n' "$shares" | sed -n '1p;2p')"   # only 2 of 3
  run bash -c "printf '%s\n' \"$sel\" | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" == *"below threshold"* ]]
  [[ "$output" != *"needs-three"* ]]
}

@test "corrupted share is detected via per-share checksum" {
  secret="integrity-matters"
  shares="$(_split "$secret" 3 2)"
  first="$(printf '%s\n' "$shares" | sed -n '1p')"
  second="$(printf '%s\n' "$shares" | sed -n '2p')"
  # Поля SSS3: SSS3-setid-T-x-Y-par-chk. Портим сразу много байт Y — больше, чем чинит parity,
  # поэтому доля обязана быть отвергнута, а не «починена».
  sid="$(cut -d- -f2 <<<"$first")"; T="$(cut -d- -f3 <<<"$first")"
  x="$(cut -d- -f4 <<<"$first")"; Y="$(cut -d- -f5 <<<"$first")"
  par="$(cut -d- -f6 <<<"$first")"; chk="$(cut -d- -f7 <<<"$first")"
  # Восемь испорченных hex-пар — вчетверо больше, чем чинит parity.
  badY="ffffffffffffffff${Y:16}"
  corrupt="SSS3-${sid}-${T}-${x}-${badY}-${par}-${chk}"
  run bash -c "printf '%s\n%s\n' '$corrupt' '$second' | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" == *"damaged"* ]] || [[ "$output" == *"повреждена"* ]]
  [[ "$output" != *"$secret"* ]]
}

@test "shares from different splits rejected with set-id message" {
  a="$(_split "secret-A" 3 2)"
  b="$(_split "secret-B" 3 2)"
  mix="$(printf '%s\n%s\n' "$(printf '%s\n' "$a" | sed -n '1p')" "$(printf '%s\n' "$b" | sed -n '2p')")"
  run bash -c "printf '%s\n' \"$mix\" | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" == *"set-id"* ]]
}

@test "shares declaring a different threshold T are rejected" {
  shares="$(_split "tee" 3 2)"
  s1="$(printf '%s\n' "$shares" | sed -n '1p')"
  s2="$(printf '%s\n' "$shares" | sed -n '2p')"
  # Подменяем у s2 заявленный T=2 -> 9 и пересчитываем per-share chk (чтобы доля «прошла»).
  sid="$(cut -d- -f2 <<<"$s2")"; x="$(cut -d- -f4 <<<"$s2")"; Y="$(cut -d- -f5 <<<"$s2")"
  body="SSS2-${sid}-9-${x}-${Y}"
  chk="$(printf '%s' "$body" | shasum -a 256 | cut -c1-4)"
  run bash -c "printf '%s\n%s\n' '$s1' '${body}-${chk}' | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" == *"different threshold"* ]]
}

@test "16-byte payload tag catches corruption that passes per-share checksum" {
  secret="tag-guard"
  shares="$(_split "$secret" 3 2)"
  s1="$(printf '%s\n' "$shares" | sed -n '1p')"
  s2="$(printf '%s\n' "$shares" | sed -n '2p')"
  # Портим Y у s1 на один nibble И пересчитываем per-share chk → доля сама «валидна»,
  # но восстановленный payload не сойдётся с 16-байтным tag.
  sid="$(cut -d- -f2 <<<"$s1")"; T="$(cut -d- -f3 <<<"$s1")"; x="$(cut -d- -f4 <<<"$s1")"; Y="$(cut -d- -f5 <<<"$s1")"
  c="${Y:0:1}"; if [ "$c" = "0" ]; then nc="1"; else nc="0"; fi
  body="SSS2-${sid}-${T}-${x}-${nc}${Y:1}"
  chk="$(printf '%s' "$body" | shasum -a 256 | cut -c1-4)"
  run bash -c "printf '%s\n%s\n' '${body}-${chk}' '$s2' | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" == *"integrity"* ]]
  [[ "$output" != *"$secret"* ]]
}

@test "duplicate share (same x) is rejected" {
  shares="$(_split "dup-check" 3 2)"
  one="$(printf '%s\n' "$shares" | sed -n '1p')"
  run bash -c "printf '%s\n%s\n' \"$one\" \"$one\" | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate"* ]]
}

@test "verify confirms a reconstructable set WITHOUT printing the secret" {
  secret="do-not-print-me"
  shares="$(_split "$secret" 3 2)"
  out="$(printf '%s\n' "$shares" | sed -n '1p;2p' | bash "$SCRIPT" verify)"
  [[ "$out" == *"recoverable"* ]]
  [[ "$out" != *"$secret"* ]]
}

@test "verify fails on a below-threshold set" {
  shares="$(_split "vsecret" 5 3)"
  sel="$(printf '%s\n' "$shares" | sed -n '1p;2p')"
  run bash -c "printf '%s\n' \"$sel\" | bash '$SCRIPT' verify"
  [ "$status" -ne 0 ]
}

@test "binary secret with high bytes round-trips" {
  shares="$(printf '\x00\x01\xfe\xff\x80\x7f' | bash "$SCRIPT" split -n 3 -t 2)"
  sel="$(printf '%s\n' "$shares" | sed -n '1p;3p')"
  out_hex="$(printf '%s\n' "$sel" | bash "$SCRIPT" combine | od -An -v -tx1 | tr -d ' \n')"
  [ "$out_hex" = "0001feff807f" ]
}

@test "secret from --file round-trips" {
  f="$(mktemp)"; printf 'file-fed-secret' > "$f"
  shares="$(bash "$SCRIPT" split -n 3 -t 2 --file "$f")"
  sel="$(printf '%s\n' "$shares" | sed -n '1p;2p')"
  out="$(printf '%s\n' "$sel" | bash "$SCRIPT" combine)"
  [ "$out" = "file-fed-secret" ]
  rm -f "$f"
}

@test "threshold below 2 is rejected" {
  run bash -c "printf 'x' | bash '$SCRIPT' split -n 3 -t 1"
  [ "$status" -ne 0 ]
}

@test "threshold above shares is rejected" {
  run bash -c "printf 'x' | bash '$SCRIPT' split -n 3 -t 4"
  [ "$status" -ne 0 ]
}

@test "shares above 255 is rejected" {
  run bash -c "printf 'x' | bash '$SCRIPT' split -n 256 -t 2"
  [ "$status" -ne 0 ]
}

@test "empty secret is rejected" {
  run bash -c "printf '' | bash '$SCRIPT' split -n 3 -t 2"
  [ "$status" -ne 0 ]
}

@test "split is randomized: two runs give different shares but both reconstruct" {
  secret="randomness-check"
  s1="$(_split "$secret" 3 2)"
  s2="$(_split "$secret" 3 2)"
  [ "$s1" != "$s2" ]
  o1="$(printf '%s\n' "$s1" | sed -n '1p;2p' | bash "$SCRIPT" combine)"
  o2="$(printf '%s\n' "$s2" | sed -n '1p;2p' | bash "$SCRIPT" combine)"
  [ "$o1" = "$secret" ]
  [ "$o2" = "$secret" ]
}

@test "T=N boundary (all shares required) round-trips" {
  secret="all-needed"
  shares="$(_split "$secret" 4 4)"
  out="$(printf '%s\n' "$shares" | bash "$SCRIPT" combine)"
  [ "$out" = "$secret" ]
}

# --- Known-answer tests (страховка от регрессии при будущем рефакторинге) ---

@test "KAT: GF(256) multiply matches FIPS-197 vectors" {
  # 0x57·0x13=0xfe(254), 0x57·0x83=0xc1(193), 0x01·0xab=0xab(171) — эталон AES (FIPS-197 §4.2).
  # Робастно к версии bash: single-quoted body (без вложенного экранирования), SCRIPT через $1,
  # 'set +eu' нейтрализует строгий режим sourced-скрипта, индексы литеральные (не через $N).
  run bash -c 'source "$1"; set +eu; _gf_init
    echo $(( GF_EXP[(GF_LOG[87]+GF_LOG[19])%255] )) \
         $(( GF_EXP[(GF_LOG[87]+GF_LOG[131])%255] )) \
         $(( GF_EXP[(GF_LOG[1]+GF_LOG[171])%255] ))' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "254 193 171" ]
}

@test "KAT: frozen SSS2 share-set reconstructs the known secret" {
  s1="SSS2-c8854057-2-1-7f68df20a655723629706e8be2e0741a33c4df7ac2ca982951c438ff3f707f6c15ce9b9c50-f201"
  s2="SSS2-c8854057-2-2-01d0939d945693f9fd4f70984f6f53a81109f5a1cfa0b44e7dbc279aa76b64da2932a07193-49a0"
  s3="SSS2-c8854057-2-3-2bb85ef67357ccbcb15a7a60dde34ec60fbb1ae83d86599a9094dbb926626d413d66402ad2-8ca1"
  [ "$(printf '%s\n%s\n' "$s1" "$s2" | bash "$SCRIPT" combine)" = "KAT-seedsplit-v030" ]
  [ "$(printf '%s\n%s\n' "$s1" "$s3" | bash "$SCRIPT" combine)" = "KAT-seedsplit-v030" ]
  [ "$(printf '%s\n%s\n' "$s2" "$s3" | bash "$SCRIPT" combine)" = "KAT-seedsplit-v030" ]
}

# --- SSS3: RS-коррекция опечаток в переписанной с бумаги доле ---

# Собрать долю старого формата SSS2 из свежей SSS3 (снять parity, пересчитать chk4) —
# ровно то, что печатали релизы до 0.5.0. Так проверяется обратная совместимость combine.
_sss3_to_sss2() {
  local line="$1" sid T x yh
  [[ "$line" =~ ^SSS3-([0-9a-f]{8})-([0-9]+)-([0-9]+)-([0-9a-f]+)-([0-9a-f]+)-([0-9a-f]{4})$ ]] || return 1
  sid="${BASH_REMATCH[1]}"; T="${BASH_REMATCH[2]}"; x="${BASH_REMATCH[3]}"; yh="${BASH_REMATCH[4]}"
  local body="SSS2-${sid}-${T}-${x}-${yh}" chk
  chk="$(printf '%s' "$body" | shasum -a 256 | cut -d' ' -f1)"
  printf '%s-%s' "$body" "${chk:0:4}"
}

# Испортить один hex-символ строки в позиции $2 (гарантированно на другой).
_typo_at() {
  local line="$1" pos="$2" ch alt
  ch="${line:pos:1}"
  if [[ "$ch" == "a" ]]; then alt=b; else alt=a; fi
  printf '%s%s%s' "${line:0:pos}" "$alt" "${line:pos+1}"
}

@test "split emits the SSS3 format with a parity field" {
  run bash -c "printf 'legal winner thank year wave' | bash '$SCRIPT' split -n 3 -t 2"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" =~ ^SSS3-[0-9a-f]{8}-2-1-[0-9a-f]+-[0-9a-f]{8}-[0-9a-f]{4}$ ]]
  [ "${#lines[@]}" -eq 3 ]
}

@test "one mistyped character in a share is corrected, secret comes back intact" {
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  s1="$(printf '%s\n' "$shares" | sed -n 1p)"; s2="$(printf '%s\n' "$shares" | sed -n 2p)"
  bad="$(_typo_at "$s1" 30)"
  run bash -c "printf '%s\n%s\n' '$bad' '$s2' | bash '$SCRIPT' combine"
  [ "$status" -eq 0 ]
  [ "$output" != "" ]
  [[ "$output" == *"$secret"* ]]
  [[ "$output" == *"corrected"* ]] || [[ "$output" == *"исправлено"* ]]   # починку не скрываем
}

@test "two mistyped characters in different bytes are still corrected" {
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  s1="$(printf '%s\n' "$shares" | sed -n 1p)"; s2="$(printf '%s\n' "$shares" | sed -n 2p)"
  bad="$(_typo_at "$(_typo_at "$s1" 30)" 44)"
  run bash -c "printf '%s\n%s\n' '$bad' '$s2' | bash '$SCRIPT' combine"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$secret"* ]]
}

@test "beyond two damaged bytes combine refuses — it never guesses a secret" {
  # Самое важное свойство: код чинит или отказывает, но НЕ отдаёт молча другой секрет.
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  s1="$(printf '%s\n' "$shares" | sed -n 1p)"; s2="$(printf '%s\n' "$shares" | sed -n 2p)"
  bad="$s1"
  for pos in 30 44 50 56 62; do bad="$(_typo_at "$bad" "$pos")"; done
  run bash -c "printf '%s\n%s\n' '$bad' '$s2' | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" != *"$secret"* ]]
}

@test "old SSS2 shares (pre-0.5.0 printouts) still combine" {
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  o1="$(_sss3_to_sss2 "$(printf '%s\n' "$shares" | sed -n 1p)")"
  o2="$(_sss3_to_sss2 "$(printf '%s\n' "$shares" | sed -n 2p)")"
  run bash -c "printf '%s\n%s\n' '$o1' '$o2' | bash '$SCRIPT' combine"
  [ "$status" -eq 0 ]
  [ "$output" = "$secret" ]
}

@test "a damaged SSS2 share still fails closed (no parity to repair with)" {
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  o1="$(_sss3_to_sss2 "$(printf '%s\n' "$shares" | sed -n 1p)")"
  o2="$(_sss3_to_sss2 "$(printf '%s\n' "$shares" | sed -n 2p)")"
  bad="$(_typo_at "$o1" 30)"
  run bash -c "printf '%s\n%s\n' '$bad' '$o2' | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" != *"$secret"* ]]
}

@test "parity is deterministic — known-answer for a fixed payload (bash↔ps1 parity anchor)" {
  # Тот же вектор проверяется в Pester: доли, нарезанные на macOS, обязаны собираться
  # на Windows и наоборот, значит и parity обязана считаться байт-в-байт одинаково.
  run bash -c "source '$SCRIPT'; _rs_parity_hex '55000c6c6567616c2077696e6e6572deadbeefcafe00112233445566778899aa'"
  [ "$status" -eq 0 ]
  [ "$output" = "36e2117b" ]
}

@test "verify accepts a share it had to repair" {
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  s1="$(printf '%s\n' "$shares" | sed -n 1p)"; s2="$(printf '%s\n' "$shares" | sed -n 2p)"
  bad="$(_typo_at "$s1" 30)"
  run bash -c "printf '%s\n%s\n' '$bad' '$s2' | bash '$SCRIPT' verify"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$secret"* ]]   # verify не печатает секрет
}

# KAT формата SSS3: набор заморожен (нарезан bash-версией 0.5.0). Тот же вектор проверяется
# в Pester — так гарантируется, что доли, нарезанные на macOS, соберутся на Windows и наоборот.
@test "KAT: frozen SSS3 share-set reconstructs the known secret" {
  s1="SSS3-de3006a6-2-1-8078e43fb71f926eabbe001af8802beabe7bbc4b9e6cd7b48d92f566d4214fc5e1e7a3683487e4640e35077b-a6effc9d-ebc2"
  s2="SSS3-de3006a6-2-2-e4f0f8eed6a89c6efcdcac5477aae77bf296de35bbb820dca4a95e50d93393c16b24ad6868acc44668047d71-4118ad84-4213"
  run bash -c "printf '%s\n%s\n' '$s1' '$s2' | bash '$SCRIPT' combine"
  [ "$status" -eq 0 ]
  [ "$output" = "paranoid tools kat secret" ]
}

@test "KAT: a typo in the frozen SSS3 set is repaired to the same secret" {
  s1="SSS3-de3006a6-2-1-8078e43fb71f926eabbe001af8802beabe7bbc4b9e6cd7b48d92f566d4214fc5e1e7a3683487e4640e35077b-a6effc9d-ebc2"
  s2="SSS3-de3006a6-2-2-e4f0f8eed6a89c6efcdcac5477aae77bf296de35bbb820dca4a95e50d93393c16b24ad6868acc44668047d71-4118ad84-4213"
  bad="$(_typo_at "$s1" 25)"
  run bash -c "printf '%s\n%s\n' '$bad' '$s2' | bash '$SCRIPT' combine"
  [ "$status" -eq 0 ]
  [[ "$output" == *"paranoid tools kat secret"* ]]
}

@test "multi-chunk payload: parity covers every chunk and repairs the second one" {
  # Полезная нагрузка >251 байта → parity из двух блоков. Проверяем и round-trip, и то,
  # что чинится опечатка ВО ВТОРОМ чанке (первый чанк при этом чистый).
  secret="$(head -c 300 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 600)"
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  s1="$(printf '%s\n' "$shares" | sed -n 1p)"; s2="$(printf '%s\n' "$shares" | sed -n 2p)"
  IFS=- read -r pfx sid T x yh par chk <<<"$s1"
  # 619 байт нагрузки → 3 чанка по 251 → 12 байт parity = 24 hex-символа.
  [ "${#par}" -eq 24 ]
  out="$(printf '%s\n%s\n' "$s1" "$s2" | bash "$SCRIPT" combine)"
  [ "$out" = "$secret" ]
  head_len=$(( ${#pfx} + 1 + ${#sid} + 1 + ${#T} + 1 + ${#x} + 1 ))
  bad="$(_typo_at "$s1" $(( head_len + 520 )))"
  run bash -c "printf '%s\n%s\n' '$bad' '$s2' | bash '$SCRIPT' combine"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$secret"* ]]
}

@test "a typo landing on a field separator is refused, not silently mangled" {
  # RS кроет тело доли, но не структуру строки: съеденный/подменённый дефис = нечитаемая доля.
  # Так и задокументировано; проверяем, что мы это честно говорим, а не гадаем.
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  s1="$(printf '%s\n' "$shares" | sed -n 1p)"; s2="$(printf '%s\n' "$shares" | sed -n 2p)"
  IFS=- read -r pfx sid T x yh par chk <<<"$s1"
  sep=$(( ${#pfx} + 1 + ${#sid} + 1 + ${#T} + 1 + ${#x} + 1 + ${#yh} ))   # дефис перед parity
  bad="${s1:0:sep}a${s1:sep+1}"
  run bash -c "printf '%s\n%s\n' '$bad' '$s2' | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" != *"$secret"* ]]
}

@test "a typo inside the parity field is repaired too (Codex review)" {
  # Раньше combine чинил тело, но сверял chk4 со всё ещё испорченным parity — и починка
  # не засчитывалась. Теперь исправленный parity возвращается вместе с телом.
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  s1="$(printf '%s\n' "$shares" | sed -n 1p)"; s2="$(printf '%s\n' "$shares" | sed -n 2p)"
  IFS=- read -r pfx sid T x yh par chk <<<"$s1"
  ppos=$(( ${#pfx} + 1 + ${#sid} + 1 + ${#T} + 1 + ${#x} + 1 + ${#yh} + 1 + 2 ))
  bad="$(_typo_at "$s1" "$ppos")"
  run bash -c "printf '%s\n%s\n' '$bad' '$s2' | bash '$SCRIPT' combine"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$secret"* ]]
}

@test "a parity field of the wrong length is called out, not silently accepted" {
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  s1="$(printf '%s\n' "$shares" | sed -n 1p)"; s2="$(printf '%s\n' "$shares" | sed -n 2p)"
  IFS=- read -r pfx sid T x yh par chk <<<"$s1"
  body="SSS3-${sid}-${T}-${x}-${yh}-${par:0:4}"
  newchk="$(printf '%s' "$body" | shasum -a 256 | cut -d' ' -f1)"
  run bash -c "printf '%s-%s\n%s\n' '$body' '${newchk:0:4}' '$s2' | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" != *"$secret"* ]]
}

@test "the repair notice is printed only after the payload tag verifies" {
  # «Починил» имеет смысл говорить лишь когда набор реально собрался: иначе пользователь
  # читал бы «исправлено» у долей, которые следом честно отвергнуты.
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  s1="$(printf '%s\n' "$shares" | sed -n 1p)"
  other="$(printf 'unrelated secret' | bash "$SCRIPT" split -n 3 -t 2 | sed -n 2p)"
  bad="$(_typo_at "$s1" 30)"
  run bash -c "printf '%s\n%s\n' '$bad' '$other' | bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" != *"corrected"* ]] && [[ "$output" != *"исправлено"* ]]
}
