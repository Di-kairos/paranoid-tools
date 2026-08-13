# Tests for paranoid — the interactive ecosystem launcher (pure Bash).
# Technique: the five ecosystem CLIs + fdesetup are replaced by stubs in $STUBS on PATH;
# each stub appends "<name> $@" to $LOG. That is how a test verifies which tool was
# called and with which arguments. A missing tool = simply don't create its stub.
# The interactive loop is driven by feeding menu items into stdin (each action
# pauses in _pause — hence the extra empty line — before returning to the menu; the
# final '0' exits).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../paranoid"
  TMP="$(mktemp -d)"
  STUBS="$TMP/bin"
  LOG="$TMP/calls.log"
  mkdir -p "$STUBS"
  : >"$LOG"

  # Base utilities (coreutils + bash itself) the script relies on.
  # PATH = stubs only + the system paths with those utilities, so that the REAL
  # securetrash/panic/… (if installed) cannot intercept the call.
  _ESSENTIAL_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  # The five ecosystem CLIs + fdesetup. All five are installed by default; individual
  # tests delete the relevant stub to model "not installed".
  for t in securetrash vaultwatch panic seedsplit ghostdraft fdesetup; do
    _make_stub "$t"
  done

  # The mount table is under test control: "vault open" = the volume appears in `mount`
  # output, not "the directory exists" (see _volume_mounted in the launcher).
  # The root entry is always there — empty `mount` output would mean "could not read it".
  MOUNTS="$TMP/mounts"
  printf '/dev/disk1s5 on / (apfs, local, read-only, journaled)\n' >"$MOUNTS"
  cat >"$STUBS/mount" <<EOF
#!/usr/bin/env bash
cat "$MOUNTS"
EOF
  chmod +x "$STUBS/mount"

  unset ST_LANG ST_LOCALE
  export ST_LOCALE=en   # deterministic chrome by default (en)
}

# Declare a volume as mounted for the `mount` stub.
_mark_mounted() {
  printf '/dev/disk9s1 on %s (apfs, local, nodev, nosuid, journaled, nobrowse)\n' "$1" >>"$MOUNTS"
}

# Break reading the mount table (mount returns a non-zero code).
_break_mount() {
  printf '#!/usr/bin/env bash\nexit 1\n' >"$STUBS/mount"
  chmod +x "$STUBS/mount"
}

teardown() { rm -rf "$TMP"; }

# Create an executable stub that appends "<name> $@" to $LOG.
# Special cases: vaultwatch status → idle (no "session:"), fdesetup status → On.
_make_stub() {
  local name="$1"
  cat >"$STUBS/$name" <<EOF
#!/usr/bin/env bash
printf '$name %s\n' "\$*" >>"$LOG"
case "\${1:-}" in version|--version|-v) echo "$name \${STUB_VER:-0.0.1}"; exit 0 ;; esac
case "$name:\${1:-}" in
  fdesetup:status) echo "FileVault is On." ;;
  vaultwatch:status) : ;;  # empty → _status_vaultwatch = idle
esac
exit 0
EOF
  chmod +x "$STUBS/$name"
}

# Run the launcher with the substituted PATH and the given stdin.
# Usage: run_paranoid "<stdin>" [extra env assignments...]
run_paranoid() {
  local input="$1"; shift
  run env -i PATH="$STUBS:$_ESSENTIAL_PATH" HOME="$HOME" \
    ST_LOCALE="${ST_LOCALE:-en}" "$@" \
    bash -c "printf '%s' \"\$0\" | bash '$SCRIPT'" "$input"
}

# --- subcommands (do not start the loop) ---

@test "version prints 'paranoid 0.1.0'" {
  run env PATH="$STUBS:$_ESSENTIAL_PATH" bash "$SCRIPT" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"paranoid 0.1.0"* ]]
}

@test "help prints usage and exits zero" {
  run env PATH="$STUBS:$_ESSENTIAL_PATH" bash "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"interactive"* ]]
}

