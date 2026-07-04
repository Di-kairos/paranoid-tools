# Runbook — verify the Windows unmount-guard on real hardware

The unmount-guard (P2-4) auto-restores the Windows Search exclusion when a vault is
ejected **past** `vaultwatch stop`. Its logic is covered by Pester with mocked system
primitives; the *real* Task Scheduler polling + Search-attribute behavior can only be
confirmed on a live Windows box. This runbook is that confirmation. Until it passes,
treat the guard as **implemented but unverified on hardware**.

## Prerequisites

- Windows 10/11, **PowerShell 7+** (`pwsh -v`). vaultwatch hard-fails on 5.1.
- An **elevated** pwsh session (Task Scheduler registration + Search attribute).
- A test volume mounted at a drive letter — a mounted **VHDX** is ideal (create one in
  Disk Management → Action → Create VHD, init, format, note its letter, e.g. `V:\`).
  A BitLocker vault via `securetrash vault open` works too.

> Do this on a scratch volume, not real data. `-WhatIf` is not available here — the
> steps toggle the folder's `NotContentIndexed` attribute and register a scheduled task.

## 1 · Guard registers on start

```powershell
pwsh -File .\vaultwatch.ps1 start V:\
Get-ScheduledTask -TaskName 'vaultwatch-guard-*'      # → one task, State Ready
Get-Content "$env:USERPROFILE\.vaultwatch\sessions\*" # → line: guard_label=vaultwatch-guard-V__
(Get-Item V:\).Attributes                             # → includes NotContentIndexed
```
**Pass:** a `vaultwatch-guard-*` task exists, `guard_label=` is in the session file,
and the drive carries `NotContentIndexed`.

## 2 · Eject past stop → auto-restore (the headline behavior)

Eject the volume **without** running `vaultwatch stop`:
- VHDX: Disk Management → right-click the disk → **Detach VHD** (or eject via Explorer).
- BitLocker vault: eject the drive from Explorer.

Then **wait up to ~90 s** (polling interval is 1 min) and check:
```powershell
Get-ScheduledTask -TaskName 'vaultwatch-guard-*'      # → gone (guard removed itself via stop)
Get-Content "$env:USERPROFILE\.vaultwatch\sessions\*" # → no session file for the mount
```
Re-mount the same VHDX to the same letter and confirm indexing is no longer suppressed:
```powershell
(Get-Item V:\).Attributes                             # → NotContentIndexed is GONE
```
**Pass:** after the volume disappeared, the guard fired, the exclusion was removed, and
the session was cleared — with no manual `stop`.

## 3 · Normal stop is immediate and removes the guard

```powershell
pwsh -File .\vaultwatch.ps1 start V:\
pwsh -File .\vaultwatch.ps1 stop  V:\    # prints a session report immediately
Get-ScheduledTask -TaskName 'vaultwatch-guard-*'      # → gone at once (no polling wait)
(Get-Item V:\).Attributes                             # → NotContentIndexed removed
```
**Pass:** `stop` restores instantly and leaves no guard task behind.

## 4 · Cleanup / on failure

```powershell
Get-ScheduledTask -TaskName 'vaultwatch-guard-*','vaultwatch-ttl-*' |
  Unregister-ScheduledTask -Confirm:$false            # nuke any leftover tasks
```
If step 2 does **not** restore within ~2 min: capture
`Get-ScheduledTaskInfo -TaskName 'vaultwatch-guard-*'` (LastRunTime / LastTaskResult)
and the task's `-Argument`, and report back — the polling trigger or the `_guard_fire`
path needs adjustment for this Windows build.

## Result

- [ ] Step 1 pass — guard registers
- [ ] Step 2 pass — eject-past-stop auto-restores
- [ ] Step 3 pass — normal stop immediate + guard removed
- [ ] Tested on: Windows ____  · PowerShell ____  · volume type ____
