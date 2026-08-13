#!/usr/bin/env bash
# vendor-common.sh — embeds securetrash lib/common.sh inline into the panic file
# between the markers. The source is pinned to a securetrash git ref AND to the content's
# SHA256 (defense-in-depth: the ref can be rewritten/MITMed — the hash catches byte substitution).
#
# Usage:
#   tools/vendor-common.sh          # refresh the embedded block from the source (needs network)
#   tools/vendor-common.sh --check  # CI: embedded block == pinned SHA256 (OFFLINE, no network)
#
# When bumping the common.sh version, update PIN and COMMON_SHA256 together (and the BEGIN marker).
set -euo pipefail

PIN="221f2c7fbed10a220b832aab9264e6665581b514"
COMMON_SHA256="348afdd5d924230b4eea6e495b6b21bd78fc851ac5795108078abf7dc5d4e6a0"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Monorepo: the source is the sibling securetrash directory in this same repository.
# PIN remains the version label in the markers; SHA256 still guards the bytes.
SRC_FILE="${ROOT}/../securetrash/lib/common.sh"
TARGET="${ROOT}/panic"
BEGIN="# === BEGIN vendored common (pin: ${PIN}) ==="
END="# === END vendored common ==="

# Exactly one marker pair — otherwise the awk parsing in build_expected is incorrect.
_assert_markers() {
  local nb ne
  nb="$(grep -cF '# === BEGIN vendored common' "$TARGET" || true)"
  ne="$(grep -cF "$END" "$TARGET" || true)"
  if [[ "$nb" != "1" || "$ne" != "1" ]]; then
    echo "vendor: в $TARGET ожидается ровно по одному маркеру BEGIN/END (нашёл BEGIN=$nb END=$ne)" >&2
    exit 1
  fi
}

# Take common.sh from the monorepo (exact bytes) and verify its SHA256. Missing
# file / hash failure → exit 3 (NOT "drift": CI must tell source failure apart from desync).
_fetch_common_to() {
  local out="$1" actual
  cp "$SRC_FILE" "$out" 2>/dev/null || { echo "vendor: не найден источник $SRC_FILE" >&2; exit 3; }
  [[ -s "$out" ]] || { echo "vendor: пустой источник" >&2; exit 3; }
  actual="$(shasum -a 256 "$out" | awk '{print $1}')"
  if [[ "$actual" != "$COMMON_SHA256" ]]; then
    echo "vendor: SHA256 источника НЕ совпал (возможна подмена)." >&2
    echo "  expected: $COMMON_SHA256" >&2
    echo "  actual:   $actual" >&2
    exit 3
  fi
}

# Build the expected file: everything before BEGIN, a fresh BEGIN, exact common.sh bytes, END,
# everything after END. The bytes are embedded via cat (no trimming of the final newline).
build_expected() {
  local commonfile="$1"
  awk '/# === BEGIN vendored common/{exit} {print}' "$TARGET"
  printf '%s\n' "$BEGIN"
  cat "$commonfile"
  printf '%s\n' "$END"
  awk 'p{print} /# === END vendored common/{p=1}' "$TARGET"
}

# Extract the embedded block (lines strictly between the markers) — for the offline hash check.
_extract_block() {
  awk 'f && /# === END vendored common/{exit} f{print} /# === BEGIN vendored common/{f=1}' "$TARGET"
}

_assert_markers

if [[ "${1:-}" == "--check" ]]; then
  # OFFLINE: hash the embedded block and compare against the pinned SHA256 — no network. CI does
  # not depend on securetrash's availability (incl. its privacy); the network MITM surface is out —
  # the trusted anchor is the COMMON_SHA256 pin itself in this file (under git).
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
  # UPDATE: pull exact common.sh bytes from the pinned ref (needs network) and check the SHA.
  COMMON_FILE="$(mktemp)"
  trap 'rm -f "$COMMON_FILE"' EXIT
  _fetch_common_to "$COMMON_FILE"
  tmp="$(mktemp)"
  build_expected "$COMMON_FILE" > "$tmp"
  # Preserve the target file's mode (mv from mktemp would wipe +x).
  mode="$(stat -f '%Lp' "$TARGET" 2>/dev/null || echo 755)"
  mv "$tmp" "$TARGET"
  chmod "$mode" "$TARGET"
  echo "vendor: вшит проверенный common.sh из securetrash@${PIN:0:7} → $TARGET"
fi
