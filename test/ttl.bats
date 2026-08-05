# Тесты --ttl авто-выхода (pack 3c): парсинг длительности, планирование в state,
# и _ttl_fire (lsof-чек → hdiutil detach / honest warn). Системные команды —
# стабы через PATH, поэтому тесты идут и на Linux-CI без macOS-тулзов.

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
  export VW_NO_SPAWN=1   # по умолчанию не грузить launchd-таймер (юнит-тесты состояния)
  unset ST_LANG
  # «Том на месте» = он есть в таблице монтирования, а не «каталог существует».
  export STUB_MOUNTS="$TMP/mounts"
  printf '/dev/disk9s1 on %s (apfs, local, nodev, nosuid, journaled, nobrowse)\n' "$MOUNT" >"$STUB_MOUNTS"
}

teardown() { rm -rf "$TMP"; }

run_vw() { run env PATH="$STUBS:$PATH" bash "$SCRIPT" "$@"; }

# --- _parse_duration ---

@test "_parse_duration converts unit suffixes to seconds" {
  source "$SCRIPT"
  [ "$(_parse_duration 45s)" -eq 45 ]
  [ "$(_parse_duration 30m)" -eq 1800 ]
  [ "$(_parse_duration 2h)" -eq 7200 ]
  [ "$(_parse_duration 1d)" -eq 86400 ]
}

@test "_parse_duration treats a bare number as seconds" {
  source "$SCRIPT"
  [ "$(_parse_duration 90)" -eq 90 ]
}

@test "_parse_duration rejects garbage" {
  source "$SCRIPT"
  run _parse_duration abc
  [ "$status" -ne 0 ]
  run _parse_duration ""
  [ "$status" -ne 0 ]
}

# --- start --ttl ---

