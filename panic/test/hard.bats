# Тесты panic --hard (pack 3: прибить cloud-демоны + почистить Recent items).
# Стабы через PATH (pkill) + PANIC_CGSESSION + PANIC_SFL_DIR — детерминированно и на Linux-CI.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../panic"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  TMP="$(mktemp -d)"
  export VW_STUB_LOG="$TMP/calls.log"
  export PANIC_CGSESSION="$STUBS/cgsession"
  export PANIC_SFL_DIR="$TMP/sfl"
  export PATH="$STUBS:$PATH"
  export ST_ASSUME_YES=1
  export STUB_MOUNTS=""    # без образов — фокус на --hard
  unset ST_LANG
  mkdir -p "$PANIC_SFL_DIR"
  : > "$PANIC_SFL_DIR/com.apple.LSSharedFileList.RecentDocuments.sfl3"
  : > "$PANIC_SFL_DIR/com.apple.LSSharedFileList.RecentApplications.sfl2"
}

teardown() { rm -rf "$TMP"; }

run_now() {
  run env PATH="$STUBS:$PATH" PANIC_CGSESSION="$STUBS/cgsession" \
    PANIC_SFL_DIR="$PANIC_SFL_DIR" bash "$SCRIPT" now "$@"
}

@test "now --hard kills known cloud daemons" {
  run_now --hard
  [ "$status" -eq 0 ]
  grep -q "pkill.*Dropbox" "$VW_STUB_LOG"
  grep -q "pkill.*OneDrive" "$VW_STUB_LOG"
  grep -q "pkill.*bird" "$VW_STUB_LOG"
  grep -q "pkill.*Google Drive" "$VW_STUB_LOG"
}

@test "now --hard clears recent-items shared file lists" {
  run_now --hard
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$PANIC_SFL_DIR" 2>/dev/null)" ]   # sfl-файлы удалены
}

@test "now WITHOUT --hard does not kill daemons or clear recents" {
  run_now
  [ "$status" -eq 0 ]
  ! grep -q "pkill" "$VW_STUB_LOG"
  [ -n "$(ls -A "$PANIC_SFL_DIR" 2>/dev/null)" ]    # recent items целы
}

@test "now --hard still performs base actions (clipboard, lock)" {
  run_now --hard
  [ "$status" -eq 0 ]
  grep -q "pbcopy" "$VW_STUB_LOG"
  grep -qF -- "cgsession -suspend" "$VW_STUB_LOG"
}

@test "now --hard report mentions hard actions" {
  run_now --hard
  [ "$status" -eq 0 ]
  [[ "$output" == *"hard"* ]] || [[ "$output" == *"демон"* ]] || [[ "$output" == *"daemon"* ]]
}