@test "unknown arg exits 1 with usage on stderr" {
  # Capture ONLY stderr (the usage + the error message go to stderr):
  # stdout is silenced, stderr → file.
  run env PATH="$STUBS:$_ESSENTIAL_PATH" bash -c "bash '$SCRIPT' bogus 2>'$TMP/err' >/dev/null"
  [ "$status" -eq 1 ]
  grep -q "Usage:" "$TMP/err"
  grep -q "Unknown command" "$TMP/err"
}

@test "sourcing the script does not launch the loop" {
  run env PATH="$STUBS:$_ESSENTIAL_PATH" bash -c "source '$SCRIPT'; echo SOURCED_OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED_OK"* ]]
  [[ "$output" != *"Choose"* ]]
}

# --- status (item 1) ---

@test "status runs 'securetrash check' and 'vaultwatch status'" {
  run_paranoid $'1\n\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "securetrash check" "$LOG"
  grep -qx "vaultwatch status" "$LOG"
}

# --- panic (item 2) ---

@test "panic dispatches 'panic now --hard' instantly (no confirm)" {
  run_paranoid $'2\n\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "panic now --hard" "$LOG"
}

@test "panic asks for NO confirmation (speed is the point)" {
  run_paranoid $'2\n\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Run panic now"* ]]
  [[ "$output" != *"type yes"* ]]
  [[ "$output" != *"--hard)?"* ]]
}

@test "panic item greys out when panic is not installed" {
  rm -f "$STUBS/panic"
  run_paranoid $'0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"PANIC NOW"*"(not installed)"* ]]
}

@test "panic absent: choosing it shows hint, runs nothing, no confirm" {
  rm -f "$STUBS/panic"
  run_paranoid $'2\n\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "^panic " "$LOG"
  [[ "$output" == *"github.com/Di-kairos/paranoid-tools"* ]]
}

# --- vault: submenu (item 3 → ...) ---

@test "vault submenu: no container -> dispatches 'securetrash vault create'" {
  # input after '1': empty size (default) + empty pause
  run_paranoid $'3\n1\n\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault create" "$LOG"
  ! grep -q "vault open" "$LOG"
  ! grep -q "vault close" "$LOG"
}

@test "vault create passes a chosen size cap to securetrash" {
  run_paranoid $'3\n1\n5g\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault create 5g" "$LOG"
}

@test "vault create with an invalid size cancels (no create dispatched)" {
  run_paranoid $'3\n1\nbig\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  ! grep -q "vault create" "$LOG"
  [[ "$output" == *"Invalid size"* ]]
}

@test "vault submenu: closed -> dispatches 'securetrash vault open'" {
  touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n1\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault open" "$LOG"
  ! grep -q "vault close" "$LOG"
  ! grep -q "vault create" "$LOG"
}

@test "vault submenu: open -> dispatches 'securetrash vault close'" {
  mkdir -p "$TMP/vault"; _mark_mounted "$TMP/vault"
  run_paranoid $'3\n1\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault close" "$LOG"
  ! grep -q "vault open" "$LOG"
  ! grep -q "vault create" "$LOG"
}

# --- vault: empty = vault reset (submenu 3 → 2) ---

@test "vault submenu 2 dispatches 'securetrash vault reset' when a vault exists" {
  touch "$TMP/container.sparsebundle"
  # after '2': empty size (default) + empty pause
  run_paranoid $'3\n2\n\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault reset" "$LOG"
}

@test "vault empty warns it crypto-shreds and recreates" {
  touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n2\n\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  [[ "$output" == *"crypto-shred"* ]]
}

@test "vault empty is a no-op when there is no vault (no dead-end)" {
  run_paranoid $'3\n2\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  ! grep -q "vault reset" "$LOG"
}

# --- vault: destroy (submenu 3 → 3) ---

