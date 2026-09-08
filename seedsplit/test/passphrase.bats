# Tests for the passphrase layer (-p): the secret is encrypted with native openssl
# (AES-256-CBC/PBKDF2) BEFORE the Shamir split, so a reconstructed threshold of shares still
# requires the passphrase. The split/combine core is untouched. Env SEEDSPLIT_PASSPHRASE is for
# tests/automation (instead of /dev/tty). Requires openssl — without it the mode is unavailable
# and the tests are skipped.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../seedsplit"
  STUBS="${BATS_TEST_DIRNAME}/stubs"   # uname→Darwin: require_macos stays green on Linux CI
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
  # the reconstructed bytes BEFORE decryption = the sealed container (magic "SSPP2" + the openssl
  # container), NOT the plaintext secret
  sh="$(printf '%s\n' "$sel" | bash -c "ST_NO_MAIN=1 source '$SCRIPT' 2>/dev/null; _recover_secret_hex \"\$(cat)\"")"
  [[ "${sh:0:10}" == "5353505032" ]]
  [[ "$sh" != *"$(printf '%s' "$secret" | od -An -v -tx1 | tr -d ' \n')"* ]]
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
  # Replace reconstruction with a deliberately wrong one → split must catch the mismatch and abort
  # before printing. Without the self-check cmd_split would never call _recover_secret_hex → the
  # shares would get printed (and the test would fail).
  run bash -c "ST_NO_MAIN=1 source '$SCRIPT' 2>/dev/null
    _recover_secret_hex() { printf 'deadbeef'; }
    printf '%s' 'seedcafe' | cmd_split -n 3 -t 2"
  [ "$status" -ne 0 ]
  [[ "$output" != *"SSS2-"* ]]
}

@test "passphrase is never fed via a disk-backed here-string (no <<< spill, P1-5)" {
  # bash `<<<` materializes the string in a TEMP FILE on disk → the passphrase could be
  # read out of $TMPDIR/by carving. The passphrase must go through a pipe (process substitution).
  ! grep -qE '3<<<' "$SCRIPT"
}

@test "a wrong passphrase never yields a 'successful' wrong secret (F01, authenticated format)" {
  _need_openssl
  # The old format encrypted with `openssl enc` alone: a wrong passphrase that happened to leave
  # valid PKCS#7 padding (p ≈ 1/256) exited 0 and printed garbage as if it were the secret.
  # 300 wrong passphrases must now all be refused — the tag inside the ciphertext catches them.
  secret="correct horse battery staple"
  shares="$(printf '%s' "$secret" | SEEDSPLIT_PASSPHRASE=hunter2 bash "$SCRIPT" split -p -n 3 -t 2)"
  sel="$(printf '%s\n' "$shares" | sed -n '1p;2p')"
  local accepted=0 i out
  for ((i=0; i<300; i++)); do
    out="$(printf '%s\n' "$sel" | SEEDSPLIT_PASSPHRASE="wrong$i" bash "$SCRIPT" combine 2>/dev/null)" && accepted=$((accepted+1))
    [ -z "$out" ]
  done
  [ "$accepted" -eq 0 ]
}

@test "the -p container carries the authenticated magic SSPP2" {
  _need_openssl
  shares="$(printf '%s' "topsecretvalue" | SEEDSPLIT_PASSPHRASE=pw bash "$SCRIPT" split -p -n 3 -t 2)"
  sel="$(printf '%s\n' "$shares" | sed -n '1p;2p')"
  sh="$(printf '%s\n' "$sel" | bash -c "ST_NO_MAIN=1 source '$SCRIPT' 2>/dev/null; _recover_secret_hex \"\$(cat)\"")"
  [[ "${sh:0:10}" == "5353505032" ]]
  # and the openssl container proper begins right after the magic
  [[ "${sh:10:16}" == "53616c7465645f5f" ]]
}

# The work factor moved 200000 → 600000 (OWASP for PBKDF2-HMAC-SHA256) and `openssl enc` does not
# record it, so the number travels with the magic. A share printed on paper under SSPP1 cannot be
# rewritten — it has to keep opening, at ITS count, forever.
@test "an SSPP1 container written at 200000 iterations still combines" {
  _need_openssl
  secret="v1 paper share secret"
  tag="$(printf '%s' "$secret" | shasum -a 256 | cut -c1-32)"
  v1="${BATS_TEST_TMPDIR:-/tmp}/v1.bin"
  { printf 'SSPP1'
    { printf '%s' "$secret"; printf '%s' "$tag" | xxd -r -p; } \
      | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass pass:hunter2
  } > "$v1"
  sel="$(bash "$SCRIPT" split --file "$v1" -n 3 -t 2 | sed -n '1p;2p')"
  run bash -c "printf '%s\n' \"$sel\" | SEEDSPLIT_PASSPHRASE=hunter2 bash '$SCRIPT' combine"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$secret"* ]]
}

@test "an SSPP1 container is refused on a wrong passphrase, exactly like SSPP2" {
  _need_openssl
  secret="v1 paper share secret"
  tag="$(printf '%s' "$secret" | shasum -a 256 | cut -c1-32)"
  v1="${BATS_TEST_TMPDIR:-/tmp}/v1w.bin"
  { printf 'SSPP1'
    { printf '%s' "$secret"; printf '%s' "$tag" | xxd -r -p; } \
      | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass pass:hunter2
  } > "$v1"
  sel="$(bash "$SCRIPT" split --file "$v1" -n 3 -t 2 | sed -n '1p;2p')"
  run bash -c "printf '%s\n' \"$sel\" | SEEDSPLIT_PASSPHRASE=nothunter2 bash '$SCRIPT' combine"
  [ "$status" -ne 0 ]
  [[ "$output" != *"$secret"* ]]
}

@test "legacy passphrase shares still combine, with the no-authentication warning" {
  _need_openssl
  # A container cut before the authenticated format existed: bare `openssl enc` output split as
  # plain bytes. It must keep opening (old printouts stay usable) and say what it cannot promise.
  secret="legacy secret 42"
  legacy="${BATS_TEST_TMPDIR:-/tmp}/legacy.bin"
  printf '%s' "$secret" | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass pass:hunter2 > "$legacy"
  sel="$(bash "$SCRIPT" split --file "$legacy" -n 3 -t 2 | sed -n '1p;2p')"
  run bash -c "printf '%s\n' \"$sel\" | SEEDSPLIT_PASSPHRASE=hunter2 bash '$SCRIPT' combine"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$secret"* ]]
  [[ "$output" == *"LEGACY passphrase format"* ]]
}
