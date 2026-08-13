#!/usr/bin/env bash
# Установщик ВСЕЙ экосистемы Paranoid Tools — «одна команда, всё есть».
#
# Ставит 5 инструментов (securetrash, vaultwatch, panic, ghostdraft, seedsplit)
# + интерактивный лаунчер `paranoid` в ~/.local/bin. Два режима, выбираются
# автоматически по тому, есть ли рядом локальные исходники тулов:
#
#   1. ПУБЛИКА (по умолчанию, любой clone). Каждый тул тянется из его
#      ПОДПИСАННОГО релиза по схеме verify-then-run: проверяется подпись Ed25519
#      над SHA256SUMS, затем контрольная сумма самого install.sh тула, и только
#      потом он запускается (а он, в свою очередь, проверяет и бинарь). Так
#      «git clone + bash install.sh» честно даёт все 5 без ручной возни.
#      Исходники тулов лежат в этом же монорепо, но публичная установка ИХ НЕ
#      БЕРЁТ: цепочка подписи важнее экономии на скачивании.
#
#   2. MAINTAINER (только явный PT_DEV=1). Локальный скрипт `<tool>/<tool>`
#      копируется из рабочей копии, включая ещё не выпущенные правки. Релиз не
#      дёргается. Раньше режим включался сам по наличию подпапок тулов; в
#      монорепо подпапки есть у КАЖДОГО клона, и автовключение выключило бы
#      verify-then-run для всей публики — поэтому только явный opt-in.
#
# Использование:
#   bash install.sh                 # поставить/обновить все 5 (+ лаунчер)
#   bash install.sh --uninstall     # удалить все 5 (+ лаунчер) из bin-каталога
#   PT_DEST=/usr/local/bin bash install.sh   # другой каталог установки
#
# Переменные окружения:
#   PT_DEST            — каталог установки. По умолчанию ~/.local/bin (без sudo).
#   PT_<TOOL>_VERSION  — закрепить версию конкретного тула (публичный режим).
#                        Точные имена: PT_ST_VERSION (securetrash), PT_VW_VERSION
#                        (vaultwatch), PT_PANIC_VERSION, PT_GHOSTDRAFT_VERSION,
#                        PT_SEEDSPLIT_VERSION. Прочие (напр. PT_SECURETRASH_VERSION)
#                        игнорируются молча. По умолчанию latest.
set -euo pipefail

# --- language detection ---
# Паритет с пятью тулами: по умолчанию английский, русский — opt-in. Security-ошибки
# установщика (провал подписи, отсутствие верификатора) обязаны читаться тем, кто
# ставит: раньше они были только по-русски, то есть для EN-пользователя это был
# молчаливый отказ без причины.
# Приоритет: PT_LANG → ST_LANG (общий для экосистемы) → $LC_ALL/$LANG.
_detect_locale() {
  local want="${PT_LANG:-${ST_LANG:-}}"
  if [[ -n "$want" ]]; then
    case "$want" in ru*) echo "ru"; return ;; *) echo "en"; return ;; esac
  fi
  case "${LC_ALL:-${LANG:-}}" in ru*) echo "ru" ;; *) echo "en" ;; esac
}
LOCALE="$(_detect_locale)"

