# Тесты paranoid — интерактивный лаунчер экосистемы (чистый Bash).
# Техника: пять CLI экосистемы + fdesetup подменяются стабами в $STUBS на PATH;
# каждый стаб дописывает "<имя> $@" в $LOG. Так тест проверяет, какой тул и с
# какими аргументами был вызван. Отсутствующий тул = просто не создаём его стаб.
# Интерактивный цикл гоняется подачей пунктов меню в stdin (каждое действие
# делает паузу _pause — лишняя пустая строка — перед возвратом в меню, финальный
# '0' выходит).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../paranoid"
  TMP="$(mktemp -d)"
  STUBS="$TMP/bin"
  LOG="$TMP/calls.log"
  mkdir -p "$STUBS"
  : >"$LOG"

  # Базовые утилиты (coreutils + сам bash), на которые опирается скрипт.
  # PATH = только стабы + системные пути с этими утилитами, чтобы НАСТОЯЩИЕ
  # securetrash/panic/… (если установлены) не перехватили вызов.
  _ESSENTIAL_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  # Пять CLI экосистемы + fdesetup. По умолчанию ставим все пять; отдельные
  # тесты удаляют нужный стаб, чтобы смоделировать «не установлен».
  for t in securetrash vaultwatch panic seedsplit ghostdraft fdesetup; do
    _make_stub "$t"
  done

  unset ST_LANG ST_LOCALE
  export ST_LOCALE=en   # детерминированный chrome по умолчанию (en)
}

teardown() { rm -rf "$TMP"; }

# Создать исполняемый стаб, дописывающий "<имя> $@" в $LOG.
# Спец-случаи: vaultwatch status → idle (нет "session:"), fdesetup status → On.
_make_stub() {
  local name="$1"
  cat >"$STUBS/$name" <<EOF
#!/usr/bin/env bash
printf '$name %s\n' "\$*" >>"$LOG"
case "$name:\${1:-}" in
  fdesetup:status) echo "FileVault is On." ;;
  vaultwatch:status) : ;;  # пусто → _status_vaultwatch = idle
esac
exit 0
EOF
  chmod +x "$STUBS/$name"
}

# Запустить лаунчер с подменённым PATH и переданным stdin.
# Использование: run_paranoid "<stdin>" [extra env assignments...]
run_paranoid() {
  local input="$1"; shift
  run env -i PATH="$STUBS:$_ESSENTIAL_PATH" HOME="$HOME" \
    ST_LOCALE="${ST_LOCALE:-en}" "$@" \
    bash -c "printf '%s' \"\$0\" | bash '$SCRIPT'" "$input"
}

# --- субкоманды (не запускают цикл) ---

@test "version prints 'paranoid 0.1.0'" {
  run env PATH="$STUBS:$_ESSENTIAL_PATH" bash "$SCRIPT" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"paranoid 0.1.0"* ]]
}

@test "help prints usage and exits zero" {
  run env PATH="$STUBS:$_ESSENTIAL_PATH" bash "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"interactive"* ]]
}

@test "unknown arg exits 1 with usage on stderr" {
  # Захватываем ТОЛЬКО stderr (usage + сообщение об ошибке идут в stderr):
  # stdout глушим, stderr → файл.
  run env PATH="$STUBS:$_ESSENTIAL_PATH" bash -c "bash '$SCRIPT' bogus 2>'$TMP/err' >/dev/null"
  [ "$status" -eq 1 ]
  grep -q "Usage:" "$TMP/err"
  grep -q "Unknown command" "$TMP/err"
}

@test "sourcing the script does not launch the loop" {
  run env PATH="$STUBS:$_ESSENTIAL_PATH" bash -c "source '$SCRIPT'; echo SOURCED_OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED_OK"* ]]
  [[ "$output" != *"Choose"* ]]
}

# --- статус (пункт 1) ---

@test "status runs 'securetrash check' and 'vaultwatch status'" {
  run_paranoid $'1\n\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "securetrash check" "$LOG"
  grep -qx "vaultwatch status" "$LOG"
}

# --- паника (пункт 2) ---

@test "panic confirm yes + hard yes dispatches 'panic now --hard'" {
  run_paranoid $'2\nyes\nyes\n\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "panic now --hard" "$LOG"
}

