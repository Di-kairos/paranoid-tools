<div align="center">

**English** · [Русский](README.ru.md)

<img src="assets/logo.svg" alt="Paranoid Tools" width="620">

### Honest privacy &amp; security tools for macOS &amp; Windows — one job each, no snake oil.

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
&nbsp;![platform](https://img.shields.io/badge/platform-macOS%20%C2%B7%20Windows-blue)
&nbsp;![dependencies](https://img.shields.io/badge/dependencies-zero-success)
&nbsp;![releases](https://img.shields.io/badge/releases-Ed25519%20signed-blueviolet)
&nbsp;![tools](https://img.shields.io/badge/tools-5-informational)

**[Manifesto](MANIFEST.md)** &nbsp;·&nbsp; **[Tools](#the-tools)** &nbsp;·&nbsp; **[Install](#install)** &nbsp;·&nbsp; **[Launcher](#the-launcher)**

</div>

> **Don't trust, verify.** Ed25519-signed releases · zero runtime dependencies · one
> auditable file per tool · shellcheck-clean. Every limitation is stated plainly — see each
> tool's *Scope &amp; limitations*. No third-party audit is claimed; the code is small enough
> to read yourself.

An umbrella of small command-line tools around the **lifecycle of a secret**
(seed phrase / password / key). Each tool is its own git repo — a single-file
script (pure Bash on macOS/Linux, a PowerShell port on Windows) with **zero
runtime dependencies** — and is honest about the limits of what it can guarantee.
(seed phrase / password / key). Each tool is its own git repo — a single-file
script (pure Bash on macOS/Linux, a PowerShell port on Windows) with **zero
runtime dependencies** — and is honest about the limits of what it can guarantee.

## The tools

| # | Tool | Step in a secret's life | Platform | Latest |
|---|------|-------------------------|----------|--------|
| 1 | [`securetrash`](https://github.com/Di-kairos/securetrash) | store in an encrypted vault, then destroy | macOS · Windows (beta) | `v0.4.5` |
| 2 | [`vaultwatch`](https://github.com/Di-kairos/vaultwatch)   | guard a vault while it's open | macOS · Windows (beta) | `v0.1.3` |
| 3 | [`panic`](https://github.com/Di-kairos/panic)             | hide & lock everything, instantly | macOS · Windows (beta) | `v0.1.4` |
| 4 | [`ghostdraft`](https://github.com/Di-kairos/ghostdraft)   | write/view text leaving no disk trace | macOS · Windows (beta) | `v0.1.3` |
| 5 | [`seedsplit`](https://github.com/Di-kairos/seedsplit)     | split a secret into Shamir shares | macOS · Windows (beta) | `v0.3.2` |

> **Windows.** All five tools ship PowerShell ports (beta, Pester-tested in CI; seedsplit
> shares are byte-compatible with the macOS build). The macOS primitives — Spotlight, Time
> Machine, `launchd`, `hdiutil` — are mapped to their Windows equivalents (Windows Search,
> VSS, Task Scheduler, BitLocker), with the gaps reported honestly per tool.

Each tool ships an English `README.md` (Russian in `README.ru.md`), a
`CHANGELOG.md`, a checksum-verified and **Ed25519-signed** `install.sh`, CI +
release workflows, and a dedicated **Scope & limitations** section — read it
before you trust the tool.

## Install

Each tool installs independently with a verify-then-run script from its release
(see the tool's README). For personal use across all five at once, this repo
ships a local installer that puts every tool on your `PATH`:

```bash
git clone https://github.com/Di-kairos/paranoid-tools
cd paranoid-tools
bash install.sh            # installs all 5 into ~/.local/bin
bash install.sh --uninstall
```

> Note: `install.sh` copies the tool scripts from a working copy that already
> contains them (the maintainer's checkout). The five tools live in separate
> repos and are not vendored here, so a fresh clone of this repo has no tool
> scripts — `install.sh` would install nothing. Public users should install
> each tool via its own `curl … | bash` verify-then-run installer (linked above).

Plain-Russian usage guide: [КАК-ПОЛЬЗОВАТЬСЯ.ru.md](КАК-ПОЛЬЗОВАТЬСЯ.ru.md).

## The launcher

`paranoid` is an interactive launcher — a status dashboard plus a menu — over the
five CLIs. Pure Bash, zero dependencies, just like the tools it drives.

It holds no secrets and adds no crypto of its own: it runs the same signed tools
and shows their output — *Scope & limitations* and `check` verdicts included —
unaltered. Run it with no arguments:

```bash
paranoid          # opens the dashboard + menu
```

Honest note: the launcher is for convenience, not real-panic-speed. For an instant,
system-wide panic key, use `panic hotkey install` (a global hotkey via skhd — see panic's
README). An open vault is always flagged "at risk".
A Windows PowerShell mirror now ships at `windows/paranoid.ps1` (beta) — run it with
`pwsh -File windows/paranoid.ps1` (or drop it on PATH as `paranoid`); it drives the
same five PowerShell ports.

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

## License

[MIT](LICENSE). Each tool repo carries its own MIT `LICENSE`, plus `SECURITY.md`
(how to report a vulnerability privately) and `CONTRIBUTING.md`.
