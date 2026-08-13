# Тесты panic status (read-only preflight): образы, буфер, FileVault, cloud-демоны.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../panic"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  TMP="$(mktemp -d)"
  export VW_STUB_LOG="$TMP/calls.log"
  export PANIC_CGSESSION="$STUBS/cgsession"
  export PATH="$STUBS:$PATH"
  unset ST_LANG
}

teardown() { rm -rf "$TMP"; }

run_status() { run env PATH="$STUBS:$PATH" bash "$SCRIPT" status "$@"; }

@test "status exits zero and prints preflight header" {
  run_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"status"* ]]
}

@test "status lists mounted disk images that would be detached" {
  STUB_MOUNTS="/Volumes/SecretVault|/Volumes/Work" run_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"2"* ]]
  [[ "$output" == *"detach"* ]] || [[ "$output" == *"размонт"* ]]
}

@test "status reports no mounted images when none present" {
  STUB_MOUNTS="" run_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"none"* ]] || [[ "$output" == *"не смонтировано"* ]]
}

@test "status reports non-empty clipboard" {
  STUB_CLIPBOARD="secret data" run_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-empty"* ]] || [[ "$output" == *"не пуст"* ]]
}

@test "status reports empty clipboard" {
  STUB_CLIPBOARD="" run_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"empty"* ]] || [[ "$output" == *"пуст"* ]]
}

@test "status survives a failing pbpaste (best-effort clipboard, no exit 1)" {
  # headless/sandbox: pbpaste падает под set -euo pipefail — read-only статус НЕ должен
  # обрываться на буфере и выходить с кодом 1, а честно сказать «неизвестно» и продолжить.
  STUB_PBPASTE_FAIL=1 run_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]] || [[ "$output" == *"неизвестно"* ]]
  [[ "$output" == *"FileVault"* ]]   # дошёл до проверок ПОСЛЕ буфера, не оборвался
}

@test "status reports FileVault ON" {
  STUB_FV=on run_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"FileVault"* ]]
  [[ "$output" == *"ON"* ]] || [[ "$output" == *"ВКЛ"* ]]
}

@test "status warns when FileVault is OFF" {
  STUB_FV=off run_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"OFF"* ]] || [[ "$output" == *"ВЫКЛ"* ]]
}

@test "status reports a running cloud daemon" {
  STUB_RUNNING="Dropbox" run_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dropbox"* ]]
  [[ "$output" == *"--hard"* ]]
}

@test "status does NOT make any destructive calls (no detach, pbcopy, cgsession)" {
  STUB_MOUNTS="/Volumes/SecretVault" STUB_CLIPBOARD="data" run_status
  [ "$status" -eq 0 ]
  ! grep -q "detach" "${TMP}/calls.log" 2>/dev/null
  ! grep -q "pbcopy" "${TMP}/calls.log" 2>/dev/null
  ! grep -q "cgsession" "${TMP}/calls.log" 2>/dev/null
}
