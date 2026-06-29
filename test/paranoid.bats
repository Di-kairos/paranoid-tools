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

@test "panic dispatches 'panic now --hard' instantly (no confirm)" {
  run_paranoid $'2\n\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "panic now --hard" "$LOG"
}

@test "panic asks for NO confirmation (speed is the point)" {
  run_paranoid $'2\n\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Run panic now"* ]]
  [[ "$output" != *"type yes"* ]]
  [[ "$output" != *"--hard)?"* ]]
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

# --- сейф: подменю (пункт 3 → ...) ---

@test "vault submenu: no container -> dispatches 'securetrash vault create'" {
  # ввод после '1': пустой размер (дефолт) + пустая пауза
  run_paranoid $'3\n1\n\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault create" "$LOG"
  ! grep -q "vault open" "$LOG"
  ! grep -q "vault close" "$LOG"
}

@test "vault create passes a chosen size cap to securetrash" {
  run_paranoid $'3\n1\n5g\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault create 5g" "$LOG"
}

@test "vault create with an invalid size cancels (no create dispatched)" {
  run_paranoid $'3\n1\nbig\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  ! grep -q "vault create" "$LOG"
  [[ "$output" == *"Invalid size"* ]]
}

@test "vault submenu: closed -> dispatches 'securetrash vault open'" {
  touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n1\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault open" "$LOG"
  ! grep -q "vault close" "$LOG"
  ! grep -q "vault create" "$LOG"
}

@test "vault submenu: open -> dispatches 'securetrash vault close'" {
  mkdir -p "$TMP/vault"
  run_paranoid $'3\n1\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault close" "$LOG"
  ! grep -q "vault open" "$LOG"
  ! grep -q "vault create" "$LOG"
}

# --- сейф: empty = vault reset (подменю 3 → 2) ---

@test "vault submenu 2 dispatches 'securetrash vault reset' when a vault exists" {
  touch "$TMP/container.sparsebundle"
  # после '2': пустой размер (дефолт) + пустая пауза
  run_paranoid $'3\n2\n\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault reset" "$LOG"
}

@test "vault empty warns it crypto-shreds and recreates" {
  touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n2\n\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  [[ "$output" == *"crypto-shred"* ]]
}

@test "vault empty is a no-op when there is no vault (no dead-end)" {
  run_paranoid $'3\n2\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  ! grep -q "vault reset" "$LOG"
}

# --- сейф: destroy (подменю 3 → 3) ---

@test "vault submenu 3 dispatches 'securetrash vault destroy' when a vault exists" {
  touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n3\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault destroy" "$LOG"
}

@test "vault destroy warns before destroy (irreversible)" {
  touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n3\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  [[ "$output" == *"permanently"* ]]
}

@test "vault destroy is a no-op when there is no vault (no dead-end)" {
  run_paranoid $'3\n3\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  ! grep -q "vault destroy" "$LOG"
}

# --- секреты: подменю (пункт 5 → ...) ---

@test "secrets submenu 1 dispatches 'seedsplit split'" {
  run_paranoid $'5\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "seedsplit split" "$LOG"
}

@test "secrets submenu 2 dispatches 'seedsplit combine'" {
  run_paranoid $'5\n2\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "seedsplit combine" "$LOG"
}

# --- блокнот: подменю (пункт 4 → ...) ---

@test "notepad submenu 1 dispatches 'ghostdraft new'" {
  run_paranoid $'4\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "ghostdraft new" "$LOG"
}

@test "notepad submenu 2 dispatches 'ghostdraft pipe'" {
  run_paranoid $'4\n2\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "ghostdraft pipe" "$LOG"
}

@test "notepad submenu 3 dispatches 'ghostdraft new --clipboard'" {
  run_paranoid $'4\n3\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "ghostdraft new --clipboard" "$LOG"
}

@test "notepad submenu 3 warns the clipboard auto-wipes" {
  run_paranoid $'4\n3\n\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"clipboard"* ]]
  [[ "$output" == *"20s"* ]]
}

# --- сейф: vaultwatch start (подменю 3 → 4) ---

@test "watch with TTL dispatches 'vaultwatch start --ttl <X> <vault>'" {
  run_paranoid $'3\n4\n30m\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "vaultwatch start --ttl 30m $TMP/vault" "$LOG"
}

@test "watch without TTL dispatches 'vaultwatch start <vault>'" {
  run_paranoid $'3\n4\n\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "vaultwatch start $TMP/vault" "$LOG"
}

# Регресс: активная сессия должна показываться как "active", а не "idle".
# Баг: `vaultwatch status | grep -q` под `set -o pipefail` — grep -q закрывает пайп
# на первой строке, vaultwatch ловит SIGPIPE (141), pipefail делает конвейер
# ненулевым → ложный "idle". Стаб с session: на первой строке + хвост больше буфера
# пайпа (~64KB) делает SIGPIPE детерминированным, иначе мелкий вывод влез бы в буфер.
@test "active vaultwatch session shows 'active' under pipefail (no SIGPIPE false-idle)" {
  cat >"$STUBS/vaultwatch" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "status" ]; then
  echo "session: /tmp/vault (running 5m)"
  for i in $(seq 1 5000); do echo "  detail line $i padding padding padding padding"; done
fi
exit 0
STUB
  chmod +x "$STUBS/vaultwatch"
  run_paranoid $'0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"active"* ]]
  [[ "$output" != *"idle"* ]]
}

