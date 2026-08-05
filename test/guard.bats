# Тесты unmount-guard: launchd WatchPaths авто-восстанавливает исключения, если том
# исчезает мимо `vaultwatch stop` (Finder-eject / detach в обход securetrash post-close).
# Системные команды macOS — стабы через PATH, поэтому тесты идут и на Linux-CI.

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
  # «Том на месте» = он есть в таблице монтирования, а не «каталог существует».
  export STUB_MOUNTS="$TMP/mounts"
  _mark_mounted "$MOUNT"
}

teardown() { rm -rf "$TMP"; }

# Объявить том примонтированным для стаба `mount`.
_mark_mounted() {
  printf '/dev/disk9s1 on %s (apfs, local, nodev, nosuid, journaled, nobrowse)\n' "$1" >"$STUB_MOUNTS"
}

# Размонтировать: убрать том из таблицы. Каталог при этом не трогаем — реальный
# остаточный /Volumes/… именно так и выглядит.
_mark_unmounted() { : >"$STUB_MOUNTS"; }

run_vw() { run env PATH="$STUBS:$PATH" bash "$SCRIPT" "$@"; }

# --- регистрация guard на start ---

@test "start registers an unmount-guard LaunchAgent (real schedule path)" {
  VW_NO_SPAWN=0 run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1   # plist записан
  grep -q "bootstrap" "$VW_STUB_LOG"                                 # launchctl загрузил
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
  [[ "$output" != *"RunAtLoad"* ]]   # палим по изменению пути, НЕ по загрузке
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
  ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1   # есть до stop
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  ! ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1 # plist снят
}

# --- _guard_fire: восстанавливает ТОЛЬКО когда том реально исчез ---

@test "_guard_fire is a no-op while the mount still exists (WatchPaths fired on a write)" {
  VW_NO_SPAWN=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
  ls "$VW_STATE_DIR"/* >/dev/null 2>&1   # сессия НЕ снята — том на месте, ничего не восстанавливаем
}

@test "_guard_fire restores and clears the session when the mount is gone (Finder-eject)" {
  VW_NO_SPAWN=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  ls "$VW_STATE_DIR"/* >/dev/null 2>&1    # сессия есть
  _mark_unmounted; rmdir "$MOUNT"         # имитируем размонтаж: mountpoint исчез
  run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
  ! ls "$VW_STATE_DIR"/* >/dev/null 2>&1  # сессия снята — restore прошёл без смонтированного тома
}

@test "_guard_fire restores when the volume is gone but its directory is left behind" {
  # Главный кейс: eject оставил пустой каталог. Проверка «каталог есть» считала том
  # смонтированным, guard молчал, и исключение Spotlight не восстанавливалось НИКОГДА.
  VW_NO_SPAWN=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  _mark_unmounted                         # том ушёл из таблицы, каталог остался
  [ -d "$MOUNT" ]
  run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
  ! ls "$VW_STATE_DIR"/* >/dev/null 2>&1  # сессия снята, исключение восстановлено
}

@test "_guard_fire keeps the exclusion while the mount table cannot be read" {
  # «Не смогли посмотреть» — не повод снимать защиту с возможно открытого тома.
  VW_NO_SPAWN=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  STUB_MOUNT_FAIL=1 run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
  ls "$VW_STATE_DIR"/* >/dev/null 2>&1    # сессия цела — ничего не восстанавливали вслепую
}

@test "_guard_fire is a no-op on a neighbouring volume with a longer name" {
  # Смонтирован /…/Vault Backup — это НЕ /…/Vault. Подстрочное сравнение считало иначе.
  VW_NO_SPAWN=1 bash "$SCRIPT" start "$MOUNT" >/dev/null
  _mark_mounted "$MOUNT Backup"           # настоящий том ушёл, соседний на месте
  run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
  ! ls "$VW_STATE_DIR"/* >/dev/null 2>&1  # том действительно исчез → сессия снята
}

@test "_guard_fire with no session is a quiet success" {
  run_vw _guard_fire "$MOUNT"
  [ "$status" -eq 0 ]
}

@test "stop removes the guard plist even if the state lost guard_label (race-safe)" {
  VW_NO_SPAWN=0 bash "$SCRIPT" start "$MOUNT" >/dev/null
  ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1   # plist есть
  # имитируем гонку bootstrap↔printf: запись guard_label в state «не успела»
  local sf; sf="$(ls "$VW_STATE_DIR"/*)"
  grep -v '^guard_label=' "$sf" > "$sf.tmp" && mv "$sf.tmp" "$sf"
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  ! ls "$VW_LAUNCH_DIR"/com.vaultwatch.guard.*.plist >/dev/null 2>&1 # всё равно снят (unconditional)
}
