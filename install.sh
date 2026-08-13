#!/usr/bin/env bash
# Installer for the WHOLE Paranoid Tools ecosystem — "one command, everything's there".
#
# Installs 5 tools (securetrash, vaultwatch, panic, ghostdraft, seedsplit)
# + the interactive `paranoid` launcher into ~/.local/bin. Two modes, selected
# automatically by whether local tool sources are present nearby:
#
#   1. PUBLIC (default, any clone). Each tool is pulled from its SIGNED
#      release using the verify-then-run scheme: the Ed25519 signature over
#      SHA256SUMS is verified, then the checksum of the tool's own install.sh,
#      and only then it runs (and it, in turn, verifies the binary too). This
#      way "git clone + bash install.sh" honestly delivers all 5, no manual fuss.
#      The tool sources live in this same monorepo, but the public install does
#      NOT use them: the signature chain matters more than saving a download.
#
#   2. MAINTAINER (explicit PT_DEV=1 only). The local `<tool>/<tool>` script is
#      copied from the working copy, including not-yet-released changes. No release
#      is fetched. Previously the mode enabled itself when tool subfolders existed;
#      in the monorepo EVERY clone has the subfolders, and auto-enabling would have
#      disabled verify-then-run for the entire public — hence explicit opt-in only.
#
# Usage:
#   bash install.sh                 # install/update all 5 (+ the launcher)
#   bash install.sh --uninstall     # remove all 5 (+ the launcher) from the bin dir
#   PT_DEST=/usr/local/bin bash install.sh   # different install directory
#
# Environment variables:
#   PT_DEST            — install directory. Defaults to ~/.local/bin (no sudo).
#   PT_<TOOL>_VERSION  — pin a specific tool's version (public mode).
#                        Exact names: PT_ST_VERSION (securetrash), PT_VW_VERSION
#                        (vaultwatch), PT_PANIC_VERSION, PT_GHOSTDRAFT_VERSION,
#                        PT_SEEDSPLIT_VERSION. Others (e.g. PT_SECURETRASH_VERSION)
#                        are silently ignored. Defaults to latest.
set -euo pipefail

# --- language detection ---
# Parity with the five tools: English by default, Russian is opt-in. The installer's
# security errors (signature failure, missing verifier) must be readable by whoever
# is installing: previously they were Russian-only, which for an EN user amounted
# to a silent refusal with no reason given.
# Priority: PT_LANG → ST_LANG (ecosystem-wide) → $LC_ALL/$LANG.
_detect_locale() {
  local want="${PT_LANG:-${ST_LANG:-}}"
  if [[ -n "$want" ]]; then
    case "$want" in ru*) echo "ru"; return ;; *) echo "en"; return ;; esac
  fi
  case "${LC_ALL:-${LANG:-}}" in ru*) echo "ru" ;; *) echo "en" ;; esac
}
LOCALE="$(_detect_locale)"

