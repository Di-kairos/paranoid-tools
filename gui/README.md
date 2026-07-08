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

**Phase B polish (product-grade UX, both platforms, full feature parity):**

- **Global panic hotkey** — ⌃⌥⇧P on macOS (Carbon `RegisterEventHotKey`, no Accessibility
  permission needed), Ctrl+Alt+Shift+P on Windows (`RegisterHotKey` + a hidden message window).
  Double-press within 2s → `panic now --hard` fires (a terminal/console opens with real output —
  the honesty contract holds; the double-press itself is the confirmation, no extra dialog).
  Single press arms + notifies. Presets (P / L / Off) in Settings; a failed registration is
  reported honestly, never silently swallowed.
  "PANIC NOW" means the same thing everywhere: the GUI menu item, the hotkey, and the launcher's
  menu entry all run `panic now --hard` (hide & lock + kill cloud daemons + clear recents).
- **Native notifications** — TTL warning (<120s to auto-close), TTL expired while still open,
  and a long-open reminder (30+ min without a vaultwatch session). Pure decision engine, fires
  once per episode, re-arms if the session is extended. Delivery via `osascript` on macOS,
  `NotifyIcon.ShowBalloonTip` on Windows.
- **Welcome onboarding (first run)** — a live readiness checklist (CLI installed / vault created
  / hotkey enabled / start at login) with action buttons, shown once on first launch and always
  reachable from the menu ("Setup guide…") and from Settings.
- **RU/EN localization** — an in-code string dictionary (49 keys), no `.lproj` bundles (keeps the
  single-file design). Language: System / English / Русский in Settings. Key parity between the
  two languages and between macOS and Windows is enforced by test.
- **Settings v2** — vault volume, poll interval, language, panic-hotkey preset, and a "Setup
  guide" button, all in the existing settings window.

Verified here: macOS source compiles cleanly (`swiftc -O`) and passes `./ParanoidBar --selftest`
(pure-logic checks: hotkey preset parsing, notification decision engine, localization-dictionary
completeness, onboarding-checklist state — `gui/macos/test.sh` runs both as the build gate).
Windows tray menu/dispatch/autostart/hotkey/notification/localization/onboarding logic is
Pester-tested in CI (`gui/windows/test` runs on `windows-latest`). The two mirror each other and
the bash launcher's grouping.

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

- **Signing / distribution** — Apple Developer Program enrollment + Developer ID cert +
  notarization (macOS), and a Windows code-signing cert for Authenticode-signing the `.ps1`
  (see the readiness table above). The pipelines are built and ready; only the credentials/cert
  are missing.
- **Open-core packaging** (the convenience layer is the paid tier per the project's monetization
  direction; the CLIs stay free + fully usable without the GUI).

UX polish is done: hotkey, notifications, onboarding, RU/EN, and the settings pane (vault-volume
override, poll interval, language, hotkey preset — see the table above) all shipped in Phase B.
What remains is distribution (signing/notarization/code-signing) and the open-core packaging
decision — not UX.
