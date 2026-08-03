# Тесты целостности install.sh: проверяет, что установщик ставит бинарь только
# при совпадении SHA256 и fail-closed отказывается при подмене.
setup() {
  INSTALL="${BATS_TEST_DIRNAME}/../install.sh"
  WORK="$(mktemp -d)"
  FIX="${WORK}/release"        # «релиз»: securetrash + SHA256SUMS
  DEST="${WORK}/bin/securetrash"
  mkdir -p "$FIX" "${WORK}/bin"
  # Полезная нагрузка-заглушка.
  printf '#!/usr/bin/env bash\necho payload-ok\n' > "${FIX}/securetrash"
  ( cd "$FIX" && shasum -a 256 securetrash > SHA256SUMS )
}

teardown() {
  rm -rf "$WORK"
}

@test "install.sh installs binary when checksum matches" {
  # ALLOW_UNSIGNED_LEGACY=1 — тест проверяет только checksum, не подпись.
  run env ST_BASE_URL="file://${FIX}" ST_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -x "$DEST" ]
  run "$DEST"
  [[ "$output" == *"payload-ok"* ]]
}

@test "install.sh fails closed on checksum mismatch" {
  # Подменяем бинарь ПОСЛЕ генерации SHA256SUMS — хеш больше не сходится.
  printf '#!/usr/bin/env bash\necho TAMPERED\n' > "${FIX}/securetrash"
  run env ST_BASE_URL="file://${FIX}" ST_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
}

@test "install.sh aborts when SHA256SUMS is unavailable" {
  rm -f "${FIX}/SHA256SUMS"
  run env ST_BASE_URL="file://${FIX}" ST_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
}

@test "install.sh fails closed when .sig is absent (no ALLOW_UNSIGNED_LEGACY)" {
  # Нет SHA256SUMS.sig → жёсткий отказ (новые релизы всегда подписаны).
  run env ST_BASE_URL="file://${FIX}" ST_DEST="$DEST" bash "$INSTALL"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
  [[ "$output" == *"отсутствует"* ]] || [[ "$output" == *"absent"* ]] || [[ "$output" == *"прерван"* ]]
}

@test "install.sh succeeds with ALLOW_UNSIGNED_LEGACY=1 when .sig is absent" {
  run env ST_BASE_URL="file://${FIX}" ST_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -x "$DEST" ]
}

# Минимальный fakebin: ровно те внешние бинари, что нужны install.sh, + fake uname=Darwin.
# $1 = with-keygen | without-keygen — управляет наличием ssh-keygen.
_make_fakebin() {
  local mode="$1" bins="${WORK}/fakebin" b p
  mkdir -p "$bins"
  for b in bash sh env curl shasum mktemp dirname install chmod rm mkdir cat; do
    p="$(command -v "$b" 2>/dev/null)" || continue
    ln -s "$p" "${bins}/${b}" 2>/dev/null || true
  done
  if [ "$mode" = "with-keygen" ]; then
    p="$(command -v ssh-keygen 2>/dev/null)" && ln -s "$p" "${bins}/ssh-keygen"
  fi
  printf '#!/usr/bin/env bash\necho Darwin\n' > "${bins}/uname"
  chmod +x "${bins}/uname"
  printf '%s' "$bins"
}

@test "install.sh fails closed when ssh-keygen is missing (no silent hash-only)" {
  # Молчаливая деградация до hash-only маскировала бы подмену (P1-1, паритет с umbrella).
  BINS="$(_make_fakebin without-keygen)"
  run env PATH="$BINS" ST_BASE_URL="file://${FIX}" ST_DEST="$DEST" bash "$INSTALL"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
  [[ "$output" == *"ssh-keygen"* ]]
}

@test "install.sh with ALLOW_UNSIGNED_LEGACY=1 proceeds hash-only without ssh-keygen" {
  BINS="$(_make_fakebin without-keygen)"
  run env PATH="$BINS" ST_BASE_URL="file://${FIX}" ST_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -x "$DEST" ]
}
