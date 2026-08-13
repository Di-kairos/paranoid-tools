// ParanoidBar — a native menu-bar agent on top of the same signed Paranoid Tools CLIs (Phase B).
//
// HONESTY (as with the Phase A bash launcher): the GUI holds NO secrets and adds NO crypto. It only
// shows a live status in the menu bar and launches the same CLIs (securetrash / panic / paranoid),
// hiding nothing. Destructive actions and password entry go into the CLI itself (a Terminal opens
// with its output) — secrets never pass through the GUI. It is a convenience layer, not a new tool.
//
// Build (Command Line Tools is enough): see build.sh — `swiftc -O -o ParanoidBar ParanoidBar.swift`.
// Running as a menu-bar agent (no Dock icon) — via an .app bundle with LSUIElement=true; signing/
// notarization/packaging needs an Apple Developer account (a distribution step, see gui/README.md).

import AppKit
import Carbon.HIToolbox

// Vault mount point — the same one securetrash uses. Priority: settings (the settings panel) →
// ST_VAULT_VOLUME environment → default. Computed, to pick up settings changes without a restart.
private var vaultVolume: String {
    if let v = UserDefaults.standard.string(forKey: "vaultVolume"), !v.isEmpty { return v }
    return ProcessInfo.processInfo.environment["ST_VAULT_VOLUME"] ?? "/Volumes/SecretVault"
}
// The set of CLIs the GUI works on top of: install.sh installs them together, so "ready"
// means all five. The `paranoid` launcher is here too — the menu bar invokes exactly it, and
// without it the green checkmark would be a lie (previously only three of five tools were checked).
let ecosystemCLIs = ["securetrash", "vaultwatch", "panic", "ghostdraft", "seedsplit", "paranoid"]

// Escape a value for the shell (inner `'` get split out). Pure function → selftest.
func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
// Environment prefix for CLIs launched in Terminal.app: a fresh shell does NOT inherit the GUI's
// environment. BOTH variables are mandatory — ST_VAULT_VOLUME sets the mount point, ST_VAULT_PATH
// the container itself; without the second one open/create/destroy would hit the default vault
// while the GUI shows a custom one (Codex finding for AUDIT_2026-08-03 P2-9).
func terminalEnvPrefix(volume: String, path: String) -> String {
    "ST_VAULT_VOLUME=\(shellQuote(volume)) ST_VAULT_PATH=\(shellQuote(path)) "
}

// Clamp the poll interval to sane bounds: 5s floor (battery/CPU), 3600s ceiling (otherwise the status
// "freezes" for an hour+ and TTL notifications arrive too late to be useful). Mirrors the Windows-tray clamp.
func clampPoll(_ v: Int) -> Int { min(max(v, 5), 3600) }
// Status poll interval (sec) from settings; <5 (including a not-yet-set 0) → default 15, otherwise clamp the top.
private func pollSeconds() -> Double {
    let v = UserDefaults.standard.double(forKey: "pollSeconds")
    // min in the Double domain BEFORE Int(): a huge/inf double from hand-edited defaults would otherwise trap Int(v)
    return v >= 5 ? Double(clampPoll(Int(min(v, 3600)))) : 15
}
// Same mounted volume? Normalizing via standardizedFileURL eats the trailing slash and
// relative components, so that "/Volumes/Foo" and "/Volumes/Foo/" match as one volume.
func sameMount(_ a: String, _ b: String) -> Bool {
    URL(fileURLWithPath: a).standardizedFileURL.path == URL(fileURLWithPath: b).standardizedFileURL.path
}

