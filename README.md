<div align="center">

**English** · [Русский](README.ru.md)

<img src="assets/logo.png" alt="Paranoid Tools" width="620">

### Honest privacy &amp; security tools for macOS &amp; Windows — one job each, no snake oil.

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
&nbsp;![platform](https://img.shields.io/badge/platform-macOS%20%C2%B7%20Windows-blue)
&nbsp;![dependencies](https://img.shields.io/badge/dependencies-zero-success)
&nbsp;![releases](https://img.shields.io/badge/releases-Ed25519%20signed-blueviolet)
&nbsp;![tools](https://img.shields.io/badge/tools-5-informational)

**[Manifesto](MANIFEST.md)** &nbsp;·&nbsp; **[Tools](#the-tools)** &nbsp;·&nbsp; **[Install](#install)** &nbsp;·&nbsp; **[Launcher](#the-launcher)**

<img src="assets/dashboard.svg" alt="The paranoid launcher: a status dashboard plus a menu over the five tools" width="560">

</div>

> **Don't trust, verify.** Ed25519-signed releases · zero runtime dependencies · one
> auditable file per tool · shellcheck-clean. Every limitation is stated plainly — see each
> tool's *Scope &amp; limitations*. No third-party audit is claimed; the code is small enough
> to read yourself.

An umbrella of small command-line tools around the **lifecycle of a secret**
(seed phrase / password / key). Each tool is its own git repo — a single-file
script (pure Bash on macOS, a PowerShell port on Windows) with **zero
runtime dependencies** — and is honest about the limits of what it can guarantee.

## The tools

| # | Tool | Step in a secret's life | Platform | Latest |
|---|------|-------------------------|----------|--------|
| 1 | [`securetrash`](https://github.com/Di-kairos/securetrash) | store in an encrypted vault, empty or destroy it | macOS · Windows (beta) | [![latest](https://img.shields.io/github/v/release/Di-kairos/securetrash?display_name=tag&label=&color=2ea44f)](https://github.com/Di-kairos/securetrash/releases/latest) |
| 2 | [`vaultwatch`](https://github.com/Di-kairos/vaultwatch)   | guard a vault while it's open | macOS · Windows (beta) | [![latest](https://img.shields.io/github/v/release/Di-kairos/vaultwatch?display_name=tag&label=&color=2ea44f)](https://github.com/Di-kairos/vaultwatch/releases/latest) |
| 3 | [`panic`](https://github.com/Di-kairos/panic)             | hide & lock everything, instantly | macOS · Windows (beta) | [![latest](https://img.shields.io/github/v/release/Di-kairos/panic?display_name=tag&label=&color=2ea44f)](https://github.com/Di-kairos/panic/releases/latest) |
| 4 | [`ghostdraft`](https://github.com/Di-kairos/ghostdraft)   | write/view text without leaving copies in the usual places | macOS · Windows (beta) | [![latest](https://img.shields.io/github/v/release/Di-kairos/ghostdraft?display_name=tag&label=&color=2ea44f)](https://github.com/Di-kairos/ghostdraft/releases/latest) |
| 5 | [`seedsplit`](https://github.com/Di-kairos/seedsplit)     | split a secret into Shamir shares (+ passphrase) | macOS · Windows (beta) | [![latest](https://img.shields.io/github/v/release/Di-kairos/seedsplit?display_name=tag&label=&color=2ea44f)](https://github.com/Di-kairos/seedsplit/releases/latest) |

> **Windows.** All five tools ship PowerShell ports (beta, Pester-tested in CI; seedsplit
> shares are byte-compatible with the macOS build). The macOS primitives — Spotlight, Time
> Machine, `launchd`, `hdiutil` — are mapped to their Windows equivalents (Windows Search,
> VSS, Task Scheduler, BitLocker), with the gaps reported honestly per tool.

Each tool ships an English `README.md` (Russian in `README.ru.md`), a
`CHANGELOG.md`, a checksum-verified and **Ed25519-signed** `install.sh`, CI +
release workflows, and a dedicated **Scope & limitations** section — read it
before you trust the tool.

## Install

One command installs all five tools plus the launcher into `~/.local/bin`:

```bash
git clone https://github.com/Di-kairos/paranoid-tools
cd paranoid-tools
bash install.sh            # installs all 5 + the paranoid launcher
```

On a fresh clone each tool is pulled from its own **signed release** with verify-then-run:
the installer checks the Ed25519 signature over `SHA256SUMS`, then the checksum of the
tool's own `install.sh`, and only then runs it — which in turn verifies the binary before
installing. So every artifact pulled from the network — a tool's own `install.sh` and its
binary — is verified before it runs (you launch the top-level `bash install.sh` yourself,
after reading it). Pin a version with, e.g., `PT_PANIC_VERSION=0.1.7`; change the target dir
with `PT_DEST=/usr/local/bin`.

Prefer to install just one tool, or inspect each step by hand? Every tool's README carries a
standalone verify-then-run snippet plus a one-line quick form. See [the tools](#the-tools).

### Uninstall

```bash
bash install.sh --uninstall   # remove all tools and the launcher
```

### Windows

The one-line `install.sh` above is macOS only. On Windows it's a few short steps — here's
the whole thing from scratch. Steps **1–2 you do once**; step 3 you repeat per tool.

**1. Install PowerShell 7.** The supported path for install and run is PowerShell 7 (`pwsh`);
the built-in Windows PowerShell 5.1 is not officially supported. In any terminal (press `Win`,
type "PowerShell", Enter):

```powershell
winget install --id Microsoft.PowerShell -e
```

Close that window, then open **"PowerShell 7"** from the Start menu. Confirm the version:

```powershell
pwsh --version      # should print "PowerShell 7.x"
```

**2. Install Git** (used to download a tool), then open a fresh PowerShell 7 window:

```powershell
winget install --id Git.Git -e
```

**3. Install a tool.** Each tool is its own repo — install the ones you want. Example for
`securetrash` (swap the name for `vaultwatch`, `panic`, `ghostdraft`, or `seedsplit`):

```powershell
git clone https://github.com/Di-kairos/securetrash
cd securetrash
pwsh -File windows/install.ps1
```

`install.ps1` downloads the signed release, **verifies its Ed25519 signature and checksum before
installing anything** (and refuses to install if either fails), copies the tool into
`%LOCALAPPDATA%\Programs\securetrash`, and adds it to your PATH automatically.

**4. Use it.** Open a **new** PowerShell window (so the PATH change takes effect), then call the
tool by name:

```powershell
securetrash version
securetrash --help
```

Repeat step 3 for each tool. The `paranoid` menu-launcher also has a Windows version: clone this
repo (`git clone https://github.com/Di-kairos/paranoid-tools`) and run
`pwsh -File windows/paranoid.ps1`.

> **Beta.** The Windows ports are logic-tested in CI but not yet broadly validated on real
> hardware — try them on non-critical data first before trusting them with real secrets.

### Release signing — honest scope

Releases are signed with a **single Ed25519 key** shared across all five tool repos. Be aware
of the trade-off: compromise of that key (its GitHub Actions secret, or a malicious change to
any repo's `release.yml`) would let an attacker sign a forged release for the **whole
ecosystem**, and the public key is pinned in the installers so there is no in-band revocation
today. The signature still defeats an attacker who only controls the download path (mirror,
CDN, MITM) — which is the common case. Hardening this to **per-repo keys / OIDC-based signing
with a documented rotation & revocation path** is tracked work, not yet shipped. If you need
maximum assurance, pin an exact version and check its `SHA256SUMS` against an independent copy.

### Updating

There is no `update` command — updating means **re-running the installer**. It pulls each
tool's latest signed release and overwrites the binary in place:

```bash
cd paranoid-tools
git pull            # refresh the clone (launcher + installer)
bash install.sh     # reinstall all tools at their latest signed releases
```

Check a tool's version with `securetrash version` (or `--version` on any tool). If a tool's
runtime behavior changed in the update (e.g. `securetrash vault` now mounts the volume
visibly in Finder), an already-open session keeps the old code — reopen it: `securetrash
vault close` then `securetrash vault open`.

**Staying notified.** There's no telemetry and nothing phones home, so a new version won't
find you — you check for it. Cheapest and privacy-clean: on GitHub press **Watch ▸ Custom ▸
Releases** on [paranoid-tools](https://github.com/Di-kairos/paranoid-tools) (and on any
single-tool repo you rely on) — GitHub emails you on every release. The **Latest** badges in
the tools table always show the current release; compare them with your local `<tool>
version`. Installed a tool via Homebrew? `brew upgrade` picks up the new formula. The
`paranoid` launcher also shows an opt-in "update available" line on its dashboard — see
[The launcher](#the-launcher).

Usage guides: **[English](GUIDE.md)** · [Русский](ИНСТРУКЦИЯ.md).

## The launcher

`paranoid` is an interactive launcher — a status dashboard plus a menu — over the
five CLIs. Pure Bash, zero dependencies, just like the tools it drives. The menu is
grouped into submenus — **Vault** (open/close · empty · destroy · watch), **Notepad**
(ghostdraft), **Secrets** (seedsplit) — with *Status* and one-key *PANIC* kept at the top.
**Empty** crypto-shreds the vault's contents and hands you a fresh empty one (a real
guarantee, unlike wiping files in place on an SSD).

It holds no secrets and adds no crypto of its own: it runs the same signed tools
and shows their output — *Scope & limitations* and `check` verdicts included —
unaltered. Run it with no arguments:

```bash
paranoid          # opens the dashboard + menu
```

<div align="center">
<img src="demo/demo.gif" alt="paranoid launcher: live status dashboard, then a read-only check, all from one menu" width="720">
</div>

Honest note: the launcher is for convenience, not real-panic-speed. For an instant,
system-wide panic key, use `panic hotkey install` (a global hotkey via skhd — see panic's
README). An open vault is always flagged "at risk".
A Windows PowerShell mirror now ships at `windows/paranoid.ps1` (beta) — run it with
`pwsh -File windows/paranoid.ps1` (or drop it on PATH as `paranoid`); it drives the
same five PowerShell ports.

**Opt-in update check.** Off by default — nothing on the dashboard touches the network unless
you ask. Set `PARANOID_UPDATE_CHECK=1` and the dashboard adds an *"update available"* line when
an installed tool has a newer signed release. It's the only network call the launcher makes: a
single redirect lookup per tool against GitHub's `releases/latest` (no API key, no telemetry),
cached for 24h. Enable it for a session with `PARANOID_UPDATE_CHECK=1 paranoid`, or export it in
your shell rc to keep it on.

## How it fits together

- **Separate repos + vendoring.** The shared code is the canonical
  `securetrash/lib/common.sh`, vendored inline into each tool between
  `# === BEGIN vendored common (pin: <ref>) ===` markers. A sync script + a CI
  drift check keep copies honest. No runtime dependency, no build step.
- **Vault hooks.** `securetrash vault open/close` fire
  `~/.securetrash/hooks/{post-open,post-close}`; `vaultwatch`/`panic` hook into
  the container's lifecycle through them.
- **The ecosystem law.** One tool = one job. Every README must carry an honest
  *Scope & limitations* section. Never manufacture a false sense of security.

## Support

Paranoid Tools is free and open-source (MIT). If it saved you from a leak — or you just
want the work to continue — you can support it via **[GitHub Sponsors](https://github.com/sponsors/Di-kairos)**.
No paywalls, no telemetry, no upsell: the tools stay fully usable without paying. Sponsorship
funds maintenance and the optional convenience layer (the native menu-bar / tray, Phase B).

## License

[MIT](LICENSE). Each tool repo carries its own MIT `LICENSE`, plus `SECURITY.md`
(how to report a vulnerability privately) and `CONTRIBUTING.md`.