@test "vault submenu 3 dispatches 'securetrash vault destroy' when a vault exists" {
  touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n3\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  grep -qx "securetrash vault destroy" "$LOG"
}

@test "vault destroy warns before destroy (irreversible)" {
  touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n3\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  [[ "$output" == *"permanently"* ]]
}

@test "vault destroy is a no-op when there is no vault (no dead-end)" {
  run_paranoid $'3\n3\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/nope" ST_VAULT_PATH="$TMP/no-container-$RANDOM"
  [ "$status" -eq 0 ]
  ! grep -q "vault destroy" "$LOG"
}

# --- secrets: submenu (item 5 → ...) ---

@test "secrets submenu 1 dispatches 'seedsplit split'" {
  run_paranoid $'5\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "seedsplit split" "$LOG"
}

@test "secrets submenu 2 dispatches 'seedsplit combine'" {
  run_paranoid $'5\n2\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "seedsplit combine" "$LOG"
}

# --- notepad: submenu (item 4 → ...) ---

@test "notepad submenu 1 (unified note) dispatches 'ghostdraft new --clipboard'" {
  # The note flow is collapsed: a single item writes/edits/copies (the copy auto-wipes in ~20s).
  run_paranoid $'4\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "ghostdraft new --clipboard" "$LOG"
}

@test "notepad submenu 1 warns the clipboard auto-wipes" {
  run_paranoid $'4\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"clipboard"* ]]
  [[ "$output" == *"20s"* ]]
}

@test "notepad submenu 2 dispatches 'ghostdraft pipe'" {
  run_paranoid $'4\n2\n\n0\n0\n'
  [ "$status" -eq 0 ]
  grep -qx "ghostdraft pipe" "$LOG"
}

@test "notepad submenu has no third item (collapsed to note + show-clipboard)" {
  # Item 3 (the old new+clipboard) was removed — '3' is now invalid and dispatches nothing.
  run_paranoid $'4\n3\n\n0\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "^ghostdraft" "$LOG"
}

# --- vault: vaultwatch start (submenu 3 → 4) ---

@test "watch with TTL dispatches 'vaultwatch start --ttl <X> <vault>'" {
  run_paranoid $'3\n4\n30m\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "vaultwatch start --ttl 30m $TMP/vault" "$LOG"
}

@test "watch without TTL dispatches 'vaultwatch start <vault>'" {
  run_paranoid $'3\n4\n\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "vaultwatch start $TMP/vault" "$LOG"
}

# Regression: an active session must show as "active", not "idle".
# The bug: `vaultwatch status | grep -q` under `set -o pipefail` — grep -q closes the pipe
# on the first line, vaultwatch catches SIGPIPE (141), pipefail turns the pipeline
# non-zero → a false "idle". A stub with session: on the first line + a tail bigger than the
# pipe buffer (~64KB) makes the SIGPIPE deterministic; a small output would fit in the buffer.
@test "active vaultwatch session shows 'active' under pipefail (no SIGPIPE false-idle)" {
  cat >"$STUBS/vaultwatch" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "status" ]; then
  echo "session: /tmp/vault (running 5m)"
  for i in $(seq 1 5000); do echo "  detail line $i padding padding padding padding"; done
fi
exit 0
STUB
  chmod +x "$STUBS/vaultwatch"
  run_paranoid $'0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"active"* ]]
  [[ "$output" != *"idle"* ]]
}

# --- missing tool ---

@test "missing tool shows '(not installed)' inside its submenu" {
  rm -f "$STUBS/seedsplit"
  run_paranoid $'5\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"(not installed)"* ]]
}

@test "missing tool action invokes nothing (log stays empty for it)" {
  rm -f "$STUBS/seedsplit"
  run_paranoid $'5\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "^seedsplit" "$LOG"
  # And the install hint (the repo) is shown.
  [[ "$output" == *"github.com/Di-kairos/paranoid-tools"* ]]
}