// --- localization: an in-code dictionary (no .lproj — single-file principle). Keys are mirrored
// in the Windows tray ($PtStrings); set parity is checked by a test (Task 11). Honest wording
// ("at risk") is translated without softening. ---
private let strings: [String: (en: String, ru: String)] = [
    "vault_label":      ("Vault:", "Сейф:"),
    "vault_open_risk":  ("OPEN — at risk", "ОТКРЫТ — под риском"),
    "vault_closed":     ("closed", "закрыт"),
    "vault_not_setup":  ("not set up", "не создан"),
    "vault_unknown":    ("state unknown — volume list unreadable", "состояние неизвестно — список томов недоступен"),
    "vault_ask":        ("Ask securetrash for the vault state", "Спросить securetrash о состоянии сейфа"),
    "fv_label":         ("FileVault:", "FileVault:"),
    "fv_on":            ("ON", "включён"),
    "fv_off":           ("off / unknown", "выкл / неизвестно"),
    "status_item":      ("Status — full read-only check", "Статус — полная read-only проверка"),
    "panic_item":       ("PANIC NOW — hide & lock", "ПАНИКА — спрятать и заблокировать"),
    "vault_menu":       ("Vault", "Сейф"),
    "vault_close":      ("Close the vault", "Закрыть сейф"),
    "vault_open":       ("Open the vault", "Открыть сейф"),
    "vault_create":     ("Create a vault", "Создать сейф"),
    "vault_empty":      ("Empty — wipe contents, keep the vault", "Очистить — стереть содержимое, сейф оставить"),
    "vault_destroy":    ("Destroy the vault (irreversible)", "Уничтожить сейф (необратимо)"),
    "launcher_item":    ("Open the full launcher (paranoid)", "Открыть полный лаунчер (paranoid)"),
    "settings_item":    ("Settings…", "Настройки…"),
    "login_item":       ("Start at login", "Запускать при входе"),
    "setup_item":       ("Setup guide…", "Гид по настройке…"),
    "quit_item":        ("Quit Paranoid Bar", "Выйти из Paranoid Bar"),
    "ttl_expired":      ("TTL expired", "TTL истёк"),
    "auto_exit_in":     ("auto-exit in", "авто-выход через"),
    "watching_no_ttl":  ("watching (no TTL)", "наблюдение (без TTL)"),
    "tip_open":         ("Vault is OPEN — at risk while open", "Сейф ОТКРЫТ — под риском, пока открыт"),
    "tip_closed":       ("Vault closed", "Сейф закрыт"),
    "notif_ttl_warn":   ("Vault auto-closes in {0}", "Сейф авто-закроется через {0}"),
    "notif_ttl_expired": ("vaultwatch TTL expired — vault is still OPEN", "TTL vaultwatch истёк — сейф всё ещё ОТКРЫТ"),
    "notif_long_open":  ("Vault open for 30+ minutes (no vaultwatch)", "Сейф открыт дольше 30 минут (без vaultwatch)"),
    "notif_panic_arm":  ("Press again to PANIC", "Нажмите ещё раз для ПАНИКИ"),
    "notif_hotkey_fail": ("Panic hotkey unavailable (taken by another app)", "Хоткей паники недоступен (занят другим приложением)"),
    "set_title":        ("Paranoid Bar — Settings", "Paranoid Bar — Настройки"),
    "set_vol":          ("Vault volume:", "Том сейфа:"),
    "set_poll":         ("Poll interval (s):", "Интервал опроса (с):"),
    "set_lang":         ("Language:", "Язык:"),
    "set_hotkey":       ("Panic hotkey:", "Хоткей паники:"),
    "set_save":         ("Save", "Сохранить"),
    // set_cancel is used only by the Windows form (the macOS window has no Cancel button);
    // the key is declared here for ps1↔Swift key parity (Pester test).
    "set_cancel":       ("Cancel", "Отмена"),
    "set_setup_btn":    ("Show setup guide", "Показать гид"),
    "hk_off":           ("Off", "Выкл"),
    "lang_system":      ("System", "Системный"),
    "ob_title":         ("Paranoid Bar — Welcome", "Paranoid Bar — Добро пожаловать"),
    "ob_sub":           ("A status bar over the same signed CLIs. Secrets never pass through the GUI.",
                         "Панель статуса поверх тех же подписанных CLI. Секреты через GUI не проходят."),
    "ob_cli_ok":        ("CLIs installed (all 5 tools + launcher)", "CLI установлены (все 5 инструментов + лаунчер)"),
    "ob_cli_missing":   ("CLIs not found — install first", "CLI не найдены — сначала установите"),
    "ob_vault_ok":      ("Vault created", "Сейф создан"),
    "ob_vault_missing": ("No vault yet", "Сейф ещё не создан"),
    "ob_create_btn":    ("Create vault…", "Создать сейф…"),
    "ob_hotkey_line":   ("Panic hotkey", "Хоткей паники"),
    "ob_login_line":    ("Start at login", "Запускать при входе"),
    "ob_enable_btn":    ("Enable", "Включить"),
    "ob_risk":          ("An open vault is always “at risk” — the GUI never hides that.",
                         "Открытый сейф всегда «под риском» — GUI этого не прячет."),
    "ob_done":          ("Done", "Готово"),
]

// Language selection: the settings override ("en"/"ru") beats the system; "system" → locale prefix,
// everything non-Russian collapses to en. Pure function — exercised in selftest.
private func resolveLang(override: String, systemLang: String) -> String {
    if override == "en" || override == "ru" { return override }
    return systemLang.hasPrefix("ru") ? "ru" : "en"
}
private func currentLang() -> String {
    let override = UserDefaults.standard.string(forKey: "language") ?? "system"
    let sys = Locale.preferredLanguages.first ?? "en"
    return resolveLang(override: override, systemLang: sys)
}
private func L(_ key: String, lang: String? = nil) -> String {
    guard let s = strings[key] else { return key }
    return (lang ?? currentLang()) == "ru" ? s.ru : s.en
}

// --- notifications: a pure decision engine (selftest) + delivery via osascript.
// UNUserNotificationCenter requires an .app bundle with an identity — an unsigned binary crashes,
// hence display notification via osascript (works for a bare executable). ---
struct NotifyState: Equatable {
    var ttlWarned = false          // "auto-closes in N" already shown in this episode
    var ttlExpiredWarned = false   // "TTL expired" already shown
    var longOpenWarned = false     // "open 30+ min" already shown
    var openSince: Date? = nil     // start of the current "vault open" episode
                                   // (= the first poll that saw open; a GUI restart resets the count)
}
// Rules (spec §2): TTL<120s → ttl_warn; TTL==0 while open → ttl_expired; open >30 min
// with NO vaultwatch session → long_open. Each fires once per episode; closing the vault resets.
// Event-string names deliberately mirror the Windows tray (Get-PtNotifyEvents) — do not replace with an enum.
func decideNotifications(open: Bool, ttl: Int?, hasSessions: Bool, now: Date,
                         state: NotifyState) -> ([String], NotifyState) {
    var s = state
    guard open else { return ([], NotifyState()) }         // closed → episode reset
    if s.openSince == nil { s.openSince = now }
    var events: [String] = []
    if let t = ttl, t >= 120 { s.ttlWarned = false; s.ttlExpiredWarned = false }   // new/extended session → re-arm
    if let t = ttl {
        if t > 0 && t < 120 && !s.ttlWarned { events.append("ttl_warn"); s.ttlWarned = true }
        if t == 0 && !s.ttlExpiredWarned { events.append("ttl_expired"); s.ttlExpiredWarned = true }
    }
    if !hasSessions, let since = s.openSince,
       now.timeIntervalSince(since) > 1800, !s.longOpenWarned {
        events.append("long_open"); s.longOpenWarned = true
    }
    return (events, s)
}

