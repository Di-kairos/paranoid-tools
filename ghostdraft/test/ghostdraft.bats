# Tests for ghostdraft (pack 1: scaffold — vendoring + skeleton + dispatcher).
setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../ghostdraft"
  # A uname stub (-> Darwin) goes on PATH: cmd_new calls require_macos, otherwise
  # the tests would fail on Linux CI. The tests never touch macOS primitives (hdiutil/diskutil).
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  export PATH="$STUBS:$PATH"
  # The bats runner is not a TTY; the editor is mocked in tests (non-interactive), so we bypass
  # the interactive-terminal guard in cmd_new. The test for that guard unsets the variable explicitly.
  export GD_ASSUME_TTY=1
}

@test "new refuses in a non-interactive terminal instead of hanging the editor" {
  work="$(mktemp -d)"; bin="$work/bin"; mkdir -p "$bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/vim"; chmod +x "$bin/vim"   # stub so RED doesn't hang on real vim
  run env -u EDITOR -u GD_ASSUME_TTY PATH="$bin:$STUBS:$PATH" GHOSTDRAFT_DIR="$work/d" bash "$SCRIPT" new </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"interactive terminal"* ]] || [[ "$output" == *"интерактивный"* ]]
  rm -rf "$work"
}

@test "new warns about Warp key/focus interception when TERM_PROGRAM=WarpTerminal" {
  work="$(mktemp -d)"; ed="$work/ed"; _fake_editor "$ed"
  export GD_EDITED_PATH="$work/edited" GD_EDITED_MODE="$work/mode"
  run env TERM_PROGRAM=WarpTerminal GHOSTDRAFT_DIR="$work/draftdir" EDITOR="$ed" bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  [[ "$output" == *"Warp"* ]]
  [[ "$output" == *"Esc"* ]]
  rm -rf "$work"
}

@test "new does NOT print the Warp hint under a normal terminal" {
  work="$(mktemp -d)"; ed="$work/ed"; _fake_editor "$ed"
  export GD_EDITED_PATH="$work/edited" GD_EDITED_MODE="$work/mode"
  run env -u TERM_PROGRAM GHOSTDRAFT_DIR="$work/draftdir" EDITOR="$ed" bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  [[ "$output" != *"Use agent"* ]]
  rm -rf "$work"
}

@test "version prints semver" {
  run bash "$SCRIPT" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghostdraft"* ]]
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "--version flag prints version" {
  run bash "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghostdraft"* ]]
}

@test "--yes is accepted anywhere in the args and does not become a command" {
  # The securetrash contract: the flag is stripped, remaining args keep their order.
  run bash "$SCRIPT" --yes version
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghostdraft"* ]]
  run bash "$SCRIPT" version --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghostdraft"* ]]
}

@test "--yes alone is not treated as a command (usage, non-zero)" {
  run bash "$SCRIPT" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" != *"Unknown command"* ]]
}

@test "usage documents the --yes flag" {
  run bash "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--yes"* ]]
}

@test "-v flag prints version" {
  run bash "$SCRIPT" -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghostdraft"* ]]
}

@test "--help flag prints usage" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "-h flag prints usage" {
  run bash "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "no args prints usage and exits non-zero" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "help prints usage and exits zero" {
  run bash "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown command exits non-zero" {
  run bash "$SCRIPT" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "vendored common is present and provides primitives" {
  run bash -c "source '$SCRIPT' 2>/dev/null; type info >/dev/null && type confirm >/dev/null && type require_macos >/dev/null && echo OK"
  [[ "$output" == *"OK"* ]]
}

@test "sourcing the script does not run the dispatcher" {
  run bash -c "source '$SCRIPT'; echo SOURCED_OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED_OK"* ]]
  [[ "$output" != *"Usage:"* ]]
}

@test "vendor --check passes (no drift)" {
  run bash "${BATS_TEST_DIRNAME}/../tools/vendor-common.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"синхронен"* ]] || [[ "$output" == *"sync"* ]]
}

# Fake editor: writes a known marker into the given file and records the path.
# Via it we test the `new` lifecycle headless (no TTY, no real RAM disk).
_fake_editor() {
  local ed="$1"
  cat > "$ed" <<'SH'
#!/usr/bin/env bash
printf 'DRAFT-CONTENT' > "$1"
printf '%s\n' "$1" > "${GD_EDITED_PATH:?}"
# permissions: GNU (Linux CI) stat -c first; BSD (macOS) -c fails -> fallback -f.
  # The reverse order broke: GNU `stat -f` does NOT fail (--file-system), it yields garbage.
{ stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; } > "${GD_EDITED_MODE:?}"
SH
  chmod +x "$ed"
}

