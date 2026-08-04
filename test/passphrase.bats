# Тесты passphrase-слоя (-p): секрет шифруется native openssl'ом (AES-256-CBC/PBKDF2) ДО
# Shamir-разбиения, так что собранный порог долей всё равно требует passphrase. Ядро split/
# combine не затронуто. Env SEEDSPLIT_PASSPHRASE — для тестов/автоматизации (вместо /dev/tty).
# Требует openssl — без него режим недоступен, тесты пропускаются (skip).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../seedsplit"
  STUBS="${BATS_TEST_DIRNAME}/stubs"   # uname→Darwin: require_macos зелёный на Linux-CI
  export PATH="$STUBS:$PATH"
}

_need_openssl() { command -v openssl >/dev/null 2>&1 || skip "openssl not on PATH"; }

@test "split -p + combine with the right passphrase round-trips" {
  _need_openssl
  secret="correct horse battery staple"
  shares="$(printf '%s' "$secret" | SEEDSPLIT_PASSPHRASE=hunter2 bash "$SCRIPT" split -p -n 3 -t 2)"
  sel="$(printf '%s\n' "$shares" | sed -n '1p;2p')"
  out="$(printf '%s\n' "$sel" | SEEDSPLIT_PASSPHRASE=hunter2 bash "$SCRIPT" combine)"
  [ "$out" = "$secret" ]
}

@test "combine with the wrong passphrase fails and never prints the secret" {
  _need_openssl
  secret="correct horse battery staple"
  shares="$(printf '%s' "$secret" | SEEDSPLIT_PASSPHRASE=hunter2 bash "$SCRIPT" split -p -n 3 -t 2)"
  sel="$(printf '%s\n' "$shares" | sed -n '1p;2p')"
  run bash -c "printf '%s\n' \"$sel\" | SEEDSPLIT_PASSPHRASE=wrongpass bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" != *"$secret"* ]]
}

@test "a reconstructed -p threshold yields a sealed openssl container, not the secret" {
  _need_openssl
  secret="topsecretvalue"
  shares="$(printf '%s' "$secret" | SEEDSPLIT_PASSPHRASE=pw bash "$SCRIPT" split -p -n 3 -t 2)"
  sel="$(printf '%s\n' "$shares" | sed -n '1p;2p')"
  # восстановленные байты ДО расшифровки = стандартный openssl-контейнер (magic "Salted__"),
  # а НЕ открытый секрет
  sh="$(printf '%s\n' "$sel" | bash -c "ST_NO_MAIN=1 source '$SCRIPT' 2>/dev/null; _recover_secret_hex \"\$(cat)\"")"
  [[ "${sh:0:16}" == "53616c7465645f5f" ]]
}

@test "without -p the secret is split as plaintext (core path untouched)" {
  secret="plain text secret"
  shares="$(printf '%s' "$secret" | bash "$SCRIPT" split -n 3 -t 2)"
  out="$(printf '%s\n' "$shares" | sed -n '1p;2p' | bash "$SCRIPT" combine)"
  [ "$out" = "$secret" ]
}

@test "-p shares carry the normal SSS3 wire format (passphrase sits below the Shamir layer)" {
  _need_openssl
  shares="$(printf '%s' "x" | SEEDSPLIT_PASSPHRASE=pw bash "$SCRIPT" split -p -n 3 -t 2)"
  [ "$(printf '%s\n' "$shares" | grep -c '^SSS3-')" -eq 3 ]
}

@test "split aborts with no output if the round-trip self-check fails (MED)" {
  # Подменяем сборку на заведомо неверную → split обязан поймать mismatch и прерваться до печати.
  # Без self-check cmd_split не звал бы _recover_secret_hex → доли напечатались бы (тест бы упал).
  run bash -c "ST_NO_MAIN=1 source '$SCRIPT' 2>/dev/null
    _recover_secret_hex() { printf 'deadbeef'; }
    printf '%s' 'seedcafe' | cmd_split -n 3 -t 2"
  [ "$status" -ne 0 ]
  [[ "$output" != *"SSS2-"* ]]
}

@test "passphrase is never fed via a disk-backed here-string (no <<< spill, P1-5)" {
  # bash `<<<` материализует строку во ВРЕМЕННЫЙ ФАЙЛ на диске → passphrase может быть
  # вычитан из $TMPDIR/карвингом. Passphrase обязан идти через pipe (process substitution).
  ! grep -qE '3<<<' "$SCRIPT"
}
