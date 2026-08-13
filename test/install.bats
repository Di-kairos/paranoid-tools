# Tests for install.sh — the ecosystem installer.
# Network/releases are left aside: only the localization and its invariants are checked.
# The point: security-critical installer errors (signature failure, missing
# verifier) must be readable by whoever installs. install.sh used to speak
# Russian only, i.e. for an EN user the refusal came with no explanation.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../install.sh"
  TMP="$(mktemp -d)"
  BINS="$(_make_fakebin)"
}

# A minimal fakebin with a fake `uname=Darwin`: install.sh rejects non-macOS on its very
# first line, and CI runs the tests on ubuntu — without the fake every run would die with exit 1.
_make_fakebin() {
  local bins="${TMP}/fakebin" b p
  mkdir -p "$bins"
  # uname is deliberately NOT in the list: a symlink to the system binary would make
  # writing the fake follow the link into /usr/bin/uname (permission denied on CI).
  for b in bash sh env curl shasum mktemp dirname install chmod rm mkdir cat sed grep awk head; do
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
  # Everything printed to the user must go through t(); the body of t() is skipped.
  # Catch both double and single quotes: otherwise a single-quoted Russian printf would slip through.
  body="$(awk '/^t\(\) \{/,/^\}/ {next} {print}' "$SCRIPT")"
  ! printf '%s' "$body" | grep -qE "(echo|printf) [\"'][^\"']*[А-Яа-я]"
}

@test "every t() branch ends its line (a missing newline glues the next output on)" {
  # printf without \n would glue the message to the following output — that is how the
  # English diagnostics about a failing child installer already lost their formatting once.
  ! grep -E "^\s+(en|ru):[a-z_]+\)\s+printf" "$SCRIPT" | grep -vq '\\n'
}

@test "security-critical messages are non-empty in both locales" {
  # Take ONLY the t() function — sourcing would run the whole install.
  fn="$(sed -n '/^t() {/,/^}/p' "$SCRIPT")"
  for loc in en ru; do
    for key in sig_bad sig_missing no_verifier no_verifier_warn sum_mismatch tool_fail dl_fail; do
      out="$(LOCALE="$loc" bash -c "$fn"$'\n'"LOCALE=$loc; t $key seedsplit https://example/x")"
      [ -n "$out" ]
      # the key must not leak into the output instead of the text (fallback branch)
      [ "$out" != "$key" ]
    done
  done
}

@test "security-critical failures still go to stderr" {
  for key in sig_bad sig_missing no_verifier no_verifier_warn sum_mismatch tool_fail dl_fail; do
    grep -qE "^\s*t $key .*>&2" "$SCRIPT"
  done
}

@test "PT_DEV=1 prints the unverified-worktree banner and copies the local file" {
  # Fake tool source in the layout install.sh expects: $ROOT/<tool>/<tool>.
  root="$TMP/repo"; mkdir -p "$root/securetrash"
  cp "$SCRIPT" "$root/install.sh"
  printf '#!/usr/bin/env bash\necho launcher\n' > "$root/paranoid"
  printf '#!/usr/bin/env bash\necho fake\n' > "$root/securetrash/securetrash"
  # curl stub that always fails: the other four tools must fail fast offline.
  # (rm first: the fakebin entry is a symlink to the system curl — writing
  # through it would chase the link into /usr/bin.)
  rm -f "$BINS/curl"
  printf '#!/usr/bin/env bash\nexit 22\n' > "$BINS/curl"; chmod +x "$BINS/curl"
  run env -i PATH="$BINS:/usr/bin:/bin" HOME="$TMP" PT_DEST="$TMP/bin" \
    PT_DEV=1 PT_ALLOW_PARTIAL=1 bash "$root/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIED WORKTREE INSTALL"* ]]
  [[ "$output" == *"from the working copy"* ]]
  [ -x "$TMP/bin/securetrash" ]
}

@test "without PT_DEV a local tool file is ignored in favor of the signed path" {
  root="$TMP/repo2"; mkdir -p "$root/securetrash"
  cp "$SCRIPT" "$root/install.sh"
  printf '#!/usr/bin/env bash\necho launcher\n' > "$root/paranoid"
  printf '#!/usr/bin/env bash\necho fake\n' > "$root/securetrash/securetrash"
  rm -f "$BINS/curl"
  printf '#!/usr/bin/env bash\nexit 22\n' > "$BINS/curl"; chmod +x "$BINS/curl"
  run env -i PATH="$BINS:/usr/bin:/bin" HOME="$TMP" PT_DEST="$TMP/bin2" \
    PT_ALLOW_PARTIAL=1 bash "$root/install.sh"
  # The local copy must NOT be installed; the network path fails (stub curl),
  # so securetrash is simply absent — that is the honest outcome.
  [[ "$output" != *"from the working copy"* ]]
  [[ "$output" != *"UNVERIFIED WORKTREE INSTALL"* ]]
  [ ! -e "$TMP/bin2/securetrash" ]
}