// --- global panic hotkey (Carbon RegisterEventHotKey; works without Accessibility permissions,
// unlike CGEventTap). Double press within 2s → panic now --hard WITHOUT confirm (double-press =
// confirmation; --hard = parity with the launcher's "PANIC NOW": hide&lock + cloud daemons + recents).
// A single press — arm + notification. ---
func panicShouldFire(now: Date, armedAt: Date?, window: TimeInterval = 2.0) -> Bool {
    guard let a = armedAt else { return false }
    // d < 0 → the clock was set back between arming and the second press; do not count that as "second in window".
    let d = now.timeIntervalSince(a)
    return d >= 0 && d <= window
}
// Preset → virtual key (all presets share the same modifiers: ⌃⌥⇧). nil → do not register.
func hotkeyVK(preset: String) -> UInt32? {
    switch preset {
    case "ctrl-opt-shift-p": return UInt32(kVK_ANSI_P)
    case "ctrl-opt-shift-l": return UInt32(kVK_ANSI_L)
    default: return nil
    }
}
// A Carbon C callback cannot capture Swift context → a global hook for the action.
private var panicHotkeyAction: (() -> Void)?
private var panicHotKeyRef: EventHotKeyRef?
private var hotkeyHandlerInstalled = false
// false → the handler REALLY did not install (Carbon returned an error); repeat calls after success — true.
func installHotkeyHandlerOnce() -> Bool {
    guard !hotkeyHandlerInstalled else { return true }
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        panicHotkeyAction?()
        return noErr
    }, 1, &spec, nil, nil)
    guard status == noErr else { return false }
    hotkeyHandlerInstalled = true
    return true
}
// true = the hotkey is in the requested state (registered OR deliberately removed via off);
// false = a REAL registration failure (for example, the combination is taken by another app).
func registerPanicHotkey(preset: String) -> Bool {
    if let ref = panicHotKeyRef { UnregisterEventHotKey(ref); panicHotKeyRef = nil }
    guard let vk = hotkeyVK(preset: preset) else { return true }   // off/garbage → removed deliberately
    guard installHotkeyHandlerOnce() else { return false }
    let id = EventHotKeyID(signature: OSType(0x50424152), id: 1)   // 'PBAR'
    let status = RegisterEventHotKey(vk, UInt32(controlKey | optionKey | shiftKey), id,
                                     GetApplicationEventTarget(), 0, &panicHotKeyRef)
    if status != noErr { panicHotKeyRef = nil; return false }
    return true
}
// Settings popup values: popup item index ↔ value in UserDefaults (a single source for
// building, resyncing the cached window, and saving — index desync is ruled out).
private let langValues = ["system", "en", "ru"]
private let hotkeyValues = ["ctrl-opt-shift-p", "ctrl-opt-shift-l", "off"]
// Sanitize a garbage value from UserDefaults (e.g. a foreign `defaults write` with a typo): outside
// the known presets we silently fall back to the default rather than quietly disabling the hotkey
// (Settings would otherwise show ⌃⌥⇧P while the hotkey was in fact not registered). Mirrors the Windows-tray sanitization.
func sanitizeHotkeyPreset(_ raw: String) -> String {
    hotkeyValues.contains(raw) ? raw : "ctrl-opt-shift-p"
}
// Preset from settings (default — enabled: the hotkey is the whole point of Phase B).
func hotkeyPreset() -> String {
    sanitizeHotkeyPreset(UserDefaults.standard.string(forKey: "panicHotkey") ?? "ctrl-opt-shift-p")
}

