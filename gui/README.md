# Paranoid Tools — GUI (Phase B)

Native **menu-bar (macOS)** and **system-tray (Windows)** agents over the same signed CLIs.
This is the optional *convenience* layer — Phase A is the cross-platform `paranoid` TUI launcher
(repo root). Phase B adds a one-glance status indicator + quick actions without opening a terminal.

## Honesty (same contract as Phase A)

The GUI **holds no secrets and adds no crypto**. It only:
- shows read-only status (vault open/closed, FileVault/BitLocker) in the menu bar / tray, and
- launches the **same signed CLIs** (`securetrash`, `panic`, `paranoid`) — every destructive op
  and every password prompt happens **in the CLI** (a terminal/console window opens with the
  tool's real output); secrets never pass through the GUI.

So the GUI cannot weaken the tools' guarantees: it is a launcher, not a new tool.

## What's here (this commit)

| Platform | File | Status |
|----------|------|--------|
| macOS | `macos/ParanoidBar.swift` + `macos/build.sh` | **Source compiles** with `swiftc` (Command Line Tools). AppKit `NSStatusItem` menu-bar agent: live vault/FileVault status, Status/PANIC/Vault▸(open·close·empty·destroy)/launcher, runs CLIs via Terminal. |
| Windows | `windows/paranoid-tray.ps1` (+ Pester) | **Runnable PowerShell** (no compile). `NotifyIcon` tray, same menu, runs CLIs in a new console. Menu/status logic Pester-tested (8/8). |

Verified here: macOS source compiles cleanly (`swiftc -O`); Windows tray parses and its menu/dispatch
logic passes Pester. The two mirror each other and the bash launcher's grouping.

## Build / run

**macOS**
```bash
cd macos
./build.sh            # → ./ParanoidBar  (run it: a 🔒 appears in the menu bar)
./build.sh --bundle   # → ParanoidBar.app (LSUIElement: menu-bar agent, no Dock icon)
```

**Windows**
```powershell
pwsh -File windows/paranoid-tray.ps1   # a Shield icon appears in the tray; right-click for the menu
```

## Not done yet (honest scope — the rest of Phase B)

- **Code signing + notarization + packaging** (macOS `.app` → Developer ID + `notarytool` + staple;
  Windows tray → signed `.exe`/MSIX or a signed launch shim). Needs an **Apple Developer account** and
  a Windows code-signing cert — a distribution step, not a code step.
- **Auto-start at login** (LaunchAgent / Startup), custom monochrome status glyphs, richer status
  (vaultwatch session + TTL countdown), and a settings pane.
- **Open-core packaging** (the convenience layer is the paid tier per the project's monetization
  direction; the CLIs stay free + fully usable without the GUI).

These are deliberately staged: the foundations (compilable source, same-CLI dispatch, honest status)
are in; signing/distribution/polish are the follow-on Phase-B work.
