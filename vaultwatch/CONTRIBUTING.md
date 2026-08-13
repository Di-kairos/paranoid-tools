# Contributing to vaultwatch

Thanks for considering a contribution. vaultwatch is a small, deliberately
honest security tool — it watches an *open* vault, narrows the channels through
which plaintext can leak, and restores exactly what it changed on close. Please
keep that spirit when you propose changes.

## Project principles (please don't break these)

1. **Honesty over comfort.** The tool must never claim a guarantee it doesn't
   provide. It does not close swap, does not delete pre-existing Time Machine
   snapshots, and does not touch cloud settings — and the session report says so
   out loud. If a change touches user-facing wording about what is contained,
   excluded, or restored, it has to stay accurate. See the README
   "Scope & limitations".
2. **Zero runtime dependencies.** The tool is pure Bash on native macOS
   primitives (`mdutil`, `tmutil`, `hdiutil`, `lsof`, `launchd`). A security
   tool should be readable end to end. Don't add a runtime dependency without a
   very strong reason and a discussion first.
3. **ShellCheck-clean, tested.** Every change ships green: ShellCheck clean and
   bats passing.

## Development setup

```bash
brew install bats-core shellcheck

shellcheck vaultwatch install.sh tools/vendor-common.sh   # lint — must be clean
bats test/                                                # unit tests
```

The bats suite runs on Linux CI as well as macOS: macOS-only commands
(`hdiutil`, `mdutil`, `tmutil`, `launchctl`, `lsof`, `pgrep`, `uname`) are
shimmed by the PATH stubs in `test/stubs`, so the watch/TTL logic is validated
without touching real volumes or system indexing state.

## Submitting changes

1. Fork, branch from `main` with a descriptive name (`fix/ttl-detach-race`).
2. Keep changes surgical — touch only what the change needs.
3. Match the existing style. Comments and docstrings in the codebase are in
   Russian; identifiers, filenames, branches, and commit messages are in English.
4. Use Conventional Commit prefixes (`feat:`, `fix:`, `docs:`, `refactor:`,
   `chore:`, `test:`) — see `git log` for the house style.
5. Make sure CI is green (ShellCheck + bats) before opening the PR.
6. In the PR description, say what you changed and how you verified it.

## A note on the vendored common block

`vaultwatch` vendors the ecosystem's shared primitives inline from securetrash's
`lib/common.sh`, pinned to a git ref, between the
`BEGIN/END vendored common` markers. Don't edit that block by hand — change the
canonical source in securetrash and re-vendor. `tools/vendor-common.sh --check`
catches drift in CI.

## Reporting a security issue

**Do not open a public issue for an exploitable vulnerability.** Use GitHub's
private reporting: *Security → Report a vulnerability* (draft advisory) on the
repository, so the issue can be fixed before disclosure. See `SECURITY.md`.