# --- top-level: the three submenu groups ---

@test "top level shows the three submenu groups" {
  run_paranoid $'0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Vault ▸"* ]]
  [[ "$output" == *"Notepad ▸"* ]]
  [[ "$output" == *"Secrets ▸"* ]]
}

@test "submenu 0 returns to the top menu (back navigation)" {
  # Enter Vault, go back (0), then quit (0). The dashboard is drawn twice → we see Status.
  run_paranoid $'3\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Vault — encrypted container"* ]]
  [[ "$output" == *"Status — full read-only check"* ]]
}

# --- i18n chrome ---

@test "en chrome shows 'Status — full read-only check'" {
  ST_LOCALE=en run_paranoid $'0\n' ST_LOCALE=en
  [ "$status" -eq 0 ]
  [[ "$output" == *"Status — full read-only check"* ]]
}

@test "ru chrome shows Russian menu string" {
  run_paranoid $'0\n' ST_LANG=ru ST_LOCALE=ru
  [ "$status" -eq 0 ]
  [[ "$output" == *"Статус — полная проверка"* ]]
}

# --- quit ---

@test "quit via 0 exits cleanly" {
  run_paranoid $'0\n'
  [ "$status" -eq 0 ]
}

@test "quit via q exits cleanly" {
  run_paranoid $'q\n'
  [ "$status" -eq 0 ]
}

@test "quit via Q exits cleanly" {
  run_paranoid $'Q\n'
  [ "$status" -eq 0 ]
}

# --- UX: hints and dead-ends ---

@test "split leaves the input prompt to seedsplit itself" {
  # seedsplit prompts for the secret itself and reads it without echo; the launcher dropped
  # its own prompt, otherwise the user got two different instructions in a row (AUDIT_2026-08-03 P2-1).
  run_paranoid $'5\n1\n\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Paste the secret"* ]]
}

@test "combine prints a one-per-line paste prompt" {
  run_paranoid $'5\n2\n\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"one per line"* ]]
}

@test "ghost new shows which editor opens and how to exit" {
  EDITOR=nano run_paranoid $'4\n1\n\n0\n0\n' EDITOR=nano
  [ "$status" -eq 0 ]
  [[ "$output" == *"nano"* ]]
  [[ "$output" == *"Ctrl-X"* ]]
}

@test "ghost new (vim) hint shows how to DISCARD, not just save" {
  # Live test: a novice got stuck in vim, saw only how to save (:wq), wanted to exit WITHOUT
  # saving. The hint must give both paths by keyboard (F-keys do not get through in Warp).
  EDITOR=vim run_paranoid $'4\n1\n\n0\n0\n' EDITOR=vim
  [ "$status" -eq 0 ]
  [[ "$output" == *"vim"* ]]
  [[ "$output" == *"ZQ"* ]] || [[ "$output" == *":q!"* ]]   # exit without saving
  [[ "$output" == *"ZZ"* ]] || [[ "$output" == *":wq"* ]]   # save and exit
  [[ "$output" == *"Esc"* ]]
}

@test "ghost pipe shows a hint (does not silently wait on stdin)" {
  run_paranoid $'4\n2\n\n0\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"clipboard"* ]]
}

@test "invalid TTL is rejected and does not start vaultwatch" {
  run_paranoid $'3\n4\n30min\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Invalid format"* ]]
  ! grep -q "vaultwatch start" "$LOG"
}

@test "vault submenu 4 stops the watch when a session is active" {
  cat >"$STUBS/vaultwatch" <<EOF
#!/usr/bin/env bash
printf 'vaultwatch %s\n' "\$*" >>"$LOG"
[ "\${1:-}" = "status" ] && echo "session: active"
exit 0
EOF
  chmod +x "$STUBS/vaultwatch"
  run_paranoid $'3\n4\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault"
  [ "$status" -eq 0 ]
  grep -qx "vaultwatch stop $TMP/vault" "$LOG"
}

