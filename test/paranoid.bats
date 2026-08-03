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
case "\${1:-}" in version|--version|-v) echo "$name \${STUB_VER:-0.0.1}"; exit 0 ;; esac
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

@test "notepad submenu 1 (unified note) dispatches 'ghostdraft new --clipboard'" {
  # Заметка схлопнута: единый пункт пишет/правит/копирует (копия с авто-очисткой ~20с).
  run_paranoid $'4\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "ghostdraft new --clipboard" "$LOG"
}

@test "notepad submenu 1 warns the clipboard auto-wipes" {
  run_paranoid $'4\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"clipboard"* ]]
  [[ "$output" == *"20s"* ]]
}

@test "notepad submenu 2 dispatches 'ghostdraft pipe'" {
  run_paranoid $'4\n2\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "ghostdraft pipe" "$LOG"
}

@test "notepad submenu has no third item (collapsed to note + show-clipboard)" {
  # Пункт 3 (старый new+clipboard) убран — '3' теперь невалиден, ничего не диспатчит.
  run_paranoid $'4\n3\n\n0\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "^ghostdraft" "$LOG"
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

# --- opt-in проверка обновлений (PARANOID_UPDATE_CHECK) ---

@test "update check stays silent when PARANOID_UPDATE_CHECK is unset (privacy default)" {
  printf 'ghostdraft=v9.9.9\n' >"$TMP/feed"   # свежак есть, но проверка выключена
  run_paranoid $'0\n' PARANOID_UPDATE_FEED="$TMP/feed" STUB_VER=0.1.0
  [ "$status" -eq 0 ]
  [[ "$output" != *"update available"* ]]
  [[ "$output" != *"→"* ]]
}

@test "update check shows a newer release when enabled and one is available" {
  printf 'ghostdraft=v0.1.9\n' >"$TMP/feed"
  run_paranoid $'0\n' PARANOID_UPDATE_CHECK=1 PARANOID_UPDATE_FEED="$TMP/feed" STUB_VER=0.1.7
  [ "$status" -eq 0 ]
  [[ "$output" == *"update available"* ]]
  [[ "$output" == *"ghostdraft 0.1.7→0.1.9"* ]]
}

@test "update check is silent when the installed version is already latest" {
  printf 'ghostdraft=v0.1.9\n' >"$TMP/feed"
  run_paranoid $'0\n' PARANOID_UPDATE_CHECK=1 PARANOID_UPDATE_FEED="$TMP/feed" STUB_VER=0.1.9
  [ "$status" -eq 0 ]
  [[ "$output" != *"update available"* ]]
}

@test "update check does not flag when installed is newer than the feed (no false positive)" {
  printf 'ghostdraft=v0.1.9\n' >"$TMP/feed"
  run_paranoid $'0\n' PARANOID_UPDATE_CHECK=1 PARANOID_UPDATE_FEED="$TMP/feed" STUB_VER=0.2.0
  [ "$status" -eq 0 ]
  [[ "$output" != *"update available"* ]]
}

# --- пункт меню Update: перезапуск установщика из клона ---
# Своей логики скачивания у лаунчера нет намеренно: обновление = install.sh из клона.
# Тесты идут через run_paranoid (env -i): иначе XDG_DATA_HOME/PARANOID_SRC из окружения
# разработчика протекли бы внутрь, лаунчер взял бы НАСТОЯЩИЙ клон и тест запустил бы
# боевой установщик, оставаясь при этом «зелёным».

# Каталог, похожий на наш клон: install.sh + paranoid рядом.
_make_fake_clone() {
  local dir="$1" marker="$2"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\necho "%s" >> "%s"\nexit %s\n' "$marker" "$LOG" "${3:-0}" > "$dir/install.sh"
  chmod +x "$dir/install.sh"
  : > "$dir/paranoid"
}

@test "menu shows the Update item" {
  run_paranoid $'0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"6)"* ]]
  [[ "$output" == *"Update"* ]]
}

@test "update runs install.sh from the recorded source dir and shows which one" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  grep -q "INSTALLER RAN" "$LOG"
  # пользователь обязан ВИДЕТЬ, код какого каталога сейчас выполнится
  [[ "$output" == *"$TMP/clone"* ]]
}

@test "update does nothing without an explicit yes" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nn\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  ! grep -q "INSTALLER RAN" "$LOG"
  [[ "$output" == *"Cancelled"* ]]
}

@test "update says plainly when no installer can be found" {
  cp "$SCRIPT" "$TMP/paranoid-standalone"
  run env -i PATH="$STUBS:$_ESSENTIAL_PATH" HOME="$TMP" ST_LOCALE=en \
    bash -c "printf '%s' \"\$0\" | bash '$TMP/paranoid-standalone'" $'6\n\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cannot find the installer"* ]]
}