@test "new opens editor on a draft inside GHOSTDRAFT_DIR" {
  work="$(mktemp -d)"; ed="$work/ed"; _fake_editor "$ed"
  export GD_EDITED_PATH="$work/edited" GD_EDITED_MODE="$work/mode"
  run env GHOSTDRAFT_DIR="$work/draftdir" EDITOR="$ed" bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  edited="$(cat "$work/edited")"
  [[ "$edited" == "$work/draftdir/"* ]]
  rm -rf "$work"
}

@test "$EDITOR with a space in its path still opens (not split into words)" {
  # On macOS a path with a space is normal (`/Applications/Visual Studio Code.app/…/code`).
  # An $EDITOR split into words never launched at all: nothing could open the draft.
  work="$(mktemp -d)"; mkdir -p "$work/my editors"; ed="$work/my editors/ed"
  _fake_editor "$ed"
  export GD_EDITED_PATH="$work/edited" GD_EDITED_MODE="$work/mode"
  run env GHOSTDRAFT_DIR="$work/draftdir" EDITOR="$ed" bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  edited="$(cat "$work/edited")"
  [[ "$edited" == "$work/draftdir/"* ]]
  rm -rf "$work"
}

@test "new shreds the draft file on exit (nothing left)" {
  work="$(mktemp -d)"; ed="$work/ed"; _fake_editor "$ed"
  export GD_EDITED_PATH="$work/edited" GD_EDITED_MODE="$work/mode"
  run env GHOSTDRAFT_DIR="$work/draftdir" EDITOR="$ed" bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  edited="$(cat "$work/edited")"
  [ ! -e "$edited" ]
  run bash -c "grep -rl 'DRAFT-CONTENT' '$work/draftdir' 2>/dev/null"
  [ -z "$output" ]
  rm -rf "$work"
}

@test "new creates the draft with 600 perms" {
  work="$(mktemp -d)"; ed="$work/ed"; _fake_editor "$ed"
  export GD_EDITED_PATH="$work/edited" GD_EDITED_MODE="$work/mode"
  run env GHOSTDRAFT_DIR="$work/draftdir" EDITOR="$ed" bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  [ "$(cat "$work/mode")" = "600" ]
  rm -rf "$work"
}

@test "new defaults the fallback editor to 'vim -i NONE' when EDITOR is unset" {
  work="$(mktemp -d)"; bin="$work/bin"; mkdir -p "$bin"
  # vim stub: writes content into the last argument (the draft), logs its arguments.
  cat > "$bin/vim" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$VIM_ARGS"
for f; do :; done
printf 'DRAFT-CONTENT' > "$f"
SH
  chmod +x "$bin/vim"
  export VIM_ARGS="$work/vimargs"
  run env -u EDITOR PATH="$bin:$PATH" GHOSTDRAFT_DIR="$work/d" bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  run cat "$VIM_ARGS"
  [[ "$output" == "-N -i NONE "* ]]
  rm -rf "$work"
}