# --- opt-in update check (PARANOID_UPDATE_CHECK) ---

@test "update check stays silent when PARANOID_UPDATE_CHECK is unset (privacy default)" {
  printf 'ghostdraft=v9.9.9\n' >"$TMP/feed"   # a newer release exists, but the check is off
  run_paranoid $'0\n' PARANOID_UPDATE_FEED="$TMP/feed" STUB_VER=0.1.0
  [ "$status" -eq 0 ]
  [[ "$output" != *"update available"* ]]
  [[ "$output" != *"→"* ]]
}

@test "update check shows a newer release when enabled and one is available" {
  printf 'ghostdraft=v0.1.9\n' >"$TMP/feed"
  run_paranoid $'0\n' PARANOID_UPDATE_CHECK=1 PARANOID_UPDATE_FEED="$TMP/feed" STUB_VER=0.1.7
  [ "$status" -eq 0 ]
  [[ "$output" == *"update available"* ]]
  [[ "$output" == *"ghostdraft 0.1.7→0.1.9"* ]]
}

@test "update check is silent when the installed version is already latest" {
  printf 'ghostdraft=v0.1.9\n' >"$TMP/feed"
  run_paranoid $'0\n' PARANOID_UPDATE_CHECK=1 PARANOID_UPDATE_FEED="$TMP/feed" STUB_VER=0.1.9
  [ "$status" -eq 0 ]
  [[ "$output" != *"update available"* ]]
}

@test "update check does not flag when installed is newer than the feed (no false positive)" {
  printf 'ghostdraft=v0.1.9\n' >"$TMP/feed"
  run_paranoid $'0\n' PARANOID_UPDATE_CHECK=1 PARANOID_UPDATE_FEED="$TMP/feed" STUB_VER=0.2.0
  [ "$status" -eq 0 ]
  [[ "$output" != *"update available"* ]]
}

# --- the Update menu item: re-running the installer from the clone ---
# The launcher deliberately has no download logic of its own: update = install.sh from the clone.
# The tests go through run_paranoid (env -i): otherwise XDG_DATA_HOME/PARANOID_SRC from the
# developer's environment would leak in, the launcher would pick the REAL clone and the test
# would run the live installer while still staying "green".

# A directory that looks like our clone: install.sh + paranoid next to it.
_make_fake_clone() {
  local dir="$1" marker="$2"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\necho "%s" >> "%s"\nexit %s\n' "$marker" "$LOG" "${3:-0}" > "$dir/install.sh"
  chmod +x "$dir/install.sh"
  : > "$dir/paranoid"
}

@test "menu shows the Update item" {
  run_paranoid $'0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"6)"* ]]
  [[ "$output" == *"Update"* ]]
}

@test "update runs install.sh from the recorded source dir and shows which one" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  grep -q "INSTALLER RAN" "$LOG"
  # the user must SEE which directory's code is about to run
  [[ "$output" == *"$TMP/clone"* ]]
}

@test "update does nothing without an explicit yes" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nn\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  ! grep -q "INSTALLER RAN" "$LOG"
  [[ "$output" == *"Cancelled"* ]]
}

@test "update says plainly when no installer can be found" {
  cp "$SCRIPT" "$TMP/paranoid-standalone"
  run env -i PATH="$STUBS:$_ESSENTIAL_PATH" HOME="$TMP" ST_LOCALE=en \
    bash -c "printf '%s' \"\$0\" | bash '$TMP/paranoid-standalone'" $'6\n\n0\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cannot find the installer"* ]]
}

@test "PARANOID_SRC overrides the recorded source dir" {
  _make_fake_clone "$TMP/other" "OTHER RAN"
  _make_fake_clone "$TMP/clone" "RECORDED RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP" PARANOID_SRC="$TMP/other"
  [ "$status" -eq 0 ]
  grep -q "OTHER RAN" "$LOG"
  ! grep -q "RECORDED RAN" "$LOG"
}

