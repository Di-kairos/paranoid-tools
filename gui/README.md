# Paranoid Tools — GUI (Phase B)

Native **menu-bar (macOS)** and **system-tray (Windows)** agents over the same signed CLIs.
This is the optional *convenience* layer — Phase A is the cross-platform `paranoid` TUI launcher
(repo root). Phase B adds a one-glance status indicator + quick actions without opening a terminal.

## Honesty (same contract as Phase A)

The GUI **holds no secrets and adds no crypto**. It only:
- shows read-only status (vault open/closed, FileVault/BitLocker) in the menu bar / tray, and
- launches the **same CLIs you installed** (`securetrash`, `panic`, `paranoid`) — resolved
  through `PATH` at runtime, not re-verified per launch (signatures are checked at install
  time; see the launcher note in the root README) — and every destructive op
  and every password prompt happens **in the CLI** (a terminal/console window opens with the
  tool's real output); secrets never pass through the GUI.

So the GUI cannot weaken the tools' guarantees: it is a launcher, not a new tool.

## What's here

| Platform | File | Status |
|----------|------|--------|
| macOS | `macos/ParanoidBar.swift` + `macos/build.sh` | **Signed + notarized** (Developer ID, hardened runtime, ticket stapled); source compiles with `swiftc` (Command Line Tools). AppKit `NSStatusItem` menu-bar agent: monochrome SF-Symbol status glyph (adapts to light/dark menu bar), live vault/FileVault status, **vaultwatch session + TTL countdown** (in the glyph + menu), Status/PANIC/Vault▸(open·close·empty·destroy)/launcher, **Start at login** toggle (LaunchAgent), runs CLIs via Terminal. |
| Windows | `windows/paranoid-tray.ps1` (+ Pester) | **Runnable PowerShell** (no compile), installed into `lib\` by `windows\install.cmd` and started by `paranoid`. `NotifyIcon` tray with its own padlock glyph (open while the vault is open), menu on left or right click: status headers, Status / PANIC, Vault ▸ (create·open·close·empty·destroy) + **Guard the vault** (vaultwatch, TTL presets 30 m/1 h/2 h/4 h/none, "stop guarding" while a session runs), **Notepad** (ghostdraft) and **Secrets** (seedsplit) submenus, launcher, two **Start at login** toggles (HKCU Run, or a Task Scheduler task at the highest run level — see below), Settings, setup guide. Items that will ask for rights carry the UAC shield; CLIs run in a titled console that ends with "press Enter to close". First-run guide can pin the icon to the taskbar (Windows 11 hides new ones under `^`). Menu/status/autostart/vaultwatch/hotkey/l10n logic Pester-tested on pwsh 7 and Windows PowerShell 5.1; the whole thing walked by hand on a Windows 11 machine. |

**Phase B polish (product-grade UX, both platforms, full feature parity):**

- **Global panic hotkey** — ⌃⌥⇧P on macOS (Carbon `RegisterEventHotKey`, no Accessibility
  permission needed), Ctrl+Alt+P on Windows (`RegisterHotKey` + a hidden message window; it was
  Ctrl+Alt+Shift+P until s48 and is still in Settings — an older settings file is moved over once,
  with a notice). Windows sends AltGr as Ctrl+Alt: on a layout where AltGr+P types a character
  (US-International: ö), pick a Shift variant.
  Double-press within 2s → `panic now --hard` fires (a terminal/console opens with real output —
  the honesty contract holds; the double-press itself is the confirmation, no extra dialog).
  Single press arms + notifies. Presets in Settings (Windows: Ctrl+Alt+P / Ctrl+Alt+Shift+P / Ctrl+Alt+Shift+L / Off); a failed registration is
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
- **RU/EN localization** — an in-code string dictionary (54 keys shared by both platforms, plus
  30 Windows-only ones for UAC, the tool submenus and the console windows), no `.lproj` bundles
  (keeps the single-file design). Language: System / English / Русский in Settings. Key parity
  between the two languages, and between macOS and Windows for the shared set, is enforced by test.
- **Settings v2** — vault volume, poll interval, language, panic-hotkey preset, and a "Setup
  guide" button, all in the existing settings window.
- **Windows: privileged actions go through UAC, like the terminal launcher.** The vault is
  diskpart + BitLocker and `panic` has to close BitLocker volumes — none of that works without
  administrator rights, and a tray started normally (or from HKCU Run) has none. So the tray
  raises a single UAC prompt for `securetrash vault …` and `panic now`, the menu item says in
  advance that it will ask, and a declined prompt is reported as "nothing was done" instead of
  opening a console that quietly fails half its work.

Verified here: macOS source compiles cleanly (`swiftc -O`) and passes `./ParanoidBar --selftest`
(pure-logic checks: hotkey preset parsing, notification decision engine, localization-dictionary
completeness, onboarding-checklist state — `gui/macos/test.sh` runs both as the build gate).
### Windows: the two autostarts, and why the second one exists

The tray offers **Start at login** (an `HKCU\…\Run` entry, no rights needed) and **Start at
login WITH admin rights**, which registers a Task Scheduler task at the highest run level
instead. They are mutually exclusive — turning one on removes the other, or the tray would
start twice at logon.

The second one exists because of the panic path. On Windows every vault action and `panic now`
needs administrator rights, so an unelevated tray raises one UAC prompt each time — including
when the panic hotkey fires, which is precisely the moment a dialog is unwelcome. Started from
the task, the tray already holds the rights and the hotkey fires with no prompt at all.

The price is stated on the switch itself and in the balloon that confirms it: the tray then
runs as administrator for the whole session, and whatever compromises it is compromised with
administrator rights. That is why it is off by default, why it is a separate menu item rather
than a third state of the first one, and why turning it on or off costs one UAC prompt of its
own. Declining that prompt changes nothing.

Windows tray menu/dispatch/autostart/hotkey/notification/localization/onboarding logic is
Pester-tested in CI (`gui/windows/test` runs on `windows-latest`). The two mirror each other and
the bash launcher's grouping.

## Download (macOS)

Signed, notarized, stapled — [`ParanoidBar-0.1.0.dmg`](https://github.com/Di-kairos/paranoid-tools/releases/download/gui-v0.1.0/ParanoidBar-0.1.0.dmg)
(`gui-v0.1.0`, sha256 `da80707bb0e63a9deb3a05a0387ef64b75db6b6d2c28c25a5170d293b445b00a`). Open it,
drag the app onto `/Applications`. It drives the five CLIs, so install those first — see the
[root README](../README.md#install). Building it yourself is below. The Windows tray has no
release of its own: `windows\install.cmd` copies it from the clone into `lib\` next to the
launcher, and `paranoid` starts it — see [the tray](../README.md#the-tray) in the root README.

## Build / run

**macOS**
```bash
cd macos
./build.sh            # → ./ParanoidBar  (run it: a 🔒 appears in the menu bar)
./build.sh --bundle   # → ParanoidBar.app (LSUIElement: menu-bar agent, no Dock icon)

# release build — signed + notarized .dmg (needs an Apple Developer account; see below):
./build.sh --bundle --sign "Developer ID Application: NAME (TEAMID)" --notarize <profile> --dmg
./build.sh --bundle --sign -   # ad-hoc: exercises the codesign path locally (NOT distributable)
```
`--bundle` also puts `macos/ParanoidBar.icns` into the bundle's `Resources` and points
`CFBundleIconFile` at it, so Finder and the disk image show the project's mark — the terminal
square with the prompt chevron from `assets/logo.svg` — instead of the generic app icon. The
`.icns` carries every size from 16 to 1024 (@1x and @2x), each drawn from the vector rather than
downscaled, so the small ones stay sharp.
`--sign` runs `codesign` with hardened runtime + `--verify`; `--notarize <profile>` zips, submits
via `notarytool --wait`, then staples + validates. `--dmg` builds a compressed `hdiutil` image
holding the `.app` next to an `/Applications` symlink, then signs, notarizes and staples the
image **separately** — Gatekeeper checks the `.dmg` as its own artifact when you open it, and the
inner app's ticket does not cover that. The image also carries its window layout: a fixed 640×400
icon view, 128px icons, and an engraved background with an arrow pointing the app at the
`/Applications` symlink. Finder is the only thing that writes that layout (it lives in the volume's
`.DS_Store`), so the build mounts a writable image, drives Finder over Automation, and only then
compresses it to UDZO. Between mounting and laying out it waits for Finder to actually see the
volume: `hdiutil attach` returns before DiskArbitration has told Finder about it, and asking too
early fails with `-1728` — which looks exactly like a refused Automation prompt, except the image
comes out signed, notarized and unstyled. In a headless session — CI or ssh, where Automation is
refused for real — the step prints a warning and the image is still built, just without the layout. `--version X.Y.Z` stamps
both. Only the real Developer-ID
sign + notary submission need the account; without one, the ad-hoc path still exercises the
pipeline mechanics.

**Windows**
```powershell
pwsh -File windows/paranoid-tray.ps1   # a padlock appears in the tray (under ^ on Windows 11); left or right click for the menu
```
Installed by `windows\install.cmd`, it is started by `paranoid` whenever none is running
(`PARANOID_NO_TRAY=1` to opt out); one tray per session — a second copy exits. pwsh 7 only.

## Signing and distribution

**macOS is signed and notarized.** `ParanoidBar.app` is signed with a Developer ID Application
certificate under hardened runtime and a secure timestamp, notarized by Apple, and the notary
ticket is stapled into the bundle — so Gatekeeper accepts it offline too, on a machine that has
never seen this app:

```
spctl --assess --type execute ParanoidBar.app   → accepted, source=Notarized Developer ID
xcrun stapler validate ParanoidBar.app          → the validate action worked
codesign -dvv                                   → flags=0x10000(runtime), Developer ID Application
```

**The `.dmg` is signed and notarized too**, in its own right — verified by mounting the finished
image and checking what is actually inside it, not just the file on disk:

```
spctl --assess --type open --context context:primary-signature ParanoidBar-X.Y.Z.dmg
                                                → accepted, source=Notarized Developer ID
mounted: ParanoidBar.app + an /Applications symlink (drag-n-drop install)
the mounted app: accepted · stapler validate ok · codesign --test-requirement="=notarized" ok
```

Reproduce a release build yourself (the identity string comes from
`security find-identity -v -p codesigning`, the notary profile from
`xcrun notarytool store-credentials`):

```bash
cd macos
./build.sh --bundle --sign "Developer ID Application: NAME (TEAMID)" \
           --notarize <profile> --dmg --version X.Y.Z
```

Neither the app bundle nor the `.dmg` is committed — both are build artifacts (`.gitignore`),
rebuilt from source.

**Windows is not signed yet.** The tray ships as a `.ps1`, which needs an Authenticode
code-signing certificate from a commercial CA — a separate purchase from the Apple account, not
covered by it. Until that lands, the installer copies the tray (and the launcher) from the clone
you read, the way it always has for the launcher; the five CLIs it drives are Ed25519-signed and
verified at install time regardless.

## Not done yet (honest scope — the rest of Phase B)

- **Windows code signing** — an Authenticode certificate for the tray `.ps1` (see above), so
  the tray can ship from a signed release like the CLIs instead of being copied from the clone.
  The macOS half of this item — signing, notarization and a `.dmg` — is done.

UX polish is done: hotkey, notifications, onboarding, RU/EN, and the settings pane (vault-volume
override, poll interval, language, hotkey preset — see the table above) all shipped in Phase B.
What remains is the Windows certificate — not UX, and not macOS.

The GUI is free, like the CLIs, and stays that way: no paid tier, no feature held back for one.
If it is useful to you, the project takes donations — nothing else is being sold.
