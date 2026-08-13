# ghostdraft on Windows (PowerShell, BETA)

A PowerShell port of [`ghostdraft`](../README.md) — write or view a secret (seed /
password / key) so that as few traces as possible survive afterward.

> **BETA.** ghostdraft touches the outside world (editor, shred, clipboard), so the
> Pester suite covers the **orchestration** — directory choice, ordering, shred-runs-
> in-finally, the `--clipboard` gate — with those primitives mocked. Not yet broadly
> field-tested: exotic editors, locales, real vault drives.

> **Honest scope — read this.** Windows has **no built-in RAM disk** (unlike macOS
> `hdiutil ram://`). So the only place a draft is *truly* ephemeral is **inside an
> open [`securetrash`](https://github.com/Di-kairos/securetrash) vault** (a BitLocker
> VHDX — closing it crypto-shreds the contents). With **no vault open**, ghostdraft
> falls back to an **on-disk temp file** (ACL-locked to you) and best-effort
> overwrite-shred — which is **not a guarantee on an SSD** (wear-leveling). For a real
> guarantee, open a vault first.

## Install (verify-then-run)

Requires [PowerShell 7+](https://aka.ms/powershell) (`pwsh`); Windows PowerShell 5.1
also runs the script.

```powershell
irm https://github.com/Di-kairos/ghostdraft/releases/latest/download/install.ps1 -OutFile install.ps1
irm https://github.com/Di-kairos/ghostdraft/releases/latest/download/SHA256SUMS  -OutFile SHA256SUMS
# verify install.ps1's hash against SHA256SUMS, read the script, then:
pwsh -File install.ps1
```

The installer downloads `ghostdraft.ps1` + `SHA256SUMS` from the **release tag**,
verifies the SHA-256 **before** installing (fail-closed on mismatch or missing entry),
drops the script into `%LOCALAPPDATA%\Programs\ghostdraft`, writes a `ghostdraft.cmd`
shim, and adds that folder to your user `PATH`. Open a new terminal afterward.

## Commands

| Command | What it does |
|---------|--------------|
| `ghostdraft new [--clipboard]` | Edit an ephemeral draft (in an open vault, or an on-disk fallback), then shred it and clean editor backups on exit. `--clipboard` copies the result to the clipboard (off by default, with a warning). |
| `ghostdraft pipe` | Read stdin, print it to the terminal, write **nothing** to disk. |
| `ghostdraft version` | Show the version. |

```powershell
Get-Clipboard | ghostdraft pipe     # view without writing to disk
ghostdraft new                      # edit a draft (vault if open, else on-disk fallback)
```

The editor is `$env:EDITOR` (default `notepad`). `ST_LANG=ru` switches messages to
Russian. Draft location priority: `GHOSTDRAFT_DIR` (your override) → open securetrash
vault (`ST_VAULT_VOLUME`, default `V:\`) → on-disk secure-temp fallback.

## What maps to what (macOS → Windows)

| macOS (bash) | Windows (this port) |
|--------------|---------------------|
| RAM disk (`hdiutil ram://`) | **none** — on-disk temp file (ACL-locked), loudly flagged |
| open vault under `/Volumes` | open securetrash vault drive (`V:\`) |
| `securetrash shred` / overwrite+`rm` | `securetrash shred` / overwrite + `Remove-Item` |
| `pbcopy` / `pbpaste` | `Set-Clipboard` / `Get-Clipboard` |
| iCloud Universal Clipboard risk | Windows Cloud Clipboard + Win+V history |
| `~/.viminfo`, swap, scrollback (unscrubbable) | `~/.viminfo`, pagefile, console scrollback (unscrubbable) |

## Scope & limitations (honest)

- **No RAM disk on Windows.** The no-vault fallback is on disk; shred is best-effort
  (no guarantee on SSD). Open a securetrash vault for a real crypto-shred.
- **Cannot scrub:** console scrollback, the OS pagefile (swap), and a vim `~/.viminfo`
  if you used vim. Listed, not hidden.
- **`--clipboard` is dangerous:** clipboard history (Win+V) keeps copies and Cloud
  Clipboard syncs to your Microsoft account. There is **no background auto-clear** on
  Windows (clipboard cmdlets need an STA thread a background job can't give) — clear it
  yourself. Off by default.

## Tests

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -MinimumVersion 5.0.0
Invoke-Pester windows/test -Output Detailed
```

## See also

- macOS / Linux build: [`../README.md`](../README.md)
- Changelog: [`../CHANGELOG.md`](../CHANGELOG.md)
