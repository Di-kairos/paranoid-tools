# Paranoid Tools

**English** · [Русский](README.ru.md)

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![platform](https://img.shields.io/badge/platform-macOS-blue)
![dependencies](https://img.shields.io/badge/dependencies-zero-success)
![releases](https://img.shields.io/badge/releases-Ed25519%20signed-blueviolet)
![tools](https://img.shields.io/badge/tools-5-informational)

Honest privacy & security tools for macOS — one job each, no snake oil.

> **Why these tools exist →** [The Paranoid Tools Manifesto](MANIFEST.md)

An umbrella of small command-line tools around the **lifecycle of a secret**
(seed phrase / password / key). Each tool is its own git repo, a single-file
pure-Bash script with **zero runtime dependencies**, and is honest about the
limits of what it can guarantee.

## The tools

| # | Tool | Step in a secret's life | Platform | Latest |
|---|------|-------------------------|----------|--------|
| 1 | [`securetrash`](https://github.com/Di-kairos/securetrash) | store in an encrypted vault, then destroy | macOS · Windows (beta) | `v0.4.4` |
| 2 | [`vaultwatch`](https://github.com/Di-kairos/vaultwatch)   | guard a vault while it's open | macOS | `v0.1.2` |
| 3 | [`panic`](https://github.com/Di-kairos/panic)             | hide & lock everything, instantly | macOS · Windows (beta) | `v0.1.3` |
| 4 | [`ghostdraft`](https://github.com/Di-kairos/ghostdraft)   | write/view text leaving no disk trace | macOS | `v0.1.2` |
| 5 | [`seedsplit`](https://github.com/Di-kairos/seedsplit)     | split a secret into Shamir shares | macOS · Windows (beta) | `v0.3.2` |

> **Windows.** `securetrash`, `seedsplit` and `panic` ship PowerShell ports (beta,
> Pester-tested in CI; seedsplit shares are byte-compatible with the macOS build). The
> other two are macOS-native by design — they lean on Spotlight, Time Machine, `launchd`
> and `hdiutil`, which have no clean Windows equivalent.

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