@test "start --ttl records ttl seconds in the session state" {
  run_vw start --ttl 30m "$MOUNT"
  [ "$status" -eq 0 ]
  run cat "$VW_STATE_DIR"/*
  [[ "$output" == *"ttl_secs=1800"* ]]
}

@test "start --ttl with bad duration errors" {
  run_vw start --ttl nope "$MOUNT"
  [ "$status" -ne 0 ]
}

@test "start without --ttl records no ttl timer" {
  run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  run cat "$VW_STATE_DIR"/*
  [[ "$output" != *"ttl_secs="* ]] || [[ "$output" == *"ttl_secs=0"* ]]
}

@test "start --force --ttl records force flag" {
  run_vw start --force --ttl 10m "$MOUNT"
  [ "$status" -eq 0 ]
  run cat "$VW_STATE_DIR"/*
  [[ "$output" == *"ttl_force=1"* ]]
}

# --- _ttl_fire ---

@test "ttl fire detaches an idle vault and clears the session" {
  bash "$SCRIPT" start --ttl 30m "$MOUNT" >/dev/null
  STUB_LSOF_BUSY=0 run_vw _ttl_fire "$MOUNT"
  [ "$status" -eq 0 ]
  grep -qF -- "detach $MOUNT" "$VW_STUB_LOG"
  [ -z "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]   # сессия закрыта
}

@test "ttl fire does NOT detach a busy vault without force" {
  bash "$SCRIPT" start --ttl 30m "$MOUNT" >/dev/null
  STUB_LSOF_BUSY=1 run_vw _ttl_fire "$MOUNT"
  [ "$status" -eq 0 ]
  ! grep -q "detach" "$VW_STUB_LOG"
  [ -n "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]   # сессия цела (честно: не смогли закрыть)
  [[ "$output" == *"open files"* ]] || [[ "$output" == *"открыты файлы"* ]]
}

@test "ttl fire force-detaches a busy vault when force was set" {
  bash "$SCRIPT" start --force --ttl 30m "$MOUNT" >/dev/null
  STUB_LSOF_BUSY=1 run_vw _ttl_fire "$MOUNT"
  [ "$status" -eq 0 ]
  grep -qF -- "detach -force $MOUNT" "$VW_STUB_LOG"
  [ -z "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]
}

@test "ttl fire on a vault with no session is a quiet success" {
  STUB_LSOF_BUSY=0 run_vw _ttl_fire "$MOUNT"
  [ "$status" -eq 0 ]
  ! grep -q "detach" "$VW_STUB_LOG"
}

# --- launchd-таймер (pack 3d): schedule / cancel ---

@test "start --ttl writes and bootstraps a LaunchAgent (real schedule path)" {
  VW_NO_SPAWN=0 run_vw start --ttl 30m "$MOUNT"
  [ "$status" -eq 0 ]
  ls "$VW_LAUNCH_DIR"/com.vaultwatch.ttl.*.plist >/dev/null 2>&1   # plist записан
  grep -q "bootstrap" "$VW_STUB_LOG"                               # launchctl загрузил
  run cat "$VW_STATE_DIR"/*
  [[ "$output" == *"ttl_label=com.vaultwatch.ttl."* ]]
}

@test "LaunchAgent plist references _ttl_fire with the mountpoint" {
  VW_NO_SPAWN=0 run_vw start --ttl 10m "$MOUNT"
  [ "$status" -eq 0 ]
  run cat "$VW_LAUNCH_DIR"/com.vaultwatch.ttl.*.plist
  [[ "$output" == *"_ttl_fire"* ]]
  [[ "$output" == *"$MOUNT"* ]]
  [[ "$output" == *"RunAtLoad"* ]]
}

@test "stop removes the scheduled LaunchAgent" {
  VW_NO_SPAWN=0 bash "$SCRIPT" start --ttl 30m "$MOUNT" >/dev/null
  ls "$VW_LAUNCH_DIR"/com.vaultwatch.ttl.*.plist >/dev/null 2>&1   # есть до stop
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  ! ls "$VW_LAUNCH_DIR"/com.vaultwatch.ttl.*.plist >/dev/null 2>&1 # plist снят
  grep -q "bootout" "$VW_STUB_LOG"                                 # launchctl выгрузил
}

@test "ttl fire removes its own LaunchAgent after detach" {
  VW_NO_SPAWN=0 bash "$SCRIPT" start --ttl 30m "$MOUNT" >/dev/null
  STUB_LSOF_BUSY=0 run_vw _ttl_fire "$MOUNT"
  [ "$status" -eq 0 ]
  ! ls "$VW_LAUNCH_DIR"/com.vaultwatch.ttl.*.plist >/dev/null 2>&1
}

@test "ttl fire does not call a successful detach a failure over a leftover directory" {
  # detach сработал, том ушёл из таблицы, но каталог остался. Проверка «каталог есть»
  # объявляла бы «dismount не удался, сейф может быть открыт» — и это была бы ложь.
  bash "$SCRIPT" start --ttl 30m "$MOUNT" >/dev/null
  STUB_LSOF_BUSY=0 STUB_DETACH_LEAVES_DIR=1 run_vw _ttl_fire "$MOUNT"
  [ "$status" -eq 0 ]
  [ -d "$MOUNT" ]                                  # каталог на месте
  [ -z "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]    # сессия всё равно закрыта корректно
}

@test "ttl fire keeps session state when the mount table cannot be read" {
  # «Не знаем» после detach трактуем как «может быть открыт»: сессию не чистим.
  bash "$SCRIPT" start --ttl 30m "$MOUNT" >/dev/null
  STUB_LSOF_BUSY=0 STUB_MOUNT_FAIL=1 run_vw _ttl_fire "$MOUNT"
  [ "$status" -ne 0 ]
  [ -n "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]
}

@test "ttl fire keeps session state when detach does not unmount the vault" {
  bash "$SCRIPT" start --ttl 30m "$MOUNT" >/dev/null
  STUB_LSOF_BUSY=0 STUB_DETACH_FAIL=1 run_vw _ttl_fire "$MOUNT"
  [ "$status" -ne 0 ]
  [ -n "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]
  [[ "$output" == *"detach"* ]]
}

@test "start --ttl warns and stores no label when launchd bootstrap fails" {
  VW_NO_SPAWN=0 STUB_LAUNCHCTL_FAIL=1 run_vw start --ttl 30m "$MOUNT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bootstrap"* ]] || [[ "$output" == *"launchd"* ]]
  run cat "$VW_STATE_DIR"/* 2>/dev/null
  [[ "$output" != *"ttl_label=com.vaultwatch"* ]]
}