@test "a CRLF state file still resolves to the recorded dir" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\r\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  grep -q "INSTALLER RAN" "$LOG"
}

@test "a directory that is not our clone is not executed" {
  # install.sh alone, no paranoid next to it — a foreign directory must not be run
  mkdir -p "$TMP/notclone"
  printf '#!/usr/bin/env bash\necho "STRANGER RAN" >> "%s"\n' "$LOG" > "$TMP/notclone/install.sh"
  chmod +x "$TMP/notclone/install.sh"
  cp "$SCRIPT" "$TMP/paranoid-standalone"
  run env -i PATH="$STUBS:$_ESSENTIAL_PATH" HOME="$TMP" ST_LOCALE=en PARANOID_SRC="$TMP/notclone" \
    bash -c "printf '%s' \"\$0\" | bash '$TMP/paranoid-standalone'" $'6\n\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "STRANGER RAN" "$LOG"
  [[ "$output" == *"Cannot find the installer"* ]]
}

@test "update pulls first when the source really is a git clone" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  # the git stub writes to the log so we can see pull was called at all
  printf '#!/usr/bin/env bash\necho "git $*" >> "%s"\nexit 0\n' "$LOG" > "$STUBS/git"
  chmod +x "$STUBS/git"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  grep -q "pull --ff-only" "$LOG"
  grep -q "INSTALLER RAN" "$LOG"
}

@test "a failed pull does not stop the reinstall and is reported" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  printf '#!/usr/bin/env bash\ncase "$*" in *rev-parse*) exit 0;; *pull*) exit 1;; esac\nexit 0\n' > "$STUBS/git"
  chmod +x "$STUBS/git"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"did not succeed"* ]]
  grep -q "INSTALLER RAN" "$LOG"
}

@test "update clears the cached update-available banner after a successful install" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools" "$TMP/.cache/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  echo "securetrash 0.1.0->9.9.9" > "$TMP/.cache/paranoid-tools/update-check"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/.cache/paranoid-tools/update-check" ]
}

@test "a failing installer is reported and the stale banner is kept" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN" 1
  mkdir -p "$TMP/.local/share/paranoid-tools" "$TMP/.cache/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  echo "securetrash 0.1.0->9.9.9" > "$TMP/.cache/paranoid-tools/update-check"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exited with an error"* ]]
  # a failed install must not hide the "update available" banner
  [ -f "$TMP/.cache/paranoid-tools/update-check" ]
}

@test "a symlinked install.sh is not executed" {
  # -f follows the link: a swapped target would pass the check while the user kept seeing
  # the old trusted path. Symlinks are not accepted.
  _make_fake_clone "$TMP/evil" "EVIL RAN"
  mkdir -p "$TMP/clone"
  ln -s "$TMP/evil/install.sh" "$TMP/clone/install.sh"
  : > "$TMP/clone/paranoid"
  cp "$SCRIPT" "$TMP/paranoid-standalone"
  run env -i PATH="$STUBS:$_ESSENTIAL_PATH" HOME="$TMP" ST_LOCALE=en PARANOID_SRC="$TMP/clone" \
    bash -c "printf '%s' \"\$0\" | bash '$TMP/paranoid-standalone'" $'6\n\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "EVIL RAN" "$LOG"
  [[ "$output" == *"Cannot find the installer"* ]]
}

@test "a trailing space in the state file is not silently trimmed into another dir" {
  # /tmp/x and '/tmp/x ' are different directories; a blanket trim would swap one for the other.
  _make_fake_clone "$TMP/other" "OTHER RAN"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s \n' "$TMP/other" > "$TMP/.local/share/paranoid-tools/source"
  cp "$SCRIPT" "$TMP/paranoid-standalone"
  run env -i PATH="$STUBS:$_ESSENTIAL_PATH" HOME="$TMP" ST_LOCALE=en \
    bash -c "printf '%s' \"\$0\" | bash '$TMP/paranoid-standalone'" $'6\n\n0\n'
  [ "$status" -eq 0 ]
  ! grep -q "OTHER RAN" "$LOG"
}

