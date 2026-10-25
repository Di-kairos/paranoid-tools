#!/usr/bin/env bash
# verify-releases.sh — signature + integrity check of the published releases of all 5 tools.
#
# The repository is public: assets are fetched with plain `curl`, no `gh`, no token —
# "don't trust, verify" is available to anyone, not just the owner. For every tool:
#   1) curl SHA256SUMS + SHA256SUMS.sig + every signed file of the release;
#   2) ssh-keygen -Y verify — the Ed25519 signature of the manifest against the
#      embedded pubkey (authenticity);
#   3) sha256 -c — each file matches the signed manifest byte for byte (integrity).
# Prints ✓/✗ per tool. Run:  bash verify-releases.sh
#
# A release ships FOUR signed files (see .github/workflows/release.yml): the tool
# itself, its PowerShell twin, and both installers. All four are checked: an
# installer nobody verifies is the same supply-chain hole as an unverified tool.
# Anything short of "signature verified AND every file matched" is a ✗ — a file
# that did not download is an INCOMPLETE check, never a pass. Reporting it as one
# is what this script existed to prevent (audit 2026-09-07, F04).
set -uo pipefail

# The three PT_VERIFY_* overrides exist so the regression test can point the script
# at a local fixture release signed with a throwaway key. Unset in normal use.
PUB="${PT_VERIFY_PUBKEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9DVd0vNOwa5hyr9gShaCWoNOVnUsrdHVO/WE0wCZkT}"
PRINCIPAL="releases@paranoid-tools"
# All releases live in the monorepo under per-tool prefixed tags.
BASE="${PT_VERIFY_BASE:-https://github.com/Di-kairos/paranoid-tools/releases/download}"

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
for spec in ${PT_VERIFY_SPECS-securetrash:0.5.9 vaultwatch:0.1.17 panic:0.1.19 ghostdraft:0.1.20 seedsplit:0.5.8}; do
  t="${spec%%:*}"; ver="${spec##*:}"; tag="${t}-v${ver}"; d="$W/$t"; mkdir -p "$d"
  rel="$BASE/$tag"
  printf '%-12s %-20s ' "$t" "$tag"

  # Every asset is fetched separately, so a failure names exactly WHAT did not
  # download and why (curl exit code + last stderr line) instead of a vague
  # "network?". `-S` surfaces the curl error (`-s` alone would swallow it);
  # `--retry` covers transient DNS/timeout/429/5xx.
  files=("$t" "install.sh" "$t.ps1" "install.ps1")
  fetch_fail=""
  for asset in SHA256SUMS SHA256SUMS.sig "${files[@]}"; do
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

  # (2) integrity: every file matches the signed manifest. A file the manifest
  # does not mention counts as a miss too — an unlisted file is unsigned.
  bad=""; ok=0
  for f in "${files[@]}"; do
    want="$(grep -E "  ${f//./\\.}\$" "$d/SHA256SUMS" | awk '{print $1}')"
    got="$(cd "$d" && SHA "$f" | awk '{print $1}')"
    if [[ -n "$want" && "$want" == "$got" ]]; then ok=$((ok+1)); else bad="${bad:+$bad, }$f"; fi
  done
  if [[ -z "$bad" ]]; then
    printf '\033[32m✓ подпись + %d/%d файла верны\033[0m\n' "$ok" "${#files[@]}"; PASS=$((PASS+1))
  else
    printf '\033[31m✗ НЕ совпало с манифестом: %s\033[0m\n' "$bad"; FAIL=$((FAIL+1))
  fi
done

printf '\nИтог: \033[32m%d ✓\033[0m  \033[31m%d ✗\033[0m\n' "$PASS" "$FAIL"
if [[ "$FAIL" -eq 0 && "$PASS" -gt 0 ]]; then
  echo "Все релизы подписаны корректно, и все файлы соответствуют манифесту."
elif [[ "$PASS" -eq 0 && "$FAIL" -eq 0 ]]; then
  echo "Проверять было нечего — ни один релиз не проверен."; exit 1
else
  echo "Есть проблемы — см. ✗."; exit 1
fi
