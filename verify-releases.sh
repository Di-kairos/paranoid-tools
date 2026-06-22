#!/usr/bin/env bash
# verify-releases.sh — проверка подписи + целостности опубликованных релизов всех 5 тулов.
#
# Репозитории приватные, поэтому ассеты тянутся через `gh` (твой токен). Для каждого тула:
#   1) скачиваем SHA256SUMS + SHA256SUMS.sig из релиза;
#   2) проверяем Ed25519-подпись против вшитого pubkey (аутентичность);
#   3) (бинарь не качаем — это проверка именно подписи манифеста сумм).
# Печатает ✓/✗ по каждому. Запуск:  bash verify-releases.sh
set -uo pipefail

PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U"
PRINCIPAL="releases@paranoid-tools"

command -v gh >/dev/null 2>&1 || { echo "нужен gh CLI (brew install gh; gh auth login)"; exit 1; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
printf '%s namespaces="file" %s\n' "$PRINCIPAL" "$PUB" > "$W/allowed_signers"

PASS=0; FAIL=0
for spec in securetrash:v0.4.1 vaultwatch:v0.1.1 panic:v0.1.1 ghostdraft:v0.1.1 seedsplit:v0.3.0; do
  t="${spec%%:*}"; tag="${spec##*:}"; d="$W/$t"; mkdir -p "$d"
  gh release download "$tag" --repo "Di-kairos/$t" --pattern SHA256SUMS --pattern SHA256SUMS.sig --dir "$d" >/dev/null 2>&1
  printf '%-12s %-8s ' "$t" "$tag"
  if [[ ! -f "$d/SHA256SUMS" || ! -f "$d/SHA256SUMS.sig" ]]; then
    printf '\033[31m✗ не скачались ассеты (gh auth? сеть?)\033[0m\n'; FAIL=$((FAIL+1)); continue
  fi
  if ssh-keygen -Y verify -f "$W/allowed_signers" -I "$PRINCIPAL" -n file \
       -s "$d/SHA256SUMS.sig" < "$d/SHA256SUMS" >/dev/null 2>&1; then
    printf '\033[32m✓ подпись верна\033[0m\n'; PASS=$((PASS+1))
  else
    printf '\033[31m✗ подпись НЕ прошла\033[0m\n'; FAIL=$((FAIL+1))
  fi
done

printf '\nИтог: \033[32m%d ✓\033[0m  \033[31m%d ✗\033[0m\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] && echo "Все релизы подписаны корректно." || { echo "Есть проблемы — см. ✗."; exit 1; }
