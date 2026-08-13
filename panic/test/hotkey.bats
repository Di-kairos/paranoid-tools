# Тесты `panic hotkey` — глобальный хоткей через skhd.
# skhd и uname подменены стабами (uname → Darwin, чтобы require_macos прошёл на Linux-CI);
# проверяем только генерацию managed-конфига, не реальный демон.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../panic"
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  TMP="$(mktemp -d)"
  export SKHD_CONFIG="$TMP/skhdrc"
  # Каталог только с uname (без skhd) — для детерминированного теста «skhd отсутствует».
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
  # путь к panic обязан быть в кавычках — иначе skhd порвёт команду по пробелу
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
  # Раньше managed-блок вырезался через `mv` временного файла — skhdrc получал права
  # mktemp (600) и владельца текущего пользователя вместо своих.
  printf 'alt - a : echo hi\n' > "$SKHD_CONFIG"
  chmod 0644 "$SKHD_CONFIG"
  # Права: GNU (Linux-CI) `stat -c` сначала, BSD (macOS) `-f` фолбэком — тот же канон,
  # что в ghostdraft/test/ghostdraft.bats. Обратный порядок читался как рабочий, но на
  # Linux `stat -f` — это --file-system: он не падает, а печатает отчёт по ФС со строкой
  # `Free:`, и она между вызовами меняется. Сравнивались не права, а свободные блоки.
  before="$(stat -c '%a' "$SKHD_CONFIG" 2>/dev/null || stat -f '%Lp' "$SKHD_CONFIG")"
  run_hk install
  run_hk uninstall
  [ "$status" -eq 0 ]
  after="$(stat -c '%a' "$SKHD_CONFIG" 2>/dev/null || stat -f '%Lp' "$SKHD_CONFIG")"
  [ "$before" = "$after" ]
}
