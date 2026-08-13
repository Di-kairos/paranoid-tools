# Contributing to securetrash

Thanks for considering a contribution. securetrash is a small, deliberately
honest security tool — please keep that spirit when you propose changes.

## Project principles (please don't break these)

1. **Honesty over comfort.** The tool must never claim that overwriting securely
   shreds data on an SSD. If a change touches user-facing wording about
   shredding, erasure, or guarantees, it has to stay accurate. See the blog post
   in `docs/blog/` for the reasoning.
2. **Zero runtime dependencies.** The macOS core is pure Bash; the Windows port
   is pure PowerShell. A security tool should be readable end to end. Don't add a
   runtime dependency without a very strong reason and a discussion first.
3. **ShellCheck-clean, tested.** Every change ships green: ShellCheck clean,
   bats passing, Pester passing.

## Development setup

### macOS

```bash
brew install bats-core shellcheck

shellcheck securetrash install.sh   # lint — must be clean
bats test/securetrash.bats          # unit tests
```

Real vault smoke test (uses `hdiutil`, creates and destroys a throwaway vault):

```bash
export ST_VAULT_PASS=dev-test-pass ST_ASSUME_YES=1
./securetrash vault create 10m
./securetrash vault open
echo secret > /Volumes/SecretVault/s.txt
./securetrash vault close
./securetrash vault destroy
```

### Windows (PowerShell)

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -MinimumVersion 5.0.0
Invoke-Pester windows/test -Output Detailed
```

The Windows Pester suite runs against **mocked** Windows cmdlets — it validates
logic, not real BitLocker/VHDX behaviour. See the hardware-tester note below.

## Submitting changes

1. Fork, branch from `main` with a descriptive name (`fix/vault-close-race`).
2. Keep changes surgical — touch only what the change needs.
3. Match the existing style. Comments and docstrings in the codebase are in
   Russian; identifiers, filenames, branches, and commit messages are in English.
4. Use Conventional Commit prefixes (`feat:`, `fix:`, `docs:`, `refactor:`,
   `chore:`, `test:`) — see `git log` for the house style.
5. Make sure CI is green (ShellCheck + bats + Pester) before opening the PR.
6. In the PR description, say what you changed and how you verified it.

## Reporting a security issue

**Do not open a public issue for an exploitable vulnerability.** Use GitHub's
private reporting: *Security → Report a vulnerability* (draft advisory) on the
repository, so the issue can be fixed before disclosure.

## Windows hardware testing — help needed

The Windows port passes its logic tests and CI, but has **not been validated on
real hardware** against actual BitLocker and VHDX. This is the main gap before
the Windows port leaves beta.

If you have a real Windows machine with BitLocker available and can run a
short, scripted test of `vault create / open / close / destroy` and report what
happened — please open a **Windows hardware test report** issue (template
provided). That's a valuable contribution right now.