# Локализованные строки. Первый аргумент — ключ, остальные подставляются printf'ом.
t() {
  case "$LOCALE:$1" in
    en:only_macos)     echo "Paranoid Tools targets macOS." ;;
    ru:only_macos)     echo "Paranoid Tools рассчитаны на macOS." ;;
    en:uninstalling)   printf 'Removing Paranoid Tools from %s...\n' "$2" ;;
    ru:uninstalling)   printf 'Удаляю Paranoid Tools из %s...\n' "$2" ;;
    en:removed)        printf '  ✓ removed %s\n' "$2" ;;
    ru:removed)        printf '  ✓ удалён %s\n' "$2" ;;
    en:uninstall_done) echo "Done. (A Homebrew-installed securetrash, if any, was left alone — remove it with 'brew uninstall'.)" ;;
    ru:uninstall_done) echo "Готово. (Homebrew-версия securetrash, если была, не тронута — снимай через 'brew uninstall'.)" ;;
    en:dl_fail)        printf '  ✗ %s: could not download the release (%s).\n' "$2" "$3" ;;
    ru:dl_fail)        printf '  ✗ %s: не удалось скачать релиз (%s).\n' "$2" "$3" ;;
    en:sig_bad)        printf '  ✗ %s: the release signature did NOT verify — skipping (possible tampering).\n' "$2" ;;
    ru:sig_bad)        printf '  ✗ %s: подпись релиза НЕ прошла проверку — пропускаю (возможна подмена).\n' "$2" ;;
    en:sig_missing)    printf '  ✗ %s: no release signature available — skipping (override: ALLOW_UNSIGNED_LEGACY=1).\n' "$2" ;;
    ru:sig_missing)    printf '  ✗ %s: подпись релиза недоступна — пропускаю (обход: ALLOW_UNSIGNED_LEGACY=1).\n' "$2" ;;
    en:no_verifier)    printf '  ✗ %s: ssh-keygen is unavailable, so the signature cannot be checked; skipping (override: ALLOW_UNSIGNED_LEGACY=1).\n' "$2" ;;
    ru:no_verifier)    printf '  ✗ %s: ssh-keygen недоступен — подпись проверить нечем; пропускаю (обход: ALLOW_UNSIGNED_LEGACY=1).\n' "$2" ;;
    en:no_verifier_warn) printf '  ! ssh-keygen is unavailable — the signature of %s was NOT verified (ALLOW_UNSIGNED_LEGACY=1, checksum only).\n' "$2" ;;
    ru:no_verifier_warn) printf '  ! ssh-keygen недоступен — подпись %s НЕ проверена (ALLOW_UNSIGNED_LEGACY=1, только SHA256).\n' "$2" ;;
    en:sum_mismatch)   printf '  ✗ %s: checksum mismatch on install.sh — skipping.\n' "$2" ;;
    ru:sum_mismatch)   printf '  ✗ %s: контрольная сумма install.sh не совпала — пропускаю.\n' "$2" ;;
    en:tool_fail)      printf "  ✗ %s: the tool's own installer exited with an error:\n" "$2" ;;
    ru:tool_fail)      printf '  ✗ %s: установщик тула завершился с ошибкой:\n' "$2" ;;
    en:installing)     printf 'Installing Paranoid Tools into %s...\n' "$2" ;;
    ru:installing)     printf 'Ставлю Paranoid Tools в %s...\n' "$2" ;;
    en:from_worktree)  printf '  ✓ %s → %s (from the working copy)\n' "$2" "$3" ;;
    ru:from_worktree)  printf '  ✓ %s → %s (из рабочей копии)\n' "$2" "$3" ;;
    en:from_release)   printf '  ✓ %s → %s (from the signed release)\n' "$2" "$3" ;;
    ru:from_release)   printf '  ✓ %s → %s (из подписанного релиза)\n' "$2" "$3" ;;
    en:installed_n)    printf 'Tools installed: %s/%s (+ the paranoid launcher).\n' "$2" "$3" ;;
    ru:installed_n)    printf 'Установлено инструментов: %s/%s (+ лаунчер paranoid).\n' "$2" "$3" ;;
    en:partial_note)   echo "Some tools did not install — see the messages above (network / signature / directory)." ;;
    ru:partial_note)   echo "Часть тулов не встала — см. сообщения выше (сеть / подпись / каталог)." ;;
    en:path_ok)        printf 'PATH: %s is already on PATH — call the tools by name.\n' "$2" ;;
    ru:path_ok)        printf 'PATH: %s уже в PATH — вызывай тулы по имени.\n' "$2" ;;
    en:path_missing)   printf 'WARNING: %s is NOT on PATH. Add this to ~/.zshrc:\n' "$2" ;;
    ru:path_missing)   printf 'ВНИМАНИЕ: %s НЕ в PATH. Добавь в ~/.zshrc:\n' "$2" ;;
    en:state_fail)     printf 'WARNING: could not write %s — the launcher Update item will not find this clone.\n' "$2" ;;
    ru:state_fail)     printf 'ВНИМАНИЕ: не смог записать %s — пункт «Обновить» в лаунчере не найдёт этот клон.\n' "$2" ;;
    en:check_hint)     echo "Check: securetrash version  |  panic version  |  ghostdraft version" ;;
    ru:check_hint)     echo "Проверь: securetrash version  |  panic version  |  ghostdraft version" ;;
    en:run_launcher)   echo "Run the launcher: paranoid" ;;
    ru:run_launcher)   echo "Запусти лаунчер: paranoid" ;;
    en:guide_hint)     echo "Guide: GUIDE.md" ;;
    ru:guide_hint)     echo "Гайд по-русски: ИНСТРУКЦИЯ.md" ;;
    en:partial_exit)   printf 'Installation is incomplete (%s/%s) — exiting with an error. Override: PT_ALLOW_PARTIAL=1.\n' "$2" "$3" ;;
    ru:partial_exit)   printf 'Установка неполная (%s/%s) — выхожу с ошибкой. Обход: PT_ALLOW_PARTIAL=1.\n' "$2" "$3" ;;
    *) echo "$1" ;;
  esac
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  t only_macos >&2; exit 1
fi

