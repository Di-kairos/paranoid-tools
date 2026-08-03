# Тесты install.sh — установщик экосистемы.
# Ставит сеть/релизы в стороне: проверяются только локализация и её инварианты.
# Смысл: security-критичные ошибки установщика (провал подписи, отсутствие
# верификатора) обязаны читаться тем, кто ставит. Раньше install.sh говорил
# только по-русски, то есть для EN-пользователя отказ был без объяснения.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../install.sh"
  TMP="$(mktemp -d)"
  BINS="$(_make_fakebin)"
}

# Минимальный fakebin с fake `uname=Darwin`: install.sh отшивает не-macOS первой же
# строкой, а CI гоняет тесты на ubuntu — без подмены все прогоны падали бы на выходе 1.
_make_fakebin() {
  local bins="${TMP}/fakebin" b p
  mkdir -p "$bins"
  for b in bash sh env curl shasum mktemp dirname install chmod rm mkdir cat sed grep awk head printf uname; do
    p="$(command -v "$b" 2>/dev/null)" || continue
    ln -sf "$p" "${bins}/${b}" 2>/dev/null || true
  done
  printf '#!/usr/bin/env bash\necho Darwin\n' > "${bins}/uname"
  chmod +x "${bins}/uname"
  printf '%s' "$bins"
}

teardown() { rm -rf "$TMP"; }

@test "the installer speaks English by default" {
  run env -i PATH="$BINS:/usr/bin:/bin" HOME="$TMP" PT_DEST="$TMP/bin" \
    bash "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removing Paranoid Tools"* ]]
  [[ "$output" != *"Удаляю"* ]]
}

@test "PT_LANG=ru switches to Russian" {
  run env -i PATH="$BINS:/usr/bin:/bin" HOME="$TMP" PT_DEST="$TMP/bin" PT_LANG=ru \
    bash "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"Удаляю Paranoid Tools"* ]]
}

@test "ST_LANG=ru works too (shared across the ecosystem)" {
  run env -i PATH="$BINS:/usr/bin:/bin" HOME="$TMP" PT_DEST="$TMP/bin" ST_LANG=ru \
    bash "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"Удаляю Paranoid Tools"* ]]
}

@test "PT_LANG wins over ST_LANG" {
  run env -i PATH="$BINS:/usr/bin:/bin" HOME="$TMP" PT_DEST="$TMP/bin" ST_LANG=ru PT_LANG=en \
    bash "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removing Paranoid Tools"* ]]
}

@test "an unrecognised system locale falls back to English" {
  run env -i PATH="$BINS:/usr/bin:/bin" HOME="$TMP" PT_DEST="$TMP/bin" LANG=de_DE.UTF-8 \
    bash "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removing Paranoid Tools"* ]]
}

@test "every key exists in both locales" {
  en="$(grep -oE '^\s+en:[a-z_]+\)' "$SCRIPT" | sed 's/.*en://; s/)//' | sort)"
  ru="$(grep -oE '^\s+ru:[a-z_]+\)' "$SCRIPT" | sed 's/.*ru://; s/)//' | sort)"
  [ -n "$en" ]
  [ "$en" == "$ru" ]
}

@test "no t() branch calls itself" {
  ! grep -qE '^\s+(en|ru):([a-z_]+)\)\s+t \2\b' "$SCRIPT"
}

@test "no Russian literals left outside the t() table" {
  # Всё, что печатается пользователю, должно идти через t(); тело t() пропускаем.
  # Ловим и двойные, и одинарные кавычки: иначе printf 'Ошибка' проскочил бы.
  body="$(awk '/^t\(\) \{/,/^\}/ {next} {print}' "$SCRIPT")"
  ! printf '%s' "$body" | grep -qE "(echo|printf) [\"'][^\"']*[А-Яа-я]"
}

@test "every t() branch ends its line (a missing newline glues the next output on)" {
  # printf без \n склеил бы сообщение с последующим выводом — так уже терялся формат
  # английской диагностики о падении дочернего установщика.
  ! grep -E "^\s+(en|ru):[a-z_]+\)\s+printf" "$SCRIPT" | grep -vq '\\n'
}

@test "security-critical messages are non-empty in both locales" {
  # Берём ТОЛЬКО функцию t() — sourcing запустил бы установку целиком.
  fn="$(sed -n '/^t() {/,/^}/p' "$SCRIPT")"
  for loc in en ru; do
    for key in sig_bad sig_missing no_verifier no_verifier_warn sum_mismatch tool_fail dl_fail; do
      out="$(LOCALE="$loc" bash -c "$fn"$'\n'"LOCALE=$loc; t $key seedsplit https://example/x")"
      [ -n "$out" ]
      # ключ не должен просочиться в вывод вместо текста (fallback-ветка)
      [ "$out" != "$key" ]
    done
  done
}

@test "security-critical failures still go to stderr" {
  for key in sig_bad sig_missing no_verifier no_verifier_warn sum_mismatch tool_fail dl_fail; do
    grep -qE "^\s*t $key .*>&2" "$SCRIPT"
  done
}