// A Welcome-window checklist line — pure, for selftest.
func checklistLine(ok: Bool, okKey: String, missKey: String, lang: String? = nil) -> String {
    (ok ? "✅ " + L(okKey, lang: lang) : "❌ " + L(missKey, lang: lang))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private var volField: NSTextField?
    private var pollField: NSTextField?
    private var langPopup: NSPopUpButton?
    private var hotkeyPopup: NSPopUpButton?
    private var welcomeWindow: NSWindow?
    private var notifyState = NotifyState()
    // Carbon hot-key events arrive on the main thread via the NSApplication event loop —
    // no synchronization needed for panicArmedAt.
    private var panicArmedAt: Date?
    // true = the hotkey is in the requested state (registered OR deliberately removed via off);
    // false = a real registration failure. Read only behind the hotkeyVK(preset:) != nil gate —
    // by itself true with off does NOT mean "the hotkey works" (honest Welcome-checklist status).
    private var hotkeyRegistered = false

    // Global hotkey handling: first press — arm + notification, second within the 2s window — panic.
    private func hotkeyPressed() {
        let now = Date()
        if panicShouldFire(now: now, armedAt: panicArmedAt) {
            panicArmedAt = nil
            runInTerminal("panic now --hard")
        } else {
            panicArmedAt = now
            notify(L("notif_panic_arm"))
        }
    }

    // Native notification delivery. There are no secrets in the text — status only.
    private func notify(_ text: String) {
        let esc = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(esc)\" with title \"Paranoid Bar\""]
        try? p.run()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()
        rescheduleTimer()   // periodic status polling (interval from settings)
        panicHotkeyAction = { [weak self] in self?.hotkeyPressed() }
        // A registration failure (combination taken by another app) is not swallowed — the user must know.
        hotkeyRegistered = registerPanicHotkey(preset: hotkeyPreset())
        if !hotkeyRegistered { notify(L("notif_hotkey_fail")) }
        // first-run: Welcome once; afterwards — from the "Setup guide…" menu item
        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            doWelcome()
        }
    }

    // Restart the poll timer with the current interval (called at startup and when saving settings).
    private func rescheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollSeconds(), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // --- status (read-only, like the launcher's dashboard) ---
    // Really MOUNTED, not "the path exists" (a leftover /Volumes/… directory gave a false OPEN, P2-10).
    // Three-state: "open" / "closed" / "unknown". Answering "closed" when the volume list
    // could not be obtained is not allowed: a green "closed" over an open vault is the worst
    // possible lie (mirrors lib/common.sh:_volume_mounted and the launcher's dashboard). This branch
    // used to hold fileExists — i.e. exactly the directory check the ecosystem moved away from.
    private func vaultMountState() -> String {
        let target = URL(fileURLWithPath: vaultVolume).standardizedFileURL
        guard let vols = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) else {
            return "unknown"
        }
        return vols.contains { $0.standardizedFileURL == target } ? "open" : "closed"
    }
    // For the glyph and notifications "don't know" = "not open": there is no ground to alarm
    // with ⚠ or send long_open over an unknown state. The menu, though, must call unknown by its name.
    private func vaultOpen() -> Bool { vaultMountState() == "open" }
    // Vault container. ST_VAULT_PATH — the same override the CLI honors (AUDIT_2026-07-03 P0-1):
    // without it the GUI would show "no vault" right next to an existing custom vault.
    private var vaultPath: String {
        if let p = ProcessInfo.processInfo.environment["ST_VAULT_PATH"], !p.isEmpty { return p }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/SecureVault.sparsebundle"
    }
    private func vaultExists() -> Bool {
        FileManager.default.fileExists(atPath: vaultPath)
    }
    private func fileVaultOn() -> Bool { capture("/usr/bin/fdesetup", ["status"]).contains("FileVault is On") }

    // --- vaultwatch status (read-only over the same session files the vaultwatch CLI writes) ---
    private struct VWSession { let mount: String; let remaining: Int? }  // remaining=nil → session without a TTL
    private var vwStateDir: String {
        ProcessInfo.processInfo.environment["VW_STATE_DIR"]
            ?? (FileManager.default.homeDirectoryForCurrentUser.path + "/.vaultwatch/sessions")
    }
    // Parse key=value session files (mount/started/ttl_secs). remaining = started+ttl_secs-now.
    private func vaultwatchSessions() -> [VWSession] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: vwStateDir) else { return [] }
        let now = Int(Date().timeIntervalSince1970)
        var out: [VWSession] = []
        for f in files.sorted() {
            guard let text = try? String(contentsOfFile: vwStateDir + "/" + f, encoding: .utf8) else { continue }
            var mount = "", started = 0, ttl = 0
            for line in text.split(separator: "\n") {
                guard let eq = line.firstIndex(of: "=") else { continue }
                let k = String(line[..<eq]); let v = String(line[line.index(after: eq)...])
                switch k {
                case "mount":    mount = v
                case "started":  started = Int(v) ?? 0
                case "ttl_secs": ttl = Int(v) ?? 0
                default: break
                }
            }
            guard !mount.isEmpty else { continue }
            out.append(VWSession(mount: mount, remaining: ttl > 0 ? max(0, started + ttl - now) : nil))
        }
        return out
    }
    // Same format as the vaultwatch CLI: "1h 5m 9s" / "5m 9s".
    private func fmtDuration(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? "\(h)h \(m)m \(sec)s" : "\(m)m \(sec)s"
    }

    private func refresh() {
        let open = vaultOpen()
        let sessions = vaultwatchSessions()
        // Scoped to the current volume (P1): a stale session file of a FOREIGN volume (e.g. an
        // unmounted /Volumes/OldVault) would otherwise mute long_open forever (hasSessions always
        // true) and could drive the current vault's TTL warnings. The menu list below stays full/
        // honest — the scope is only for notification decisions and the current volume's tooltip/glyph.
        let vaultSessions = sessions.filter { sameMount($0.mount, vaultVolume) }
        // TTL is shown ONLY with a really open vault: an orphaned session file would otherwise draw
        // "auto-exit in …" with the vault closed (P2-10). Closed → no countdown at all.
        let ttl = open ? vaultSessions.compactMap { $0.remaining }.min() : nil   // nearest auto-exit
        // Text to the right of the glyph: TTL countdown / "expired" (⚠) / ⚠ with an open vault / empty.
        let suffix: String
        if let t = ttl { suffix = t == 0 ? " ⚠" : " " + fmtDuration(t) } else { suffix = open ? " ⚠" : "" }
        // Monochrome SF-Symbol glyph (template) — adapts to the dark/light menu bar, unlike
        // a colored emoji. Falls back to emoji if the symbol is unavailable (before macOS 11).
        let symbol = open ? "lock.open.fill" : "lock.fill"
        if let img = NSImage(systemSymbolName: symbol,
                             accessibilityDescription: open ? "Vault open" : "Vault closed") {
            img.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.title = suffix
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = ttl != nil ? suffix.trimmingCharacters(in: .whitespaces) : (open ? "🔓⚠" : "🔒")
        }
        let tip = open ? L("tip_open") : (vaultMountState() == "unknown" ? L("vault_unknown") : L("tip_closed"))
        if let t = ttl {
            statusItem.button?.toolTip = tip + (t == 0 ? " · vaultwatch " + L("ttl_expired") : " · vaultwatch " + L("auto_exit_in") + " " + fmtDuration(t))
        } else {
            statusItem.button?.toolTip = tip
        }
        rebuildMenu(open: open, sessions: sessions)

        let (events, newState) = decideNotifications(
            open: open, ttl: ttl, hasSessions: !vaultSessions.isEmpty, now: Date(), state: notifyState)
        notifyState = newState
        for e in events {
            switch e {
            case "ttl_warn":    notify(L("notif_ttl_warn").replacingOccurrences(of: "{0}", with: fmtDuration(ttl ?? 0)))
            case "ttl_expired": notify(L("notif_ttl_expired"))
            case "long_open":   notify(L("notif_long_open"))
            default: break
            }
        }
    }

    // --- menu ---
    private func rebuildMenu(open: Bool, sessions: [VWSession]) {
        let menu = NSMenu()
        let mountState = vaultMountState()
        let vaultStatusText: String
        if mountState == "open" { vaultStatusText = L("vault_open_risk") }
        else if mountState == "unknown" { vaultStatusText = L("vault_unknown") }
        else { vaultStatusText = vaultExists() ? L("vault_closed") : L("vault_not_setup") }
        menu.addItem(header(L("vault_label") + "      " + vaultStatusText))
        menu.addItem(header(L("fv_label") + "  " + (fileVaultOn() ? L("fv_on") : L("fv_off"))))
        // Active vaultwatch sessions: mount point + TTL countdown (or "no TTL").
        for s in sessions {
            let name = (s.mount as NSString).lastPathComponent
            let detail: String
            if let r = s.remaining { detail = r == 0 ? L("ttl_expired") : L("auto_exit_in") + " " + fmtDuration(r) }
            else { detail = L("watching_no_ttl") }
            menu.addItem(header("vaultwatch: " + name + " — " + detail))
        }
        menu.addItem(.separator())

        menu.addItem(item(L("status_item"), #selector(doStatus)))
        menu.addItem(item("🔒  " + L("panic_item"), #selector(doPanic)))
        menu.addItem(.separator())

        // The "Vault" submenu — a mirror of the bash launcher's grouping. autoenablesItems=false,
        // otherwise AppKit enables items itself by target presence (our disable would not hold).
        let vault = NSMenu()
        vault.autoenablesItems = false
        // With unknown the item promises no action: opening/closing blindly is guessing.
        let hasVault = vaultExists() && mountState != "unknown"
        let toggleLabel: String
        if mountState == "open" { toggleLabel = L("vault_close") }
        else if mountState == "unknown" { toggleLabel = L("vault_ask") }
        else { toggleLabel = vaultExists() ? L("vault_open") : L("vault_create") }
        vault.addItem(item(toggleLabel, #selector(doVaultToggle)))
        // Empty/Destroy only make sense with an existing container AND a known state —
        // otherwise grey-out, so that a destructive action is not live "into the void" (P2-7)
        // and does not run on top of a state we do not know.
        let emptyItem = item(L("vault_empty"), #selector(doVaultEmpty))
        emptyItem.isEnabled = hasVault
        vault.addItem(emptyItem)
        let destroyItem = item(L("vault_destroy"), #selector(doVaultDestroy))
        destroyItem.isEnabled = hasVault
        vault.addItem(destroyItem)
        let vaultItem = NSMenuItem(title: L("vault_menu") + " ▸", action: nil, keyEquivalent: "")
        vaultItem.submenu = vault
        menu.addItem(vaultItem)

        menu.addItem(item(L("launcher_item"), #selector(doLauncher)))
        menu.addItem(.separator())

        menu.addItem(item(L("settings_item"), #selector(doSettings)))
        menu.addItem(item(L("setup_item"), #selector(doWelcome)))
        // Start at login — the checkmark reflects the current LaunchAgent state.
        let loginItem = item(L("login_item"), #selector(doToggleLogin))
        loginItem.state = loginEnabled() ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item(L("quit_item"), #selector(doQuit)))
        statusItem.menu = menu
    }

    private func header(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }
    private func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        return it
    }

    // --- actions: launch the same CLIs; output/input are visible in Terminal (the GUI hides nothing) ---
    @objc private func doStatus()        { runInTerminal("securetrash check") }
    // --hard = parity with the launcher's "PANIC NOW" (hide&lock + cloud daemons + recents)
    @objc private func doPanic()         { runInTerminal("panic now --hard") }
    // unknown → read-only `vault status`: we ask the tool instead of guessing.
    @objc private func doVaultToggle() {
        let s = vaultMountState()
        let verb: String
        if s == "open" { verb = "close" }
        else if s == "unknown" { verb = "status" }
        else { verb = vaultExists() ? "open" : "create" }
        runInTerminal("securetrash vault " + verb)
    }
    @objc private func doVaultEmpty()    { runInTerminal("securetrash vault reset") }
    @objc private func doVaultDestroy()  { runInTerminal("securetrash vault destroy") }
    @objc private func doLauncher()      { runInTerminal("paranoid") }
    @objc private func doQuit()          { NSApp.terminate(nil) }

    // --- start at login (LaunchAgent) ---
    // We write the per-user LaunchAgent plist directly: works with an UNsigned local build (unlike
    // SMAppService.mainApp, which needs a signed/registered bundle). It points at the current
    // executable; the .accessory policy is set in code, so there will be no Dock icon.
    private let loginLabel = "com.di-kairos.paranoidbar"
    private var loginPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(loginLabel).plist")
    }
    private func loginEnabled() -> Bool { FileManager.default.fileExists(atPath: loginPlistURL.path) }
    private func setLogin(_ on: Bool) {
        let fm = FileManager.default
        if on {
            guard let exe = Bundle.main.executableURL?.path else { return }
            let plist: [String: Any] = [
                "Label": loginLabel,
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            try? fm.createDirectory(at: loginPlistURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                              format: .xml, options: 0) {
                try? data.write(to: loginPlistURL)
            }
        } else {
            try? fm.removeItem(at: loginPlistURL)
        }
    }
    @objc private func doToggleLogin() { setLogin(!loginEnabled()); refresh() }

    // --- Welcome onboarding (spec §3): a live readiness checklist + action buttons.
    // Shown once at first-run (didOnboard in UserDefaults); always available from the
    // "Setup guide…" menu item. No secrets — only launching the same CLIs/toggles as the rest of the GUI. ---

    // Are all 3 CLIs installed? (We do not check them one by one — install.sh installs them as a set.)
    // No shell-out: `sh -lc` does not read ~/.zshrc, where install.sh tells you to add ~/.local/bin →
    // there would be a false ❌. We check the executables directly: process PATH + typical install dirs.
    private func clisInstalled() -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        dirs += [home + "/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"]
        for tool in ecosystemCLIs {
            guard dirs.contains(where: { fm.isExecutableFile(atPath: $0 + "/" + tool) }) else { return false }
        }
        return true
    }

    @objc private func doWelcome() {
        if let w = welcomeWindow {
            rebuildWelcome(in: w)   // the checklist is live on reopen too, not a stale snapshot
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 250),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        rebuildWelcome(in: w)
        welcomeWindow = w
        w.center(); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    // Rebuild the content (after every action — the checklist is live).
    private func rebuildWelcome(in w: NSWindow) {
        w.title = L("ob_title")   // here, not in doWelcome: a language change updates the title too
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 250))
        var y: CGFloat = 214
        func label(_ s: String, size: CGFloat = 13, color: NSColor = .labelColor, wrap: Bool = false) {
            let l = NSTextField(labelWithString: s)
            l.font = .systemFont(ofSize: size)
            l.textColor = color
            if wrap {
                // a long caption (the EN ob_sub, ~77 chars, does not fit 420px on one line) →
                // word wrap, 2 lines, increased step
                l.usesSingleLineMode = false
                l.lineBreakMode = .byWordWrapping
                l.maximumNumberOfLines = 2
                l.frame = NSRect(x: 20, y: y - 12, width: 420, height: 30)
                v.addSubview(l); y -= 36
            } else {
                l.frame = NSRect(x: 20, y: y, width: 420, height: 18)
                v.addSubview(l); y -= 26
            }
        }
        func actionButton(_ title: String, _ sel: Selector) {
            let b = NSButton(title: title, target: self, action: sel)
            b.bezelStyle = .rounded
            // y+22: return to the previous row (step 26) minus centering a 24px button in an 18px row
            b.frame = NSRect(x: 320, y: y + 22, width: 120, height: 24)
            v.addSubview(b)
        }
        label("🔒 Paranoid Bar", size: 15)
        label(L("ob_sub"), size: 11, color: .secondaryLabelColor, wrap: true)
        let cli = clisInstalled()
        label(checklistLine(ok: cli, okKey: "ob_cli_ok", missKey: "ob_cli_missing"))
        let hasVault = vaultExists()
        label(checklistLine(ok: hasVault, okKey: "ob_vault_ok", missKey: "ob_vault_missing"))
        if !hasVault { actionButton(L("ob_create_btn"), #selector(obCreateVault)) }
        let preset = hotkeyPreset()
        // Honest status: a valid preset AND a registration that actually took (the combination may
        // be taken by another app — then ⬜ + Enable, not a false ✅).
        let hk = hotkeyVK(preset: preset) != nil && hotkeyRegistered
        // The key caption follows the actual preset (P/L), not a hard-coded P as in the spec's simplification.
        let hkKey = preset == "ctrl-opt-shift-l" ? "⌃⌥⇧L" : "⌃⌥⇧P"
        label((hk ? "✅ " : "⬜ ") + L("ob_hotkey_line") + ": \(hkKey) (×2)")
        if !hk { actionButton(L("ob_enable_btn"), #selector(obEnableHotkey)) }
        let login = loginEnabled()
        label((login ? "✅ " : "⬜ ") + L("ob_login_line"))
        if !login { actionButton(L("ob_enable_btn"), #selector(obEnableLogin)) }
        label("⚠ " + L("ob_risk"), size: 11, color: .systemOrange)
        let done = NSButton(title: L("ob_done"), target: self, action: #selector(obDone))
        done.bezelStyle = .rounded; done.keyEquivalent = "\r"
        done.frame = NSRect(x: 360, y: 14, width: 80, height: 28)
        v.addSubview(done)
        w.contentView = v
    }

    @objc private func obCreateVault() { runInTerminal("securetrash vault create") }
    @objc private func obEnableHotkey() {
        // ASSUMPTION: Enable always turns on the default P; restoring the previous preset is Settings territory (T5)
        UserDefaults.standard.set("ctrl-opt-shift-p", forKey: "panicHotkey")
        hotkeyRegistered = registerPanicHotkey(preset: hotkeyPreset())
        if !hotkeyRegistered { notify(L("notif_hotkey_fail")) }
        // Resync an open Settings popup right away: its Save would otherwise silently roll back the new preset.
        hotkeyPopup?.selectItem(at: hotkeyValues.firstIndex(of: hotkeyPreset()) ?? 0)
        if let w = welcomeWindow { rebuildWelcome(in: w) }
    }
    @objc private func obEnableLogin() {
        setLogin(true)
        if let w = welcomeWindow { rebuildWelcome(in: w) }
    }
    @objc private func obDone() { welcomeWindow?.close() }

    // --- settings panel (vault mount-point override + poll interval) ---
    // Touches no secrets: only paths/interval, stored in UserDefaults, applied without a restart.
    @objc private func doSettings() {
        if let w = settingsWindow {
            // Resync the hidden cached window from the current state (settings may have changed from
            // outside, e.g. Welcome/Enable). A VISIBLE window is left alone: it may hold typed but
            // unsaved edits — hotkey consistency is kept by the resync in obEnableHotkey.
            if !w.isVisible {
                volField?.stringValue = vaultVolume
                pollField?.stringValue = String(Int(pollSeconds()))
                let langNow = UserDefaults.standard.string(forKey: "language") ?? "system"
                langPopup?.selectItem(at: langValues.firstIndex(of: langNow) ?? 0)
                hotkeyPopup?.selectItem(at: hotkeyValues.firstIndex(of: hotkeyPreset()) ?? 0)
            }
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 230),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("set_title")
        w.isReleasedWhenClosed = false
        let v = w.contentView!

        v.addSubview(settingsLabel(L("set_vol"), y: 190))
        let vol = NSTextField(frame: NSRect(x: 130, y: 186, width: 234, height: 24))
        vol.stringValue = vaultVolume
        v.addSubview(vol); volField = vol

        v.addSubview(settingsLabel(L("set_poll"), y: 150))
        let poll = NSTextField(frame: NSRect(x: 130, y: 146, width: 70, height: 24))
        poll.stringValue = String(Int(pollSeconds()))
        v.addSubview(poll); pollField = poll

        v.addSubview(settingsLabel(L("set_lang"), y: 110))
        let lang = NSPopUpButton(frame: NSRect(x: 130, y: 104, width: 150, height: 26))
        lang.addItems(withTitles: [L("lang_system"), "English", "Русский"])
        let langNow = UserDefaults.standard.string(forKey: "language") ?? "system"
        lang.selectItem(at: langValues.firstIndex(of: langNow) ?? 0)
        v.addSubview(lang); langPopup = lang

        v.addSubview(settingsLabel(L("set_hotkey"), y: 70))
        let hk = NSPopUpButton(frame: NSRect(x: 130, y: 64, width: 150, height: 26))
        hk.addItems(withTitles: ["⌃⌥⇧P", "⌃⌥⇧L", L("hk_off")])
        hk.selectItem(at: hotkeyValues.firstIndex(of: hotkeyPreset()) ?? 0)
        v.addSubview(hk); hotkeyPopup = hk

        let setup = NSButton(title: L("set_setup_btn"), target: self, action: #selector(doWelcome))
        setup.bezelStyle = .rounded
        setup.frame = NSRect(x: 16, y: 16, width: 160, height: 30)
        v.addSubview(setup)

        let save = NSButton(frame: NSRect(x: 274, y: 16, width: 90, height: 30))
        save.title = L("set_save"); save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        save.target = self; save.action = #selector(saveSettings)
        v.addSubview(save)

        settingsWindow = w
        w.center(); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func settingsLabel(_ s: String, y: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.frame = NSRect(x: 16, y: y, width: 110, height: 20)
        return l
    }

    @objc private func saveSettings() {
        if let vf = volField { UserDefaults.standard.set(vf.stringValue.trimmingCharacters(in: .whitespaces), forKey: "vaultVolume") }
        if let pf = pollField, let n = Int(pf.stringValue), n >= 5 {
            UserDefaults.standard.set(Double(clampPoll(n)), forKey: "pollSeconds")
        }
        if let lp = langPopup {
            UserDefaults.standard.set(langValues[max(0, lp.indexOfSelectedItem)], forKey: "language")
        }
        if let hp = hotkeyPopup {
            let hkValue = hotkeyValues[max(0, hp.indexOfSelectedItem)]
            UserDefaults.standard.set(hkValue, forKey: "panicHotkey")
            hotkeyRegistered = registerPanicHotkey(preset: hkValue)
            // off returns true → !hotkeyRegistered already excludes a deliberate removal
            if !hotkeyRegistered { notify(L("notif_hotkey_fail")) }
        }
        // Drop the whole window cache: on a language change the next doSettings recreates the labels.
        settingsWindow?.close()
        settingsWindow = nil; volField = nil; pollField = nil; langPopup = nil; hotkeyPopup = nil
        if let w = welcomeWindow { rebuildWelcome(in: w) }   // an open Welcome must not go stale
        rescheduleTimer()   // pick up the new interval
        refresh()           // pick up the new mount point (and language — the menu rebuilds)
    }

    // Run a command in Terminal.app — the user sees the output and types secrets directly into the
    // CLI, NOT through the GUI. Terminal.app starts a fresh shell that does NOT inherit the GUI's
    // environment → we prefix `ST_VAULT_VOLUME=<quoted>`, otherwise securetrash/paranoid would work
    // with the default vault while the GUI shows a custom one (parity with the Windows tray, which sets $env beforehand).
    private func runInTerminal(_ command: String) {
        let full = terminalEnvPrefix(volume: vaultVolume, path: vaultPath) + command
        // AppleScript string: escape backslashes BEFORE quotes (shQuote may introduce a `\`).
        let escaped = full
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\n  activate\n  do script \"\(escaped)\"\nend tell"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    // Read a short command's stdout (for status). Arguments as an array → no shell injection.
    private func capture(_ launchPath: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// --- selftest: pure logic without the GUI (analog of the Windows tray's ST_NO_MAIN). `./ParanoidBar --selftest`
// runs the asserts and exits; in CI/locally it is a gate together with compilation. ---
private func runSelfTests() -> Never {
    // under -O a precondition traps silently — our own expect() names the failed assert
    func expect(_ cond: Bool, _ what: String) {
        if !cond { FileHandle.standardError.write(Data("selftest FAIL: \(what)\n".utf8)); exit(1) }
    }
    // localization: the key exists in both tables, an unknown key is returned as-is
    expect(L("vault_closed", lang: "en") == "closed", "L vault_closed en")
    expect(L("vault_closed", lang: "ru") == "закрыт", "L vault_closed ru")
    expect(L("no_such_key", lang: "en") == "no_such_key", "L unknown key fallback")
    // The unknown vault state must have its own string in both tables: otherwise the menu
    // would silently show the key instead of the text.
    expect(L("vault_unknown", lang: "en") != "vault_unknown", "L vault_unknown en")
    expect(L("vault_unknown", lang: "ru") != "vault_unknown", "L vault_unknown ru")
    expect(L("vault_ask", lang: "ru") != "vault_ask", "L vault_ask ru")
    // onboarding: a checklist line from status (check/cross + localized text)
    expect(checklistLine(ok: true, okKey: "ob_cli_ok", missKey: "ob_cli_missing", lang: "en")
           == "✅ CLIs installed (all 5 tools + launcher)", "checklist ok en")
    // Terminal environment: both vault variables + correct escaping of a path with an apostrophe
    expect(terminalEnvPrefix(volume: "/Volumes/V", path: "/Users/me/V.sparsebundle")
           == "ST_VAULT_VOLUME='/Volumes/V' ST_VAULT_PATH='/Users/me/V.sparsebundle' ",
           "terminal env prefix carries both vault variables")
    expect(shellQuote("/Users/o'brien/V") == "'/Users/o'\\''brien/V'", "shellQuote escapes a quote")
    // readiness must cover the WHOLE set, including the launcher itself (AUDIT_2026-08-03 P2-9)
    expect(ecosystemCLIs.count == 6, "ecosystemCLIs covers all five tools plus the launcher")
    for tool in ["securetrash", "vaultwatch", "panic", "ghostdraft", "seedsplit", "paranoid"] {
        expect(ecosystemCLIs.contains(tool), "ecosystemCLIs contains \(tool)")
    }
    expect(checklistLine(ok: false, okKey: "ob_vault_ok", missKey: "ob_vault_missing", lang: "ru")
           == "❌ Сейф ещё не создан", "checklist miss ru")
    // language selection: an explicit override beats the system; "system" falls back to the locale prefix
    expect(resolveLang(override: "ru", systemLang: "en") == "ru", "resolveLang override ru")
    expect(resolveLang(override: "system", systemLang: "ru") == "ru", "resolveLang system ru")
    expect(resolveLang(override: "system", systemLang: "fr") == "en", "resolveLang system fr->en")   // non-RU → en
    // double-press: a second tick within the 2s window → fire; outside the window → re-arm
    let base = Date(timeIntervalSince1970: 2_000_000)
    expect(panicShouldFire(now: base, armedAt: nil) == false, "not armed no fire")
    expect(panicShouldFire(now: base.addingTimeInterval(1.5), armedAt: base) == true, "fire in window")
    expect(panicShouldFire(now: base.addingTimeInterval(2.0), armedAt: base) == true, "window boundary inclusive")
    expect(panicShouldFire(now: base.addingTimeInterval(2.5), armedAt: base) == false, "window passed")
    expect(panicShouldFire(now: base.addingTimeInterval(-5), armedAt: base) == false, "negative delta no fire")
    // hotkey preset sanitization: garbage/empty string → default P, valid values — as-is
    expect(sanitizeHotkeyPreset("garbage") == "ctrl-opt-shift-p", "sanitize garbage -> default")
    expect(sanitizeHotkeyPreset("off") == "off", "sanitize off unchanged")
    expect(sanitizeHotkeyPreset("ctrl-opt-shift-l") == "ctrl-opt-shift-l", "sanitize valid L unchanged")
    // poll interval clamp: floor 5, ceiling 3600, in range — unchanged
    expect(clampPoll(4) == 5, "clampPoll below floor")
    expect(clampPoll(999999) == 3600, "clampPoll above ceiling")
    expect(clampPoll(15) == 15, "clampPoll in range unchanged")
    // sameMount: path normalization (trailing slash) matches, different volumes — do not
    expect(sameMount("/Volumes/SecretVault", "/Volumes/SecretVault") == true, "sameMount identical")
    expect(sameMount("/Volumes/SecretVault/", "/Volumes/SecretVault") == true, "sameMount trailing slash")
    expect(sameMount("/Volumes/SecretVault", "/Volumes/OldVault") == false, "sameMount different volumes")
    // presets: mapping to virtual keys; off → nil (do not register)
    expect(hotkeyVK(preset: "ctrl-opt-shift-p") == UInt32(kVK_ANSI_P), "preset P")
    expect(hotkeyVK(preset: "ctrl-opt-shift-l") == UInt32(kVK_ANSI_L), "preset L")
    expect(hotkeyVK(preset: "off") == nil, "off nil")
    expect(hotkeyVK(preset: "garbage") == nil, "garbage nil")
    // the whole dictionary: no empty/placeholder values
    for (k, v) in strings { expect(!v.en.isEmpty && !v.ru.isEmpty, "empty value for \(k)") }
    // notification engine: each event once per episode, closing the vault resets everything
    var ns = NotifyState()
    var ev: [String]
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    (ev, ns) = decideNotifications(open: true, ttl: 90, hasSessions: true, now: t0, state: ns)
    expect(ev == ["ttl_warn"], "ttl<120 warns")
    (ev, ns) = decideNotifications(open: true, ttl: 80, hasSessions: true, now: t0, state: ns)
    expect(ev.isEmpty, "no repeat warn")
    (ev, ns) = decideNotifications(open: true, ttl: 0, hasSessions: true, now: t0, state: ns)
    expect(ev == ["ttl_expired"], "ttl==0 expired")
    (ev, ns) = decideNotifications(open: false, ttl: nil, hasSessions: false, now: t0, state: ns)
    expect(ev.isEmpty && ns.openSince == nil, "close resets")
    (ev, ns) = decideNotifications(open: true, ttl: nil, hasSessions: false, now: t0, state: ns)
    expect(ev.isEmpty && ns.openSince == t0, "episode starts")
    (ev, ns) = decideNotifications(open: true, ttl: nil, hasSessions: false,
                                   now: t0.addingTimeInterval(1801), state: ns)
    expect(ev == ["long_open"], "30min long_open")
    (ev, ns) = decideNotifications(open: true, ttl: nil, hasSessions: false,
                                   now: t0.addingTimeInterval(3600), state: ns)
    expect(ev.isEmpty, "no repeat long_open")
    // re-arm: a new/extended vaultwatch session (ttl≥120) re-arms the ttl warnings without
    // waiting for the vault to close — a repeat expiry within an episode must not stay silent
    (ev, ns) = decideNotifications(open: true, ttl: 90, hasSessions: true,
                                   now: t0.addingTimeInterval(3590), state: ns)
    expect(ev == ["ttl_warn"], "warn mid-episode")
    (ev, ns) = decideNotifications(open: true, ttl: 0, hasSessions: true,
                                   now: t0.addingTimeInterval(3600), state: ns)
    expect(ev == ["ttl_expired"], "expired mid-episode")
    (ev, ns) = decideNotifications(open: true, ttl: 300, hasSessions: true,
                                   now: t0.addingTimeInterval(3660), state: ns)
    expect(ev.isEmpty, "ttl>=120 silent re-arm")
    (ev, ns) = decideNotifications(open: true, ttl: 90, hasSessions: true,
                                   now: t0.addingTimeInterval(3900), state: ns)
    expect(ev == ["ttl_warn"], "re-armed warn after new session")
    // long_open is suppressed while a vaultwatch session is alive (even without a TTL)
    var ns2 = NotifyState()
    (ev, ns2) = decideNotifications(open: true, ttl: nil, hasSessions: true, now: t0, state: ns2)
    (ev, ns2) = decideNotifications(open: true, ttl: nil, hasSessions: true,
                                    now: t0.addingTimeInterval(1801), state: ns2)
    expect(ev.isEmpty, "long_open suppressed with live session")
    print("selftest OK")
    exit(0)
}
if CommandLine.arguments.contains("--selftest") { runSelfTests() }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar agent: no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
