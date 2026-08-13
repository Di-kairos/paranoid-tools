# Integrity/signature tests for install.sh: the binary is installed only when the SHA256
# matches; fail-closed on tampering, missing .sig, and missing ssh-keygen (AUDIT_2026-08-03 P1-1).
# All tests go through a minimal fakebin PATH with a fake uname=Darwin:
# CI runs bats on ubuntu, while install.sh has an honest Darwin guard.
setup() {
  INSTALL="${BATS_TEST_DIRNAME}/../install.sh"
  WORK="$(mktemp -d)"
  FIX="${WORK}/release"        # the "release": vaultwatch + SHA256SUMS
  DEST="${WORK}/bin/vaultwatch"
  mkdir -p "$FIX" "${WORK}/bin"
  printf '#!/usr/bin/env bash\necho payload-ok\n' > "${FIX}/vaultwatch"
  ( cd "$FIX" && shasum -a 256 vaultwatch > SHA256SUMS )
}

teardown() {
  rm -rf "$WORK"
}

# Minimal fakebin: exactly the external binaries install.sh needs, plus fake uname=Darwin.
# $1 = with-keygen | without-keygen — controls whether ssh-keygen is present.
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
  # ALLOW_UNSIGNED_LEGACY=1 — the test checks only the checksum, not the signature.
  BINS="$(_make_fakebin with-keygen)"
  run env PATH="$BINS" VW_BASE_URL="file://${FIX}" VW_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -x "$DEST" ]
  run "$DEST"
  [[ "$output" == *"payload-ok"* ]]
}

@test "install.sh fails closed on checksum mismatch" {
  printf '#!/usr/bin/env bash\necho TAMPERED\n' > "${FIX}/vaultwatch"
  BINS="$(_make_fakebin with-keygen)"
  run env PATH="$BINS" VW_BASE_URL="file://${FIX}" VW_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
}

@test "install.sh fails closed when .sig is absent (no ALLOW_UNSIGNED_LEGACY)" {
  BINS="$(_make_fakebin with-keygen)"
  run env PATH="$BINS" VW_BASE_URL="file://${FIX}" VW_DEST="$DEST" bash "$INSTALL"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
}

@test "install.sh fails closed when ssh-keygen is missing (no silent hash-only)" {
  # Silent degradation to hash-only would mask tampering (P1-1, parity with umbrella).
  BINS="$(_make_fakebin without-keygen)"
  run env PATH="$BINS" VW_BASE_URL="file://${FIX}" VW_DEST="$DEST" bash "$INSTALL"
  [ "$status" -ne 0 ]
  [ ! -e "$DEST" ]
  [[ "$output" == *"ssh-keygen"* ]]
}

@test "install.sh with ALLOW_UNSIGNED_LEGACY=1 proceeds hash-only without ssh-keygen" {
  BINS="$(_make_fakebin without-keygen)"
  run env PATH="$BINS" VW_BASE_URL="file://${FIX}" VW_DEST="$DEST" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -x "$DEST" ]
}

@test "install.sh installs next to an existing umbrella copy instead of making a second one" {
  # The umbrella installs everything into ~/.local/bin; this installer defaults to /usr/local/bin.
  # Two copies of one tool = an update that silently never lands: PATH order decides which
  # one runs. If the umbrella copy already exists — install over it, not next to it.
  BINS="$(_make_fakebin with-keygen)"
  FAKEHOME="${WORK}/home"
  mkdir -p "${FAKEHOME}/.local/bin"
  printf '#!/usr/bin/env bash\necho stale\n' > "${FAKEHOME}/.local/bin/vaultwatch"
  chmod +x "${FAKEHOME}/.local/bin/vaultwatch"
  run env PATH="$BINS" HOME="$FAKEHOME" VW_BASE_URL="file://${FIX}" ALLOW_UNSIGNED_LEGACY=1 bash "$INSTALL"
  [ "$status" -eq 0 ]
  run "${FAKEHOME}/.local/bin/vaultwatch"
  [[ "$output" == *"payload-ok"* ]]
}