# --- отсутствующий тул ---

@test "missing tool shows '(not installed)' inside its submenu" {
  rm -f "$STUBS/seedsplit"
  run_paranoid $'5\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"(not installed)"* ]]
}

@test "missing tool action invokes nothing (log stays empty for it)" {
  rm -f "$STUBS/seedsplit"
  run_paranoid $'5\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "^seedsplit" "$LOG"
  # И показан хинт на установку (репо).
  [[ "$output" == *"github.com/Di-kairos/seedsplit"* ]]
}

# --- top-level: три группы-подменю ---

@test "top level shows the three submenu groups" {
  run_paranoid $'0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Vault ▸"* ]]
  [[ "$output" == *"Notepad ▸"* ]]
  [[ "$output" == *"Secrets ▸"* ]]
}

@test "submenu 0 returns to the top menu (back navigation)" {
  # Войти в Сейф, вернуться (0), затем выйти (0). Дашборд показан дважды → видим Status.
  run_paranoid $'3\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Vault — encrypted container"* ]]
  [[ "$output" == *"Status — full read-only check"* ]]
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

# --- UX: подсказки и тупики ---

@test "split prints a paste prompt before reading stdin" {
  run_paranoid $'5\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Paste the secret"* ]]
}

@test "combine prints a one-per-line paste prompt" {
  run_paranoid $'5\n2\n\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"one per line"* ]]
}

@test "ghost new shows which editor opens and how to exit" {
  EDITOR=nano run_paranoid $'4\n1\n\n0\n0\n' EDITOR=nano
  [ "$status" -eq 0 ]
  [[ "$output" == *"nano"* ]]
  [[ "$output" == *"Ctrl-X"* ]]
}

@test "ghost new (vim) hint shows how to DISCARD, not just save" {
  # Live-тест: новичок застрял в vim, видел только сохранение (:wq), хотел выйти БЕЗ
  # сохранения. Подсказка обязана давать оба пути клавиатурой (F-клавиши в Warp не проходят).
  EDITOR=vim run_paranoid $'4\n1\n\n0\n0\n' EDITOR=vim
  [ "$status" -eq 0 ]
  [[ "$output" == *"vim"* ]]
  [[ "$output" == *"ZQ"* ]] || [[ "$output" == *":q!"* ]]   # выйти без сохранения
  [[ "$output" == *"ZZ"* ]] || [[ "$output" == *":wq"* ]]   # сохранить и выйти
  [[ "$output" == *"Esc"* ]]
}

@test "ghost pipe shows a hint (does not silently wait on stdin)" {
  run_paranoid $'4\n2\n\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"clipboard"* ]]
}

@test "invalid TTL is rejected and does not start vaultwatch" {
  run_paranoid $'3\n4\n30min\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Invalid format"* ]]
  ! grep -q "vaultwatch start" "$LOG"
}

@test "vault submenu 4 stops the watch when a session is active" {
  cat >"$STUBS/vaultwatch" <<EOF
#!/usr/bin/env bash
printf 'vaultwatch %s\n' "\$*" >>"$LOG"
[ "\${1:-}" = "status" ] && echo "session: active"
exit 0
EOF
  chmod +x "$STUBS/vaultwatch"
  run_paranoid $'3\n4\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "vaultwatch stop $TMP/vault" "$LOG"
}