@test "panic confirm yes + hard no dispatches 'panic now' (no --hard)" {
  run_paranoid $'2\nyes\nno\n\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "panic now" "$LOG"
  ! grep -q -- "--hard" "$LOG"
}

@test "panic confirm no does NOT run panic" {
  run_paranoid $'2\nno\n\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "^panic " "$LOG"
}

@test "panic item greys out when panic is not installed" {
  rm -f "$STUBS/panic"
  run_paranoid $'0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"PANIC NOW"*"(not installed)"* ]]
}

@test "panic absent: choosing it shows hint, runs nothing, no confirm" {
  rm -f "$STUBS/panic"
  run_paranoid $'2\n\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "^panic " "$LOG"
  [[ "$output" == *"github.com/Di-kairos/panic"* ]]
}

# --- сейф (пункт 3) ---

@test "vault not set up (no container) -> dispatches 'securetrash vault create'" {
  run_paranoid $'3\n\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault create" "$LOG"
  ! grep -q "vault open" "$LOG"
  ! grep -q "vault close" "$LOG"
}

@test "vault closed (container exists, unmounted) -> dispatches 'securetrash vault open'" {
  touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault open" "$LOG"
  ! grep -q "vault close" "$LOG"
  ! grep -q "vault create" "$LOG"
}

@test "vault open -> dispatches 'securetrash vault close'" {
  mkdir -p "$TMP/vault"
  run_paranoid $'3\n\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault close" "$LOG"
  ! grep -q "vault open" "$LOG"
  ! grep -q "vault create" "$LOG"
}

# --- seedsplit (пункты 4/5) ---

@test "menu 4 dispatches 'seedsplit split'" {
  run_paranoid $'4\n\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "seedsplit split" "$LOG"
}

@test "menu 5 dispatches 'seedsplit combine'" {
  run_paranoid $'5\n\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "seedsplit combine" "$LOG"
}

# --- ghostdraft submenu (пункт 6) ---

@test "ghostdraft submenu 1 dispatches 'ghostdraft new'" {
  run_paranoid $'6\n1\n\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "ghostdraft new" "$LOG"
}

@test "ghostdraft submenu 2 dispatches 'ghostdraft pipe'" {
  run_paranoid $'6\n2\n\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "ghostdraft pipe" "$LOG"
}

# --- vaultwatch start (пункт 7) ---

@test "watch with TTL dispatches 'vaultwatch start --ttl <X> <vault>'" {
  run_paranoid $'7\n30m\n\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "vaultwatch start --ttl 30m $TMP/vault" "$LOG"
}

@test "watch without TTL dispatches 'vaultwatch start <vault>'" {
  run_paranoid $'7\n\n\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "vaultwatch start $TMP/vault" "$LOG"
}

# --- отсутствующий тул ---

@test "missing tool shows '(not installed)' in menu" {
  rm -f "$STUBS/seedsplit"
  run_paranoid $'0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"(not installed)"* ]]
}

@test "missing tool action invokes nothing (log stays empty for it)" {
  rm -f "$STUBS/seedsplit"
  run_paranoid $'4\n\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "^seedsplit" "$LOG"
  # И показан хинт на установку (репо).
  [[ "$output" == *"github.com/Di-kairos/seedsplit"* ]]
}

# --- i18n chrome ---

@test "en chrome shows 'Status — full read-only check'" {
  ST_LOCALE=en run_paranoid $'0\n' ST_LOCALE=en
  [ "$status" -eq 0 ]
  [[ "$output" == *"Status — full read-only check"* ]]
}

@test "ru chrome shows Russian menu string" {
  run_paranoid $'0\n' ST_LANG=ru ST_LOCALE=ru
  [ "$status" -eq 0 ]
  [[ "$output" == *"Статус — полная проверка"* ]]
}

# --- выход ---

@test "quit via 0 exits cleanly" {
  run_paranoid $'0\n'
  [ "$status" -eq 0 ]
}

@test "quit via q exits cleanly" {
  run_paranoid $'q\n'
  [ "$status" -eq 0 ]
}

@test "quit via Q exits cleanly" {
  run_paranoid $'Q\n'
  [ "$status" -eq 0 ]
}
