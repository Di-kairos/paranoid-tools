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
| macOS | `macos/ParanoidBar.swift` + `macos/build.sh` | **Source compiles** with `swiftc` (Command Line Tools). AppKit `NSStatusItem` menu-bar agent: monochrome SF-Symbol status glyph (adapts to light/dark menu bar), live vault/FileVault status, **vaultwatch session + TTL countdown** (in the glyph + menu), Status/PANIC/Vault▸(open·close·empty·destroy)/launcher, **Start at login** toggle (LaunchAgent), runs CLIs via Terminal. |
| Windows | `windows/paranoid-tray.ps1` (+ Pester) | **Runnable PowerShell** (no compile). `NotifyIcon` tray, same menu + **vaultwatch TTL countdown** (tooltip + menu headers) + **Start at login** toggle (HKCU Run), runs CLIs in a new console. Menu/status/autostart/vaultwatch logic Pester-tested. |

Verified here: macOS source compiles cleanly (`swiftc -O`); Windows tray menu/dispatch/autostart
logic is Pester-tested in CI (`gui/windows/test` runs on `windows-latest`). The two mirror each
other and the bash launcher's grouping.

## Build / run

**macOS**
```bash
cd macos
./build.sh            # → ./ParanoidBar  (run it: a 🔒 appears in the menu bar)
./build.sh --bundle   # → ParanoidBar.app (LSUIElement: menu-bar agent, no Dock icon)

# distribution (needs an Apple Developer account — see below):
./build.sh --bundle --sign "Developer ID Application: NAME (TEAMID)" --notarize <profile>
./build.sh --bundle --sign -   # ad-hoc: exercises the codesign path locally (NOT distributable)
```
`build.sh` is distribution-ready: `--sign` runs `codesign` with hardened runtime + `--verify`;
`--notarize <profile>` zips, submits via `notarytool --wait`, then staples + validates.
`--version X.Y.Z` stamps the bundle. Only the real Developer-ID sign + notary submission need the
account; the pipeline mechanics are exercised by the ad-hoc path.

**Windows**
```powershell
pwsh -File windows/paranoid-tray.ps1   # a Shield icon appears in the tray; right-click for the menu
```

## Distribution readiness (what the maintainer must obtain)

The macOS pipeline (`build.sh --sign --notarize`) is ready; it only needs credentials:

| Need | What / where | Cost | Unblocks |
|------|--------------|------|----------|
| **Apple Developer Program** | developer.apple.com/programs — enroll the Di-kairos Apple ID | **$99/yr** | Developer ID cert + notarization |
| **Developer ID Application cert** | Xcode/Keychain or developer.apple.com → Certificates | included | `codesign` that passes Gatekeeper |
| **notarytool keychain profile** | `xcrun notarytool store-credentials <profile> --apple-id … --team-id … --password <app-specific>` | included | `--notarize <profile>` |
| **xcodebuild / real Mac** | this machine has Command Line Tools only (`codesign`/`notarytool`/`stapler` present) — full `.app` sign+notarize best run on the **home machine** | — | end-to-end release |

> App-specific password: appleid.apple.com → Sign-In & Security → App-Specific Passwords.
> One `store-credentials` per machine; then release is a single `build.sh --sign … --notarize …`.

**Windows tray** (`.ps1`, not a compiled exe) → Authenticode-sign the script with a code-signing
cert (`Set-AuthenticodeSignature`) or ship a signed launch shim. Needs a Windows code-signing cert
(OV ~$100–400/yr, or EV for instant SmartScreen trust) — separate pack, not yet scripted.

## Not done yet (honest scope — the rest of Phase B)

- A settings pane (vault-volume override, poll interval, language) — a UX-design decision, staged
  separately. *(Auto-start at login, monochrome status glyphs, and vaultwatch session + TTL
  countdown are now done — see the table above.)*
- **Open-core packaging** (the convenience layer is the paid tier per the project's monetization
  direction; the CLIs stay free + fully usable without the GUI).

These are deliberately staged: the foundations (compilable source, same-CLI dispatch, honest status)
are in; signing/distribution/polish are the follow-on Phase-B work.
