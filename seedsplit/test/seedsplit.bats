# Tests for seedsplit (pack 1: scaffold — vendoring + skeleton + dispatcher).
setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../seedsplit"
  # A uname stub (-> Darwin) on PATH: the core will call require_macos. The tests never
  # touch macOS primitives; the stub keeps require_macos green on Linux CI (as in panic/ghostdraft).
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  export PATH="$STUBS:$PATH"
}

# Run a command under a pty. BSD (macOS): script -q <file> <cmd...>; GNU (util-linux, Linux CI):
# script -qec "<cmd>" <file>. We distinguish via `script --version` — probing "run true under a pty"
# turned out flaky, and uname lies here (a stub on PATH reports Darwin).
_pty() {
  if script --version 2>&1 | grep -qi util-linux; then
    script -qec "$*" /dev/null
  else
    script -q /dev/null "$@"
  fi
}

@test "version prints semver" {
  run bash "$SCRIPT" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"seedsplit"* ]]
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "no args prints usage and exits non-zero" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "help prints usage and exits zero" {
  run bash "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "--version flag prints version" { run bash "$SCRIPT" --version; [ "$status" -eq 0 ]; [[ "$output" == *"seedsplit"* ]]; }
@test "-v flag prints version" { run bash "$SCRIPT" -v; [ "$status" -eq 0 ]; [[ "$output" == *"seedsplit"* ]]; }
@test "--help flag prints usage" { run bash "$SCRIPT" --help; [ "$status" -eq 0 ]; [[ "$output" == *"Usage:"* ]]; }
@test "-h flag prints usage" { run bash "$SCRIPT" -h; [ "$status" -eq 0 ]; [[ "$output" == *"Usage:"* ]]; }

@test "unknown command exits non-zero" {
  run bash "$SCRIPT" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "vendored common is present and provides primitives" {
  run bash -c "source '$SCRIPT' 2>/dev/null; type info >/dev/null && type confirm >/dev/null && type require_macos >/dev/null && echo OK"
  [[ "$output" == *"OK"* ]]
}

@test "sourcing the script does not run the dispatcher" {
  run bash -c "source '$SCRIPT'; echo SOURCED_OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED_OK"* ]]
  [[ "$output" != *"Usage:"* ]]
}

@test "vendor --check passes (no drift)" {
  run bash "${BATS_TEST_DIRNAME}/../tools/vendor-common.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"синхронен"* ]] || [[ "$output" == *"sync"* ]]
}

@test "split with no secret prints error (not crash) — core is implemented" {
  # split with no stdin secret and no --file: must refuse clearly, not fail silently.
  run bash -c "printf '' | bash '$SCRIPT' split"
  [ "$status" -ne 0 ]
}

@test "split on a terminal prompts instead of silently waiting on stdin (P2-1)" {
  # Interactive `seedsplit split` used to wait on stdin silently — it read as a hang,
  # and the typed secret stayed in scrollback. A pty is required: without it the branch doesn't fire.
  command -v script >/dev/null 2>&1 || skip "script(1) unavailable"
  out="$( (sleep 0.4; printf 'correct horse battery staple\n'; sleep 0.4) \
          | _pty bash "$SCRIPT" split -n 2 -t 2 2>&1 )"
  [[ "$out" == *"Secret to split"* ]] || [[ "$out" == *"Секрет для разбиения"* ]]
  [[ "$out" == *"SSS3-"* ]]                        # shares are still produced
  [[ "$out" != *"correct horse battery staple"* ]] # and the secret is not echoed back
}

@test "TTY input reconstructs byte-for-byte, spaces included (Codex review)" {
  # Default IFS would strip leading/trailing spaces, and the same secret via the
  # terminal and via a pipe would yield different shares. Compare the reconstructed secret byte-for-byte.
  command -v script >/dev/null 2>&1 || skip "script(1) unavailable"
  secret='  two spaces  and trailing  '
  out="$( (sleep 0.4; printf '%s\n' "$secret"; sleep 0.4) \
          | _pty bash "$SCRIPT" split -n 2 -t 2 2>&1 )"
  shares="$(printf '%s\n' "$out" | tr -d '\r' | grep '^SSS3-')"
  [ -n "$shares" ]
  back="$(printf '%s\n' "$shares" | bash "$SCRIPT" combine)"
  [ "$back" = "$secret" ]
}

@test "piped stdin still works and shows no prompt (non-interactive path unchanged)" {
  run bash -c "printf 'correct horse battery staple' | bash '$SCRIPT' split -n 2 -t 2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SSS3-"* ]]
  [[ "$output" != *"Secret to split"* ]]
}

@test "vendor --check detects drift in the vendored block" {
  work="$(mktemp -d)"; mkdir -p "$work/tools"
  cp "${BATS_TEST_DIRNAME}/../seedsplit" "$work/seedsplit"
  cp "${BATS_TEST_DIRNAME}/../tools/vendor-common.sh" "$work/tools/"
  sed 's/_ST_COMMON_LOADED=1/_ST_COMMON_LOADED=999/' "$work/seedsplit" > "$work/seedsplit.mut"
  mv "$work/seedsplit.mut" "$work/seedsplit"
  run bash "$work/tools/vendor-common.sh" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ДРЕЙФ"* ]] || [[ "$output" == *"drift"* ]]
  rm -rf "$work"
}

@test "split/combine work without the macOS gate (POSIX-only dependencies)" {
  # The seedsplit core is GF(256) arithmetic on top of od/tr/printf: there are no macOS primitives
  # in it, and the ps1 port never had this gate at all. Run WITHOUT the uname stub reporting Darwin.
  secret='legal winner thank year wave'
  shares="$(printf '%s' "$secret" | env PATH="/usr/bin:/bin" bash "$SCRIPT" split -n 3 -t 2)"
  [[ "$shares" == *"SSS3-"* ]]
  back="$(printf '%s\n' "$shares" | head -2 | env PATH="/usr/bin:/bin" bash "$SCRIPT" combine)"
  [ "$back" = "$secret" ]
}
