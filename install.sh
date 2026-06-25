#!/usr/bin/env bash
# Локальный установщик ВСЕЙ экосистемы Paranoid Tools из рабочей копии.
#
# Назначение: личное использование на своей машине. Ставит 5 инструментов
# (securetrash, vaultwatch, panic, ghostdraft, seedsplit) из ЭТОГО репозитория
# на X10 — не из GitHub-релизов. Так удобно владельцу: один запуск — все тулы
# в PATH, включая локальные правки ещё до выпуска нового релиза.
#
# Отличие от per-tool install.sh: те тянут подписанный релиз из GitHub (для
# ПУБЛИКИ, с проверкой SHA). Этот — копирует локальные скрипты (для СЕБЯ).
#
# Использование:
#   bash install.sh                 # поставить/обновить все 5 в ~/.local/bin
#   bash install.sh --uninstall     # удалить все 5 из bin-каталога
#   PT_DEST=/usr/local/bin bash install.sh   # другой каталог установки
#
# Каждый тул — самодостаточный bash-скрипт (common.sh вшит в него), внешних
# рантайм-зависимостей нет, потому установка = copy + chmod.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Paranoid Tools рассчитаны на macOS." >&2; exit 1
fi

# Корень репозитория = каталог этого скрипта (устойчиво к запуску из любого cwd).
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEST="${PT_DEST:-$HOME/.local/bin}"
TOOLS=(securetrash vaultwatch panic ghostdraft seedsplit)

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

mkdir -p "$DEST"

echo "Ставлю Paranoid Tools в ${DEST} из ${ROOT}..."
installed=0
for t in "${TOOLS[@]}"; do
  src="${ROOT}/${t}/${t}"
  if [[ ! -f "$src" ]]; then
    echo "  ✗ пропускаю ${t}: не найден ${src}" >&2
    continue
  fi
  install -m 0755 "$src" "${DEST}/${t}"
  echo "  ✓ ${t} → ${DEST}/${t}"
  installed=$((installed + 1))
done

# Лаунчер paranoid лежит в корне этого репо (рядом с install.sh), а не в
# отдельном репо, как пять тулов — потому всегда на месте, ставим отдельно.
install -m 0755 "${ROOT}/paranoid" "${DEST}/paranoid"
echo "  ✓ paranoid → ${DEST}/paranoid"

echo
echo "Установлено инструментов: ${installed}/${#TOOLS[@]} (+ лаунчер paranoid)."

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
echo "Гайд по-русски: КАК-ПОЛЬЗОВАТЬСЯ.ru.md"
