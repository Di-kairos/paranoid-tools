#!/usr/bin/env bash
# smoke-test.sh — безопасная самопроверка всех 5 инструментов Paranoid Tools на macOS.
#
# Что делает: прогоняет happy-path каждого тула в ПЕСОЧНИЦЕ (временный HOME, temp-файлы,
# никаких твоих данных не трогает) и печатает ✓/✗ по каждой проверке. Ничего не публикует,
# работает локально и в приватном окружении. Запуск:
#
#   bash smoke-test.sh
#
# Источник тулов: сперва из PATH (если ставил через install.sh), иначе из этого репозитория.
# Деструктивных операций над твоими файлами НЕТ: shred/vault работают только во временной
# песочнице, vault монтируется в /Volumes/SecretVault и сразу уничтожается (если точка занята
# твоим реальным vault — этот блок пропускается, чтобы ничего не задеть).
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PASS=0; FAIL=0; SKIP=0

# Запуск тула: из PATH, если установлен, иначе из репозитория.
tool() { local t="$1"; shift; if command -v "$t" >/dev/null 2>&1; then "$t" "$@"; else bash "${ROOT}/${t}/${t}" "$@"; fi; }

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33m–\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }
head() { printf '\n\033[1m%s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Darwin" ]]; then echo "Paranoid Tools рассчитаны на macOS." >&2; exit 1; fi

# --- 1. Версии (все 5 запускаются) ---
head "1. Версии"
for t in securetrash vaultwatch panic ghostdraft seedsplit; do
  if out="$(tool "$t" version 2>/dev/null)" && [[ "$out" == *"$t"* ]]; then ok "$out"; else bad "$t version не запустился"; fi
done

# --- 2. seedsplit: split → combine → verify + отказ при подмене ---
head "2. seedsplit (Shamir split/combine/verify)"
secret="smoke-secret-$$"
shares="$(printf '%s' "$secret" | tool seedsplit split -n 3 -t 2 2>/dev/null)"
if [[ "$(printf '%s\n' "$shares" | grep -c '^SSS2-')" -eq 3 ]]; then ok "split → 3 доли"; else bad "split не дал 3 доли"; fi
rec="$(printf '%s\n' "$shares" | sed -n '1p;3p' | tool seedsplit combine 2>/dev/null)"
if [[ "$rec" == "$secret" ]]; then ok "combine(1,3) восстановил секрет"; else bad "combine не восстановил секрет"; fi
if printf '%s\n' "$shares" | sed -n '2p;3p' | tool seedsplit verify >/dev/null 2>&1; then ok "verify подтвердил восстановимость"; else bad "verify не прошёл"; fi
# подмена одной доли → combine должен отказать (а не молча вернуть мусор)
badshare="$(printf '%s\n' "$shares" | sed -n '1p' | sed 's/-\([0-9a-f]\)/-X/2')"
if printf '%s\n%s\n' "$badshare" "$(printf '%s\n' "$shares" | sed -n '2p')" | tool seedsplit combine >/dev/null 2>&1; then
  bad "подмена доли НЕ была отвергнута"; else ok "подмена доли отвергнута (fail-closed)"; fi

# --- 3. ghostdraft: pipe (без записи на диск) + new в temp-каталоге ---
head "3. ghostdraft (pipe + ephemeral draft)"
out="$(printf 'a\nb\n' | tool ghostdraft pipe 2>/dev/null)"
if [[ "$out" == $'a\nb' ]]; then ok "pipe пробросил stdin без записи на диск"; else bad "pipe исказил ввод"; fi
gtmp="$(mktemp -d)"
if GHOSTDRAFT_DIR="$gtmp" EDITOR=true tool ghostdraft new >/dev/null 2>&1; then
  if [[ -z "$(ls -A "$gtmp" 2>/dev/null)" ]]; then ok "new создал и стёр черновик (каталог пуст)"; else bad "new оставил файлы в каталоге"; fi
else skip "new (нужен интерактивный \$EDITOR — см. docs/TESTING.md)"; fi
rm -rf "$gtmp"

# --- 4. securetrash: shred (песочница) ---
head "4. securetrash shred (песочница)"
sb="$(mktemp -d)"; printf 'throwaway' > "$sb/junk.txt"
HOME="$sb" ST_ASSUME_YES=1 tool securetrash shred "$sb/junk.txt" >/dev/null 2>&1
if [[ -e "$sb/junk.txt" ]]; then bad "shred не удалил файл"; else ok "shred удалил temp-файл"; fi
rm -rf "$sb"

# --- 5. securetrash: полный vault-цикл (песочница; пропуск, если /Volumes/SecretVault занят) ---
head "5. securetrash vault (create → open → close → destroy)"
if mount | grep -q "/Volumes/SecretVault"; then
  skip "пропуск: /Volumes/SecretVault уже смонтирован (твой реальный vault — не трогаю)"
else
  vh="$(mktemp -d)"; v(){ HOME="$vh" ST_ASSUME_YES=1 ST_VAULT_PASS="smoke-pass" tool securetrash "$@" >/dev/null 2>&1; }
  if v vault create 10m; then ok "vault create (10m sparsebundle в песочнице)"; else bad "vault create"; fi
  if v vault open && mount | grep -q "/Volumes/SecretVault"; then ok "vault open (смонтирован)"; else bad "vault open"; fi
  if printf 'secret' > /Volumes/SecretVault/s.txt 2>/dev/null; then ok "запись секрета в открытый vault"; else bad "запись в vault"; fi
  if v vault close && ! mount | grep -q "/Volumes/SecretVault"; then ok "vault close (размонтирован)"; else bad "vault close"; fi
  if v vault destroy && [[ ! -e "$vh/SecureVault.sparsebundle" ]]; then ok "vault destroy (crypto-shred контейнера)"; else bad "vault destroy"; fi
  rm -rf "$vh"
fi

# --- vaultwatch / panic: реальные функции — интеграционные/disruptive, тест вручную ---
head "vaultwatch / panic"
skip "vaultwatch (сторож открытого vault) и panic (скрыть тома) — disruptive, тест вручную по docs/TESTING.md"

# --- итог ---
printf '\n\033[1mИтог:\033[0m \033[32m%d ✓\033[0m  \033[31m%d ✗\033[0m  \033[33m%d –\033[0m\n' "$PASS" "$FAIL" "$SKIP"
if [[ "$FAIL" -eq 0 ]]; then
  echo "Все автоматические проверки прошли."; exit 0
else
  echo "Есть провалы — см. ✗ выше."; exit 1
fi