# Localized strings. The first argument is the key; the rest are substituted via printf.
t() {
  case "$LOCALE:$1" in
    en:only_macos)     echo "Paranoid Tools targets macOS." ;;
    ru:only_macos)     echo "Paranoid Tools рассчитаны на macOS." ;;
    en:uninstalling)   printf 'Removing Paranoid Tools from %s...\n' "$2" ;;
    ru:uninstalling)   printf 'Удаляю Paranoid Tools из %s...\n' "$2" ;;
    en:removed)        printf '  ✓ removed %s\n' "$2" ;;
    ru:removed)        printf '  ✓ удалён %s\n' "$2" ;;
    en:uninstall_done) echo "Done. (A Homebrew-installed securetrash, if any, was left alone — remove it with 'brew uninstall'.)" ;;
    ru:uninstall_done) echo "Готово. (Homebrew-версия securetrash, если была, не тронута — снимай через 'brew uninstall'.)" ;;
    en:dl_fail)        printf '  ✗ %s: could not download the release (%s).\n' "$2" "$3" ;;
    ru:dl_fail)        printf '  ✗ %s: не удалось скачать релиз (%s).\n' "$2" "$3" ;;
    en:sig_bad)        printf '  ✗ %s: the release signature did NOT verify — skipping (possible tampering).\n' "$2" ;;
    ru:sig_bad)        printf '  ✗ %s: подпись релиза НЕ прошла проверку — пропускаю (возможна подмена).\n' "$2" ;;
    en:sig_missing)    printf '  ✗ %s: no release signature available — skipping (override: ALLOW_UNSIGNED_LEGACY=1).\n' "$2" ;;
    ru:sig_missing)    printf '  ✗ %s: подпись релиза недоступна — пропускаю (обход: ALLOW_UNSIGNED_LEGACY=1).\n' "$2" ;;
    en:no_verifier)    printf '  ✗ %s: ssh-keygen is unavailable, so the signature cannot be checked; skipping (override: ALLOW_UNSIGNED_LEGACY=1).\n' "$2" ;;
    ru:no_verifier)    printf '  ✗ %s: ssh-keygen недоступен — подпись проверить нечем; пропускаю (обход: ALLOW_UNSIGNED_LEGACY=1).\n' "$2" ;;
    en:no_verifier_warn) printf '  ! ssh-keygen is unavailable — the signature of %s was NOT verified (ALLOW_UNSIGNED_LEGACY=1, checksum only).\n' "$2" ;;
    ru:no_verifier_warn) printf '  ! ssh-keygen недоступен — подпись %s НЕ проверена (ALLOW_UNSIGNED_LEGACY=1, только SHA256).\n' "$2" ;;
    en:sum_mismatch)   printf '  ✗ %s: checksum mismatch on install.sh — skipping.\n' "$2" ;;
    ru:sum_mismatch)   printf '  ✗ %s: контрольная сумма install.sh не совпала — пропускаю.\n' "$2" ;;
    en:tool_fail)      printf "  ✗ %s: the tool's own installer exited with an error:\n" "$2" ;;
    ru:tool_fail)      printf '  ✗ %s: установщик тула завершился с ошибкой:\n' "$2" ;;
    en:installing)     printf 'Installing Paranoid Tools into %s...\n' "$2" ;;
    ru:installing)     printf 'Ставлю Paranoid Tools в %s...\n' "$2" ;;
    en:from_worktree)  printf '  ✓ %s → %s (from the working copy)\n' "$2" "$3" ;;
    ru:from_worktree)  printf '  ✓ %s → %s (из рабочей копии)\n' "$2" "$3" ;;
    en:from_release)   printf '  ✓ %s → %s (from the signed release)\n' "$2" "$3" ;;
    ru:from_release)   printf '  ✓ %s → %s (из подписанного релиза)\n' "$2" "$3" ;;
    en:installed_n)    printf 'Tools installed: %s/%s (+ the paranoid launcher).\n' "$2" "$3" ;;
    ru:installed_n)    printf 'Установлено инструментов: %s/%s (+ лаунчер paranoid).\n' "$2" "$3" ;;
    en:partial_note)   echo "Some tools did not install — see the messages above (network / signature / directory)." ;;
    ru:partial_note)   echo "Часть тулов не встала — см. сообщения выше (сеть / подпись / каталог)." ;;
    en:path_ok)        printf 'PATH: %s is already on PATH — call the tools by name.\n' "$2" ;;
    ru:path_ok)        printf 'PATH: %s уже в PATH — вызывай тулы по имени.\n' "$2" ;;
    en:path_missing)   printf 'WARNING: %s is NOT on PATH. Add this to ~/.zshrc:\n' "$2" ;;
    ru:path_missing)   printf 'ВНИМАНИЕ: %s НЕ в PATH. Добавь в ~/.zshrc:\n' "$2" ;;
    en:state_fail)     printf 'WARNING: could not write %s — the launcher Update item will not find this clone.\n' "$2" ;;
    ru:state_fail)     printf 'ВНИМАНИЕ: не смог записать %s — пункт «Обновить» в лаунчере не найдёт этот клон.\n' "$2" ;;
    en:check_hint)     echo "Check: securetrash version  |  panic version  |  ghostdraft version" ;;
    ru:check_hint)     echo "Проверь: securetrash version  |  panic version  |  ghostdraft version" ;;
    en:run_launcher)   echo "Run the launcher: paranoid" ;;
    ru:run_launcher)   echo "Запусти лаунчер: paranoid" ;;
    en:guide_hint)     echo "Guide: GUIDE.md" ;;
    ru:guide_hint)     echo "Гайд по-русски: ИНСТРУКЦИЯ.md" ;;
    en:partial_exit)   printf 'Installation is incomplete (%s/%s) — exiting with an error. Override: PT_ALLOW_PARTIAL=1.\n' "$2" "$3" ;;
    ru:partial_exit)   printf 'Установка неполная (%s/%s) — выхожу с ошибкой. Обход: PT_ALLOW_PARTIAL=1.\n' "$2" "$3" ;;
    en:dev_banner)     echo "!!! PT_DEV=1: UNVERIFIED WORKTREE INSTALL — tools are copied from the local working copy, release signatures are NOT checked. Unset PT_DEV for the signed path." ;;
    ru:dev_banner)     echo "!!! PT_DEV=1: УСТАНОВКА ИЗ РАБОЧЕЙ КОПИИ БЕЗ ПРОВЕРКИ — инструменты копируются локально, подписи релизов НЕ проверяются. Убери PT_DEV, чтобы вернуть подписанный путь." ;;
    *) echo "$1" ;;
  esac
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  t only_macos >&2; exit 1
fi

