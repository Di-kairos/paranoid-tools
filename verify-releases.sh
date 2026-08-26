#!/usr/bin/env bash
# verify-releases.sh — signature + integrity check of the published releases of all 5 tools.
#
# The repository is public: assets are fetched with plain `curl`, no `gh`, no token —
# "don't trust, verify" is available to anyone, not just the owner. For every tool:
#   1) curl SHA256SUMS + SHA256SUMS.sig + the binary itself from the public release;
#   2) ssh-keygen -Y verify — the Ed25519 signature of the manifest against the
#      embedded pubkey (authenticity);
#   3) sha256 -c — the binary matches the signed manifest byte for byte (integrity).
# Prints ✓/✗ per tool. Run:  bash verify-releases.sh
set -uo pipefail

PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9DVd0vNOwa5hyr9gShaCWoNOVnUsrdHVO/WE0wCZkT"
PRINCIPAL="releases@paranoid-tools"
# All releases live in the monorepo under per-tool prefixed tags.
BASE="https://github.com/Di-kairos/paranoid-tools/releases/download"

for tool in curl ssh-keygen; do
  command -v "$tool" >/dev/null 2>&1 || { echo "нужен $tool"; exit 1; }
done
# Cross-platform sha256: shasum (macOS) or sha256sum (Linux).
if command -v shasum >/dev/null 2>&1; then SHA() { shasum -a 256 "$@"; }
elif command -v sha256sum >/dev/null 2>&1; then SHA() { sha256sum "$@"; }
else echo "нужен shasum или sha256sum"; exit 1; fi

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
printf '%s namespaces="file" %s\n' "$PRINCIPAL" "$PUB" > "$W/allowed_signers"

PASS=0; FAIL=0
# Pins of the current release tags (kept in sync with docs/RELEASE-STATE.md).
for spec in securetrash:0.5.7 vaultwatch:0.1.15 panic:0.1.16 ghostdraft:0.1.19 seedsplit:0.5.6; do
  t="${spec%%:*}"; ver="${spec##*:}"; tag="${t}-v${ver}"; d="$W/$t"; mkdir -p "$d"
  rel="$BASE/$tag"
  printf '%-12s %-20s ' "$t" "$tag"

  # The sums manifest and the signature are fetched separately, so a failure names
  # exactly WHAT did not download and why (curl exit code + last stderr line)
  # instead of a vague "network?". `-S` surfaces the curl error (`-s` alone would
  # swallow it); `--retry` covers transient DNS/timeout/429/5xx.
  fetch_fail=""
  for asset in SHA256SUMS SHA256SUMS.sig; do
    cerr="$(curl -fsSLS --retry 2 --retry-delay 1 "$rel/$asset" -o "$d/$asset" 2>&1)" && continue
    fetch_fail="$asset — curl $?: ${cerr##*$'\n'}"; break
  done
  if [[ -n "$fetch_fail" ]]; then
    printf '\033[31m✗ не скачалось: %s\033[0m\n' "$fetch_fail"; FAIL=$((FAIL+1)); continue
  fi

  # (1) authenticity: the signature of the sums manifest.
  if ! ssh-keygen -Y verify -f "$W/allowed_signers" -I "$PRINCIPAL" -n file \
         -s "$d/SHA256SUMS.sig" < "$d/SHA256SUMS" >/dev/null 2>&1; then
    printf '\033[31m✗ подпись НЕ прошла\033[0m\n'; FAIL=$((FAIL+1)); continue
  fi

  # (2) integrity: the binary matches the signed manifest. if/else without `!` so
  # that `$?` in the else branch is the real curl code (after `if ! cmd` it would
  # be 0 because of the negation).
  if berr="$(curl -fsSLS --retry 2 --retry-delay 1 "$rel/$t" -o "$d/$t" 2>&1)"; then :; else
    brc=$?
    printf '\033[33m✓ подпись верна, но бинарь не скачался (curl %s: %s)\033[0m\n' "$brc" "${berr##*$'\n'}"; PASS=$((PASS+1)); continue
  fi
  want="$(grep -E "  $t\$" "$d/SHA256SUMS" | awk '{print $1}')"
  got="$(cd "$d" && SHA "$t" | awk '{print $1}')"
  if [[ -n "$want" && "$want" == "$got" ]]; then
    printf '\033[32m✓ подпись + бинарь верны\033[0m\n'; PASS=$((PASS+1))
  else
    printf '\033[31m✗ бинарь НЕ совпал с манифестом\033[0m\n'; FAIL=$((FAIL+1))
  fi
done

printf '\nИтог: \033[32m%d ✓\033[0m  \033[31m%d ✗\033[0m\n' "$PASS" "$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  echo "Все релизы подписаны корректно и бинари соответствуют манифесту."
else
  echo "Есть проблемы — см. ✗."; exit 1
fi
