# vaultwatch on Windows (PowerShell, BETA)

A PowerShell port of [`vaultwatch`](../README.md) — an honest guard for an **open**
vault. Active only while the vault is mounted: it narrows the leak channels for the
exposed plaintext and restores everything when the vault closes.

> **BETA.** vaultwatch touches Windows Search, Task Scheduler, BitLocker and VSS, so
> the Pester suite covers the **orchestration** — session state on start/stop/status,
> TTL scheduling, restore, `_ttl_fire`, hook files — with those primitives mocked.
> Not yet broadly field-tested on real Search/VSS/Scheduler configurations.

> **Honest scope — read this.** vaultwatch makes *reversible* changes for the session
> and reports the limits it cannot close. On Windows the headline pieces are the
> **TTL auto-dismount** and **Windows Search exclusion**; backup snapshots and the
> pagefile it can only *report*, not scrub (see below).

## Install (verify-then-run)

Requires [PowerShell 7+](https://aka.ms/powershell) (`pwsh`). TTL auto-dismount and
BitLocker locking need an **elevated** session.

```powershell
irm https://github.com/Di-kairos/paranoid-tools/releases/download/vaultwatch-v0.1.16/install.ps1 -OutFile install.ps1
irm https://github.com/Di-kairos/paranoid-tools/releases/download/vaultwatch-v0.1.16/SHA256SUMS  -OutFile SHA256SUMS
# verify install.ps1's hash against SHA256SUMS, read the script, then:
pwsh -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

The installer verifies the SHA-256 of `vaultwatch.ps1` against the release `SHA256SUMS`
**before** installing (fail-closed), drops it into `%LOCALAPPDATA%\Programs\vaultwatch`,
writes a `vaultwatch.cmd` shim, and adds the folder to your user `PATH`.

## Commands

| Command | What it does |
|---------|--------------|
| `vaultwatch start [--ttl D] [--force] <mount>` | Guard an open vault: exclude it from Windows Search, check cloud-sync daemons, report VSS shadows. `--ttl D` schedules an auto-dismount after `D` (`30m`, `2h`, `45s`, `1d`); `--force` allows dismounting even with open files. |
| `vaultwatch status` | Show active sessions (read-only). |
| `vaultwatch stop <mount>` | Restore exactly what `start` changed and print a session report. |
| `vaultwatch install-hooks` / `uninstall-hooks` | Wire vaultwatch into the securetrash vault open/close hooks (managed `.cmd` files). |
| `vaultwatch version` | Show the version. |

```powershell
vaultwatch start --ttl 30m V:\    # guard the vault, auto-dismount in 30 min
vaultwatch status
vaultwatch stop V:\               # restore + report
```

`start`/`stop` are normally invoked by the securetrash vault open/close hooks.
`ST_LANG=ru` switches messages to Russian.

## What maps to what (macOS → Windows)

| macOS (bash) | Windows (this port) |
|--------------|---------------------|
| Spotlight off (`mdutil -i off`) | exclude folder from Windows Search (`NotContentIndexed` attribute) |
| `--ttl` auto-detach (launchd LaunchAgent) | one-shot **Task Scheduler** task → `vaultwatch _ttl_fire` |
| unmount-guard (launchd **WatchPaths**, event-driven) | unmount-guard (**Task Scheduler polling**, ~1 min) → `vaultwatch _guard_fire` |
| Time Machine exclusion (`tmutil addexclusion`) | **not done** — Windows can't cleanly exclude backups from CLI |
| `tmutil listlocalsnapshots` (report) | `vssadmin list shadows` (report VSS shadow copies) |
| cloud daemons (`pgrep` + folders) | `Get-Process` (OneDrive/Dropbox/GoogleDriveFS) + folder heuristic |
| `hdiutil detach` on TTL (`-force` only with `--force`) | `Lock-BitLocker` on TTL (`-ForceDismount` only with `--force`) |
| FileVault (`fdesetup`) | BitLocker (`Get-BitLockerVolume`) |
| swap (not addressed) | pagefile (not addressed) |

## Scope & limitations (honest)

- **Backup snapshots are reported, not removed.** Windows offers no clean CLI to
  exclude a path from File History / VSS, so vaultwatch only *reports* existing VSS
  shadow copies that may already hold plaintext — it does not delete them. The count is
  tri-state: when `vssadmin` cannot be read at all (it needs an administrator console, and
  it also fails with the service off) the report says **UNKNOWN**, never "none observed".
- **Pagefile (swap) is not addressed** — plaintext paged out can survive on disk.
- **Search exclusion** uses the `NotContentIndexed` folder attribute (reversible);
  it stops *future* content indexing, not anything already indexed.
- **TTL auto-dismount** needs an administrator console — `Lock-BitLocker` and the highest
  run level both require it, so `vaultwatch start` refuses without one rather than
  registering a guard that could never fire. `stop` and `status` need no rights.
  A busy mount is not dismounted unless the session was started with `--force`; the consent
  is given there, interactively, because the timer fires inside a Task Scheduler task with
  no console to ask at.
- **Unmount-guard is polling, not event-driven.** If the vault is ejected past
  `vaultwatch stop` (e.g. Explorer eject of the VHDX), a Task Scheduler task checks
  every ~1 minute and auto-restores the Search exclusion once the volume is gone. macOS
  restores instantly (launchd WatchPaths); Windows has up to ~1 min latency. Running
  `vaultwatch stop` yourself is still immediate.
- Cloud-sync detection is a heuristic (process + folder location), not telepathy.

## Tests

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -MinimumVersion 5.0.0
Invoke-Pester windows/test -Output Detailed
```

## See also

- macOS / Linux build: [`../README.md`](../README.md)
- Changelog: [`../CHANGELOG.md`](../CHANGELOG.md)
