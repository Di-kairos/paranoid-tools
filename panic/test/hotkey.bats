# Tests for `panic hotkey` — global hotkey via skhd.
# skhd and uname are replaced with stubs (uname → Darwin so require_macos passes on Linux CI);
# we only verify managed-config generation, not the real daemon.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../panic"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  TMP="$(mktemp -d)"
  export SKHD_CONFIG="$TMP/skhdrc"
  # Directory with uname only (no skhd) — for a deterministic "skhd is absent" test.
  mkdir -p "$TMP/noskhd"
  cp "$STUBS/uname" "$TMP/noskhd/uname"
  unset ST_LANG
}

teardown() { rm -rf "$TMP"; }

run_hk() { run env PATH="$STUBS:$PATH" SKHD_CONFIG="$SKHD_CONFIG" bash "$SCRIPT" hotkey "$@"; }

@test "hotkey install writes a managed skhd binding to 'panic now'" {
  run_hk install
  [ "$status" -eq 0 ]
  grep -qF "BEGIN panic hotkey" "$SKHD_CONFIG"
  grep -qE 'cmd \+ alt - p : ".*/panic" now' "$SKHD_CONFIG"
}

@test "hotkey install quotes the script path (survives paths with spaces)" {
  run_hk install
  [ "$status" -eq 0 ]
  # the panic path must be quoted — otherwise skhd splits the command on the space
  grep -qE ' : "[^"]*/panic" now' "$SKHD_CONFIG"
}

@test "hotkey install honors a custom combo" {
  run_hk install "cmd + shift - escape"
  [ "$status" -eq 0 ]
  grep -qE 'cmd \+ shift - escape : ".*/panic" now' "$SKHD_CONFIG"
}

@test "hotkey install rejects a combo containing a colon (injection guard)" {
  run_hk install "cmd - x : echo pwned"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid combo"* ]]
  ! grep -qF "echo pwned" "$SKHD_CONFIG" 2>/dev/null
}

@test "hotkey install preserves foreign skhd config (managed block only)" {
  printf 'alt - a : echo hi\n' > "$SKHD_CONFIG"
  run_hk install
  [ "$status" -eq 0 ]
  grep -qx "alt - a : echo hi" "$SKHD_CONFIG"
  grep -qF "BEGIN panic hotkey" "$SKHD_CONFIG"
}

@test "hotkey uninstall removes only the managed block" {
  printf 'alt - a : echo hi\n' > "$SKHD_CONFIG"
  run_hk install
  run_hk uninstall
  [ "$status" -eq 0 ]
  grep -qx "alt - a : echo hi" "$SKHD_CONFIG"
  ! grep -qF "BEGIN panic hotkey" "$SKHD_CONFIG"
}

@test "hotkey install is idempotent (no duplicate blocks)" {
  run_hk install
  run_hk install
  [ "$status" -eq 0 ]
  [ "$(grep -cF "BEGIN panic hotkey" "$SKHD_CONFIG")" -eq 1 ]
}

@test "hotkey status reports installed once a binding exists" {
  run_hk install
  run_hk status
  [ "$status" -eq 0 ]
  [[ "$output" == *"installed"* ]]
}

@test "hotkey status reports not installed initially" {
  run_hk status
  [ "$status" -eq 0 ]
  [[ "$output" == *"not installed"* ]]
}

@test "hotkey install fails clearly when skhd is absent" {
  run env PATH="$TMP/noskhd:/usr/bin:/bin" SKHD_CONFIG="$SKHD_CONFIG" bash "$SCRIPT" hotkey install
  [ "$status" -ne 0 ]
  [[ "$output" == *"skhd not found"* ]]
}

@test "hotkey install/uninstall keeps the skhd config's own permissions (P3 trap hygiene)" {
  # Previously the managed block was cut out via `mv` of a temp file — skhdrc ended up
  # with mktemp permissions (600) and the current user as owner instead of its own.
  printf 'alt - a : echo hi\n' > "$SKHD_CONFIG"
  chmod 0644 "$SKHD_CONFIG"
  # Permissions: GNU (Linux CI) `stat -c` first, BSD (macOS) `-f` as fallback — same canon
  # as in ghostdraft/test/ghostdraft.bats. The reverse order looked like it worked, but on
  # Linux `stat -f` means --file-system: it does not fail, it prints a filesystem report with
  # a `Free:` line that changes between calls. We were comparing free blocks, not permissions.
  before="$(stat -c '%a' "$SKHD_CONFIG" 2>/dev/null || stat -f '%Lp' "$SKHD_CONFIG")"
  run_hk install
  run_hk uninstall
  [ "$status" -eq 0 ]
  after="$(stat -c '%a' "$SKHD_CONFIG" 2>/dev/null || stat -f '%Lp' "$SKHD_CONFIG")"
  [ "$before" = "$after" ]
}
