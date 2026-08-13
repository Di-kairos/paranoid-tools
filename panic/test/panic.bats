# Tests for panic (pack 1: scaffold — vendoring + skeleton + dispatcher).
setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../panic"
}

@test "version prints semver" {
  run bash "$SCRIPT" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"panic"* ]]
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

@test "unknown command exits non-zero" {
  run bash "$SCRIPT" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "--version flag prints version" {
  run bash "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"panic"* ]]
}

@test "-v flag prints version" {
  run bash "$SCRIPT" -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"panic"* ]]
}

@test "--help flag prints usage" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "-h flag prints usage" {
  run bash "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
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

# The `now` core is tested in now.bats WITH STUBS — without them `panic now` would run
# a real panic (detach images + lock) on the host. Here only scaffold/dispatcher.

@test "vendor --check detects drift in the vendored block" {
  work="$(mktemp -d)"; mkdir -p "$work/tools"
  cp "${BATS_TEST_DIRNAME}/../panic" "$work/panic"
  cp "${BATS_TEST_DIRNAME}/../tools/vendor-common.sh" "$work/tools/"
  # Mutate a line INSIDE the vendored block → --check must catch the drift (exit 1).
  # Portable (no sed -i: BSD/GNU diverge): sed into a file → mv.
  sed 's/_ST_COMMON_LOADED=1/_ST_COMMON_LOADED=999/' "$work/panic" > "$work/panic.mut"
  mv "$work/panic.mut" "$work/panic"
  run bash "$work/tools/vendor-common.sh" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ДРЕЙФ"* ]] || [[ "$output" == *"drift"* ]]
  rm -rf "$work"
}