# Корень репозитория = каталог этого скрипта (устойчиво к запуску из любого cwd).
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEST="${PT_DEST:-$HOME/.local/bin}"
TOOLS=(securetrash vaultwatch panic ghostdraft seedsplit)

# Подпись релизов: выделенный ed25519-ключ экосистемы (общий для всех 5 тулов).
RELEASE_SIGNING_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U"
SIGN_PRINCIPAL="releases@paranoid-tools"

# Имя env-переменной DEST у install.sh конкретного тула (у каждого свой префикс).
dest_var_for() {
  case "$1" in
    securetrash) echo "ST_DEST" ;;
    vaultwatch)  echo "VW_DEST" ;;
    panic)       echo "PANIC_DEST" ;;
    ghostdraft)  echo "GHOSTDRAFT_DEST" ;;
    seedsplit)   echo "SEEDSPLIT_DEST" ;;
  esac
}

# Имя env-переменной VERSION у install.sh конкретного тула.
version_var_for() {
  case "$1" in
    securetrash) echo "ST_VERSION" ;;
    vaultwatch)  echo "VW_VERSION" ;;
    panic)       echo "PANIC_VERSION" ;;
    ghostdraft)  echo "GHOSTDRAFT_VERSION" ;;
    seedsplit)   echo "SEEDSPLIT_VERSION" ;;
  esac
}

# Режим удаления.
if [[ "${1:-}" == "--uninstall" ]]; then
  t uninstalling "$DEST"
  for t in "${TOOLS[@]}" paranoid; do
    if [[ -e "${DEST}/${t}" ]]; then
      rm -f "${DEST}/${t}"
      t removed "$t"
    fi
  done
  t uninstall_done
  exit 0
fi

# Публичный режим: тянем подписанный релиз тула и ставим его в $DEST.
# verify-then-run: подпись Ed25519 над SHA256SUMS → checksum install.sh → запуск.
# Запускается ТОЛЬКО как условие `if`, поэтому set -e внутри не рвёт весь install.
install_from_release() {
  local t="$1"
  # Релизы до монорепо-миграции живут в архивированных пер-тул репозиториях —
  # GitHub продолжает их отдавать. С первого монорепо-релиза (теги <tool>-vX.Y.Z)
  # base переедет на paranoid-tools/releases.
  local base="https://github.com/Di-kairos/${t}/releases/latest/download"
  local tmp; tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  # Закрепить версию тула, если задана PT_<TOOL>_VERSION.
  local pin_var; pin_var="PT_$(version_var_for "$t" | sed 's/_VERSION//')_VERSION"
  local pin="${!pin_var:-}"
  if [[ -n "$pin" ]]; then
    base="https://github.com/Di-kairos/${t}/releases/download/v${pin}"
  fi

  if ! curl -fsSL "${base}/install.sh" -o "${tmp}/install.sh" 2>/dev/null \
    || ! curl -fsSL "${base}/SHA256SUMS" -o "${tmp}/SHA256SUMS" 2>/dev/null; then
    t dl_fail "$t" "$base" >&2
    return 1
  fi

  # Аутентичность: подпись Ed25519 над SHA256SUMS (поверх целостности). Нет
  # ssh-keygen → громко предупреждаем (проверим только хеш); .sig есть и не
  # сошёлся → жёсткий отказ; .sig нет → отказ (legacy-обход ALLOW_UNSIGNED_LEGACY=1).
  if command -v ssh-keygen >/dev/null 2>&1; then
    if curl -fsSL "${base}/SHA256SUMS.sig" -o "${tmp}/SHA256SUMS.sig" 2>/dev/null; then
      printf '%s namespaces="file" %s\n' "$SIGN_PRINCIPAL" "$RELEASE_SIGNING_PUBKEY" > "${tmp}/allowed_signers"
      if ! ( cd "$tmp" && ssh-keygen -Y verify -f allowed_signers -I "$SIGN_PRINCIPAL" \
                            -n file -s SHA256SUMS.sig < SHA256SUMS >/dev/null 2>&1 ); then
        t sig_bad "$t" >&2
        return 1
      fi
    elif [[ "${ALLOW_UNSIGNED_LEGACY:-0}" != "1" ]]; then
      t sig_missing "$t" >&2
      return 1
    fi
  else
    # Нет verifier'а. На macOS ssh-keygen идёт в комплекте → его отсутствие аномально;
    # молчаливая деградация до hash-only маскировала бы подмену. Fail-closed (P1-4).
    if [[ "${ALLOW_UNSIGNED_LEGACY:-0}" != "1" ]]; then
      t no_verifier "$t" >&2
      return 1
    fi
    t no_verifier_warn "$t" >&2
  fi

  # Целостность: хеш самого install.sh из (уже проверенного подписью) SHA256SUMS.
  if ! ( cd "$tmp" && shasum -a 256 -c SHA256SUMS --ignore-missing >/dev/null 2>&1 ); then
    t sum_mismatch "$t" >&2
    return 1
  fi

  # Запускаем проверенный install.sh тула, направив его DEST в наш каталог.
  # Он сам до-проверяет бинарь (SHA256 + та же подпись Ed25519) перед установкой.
  local dvar; dvar="$(dest_var_for "$t")"
  local vvar; vvar="$(version_var_for "$t")"
  # stderr вложенного установщика НЕ глушим (иначе провал подписи/подмена неотличимы от
  # сетевой ошибки) — ловим в лог и проксируем при провале (P1-4).
  local errlog="${tmp}/${t}.install.err"
  if ! env "${dvar}=${DEST}/${t}" ${pin:+"${vvar}=${pin}"} bash "${tmp}/install.sh" >/dev/null 2>"$errlog"; then
    t tool_fail "$t" >&2
    sed 's/^/      /' "$errlog" >&2
    return 1
  fi
  return 0
}

