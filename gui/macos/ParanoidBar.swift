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

// Точка монтирования vault — та же, что у securetrash (переопределяема через окружение).
private let vaultVolume = ProcessInfo.processInfo.environment["ST_VAULT_VOLUME"] ?? "/Volumes/SecretVault"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()
        // Периодический опрос статуса (дёшево: только наличие mountpoint + fdesetup).
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
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

    private func refresh() {
        let open = vaultOpen()
        statusItem.button?.title = open ? "🔓⚠" : "🔒"
        statusItem.button?.toolTip = open ? "Vault is OPEN — at risk while open" : "Vault closed"
        rebuildMenu(open: open)
    }

    // --- меню ---
    private func rebuildMenu(open: Bool) {
        let menu = NSMenu()
        menu.addItem(header("Vault:      " + (open ? "OPEN — at risk" : (vaultExists() ? "closed" : "not set up"))))
        menu.addItem(header("FileVault:  " + (fileVaultOn() ? "ON" : "off / unknown")))
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
