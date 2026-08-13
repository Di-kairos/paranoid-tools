# Тесты целостности/подписи install.sh: бинарь ставится только при совпадении SHA256;
# fail-closed на подмену, отсутствие .sig и отсутствие ssh-keygen (AUDIT_2026-08-03 P1-1).
# Все тесты идут через минимальный fakebin-PATH с фейковым uname=Darwin:
# CI гоняет bats на ubuntu, а install.sh имеет честный Darwin-guard.
setup() {
  INSTALL="${BATS_TEST_DIRNAME}/../install.sh"
  WORK="$(mktemp -d)"
  FIX="${WORK}/release"        # «релиз»: panic + SHA256SUMS
  DEST="${WORK}/bin/panic"
  mkdir -p "$FIX" "${WORK}/bin"
  printf '#!/usr/bin/env bash\necho payload-ok\n' > "${FIX}/panic"
  ( cd "$FIX" && shasum -a 256 panic > SHA256SUMS )
}

teardown() {
  rm -rf "$WORK"
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

@test "install.sh installs binary when checksum matches" {
  # ALLOW_UNSIGNED_LEGACY=1 — тест проверяет только checksum, не подпись.
  BINS="$(_make_fakebin with-keygen)"
  run env PATH="$BINS" PANIC_BASE_URL="file://${FIX}" PANIC_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -x "$DEST" ]
  run "$DEST"
  [[ "$output" == *"payload-ok"* ]]
}

@test "install.sh fails closed on checksum mismatch" {
  printf '#!/usr/bin/env bash\necho TAMPERED\n' > "${FIX}/panic"
  BINS="$(_make_fakebin with-keygen)"
  run env PATH="$BINS" PANIC_BASE_URL="file://${FIX}" PANIC_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
}

@test "install.sh fails closed when .sig is absent (no ALLOW_UNSIGNED_LEGACY)" {
  BINS="$(_make_fakebin with-keygen)"
  run env PATH="$BINS" PANIC_BASE_URL="file://${FIX}" PANIC_DEST="$DEST" bash "$INSTALL"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
}

@test "install.sh fails closed when ssh-keygen is missing (no silent hash-only)" {
  # Молчаливая деградация до hash-only маскировала бы подмену (P1-1, паритет с umbrella).
  BINS="$(_make_fakebin without-keygen)"
  run env PATH="$BINS" PANIC_BASE_URL="file://${FIX}" PANIC_DEST="$DEST" bash "$INSTALL"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
  [[ "$output" == *"ssh-keygen"* ]]
}

@test "install.sh with ALLOW_UNSIGNED_LEGACY=1 proceeds hash-only without ssh-keygen" {
  BINS="$(_make_fakebin without-keygen)"
  run env PATH="$BINS" PANIC_BASE_URL="file://${FIX}" PANIC_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -x "$DEST" ]
}

@test "install.sh installs next to an existing umbrella copy instead of making a second one" {
  # Умбрелла ставит всё в ~/.local/bin; этот установщик по умолчанию — в /usr/local/bin.
  # Две копии одного тула = обновление, которое молча не доезжает: какая запустится, решает
  # порядок в PATH. Если копия из умбреллы уже есть — ставим поверх неё, а не рядом.
  BINS="$(_make_fakebin with-keygen)"
  FAKEHOME="${WORK}/home"
  mkdir -p "${FAKEHOME}/.local/bin"
  printf '#!/usr/bin/env bash\necho stale\n' > "${FAKEHOME}/.local/bin/panic"
  chmod +x "${FAKEHOME}/.local/bin/panic"
  run env PATH="$BINS" HOME="$FAKEHOME" PANIC_BASE_URL="file://${FIX}" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -eq 0 ]
  run "${FAKEHOME}/.local/bin/panic"
  [[ "$output" == *"payload-ok"* ]]
}
