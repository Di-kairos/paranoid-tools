# Paranoid Tools

**English** · [Русский](README.ru.md)

Honest privacy & security tools for macOS — one job each, no snake oil.

An umbrella of small command-line tools around the **lifecycle of a secret**
(seed phrase / password / key). Each tool is its own git repo, a single-file
pure-Bash script with **zero runtime dependencies**, and is honest about the
limits of what it can guarantee.

## The tools

| # | Tool | Step in a secret's life | Status |
|---|------|-------------------------|--------|
| 1 | [`securetrash`](https://github.com/Di-kairos/securetrash) | store (encrypted vault) + destroy | v0.4.2 |
| 2 | [`vaultwatch`](https://github.com/Di-kairos/vaultwatch)   | guard an open vault | v0.1.1 |
| 3 | [`panic`](https://github.com/Di-kairos/panic)             | hide & lock everything, instantly | v0.1.1 |
| 4 | [`ghostdraft`](https://github.com/Di-kairos/ghostdraft)   | write/view text leaving no disk trace | v0.1.1 |
| 5 | [`seedsplit`](https://github.com/Di-kairos/seedsplit)     | split a secret into Shamir shares | v0.3.0 |

Each tool ships an English `README.md` (Russian in `README.ru.md`), a
`CHANGELOG.md`, a checksum-verified `install.sh`, CI + release workflows, and a
dedicated **Scope & limitations** section — read it before you trust the tool.

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

## Navigation graph

Each repo keeps its own graph (`<tool>/graphify-out/graph.json`). A cross-repo
graph is built by merging them:

```bash
bin/rebuild-graph.sh          # merges all tool graphs -> graphify-out/merged-graph.json
graphify path "A" "B" --graph graphify-out/merged-graph.json
```

## License

[MIT](LICENSE). Each tool repo carries its own MIT `LICENSE`, plus `SECURITY.md`
(how to report a vulnerability privately) and `CONTRIBUTING.md`.
