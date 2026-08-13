# unmount-guard tests: launchd WatchPaths auto-restores exclusions when the volume
# disappears bypassing `vaultwatch stop` (Finder eject / detach around securetrash post-close).
# macOS system commands are PATH stubs, so the tests also run on Linux CI.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../vaultwatch"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/Vault"
  MOUNT="$(cd "$TMP/Vault" && pwd -P)"
  export VW_STATE_DIR="$TMP/state"
  export VW_LAUNCH_DIR="$TMP/agents"
  export VW_STUB_LOG="$TMP/calls.log"
  export PATH="$STUBS:$PATH"
  export ST_ASSUME_YES=1
  unset ST_LANG
  # "Volume is present" = it is in the mount table, not "the directory exists".
  export STUB_MOUNTS="$TMP/mounts"
  _mark_mounted "$MOUNT"
}

teardown() { rm -rf "$TMP"; }

# Declare the volume mounted for the `mount` stub.
_mark_mounted() {
  printf '/dev/disk9s1 on %s (apfs, local, nodev, nosuid, journaled, nobrowse)\n' "$1" >"$STUB_MOUNTS"
}

# Unmount: remove the volume from the table. Leave the directory alone — that is
# exactly what a real leftover /Volumes/… looks like.
_mark_unmounted() { : >"$STUB_MOUNTS"; }

run_vw() { run env PATH="$STUBS:$PATH" bash "$SCRIPT" "$@"; }

# --- guard registration on start ---

@test "start registers an unmount-guard LaunchAgent (real schedule path)" {
  VW_NO_SPAWN=0 run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1   # plist written
  grep -q "bootstrap" "$VW_STUB_LOG"                                 # launchctl loaded it
  run cat "$VW_STATE_DIR"/*
  [[ "$output" == *"guard_label=com.vaultwatch.guard."* ]]
}

@test "guard plist watches the mount via WatchPaths and calls _guard_fire (not RunAtLoad)" {
  VW_NO_SPAWN=0 run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  run cat "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist
  [[ "$output" == *"WatchPaths"* ]]
  [[ "$output" == *"_guard_fire"* ]]
  [[ "$output" == *"$MOUNT"* ]]
  [[ "$output" != *"RunAtLoad"* ]]   # fire on the path change, NOT on load
}

@test "VW_NO_SPAWN=1 registers no guard (unit-test mode)" {
  VW_NO_SPAWN=1 run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  run cat "$VW_STATE_DIR"/*
  [[ "$output" != *"guard_label="* ]]
  ! ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1
}

@test "stop removes the unmount-guard LaunchAgent" {
  VW_NO_SPAWN=0 bash "$SCRIPT" start "$MOUNT" >/dev/null
  ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1   # present before stop
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  ! ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1 # plist removed
}

# --- _guard_fire: restores ONLY when the volume is really gone ---

@test "_guard_fire is a no-op while the mount still exists (WatchPaths fired on a write)" {
  VW_NO_SPAWN=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
  ls "$VW_STATE_DIR"/* >/dev/null 2>&1   # session NOT cleared — volume in place, nothing to restore
}

@test "_guard_fire restores and clears the session when the mount is gone (Finder-eject)" {
  VW_NO_SPAWN=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  ls "$VW_STATE_DIR"/* >/dev/null 2>&1    # session exists
  _mark_unmounted; rmdir "$MOUNT"         # simulate an unmount: the mountpoint is gone
  run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
  # WE turned indexing off, and it can only be turned back on on a mounted volume — so
  # the debt remains. The session is kept precisely as that debt (`pending_restore`): otherwise
  # the next start knows nothing about it and the exclusion stays on the volume forever.
  grep -q '^pending_restore=1$' "$VW_STATE_DIR"/*
}

@test "_guard_fire restores when the volume is gone but its directory is left behind" {
  # The main case: eject left an empty directory. The "directory exists" check considered the
  # volume mounted, the guard stayed silent, and the Spotlight exclusion was NEVER restored.
  VW_NO_SPAWN=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  _mark_unmounted                         # volume left the table, the directory remains
  [ -d "$MOUNT" ]
  run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
  # WE turned indexing off, and it can only be turned back on on a mounted volume — so
  # the debt remains. The session is kept precisely as that debt (`pending_restore`): otherwise
  # the next start knows nothing about it and the exclusion stays on the volume forever.
  grep -q '^pending_restore=1$' "$VW_STATE_DIR"/*
}

@test "_guard_fire keeps the exclusion while the mount table cannot be read" {
  # "Could not look" is no reason to drop protection from a possibly open volume.
  VW_NO_SPAWN=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  STUB_MOUNT_FAIL=1 run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
  ls "$VW_STATE_DIR"/* >/dev/null 2>&1    # session intact — nothing was restored blindly
}

@test "_guard_fire is a no-op on a neighbouring volume with a longer name" {
  # /…/Vault Backup being mounted is NOT /…/Vault. Substring comparison thought otherwise.
  VW_NO_SPAWN=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  _mark_mounted "$MOUNT Backup"           # the real volume left, the neighbour stayed
  run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
  # WE turned indexing off, and it can only be turned back on on a mounted volume — so
  # the debt remains. The session is kept precisely as that debt (`pending_restore`): otherwise
  # the next start knows nothing about it and the exclusion stays on the volume forever.
  grep -q '^pending_restore=1$' "$VW_STATE_DIR"/*
}

@test "_guard_fire with no session is a quiet success" {
  run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
}

@test "stop removes the guard plist even if the state lost guard_label (race-safe)" {
  VW_NO_SPAWN=0 bash "$SCRIPT" start "$MOUNT" >/dev/null
  ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1   # plist exists
  # simulate the bootstrap↔printf race: the guard_label write to state "did not make it"
  local sf; sf="$(ls "$VW_STATE_DIR"/*)"
  grep -v '^guard_label=' "$sf" > "$sf.tmp" && mv "$sf.tmp" "$sf"
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  ! ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1 # removed anyway (unconditional)
}
