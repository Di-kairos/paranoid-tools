# Тесты ядра panic (pack 2: now — detach образов, clipboard, lock screen).
# Системные команды подменяются стабами через PATH (+ PANIC_CGSESSION), поэтому
# тесты детерминированно гоняются и на Linux-CI.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../panic"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  TMP="$(mktemp -d)"
  export VW_STUB_LOG="$TMP/calls.log"
  export PANIC_CGSESSION="$STUBS/cgsession"
  export PATH="$STUBS:$PATH"
  export ST_ASSUME_YES=1
  unset ST_LANG
}

teardown() { rm -rf "$TMP"; }

run_now() { run env PATH="$STUBS:$PATH" PANIC_CGSESSION="$STUBS/cgsession" bash "$SCRIPT" now "$@"; }

@test "now detaches each mounted /Volumes disk image" {
  STUB_MOUNTS="/Volumes/SecretVault|/Volumes/Other" run_now
  [ "$status" -eq 0 ]
  grep -qF -- "detach -force /Volumes/SecretVault" "$VW_STUB_LOG"
  grep -qF -- "detach -force /Volumes/Other" "$VW_STUB_LOG"
}

@test "now does NOT detach a system image mounted outside /Volumes" {
  STUB_MOUNTS="/|/Volumes/SecretVault" run_now
  [ "$status" -eq 0 ]
  grep -qF -- "detach -force /Volumes/SecretVault" "$VW_STUB_LOG"
  ! grep -qE "detach -force /$" "$VW_STUB_LOG"
}

@test "now preserves a mountpoint with spaces" {
  STUB_MOUNTS="/Volumes/Secret Vault" run_now
  [ "$status" -eq 0 ]
  grep -qF -- "detach -force /Volumes/Secret Vault" "$VW_STUB_LOG"
}

@test "now clears the clipboard" {
  STUB_MOUNTS="/Volumes/SecretVault" run_now
  [ "$status" -eq 0 ]
  grep -q "pbcopy" "$VW_STUB_LOG"
}

@test "now locks the screen" {
  STUB_MOUNTS="/Volumes/SecretVault" run_now
  [ "$status" -eq 0 ]
  grep -qF -- "cgsession -suspend" "$VW_STUB_LOG"
}

@test "now with no mounted images still clears clipboard and locks" {
  STUB_MOUNTS="" run_now
  [ "$status" -eq 0 ]
  ! grep -q "detach" "$VW_STUB_LOG"
  grep -q "pbcopy" "$VW_STUB_LOG"
  grep -qF -- "cgsession -suspend" "$VW_STUB_LOG"
}

@test "now reports what it did" {
  STUB_MOUNTS="/Volumes/SecretVault" run_now
  [ "$status" -eq 0 ]
  [[ "$output" == *"clipboard"* ]] || [[ "$output" == *"буфер"* ]]
  [[ "$output" == *"lock"* ]] || [[ "$output" == *"заперт"* ]] || [[ "$output" == *"экран"* ]]
}

# --- честность блокировки (regression: раньше CGSession падал молча, а отчёт врал «locked») ---

@test "now falls back to osascript Ctrl+Cmd+Q when CGSession is missing" {
  STUB_MOUNTS="" run env PATH="$STUBS:$PATH" \
    PANIC_CGSESSION="$TMP/nonexistent-cgsession" PANIC_OSASCRIPT="$STUBS/osascript" \
    bash "$SCRIPT" now
  [ "$status" -eq 0 ]
  grep -qF -- "osascript" "$VW_STUB_LOG"
  [[ "$output" == *"locked"* ]] || [[ "$output" == *"заблокирован"* ]]
}

@test "now honestly warns when the screen could NOT be locked" {
  STUB_MOUNTS="" run env PATH="$STUBS:$PATH" \
    PANIC_CGSESSION="$TMP/nonexistent-cgsession" PANIC_OSASCRIPT="$STUBS/osascript" OSASCRIPT_EXIT=1 \
    bash "$SCRIPT" now
  [ "$status" -eq 0 ]                       # паника не падает, даже если лок не удался
  [[ "$output" == *"could NOT lock"* ]] || [[ "$output" == *"НЕ удалось заблокировать"* ]]
  [[ "$output" != *"screen locked"* ]]      # и НЕ врёт про успех
}

@test "now falls back to osascript when CGSession exists but returns non-zero" {
  # CGSession-бинарь есть, но -suspend упал (CGSESSION_EXIT=1) → обязан уйти в osascript.
  STUB_MOUNTS="" run env PATH="$STUBS:$PATH" \
    PANIC_CGSESSION="$STUBS/cgsession" CGSESSION_EXIT=1 PANIC_OSASCRIPT="$STUBS/osascript" \
    bash "$SCRIPT" now
  [ "$status" -eq 0 ]
  grep -qF -- "osascript" "$VW_STUB_LOG"     # fallback реально вызван
  [[ "$output" == *"locked"* ]] || [[ "$output" == *"заблокирован"* ]]
}

@test "now exit code survives a closed pipe (no SIGPIPE 141 from multi-line report)" {
  # Регрессия: второй stdout-строкой отчёта (lock_ok) под pipefail `panic now | head -n1`
  # ронял exit в 141, хотя паника успешна. Отчёт best-effort → pipeline status 0.
  STUB_MOUNTS="/Volumes/SecretVault" run env PATH="$STUBS:$PATH" \
    PANIC_CGSESSION="$STUBS/cgsession" \
    bash -o pipefail -c '"'"$SCRIPT"'" now | head -n1'
  [ "$status" -eq 0 ]
}