@test "a failed pull is still called out after a successful install" {
  _make_fake_clone "$TMP/clone" "INSTALLER RAN"
  printf '#!/usr/bin/env bash\ncase "$*" in *rev-parse*) exit 0;; *pull*) exit 1;; esac\nexit 0\n' > "$STUBS/git"
  chmod +x "$STUBS/git"
  mkdir -p "$TMP/.local/share/paranoid-tools"
  printf '%s\n' "$TMP/clone" > "$TMP/.local/share/paranoid-tools/source"
  run_paranoid $'6\nyes\n\n0\n' HOME="$TMP"
  [ "$status" -eq 0 ]
  grep -q "INSTALLER RAN" "$LOG"
  # installer success must not be passed off as "everything is fresh"
  [[ "$output" == *"clone itself was not updated"* ]]
}

# Structural P3: a leftover /Volumes/… directory is NOT an open vault. The launcher used to
# treat "directory exists" = "mounted" and showed "OPEN · at risk", while ghostdraft and the
# GUI honestly answered "closed" for the very same path: three detection implementations,
# three different answers. Now there is one answer — the mount table.
@test "a leftover volume directory is not reported as an open vault" {
  mkdir -p "$TMP/vault"; touch "$TMP/container.sparsebundle"   # the directory exists, mount does not list it
  run_paranoid $'0\n' ST_VAULT_VOLUME="$TMP/vault" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  [[ "$output" != *"OPEN"* ]]
  [[ "$output" == *"closed"* ]]
}

# And the converse: a volume in the mount table is an open vault, even if the container is
# not in its usual place (the vault could have been opened with a custom path).
@test "a mounted volume is reported as an open vault" {
  mkdir -p "$TMP/vault"; _mark_mounted "$TMP/vault"
  run_paranoid $'0\n' ST_VAULT_VOLUME="$TMP/vault" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OPEN"* ]]
}

# An unreadable mount table is not "closed". A green "closed" over an actually open vault
# is more dangerous than an honest "could not determine": the user would assume the data
# is already encrypted.
@test "an unreadable mount table is reported as unknown, not as closed" {
  _break_mount   # mount fails → _volume_mounted returns code 2
  mkdir -p "$TMP/vault"; touch "$TMP/container.sparsebundle"
  run_paranoid $'0\n' ST_VAULT_VOLUME="$TMP/vault" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not be determined"* ]]
  [[ "$output" != *"OPEN"* ]]
}

# And the launcher does not guess with an action: submenu item 1 dispatches neither open nor close.
@test "the vault submenu refuses to guess while the state is unknown" {
  _break_mount
  mkdir -p "$TMP/vault"; touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n1\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  ! grep -q "vault open" "$LOG"
  ! grep -q "vault close" "$LOG"
  [[ "$output" == *"Refusing to guess"* ]]
}

# Codex review: unknown must not leak into the IRREVERSIBLE submenu actions.
@test "empty and destroy refuse to run while the vault state is unknown" {
  _break_mount
  mkdir -p "$TMP/vault"; touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n2\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  ! grep -q "vault reset" "$LOG"
  run_paranoid $'3\n3\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  ! grep -q "vault destroy" "$LOG"
}

# Watching a volume whose mount state is unknown is a session around empty space.
@test "watch refuses to start while the vault state is unknown" {
  _break_mount
  mkdir -p "$TMP/vault"; touch "$TMP/container.sparsebundle"
  run_paranoid $'3\n4\n\n0\n0\n' ST_VAULT_VOLUME="$TMP/vault" ST_VAULT_PATH="$TMP/container.sparsebundle"
  [ "$status" -eq 0 ]
  ! grep -q "vaultwatch start" "$LOG"
}