# Repo root = this script's directory (robust to being run from any cwd).
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEST="${PT_DEST:-$HOME/.local/bin}"
TOOLS=(securetrash vaultwatch panic ghostdraft seedsplit)

# Release signing: the ecosystem's dedicated ed25519 key (shared by all 5 tools).
RELEASE_SIGNING_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U"
SIGN_PRINCIPAL="releases@paranoid-tools"

# Name of the DEST env variable of a given tool's install.sh (each has its own prefix).
dest_var_for() {
  case "$1" in
    securetrash) echo "ST_DEST" ;;
    vaultwatch)  echo "VW_DEST" ;;
    panic)       echo "PANIC_DEST" ;;
    ghostdraft)  echo "GHOSTDRAFT_DEST" ;;
    seedsplit)   echo "SEEDSPLIT_DEST" ;;
  esac
}

# Name of the VERSION env variable of a given tool's install.sh.
version_var_for() {
  case "$1" in
    securetrash) echo "ST_VERSION" ;;
    vaultwatch)  echo "VW_VERSION" ;;
    panic)       echo "PANIC_VERSION" ;;
    ghostdraft)  echo "GHOSTDRAFT_VERSION" ;;
    seedsplit)   echo "SEEDSPLIT_VERSION" ;;
  esac
}

# Uninstall mode.
if [[ "${1:-}" == "--uninstall" ]]; then
  t uninstalling "$DEST"
  for t in "${TOOLS[@]}" paranoid; do
    if [[ -e "${DEST}/${t}" ]]; then
      rm -f "${DEST}/${t}"
      t removed "$t"
    fi
  done
  t uninstall_done
  exit 0
fi

# Public mode: pull the tool's signed release and install it into $DEST.
# verify-then-run: Ed25519 signature over SHA256SUMS → install.sh checksum → run.
# Invoked ONLY as an `if` condition, so set -e inside does not abort the whole install.
install_from_release() {
  local t="$1"
  # Pre-monorepo-migration releases live in the archived per-tool repositories —
  # GitHub keeps serving them. Starting with the first monorepo release (tags
  # <tool>-vX.Y.Z) base will move to paranoid-tools/releases.
  local base="https://github.com/Di-kairos/${t}/releases/latest/download"
  local tmp; tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  # Pin the tool's version if PT_<TOOL>_VERSION is set.
  local pin_var; pin_var="PT_$(version_var_for "$t" | sed 's/_VERSION//')_VERSION"
  local pin="${!pin_var:-}"
  if [[ -n "$pin" ]]; then
    base="https://github.com/Di-kairos/${t}/releases/download/v${pin}"
  fi

  if ! curl -fsSL "${base}/install.sh" -o "${tmp}/install.sh" 2>/dev/null \
    || ! curl -fsSL "${base}/SHA256SUMS" -o "${tmp}/SHA256SUMS" 2>/dev/null; then
    t dl_fail "$t" "$base" >&2
    return 1
  fi

  # Authenticity: Ed25519 signature over SHA256SUMS (on top of integrity). No
  # ssh-keygen → warn loudly (hash check only); .sig present but does not
  # verify → hard refusal; no .sig → refusal (legacy override ALLOW_UNSIGNED_LEGACY=1).
  if command -v ssh-keygen >/dev/null 2>&1; then
    if curl -fsSL "${base}/SHA256SUMS.sig" -o "${tmp}/SHA256SUMS.sig" 2>/dev/null; then
      printf '%s namespaces="file" %s\n' "$SIGN_PRINCIPAL" "$RELEASE_SIGNING_PUBKEY" > "${tmp}/allowed_signers"
      if ! ( cd "$tmp" && ssh-keygen -Y verify -f allowed_signers -I "$SIGN_PRINCIPAL" \
                            -n file -s SHA256SUMS.sig < SHA256SUMS >/dev/null 2>&1 ); then
        t sig_bad "$t" >&2
        return 1
      fi
    elif [[ "${ALLOW_UNSIGNED_LEGACY:-0}" != "1" ]]; then
      t sig_missing "$t" >&2
      return 1
    fi
  else
    # No verifier. On macOS ssh-keygen ships out of the box → its absence is anomalous;
    # silently degrading to hash-only would mask tampering. Fail-closed (P1-4).
    if [[ "${ALLOW_UNSIGNED_LEGACY:-0}" != "1" ]]; then
      t no_verifier "$t" >&2
      return 1
    fi
    t no_verifier_warn "$t" >&2
  fi

  # Integrity: the install.sh hash from the (already signature-verified) SHA256SUMS.
  if ! ( cd "$tmp" && shasum -a 256 -c SHA256SUMS --ignore-missing >/dev/null 2>&1 ); then
    t sum_mismatch "$t" >&2
    return 1
  fi

  # Run the tool's verified install.sh, pointing its DEST at our directory.
  # It itself re-verifies the binary (SHA256 + the same Ed25519 signature) before installing.
  local dvar; dvar="$(dest_var_for "$t")"
  local vvar; vvar="$(version_var_for "$t")"
  # Do NOT silence the nested installer's stderr (else a signature failure/tampering is
  # indistinguishable from a network error) — capture to a log and proxy on failure (P1-4).
  local errlog="${tmp}/${t}.install.err"
  if ! env "${dvar}=${DEST}/${t}" ${pin:+"${vvar}=${pin}"} bash "${tmp}/install.sh" >/dev/null 2>"$errlog"; then
    t tool_fail "$t" >&2
    sed 's/^/      /' "$errlog" >&2
    return 1
  fi
  return 0
}

