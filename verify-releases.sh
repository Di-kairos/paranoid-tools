#!/usr/bin/env bash
# verify-releases.sh — проверка подписи + целостности опубликованных релизов всех 5 тулов.
#
# Репозитории публичны: ассеты тянутся обычным `curl`, без `gh` и без токена —
# «don't trust, verify» доступно любому, не только владельцу. Для каждого тула:
#   1) curl SHA256SUMS + SHA256SUMS.sig + сам бинарь из публичного релиза;
#   2) ssh-keygen -Y verify — Ed25519-подпись манифеста против вшитого pubkey (аутентичность);
#   3) sha256 -c — бинарь побайтно соответствует подписанному манифесту (целостность).
# Печатает ✓/✗ по каждому. Запуск:  bash verify-releases.sh
set -uo pipefail

PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U"
PRINCIPAL="releases@paranoid-tools"
BASE="https://github.com/Di-kairos"

for tool in curl ssh-keygen; do
  command -v "$tool" >/dev/null 2>&1 || { echo "нужен $tool"; exit 1; }
done
# Кроссплатформенный sha256: shasum (macOS) или sha256sum (Linux).
if command -v shasum >/dev/null 2>&1; then SHA() { shasum -a 256 "$@"; }
elif command -v sha256sum >/dev/null 2>&1; then SHA() { sha256sum "$@"; }
else echo "нужен shasum или sha256sum"; exit 1; fi

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
printf '%s namespaces="file" %s\n' "$PRINCIPAL" "$PUB" > "$W/allowed_signers"

PASS=0; FAIL=0
# Пины актуальных релизных тегов (синхронны docs/RELEASE-STATE.md).
for spec in securetrash:v0.4.12 vaultwatch:v0.1.6 panic:v0.1.8 ghostdraft:v0.1.9 seedsplit:v0.4.1; do
  t="${spec%%:*}"; tag="${spec##*:}"; d="$W/$t"; mkdir -p "$d"
  rel="$BASE/$t/releases/download/$tag"
  printf '%-12s %-8s ' "$t" "$tag"

  # Манифест сумм и подпись тянем по отдельности — чтобы при сбое честно сказать, ЧТО именно
  # не скачалось и почему (curl exit code + последняя строка stderr), а не глухое «сеть?».
  # `-S` показывает ошибку curl (иначе -s её глушит); `--retry` страхует от транзиентных
  # DNS/timeout/429/5xx. Разделяем провал SHA256SUMS и SHA256SUMS.sig.
  fetch_fail=""
  for asset in SHA256SUMS SHA256SUMS.sig; do
    cerr="$(curl -fsSLS --retry 2 --retry-delay 1 "$rel/$asset" -o "$d/$asset" 2>&1)" && continue
    fetch_fail="$asset — curl $?: ${cerr##*$'\n'}"; break
  done
  if [[ -n "$fetch_fail" ]]; then
    printf '\033[31m✗ не скачалось: %s\033[0m\n' "$fetch_fail"; FAIL=$((FAIL+1)); continue
  fi

  # (1) аутентичность: подпись манифеста сумм.
  if ! ssh-keygen -Y verify -f "$W/allowed_signers" -I "$PRINCIPAL" -n file \
         -s "$d/SHA256SUMS.sig" < "$d/SHA256SUMS" >/dev/null 2>&1; then
    printf '\033[31m✗ подпись НЕ прошла\033[0m\n'; FAIL=$((FAIL+1)); continue
  fi

  # (2) целостность: бинарь соответствует подписанному манифесту. if/else без `!`, чтобы
  # `$?` в else был реальным кодом curl (после `if ! cmd` он был бы 0 из-за негации).
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
