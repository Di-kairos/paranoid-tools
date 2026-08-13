# Tests for the vaultwatch watcher core (pack 3b: start/stop, mdutil/tmutil, cloud, report).
# macOS system commands are replaced by PATH stubs (test/stubs), so the tests run
# deterministically on Linux CI too, where mdutil/tmutil are absent.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../vaultwatch"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/Vault"
  # Canonical physical path (mktemp under /var → symlink to /private/var on macOS);
  # vaultwatch canonicalizes the mount, so we compare against the same form of the path.
  MOUNT="$(cd "$TMP/Vault" && pwd -P)"
  export VW_STATE_DIR="$TMP/state"
  export VW_STUB_LOG="$TMP/calls.log"
  export PATH="$STUBS:$PATH"
  export ST_ASSUME_YES=1
  unset ST_LANG
  # "Volume is present" = it is in the mount table, not "the directory exists".
  export STUB_MOUNTS="$TMP/mounts"
  printf '/dev/disk9s1 on %s (apfs, local, nodev, nosuid, journaled, nobrowse)\n' "$MOUNT" >"$STUB_MOUNTS"
}

teardown() { rm -rf "$TMP"; }

run_vw() { run env PATH="$STUBS:$PATH" bash "$SCRIPT" "$@"; }

# --- start: validation ---

@test "start without mountpoint errors and exits non-zero" {
  run_vw start
  [ "$status" -ne 0 ]
}

@test "start on a non-existent path errors" {
  run_vw start "$TMP/nope"
  [ "$status" -ne 0 ]
}

# --- start: Spotlight ---

@test "start disables Spotlight indexing for the mount" {
  run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  grep -qF -- "-i off $MOUNT" "$VW_STUB_LOG"
}

