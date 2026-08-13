# panic on Windows (PowerShell, BETA)

A PowerShell port of [`panic`](../README.md) — a one-step kill-switch that **hides
and locks** everything: locks unlocked BitLocker volumes, dismounts VeraCrypt
volumes, clears the clipboard, and locks the screen.

> **BETA.** `panic` is all side-effects (lock / dismount / kill), so the Pester
> suite covers the **orchestration** — what runs, how many times, and the `--hard`
> gate — with every system primitive mocked. What is *not* yet broadly field-tested:
> real BitLocker/VeraCrypt configurations, admin-rights edge cases, exotic locales.
> Run `panic status` first and try it on a throwaway volume before trusting it.

> **Honest scope.** `panic` HIDES and LOCKS — it does **not** destroy data or wipe
> the pagefile (use [`securetrash`](https://github.com/Di-kairos/securetrash) to
> destroy). Forced locking/dismount of a volume with open files may corrupt them —
> a deliberate panic trade-off (hiding matters more in the moment).

## Install (verify-then-run)

Requires [PowerShell 7+](https://aka.ms/powershell) (`pwsh`); Windows PowerShell 5.1
also runs the script. BitLocker locking needs an **elevated** session.

```powershell
irm https://github.com/Di-kairos/panic/releases/latest/download/install.ps1 -OutFile install.ps1
irm https://github.com/Di-kairos/panic/releases/latest/download/SHA256SUMS  -OutFile SHA256SUMS
# verify install.ps1's hash against SHA256SUMS, read the script, then:
pwsh -File install.ps1
```

The installer downloads `panic.ps1` + `SHA256SUMS` from the **release tag**, verifies
the SHA-256 **before** installing (fail-closed on mismatch or missing entry), drops
the script into `%LOCALAPPDATA%\Programs\panic`, writes a `panic.cmd` shim, and adds
that folder to your user `PATH`. Open a new terminal afterward so `PATH` refreshes.

## Commands

| Command | What it does |
|---------|--------------|
| `panic status` | Read-only preflight — show what `panic now` would lock/dismount/clear. Makes no changes. |
| `panic now [--hard]` | Lock BitLocker volumes, dismount VeraCrypt, clear clipboard, lock screen. `--hard` also kills cloud daemons (OneDrive/Dropbox/Google Drive) and clears recent items. |
| `panic version` | Show the version. |

```powershell
panic status        # always look first
panic now           # hide & lock
panic now --hard    # + kill cloud daemons, clear recent items
```

There is **no confirmation** — `panic now` is the panic path (speed over safety);
the guard against an accidental run is the explicit `now` verb. `ST_LANG=ru` switches
messages to Russian.

## What maps to what (macOS → Windows)

| macOS (bash) | Windows (this port) |
|--------------|---------------------|
| `hdiutil detach -force` (vault images) | `Lock-BitLocker -ForceDismount` + `VeraCrypt /d /f` |
| `pbcopy </dev/null` | `Set-Clipboard -Value ''` |
| `CGSession -suspend` | P/Invoke `user32!LockWorkStation` (not `rundll32` — its exit code says nothing about whether the screen locked) |
| `pkill` cloud daemons | `Stop-Process` (OneDrive, Dropbox, GoogleDriveFS) |
| sharedfilelist Recent items | `%APPDATA%\Microsoft\Windows\Recent` |
| `fdesetup status` (FileVault) | `Get-BitLockerVolume` (system drive) |

## Scope & limitations (honest)

- **Does not destroy.** `panic` hides and locks; it does not wipe data or the
  pagefile. For destruction use `securetrash`.
- **BitLocker locking** needs admin and only applies to **data** volumes with
  auto-unlock off (never the OS drive). No access / no module → skipped (best-effort).
- **VeraCrypt** needs `VeraCrypt.exe` on `PATH`. Absent → skipped (not an error).
- **Recent items** clears the *global* jump-list folder; per-app "recent" lists
  inside applications are not touched.
- Force-dismount may corrupt files that are open at the moment of panic.

## Tests

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -MinimumVersion 5.0.0
Invoke-Pester windows/test -Output Detailed
```

## See also

- macOS / Linux build: [`../README.md`](../README.md)
- Changelog: [`../CHANGELOG.md`](../CHANGELOG.md)
