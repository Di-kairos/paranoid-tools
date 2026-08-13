# Тесты ядра сторожа vaultwatch (pack 3b: start/stop, mdutil/tmutil, cloud, report).
# Системные команды macOS подменяются стабами через PATH (test/stubs), поэтому
# тесты детерминированно гоняются и на Linux-CI, где mdutil/tmutil отсутствуют.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../vaultwatch"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/Vault"
  # Канонический физический путь (mktemp под /var → симлинк на /private/var на macOS);
  # vaultwatch канонизирует mount, поэтому сверяем по тому же виду пути.
  MOUNT="$(cd "$TMP/Vault" && pwd -P)"
  export VW_STATE_DIR="$TMP/state"
  export VW_STUB_LOG="$TMP/calls.log"
  export PATH="$STUBS:$PATH"
  export ST_ASSUME_YES=1
  unset ST_LANG
  # «Том на месте» = он есть в таблице монтирования, а не «каталог существует».
  export STUB_MOUNTS="$TMP/mounts"
  printf '/dev/disk9s1 on %s (apfs, local, nodev, nosuid, journaled, nobrowse)\n' "$MOUNT" >"$STUB_MOUNTS"
}

teardown() { rm -rf "$TMP"; }

run_vw() { run env PATH="$STUBS:$PATH" bash "$SCRIPT" "$@"; }

# --- start: валидация ---

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

# --- start: не затирать до-сессионное состояние при повторе (P2-6) ---

@test "re-start on an existing session preserves original pre-session state" {
  # Первый start: Spotlight был ВКЛ, TM НЕ исключён → сессия чинит и это надо восстановить на stop.
  STUB_SPOTLIGHT=enabled STUB_TM_EXCLUDED=0 bash "$SCRIPT" start "$MOUNT" >/dev/null
  # Повторный start (теперь Spotlight ВЫКЛ нами, TM исключён) НЕ должен переписать исходное состояние.
  STUB_SPOTLIGHT=disabled STUB_TM_EXCLUDED=1 run_vw start "$MOUNT"
  run cat "$VW_STATE_DIR"/*
  [[ "$output" == *"spotlight_was=enabled"* ]]
  [[ "$output" == *"tm_added=1"* ]]
}

# --- stop: валидация / идемпотентность ---

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
  # Глобальный strip флага не должен съедать operand после `--`.
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
  # Остаточный каталог — не том: индексировать нечего, mdutil звать не по чему.
  # Со старой проверкой «каталог есть» stop дёргал mdutil на пустом каталоге, ловил
  # отказ и навсегда оставлял сессию, блокируя следующий start.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"                                # том ушёл из таблицы, каталог остался
  STUB_MDUTIL_FAIL=1 run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  # Сессия остаётся именно как долг: индексацию выключали мы, вернуть её можно только на
  # смонтированном томе, а настройка живёт на самом томе и переживает перемонтирование.
  grep -q '^pending_restore=1$' "$VW_STATE_DIR"/*
}

@test "stop does not claim it re-enabled indexing on a volume that is not mounted" {
  # Настройка Spotlight осталась на самом томе и переживёт перемонтирование — отчёт,
  # рапортующий «индексация снова включена», прямо врёт пользователю о его состоянии.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"indexing re-enabled"* ]]
  [[ "$output" == *"NOT re-enabled"* ]]
  [[ "$output" == *"vaultwatch stop"* ]]   # сказано, как всё-таки вернуть индексацию
}

@test "stop keeps the session when the mount table cannot be read" {
  # «Не знаем, смонтирован ли» → пробуем восстановить и честно падаем, а не молча чистим.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  STUB_MOUNT_FAIL=1 STUB_MDUTIL_FAIL=1 run_vw stop "$MOUNT"
  [ "$status" -ne 0 ]
  [ -n "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]
}

@test "stop warns, keeps state AND exits non-zero when Spotlight restore fails" {
  # Ненулевой код здесь несёт смысл: post-close хук securetrash и launchd-таймер
  # узнают, что исключения НЕ восстановлены, а не считают stop успешным.
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
  : > "$VW_STUB_LOG"   # сбросить лог после start — проверяем только вызовы status
  run_vw status
  [ "$status" -eq 0 ]
  ! grep -q "mdutil -i off" "$VW_STUB_LOG"
  ! grep -q "removeexclusion" "$VW_STUB_LOG"
}

@test "the next start settles an indexing debt left by a close that happened after unmount" {
  # Штатный путь: securetrash закрывает сейф (detach) и ТОЛЬКО ПОТОМ зовёт post-close хук,
  # поэтому stop почти всегда видит том уже ушедшим и вернуть индексацию не может.
  # Настройка живёт на самом томе и переживает перемонтирование — значит долг обязан
  # пережить закрытие сессии и погаситься там, где том снова доступен: на следующем start.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"                                # том ушёл — как после vault close
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  grep -q '^pending_restore=1$' "$VW_STATE_DIR"/*  # долг записан

  # Сейф открыли снова: том в таблице, mdutil снова достижим.
  printf '/dev/disk9s1 on %s (apfs, local, nodev, nosuid, journaled, nobrowse)\n' "$MOUNT" >"$STUB_MOUNTS"
  : >"$VW_STUB_LOG"
  run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  grep -qF -- "mdutil -i on $MOUNT" "$VW_STUB_LOG"  # долг погашен именно здесь
  ! grep -q '^pending_restore=1$' "$VW_STATE_DIR"/* # и снят с учёта
}

@test "a session with nothing owed is still cleared when the volume is gone" {
  # Если индексация была выключена ДО нас, восстанавливать нечего — долга нет,
  # и сессия обязана закрыться, иначе призрак блокировал бы слежение.
  STUB_SPOTLIGHT=disabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"
  run_vw stop "$MOUNT"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$VW_STATE_DIR" 2>/dev/null)" ]
}

@test "a debt is not lost when the restore itself fails at the next start" {
  # Погасить долг может не получиться (mdutil отказал). Тогда истинное до-сессионное
  # состояние — «индексация была ВКЛЮЧЕНА» — обязано переехать в новую сессию: иначе её stop
  # «восстановит» состояние «было выключено», и исключение останется на томе навсегда, молча.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"
  run_vw stop "$MOUNT"
  grep -q '^pending_restore=1$' "$VW_STATE_DIR"/*

  printf '/dev/disk9s1 on %s (apfs, local, nodev, nosuid, journaled, nobrowse)\n' "$MOUNT" >"$STUB_MOUNTS"
  # mdutil -i on проваливается, а состояние тома читается как «выключено» — самый коварный
  # случай: наивный start запомнил бы «до нас было выключено».
  STUB_MDUTIL_FAIL=1 STUB_SPOTLIGHT=disabled run_vw start "$MOUNT"
  [ "$status" -eq 0 ]
  grep -q '^spotlight_was=enabled$' "$VW_STATE_DIR"/*
}

@test "status names the mount of a session that still owes a restore" {
  # Долг без имени тома — это долг, который пользователь не найдёт.
  STUB_SPOTLIGHT=enabled bash "$SCRIPT" start "$MOUNT" >/dev/null
  : >"$STUB_MOUNTS"
  run_vw stop "$MOUNT"
  run_vw status
  [ "$status" -eq 0 ]
  [[ "$output" == *"$MOUNT"* ]]
}