@test "start records Spotlight prior state in session file" {
  STUB_SPOTLIGHT=enabled run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  run cat "$VW_STATE_DIR"/*
  [[ "$output" == *"spotlight_was=enabled"* ]]
}

# --- start: Time Machine ---

@test "start adds TM exclusion when mount is not already excluded" {
  STUB_TM_EXCLUDED=0 run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  grep -qF -- "addexclusion $MOUNT" "$VW_STUB_LOG"
}

@test "start does NOT add TM exclusion when already excluded" {
  STUB_TM_EXCLUDED=1 run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  ! grep -qF -- "addexclusion $MOUNT" "$VW_STUB_LOG"
  run cat "$VW_STATE_DIR"/*
  [[ "$output" == *"tm_added=0"* ]]
}

# --- start: cloud detect ---

@test "start reports an active cloud daemon" {
  STUB_CLOUD_PROCS="Dropbox" run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dropbox"* ]]
}

@test "start with no cloud daemons does not invent one" {
  STUB_CLOUD_PROCS="" run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Dropbox"* ]]
}

@test "start writes a session state file for the mount" {
  run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  [ -n "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]
}

# --- start: do not overwrite pre-session state on a repeat (P2-6) ---

@test "re-start on an existing session preserves original pre-session state" {
  # First start: Spotlight was ON, TM NOT excluded → the session fixes that and stop must restore it.
  STUB_SPOTLIGHT=enabled STUB_TM_EXCLUDED=0 bash "$SCRIPT" start "$MOUNT" >/dev/null
  # A repeated start (now Spotlight is OFF by us, TM excluded) must NOT rewrite the original state.
  STUB_SPOTLIGHT=disabled STUB_TM_EXCLUDED=1 run_vw start "$MOUNT"
  run cat "$VW_STATE_DIR"/*
  [[ "$output" == *"spotlight_was=enabled"* ]]
  [[ "$output" == *"tm_added=1"* ]]
}

# --- stop: validation / idempotency ---

@test "stop without mountpoint errors and exits non-zero" {
  run_vw stop
  [ "$status" -ne 0 ]
}

@test "stop with no active session is a quiet success" {
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no active"* ]] || [[ "$output" == *"нет активной"* ]]
}

# --- stop: Spotlight restore ---

@test "stop re-enables Spotlight when it was on before the session" {
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  grep -qF -- "-i on $MOUNT" "$VW_STUB_LOG"
}

@test "stop does NOT re-enable Spotlight when it was already off" {
  STUB_SPOTLIGHT=disabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  ! grep -qF -- "-i on $MOUNT" "$VW_STUB_LOG"
}

# --- stop: Time Machine restore ---

@test "stop removes TM exclusion that the session added" {
  STUB_TM_EXCLUDED=0 bash "$SCRIPT" start "$MOUNT" >/dev/null
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  grep -qF -- "removeexclusion $MOUNT" "$VW_STUB_LOG"
}

@test "stop does NOT remove a TM exclusion it did not add" {
  STUB_TM_EXCLUDED=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  ! grep -qF -- "removeexclusion $MOUNT" "$VW_STUB_LOG"
}

# --- stop: session report ---

@test "stop prints a session report with duration and swap honesty" {
  bash "$SCRIPT" start "$MOUNT" >/dev/null
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"session report"* ]]
  [[ "$output" == *"duration"* ]] || [[ "$output" == *"длительность"* ]]
  [[ "$output" == *"swap"* ]]
}

@test "stop reports local snapshots when present (honesty)" {
  bash "$SCRIPT" start "$MOUNT" >/dev/null
  STUB_SNAPSHOTS="2026-06-19-120000" run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"snapshots"* ]]
  [[ "$output" == *"limitations"* ]]
}

# --- stop: cleanup ---

@test "a mountpoint literally named --yes survives the -- escape (Codex review)" {
  # The global flag strip must not eat an operand after `--`.
  mkdir -p "$TMP/--yes"
  literal="$(cd "$TMP/--yes" && pwd -P)"
  run_vw start -- "$literal"
  [ "$status" -eq 0 ]
  run_vw stop -- "$literal"
  [ "$status" -eq 0 ]
}

@test "stop removes the session state file" {
  bash "$SCRIPT" start "$MOUNT" >/dev/null
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]
}

@test "stop calls restore N/A when the volume is gone but its directory is left behind" {
  # A leftover directory is not a volume: nothing to index, nothing for mdutil to act on.
  # With the old "directory exists" check stop invoked mdutil on an empty directory, caught
  # the refusal and kept the session forever, blocking the next start.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"                                # volume left the table, the directory remains
  STUB_MDUTIL_FAIL=1 run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  # The session stays precisely as a debt: we turned indexing off, it can only be restored on
  # a mounted volume, and the setting lives on the volume itself and survives remounting.
  grep -q '^pending_restore=1$' "$VW_STATE_DIR"/*
}

@test "stop does not claim it re-enabled indexing on a volume that is not mounted" {
  # The Spotlight setting stayed on the volume itself and will survive remounting — a report
  # claiming "indexing re-enabled" flatly lies to the user about their state.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"indexing re-enabled"* ]]
  [[ "$output" == *"NOT re-enabled"* ]]
  [[ "$output" == *"vaultwatch stop"* ]]   # tells how to get indexing back after all
}

@test "stop keeps the session when the mount table cannot be read" {
  # "Don't know whether it is mounted" → try to restore and fail honestly, not silently clean up.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  STUB_MOUNT_FAIL=1 STUB_MDUTIL_FAIL=1 run_vw stop "$MOUNT"
  [ "$status" -ne 0 ]
  [ -n "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]
}

@test "stop warns, keeps state AND exits non-zero when Spotlight restore fails" {
  # The non-zero code carries meaning here: the securetrash post-close hook and the launchd
  # timer learn that the exclusions were NOT restored instead of treating stop as a success.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  STUB_MDUTIL_FAIL=1 run_vw stop "$MOUNT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"restore"* ]] || [[ "$output" == *"восстан"* ]]
  [ -n "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]
}

# --- status: read-only session view ---

@test "status shows no sessions when nothing is running" {
  run_vw status
  [ "$status" -eq 0 ]
  [[ "$output" == *"no active"* ]] || [[ "$output" == *"нет активных"* ]]
}

@test "status shows active session after start" {
  bash "$SCRIPT" start "$MOUNT" >/dev/null
  run_vw status
  [ "$status" -eq 0 ]
  [[ "$output" == *"$MOUNT"* ]]
}

@test "status makes no destructive calls" {
  bash "$SCRIPT" start "$MOUNT" >/dev/null
  : > "$VW_STUB_LOG"   # reset the log after start — check only the status calls
  run_vw status
  [ "$status" -eq 0 ]
  ! grep -q "mdutil -i off" "$VW_STUB_LOG"
  ! grep -q "removeexclusion" "$VW_STUB_LOG"
}

@test "the next start settles an indexing debt left by a close that happened after unmount" {
  # The normal path: securetrash closes the vault (detach) and ONLY THEN calls the post-close
  # hook, so stop almost always sees the volume already gone and cannot restore indexing.
  # The setting lives on the volume itself and survives remounting — so the debt must
  # outlive the session close and be settled where the volume is reachable again: on the next start.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"                                # volume gone — as after vault close
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  grep -q '^pending_restore=1$' "$VW_STATE_DIR"/*  # debt recorded

  # The vault was opened again: volume in the table, mdutil reachable again.
  printf '/dev/disk9s1 on %s (apfs, local, nodev, nosuid, journaled, nobrowse)\n' "$MOUNT" >"$STUB_MOUNTS"
  : >"$VW_STUB_LOG"
  run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  grep -qF -- "mdutil -i on $MOUNT" "$VW_STUB_LOG"  # the debt is settled right here
  ! grep -q '^pending_restore=1$' "$VW_STATE_DIR"/* # and taken off the books
}

@test "a session with nothing owed is still cleared when the volume is gone" {
  # If indexing was off BEFORE us, there is nothing to restore — no debt,
  # and the session must close, otherwise the ghost would block watching.
  STUB_SPOTLIGHT=disabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]
}

@test "a debt is not lost when the restore itself fails at the next start" {
  # Settling the debt can fail (mdutil refused). Then the true pre-session state —
  # "indexing was ON" — must carry over into the new session: otherwise its stop would
  # "restore" a "was off" state, and the exclusion stays on the volume forever, silently.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"
  run_vw stop "$MOUNT"
  grep -q '^pending_restore=1$' "$VW_STATE_DIR"/*

  printf '/dev/disk9s1 on %s (apfs, local, nodev, nosuid, journaled, nobrowse)\n' "$MOUNT" >"$STUB_MOUNTS"
  # mdutil -i on fails while the volume state reads as "off" — the most treacherous
  # case: a naive start would remember "it was off before us".
  STUB_MDUTIL_FAIL=1 STUB_SPOTLIGHT=disabled run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  grep -q '^spotlight_was=enabled$' "$VW_STATE_DIR"/*
}

@test "status names the mount of a session that still owes a restore" {
  # A debt without a volume name is a debt the user will never find.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"
  run_vw stop "$MOUNT"
  run_vw status
  [ "$status" -eq 0 ]
  [[ "$output" == *"$MOUNT"* ]]
}
