# shellcheck shell=bash
# common.sh — переиспользуемые примитивы экосистемы Paranoid Tools.
#
# Канонический источник: securetrash/lib/common.sh. Инструменты экосистемы
# (vaultwatch/panic/ghostdraft) вендорят его inline между маркерами
# (см. CLAUDE.md «Vendoring»). Файл sourceable и идемпотентен (двойной source/inline
# безопасны — guard через if-обёртку, без top-level return, поэтому корректен и когда
# блок вставлен в исполняемый скрипт).
#
# Даёт tool-агностичные примитивы: локаль (ST_LOCALE), цветной вывод (info/warn/err),
# подтверждение (confirm), детект платформы macOS (require_macos/is_ssd/_disk_kind/
# _fv_state/filevault_on), детект примонтированного тома (_volume_mounted), канонизацию
# пути (_abspath). Своя i18n-таблица — у каждого инструмента.
#
# ВЕНДОРИНГ — зарезервированные имена (не переопределять в host-скрипте): функции
# info warn err confirm require_macos is_ssd _disk_kind _fv_state filevault_on
# _volume_mounted _abspath _st_detect_locale; переменные ST_LOCALE C_RED C_GRN C_YEL
# C_RST _ST_COMMON_LOADED.

# Идемпотентность через if-обёртку (а не top-level return): безопасно при source,
# исполнении и inline-вставке. Определения функций внутри if регистрируются глобально.
if [[ -z "${_ST_COMMON_LOADED:-}" ]]; then
  _ST_COMMON_LOADED=1

  # --- locale ---
  # en по умолчанию; ru — если ST_LANG или системная локаль начинаются с 'ru'.
  _st_detect_locale() {
    local want="${ST_LANG:-}"
    if [[ -n "$want" ]]; then
      case "$want" in ru*) echo ru ;; *) echo en ;; esac
      return
    fi
    local sys="${LC_ALL:-${LANG:-}}"
    case "$sys" in ru*) echo ru ;; *) echo en ;; esac
  }
  # Уважаем заранее выставленный ST_LOCALE (host может переопределить).
  ST_LOCALE="${ST_LOCALE:-$(_st_detect_locale)}"

  # --- output ---
  # Цвет только в TTY (в пайпах/файлах — без ANSI).
  if [[ -t 1 ]]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RST=$'\033[0m'
  else
    C_RED=""; C_GRN=""; C_YEL=""; C_RST=""
  fi
  info() { echo "${C_GRN}✓${C_RST} $*"; }
  warn() { echo "${C_YEL}!${C_RST} $*" >&2; }
  err()  { echo "${C_RED}✗${C_RST} $*" >&2; }

  # --- confirm ---
  # Подтверждение необратимой операции. ST_ASSUME_YES=1 обходит вопрос (скрипты/тесты).
  # Возвращает 0 только при точном вводе 'yes' (EOF/пусто → отказ, fail-closed).
  # Суффикс намеренно продублирован из i18n securetrash (lib без таблицы строк).
  confirm() {
    local prompt="$1" ans suffix
    [[ "${ST_ASSUME_YES:-0}" == "1" ]] && return 0
    case "$ST_LOCALE" in ru) suffix="[введите yes]" ;; *) suffix="[type yes]" ;; esac
    read -r -p "$prompt $suffix: " ans
    [[ "$ans" == "yes" ]]
  }

  # --- platform (macOS) ---
  require_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
      case "$ST_LOCALE" in
        ru) err "работает только на macOS." ;;
        *)  err "runs on macOS only." ;;
      esac
      exit 1
    fi
  }

  # Диск под путём — SSD? (diskutil info: "Solid State: Yes")
  is_ssd() {
    local path="${1:-/}"
    diskutil info "$path" 2>/dev/null | grep -qi "Solid State:.*Yes"
  }

  # Тип диска: ssd | hdd | unknown. Честность важнее догадок: неизвестный тип
  # НЕ приравниваем к hdd-эффективному (нет поля "Solid State" → unknown).
  _disk_kind() {
    local path="${1:-/}" out
    out="$(diskutil info "$path" 2>/dev/null)"
    if grep -qi "Solid State:.*Yes" <<<"$out"; then echo ssd
    elif grep -qi "Solid State:.*No" <<<"$out"; then echo hdd
    else echo unknown; fi
  }

  # Состояние FileVault — tri-state: on / off / unknown. Отличать «выключен» от
  # «не смогли определить» обязательно: инструмент, который печатает «ВЫКЛЮЧЕН» на
  # отсутствующий fdesetup, врёт пользователю о его защите.
  #
  # Вывод захватываем в переменную и матчим here-string, а НЕ через прямой пайп
  # `fdesetup ... | grep -q`: под `set -o pipefail` такой пайп ложно «падает» — grep -q
  # закрывает канал на первом совпадении, источник получает SIGPIPE (141), и pipefail
  # делает весь конвейер ненулевым (ложный unknown).
  _fv_state() {
    command -v fdesetup >/dev/null 2>&1 || { echo unknown; return; }
    local s; s="$(fdesetup status 2>/dev/null)"
    if   grep -qi "FileVault is On"  <<<"$s"; then echo on
    elif grep -qi "FileVault is Off" <<<"$s"; then echo off
    else echo unknown; fi
  }

  # FileVault включён? Двоичная обёртка над _fv_state для мест, где «не определили»
  # безопасно трактовать как «не включён» (fail-closed).
  filevault_on() {
    [[ "$(_fv_state)" == on ]]
  }

  # Том РЕАЛЬНО примонтирован по этому пути? Единственный ответ на этот вопрос в
  # экосистеме — раньше их было три: `[[ -d ]]` (лаунчер), `mount | grep` (ghostdraft),
  # mountedVolumeURLs (GUI), и на остаточном каталоге /Volumes/… они расходились:
  # каталог, оставшийся от прошлого монтирования (или созданный руками), читался как
  # «ОТКРЫТ». Проверяем таблицу монтирования, а не наличие каталога.
  #
  # Разбираем строку `mount` целиком и сравниваем точку монтирования ЦЕЛИКОМ, а не
  # ищем подстроку: `grep -F " on /Volumes/Foo "` считает смонтированным `/Volumes/Foo`,
  # когда на деле смонтирован `/Volumes/Foo Bar` — пробел внутри имени тома выглядит
  # как разделитель перед опциями (нашёл Codex). Формат строки на macOS:
  #   /dev/diskNsM on /Volumes/Имя тома (apfs, local, nobrowse)
  # Имя тома может содержать и пробелы, и `(`, поэтому опции срезаем КОРОТЧАЙШИМ
  # суффиксом ` (*` — у тома `/Volumes/Foo (1)` останется именно `/Volumes/Foo (1)`.
  _volume_mounted() {
    local vol="${1:-}" line mp
    [[ -n "$vol" ]] || return 1
    while [[ "$vol" == */ && "$vol" != "/" ]]; do vol="${vol%/}"; done
    while IFS= read -r line; do
      [[ "$line" == *" on "* ]] || continue
      mp="${line#* on }"
      mp="${mp% (*}"
      [[ "$mp" == "$vol" ]] && return 0
    done < <(mount 2>/dev/null)
    return 1
  }

  # --- path ---
  # Физический канонический путь: режет trailing-slash, резолвит .. и симлинки,
  # ВКЛЮЧАЯ финальный компонент. Непустая строка или код !=0, если путь недоступен.
  _abspath() {
    local p="$1"
    while [[ "$p" == */ && "$p" != "/" ]]; do p="${p%/}"; done
    if [[ -d "$p" ]]; then
      ( cd -P -- "$p" 2>/dev/null && pwd -P ); return
    fi
    local d b
    d="$(cd -P -- "$(dirname -- "$p")" 2>/dev/null && pwd -P)" || return 1
    b="$(basename -- "$p")"
    printf '%s/%s' "${d%/}" "$b"
  }
fi