@test "default vim exits with one key from any mode (Ctrl-D save, Ctrl-X discard)" {
  work="$(mktemp -d)"; bin="$work/bin"; mkdir -p "$bin"
  cat > "$bin/vim" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$VIM_ARGS"
for f; do :; done
printf 'DRAFT-CONTENT' > "$f"
SH
  chmod +x "$bin/vim"
  export VIM_ARGS="$work/vimargs"
  run env -u EDITOR PATH="$bin:$PATH" GHOSTDRAFT_DIR="$work/d" bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  run cat "$VIM_ARGS"
  # Exit must work FROM ANY MODE: `ZZ`/`ZQ` live only in normal mode; from insert
  # mode they just get typed into the text and the editor looks hung; F-keys are
  # intercepted by the terminal (Warp). Hence a Ctrl chord + mapping in normal AND insert.
  [[ "$output" == *"laststatus=2"* ]]
  [[ "$output" == *"statusline="* ]]
  [[ "$output" == *"Ctrl-D"* ]]
  [[ "$output" == *"Ctrl-X"* ]]
  [[ "$output" == *"nnoremap <silent> <C-d> :wq<CR>"* ]]
  [[ "$output" == *"inoremap <silent> <C-d> <Esc>:wq<CR>"* ]]
  [[ "$output" == *"nnoremap <silent> <C-x> :q!<CR>"* ]]
  [[ "$output" == *"inoremap <silent> <C-x> <Esc>:q!<CR>"* ]]
  # A missed `ZQ` started macro recording (`recording @q`) — the editor stopped responding
  # to the familiar keys and it looked like a hang. No macro recording in a notepad.
  [[ "$output" == *"nnoremap q <Nop>"* ]]
  # The old paths are not broken — whoever knows them loses nothing.
  [[ "$output" == *"ZZ"* ]]
  [[ "$output" == *"ZQ"* ]]
  [[ "$output" == *"nnoremap <F2> :wq<CR>"* ]]
  [[ "$output" == *"<F3> :q!<CR>"* ]]
  # The notepad must open READY TO TYPE. vim starts in normal mode where letters are
  # commands: a real user typed, no text appeared, and a half-entered command stub hung
  # at the bottom. Plus `-N`: without ~/.vimrc vim goes compatible, where Backspace
  # and arrows in insert don't behave the way a non-vim user expects.
  [[ "$output" == *"startinsert"* ]]
  [[ "$output" == *"-N"* ]]
  [[ "$output" == *"backspace=indent,eol,start"* ]]
  # vim accepts AT MOST 10 `-c`; on the eleventh it refuses to start entirely,
  # i.e. the notepad doesn't open at all. The vim stub won't show this — guard by counting.
  n_c="$(printf '%s\n' $output | grep -c -- '^-c$')"
  [ "$n_c" -le 10 ]
  rm -rf "$work"
}

@test "new falls back to default when \$EDITOR is whitespace-only (no exec of the draft)" {
  work="$(mktemp -d)"; bin="$work/bin"; mkdir -p "$bin"
  cat > "$bin/vim" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$VIM_ARGS"
for f; do :; done
printf 'DRAFT-CONTENT' > "$f"
SH
  chmod +x "$bin/vim"
  export VIM_ARGS="$work/vimargs"
  run env PATH="$bin:$PATH" GHOSTDRAFT_DIR="$work/d" EDITOR="   " bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  run cat "$VIM_ARGS"
  [[ "$output" == "-N -i NONE "* ]]
  rm -rf "$work"
}

@test "new honors a multi-word \$EDITOR (flags preserved)" {
  work="$(mktemp -d)"; bin="$work/bin"; mkdir -p "$bin"
  cat > "$bin/myed" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$ED_ARGS"
for f; do :; done
printf 'DRAFT-CONTENT' > "$f"
SH
  chmod +x "$bin/myed"
  export ED_ARGS="$work/edargs"
  run env PATH="$bin:$PATH" GHOSTDRAFT_DIR="$work/d" EDITOR="myed --wrap" bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  run cat "$ED_ARGS"
  [[ "$output" == "--wrap "* ]]
  rm -rf "$work"
}

@test "new cleans vim swap/undo and nano backup of the draft" {
  work="$(mktemp -d)"; dir="$work/draftdir"
  # the editor creates side artifacts next to the draft
  cat > "$work/ed" <<'SH'
#!/usr/bin/env bash
printf 'DRAFT-CONTENT' > "$1"
d="$(dirname "$1")"; b="$(basename "$1")"
printf 'swap' > "$d/.$b.swp"
printf 'undo' > "$d/.$b.un~"
printf 'backup' > "$d/$b~"
printf '%s\n' "$1" > "${GD_EDITED_PATH:?}"
{ stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; } > "${GD_EDITED_MODE:?}"
SH
  chmod +x "$work/ed"
  export GD_EDITED_PATH="$work/edited" GD_EDITED_MODE="$work/mode"
  run env GHOSTDRAFT_DIR="$dir" EDITOR="$work/ed" bash "$SCRIPT" new
  [ "$status" -eq 0 ]
  run bash -c "ls -A '$dir' 2>/dev/null"
  [ -z "$output" ]
  rm -rf "$work"
}

# Regression: _pick_draft_dir carries ram-dev as the third field via stdout (not via
# a global inside $(...)). Previously the RAM disk leaked without detach because of the
# subshell. Contract: output = "<dir>\t<kind>\t<ram_dev>" (ram_dev empty for override/vault).
@test "_pick_draft_dir emits the ram-dev field (no-subshell-leak contract)" {
  work="$(mktemp -d)"
  out="$(source "$SCRIPT"; GHOSTDRAFT_DIR="$work" _pick_draft_dir)"
  fields="$(awk -F'\t' '{print NF}' <<<"$out")"
  [ "$fields" -eq 3 ]
  [[ "$out" == "$work"$'\t'override$'\t'* ]]
  rm -rf "$work"
}

