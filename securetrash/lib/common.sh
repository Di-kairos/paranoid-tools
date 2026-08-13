# shellcheck shell=bash
# common.sh — reusable primitives of the Paranoid Tools ecosystem.
#
# Canonical source: securetrash/lib/common.sh. Ecosystem tools
# (vaultwatch/panic/ghostdraft) vendor it inline between markers
# (see CLAUDE.md "Vendoring"). The file is sourceable and idempotent (double source/inline
# are safe — guard via an if-wrapper, no top-level return, so it stays correct even when
# the block is pasted into an executable script).
#
# Provides tool-agnostic primitives: locale (ST_LOCALE), colored output (info/warn/err),
# confirmation (confirm), macOS platform detection (require_macos/is_ssd/_disk_kind/
# _fv_state/filevault_on), mounted-volume detection (_volume_mounted), path
# canonicalization (_abspath). Each tool keeps its own i18n table.
#
# VENDORING — reserved names (do not redefine in the host script): functions
# info warn err confirm require_macos is_ssd _disk_kind _fv_state filevault_on
# _volume_mounted _abspath _st_detect_locale; variables ST_LOCALE C_RED C_GRN C_YEL
# C_RST _ST_COMMON_LOADED.

# Idempotency via an if-wrapper (not a top-level return): safe when sourced,
# executed, or pasted inline. Function definitions inside the if register globally.
if [[ -z "${_ST_COMMON_LOADED:-}" ]]; then
  _ST_COMMON_LOADED=1

  # --- locale ---
  # en by default; ru — if ST_LANG or the system locale starts with 'ru'.
  _st_detect_locale() {
    local want="${ST_LANG:-}"
    if [[ -n "$want" ]]; then
      case "$want" in ru*) echo ru ;; *) echo en ;; esac
      return
    fi
    local sys="${LC_ALL:-${LANG:-}}"
    case "$sys" in ru*) echo ru ;; *) echo en ;; esac
  }
  # Respect a pre-set ST_LOCALE (the host may override it).
  ST_LOCALE="${ST_LOCALE:-$(_st_detect_locale)}"

  # --- output ---
  # Color only on a TTY (no ANSI in pipes/files).
  if [[ -t 1 ]]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RST=$'\033[0m'
  else
    C_RED=""; C_GRN=""; C_YEL=""; C_RST=""
  fi
  info() { echo "${C_GRN}✓${C_RST} $*"; }
  warn() { echo "${C_YEL}!${C_RST} $*" >&2; }
  err()  { echo "${C_RED}✗${C_RST} $*" >&2; }

  # --- confirm ---
  # Confirmation for an irreversible operation. ST_ASSUME_YES=1 skips the question (scripts/tests).
  # Returns 0 only on the exact input 'yes' (EOF/empty → refusal, fail-closed).
  # The suffix is deliberately duplicated from securetrash's i18n (the lib has no string table).
  confirm() {
    local prompt="$1" ans suffix
    [[ "${ST_ASSUME_YES:-0}" == "1" ]] && return 0
    case "$ST_LOCALE" in ru) suffix="[введите yes]" ;; *) suffix="[type yes]" ;; esac
    read -r -p "$prompt $suffix: " ans
    [[ "$ans" == "yes" ]]
  }

  # --- platform (macOS) ---
  require_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
      case "$ST_LOCALE" in
        ru) err "работает только на macOS." ;;
        *)  err "runs on macOS only." ;;
      esac
      exit 1
    fi
  }

  # Is the disk under the path an SSD? (diskutil info: "Solid State: Yes")
  is_ssd() {
    local path="${1:-/}"
    diskutil info "$path" 2>/dev/null | grep -qi "Solid State:.*Yes"
  }

  # Disk kind: ssd | hdd | unknown. Honesty over guessing: an unknown kind is
  # NOT treated as hdd-effective (no "Solid State" field → unknown).
  _disk_kind() {
    local path="${1:-/}" out
    out="$(diskutil info "$path" 2>/dev/null)"
    if grep -qi "Solid State:.*Yes" <<<"$out"; then echo ssd
    elif grep -qi "Solid State:.*No" <<<"$out"; then echo hdd
    else echo unknown; fi
  }

  # FileVault state — tri-state: on / off / unknown. Distinguishing "off" from
  # "could not determine" is mandatory: a tool that prints "OFF" when fdesetup is
  # missing lies to the user about their protection.
  #
  # We capture the output into a variable and match a here-string, NOT a direct pipe
  # `fdesetup ... | grep -q`: under `set -o pipefail` such a pipe falsely "fails" — grep -q
  # closes the channel on the first match, the source gets SIGPIPE (141), and pipefail
  # makes the whole pipeline non-zero (a false unknown).
  _fv_state() {
    command -v fdesetup >/dev/null 2>&1 || { echo unknown; return; }
    local s; s="$(fdesetup status 2>/dev/null)"
    if   grep -qi "FileVault is On"  <<<"$s"; then echo on
    elif grep -qi "FileVault is Off" <<<"$s"; then echo off
    else echo unknown; fi
  }

  # Is FileVault on? Binary wrapper over _fv_state for places where "undetermined"
  # is safe to treat as "not on" (fail-closed).
  filevault_on() {
    [[ "$(_fv_state)" == on ]]
  }

  # Is the volume REALLY mounted at this path? The single answer to this question in
  # the ecosystem — there used to be three: `[[ -d ]]` (launcher), `mount | grep` (ghostdraft),
  # mountedVolumeURLs (GUI), and on a leftover /Volumes/… directory they disagreed:
  # a directory remaining from a past mount (or created by hand) read as
  # "OPEN". We check the mount table, not the directory's existence.
  #
  # We parse the `mount` line as a whole and compare the mount point IN FULL, rather
  # than searching for a substring: `grep -F " on /Volumes/Foo "` considers `/Volumes/Foo`
  # mounted when what is actually mounted is `/Volumes/Foo Bar` — a space inside the volume
  # name looks like the separator before the options (found by Codex). Line format on macOS:
  #   /dev/diskNsM on /Volumes/Volume Name (apfs, local, nobrowse)
  # The volume name may contain both spaces and `(`, so we strip the options as the SHORTEST
  # ` (*` suffix — volume `/Volumes/Foo (1)` keeps exactly `/Volumes/Foo (1)`.
  #
  # Return code — three states, not two: 0 — mounted, 1 — definitely NOT mounted,
  # 2 — the mount table could not be read. To predicate callers (`if
  # _volume_mounted …`) a 2 honestly reads as "not mounted" (fail-closed: don't write
  # a draft to a path we know nothing about), while whoever shows the state to the user
  # must distinguish "closed" from "could not look" — otherwise the dashboard would print
  # a green "closed" over an open vault.
  _volume_mounted() {
    local vol="${1:-}" line mp out
    [[ -n "$vol" ]] || return 1
    command -v mount >/dev/null 2>&1 || return 2
    out="$(mount 2>/dev/null)" || return 2
    [[ -n "$out" ]] || return 2   # an empty table is impossible (root is always mounted)
    while [[ "$vol" == */ && "$vol" != "/" ]]; do vol="${vol%/}"; done
    while IFS= read -r line; do
      [[ "$line" == *" on "* ]] || continue
      mp="${line#* on }"
      mp="${mp% (*}"
      [[ "$mp" == "$vol" ]] && return 0
    done <<<"$out"
    return 1
  }

  # --- path ---
  # Physical canonical path: strips trailing slashes, resolves .. and symlinks,
  # INCLUDING the final component. Non-empty string, or status !=0 if the path is inaccessible.
  _abspath() {
    local p="$1"
    while [[ "$p" == */ && "$p" != "/" ]]; do p="${p%/}"; done
    if [[ -d "$p" ]]; then
      ( cd -P -- "$p" 2>/dev/null && pwd -P ); return
    fi
    local d b
    d="$(cd -P -- "$(dirname -- "$p")" 2>/dev/null && pwd -P)" || return 1
    b="$(basename -- "$p")"
    printf '%s/%s' "${d%/}" "$b"
  }
fi
