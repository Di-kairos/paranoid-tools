#!/usr/bin/env bash
# vendor-common.sh — embeds securetrash lib/common.sh inline into the ghostdraft file
# between markers. The source is pinned to a securetrash git ref AND to a SHA256 of the
# contents (defense-in-depth: a ref can be rewritten/MITM'd — the hash catches byte tampering).
#
# Usage:
#   tools/vendor-common.sh          # refresh the embedded block from the source (network required)
#   tools/vendor-common.sh --check  # CI: embedded block == pinned SHA256 (OFFLINE, no network)
#
# When bumping the common.sh version, update PIN and COMMON_SHA256 together (and the BEGIN marker).
set -euo pipefail

PIN="42fc268"
COMMON_SHA256="7f122385b8a8f62021f9883c185409ec3f4dc26bcfb59521d127a91368649f45"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Monorepo: the source is the sibling securetrash directory in this same repository.
# PIN remains the version label in the markers, SHA256 still guards the bytes.
SRC_FILE="${ROOT}/../securetrash/lib/common.sh"
TARGET="${ROOT}/ghostdraft"
BEGIN="# === BEGIN vendored common (pin: ${PIN}) ==="
END="# === END vendored common ==="

# Exactly one pair of markers — otherwise the awk parsing in build_expected is incorrect.
_assert_markers() {
  local nb ne
  nb="$(grep -cF '# === BEGIN vendored common' "$TARGET" || true)"
  ne="$(grep -cF "$END" "$TARGET" || true)"
  if [[ "$nb" != "1" || "$ne" != "1" ]]; then
    echo "vendor: в $TARGET ожидается ровно по одному маркеру BEGIN/END (нашёл BEGIN=$nb END=$ne)" >&2
    exit 1
  fi
}

# Take common.sh from the monorepo (exact bytes) and verify SHA256. Missing
# file/hash failure → exit 3 (NOT "drift": CI must distinguish a source failure from desync).
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

# Assemble the expected file: everything before BEGIN, a fresh BEGIN, the exact bytes of
# common.sh, END, everything after END. Bytes are embedded via cat (no trimming of the final newline).
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
  # OFFLINE: hash the embedded block and compare against the pinned SHA256 — no network.
  # CI does not depend on securetrash being reachable (or private); the network MITM
  # surface is eliminated — the trusted anchor is the COMMON_SHA256 pin itself in this file (under git).
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
  # UPDATE: pull the exact bytes of common.sh from the pinned ref (network required) and verify the SHA.
  COMMON_FILE="$(mktemp)"
  trap 'rm -f "$COMMON_FILE"' EXIT
  _fetch_common_to "$COMMON_FILE"
  tmp="$(mktemp)"
  build_expected "$COMMON_FILE" > "$tmp"
  # Preserve the target file's mode (mv from mktemp would clobber +x).
  mode="$(stat -f '%Lp' "$TARGET" 2>/dev/null || echo 755)"
  mv "$tmp" "$TARGET"
  chmod "$mode" "$TARGET"
  echo "vendor: вшит проверенный common.sh из securetrash@${PIN:0:7} → $TARGET"
fi
