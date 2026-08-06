**English** · [Русский](README.ru.md)

# seedsplit

Split a secret across shares with Shamir Secret Sharing — no "unbreakable" snake oil.

[![CI](https://github.com/Di-kairos/seedsplit/actions/workflows/ci.yml/badge.svg)](https://github.com/Di-kairos/seedsplit/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![platform](https://img.shields.io/badge/platform-macOS-blue)
![windows](https://img.shields.io/badge/Windows-beta-orange)
![shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)

Part of the [Paranoid Tools](https://github.com/Di-kairos/paranoid-tools) ecosystem.

## Why

Split a seed phrase, password or key into N shares so that any T of them reconstruct
the secret, while T-1 shares reveal **nothing** about it. That way no single medium or
backup is a single point of failure or compromise: lose one sheet and the secret
survives; find one sheet and you learn nothing.

## Install

The installer targets macOS, but the tool itself does not: `split`, `combine` and `verify` are
arithmetic over POSIX utilities (`od`, `tr`, `printf`) with no macOS-specific calls, so the
script runs on Linux too — clone it and run `bash seedsplit`. The Windows port has never had a
platform gate either. (The rest of the Paranoid Tools suite genuinely needs macOS — it drives
`hdiutil`, `fdesetup` and friends.)

The installer pulls the binary **and `SHA256SUMS` from the release tag** (not from a
moving `main` branch) and verifies the checksum **before** installing — it fails closed
on any mismatch.

### Verify-then-run (don't trust, verify)

Piping any script into a shell means running code you haven't read. Prefer this —
download, check the checksum, read it, then run:

```bash
base=https://github.com/Di-kairos/seedsplit/releases/latest/download
curl -fsSLO "$base/install.sh"
curl -fsSLO "$base/SHA256SUMS"
curl -fsSLO "$base/SHA256SUMS.sig"
printf '%s\n' 'releases@paranoid-tools namespaces="file" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U' > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools -n file -s SHA256SUMS.sig < SHA256SUMS &&   # authenticity: Ed25519, pinned key
shasum -a 256 -c SHA256SUMS --ignore-missing &&   # integrity: verifies install.sh
less install.sh &&                               # read it — then run:
bash install.sh
```

### One-line install via curl

```bash
curl -fsSL https://github.com/Di-kairos/seedsplit/releases/latest/download/install.sh | bash
```

> **Integrity vs authenticity (honest scope).** The checksum proves the downloaded
> binary matches the `SHA256SUMS` published in the **same release** — it catches
> corruption, partial/cached tampering, and stops you running code off the moving `main`
> branch. Authenticity comes from the Ed25519 signature over `SHA256SUMS`: the
> snippet above and `install.sh` both verify it against a key pinned in this repo, and
> the installer fails closed when it can't (see `SECURITY.md`). Residual risk: one
> project key signs all five tools — see the ecosystem
> [threat model](https://github.com/Di-kairos/paranoid-tools/blob/main/THREAT-MODEL.md). Pin a specific version with `SEEDSPLIT_VERSION=0.5.2` instead of `latest` for
> reproducibility. Override the source with `SEEDSPLIT_BASE_URL` and the install path
> with `SEEDSPLIT_DEST`.

### Language

Output is English by default. For Russian, set `ST_LANG=ru` (the tool also honors a
Russian system locale automatically).

### Windows (PowerShell, beta)

A PowerShell port lives in [`windows/`](windows/README.md). Shares are **byte-compatible**
with this build — split on macOS, combine on Windows, or the reverse. A known-answer test
reconstructs a macOS-generated share-set on Windows CI to guarantee it.

```powershell
irm https://github.com/Di-kairos/seedsplit/releases/latest/download/install.ps1 -OutFile install.ps1
# verify the hash against SHA256SUMS, then: pwsh -File install.ps1
```

## Usage

The secret is read from **stdin** or `--file`, **never** from argv (argv is visible in
`ps`).

Split a secret into 5 shares with a threshold of 3 (any 3 reconstruct it; any 2 reveal
nothing):

```bash
$ printf '%s' "legal winner thank year wave sausage worth useful legal winner thank yellow" \
    | seedsplit split -n 5 -t 3
SSS3-32c54257-3-1-86ef3410a5785b83…-a6effc9d-316d
SSS3-32c54257-3-2-4e0f3aca2ce3ca06…-4118ad84-9fca
SSS3-32c54257-3-3-9de045b6ecfcf0e9…-1cbc6b7a-62ec
SSS3-32c54257-3-4-cd1ba35892aa7d32…-9d21be40-701d
SSS3-32c54257-3-5-1ef4dc2452b547dd…-3f0ac715-16e8
```

Each line is a self-contained share in the form
`SSS3-<setid>-<T>-<x>-<hexY>-<parity>-<chk4>`: format version, a random **set-id** shared by
all shares of one split (so `combine` deterministically refuses to mix shares from *different*
splits), threshold, point index, body, a Reed-Solomon **parity** field, and a 4-char checksum.
Distribute the lines across different media/locations.

**Typo correction (since 0.5.0).** Shares live on paper, and paper gets copied by hand. The
parity field is Reed-Solomon over the same GF(256) the sharing itself uses: `combine` repairs
**up to two mistyped bytes per share** — anywhere in the body or in the parity field itself —
and says so after the secret has verified.

Past two bytes, be precise about what happens: the code has distance 5, so a heavily damaged
share can decode toward a *different* codeword instead of simply failing. That candidate is
then rejected by the per-share checksum and, failing that, by the 128-bit payload tag, so
`combine` still returns either the exact secret or an error — but the guarantee comes from
those checks, not from the decoder refusing. What parity does *not* cover at all: the short
structural head (`setid`, `T`, `x`), where a typo is detected by the checksum but cannot be
repaired, and dropped or inserted characters, which shift everything after them. Re-copy such
a share from the paper.

Shares printed by 0.4.x (`SSS2-…`, no parity field) still combine — they just have nothing to
repair with. There is no migration: if you want the parity, re-split the secret.

Reconstruct the secret — feed **any T (or more) shares** on stdin, one per line:

```bash
$ head -3 shares.txt | seedsplit combine
legal winner thank year wave sausage worth useful legal winner thank yellow
```

You can also pass shares as file arguments:

```bash
seedsplit combine share1.txt share2.txt share3.txt
```

Check that a set reconstructs **without revealing the secret** (useful when laying out
shares across media — confirm correctness without exposing anything). It exits `0` and
prints the recovered length, never the secret:

```bash
head -3 shares.txt | seedsplit verify
```

Version and help:

```bash
seedsplit version        # or -v / --version
seedsplit help           # or -h / --help
```

### Commands & flags

| Command | What it does |
|---|---|
| `seedsplit split [-n N] [-t T] [-p] [--file F]` | Split a secret (from stdin or `--file`) into `N` shares; any `T` reconstruct it. Default `-n 3 -t 2`. |
| `seedsplit split -p` / `--passphrase` | Encrypt the secret first (openssl AES-256-CBC + PBKDF2) so a reconstructed threshold still needs the passphrase. `combine` auto-detects and prompts. See *Scope & limitations*. |
| `seedsplit combine [FILE...]` | Reconstruct the secret from ≥T shares (read from stdin, one per line, or from `FILE`s). Prompts for the passphrase if the shares were split with `-p`. |
| `seedsplit verify [FILE...]` | Confirm ≥T shares reconstruct, **without printing the secret** (prints only the recovered length). |
| `seedsplit version` | Print the version (also `-v` / `--version`). |
| `seedsplit help` | Print help (also `-h` / `--help`). |

Parameter limits: the threshold `-t` must be ≥2 (otherwise one share equals the whole
secret), `-n` must be ≥ `-t` and ≤255 (evaluation points in GF(256)); the secret may be
up to 65535 bytes.

## How it works

A pure implementation of **Shamir Secret Sharing over GF(256)** (the `2^8` field with
reducing polynomial `0x11b`, same as AES; addition = XOR, multiplication via log/antilog
tables from generator `0x03`). The random polynomial coefficients come from
`/dev/urandom`.

The secret is wrapped in an integrity header (`0x55` | length | secret | **128-bit tag**
from sha256), so `combine` returns **either the exact secret or an honest refusal** — the
odds of silently returning a *wrong* secret are ≈ 2⁻¹²⁸. Each share also carries a random
**set-id** (a 4-byte nonce, *not* derived from the secret — so it can't be used as a
guess-confirmation oracle), letting `combine` deterministically reject a mix of shares
from different splits. Failures are distinct and specific: corrupted share (checksum),
shares from different splits (set-id), below threshold, inconsistent threshold, or a
failed integrity check.

## Scope & limitations

Honesty is the whole point of this ecosystem, and Shamir sharing is especially easy to
oversell. So here are the honest limits:

- **share quality = RNG quality** — we use `/dev/urandom`, not a homegrown PRNG;
- **a secret in `argv` is visible in `ps`** — input is via stdin/file only, never an
  argument;
- **shares are only as safe as how you STORE and DISTRIBUTE them;** the threshold
  protects against a leak of fewer than T shares, but not against the LOSS of ≥(N-T+1)
  shares — geography and media are your responsibility;
- **there is NO interoperability with SLIP-39 / hardware wallets yet** — a full SLIP-39
  (1024-word list + RS1024 + encryption) is a separate effort in scope, not "zero
  dependencies"; it's honestly flagged as a scope decision for a later pack;
- **GF(256) multiplication uses log/antilog tables and is NOT constant-time** — there is a
  timing side-channel. It is outside this tool's threat model (a local CLI with no remote
  or online oracle on `split`/`combine`), but we don't hide it.
- **the passphrase layer (`-p`) uses openssl**, not the zero-dep core — it's an opt-in
  encrypt-before-split (AES-256-CBC + PBKDF2) so a reconstructed threshold still needs the
  passphrase. The core `split`/`combine` stay dependency-free; only `-p` calls openssl
  (present by default on macOS/Linux). The Windows port reconstructs the sealed container and
  tells you to decrypt it with an `openssl enc -d` pipeline. **Edge:** a non-encrypted secret
  that happens to begin with the literal bytes `Salted__` (≈2⁻⁶⁴ for arbitrary data; not a
  concern for real seed phrases) is mis-read by `combine` as encrypted — you'd get a
  "wrong passphrase" error instead of the secret (no leak); re-split with `-p` or decrypt by hand.

## Architecture

- Single-file Bash, zero dependencies. Shamir over GF(256) is implemented in pure Bash;
  the RNG is `/dev/urandom`. Tests: **bats** (44 tests — `split`/`combine`/`verify`,
  round-trip over every threshold subset, the full failure taxonomy, the 128-bit
  integrity tag, plus known-answer tests: FIPS-197 GF vectors and a frozen share-set).
- The shared core (`lib/common.sh`) is **vendored** inline from securetrash, pinned to a
  git ref; `tools/vendor-common.sh --check` catches drift in CI. See
  [`paranoid-tools/README.md`](https://github.com/Di-kairos/paranoid-tools#readme).

## Windows (beta)

A PowerShell port now exists in [`windows/README.md`](windows/README.md). It mirrors the
macOS logic — the same Shamir over GF(256), with `RNGCryptoServiceProvider` instead of
`/dev/urandom` — and produces **byte-compatible** shares (split on one OS, combine on the other).

> **Beta:** the Windows port is logic-tested (Pester on CI) but not yet validated on real
> Windows hardware. See [`windows/README.md`](windows/README.md).

## License

[MIT](LICENSE). Report security issues via [SECURITY.md](SECURITY.md); contributions via
[CONTRIBUTING.md](CONTRIBUTING.md).

This software is provided "as is," without warranty of any kind. seedsplit splits a
secret correctly (a real Shamir threshold), but it is **not** responsible for how you
store and distribute the shares — that's on you.
