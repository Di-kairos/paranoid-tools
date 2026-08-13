**English** · [Русский](README.ru.md)

# ghostdraft

Ephemeral scratchpad for sensitive text — part of the
[Paranoid Tools](../README.md) ecosystem.

Write or view a seed phrase, password or key so that once you close it, no copy is
left in the usual places (`~/.*_history`, tmp, recent docs, editor backups/viminfo).

[![CI](https://github.com/Di-kairos/paranoid-tools/actions/workflows/ci-ghostdraft.yml/badge.svg)](https://github.com/Di-kairos/paranoid-tools/actions/workflows/ci-ghostdraft.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![platform](https://img.shields.io/badge/platform-macOS-blue)
![windows](https://img.shields.io/badge/Windows-beta-orange)
![shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)

> **Status: early (v0.1.18).** `pipe` (view without writing to disk) and `new` (a draft
> in an open vault / RAM disk → `$EDITOR` → shred + clean editor traces on exit) are
> ready, including the optional `--clipboard` (dangerous, gated behind confirmation +
> auto-clear).

## Install

Checksum-verified install from the release tag — verify-then-run (don't trust, verify).
Piping a script into a shell means running code you haven't read, so prefer this:

```bash
base=https://github.com/Di-kairos/paranoid-tools/releases/download/ghostdraft-v0.1.19
curl -fsSLO "$base/install.sh"
curl -fsSLO "$base/SHA256SUMS"
curl -fsSLO "$base/SHA256SUMS.sig"
printf '%s\n' 'releases@paranoid-tools namespaces="file" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U' > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools -n file -s SHA256SUMS.sig < SHA256SUMS &&   # authenticity: Ed25519, pinned key
shasum -a 256 -c SHA256SUMS --ignore-missing &&   # integrity: verifies install.sh
less install.sh &&                               # read it — then run:
bash install.sh                                  # pulls ghostdraft + checksum, verifies, installs
```

Quick form (if you already trust the source):

```bash
curl -fsSL https://github.com/Di-kairos/paranoid-tools/releases/download/ghostdraft-v0.1.19/install.sh | bash
```

`install.sh` pulls the binary and `SHA256SUMS` from the immutable release tag and verifies
the hash **before** installing. Environment variables: `GHOSTDRAFT_VERSION` (pin a specific
tag instead of `latest`), `GHOSTDRAFT_DEST` (install path), `GHOSTDRAFT_BASE_URL` (override
the source for forks/tests).

> **Integrity vs authenticity (honest scope).** The checksum proves the binary matches the
> `SHA256SUMS` from the same release — it catches corruption and stops you running code off
> the moving `main` branch. Authenticity comes from the Ed25519
> signature over `SHA256SUMS`: the snippet above and `install.sh` both verify it against
> a key pinned in this repo, and the installer fails closed when it can't (see
> `SECURITY.md`). Residual risk: one project key signs all five tools — see the ecosystem
> [threat model](../THREAT-MODEL.md).

> The current public release is **v0.1.18** (signed, with `install.sh` + `SHA256SUMS`).
> Pin it for reproducibility with `GHOSTDRAFT_VERSION=0.1.18` instead of `latest`.

## Usage

```bash
ghostdraft new             # ephemeral draft in an open vault / RAM disk
ghostdraft new --clipboard # + copy to clipboard, auto-clear after N s (DANGEROUS, see below)
pbpaste | ghostdraft pipe  # view from the clipboard, write NOTHING to disk
ghostdraft version         # show the version (also -v / --version)
ghostdraft --help          # help (also -h)
```

**Exiting the default editor (vim).** `new` opens `vim` (with a soft-wrap, no-`.viminfo`
setup) when `$EDITOR` is unset. It opens **ready to type** — vim normally starts in normal mode,
where letters are commands and your text goes nowhere. To leave it: **`Ctrl-D`** saves and exits, **`Ctrl-X`** exits
without saving. Both work whether you are typing or not — you do not need `Esc` first, and an
always-visible hint line repeats them. `Esc` → `ZZ`/`ZQ` and `:wq` / `:q!` still work for those
who know vim; **F2/F3** are mapped too, but some terminals (e.g. Warp) swallow them before vim
sees them. Macro recording is switched off on purpose: a mistyped `ZQ` used to start it, and the
editor then looked frozen.

**Language.** Messages are English by default. Set `ST_LANG=ru` (the ecosystem-shared locale
variable, also honored by securetrash) — or a `ru*` system locale — to switch output to Russian.

## Architecture

- Single-file Bash, zero dependencies. Native macOS primitives (`hdiutil` for the RAM disk,
  `$EDITOR`/nano). `new` prefers to write **inside an open securetrash vault**.
- The shared core (`lib/common.sh`) is **vendored** inline from securetrash, pinned to a
  git ref; `tools/vendor-common.sh --check` catches drift in CI. See [`paranoid-tools/README.md`](../README.md).

## Where `new` writes the draft (by priority)

1. **`$GHOSTDRAFT_DIR`** — if set and writable (override for your own workflows; on-disk
   security is then your responsibility).
2. **An open securetrash vault** (`/Volumes/SecretVault`, overridable via `$ST_VAULT_VOLUME`)
   — encrypted; closing the vault gives crypto-shred.
3. **A RAM disk** (`hdiutil attach -nomount ram://` + HFS+) — lives in RAM, gone on detach at
   exit; not synced, never lands on the SSD.
4. **None of these available → refuse** (exit 3). It does NOT silently write to `/tmp` on APFS.

## Scope & limitations

Honesty about limits is the ecosystem's whole point — and it's especially easy to slip into
snake oil here, so we do **not** promise "zero traces":

- **macOS has no `/dev/shm`**; `/tmp` and `$TMPDIR` live on APFS (on disk). The only real
  in-memory location is a RAM disk (`hdiutil attach -nomount ram://`), which is what we use.
- **What we clean on exit:** the draft itself (`securetrash shred`, otherwise overwrite + rm),
  vim swap/undo (`.swp`/`.swo`/`.swn`/`.un~`), nano backups (`file~`), and detach of our own
  RAM disk.
- **What we cannot clean** (and say so honestly): terminal scrollback, the OS swap, and
  `~/.viminfo` (registers / last yank / search history). These are out of the tool's reach.
- **`--clipboard` is dangerous for a seed** (clipboard managers + Universal Clipboard sync the
  buffer to iCloud onto other devices) — it is OFF by default, requires confirmation when
  enabled; auto-clear after `${GHOSTDRAFT_CLIP_SECS:-20}`s, but only if the buffer hasn't
  changed, and it does NOT undo a copy already made.
- **Fallback shred on SSD is not a guarantee** (exactly what securetrash warns about); real
  erasure comes from RAM-disk detach or crypto-shred of a closed vault.

## Windows (beta)

A PowerShell port now exists in [`windows/README.md`](windows/README.md). It mirrors the
macOS flow with honest Windows substitutes: drafts go to the open vault when one is
mounted, otherwise to an owner-only on-disk temp dir with fallback shred (no RAM disk on
Windows — the port's README states this plainly), plus clipboard clearing and cleanup of
Notepad/editor backups and jump lists / recent.

> **Beta:** the Windows port is logic-tested (Pester on CI) but not yet validated on real
> Windows hardware. See [`windows/README.md`](windows/README.md).

## License

[MIT](LICENSE). Report security issues via [SECURITY.md](SECURITY.md); contributions via
[CONTRIBUTING.md](CONTRIBUTING.md).
