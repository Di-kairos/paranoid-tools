# Contributing to ghostdraft

Thanks for considering a contribution. ghostdraft is a small, deliberately
honest security tool — it helps you write or view a secret without leaving a
copy in the usual places, and it's careful to never promise more than it can
deliver. Please keep that spirit when you propose changes.

## Project principles (please don't break these)

1. **Honesty over comfort.** The tool must never claim "zero traces" where the
   OS may keep a copy. Terminal scrollback, OS swap, and `~/.viminfo` are
   limitations it cannot scrub, and it says so on exit. If a change touches
   user-facing wording about traces, residue, or guarantees, it has to stay
   accurate. See the README "Scope & limitations" for the reasoning.
2. **Zero runtime dependencies.** ghostdraft is pure Bash, built on native
   macOS primitives (`hdiutil` for the RAM disk, `$EDITOR`/nano). A security
   tool should be readable end to end. Don't add a runtime dependency without a
   very strong reason and a discussion first.
3. **ShellCheck-clean, tested.** Every change ships green: ShellCheck clean and
   bats passing.

## Development setup

```bash
brew install bats-core shellcheck

shellcheck ghostdraft install.sh tools/vendor-common.sh   # lint — must be clean
bats test/                                                # unit tests
```

The bats suite avoids creating real RAM disks or touching a real vault. On the
Linux CI it runs via PATH stubs in `test/stubs/` (e.g. a stubbed `uname`), so
the macOS-only code paths can be exercised without a Mac. Keep new tests
stub-friendly and set `GHOSTDRAFT_DISABLE_RAM=1` where a test must not attach a
RAM disk.

## Vendored common

`ghostdraft` inlines the ecosystem's shared primitives (`lib/common.sh` from
securetrash) between `BEGIN/END vendored common` markers, pinned to a git ref.
Don't hand-edit that block — `tools/vendor-common.sh --check` verifies it hasn't
drifted from the pinned version, and CI runs that check.

## Submitting changes

1. Fork, branch from `main` with a descriptive name (`fix/ram-detach-leak`).
2. Keep changes surgical — touch only what the change needs.
3. Match the existing style. Comments and docstrings in the codebase are in
   Russian; identifiers, filenames, branches, and commit messages are in English.
4. Use Conventional Commit prefixes (`feat:`, `fix:`, `docs:`, `refactor:`,
   `chore:`, `test:`) — see `git log` for the house style.
5. Make sure CI is green (ShellCheck + bats + vendor-common check) before
   opening the PR.
6. In the PR description, say what you changed and how you verified it.

## Reporting a security issue

**Do not open a public issue for an exploitable vulnerability.** Use GitHub's
private reporting: *Security → Report a vulnerability* (draft advisory) on the
repository, so the issue can be fixed before disclosure. See `SECURITY.md`.