mkdir -p "$DEST"

t installing "$DEST"
# PT_DEV — loud and up front: silently bypassing the signed path is worse
# than an honest refusal.
if [[ "${PT_DEV:-0}" == "1" ]]; then t dev_banner >&2; fi
installed=0
for t in "${TOOLS[@]}"; do
  local_src="${ROOT}/${t}/${t}"
  if [[ "${PT_DEV:-0}" == "1" && -f "$local_src" ]]; then
    # MAINTAINER (PT_DEV=1): local script — copy it (incl. unreleased changes).
    install -m 0755 "$local_src" "${DEST}/${t}"
    t from_worktree "$t" "${DEST}/${t}"
    installed=$((installed + 1))
  elif install_from_release "$t"; then
    # PUBLIC: the signed release was fetched and verified.
    t from_release "$t" "${DEST}/${t}"
    installed=$((installed + 1))
  fi
done

# The paranoid launcher lives in this repo's root (it is versioned here, not in a
# separate tool repo) — so it is always present in any clone; install it separately.
install -m 0755 "${ROOT}/paranoid" "${DEST}/paranoid"
echo "  ✓ paranoid → ${DEST}/paranoid"

echo
t installed_n "$installed" "${#TOOLS[@]}"
partial=0
if [[ "$installed" -lt "${#TOOLS[@]}" ]]; then
  t partial_note >&2
  partial=1
fi

# PATH check: without this the tools are installed but cannot be called by name.
case ":$PATH:" in
  *":$DEST:"*) t path_ok "$DEST" ;;
  *)
    t path_missing "$DEST"
    echo "  export PATH=\"${DEST}:\$PATH\""
    ;;
esac

# Remember WHERE we installed from: the launcher (`paranoid` → Update) reruns the
# installer from this directory. Without it the menu item would not know what to
# update — the launcher copy in ~/.local/bin knows nothing about its source clone.
_state_dir="${XDG_DATA_HOME:-$HOME/.local/share}/paranoid-tools"
if mkdir -p "$_state_dir" 2>/dev/null; then
  # Remove the previous file before writing: if it is a symlink, `>` would clobber its target.
  rm -f "$_state_dir/source" 2>/dev/null || true
  if ! printf '%s\n' "$ROOT" > "$_state_dir/source" 2>/dev/null; then
    t state_fail "${_state_dir}/source" >&2
  fi
fi

echo
t check_hint
t run_launcher
t guide_hint

# A partial install is not a quiet success: exit with an error (override: PT_ALLOW_PARTIAL=1). P2-3.
if [[ "$partial" == "1" && "${PT_ALLOW_PARTIAL:-0}" != "1" ]]; then
  echo >&2
  t partial_exit "$installed" "${#TOOLS[@]}" >&2
  exit 1
fi
