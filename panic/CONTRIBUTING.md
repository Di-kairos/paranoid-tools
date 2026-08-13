# Contributing to panic

Thanks for considering a contribution. panic is a small, deliberately honest
security tool — a one-step kill-switch that hides and locks. Please keep that
spirit when you propose changes: it must do exactly what it says, no more and
no less.

## Project principles (please don't break these)

1. **Honesty over comfort.** panic must never promise a guarantee it does not
   provide. It hides and locks — it does **not** destroy data or wipe swap, and
   the wording must stay accurate. If a change touches user-facing text about
   what panic does, keep it truthful (see the README "Scope & limitations").
2. **Zero runtime dependencies.** The tool is pure Bash on native macOS
   primitives (`hdiutil`, `pbcopy`, `CGSession`, `pkill`). A security tool
   should be readable end to end — don't add a runtime dependency without a
   strong reason and a discussion first.
3. **ShellCheck-clean, tested.** Every change ships green: ShellCheck clean and
   bats passing.

## Development setup

```bash
brew install bats-core shellcheck

shellcheck panic install.sh tools/vendor-common.sh   # lint — must be clean
bats test/                                            # unit tests
```

The bats suite drives panic against PATH stubs in `test/stubs/` (`hdiutil`,
`pbcopy`, `cgsession`, `pkill`, `uname`), so it runs without touching real
volumes or locking your screen — including on the Linux CI runner, where those
stubs stand in for the macOS primitives.

## Submitting changes

1. Fork, branch from `main` with a descriptive name (`fix/detach-mountpoint-spaces`).
2. Keep changes surgical — touch only what the change needs.
3. Match the existing style. Comments and docstrings in the codebase are in
   Russian; identifiers, filenames, branches, and commit messages are in English.
4. Use Conventional Commit prefixes (`feat:`, `fix:`, `docs:`, `refactor:`,
   `chore:`, `test:`) — see `git log` for the house style.
5. Make sure CI is green (ShellCheck + bats) before opening the PR.
6. In the PR description, say what you changed and how you verified it.

## Reporting a security issue

**Do not open a public issue for an exploitable vulnerability.** Use GitHub's
private reporting: *Security → Report a vulnerability* (draft advisory) on the
repository, so the issue can be fixed before disclosure. See `SECURITY.md`.
