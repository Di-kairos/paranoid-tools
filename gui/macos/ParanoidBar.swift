// ParanoidBar — нативный menu-bar агент поверх тех же подписанных CLI Paranoid Tools (Фаза B).
//
// ЧЕСТНОСТЬ (как у bash-лаунчера Фазы A): GUI секретов НЕ держит и крипту НЕ добавляет. Он лишь
// показывает живой статус в строке меню и запускает те же CLI (securetrash / panic / paranoid),
// ничего не пряча. Деструктив и ввод пароля идут в сам CLI (открывается Terminal с его выводом) —
// секреты никогда не проходят через GUI. Это convenience-слой, не новый инструмент.
//
// Сборка (Command Line Tools достаточно): см. build.sh — `swiftc -O -o ParanoidBar ParanoidBar.swift`.
// Запуск как агента строки меню (без иконки в Dock) — через .app-бандл с LSUIElement=true; для
// подписи/нотаризации/упаковки нужен Apple Developer аккаунт (это шаг дистрибуции, см. gui/README.md).

import AppKit

// Точка монтирования vault — та же, что у securetrash. Приоритет: настройки (settings-панель) →
// окружение ST_VAULT_VOLUME → дефолт. Computed, чтобы подхватывать изменение настроек без рестарта.
private var vaultVolume: String {
    if let v = UserDefaults.standard.string(forKey: "vaultVolume"), !v.isEmpty { return v }
    return ProcessInfo.processInfo.environment["ST_VAULT_VOLUME"] ?? "/Volumes/SecretVault"
}
// Интервал опроса статуса (сек) из настроек; нижняя граница 5 с (батарея/CPU), дефолт 15.
private func pollSeconds() -> Double {
    let v = UserDefaults.standard.double(forKey: "pollSeconds")
    return v >= 5 ? v : 15
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private var volField: NSTextField?
    private var pollField: NSTextField?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()
        rescheduleTimer()   // периодический опрос статуса (интервал из настроек)
    }

    // Перезапустить таймер опроса с текущим интервалом (вызывается при старте и сохранении настроек).
    private func rescheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollSeconds(), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // --- статус (только чтение, как dashboard лаунчера) ---
    private func vaultOpen() -> Bool { FileManager.default.fileExists(atPath: vaultVolume) }
    private func vaultExists() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return FileManager.default.fileExists(atPath: home + "/SecureVault.sparsebundle")
    }
    private func fileVaultOn() -> Bool { capture("/usr/bin/fdesetup", ["status"]).contains("FileVault is On") }

    // --- статус vaultwatch (только чтение тех же session-файлов, что пишет vaultwatch CLI) ---
    private struct VWSession { let mount: String; let remaining: Int? }  // remaining=nil → сессия без TTL
    private var vwStateDir: String {
        ProcessInfo.processInfo.environment["VW_STATE_DIR"]
            ?? (FileManager.default.homeDirectoryForCurrentUser.path + "/.vaultwatch/sessions")
    }
    // Парсим key=value session-файлы (mount/started/ttl_secs). remaining = started+ttl_secs-now.
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
    // Формат как у vaultwatch CLI: "1h 5m 9s" / "5m 9s".
    private func fmtDuration(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? "\(h)h \(m)m \(sec)s" : "\(m)m \(sec)s"
    }

    private func refresh() {
        let open = vaultOpen()
        let sessions = vaultwatchSessions()
        let ttl = sessions.compactMap { $0.remaining }.min()   // ближайший авто-выход (если есть)
        // Текст справа от глифа: отсчёт TTL / «истёк» (⚠) / ⚠ при открытом сейфе / пусто.
        let suffix: String
        if let t = ttl { suffix = t == 0 ? " ⚠" : " " + fmtDuration(t) } else { suffix = open ? " ⚠" : "" }
        // Monochrome SF-Symbol глиф (template) — адаптируется под тёмную/светлую строку меню, в
        // отличие от цветного emoji. Fallback на emoji, если символ недоступен (до macOS 11).
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
        let tip = open ? "Vault is OPEN — at risk while open" : "Vault closed"
        if let t = ttl {
            statusItem.button?.toolTip = tip + (t == 0 ? " · vaultwatch TTL expired" : " · vaultwatch auto-exit in " + fmtDuration(t))
        } else {
            statusItem.button?.toolTip = tip
        }
        rebuildMenu(open: open, sessions: sessions)
    }

    // --- меню ---
    private func rebuildMenu(open: Bool, sessions: [VWSession]) {
        let menu = NSMenu()
        menu.addItem(header("Vault:      " + (open ? "OPEN — at risk" : (vaultExists() ? "closed" : "not set up"))))
        menu.addItem(header("FileVault:  " + (fileVaultOn() ? "ON" : "off / unknown")))
        // Активные vaultwatch-сессии: точка монтирования + обратный отсчёт TTL (или «no TTL»).
        for s in sessions {
            let name = (s.mount as NSString).lastPathComponent
            let detail: String
            if let r = s.remaining { detail = r == 0 ? "TTL expired" : "auto-exit in " + fmtDuration(r) }
            else { detail = "watching (no TTL)" }
            menu.addItem(header("vaultwatch: " + name + " — " + detail))
        }
        menu.addItem(.separator())

        menu.addItem(item("Status — full read-only check", #selector(doStatus)))
        menu.addItem(item("🔒  PANIC NOW — hide & lock", #selector(doPanic)))
        menu.addItem(.separator())

        // Подменю «Сейф» — зеркало группировки bash-лаунчера.
        let vault = NSMenu()
        vault.addItem(item(open ? "Close the vault" : (vaultExists() ? "Open the vault" : "Create a vault"), #selector(doVaultToggle)))
        vault.addItem(item("Empty — wipe contents, keep the vault", #selector(doVaultEmpty)))
        vault.addItem(item("Destroy the vault (irreversible)", #selector(doVaultDestroy)))
        let vaultItem = NSMenuItem(title: "Vault ▸", action: nil, keyEquivalent: "")
        vaultItem.submenu = vault
        menu.addItem(vaultItem)

        menu.addItem(item("Open the full launcher (paranoid)", #selector(doLauncher)))
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(doSettings)))
        // Автостарт при логине — галочка отражает текущее состояние LaunchAgent.
        let loginItem = item("Start at login", #selector(doToggleLogin))
        loginItem.state = loginEnabled() ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("Quit Paranoid Bar", #selector(doQuit)))
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

    // --- действия: запускают те же CLI; вывод/ввод видны в Terminal (GUI ничего не прячет) ---
    @objc private func doStatus()        { runInTerminal("securetrash check") }
    @objc private func doPanic()         { runInTerminal("panic now") }
    @objc private func doVaultToggle()   { runInTerminal("securetrash vault " + (vaultOpen() ? "close" : (vaultExists() ? "open" : "create"))) }
    @objc private func doVaultEmpty()    { runInTerminal("securetrash vault reset") }
    @objc private func doVaultDestroy()  { runInTerminal("securetrash vault destroy") }
    @objc private func doLauncher()      { runInTerminal("paranoid") }
    @objc private func doQuit()          { NSApp.terminate(nil) }

    // --- автостарт при логине (LaunchAgent) ---
    // Пишем per-user LaunchAgent plist напрямую: работает с НЕподписанной локальной сборкой (в
    // отличие от SMAppService.mainApp, которому нужна подпись/реестрация бандла). Указывает на
    // текущий исполняемый файл; .accessory-политика задаётся в коде, так что Dock-иконки не будет.
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

    // --- settings-панель (override точки монтирования vault + интервал опроса) ---
    // Секретов не касается: только пути/интервал, хранятся в UserDefaults, применяются без рестарта.
    @objc private func doSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Paranoid Bar — Settings"
        w.isReleasedWhenClosed = false
        let v = w.contentView!

        v.addSubview(settingsLabel("Vault volume:", y: 110))
        let vol = NSTextField(frame: NSRect(x: 130, y: 106, width: 234, height: 24))
        vol.stringValue = vaultVolume
        v.addSubview(vol); volField = vol

        v.addSubview(settingsLabel("Poll interval (s):", y: 70))
        let poll = NSTextField(frame: NSRect(x: 130, y: 66, width: 70, height: 24))
        poll.stringValue = String(Int(pollSeconds()))
        v.addSubview(poll); pollField = poll

        let save = NSButton(frame: NSRect(x: 274, y: 16, width: 90, height: 30))
        save.title = "Save"; save.bezelStyle = .rounded; save.keyEquivalent = "\r"
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
            UserDefaults.standard.set(Double(n), forKey: "pollSeconds")
        }
        settingsWindow?.close()
        rescheduleTimer()   // подхватить новый интервал
        refresh()           // подхватить новую точку монтирования
    }

    // Запустить команду в Terminal.app — пользователь видит вывод и вводит секреты прямо в CLI,
    // НЕ через GUI. AppleScript-строка экранирует кавычки; команды фиксированы (не из польз. ввода).
    private func runInTerminal(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\n  activate\n  do script \"\(escaped)\"\nend tell"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }

    // Прочитать stdout короткой команды (для статуса). Аргументы массивом → нет shell-инъекций.
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

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // агент строки меню: без иконки в Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