# Regression: the RAM-disk volume name is unique per call (suffix from /dev/urandom). It used
# to be fixed: /Volumes/ghostdraft-ram → two instances collide and detach-by-name misses.
@test "_ram_volname is unique per call and carries the prefix" {
  a="$(source "$SCRIPT"; _ram_volname)"
  b="$(source "$SCRIPT"; _ram_volname)"
  [[ "$a" =~ ^ghostdraft-ram-[0-9a-f]{8}$ ]]
  [[ "$b" =~ ^ghostdraft-ram-[0-9a-f]{8}$ ]]
  [ "$a" != "$b" ]
}

@test "new --clipboard copies the draft to the clipboard after confirm" {
  work="$(mktemp -d)"; bin="$work/bin"; mkdir -p "$bin"
  printf '#!/usr/bin/env bash\ncat >> "$CLIP_LOG"\n' > "$bin/pbcopy"
  printf '#!/usr/bin/env bash\ncat "$CLIP_STATE" 2>/dev/null || true\n' > "$bin/pbpaste"
  chmod +x "$bin/pbcopy" "$bin/pbpaste"
  ed="$work/ed"; _fake_editor "$ed"
  export GD_EDITED_PATH="$work/edited" GD_EDITED_MODE="$work/mode"
  export CLIP_LOG="$work/clip.log" CLIP_STATE="$work/clip.state"; : > "$CLIP_LOG"
  # CLIP_SECS=1: auto-clear only appends emptiness to the append-log — the assertion below
  # (grep DRAFT-CONTENT) is race-safe; keep it short to avoid piling up background sleeps.
  run env PATH="$bin:$PATH" GHOSTDRAFT_DIR="$work/d" GHOSTDRAFT_CLIP_SECS=1 \
    ST_ASSUME_YES=1 EDITOR="$ed" bash "$SCRIPT" new --clipboard
  [ "$status" -eq 0 ]
  grep -q 'DRAFT-CONTENT' "$CLIP_LOG"
  rm -rf "$work"
}

@test "new --clipboard does NOT copy when confirm is declined" {
  work="$(mktemp -d)"; bin="$work/bin"; mkdir -p "$bin"
  printf '#!/usr/bin/env bash\ncat >> "$CLIP_LOG"\n' > "$bin/pbcopy"
  printf '#!/usr/bin/env bash\ntrue\n' > "$bin/pbpaste"
  chmod +x "$bin/pbcopy" "$bin/pbpaste"
  ed="$work/ed"; _fake_editor "$ed"
  export GD_EDITED_PATH="$work/edited" GD_EDITED_MODE="$work/mode"
  export CLIP_LOG="$work/clip.log"; : > "$CLIP_LOG"
  run env PATH="$bin:$PATH" GHOSTDRAFT_DIR="$work/d" EDITOR="$ed" \
    bash "$SCRIPT" new --clipboard <<< "no"
  [ "$status" -eq 0 ]
  run grep -q 'DRAFT-CONTENT' "$CLIP_LOG"
  [ "$status" -ne 0 ]
  rm -rf "$work"
}

@test "_clip_clear_if_match clears only when clipboard still holds our content" {
  work="$(mktemp -d)"; bin="$work/bin"; mkdir -p "$bin"
  printf '#!/usr/bin/env bash\ncat > "$CLIP_STATE"\n' > "$bin/pbcopy"
  printf '#!/usr/bin/env bash\ncat "$CLIP_STATE" 2>/dev/null || true\n' > "$bin/pbpaste"
  chmod +x "$bin/pbcopy" "$bin/pbpaste"
  export CLIP_STATE="$work/state"
  printf 'OUR-SECRET' > "$CLIP_STATE"
  PATH="$bin:$PATH" bash -c "source '$SCRIPT'; _clip_clear_if_match 'OUR-SECRET'"
  [ -z "$(cat "$CLIP_STATE")" ]
  printf 'USER-LATER-COPY' > "$CLIP_STATE"
  PATH="$bin:$PATH" bash -c "source '$SCRIPT'; _clip_clear_if_match 'OUR-SECRET'"
  [ "$(cat "$CLIP_STATE")" = "USER-LATER-COPY" ]
  rm -rf "$work"
}

@test "new refuses honestly when no safe location is available" {
  work="$(mktemp -d)"
  run env -u GHOSTDRAFT_DIR ST_VAULT_VOLUME="$work/nonexistent" \
    GHOSTDRAFT_DISABLE_RAM=1 EDITOR=true bash "$SCRIPT" new
  [ "$status" -eq 3 ]
  rm -rf "$work"
}

