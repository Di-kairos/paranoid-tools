# vaultwatch tests (pack 3a: vendoring + hook installer).
setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../vaultwatch"
  STUBS="${BATS_TEST_DIRNAME}/stubs"   # uname→Darwin etc., so the tests also run on Linux CI
}

@test "version prints semver" {
  run bash "$SCRIPT" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"vaultwatch"* ]]
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "--yes is accepted anywhere in the args and does not become a command" {
  # securetrash contract: the flag is stripped, the remaining arguments keep their order.
  run bash "$SCRIPT" --yes version
  [ "$status" -eq 0 ]
  [[ "$output" == *"vaultwatch"* ]]
  run bash "$SCRIPT" version --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"vaultwatch"* ]]
}

@test "--yes alone is not treated as a command (usage, non-zero)" {
  run bash "$SCRIPT" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" != *"Unknown command"* ]]
}

@test "usage documents the --yes flag" {
  run bash "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--yes"* ]]
}

@test "--version flag prints version" {
  run bash "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"vaultwatch"* ]]
}

@test "-v flag prints version" {
  run bash "$SCRIPT" -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"vaultwatch"* ]]
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

@test "no args prints usage and exits non-zero" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

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

@test "install-hooks writes managed, executable post-open/post-close" {
  tmp="$(mktemp -d)"; hooks="$tmp/hooks"
  run env ST_HOOK_DIR="$hooks" bash "$SCRIPT" install-hooks
  [ "$status" -eq 0 ]
  [ -x "$hooks/post-open" ]
  [ -x "$hooks/post-close" ]
  grep -q "managed-by: vaultwatch" "$hooks/post-open"
  grep -q "managed-by: vaultwatch" "$hooks/post-close"
  grep -q "start" "$hooks/post-open"
  grep -q "stop" "$hooks/post-close"
  rm -rf "$tmp"
}

@test "install-hooks does NOT clobber a foreign hook" {
  tmp="$(mktemp -d)"; hooks="$tmp/hooks"; mkdir -p "$hooks"
  printf '#!/usr/bin/env bash\necho custom\n' > "$hooks/post-open"
  chmod +x "$hooks/post-open"
  run env ST_HOOK_DIR="$hooks" bash "$SCRIPT" install-hooks
  [ "$status" -eq 0 ]
  grep -q "custom" "$hooks/post-open"          # foreign hook intact
  ! grep -q "managed-by: vaultwatch" "$hooks/post-open"
  grep -q "managed-by: vaultwatch" "$hooks/post-close"   # our own installed
  rm -rf "$tmp"
}

@test "uninstall-hooks removes managed but keeps foreign" {
  tmp="$(mktemp -d)"; hooks="$tmp/hooks"; mkdir -p "$hooks"
  env ST_HOOK_DIR="$hooks" bash "$SCRIPT" install-hooks
  printf '#!/usr/bin/env bash\n# managed-by: vaultwatch\n' > "$hooks/post-open"  # managed
  printf '#!/usr/bin/env bash\necho custom\n' > "$hooks/post-close"              # foreign
  run env ST_HOOK_DIR="$hooks" bash "$SCRIPT" uninstall-hooks
  [ "$status" -eq 0 ]
  [ ! -e "$hooks/post-open" ]                   # managed removed
  grep -q "custom" "$hooks/post-close"          # foreign intact
  rm -rf "$tmp"
}

@test "installed post-open hook forwards the mountpoint to start" {
  tmp="$(mktemp -d)"; hooks="$tmp/hooks"
  env ST_HOOK_DIR="$hooks" bash "$SCRIPT" install-hooks
  # The hook invokes `vaultwatch start <mount>`. A nonexistent path → start fails
  # (mount not found, exit 1) with that path in the message — proving the argument is forwarded.
  run env PATH="$STUBS:$PATH" bash "$hooks/post-open" /Volumes/NoSuchVault
  [ "$status" -ne 0 ]
  [[ "$output" == *"/Volumes/NoSuchVault"* ]]
  rm -rf "$tmp"
}

@test "installed post-open hook preserves a mountpoint with spaces" {
  tmp="$(mktemp -d)"; hooks="$tmp/hooks"
  env ST_HOOK_DIR="$hooks" bash "$SCRIPT" install-hooks
  run env PATH="$STUBS:$PATH" bash "$hooks/post-open" "/Volumes/Secret Vault"
  [ "$status" -ne 0 ]
  [[ "$output" == *"/Volumes/Secret Vault"* ]]   # spaces in the path survive through the hook
  rm -rf "$tmp"
}

@test "uninstall-hooks on a clean dir is a quiet success" {
  tmp="$(mktemp -d)"; hooks="$tmp/hooks"; mkdir -p "$hooks"
  run env ST_HOOK_DIR="$hooks" bash "$SCRIPT" uninstall-hooks
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
}

@test "vendor --check detects drift in the vendored block" {
  work="$(mktemp -d)"; mkdir -p "$work/tools"
  cp "${BATS_TEST_DIRNAME}/../vaultwatch" "$work/vaultwatch"
  cp "${BATS_TEST_DIRNAME}/../tools/vendor-common.sh" "$work/tools/"
  # Mutate a line INSIDE the vendored block → --check must catch the drift (exit 1).
  # Portable (no sed -i: BSD/GNU diverge): sed into a file → mv.
  sed 's/_ST_COMMON_LOADED=1/_ST_COMMON_LOADED=999/' "$work/vaultwatch" > "$work/vaultwatch.mut"
  mv "$work/vaultwatch.mut" "$work/vaultwatch"
  run bash "$work/tools/vendor-common.sh" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ДРЕЙФ"* ]] || [[ "$output" == *"drift"* ]]
  rm -rf "$work"
}
