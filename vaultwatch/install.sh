#!/usr/bin/env bash
# Installs vaultwatch into /usr/local/bin with an integrity check.
#
# Pulls the binary and SHA256SUMS from a RELEASE tag (not the main branch) and checks
# the hash BEFORE installing. Closes the "curl|bash from main without verification"
# supply-chain risk: a release tag's contents are immutable (unlike the moving main),
# and the hash catches corruption, partial/cache tampering, and a binary drifting out
# of sync with the publication.
# HONEST: the checksum and the binary arrive over the same channel — this does not
# protect against the RELEASE ITSELF being replaced (both rewritten); authenticity
# requires a signature / Homebrew.
#
# Usage (verify-then-run recommended, see README):
#   curl -fsSLO https://github.com/Di-kairos/vaultwatch/releases/latest/download/install.sh
#   curl -fsSLO https://github.com/Di-kairos/vaultwatch/releases/latest/download/SHA256SUMS
#   shasum -a 256 -c SHA256SUMS --ignore-missing   # verify install.sh itself
#   less install.sh                                  # read it with your own eyes
#   bash install.sh
#
# Environment variables:
#   VW_VERSION   — install a specific tag (e.g. 0.1.0). Defaults to latest.
#   VW_BASE_URL  — override the source entirely (for forks/tests).
#   VW_DEST      — install path. Defaults to /usr/local/bin/vaultwatch.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "vaultwatch работает только на macOS." >&2; exit 1
fi

REPO="Di-kairos/vaultwatch"
# Source: explicit VW_BASE_URL → specific VW_VERSION tag → latest release.
if [[ -n "${VW_BASE_URL:-}" ]]; then
  BASE_URL="$VW_BASE_URL"
elif [[ -n "${VW_VERSION:-}" ]]; then
  BASE_URL="https://github.com/${REPO}/releases/download/v${VW_VERSION}"
else
  BASE_URL="https://github.com/${REPO}/releases/latest/download"
fi
# Install directory. The `paranoid-tools` umbrella installs everything into ~/.local/bin
# (no sudo), while this installer historically targets /usr/local/bin. If the tool is
# already installed by the umbrella, install NEXT TO it: otherwise a second copy appears,
# and which one runs is decided by PATH order — i.e. the update silently never reaches
# the user. An explicit VW_DEST always wins.
if [[ -n "${VW_DEST:-}" ]]; then
  DEST="$VW_DEST"
elif [[ -e "$HOME/.local/bin/vaultwatch" ]]; then
  DEST="$HOME/.local/bin/vaultwatch"
else
  DEST="/usr/local/bin/vaultwatch"
fi

# Temporary download directory; cleaned up no matter what.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Скачиваю vaultwatch и SHA256SUMS из релиза..."
curl -fsSL "${BASE_URL}/vaultwatch" -o "${TMP}/vaultwatch"
curl -fsSL "${BASE_URL}/SHA256SUMS" -o "${TMP}/SHA256SUMS"

# Integrity check BEFORE chmod +x.
echo "Проверяю контрольную сумму..."
if ! ( cd "$TMP" && shasum -a 256 -c SHA256SUMS --ignore-missing ); then
  echo "✗ Контрольная сумма НЕ совпала — установка прервана (возможна подмена)." >&2
  exit 1
fi

# --- Release SIGNATURE verification (authenticity on top of integrity) ---
# Releases are signed with the ecosystem's dedicated ed25519 key (ssh-keygen -Y). Pubkey embedded below.
# Behavior: no ssh-keygen → refuse, fail-closed (bypass: ALLOW_UNSIGNED_LEGACY=1);
# release has no .sig → hard refusal (legacy bypass via ALLOW_UNSIGNED_LEGACY=1);
# .sig present and does NOT verify → hard refusal (a clear sign of tampering).
RELEASE_SIGNING_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U"
SIGN_PRINCIPAL="releases@paranoid-tools"
# pubkey is set but ssh-keygen unavailable → fail-closed: a silent degradation to hash-only
# would mask tampering; on macOS ssh-keygen ships with the system, its absence is anomalous
# (parity with the umbrella install.sh and windows/install.ps1; AUDIT_2026-08-03 P1-1).
SSH_KEYGEN="$(type -P ssh-keygen || true)"   # external binary only: an exported function is no good as a verifier
if [[ -n "$RELEASE_SIGNING_PUBKEY" ]] && [[ -z "$SSH_KEYGEN" ]]; then
  if [[ "${ALLOW_UNSIGNED_LEGACY:-0}" != "1" ]]; then
    echo "✗ ssh-keygen недоступен — подпись проверить нечем; установка прервана." >&2
    echo "  Установи openssh, либо осознанно (только целостность): ALLOW_UNSIGNED_LEGACY=1 bash install.sh" >&2
    exit 1
  fi
  echo "! ssh-keygen недоступен — подпись релиза НЕ проверена (ALLOW_UNSIGNED_LEGACY=1, только SHA256)." >&2
fi
if [[ -n "$RELEASE_SIGNING_PUBKEY" ]] && [[ -n "$SSH_KEYGEN" ]]; then
  if curl -fsSL "${BASE_URL}/SHA256SUMS.sig" -o "${TMP}/SHA256SUMS.sig" 2>/dev/null; then
    printf '%s namespaces="file" %s\n' "$SIGN_PRINCIPAL" "$RELEASE_SIGNING_PUBKEY" > "${TMP}/allowed_signers"
    echo "Проверяю подпись релиза..."
    if ( cd "$TMP" && "$SSH_KEYGEN" -Y verify -f allowed_signers -I "$SIGN_PRINCIPAL" \
                        -n file -s SHA256SUMS.sig < SHA256SUMS >/dev/null 2>&1 ); then
      echo "✓ Подпись релиза верна (аутентичность подтверждена)."
    else
      echo "✗ Подпись релиза НЕ прошла проверку — установка прервана (возможна подмена)." >&2
      exit 1
    fi
  else
    if [[ "${ALLOW_UNSIGNED_LEGACY:-0}" == "1" ]]; then
      echo "! Подпись недоступна — продолжаю (ALLOW_UNSIGNED_LEGACY=1, только для старых релизов)." >&2
    else
      echo "✗ Подпись релиза отсутствует — установка прервана." >&2
      echo "  Релизы подписаны. Неподписанный/старый релиз: ALLOW_UNSIGNED_LEGACY=1 bash install.sh" >&2
      exit 1
    fi
  fi
fi

# Hash is correct → install. For a non-writable directory — via sudo.
echo "Устанавливаю в ${DEST}..."
if [[ -w "$(dirname "$DEST")" ]]; then
  install -m 0755 "${TMP}/vaultwatch" "$DEST"
else
  sudo install -m 0755 "${TMP}/vaultwatch" "$DEST"
fi

echo "Установлено: $DEST"
# Directory not in PATH — staying silent is not an option: the user would decide the install failed.
case ":${PATH}:" in
  *":$(dirname "$DEST"):"*) : ;;
  *) echo "ВНИМАНИЕ: $(dirname "$DEST") не в PATH — добавь его, иначе команда не найдётся." >&2 ;;
esac
echo "Дальше: vaultwatch install-hooks   # подключить к securetrash vault open/close"
