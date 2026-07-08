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

// --- локализация: словарь в коде (без .lproj — single-file принцип). Ключи зеркалятся
// в Windows-tray ($PtStrings); паритет наборов проверяется тестом (Task 11). Честные формулировки
// («at risk») переводим без смягчения. ---
private let strings: [String: (en: String, ru: String)] = [
    "vault_label":      ("Vault:", "Сейф:"),
    "vault_open_risk":  ("OPEN — at risk", "ОТКРЫТ — под риском"),
    "vault_closed":     ("closed", "закрыт"),
    "vault_not_setup":  ("not set up", "не создан"),
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
    "set_vol":          ("Vault volume:", "Том сейфа:"),
    "set_poll":         ("Poll interval (s):", "Интервал опроса (с):"),
    "set_lang":         ("Language:", "Язык:"),
    "set_hotkey":       ("Panic hotkey:", "Хоткей паники:"),
    "set_save":         ("Save", "Сохранить"),
    "set_setup_btn":    ("Show setup guide", "Показать гид"),
    "hk_off":           ("Off", "Выкл"),
    "ob_title":         ("Paranoid Bar — Welcome", "Paranoid Bar — Добро пожаловать"),
    "ob_sub":           ("A status bar over the same signed CLIs. Secrets never pass through the GUI.",
                         "Панель статуса поверх тех же подписанных CLI. Секреты через GUI не проходят."),
    "ob_cli_ok":        ("CLIs installed (securetrash, panic, vaultwatch)", "CLI установлены (securetrash, panic, vaultwatch)"),
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

// Выбор языка: override из настроек ("en"/"ru") бьёт систему; "system" → префикс локали,
// всё не-русское схлопывается в en. Чистая функция — гоняется в selftest.
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

// --- уведомления: чистый движок решений (selftest) + доставка через osascript.
// UNUserNotificationCenter требует .app-бандл с identity — неподписанный бинарь падает,
// поэтому display notification через osascript (работает у голого исполняемого). ---
struct NotifyState: Equatable {
    var ttlWarned = false          // «авто-закроется через N» уже показано в этом эпизоде
    var ttlExpiredWarned = false   // «TTL истёк» уже показано
    var longOpenWarned = false     // «открыт 30+ мин» уже показано
    var openSince: Date? = nil     // начало текущего эпизода «сейф открыт»
                                   // (= первый опрос, увидевший open; рестарт GUI сбрасывает отсчёт)
}
// Правила (спека §2): TTL<120с → ttl_warn; TTL==0 при открытом → ttl_expired; открыт >30 мин
// БЕЗ vaultwatch-сессии → long_open. Каждое — однократно за эпизод; закрытие сейфа сбрасывает.
// Имена событий-строк намеренно зеркалят Windows-tray (Get-PtNotifyEvents) — не заменять на enum.
func decideNotifications(open: Bool, ttl: Int?, hasSessions: Bool, now: Date,
                         state: NotifyState) -> ([String], NotifyState) {
    var s = state
    guard open else { return ([], NotifyState()) }         // закрыт → сброс эпизода
    if s.openSince == nil { s.openSince = now }
    var events: [String] = []
    if let t = ttl, t >= 120 { s.ttlWarned = false; s.ttlExpiredWarned = false }   // новая/продлённая сессия → перевзвод
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private var volField: NSTextField?
    private var pollField: NSTextField?
    private var notifyState = NotifyState()

    // Доставка нативного уведомления. Секретов в тексте нет — только статус.
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
    // Реально СМОНТИРОВАН, а не «путь существует» (остаток каталога /Volumes/… давал ложное OPEN, P2-10).
    private func vaultOpen() -> Bool {
        let target = URL(fileURLWithPath: vaultVolume).standardizedFileURL
        guard let vols = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) else {
            return FileManager.default.fileExists(atPath: vaultVolume)   // API недоступен → старое поведение
        }
        return vols.contains { $0.standardizedFileURL == target }
    }
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
        // TTL показываем ТОЛЬКО при реально открытом сейфе: осиротевший session-файл иначе рисовал бы
        // «auto-exit in …» при закрытом vault (P2-10). Закрыт → никакого отсчёта.
        let ttl = open ? sessions.compactMap { $0.remaining }.min() : nil   // ближайший авто-выход
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
        let tip = open ? L("tip_open") : L("tip_closed")
        if let t = ttl {
            statusItem.button?.toolTip = tip + (t == 0 ? " · vaultwatch " + L("ttl_expired") : " · vaultwatch " + L("auto_exit_in") + " " + fmtDuration(t))
        } else {
            statusItem.button?.toolTip = tip
        }
        rebuildMenu(open: open, sessions: sessions)

        let (events, newState) = decideNotifications(
            open: open, ttl: ttl, hasSessions: !sessions.isEmpty, now: Date(), state: notifyState)
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

    // --- меню ---
    private func rebuildMenu(open: Bool, sessions: [VWSession]) {
        let menu = NSMenu()
        menu.addItem(header(L("vault_label") + "      " + (open ? L("vault_open_risk") : (vaultExists() ? L("vault_closed") : L("vault_not_setup")))))
        menu.addItem(header(L("fv_label") + "  " + (fileVaultOn() ? L("fv_on") : L("fv_off"))))
        // Активные vaultwatch-сессии: точка монтирования + обратный отсчёт TTL (или «no TTL»).
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

        // Подменю «Сейф» — зеркало группировки bash-лаунчера. autoenablesItems=false, иначе AppKit
        // сам включит пункты по наличию target (наш disable не удержится).
        let vault = NSMenu()
        vault.autoenablesItems = false
        let hasVault = vaultExists()
        vault.addItem(item(open ? L("vault_close") : (hasVault ? L("vault_open") : L("vault_create")), #selector(doVaultToggle)))
        // Empty/Destroy имеют смысл только при существующем контейнере — иначе grey-out, чтобы
        // деструктив не был активен «в пустоту» (P2-7).
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
        // Автостарт при логине — галочка отражает текущее состояние LaunchAgent.
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

        v.addSubview(settingsLabel(L("set_vol"), y: 110))
        let vol = NSTextField(frame: NSRect(x: 130, y: 106, width: 234, height: 24))
        vol.stringValue = vaultVolume
        v.addSubview(vol); volField = vol

        v.addSubview(settingsLabel(L("set_poll"), y: 70))
        let poll = NSTextField(frame: NSRect(x: 130, y: 66, width: 70, height: 24))
        poll.stringValue = String(Int(pollSeconds()))
        v.addSubview(poll); pollField = poll

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
            UserDefaults.standard.set(Double(n), forKey: "pollSeconds")
        }
        settingsWindow?.close()
        rescheduleTimer()   // подхватить новый интервал
        refresh()           // подхватить новую точку монтирования
    }

    // Обернуть значение в одинарные кавычки для shell (экранируя внутренние `'`). Нужно,
    // чтобы префикс ST_VAULT_VOLUME пережил произвольный путь сейфа.
    private func shQuote(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // Запустить команду в Terminal.app — пользователь видит вывод и вводит секреты прямо в CLI,
    // НЕ через GUI. Terminal.app стартует свежий shell, который НЕ наследует окружение GUI →
    // префиксуем `ST_VAULT_VOLUME=<quoted>`, иначе securetrash/paranoid работали бы с дефолтным
    // сейфом, пока GUI показывает кастомный (паритет с Windows-tray, который ставит $env заранее).
    private func runInTerminal(_ command: String) {
        let full = "ST_VAULT_VOLUME=\(shQuote(vaultVolume)) " + command
        // AppleScript-строка: экранируем backslash ПЕРЕД кавычками (shQuote может внести `\`).
        let escaped = full
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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

// --- selftest: чистая логика без GUI (аналог ST_NO_MAIN у Windows-tray). `./ParanoidBar --selftest`
// гоняет ассерты и выходит; в CI/локально это гейт вместе с компиляцией. ---
private func runSelfTests() -> Never {
    // под -O precondition трапается молча — свой expect() даёт имя упавшего ассерта
    func expect(_ cond: Bool, _ what: String) {
        if !cond { FileHandle.standardError.write(Data("selftest FAIL: \(what)\n".utf8)); exit(1) }
    }
    // локализация: ключ есть в обеих таблицах, неизвестный ключ возвращается как есть
    expect(L("vault_closed", lang: "en") == "closed", "L vault_closed en")
    expect(L("vault_closed", lang: "ru") == "закрыт", "L vault_closed ru")
    expect(L("no_such_key", lang: "en") == "no_such_key", "L unknown key fallback")
    // выбор языка: явный override бьёт систему; "system" падает на префикс локали
    expect(resolveLang(override: "ru", systemLang: "en") == "ru", "resolveLang override ru")
    expect(resolveLang(override: "system", systemLang: "ru") == "ru", "resolveLang system ru")
    expect(resolveLang(override: "system", systemLang: "fr") == "en", "resolveLang system fr->en")   // не-RU → en
    // весь словарь: нет пустых/placeholder значений
    for (k, v) in strings { expect(!v.en.isEmpty && !v.ru.isEmpty, "empty value for \(k)") }
    // движок уведомлений: каждое событие один раз за эпизод, закрытие сейфа сбрасывает всё
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
    // re-arm: новая/продлённая vaultwatch-сессия (ttl≥120) перевзводит ttl-предупреждения,
    // не дожидаясь закрытия сейфа — повторное истечение внутри эпизода не должно молчать
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
    // long_open подавляется, пока жива vaultwatch-сессия (даже без TTL)
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
app.setActivationPolicy(.accessory)   // агент строки меню: без иконки в Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
