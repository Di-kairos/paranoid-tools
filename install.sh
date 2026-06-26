#!/usr/bin/env bash
# Установщик ВСЕЙ экосистемы Paranoid Tools — «одна команда, всё есть».
#
# Ставит 5 инструментов (securetrash, vaultwatch, panic, ghostdraft, seedsplit)
# + интерактивный лаунчер `paranoid` в ~/.local/bin. Два режима, выбираются
# автоматически по тому, есть ли рядом локальные исходники тулов:
#
#   1. ПУБЛИКА (свежий clone этого репо). Подпапок тулов нет (они в отдельных
#      репозиториях и сюда не вендорятся) → каждый тул тянется из его
#      ПОДПИСАННОГО релиза по схеме verify-then-run: проверяется подпись Ed25519
#      над SHA256SUMS, затем контрольная сумма самого install.sh тула, и только
#      потом он запускается (а он, в свою очередь, проверяет и бинарь). Так
#      «git clone + bash install.sh» честно даёт все 5 без ручной возни.
#
#   2. MAINTAINER (полная рабочая копия на X10, где 5 тул-репо лежат соседними
#      подпапками). Локальный скрипт `<tool>/<tool>` есть → просто копируется,
#      включая ещё не выпущенные правки. Релиз не дёргается.
#
# Использование:
#   bash install.sh                 # поставить/обновить все 5 (+ лаунчер)
#   bash install.sh --uninstall     # удалить все 5 (+ лаунчер) из bin-каталога
#   PT_DEST=/usr/local/bin bash install.sh   # другой каталог установки
#
# Переменные окружения:
#   PT_DEST            — каталог установки. По умолчанию ~/.local/bin (без sudo).
#   PT_<TOOL>_VERSION  — закрепить версию конкретного тула (публичный режим),
#                        напр. PT_PANIC_VERSION=0.1.5. По умолчанию latest.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Paranoid Tools рассчитаны на macOS." >&2; exit 1
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
  echo "Удаляю Paranoid Tools из ${DEST}..."
  for t in "${TOOLS[@]}" paranoid; do
    if [[ -e "${DEST}/${t}" ]]; then
      rm -f "${DEST}/${t}"
      echo "  ✓ удалён ${t}"
    fi
  done
  echo "Готово. (Homebrew-версия securetrash, если была, не тронута — снимай через 'brew uninstall'.)"
  exit 0
fi

# Публичный режим: тянем подписанный релиз тула и ставим его в $DEST.
# verify-then-run: подпись Ed25519 над SHA256SUMS → checksum install.sh → запуск.
# Запускается ТОЛЬКО как условие `if`, поэтому set -e внутри не рвёт весь install.
install_from_release() {
  local t="$1"
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
    echo "  ✗ ${t}: не удалось скачать релиз (${base})." >&2
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
        echo "  ✗ ${t}: подпись релиза НЕ прошла проверку — пропускаю (возможна подмена)." >&2
        return 1
      fi
    elif [[ "${ALLOW_UNSIGNED_LEGACY:-0}" != "1" ]]; then
      echo "  ✗ ${t}: подпись релиза недоступна — пропускаю (обход: ALLOW_UNSIGNED_LEGACY=1)." >&2
      return 1
    fi
  else
    echo "  ! ssh-keygen недоступен — подпись ${t} НЕ проверена (только целостность по SHA256)." >&2
  fi

  # Целостность: хеш самого install.sh из (уже проверенного подписью) SHA256SUMS.
  if ! ( cd "$tmp" && shasum -a 256 -c SHA256SUMS --ignore-missing >/dev/null 2>&1 ); then
    echo "  ✗ ${t}: контрольная сумма install.sh не совпала — пропускаю." >&2
    return 1
  fi

  # Запускаем проверенный install.sh тула, направив его DEST в наш каталог.
  # Он сам до-проверяет бинарь (SHA256 + та же подпись Ed25519) перед установкой.
  local dvar; dvar="$(dest_var_for "$t")"
  local vvar; vvar="$(version_var_for "$t")"
  if ! env "${dvar}=${DEST}/${t}" ${pin:+"${vvar}=${pin}"} bash "${tmp}/install.sh" >/dev/null 2>&1; then
    echo "  ✗ ${t}: установщик тула завершился с ошибкой." >&2
    return 1
  fi
  return 0
}

mkdir -p "$DEST"

echo "Ставлю Paranoid Tools в ${DEST}..."
installed=0
for t in "${TOOLS[@]}"; do
  local_src="${ROOT}/${t}/${t}"
  if [[ -f "$local_src" ]]; then
    # MAINTAINER: локальный скрипт рядом — копируем (вкл. невыпущенные правки).
    install -m 0755 "$local_src" "${DEST}/${t}"
    echo "  ✓ ${t} → ${DEST}/${t} (из рабочей копии)"
    installed=$((installed + 1))
  elif install_from_release "$t"; then
    # ПУБЛИКА: подтянут и проверен подписанный релиз.
    echo "  ✓ ${t} → ${DEST}/${t} (из подписанного релиза)"
    installed=$((installed + 1))
  fi
done

# Лаунчер paranoid лежит в корне этого репо (он версионируется здесь, не в
# отдельном тул-репо) — потому всегда на месте в любом clone, ставим отдельно.
install -m 0755 "${ROOT}/paranoid" "${DEST}/paranoid"
echo "  ✓ paranoid → ${DEST}/paranoid"

echo
echo "Установлено инструментов: ${installed}/${#TOOLS[@]} (+ лаунчер paranoid)."
if [[ "$installed" -lt "${#TOOLS[@]}" ]]; then
  echo "Часть тулов не встала — см. сообщения выше (сеть / подпись / каталог)." >&2
fi

# Проверка PATH: без этого тулы стоят, но не вызываются по имени.
case ":$PATH:" in
  *":$DEST:"*) echo "PATH: ${DEST} уже в PATH — вызывай тулы по имени." ;;
  *)
    echo "ВНИМАНИЕ: ${DEST} НЕ в PATH. Добавь в ~/.zshrc:"
    echo "  export PATH=\"${DEST}:\$PATH\""
    ;;
esac

echo
echo "Проверь: securetrash version  |  panic version  |  ghostdraft version"
echo "Запусти лаунчер: paranoid"
echo "Гайд по-русски: КАК-ПОЛЬЗОВАТЬСЯ.ru.md"