mkdir -p "$DEST"

t installing "$DEST"
installed=0
for t in "${TOOLS[@]}"; do
  local_src="${ROOT}/${t}/${t}"
  if [[ "${PT_DEV:-0}" == "1" && -f "$local_src" ]]; then
    # MAINTAINER (PT_DEV=1): локальный скрипт — копируем (вкл. невыпущенные правки).
    install -m 0755 "$local_src" "${DEST}/${t}"
    t from_worktree "$t" "${DEST}/${t}"
    installed=$((installed + 1))
  elif install_from_release "$t"; then
    # ПУБЛИКА: подтянут и проверен подписанный релиз.
    t from_release "$t" "${DEST}/${t}"
    installed=$((installed + 1))
  fi
done

# Лаунчер paranoid лежит в корне этого репо (он версионируется здесь, не в
# отдельном тул-репо) — потому всегда на месте в любом clone, ставим отдельно.
install -m 0755 "${ROOT}/paranoid" "${DEST}/paranoid"
echo "  ✓ paranoid → ${DEST}/paranoid"

echo
t installed_n "$installed" "${#TOOLS[@]}"
partial=0
if [[ "$installed" -lt "${#TOOLS[@]}" ]]; then
  t partial_note >&2
  partial=1
fi

# Проверка PATH: без этого тулы стоят, но не вызываются по имени.
case ":$PATH:" in
  *":$DEST:"*) t path_ok "$DEST" ;;
  *)
    t path_missing "$DEST"
    echo "  export PATH=\"${DEST}:\$PATH\""
    ;;
esac

# Запоминаем, ОТКУДА ставили: лаунчер (`paranoid` → Update) перезапускает установщик
# из этого каталога. Без этого пункт меню не знал бы, что обновлять — копия лаунчера
# в ~/.local/bin про свой исходный клон ничего не знает.
_state_dir="${XDG_DATA_HOME:-$HOME/.local/share}/paranoid-tools"
if mkdir -p "$_state_dir" 2>/dev/null; then
  # Сносим прежний файл до записи: если это симлинк, `>` затёр бы его цель.
  rm -f "$_state_dir/source" 2>/dev/null || true
  if ! printf '%s\n' "$ROOT" > "$_state_dir/source" 2>/dev/null; then
    t state_fail "${_state_dir}/source" >&2
  fi
fi

echo
t check_hint
t run_launcher
t guide_hint

# Частичная установка — не тихий успех: выходим с ошибкой (обход: PT_ALLOW_PARTIAL=1). P2-3.
if [[ "$partial" == "1" && "${PT_ALLOW_PARTIAL:-0}" != "1" ]]; then
  echo >&2
  t partial_exit "$installed" "${#TOOLS[@]}" >&2
  exit 1
fi