@test "PARANOID_SRC overrides the recorded source dir" {
  _make_fake_clone "$TMP/other" "OTHER RAN"
  _make_fake_clone "$TMP/clone" "RECORDED RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP" PARANOID_SRC="$TMP/other"
  [ "$status" -eq 0 ]
  grep -q "OTHER RAN" "$LOG"
  ! grep -q "RECORDED RAN" "$LOG"
}

@test "a CRLF state file still resolves to the recorded dir" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\r\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  grep -q "INSTALLER RAN" "$LOG"
}

@test "a directory that is not our clone is not executed" {
  # только install.sh, без paranoid рядом — чужой каталог запускать нельзя
  mkdir -p "$TMP/notclone"
  printf '#!/usr/bin/env bash\necho "STRANGER RAN" >> "%s"\n' "$LOG" > "$TMP/notclone/install.sh"
  chmod +x "$TMP/notclone/install.sh"
  cp "$SCRIPT" "$TMP/paranoid-standalone"
  run env -i PATH="$STUBS:$_ESSENTIAL_PATH" HOME="$TMP" ST_LOCALE=en PARANOID_SRC="$TMP/notclone" \
    bash -c "printf '%s' \"\$0\" | bash '$TMP/paranoid-standalone'" $'6\n\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "STRANGER RAN" "$LOG"
  [[ "$output" == *"Cannot find the installer"* ]]
}

@test "update pulls first when the source really is a git clone" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  # стаб git пишет в лог, чтобы увидеть, что pull вообще звали
  printf '#!/usr/bin/env bash\necho "git $*" >> "%s"\nexit 0\n' "$LOG" > "$STUBS/git"
  chmod +x "$STUBS/git"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  grep -q "pull --ff-only" "$LOG"
  grep -q "INSTALLER RAN" "$LOG"
}

@test "a failed pull does not stop the reinstall and is reported" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  printf '#!/usr/bin/env bash\ncase "$*" in *rev-parse*) exit 0;; *pull*) exit 1;; esac\nexit 0\n' > "$STUBS/git"
  chmod +x "$STUBS/git"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"did not succeed"* ]]
  grep -q "INSTALLER RAN" "$LOG"
}

@test "update clears the cached update-available banner after a successful install" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools" "$TMP/.cache/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  echo "securetrash 0.1.0->9.9.9" > "$TMP/.cache/paranoid-tools/update-check"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/.cache/paranoid-tools/update-check" ]
}

@test "a failing installer is reported and the stale banner is kept" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN" 1
  mkdir -p "$TMP/.local/share/paranoid-tools" "$TMP/.cache/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  echo "securetrash 0.1.0->9.9.9" > "$TMP/.cache/paranoid-tools/update-check"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exited with an error"* ]]
  # неудачная установка не должна прятать баннер «доступно обновление»
  [ -f "$TMP/.cache/paranoid-tools/update-check" ]
}

@test "a symlinked install.sh is not executed" {
  # -f идёт по ссылке: подменённая цель прошла бы проверку, а пользователь видел бы
  # прежний доверенный путь. Ссылки не принимаем.
  _make_fake_clone "$TMP/evil" "EVIL RAN"
  mkdir -p "$TMP/clone"
  ln -s "$TMP/evil/install.sh" "$TMP/clone/install.sh"
  : > "$TMP/clone/paranoid"
  cp "$SCRIPT" "$TMP/paranoid-standalone"
  run env -i PATH="$STUBS:$_ESSENTIAL_PATH" HOME="$TMP" ST_LOCALE=en PARANOID_SRC="$TMP/clone" \
    bash -c "printf '%s' \"\$0\" | bash '$TMP/paranoid-standalone'" $'6\n\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "EVIL RAN" "$LOG"
  [[ "$output" == *"Cannot find the installer"* ]]
}

@test "a trailing space in the state file is not silently trimmed into another dir" {
  # /tmp/x и '/tmp/x ' — разные каталоги; общий trim подменил бы один другим.
  _make_fake_clone "$TMP/other" "OTHER RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s \n' "$TMP/other" > "$TMP/.local/share/paranoid-tools/source"
  cp "$SCRIPT" "$TMP/paranoid-standalone"
  run env -i PATH="$STUBS:$_ESSENTIAL_PATH" HOME="$TMP" ST_LOCALE=en \
    bash -c "printf '%s' \"\$0\" | bash '$TMP/paranoid-standalone'" $'6\n\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "OTHER RAN" "$LOG"
}

@test "a failed pull is still called out after a successful install" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  printf '#!/usr/bin/env bash\ncase "$*" in *rev-parse*) exit 0;; *pull*) exit 1;; esac\nexit 0\n' > "$STUBS/git"
  chmod +x "$STUBS/git"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  grep -q "INSTALLER RAN" "$LOG"
  # успех установщика не должен выдаваться за «всё свежее»
  [[ "$output" == *"clone itself was not updated"* ]]
}