@test "pipe echoes stdin to stdout" {
  run bash -c "printf 'secret-seed-123' | bash '$SCRIPT' pipe"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret-seed-123"* ]]
}

@test "pipe preserves multi-line input" {
  run bash -c "printf 'line1\nline2\nline3' | bash '$SCRIPT' pipe"
  [ "$status" -eq 0 ]
  [[ "$output" == *"line1"* ]]
  [[ "$output" == *"line2"* ]]
  [[ "$output" == *"line3"* ]]
}

@test "pipe handles empty stdin (status 0, no crash)" {
  run bash -c "printf '' | bash '$SCRIPT' pipe"
  [ "$status" -eq 0 ]
}

@test "pipe writes nothing to disk" {
  work="$(mktemp -d)"
  before="$(find "$work" -type f | wc -l)"
  ( cd "$work" && printf 'top-secret' | bash "$SCRIPT" pipe >/dev/null )
  after="$(find "$work" -type f | wc -l)"
  [ "$before" -eq "$after" ]
  # the content did not leak into temp files in the working directory
  run bash -c "grep -rl 'top-secret' '$work' 2>/dev/null"
  [ -z "$output" ]
  rm -rf "$work"
}

@test "vendor --check detects drift in the vendored block" {
  work="$(mktemp -d)"; mkdir -p "$work/tools"
  cp "${BATS_TEST_DIRNAME}/../ghostdraft" "$work/ghostdraft"
  cp "${BATS_TEST_DIRNAME}/../tools/vendor-common.sh" "$work/tools/"
  sed 's/_ST_COMMON_LOADED=1/_ST_COMMON_LOADED=999/' "$work/ghostdraft" > "$work/ghostdraft.mut"
  mv "$work/ghostdraft.mut" "$work/ghostdraft"
  run bash "$work/tools/vendor-common.sh" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ДРЕЙФ"* ]] || [[ "$output" == *"drift"* ]]
  rm -rf "$work"
}

# Structural P3: "is the volume mounted" is asked of the canonical _volume_mounted from
# the vendored common.sh. A directory left over from a past mount is not a vault:
# a draft written into it would land on the regular disk, the exact opposite of the tool's purpose.
@test "_is_mounted_writable refuses a writable directory that is not a mounted volume" {
  work="$(mktemp -d)"; bin="$work/bin"; mkdir -p "$bin" "$work/Volumes/SecretVault"
  printf '#!/usr/bin/env bash\necho "/dev/disk1s5 on / (apfs, local)"\n' > "$bin/mount"
  chmod +x "$bin/mount"
  run env PATH="$bin:$PATH" bash -c "source '$SCRIPT'; _is_mounted_writable '$work/Volumes/SecretVault' && echo YES || echo NO"
  [[ "$output" == *"NO"* ]]
  rm -rf "$work"
}

@test "_is_mounted_writable accepts a mounted writable volume" {
  work="$(mktemp -d)"; bin="$work/bin"; mkdir -p "$bin" "$work/Volumes/SecretVault"
  printf '#!/usr/bin/env bash\necho "/dev/disk4s1 on %s/Volumes/SecretVault (apfs, local, nobrowse)"\n' "$work" > "$bin/mount"
  chmod +x "$bin/mount"
  run env PATH="$bin:$PATH" bash -c "source '$SCRIPT'; _is_mounted_writable '$work/Volumes/SecretVault' && echo YES || echo NO"
  [[ "$output" == *"YES"* ]]
  rm -rf "$work"
}

@test "real vim: with these flags typed text actually lands in the file" {
  # A stub editor can't show WHICH MODE real vim opens in — and that is exactly where
  # a real user got stuck. Replay keys into real vim with the same flags:
  # type text and press Ctrl-D. Without `startinsert` the file would stay empty.
  command -v vim >/dev/null 2>&1 || skip "vim not installed"
  work="$(mktemp -d)"
  printf 'secret note\004' > "$work/keys"      # text + Ctrl-D
  : > "$work/draft"
  TERM=dumb vim -N -i NONE \
    -c 'execute "inoremap <silent> <C-d> <Esc>:wq<CR>"' \
    -c 'startinsert' -s "$work/keys" "$work/draft" >/dev/null 2>&1 || true
  [ "$(cat "$work/draft")" = "secret note" ]
  rm -rf "$work"
}
