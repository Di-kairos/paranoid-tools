# Тесты канонической библиотеки lib/common.sh (источник вендоринга экосистемы).
setup() {
  LIB="${BATS_TEST_DIRNAME}/../lib/common.sh"
}

@test "common.sh sources cleanly and is idempotent" {
  run bash -c "source '$LIB'; source '$LIB'; echo OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "info/warn/err format with markers" {
  run bash -c "source '$LIB'; info hi; warn wa; err er" 2>&1
  [[ "$output" == *"hi"* ]]
  [[ "$output" == *"wa"* ]]
  [[ "$output" == *"er"* ]]
}

@test "locale defaults to en, ru via ST_LANG" {
  run bash -c "unset ST_LANG LC_ALL LANG; source '$LIB'; echo \$ST_LOCALE"
  [[ "$output" == *"en"* ]]
  run bash -c "ST_LANG=ru_RU source '$LIB'; echo \$ST_LOCALE"
  [[ "$output" == *"ru"* ]]
}

@test "confirm passes with ST_ASSUME_YES" {
  run bash -c "ST_ASSUME_YES=1 bash -c 'source \"$LIB\"; confirm prompt && echo YES'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"YES"* ]]
}

@test "confirm accepts exactly yes, rejects others" {
  run bash -c "source '$LIB'; echo yes | confirm q && echo PASS"
  [[ "$output" == *"PASS"* ]]
  run bash -c "source '$LIB'; echo no | confirm q && echo PASS || echo FAIL"
  [[ "$output" == *"FAIL"* ]]
}

@test "is_ssd true when diskutil reports SSD Yes (mocked)" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash -c "source '$LIB'; is_ssd / && echo SSD || echo NOT"
  [[ "$output" == *"SSD"* ]]
}

@test "_disk_kind returns ssd/hdd/unknown" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash -c "source '$LIB'; _disk_kind /"
  [[ "$output" == *"ssd"* ]]
  run env PATH="${BATS_TEST_DIRNAME}/mocks-unknown:$PATH" \
    bash -c "source '$LIB'; _disk_kind /"
  [[ "$output" == *"unknown"* ]]
}

@test "filevault_on reflects fdesetup (mocked)" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash -c "source '$LIB'; filevault_on && echo ON || echo OFF"
  [[ "$output" == *"ON"* ]]
  run env PATH="${BATS_TEST_DIRNAME}/mocks-fvoff:$PATH" \
    bash -c "source '$LIB'; filevault_on && echo ON || echo OFF"
  [[ "$output" == *"OFF"* ]]
}

@test "_abspath canonicalizes trailing slash and symlinks" {
  tmp="$(mktemp -d)"; mkdir -p "$tmp/real"; ln -s "$tmp/real" "$tmp/link"
  run bash -c "source '$LIB'; _abspath '$tmp/link/'"
  [[ "$output" == *"/real"* ]]
  rm -rf "$tmp"
}

@test "_disk_kind returns hdd on spinning disk (mocked)" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks-hdd:$PATH" \
    bash -c "source '$LIB'; _disk_kind /"
  [[ "$output" == *"hdd"* ]]
}

@test "require_macos passes on Darwin, exits on non-macOS" {
  run bash -c "source '$LIB'; require_macos && echo PASS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  run env PATH="${BATS_TEST_DIRNAME}/mocks-linux:$PATH" \
    bash -c "source '$LIB'; require_macos; echo SHOULD_NOT_PRINT"
  [ "$status" -ne 0 ]
  [[ "$output" != *"SHOULD_NOT_PRINT"* ]]
  [[ "$output" == *"macOS"* ]]
}

@test "guard prevents function redefinition on re-source" {
  run bash -c "source '$LIB'; info() { echo SENTINEL; }; source '$LIB'; info x"
  [[ "$output" == *"SENTINEL"* ]]
}

@test "locale falls back to system LANG when ST_LANG unset" {
  run bash -c "unset ST_LANG LC_ALL; LANG=ru_RU.UTF-8 bash -c 'source \"$LIB\"; echo \$ST_LOCALE'"
  [[ "$output" == *"ru"* ]]
}

@test "confirm rejects on EOF (fail-closed)" {
  run bash -c "source '$LIB'; confirm q </dev/null && echo PASS || echo REJECT"
  [[ "$output" == *"REJECT"* ]]
}

@test "_fv_state is tri-state: on / off / unknown (mocked)" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash -c "source '$LIB'; _fv_state"
  [[ "$output" == "on" ]]
  run env PATH="${BATS_TEST_DIRNAME}/mocks-fvoff:$PATH" \
    bash -c "source '$LIB'; _fv_state"
  [[ "$output" == "off" ]]
  run env PATH="${BATS_TEST_DIRNAME}/mocks-fvunknown:$PATH" \
    bash -c "source '$LIB'; _fv_state"
  [[ "$output" == "unknown" ]]
}

# Отсутствующий fdesetup — это «не знаем», а не «выключен»: инструмент, который на
# пустом PATH печатает «FileVault ВЫКЛЮЧЕН», врёт пользователю о его защите.
@test "_fv_state says unknown when fdesetup is missing entirely" {
  tmp="$(mktemp -d)"   # пустой PATH; сам bash зовём по абсолютному пути
  run env PATH="$tmp" /bin/bash -c "source '$LIB'; _fv_state"
  [[ "$output" == "unknown" ]]
  rm -rf "$tmp"
}

