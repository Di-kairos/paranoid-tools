#!/usr/bin/env bash
# vendor-common.sh — вшивает securetrash lib/common.sh inline в файл panic
# между маркерами. Источник пиннут к git-ref securetrash И к SHA256 содержимого
# (defense-in-depth: ref может быть переписан/MITM — хеш ловит подмену байтов).
#
# Использование:
#   tools/vendor-common.sh          # обновить вшитый блок из источника (нужна сеть)
#   tools/vendor-common.sh --check  # CI: вшитый блок == запиннутому SHA256 (ОФЛАЙН, без сети)
#
# При бампе версии common.sh обнови PIN и COMMON_SHA256 вместе (и маркер BEGIN).
set -euo pipefail

PIN="221f2c7fbed10a220b832aab9264e6665581b514"
COMMON_SHA256="348afdd5d924230b4eea6e495b6b21bd78fc851ac5795108078abf7dc5d4e6a0"
SRC_URL="https://raw.githubusercontent.com/Di-kairos/securetrash/${PIN}/lib/common.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${ROOT}/panic"
BEGIN="# === BEGIN vendored common (pin: ${PIN}) ==="
END="# === END vendored common ==="

# Ровно одна пара маркеров — иначе awk-разбор в build_expected некорректен.
_assert_markers() {
  local nb ne
  nb="$(grep -cF '# === BEGIN vendored common' "$TARGET" || true)"
  ne="$(grep -cF "$END" "$TARGET" || true)"
  if [[ "$nb" != "1" || "$ne" != "1" ]]; then
    echo "vendor: в $TARGET ожидается ровно по одному маркеру BEGIN/END (нашёл BEGIN=$nb END=$ne)" >&2
    exit 1
  fi
}

# Скачать common.sh в файл (точные байты) и верифицировать SHA256. Падение
# сети/хеша → exit 3 (НЕ «дрейф»: CI должен отличать сбой загрузки от рассинхрона).
_fetch_common_to() {
  local out="$1" actual
  curl -fsSL "$SRC_URL" -o "$out" || { echo "vendor: сеть недоступна, не удалось получить $SRC_URL" >&2; exit 3; }
  [[ -s "$out" ]] || { echo "vendor: пустой источник" >&2; exit 3; }
  actual="$(shasum -a 256 "$out" | awk '{print $1}')"
  if [[ "$actual" != "$COMMON_SHA256" ]]; then
    echo "vendor: SHA256 источника НЕ совпал (возможна подмена)." >&2
    echo "  expected: $COMMON_SHA256" >&2
    echo "  actual:   $actual" >&2
    exit 3
  fi
}

# Собрать ожидаемый файл: всё до BEGIN, свежий BEGIN, точные байты common.sh, END,
# всё после END. Байты вшиваются через cat (без среза финального newline).
build_expected() {
  local commonfile="$1"
  awk '/# === BEGIN vendored common/{exit} {print}' "$TARGET"
  printf '%s\n' "$BEGIN"
  cat "$commonfile"
  printf '%s\n' "$END"
  awk 'p{print} /# === END vendored common/{p=1}' "$TARGET"
}

# Извлечь вшитый блок (строки строго между маркерами) — для офлайн-сверки хеша.
_extract_block() {
  awk 'f && /# === END vendored common/{exit} f{print} /# === BEGIN vendored common/{f=1}' "$TARGET"
}

_assert_markers

if [[ "${1:-}" == "--check" ]]; then
  # ОФЛАЙН: хешируем вшитый блок и сверяем с запиннутым SHA256 — без сети. CI не зависит
  # от доступности (в т.ч. приватности) securetrash; MITM-поверхность сети исключена —
  # доверенный якорь это сам пин COMMON_SHA256 в этом файле (под git).
  actual="$(_extract_block | shasum -a 256 | awk '{print $1}')"
  if [[ "$actual" == "$COMMON_SHA256" ]]; then
    echo "vendor: вшитый common.sh синхронен пину ${PIN:0:7} и хешу ✓ (offline)"
  else
    echo "vendor: ДРЕЙФ — вшитый common.sh не совпадает с запиннутым SHA256." >&2
    echo "  expected: $COMMON_SHA256" >&2
    echo "  actual:   $actual" >&2
    echo "  Запусти tools/vendor-common.sh для пере-вшивания из источника." >&2
    exit 1
  fi
else
  # ОБНОВЛЕНИЕ: тянем точные байты common.sh с пиннутого ref (нужна сеть) и сверяем SHA.
  COMMON_FILE="$(mktemp)"
  trap 'rm -f "$COMMON_FILE"' EXIT
  _fetch_common_to "$COMMON_FILE"
  tmp="$(mktemp)"
  build_expected "$COMMON_FILE" > "$tmp"
  # Сохранить режим целевого файла (mv от mktemp затёр бы +x).
  mode="$(stat -f '%Lp' "$TARGET" 2>/dev/null || echo 755)"
  mv "$tmp" "$TARGET"
  chmod "$mode" "$TARGET"
  echo "vendor: вшит проверенный common.sh из securetrash@${PIN:0:7} → $TARGET"
fi
