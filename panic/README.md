**English** · [Русский](README.ru.md)

# panic

One-step kill-switch — everything off the screen, vaults locked, one command.

[![CI](https://github.com/Di-kairos/panic/actions/workflows/ci.yml/badge.svg)](https://github.com/Di-kairos/panic/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![platform](https://img.shields.io/badge/platform-macOS-blue)
![windows](https://img.shields.io/badge/Windows-beta-orange)
![shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)

Part of the [Paranoid Tools](https://github.com/Di-kairos/paranoid-tools) ecosystem.

The scenario: a border crossing, coercion, "someone's coming." A single
`panic now` (or a global hotkey via `panic hotkey`, default `cmd + alt - p`) **hides and locks** everything:
force-detaches mounted volumes (including open vault disk images), clears the
clipboard, and locks the screen.

## Install

Checksum-verified install from the release tag — verify-then-run (don't trust, verify):

```bash
base=https://github.com/Di-kairos/panic/releases/latest/download
curl -fsSLO "$base/install.sh"
curl -fsSLO "$base/SHA256SUMS"
curl -fsSLO "$base/SHA256SUMS.sig"
printf '%s\n' 'releases@paranoid-tools namespaces="file" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U' > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools -n file -s SHA256SUMS.sig < SHA256SUMS &&   # authenticity: Ed25519, pinned key
shasum -a 256 -c SHA256SUMS --ignore-missing &&   # integrity: verifies install.sh
less install.sh &&                               # read it — then run:
bash install.sh                                  # pulls panic + checksum, verifies, installs
```

Quick form (one line, **skips verification** — choose deliberately):

```bash
curl -fsSL https://github.com/Di-kairos/panic/releases/latest/download/install.sh | bash
```

`install.sh` pulls the binary and `SHA256SUMS` from the immutable release tag (not the
moving `main` branch) and verifies the hash **before** installing. Environment variables:
`PANIC_VERSION` (pin a specific tag instead of `latest`), `PANIC_DEST` (install path),
`PANIC_BASE_URL` (override the source entirely, for forks/tests).

> **Integrity vs authenticity (honest scope).** The checksum proves the binary matches the
> `SHA256SUMS` published in the *same release* — it catches corruption, partial/cached
> tampering, and stops you running code off the moving `main` branch. Authenticity comes from the
> Ed25519 signature over `SHA256SUMS`: the snippet above and `install.sh` both verify it
> against a key pinned in this repo, and the installer fails closed when it can't (see
> `SECURITY.md`). Residual risk: one project key signs all five tools — see the ecosystem
> [threat model](https://github.com/Di-kairos/paranoid-tools/blob/main/THREAT-MODEL.md). Pin a
> specific version with `PANIC_VERSION=0.1.15` instead of `latest` for reproducibility.

## Usage

```bash
panic status            # read-only preflight: show what `panic now` would affect
panic now               # hide & lock now
panic now --hard        # + kill cloud daemons, clear Recent items
panic hotkey install    # bind a global hotkey (cmd + alt - p) to `panic now`
panic hotkey status     # is the hotkey installed?
panic hotkey uninstall  # remove it (only the block panic manages)
panic version           # print the version (also -v / --version)
panic --help            # print usage (also -h / help)
```

The explicit `now` verb is deliberate: a kill-switch must not fire from an accidental
bare `panic` with no arguments (bare `panic` prints usage and exits non-zero).

`ST_LANG=ru` switches messages to Russian (otherwise `en`, or auto-detected from the
system locale).

What `panic now` does:

1. detaches every mounted disk image under `/Volumes` (`hdiutil detach -force`);
2. clears the clipboard (`pbcopy </dev/null`);
3. locks the screen (`CGSession -suspend` — the real login window; falls back to
   Ctrl+Cmd+Q via `osascript` on macOS ≥12, where the legacy `CGSession` bundle is gone).

With `--hard` it additionally kills cloud daemons (Dropbox, OneDrive, iCloud's `bird`,
Google Drive) and clears the global Recent items (shared file lists).

### Global hotkey

For true one-step activation, bind a system-wide hotkey to `panic now`:

```bash
panic hotkey install                 # default: cmd + alt - p
panic hotkey install "cmd + shift - escape"   # or pick your own combo
panic hotkey status                  # show the current binding
panic hotkey uninstall               # remove it
```

A real global hotkey on macOS needs a resident listener with Accessibility permission —
pure Bash can't do it. `panic hotkey` uses [`skhd`](https://github.com/koekeishiya/skhd),
a tiny hotkey daemon (`brew install skhd`). The binding lives in a clearly-marked managed
block of your `skhdrc`, so your own skhd bindings are left untouched. On first trigger,
grant skhd access under **System Settings → Privacy & Security → Accessibility**, or the
hotkey won't fire.

> **`panic hotkey` is macOS-only, and that is a decision, not a gap in the queue.** It is bound
> through skhd; Windows has no counterpart, and panic will not leave a background process
> resident just to watch the keyboard. Windows already binds hotkeys where they belong — on the
> shortcut: make a shortcut to `panic.cmd`, open Properties, click into *Shortcut key* and press
> `Ctrl+Alt+P`. Running `panic hotkey` on Windows prints exactly this instead of pretending the
> command does not exist.

## How it works

- Single-file Bash, zero dependencies. Native macOS primitives only (`hdiutil`,
  `pbcopy`, `CGSession` for the screen lock).
- The shared core (`lib/common.sh`) is **vendored** inline from securetrash, pinned to a
  git ref; `tools/vendor-common.sh --check` catches drift in CI. See
  [`paranoid-tools/README.md`](https://github.com/Di-kairos/paranoid-tools).
- Force-detaches mounted disk images under `/Volumes` directly (`hdiutil detach -force`) — it
  does **not** call vaultwatch or run securetrash's vault-close hooks/state restore. Fast and
  blunt by design; the trade-off (a forced detach can lose unsaved writes) is stated below.

## Scope & limitations

Honesty about the limits is the whole point of the ecosystem. panic **hides and locks**,
but:

- It does **not destroy** data and does **not wipe swap** (use `securetrash` to destroy);
  plaintext fragments may already have spilled into swap and stay there until overwritten.
- `detach -force` can **corrupt data** if files are open — a deliberate panic-mode
  trade-off (hiding matters more), and you should know it. There is no confirmation prompt:
  speed wins; the guard against accidental runs is the explicit `now` verb.
- It detaches **disk images under `/Volumes`** (vaults/dmg); system images mounted outside
  `/Volumes` are left untouched. Physical external drives are a later pack.
- `--hard` clears **global** Recent items (shared file lists); per-app "recents" stored
  inside individual apps are **not** wiped by this — honest about the limit.
- The screen lock tries `CGSession -suspend` (the real login window, independent of the
  "require password" setting), then falls back to Ctrl+Cmd+Q via `osascript` on modern
  macOS (≥12, where the legacy `CGSession` bundle is gone). The fallback needs Accessibility
  access for your terminal; if **both** methods fail, panic does **not** claim the screen is
  locked — it warns loudly and tells you to lock it yourself. Overridable via
  `PANIC_CGSESSION` / `PANIC_OSASCRIPT`.
- It does not pretend to "fully wipe in a second" — that would be a lie.

## Windows (beta)

A PowerShell port now exists in [`windows/README.md`](windows/README.md). It mirrors the
macOS logic — lock the workstation, dismount BitLocker/VeraCrypt volumes, and clear the
clipboard.

> **Beta:** the Windows port is logic-tested (Pester on CI) but not yet validated on real
> Windows hardware. See [`windows/README.md`](windows/README.md).

## License

Released under the [MIT](LICENSE) license — provided "as is," without warranty of any kind
(see the license file). Report a vulnerability via [SECURITY.md](SECURITY.md). Contributions
are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