@test "_fv_state survives pipefail (no false unknown from SIGPIPE)" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash -c "set -o pipefail; source '$LIB'; _fv_state"
  [[ "$output" == "on" ]]
}

@test "_volume_mounted sees a volume listed by mount" {
  tmp="$(mktemp -d)"; mkdir -p "$tmp/bin"
  cat >"$tmp/bin/mount" <<EOF
#!/usr/bin/env bash
echo "/dev/disk4s1 on /Volumes/SecretVault (apfs, local, nodev, nosuid, journaled, nobrowse)"
EOF
  chmod +x "$tmp/bin/mount"
  run env PATH="$tmp/bin:$PATH" bash -c "source '$LIB'; _volume_mounted /Volumes/SecretVault && echo MOUNTED || echo NO"
  [[ "$output" == *"MOUNTED"* ]]
  rm -rf "$tmp"
}

# Регресс структурного P3: остаточный каталог /Volumes/… (от прошлого монтирования или
# созданный руками) — НЕ смонтированный том. Раньше лаунчер отвечал на него «ОТКРЫТ»,
# а ghostdraft и GUI — «закрыт»: три реализации, три разных ответа.
@test "_volume_mounted refuses a stale directory that is not mounted" {
  tmp="$(mktemp -d)"; mkdir -p "$tmp/bin" "$tmp/Volumes/SecretVault"
  cat >"$tmp/bin/mount" <<'EOF'
#!/usr/bin/env bash
echo "/dev/disk1s5 on / (apfs, local, read-only, journaled)"
EOF
  chmod +x "$tmp/bin/mount"
  run env PATH="$tmp/bin:$PATH" bash -c "source '$LIB'; _volume_mounted '$tmp/Volumes/SecretVault' && echo MOUNTED || echo NO"
  [[ "$output" == *"NO"* ]]
  rm -rf "$tmp"
}

# Путь тома — данные, а не регексп: том с '.', '[' или '+' в имени не должен давать
# ложное совпадение с соседним томом.
@test "_volume_mounted treats the volume path literally" {
  tmp="$(mktemp -d)"; mkdir -p "$tmp/bin"
  cat >"$tmp/bin/mount" <<'EOF'
#!/usr/bin/env bash
echo "/dev/disk4s1 on /Volumes/AxBxC (apfs, local, nobrowse)"
EOF
  chmod +x "$tmp/bin/mount"
  run env PATH="$tmp/bin:$PATH" bash -c "source '$LIB'; _volume_mounted '/Volumes/A.B.C' && echo MOUNTED || echo NO"
  [[ "$output" == *"NO"* ]]
  rm -rf "$tmp"
}

# Кейсы Codex-ревью: подстрочный поиск считал `/Volumes/Foo` смонтированным, когда на
# деле смонтирован `/Volumes/Foo Bar` — пробел в имени тома читался как разделитель
# перед опциями. Сравниваем точку монтирования целиком.
@test "_volume_mounted does not confuse a volume with a longer-named neighbour" {
  tmp="$(mktemp -d)"; mkdir -p "$tmp/bin"
  cat >"$tmp/bin/mount" <<'EOF'
#!/usr/bin/env bash
echo "/dev/disk4s1 on /Volumes/Foo Bar (apfs, local, nobrowse)"
EOF
  chmod +x "$tmp/bin/mount"
  run env PATH="$tmp/bin:$PATH" bash -c "source '$LIB'; _volume_mounted '/Volumes/Foo' && echo MOUNTED || echo NO"
  [[ "$output" == *"NO"* ]]
  run env PATH="$tmp/bin:$PATH" bash -c "source '$LIB'; _volume_mounted '/Volumes/Foo Bar' && echo MOUNTED || echo NO"
  [[ "$output" == *"MOUNTED"* ]]
  rm -rf "$tmp"
}

# Имя тома со скобкой (macOS так разрешает коллизию имён: "Vault", "Vault (1)").
@test "_volume_mounted handles a volume name containing a parenthesis" {
  tmp="$(mktemp -d)"; mkdir -p "$tmp/bin"
  cat >"$tmp/bin/mount" <<'EOF'
#!/usr/bin/env bash
echo "/dev/disk4s1 on /Volumes/Vault (1) (apfs, local, nobrowse)"
EOF
  chmod +x "$tmp/bin/mount"
  run env PATH="$tmp/bin:$PATH" bash -c "source '$LIB'; _volume_mounted '/Volumes/Vault (1)' && echo MOUNTED || echo NO"
  [[ "$output" == *"MOUNTED"* ]]
  rm -rf "$tmp"
}

@test "_volume_mounted ignores a trailing slash in the asked path" {
  tmp="$(mktemp -d)"; mkdir -p "$tmp/bin"
  cat >"$tmp/bin/mount" <<'EOF'
#!/usr/bin/env bash
echo "/dev/disk4s1 on /Volumes/SecretVault (apfs, local, nobrowse)"
EOF
  chmod +x "$tmp/bin/mount"
  run env PATH="$tmp/bin:$PATH" bash -c "source '$LIB'; _volume_mounted '/Volumes/SecretVault/' && echo MOUNTED || echo NO"
  [[ "$output" == *"MOUNTED"* ]]
  rm -rf "$tmp"
}

# Вендорится в скрипты с `set -u`: вызов без аргумента не должен ронять хост.
@test "_volume_mounted with no argument is false, not a crash under set -u" {
  run bash -c "set -u; source '$LIB'; _volume_mounted && echo MOUNTED || echo NO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO"* ]]
}
