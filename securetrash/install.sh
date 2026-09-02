#!/usr/bin/env bash
# Installs securetrash into /usr/local/bin with an integrity check.
#
# Pulls the binary and SHA256SUMS from the RELEASE tag (not from the main branch) and
# verifies the hash BEFORE installing. Closes the "curl|bash from main without verification"
# supply-chain risk: a release tag's contents are immutable (unlike the moving main), and the
# hash catches corruption, partial/cache substitution, and binary-vs-publication desync.
# HONESTLY: the checksum and the binary arrive over the same channel — this does not protect
# against substitution of the RELEASE ITSELF (both rewritten); authenticity needs a
# signature (F-4) / Homebrew.
#
# Usage (verify-then-run recommended, see README):
#   curl -fsSLO https://github.com/Di-kairos/paranoid-tools/releases/download/securetrash-v0.5.8/install.sh
#   curl -fsSLO https://github.com/Di-kairos/paranoid-tools/releases/download/securetrash-v0.5.8/SHA256SUMS
#   shasum -a 256 -c SHA256SUMS --ignore-missing   # verify install.sh itself
#   less install.sh                                  # read it with your own eyes
#   bash install.sh
#
# Environment variables:
#   ST_VERSION   — install a specific tag (e.g. 0.4.0). Defaults to latest.
#   ST_BASE_URL  — override the source entirely (for forks/tests).
#   ST_DEST      — install path. Defaults to /usr/local/bin/securetrash.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "securetrash работает только на macOS." >&2; exit 1
fi

REPO="Di-kairos/paranoid-tools"
# Default release of this tool; kept in lockstep with the securetrash-vX.Y.Z tag by a
# release.yml gate. In the monorepo `releases/latest` would be the latest release
# of ANY tool, so nothing here ever uses `latest` — the tag is always pinned.
ST_VERSION_DEFAULT="0.5.8"
# Source: explicit ST_BASE_URL → ST_VERSION override → the baked-in default tag.
if [[ -n "${ST_BASE_URL:-}" ]]; then
  BASE_URL="$ST_BASE_URL"
else
  BASE_URL="https://github.com/${REPO}/releases/download/securetrash-v${ST_VERSION:-$ST_VERSION_DEFAULT}"
fi
# Install directory. The `paranoid-tools` umbrella installs everything into ~/.local/bin (no
# sudo), while this installer historically targets /usr/local/bin. If the tool is already
# installed from the umbrella, install NEXT TO it: otherwise a second copy appears, and which
# one runs is decided by PATH order — i.e. the update silently never reaches the user.
# An explicit ST_DEST always wins.
if [[ -n "${ST_DEST:-}" ]]; then
  DEST="$ST_DEST"
elif [[ -e "$HOME/.local/bin/securetrash" ]]; then
  DEST="$HOME/.local/bin/securetrash"
else
  DEST="/usr/local/bin/securetrash"
fi

# Temporary download directory; cleaned up no matter what.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Скачиваю securetrash и SHA256SUMS из релиза..."
curl -fsSL "${BASE_URL}/securetrash" -o "${TMP}/securetrash"
curl -fsSL "${BASE_URL}/SHA256SUMS" -o "${TMP}/SHA256SUMS"

# Integrity check BEFORE chmod +x. --ignore-missing: SHA256SUMS also lists the
# Windows script, which is not present here — verify only the file we have.
echo "Проверяю контрольную сумму..."
if ! ( cd "$TMP" && shasum -a 256 -c SHA256SUMS --ignore-missing ); then
  echo "✗ Контрольная сумма НЕ совпала — установка прервана (возможна подмена)." >&2
  exit 1
fi

# --- RELEASE SIGNATURE check (authenticity on top of integrity) ---
# Releases are signed with a dedicated ed25519 key (ssh-keygen -Y). The pubkey is embedded
# below — it changes only on key rotation.
#   * pubkey not issued (empty) → silently skip (infra not ready);
#   * pubkey present but no ssh-keygen → refuse, fail-closed (bypass: ALLOW_UNSIGNED_LEGACY=1);
#   * .sig present but does NOT verify → hard refusal (clear sign of substitution);
#   * .sig missing → hard refusal (v0.4.2+ are always signed);
#     to install older releases (pre-v0.4.2): ALLOW_UNSIGNED_LEGACY=1 bash install.sh
RELEASE_SIGNING_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9DVd0vNOwa5hyr9gShaCWoNOVnUsrdHVO/WE0wCZkT"
SIGN_PRINCIPAL="releases@paranoid-tools"
# pubkey is set but ssh-keygen is unavailable → fail-closed: silently degrading to hash-only
# would mask a substitution; on macOS ssh-keygen ships with the system, its absence is anomalous
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
      echo "  Релизы v0.4.2+ всегда подписаны. Для установки более старого релиза:" >&2
      echo "  ALLOW_UNSIGNED_LEGACY=1 bash install.sh" >&2
      exit 1
    fi
  fi
fi

# Hash is correct → install. For a non-writable directory — via sudo.
echo "Устанавливаю в ${DEST}..."
if [[ -w "$(dirname "$DEST")" ]]; then
  install -m 0755 "${TMP}/securetrash" "$DEST"
else
  sudo install -m 0755 "${TMP}/securetrash" "$DEST"
fi

echo "Установлено: $DEST"
# Directory not in PATH — staying silent is not an option: the user will conclude the install failed.
case ":${PATH}:" in
  *":$(dirname "$DEST"):"*) : ;;
  *) echo "ВНИМАНИЕ: $(dirname "$DEST") не в PATH — добавь его, иначе команда не найдётся." >&2 ;;
esac
echo "Дальше: securetrash setup && securetrash check"
