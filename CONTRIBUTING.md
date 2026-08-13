# Contributing to Paranoid Tools

This is a monorepo: the `paranoid` launcher (bash + PowerShell), the installer, the
GUI wrappers, the shared documentation — and the five tools, one directory each
(`securetrash/`, `vaultwatch/`, `panic/`, `ghostdraft/`, `seedsplit/`), every tool
with its own `CONTRIBUTING.md`, its own CI (`ci-<tool>.yml`) and its own
independently versioned releases (`<tool>-vX.Y.Z` tags). A change to a tool belongs
in its directory and follows its `CONTRIBUTING.md`; a change to the launcher, the
installer, the guides or the GUI follows this one.

**Every change clears the same gates, whoever wrote it** — shellcheck, bats, Pester,
the differential crypto tests. Those gates, not the author, are what you should trust.

## Principles (please don't break these)

1. **Honesty over comfort.** Nothing here may claim a guarantee the platform cannot
   give — no "100% unrecoverable" where an SSD, a snapshot or a cloud client can keep
   a copy. If a change touches wording about erasure, encryption or guarantees, it has
   to stay accurate, in both languages.
2. **The launcher stays thin.** It holds no secrets and adds no crypto of its own: it
   runs the five signed CLIs and shows their output verbatim, including every caveat.
   New behavior belongs in a tool, not in the menu.
3. **Zero runtime dependencies.** Pure bash on macOS, PowerShell 7 on Windows. The
   named exceptions (`skhd` for `panic hotkey`, `openssl` for `seedsplit -p`) are
   opt-in and documented; adding another one needs a discussion first.
4. **Green before merge.** ShellCheck clean, bats passing, Pester passing.
5. **Both languages move together.** Every user-facing string exists in English and
   Russian. A fact stated in one guide and missing from the other is a bug.

## Development setup

```bash
brew install bats-core shellcheck        # macOS
shellcheck -S style paranoid install.sh  # lint — must be clean
bats test/                               # launcher + installer tests
```

Windows-side logic (`windows/paranoid.ps1`, `gui/windows/paranoid-tray.ps1`) is tested
with Pester and runs cross-platform under PowerShell 7:

```bash
pwsh -NoProfile -Command 'Invoke-Pester -Path windows/test'
pwsh -NoProfile -Command 'Invoke-Pester -Path gui/windows/test'
```

The macOS GUI has a compile-and-selftest gate:

```bash
gui/macos/test.sh
```

End-to-end checks that touch the real system (installing the tools, creating a vault)
are described in [`docs/TESTING.md`](docs/TESTING.md). To verify the published releases
without installing anything: `bash verify-releases.sh`.

## Commits and pull requests

- Conventional prefixes (`feat:`, `fix:`, `docs:`, `chore:`), subject in English.
- One logical change per commit; say *why* in the body, not just *what*.
- Describe how you tested it. "Tests pass" is not a description.
- Destructive paths (anything that deletes, unmounts or overwrites) need a test that
  proves the failure mode is handled, not only the happy path.

## Reporting a vulnerability

Please **do not** open a public issue. See [`SECURITY.md`](SECURITY.md).
