# Contributing to seedsplit

Thanks for considering a contribution. seedsplit is a small, deliberately honest
security tool — it splits a secret into N shares so that any T reconstruct it and
T-1 reveal **nothing**. Please keep that spirit when you propose changes.

## Project principles (please don't break these)

1. **Honesty over comfort.** The tool must never promise a guarantee it does not
   provide. Shares are only as safe as where you store them; the threshold guards
   against leakage of fewer than T shares, not against losing too many; there is
   no SLIP-39 / hardware-wallet interoperability yet. If a change touches
   user-facing wording about safety or guarantees, it has to stay accurate — see
   the README *Scope & limitations*.
2. **Zero runtime dependencies.** seedsplit is pure Bash, including the Shamir
   GF(256) arithmetic — no crypto library, no helper binaries. A security tool
   should be readable end to end. Don't add a runtime dependency without a very
   strong reason and a discussion first.
3. **ShellCheck-clean, tested.** Every change ships green: ShellCheck clean and
   bats passing.

## Development setup

```bash
brew install bats-core shellcheck

shellcheck seedsplit install.sh tools/vendor-common.sh   # lint — must be clean
bats test/                                               # unit tests
```

The bats suite (`test/seedsplit.bats`, `test/shamir.bats`) covers the CLI and the
secret-sharing round-trip (split → combine, threshold behaviour, corruption
refusal). seedsplit calls `require_macos`, so on the Linux CI the tests run with
PATH stubs that shim platform commands (`test/stubs/`, e.g. a `uname` stub) — that
lets the GF(256) math and share-format logic be validated on Linux without a real
macOS host.

## Submitting changes

1. Fork, branch from `main` with a descriptive name (`fix/combine-dup-share`).
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
