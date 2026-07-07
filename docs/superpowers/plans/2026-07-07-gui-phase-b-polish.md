# GUI Phase B — UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Довести `gui/macos/ParanoidBar.swift` и `gui/windows/paranoid-tray.ps1` до продукт-уровня: глобальный хоткей паники (double-press), уведомления, Welcome-онбординг, RU/EN локализация, расширенные Settings — с полным паритетом платформ и тестами.

**Architecture:** Архитектура НЕ меняется: single-file Swift (голый `swiftc`, без Xcode) + single-file PowerShell, ноль новых зависимостей. GUI секретов не держит и крипту не добавляет — все действия запускают те же CLI в терминале/консоли. Чистая логика (double-press, решение об уведомлениях, локаль) — в тестируемых функциях: Swift через `--selftest`-режим бинаря, ps1 через Pester (`ST_NO_MAIN=1` dot-source, как сейчас).

**Tech Stack:** Swift/AppKit + Carbon (`RegisterEventHotKey`), `osascript display notification`; PowerShell/WinForms + `RegisterHotKey` (P/Invoke через `Add-Type`), `NotifyIcon.ShowBalloonTip`; Pester; bats не затрагивается.

**Спека:** `docs/superpowers/specs/2026-07-07-gui-phase-b-polish-design.md`.

**Процесс:** после каждого таска — commit. Перед финальным push — Codex-ревью diff (процесс проекта). `pwsh` на рабочей машине НЕТ — Pester-тесты проверяет Windows CI (`gui/windows/test` на `windows-latest`); локально гейт = `swiftc` компиляция + `--selftest`. Если `command -v pwsh` вдруг есть — гонять Pester локально тоже.

---

## Общий словарь локализации (истина для обеих платформ)

Ключи ОДИНАКОВЫ на обеих платформах (паритет проверяется тестом Task 11). Значения:

| key | en | ru |
|---|---|---|
| `vault_label` | `Vault:` | `Сейф:` |
| `vault_open_risk` | `OPEN — at risk` | `ОТКРЫТ — под риском` |
| `vault_closed` | `closed` | `закрыт` |
| `vault_not_setup` | `not set up` | `не создан` |
| `fv_label` | `FileVault:` | `FileVault:` |
| `fv_on` | `ON` | `включён` |
| `fv_off` | `off / unknown` | `выкл / неизвестно` |
| `status_item` | `Status — full read-only check` | `Статус — полная read-only проверка` |
| `panic_item` | `PANIC NOW — hide & lock` | `ПАНИКА — спрятать и заблокировать` |
| `vault_menu` | `Vault` | `Сейф` |
| `vault_close` | `Close the vault` | `Закрыть сейф` |
| `vault_open` | `Open the vault` | `Открыть сейф` |
| `vault_create` | `Create a vault` | `Создать сейф` |
| `vault_empty` | `Empty — wipe contents, keep the vault` | `Очистить — стереть содержимое, сейф оставить` |
| `vault_destroy` | `Destroy the vault (irreversible)` | `Уничтожить сейф (необратимо)` |
| `launcher_item` | `Open the full launcher (paranoid)` | `Открыть полный лаунчер (paranoid)` |
| `settings_item` | `Settings…` | `Настройки…` |
| `login_item` | `Start at login` | `Запускать при входе` |
| `setup_item` | `Setup guide…` | `Гид по настройке…` |
| `quit_item` | `Quit Paranoid Bar` | `Выйти из Paranoid Bar` |
| `ttl_expired` | `TTL expired` | `TTL истёк` |
| `auto_exit_in` | `auto-exit in` | `авто-выход через` |
| `watching_no_ttl` | `watching (no TTL)` | `наблюдение (без TTL)` |
| `tip_open` | `Vault is OPEN — at risk while open` | `Сейф ОТКРЫТ — под риском, пока открыт` |
| `tip_closed` | `Vault closed` | `Сейф закрыт` |
| `notif_ttl_warn` | `Vault auto-closes in {0}` | `Сейф авто-закроется через {0}` |
| `notif_ttl_expired` | `vaultwatch TTL expired — vault is still OPEN` | `TTL vaultwatch истёк — сейф всё ещё ОТКРЫТ` |
| `notif_long_open` | `Vault open for 30+ minutes (no vaultwatch)` | `Сейф открыт дольше 30 минут (без vaultwatch)` |
| `notif_panic_arm` | `Press again to PANIC` | `Нажмите ещё раз для ПАНИКИ` |
| `set_vol` | `Vault volume:` | `Том сейфа:` |
| `set_poll` | `Poll interval (s):` | `Интервал опроса (с):` |
| `set_lang` | `Language:` | `Язык:` |
| `set_hotkey` | `Panic hotkey:` | `Хоткей паники:` |
| `set_save` | `Save` | `Сохранить` |
| `set_setup_btn` | `Show setup guide` | `Показать гид` |
| `hk_off` | `Off` | `Выкл` |
| `ob_title` | `Paranoid Bar — Welcome` | `Paranoid Bar — Добро пожаловать` |
| `ob_sub` | `A status bar over the same signed CLIs. Secrets never pass through the GUI.` | `Панель статуса поверх тех же подписанных CLI. Секреты через GUI не проходят.` |
| `ob_cli_ok` | `CLIs installed (securetrash, panic, vaultwatch)` | `CLI установлены (securetrash, panic, vaultwatch)` |
| `ob_cli_missing` | `CLIs not found — install first` | `CLI не найдены — сначала установите` |
| `ob_vault_ok` | `Vault created` | `Сейф создан` |
| `ob_vault_missing` | `No vault yet` | `Сейф ещё не создан` |
| `ob_create_btn` | `Create vault…` | `Создать сейф…` |
| `ob_hotkey_line` | `Panic hotkey` | `Хоткей паники` |
| `ob_login_line` | `Start at login` | `Запускать при входе` |
| `ob_enable_btn` | `Enable` | `Включить` |
| `ob_risk` | `An open vault is always “at risk” — the GUI never hides that.` | `Открытый сейф всегда «под риском» — GUI этого не прячет.` |
| `ob_done` | `Done` | `Готово` |

Хоткей-пресеты (оба конца): `ctrl-opt-shift-p` (дефолт), `ctrl-opt-shift-l`, `off`.
Язык: `system` (дефолт) / `en` / `ru`.

---

### Task 1: macOS — selftest-каркас + локализация L()

**Files:**
- Modify: `gui/macos/ParanoidBar.swift` (file-scope функции до `class AppDelegate`, точка входа внизу)

- [ ] **Step 1: Написать падающий selftest**

В самый низ `ParanoidBar.swift`, ПЕРЕД `let app = NSApplication.shared`, добавить:

```swift
// --- selftest: чистая логика без GUI (аналог ST_NO_MAIN у Windows-tray). `./ParanoidBar --selftest`
// гоняет ассерты и выходит; в CI/локально это гейт вместе с компиляцией. ---
private func runSelfTests() -> Never {
    // локализация: ключ есть в обеих таблицах, неизвестный ключ возвращается как есть
    precondition(L("vault_closed", lang: "en") == "closed")
    precondition(L("vault_closed", lang: "ru") == "закрыт")
    precondition(L("no_such_key", lang: "en") == "no_such_key")
    // выбор языка: явный override бьёт систему; "system" падает на префикс локали
    precondition(resolveLang(override: "ru", systemLang: "en") == "ru")
    precondition(resolveLang(override: "system", systemLang: "ru") == "ru")
    precondition(resolveLang(override: "system", systemLang: "fr") == "en")   // не-RU → en
    print("selftest OK")
    exit(0)
}
if CommandLine.arguments.contains("--selftest") { runSelfTests() }
```

- [ ] **Step 2: Убедиться, что не компилируется (L/resolveLang нет)**

Run: `cd "/Volumes/X10 Pro/projects/paranoid-tools/gui/macos" && ./build.sh`
Expected: FAIL — `cannot find 'L' in scope`.

- [ ] **Step 3: Реализовать словарь + L() + resolveLang()**

В file-scope (после `pollSeconds()`, до `class AppDelegate`):

```swift
// --- локализация: словарь в коде (без .lproj — single-file принцип). Ключи зеркалятся
// в Windows-tray ($PtStrings); паритет наборов проверяется тестом. Честные формулировки
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
```

- [ ] **Step 4: Компиляция + selftest зелёные**

Run: `./build.sh && ./ParanoidBar --selftest`
Expected: `Built ./ParanoidBar` + `selftest OK`.

- [ ] **Step 5: Перевести существующие строки на L()**

В `rebuildMenu`/`refresh`/`doSettings` заменить хардкод:
- `"Vault:      " + (open ? "OPEN — at risk" : …)` → `L("vault_label") + "      " + (open ? L("vault_open_risk") : (vaultExists() ? L("vault_closed") : L("vault_not_setup")))`
- `"FileVault:  " + (fileVaultOn() ? "ON" : "off / unknown")` → `L("fv_label") + "  " + (fileVaultOn() ? L("fv_on") : L("fv_off"))`
- `"Status — full read-only check"` → `L("status_item")`; `"🔒  PANIC NOW — hide & lock"` → `"🔒  " + L("panic_item")`
- Vault-подменю: `L("vault_close")` / `L("vault_open")` / `L("vault_create")` / `L("vault_empty")` / `L("vault_destroy")`; `"Vault ▸"` → `L("vault_menu") + " ▸"`
- `L("launcher_item")`, `L("settings_item")`, `L("login_item")`, `L("quit_item")`
- vaultwatch-строка: `detail = r == 0 ? L("ttl_expired") : L("auto_exit_in") + " " + fmtDuration(r)`; `L("watching_no_ttl")`
- tooltip: `L("tip_open")` / `L("tip_closed")` + `" · vaultwatch " + L("ttl_expired")` / `" · vaultwatch " + L("auto_exit_in") + " " + fmtDuration(t)`
- settings-панель: `L("set_vol")`, `L("set_poll")`, `L("set_save")`; заголовок окна оставить `"Paranoid Bar — Settings"` (имя продукта).

- [ ] **Step 6: Компиляция + selftest + ручной запуск**

Run: `./build.sh && ./ParanoidBar --selftest && ./ParanoidBar & sleep 3 && kill %1`
Expected: компилируется, selftest OK, глиф появляется в menu bar (глазами), меню на языке системы.

- [ ] **Step 7: Commit**

```bash
cd "/Volumes/X10 Pro/projects/paranoid-tools"
git add gui/macos/ParanoidBar.swift
git commit -m "feat(gui/macos): RU/EN localization + --selftest harness"
```

---

### Task 2: macOS — уведомления (движок решений + osascript)

**Files:**
- Modify: `gui/macos/ParanoidBar.swift`

- [ ] **Step 1: Падающие selftest-ассерты движка**

В `runSelfTests()` перед `print("selftest OK")` добавить:

```swift
    // движок уведомлений: каждое событие один раз за эпизод, закрытие сейфа сбрасывает всё
    var ns = NotifyState()
    var ev: [String]
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    (ev, ns) = decideNotifications(open: true, ttl: 90, hasSessions: true, now: t0, state: ns)
    precondition(ev == ["ttl_warn"])                       // TTL < 120с → предупредить
    (ev, ns) = decideNotifications(open: true, ttl: 80, hasSessions: true, now: t0, state: ns)
    precondition(ev.isEmpty)                               // повторно не спамим
    (ev, ns) = decideNotifications(open: true, ttl: 0, hasSessions: true, now: t0, state: ns)
    precondition(ev == ["ttl_expired"])                    // истёк, сейф открыт
    (ev, ns) = decideNotifications(open: false, ttl: nil, hasSessions: false, now: t0, state: ns)
    precondition(ev.isEmpty && ns.openSince == nil)        // закрыли → полный сброс
    (ev, ns) = decideNotifications(open: true, ttl: nil, hasSessions: false, now: t0, state: ns)
    precondition(ev.isEmpty && ns.openSince == t0)         // старт эпизода без vaultwatch
    (ev, ns) = decideNotifications(open: true, ttl: nil, hasSessions: false,
                                   now: t0.addingTimeInterval(1801), state: ns)
    precondition(ev == ["long_open"])                      // 30+ мин без vaultwatch — один раз
    (ev, ns) = decideNotifications(open: true, ttl: nil, hasSessions: false,
                                   now: t0.addingTimeInterval(3600), state: ns)
    precondition(ev.isEmpty)
```

- [ ] **Step 2: Убедиться, что не компилируется**

Run: `./build.sh`
Expected: FAIL — `cannot find 'NotifyState' in scope`.

- [ ] **Step 3: Реализовать NotifyState + decideNotifications + notify()**

File-scope (после L()):

```swift
// --- уведомления: чистый движок решений (selftest) + доставка через osascript.
// UNUserNotificationCenter требует .app-бандл с identity — неподписанный бинарь падает,
// поэтому display notification через osascript (работает у голого исполняемого). ---
struct NotifyState: Equatable {
    var ttlWarned = false          // «авто-закроется через N» уже показано в этом эпизоде
    var ttlExpiredWarned = false   // «TTL истёк» уже показано
    var longOpenWarned = false     // «открыт 30+ мин» уже показано
    var openSince: Date? = nil     // начало текущего эпизода «сейф открыт»
}
// Правила (спека §2): TTL<120с → ttl_warn; TTL==0 при открытом → ttl_expired; открыт >30 мин
// БЕЗ vaultwatch-сессии → long_open. Каждое — однократно за эпизод; закрытие сейфа сбрасывает.
func decideNotifications(open: Bool, ttl: Int?, hasSessions: Bool, now: Date,
                         state: NotifyState) -> ([String], NotifyState) {
    var s = state
    guard open else { return ([], NotifyState()) }         // закрыт → сброс эпизода
    if s.openSince == nil { s.openSince = now }
    var events: [String] = []
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
```

В `AppDelegate` — поле + доставка + вызов из `refresh()`:

```swift
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
```

В конце `refresh()` (после `rebuildMenu(...)`):

```swift
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
```

ВНИМАНИЕ: `fmtDuration` сейчас метод `AppDelegate` — оставить как есть (вызов идёт из метода).

- [ ] **Step 4: Компиляция + selftest зелёные**

Run: `./build.sh && ./ParanoidBar --selftest`
Expected: `selftest OK`.

- [ ] **Step 5: Commit**

```bash
git add gui/macos/ParanoidBar.swift
git commit -m "feat(gui/macos): native notifications — TTL warn/expired, long-open reminder"
```

---

### Task 3: macOS — глобальный хоткей паники (double-press)

**Files:**
- Modify: `gui/macos/ParanoidBar.swift`

- [ ] **Step 1: Падающие selftest-ассерты double-press**

В `runSelfTests()` добавить:

```swift
    // double-press: второй тик в окне 2с → огонь; вне окна → перевзвод
    let base = Date(timeIntervalSince1970: 2_000_000)
    precondition(panicShouldFire(now: base, armedAt: nil) == false)                          // не взведён
    precondition(panicShouldFire(now: base.addingTimeInterval(1.5), armedAt: base) == true)  // в окне
    precondition(panicShouldFire(now: base.addingTimeInterval(2.5), armedAt: base) == false) // окно ушло
    // пресеты: маппинг в виртуальные клавиши; off → nil (не регистрировать)
    precondition(hotkeyVK(preset: "ctrl-opt-shift-p") == UInt32(kVK_ANSI_P))
    precondition(hotkeyVK(preset: "ctrl-opt-shift-l") == UInt32(kVK_ANSI_L))
    precondition(hotkeyVK(preset: "off") == nil)
    precondition(hotkeyVK(preset: "garbage") == nil)
```

- [ ] **Step 2: Убедиться, что не компилируется**

Run: `./build.sh`
Expected: FAIL — `cannot find 'panicShouldFire' in scope`.

- [ ] **Step 3: Реализовать хоткей**

Вверху файла: `import Carbon.HIToolbox` (после `import AppKit`).

File-scope:

```swift
// --- глобальный хоткей паники (Carbon RegisterEventHotKey; работает без Accessibility-разрешений,
// в отличие от CGEventTap). Двойное нажатие в 2с → panic now БЕЗ confirm (panic обратим: прячет
// и лочит, данные не трогает; ASSUMPTION из спеки). Одиночное — взвод + уведомление. ---
func panicShouldFire(now: Date, armedAt: Date?, window: TimeInterval = 2.0) -> Bool {
    guard let a = armedAt else { return false }
    return now.timeIntervalSince(a) <= window
}
// Пресет → виртуальная клавиша (модификаторы у всех пресетов одни: ⌃⌥⇧). nil → не регистрировать.
func hotkeyVK(preset: String) -> UInt32? {
    switch preset {
    case "ctrl-opt-shift-p": return UInt32(kVK_ANSI_P)
    case "ctrl-opt-shift-l": return UInt32(kVK_ANSI_L)
    default: return nil
    }
}
// Carbon C-callback не captures Swift-контекст → глобальный хук на действие.
private var panicHotkeyAction: (() -> Void)?
private var panicHotKeyRef: EventHotKeyRef?
private var hotkeyHandlerInstalled = false
func installHotkeyHandlerOnce() {
    guard !hotkeyHandlerInstalled else { return }
    hotkeyHandlerInstalled = true
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        panicHotkeyAction?()
        return noErr
    }, 1, &spec, nil, nil)
}
func registerPanicHotkey(preset: String) {
    if let ref = panicHotKeyRef { UnregisterEventHotKey(ref); panicHotKeyRef = nil }
    guard let vk = hotkeyVK(preset: preset) else { return }   // off/мусор → снято
    installHotkeyHandlerOnce()
    let id = EventHotKeyID(signature: OSType(0x50424152), id: 1)   // 'PBAR'
    RegisterEventHotKey(vk, UInt32(controlKey | optionKey | shiftKey), id,
                        GetApplicationEventTarget(), 0, &panicHotKeyRef)
}
// Пресет из настроек (дефолт — включён: хоткей и есть смысл Фазы B).
func hotkeyPreset() -> String {
    UserDefaults.standard.string(forKey: "panicHotkey") ?? "ctrl-opt-shift-p"
}
```

В `AppDelegate`:

```swift
    private var panicArmedAt: Date?

    private func hotkeyPressed() {
        let now = Date()
        if panicShouldFire(now: now, armedAt: panicArmedAt) {
            panicArmedAt = nil
            runInTerminal("panic now")
        } else {
            panicArmedAt = now
            notify(L("notif_panic_arm"))
        }
    }
```

В `applicationDidFinishLaunching` после `rescheduleTimer()`:

```swift
        panicHotkeyAction = { [weak self] in self?.hotkeyPressed() }
        registerPanicHotkey(preset: hotkeyPreset())
```

- [ ] **Step 4: Компиляция + selftest + ручная проверка хоткея**

Run: `./build.sh && ./ParanoidBar --selftest`
Expected: `selftest OK`.
Ручной прогон: запустить `./ParanoidBar`, нажать ⌃⌥⇧P один раз → уведомление «Press again to PANIC»; дважды подряд → открывается Terminal с `panic now`. Убить приложение.

- [ ] **Step 5: Commit**

```bash
git add gui/macos/ParanoidBar.swift
git commit -m "feat(gui/macos): global panic hotkey — double-press within 2s fires panic now"
```

---

### Task 4: macOS — Welcome-онбординг (вариант A из спеки)

**Files:**
- Modify: `gui/macos/ParanoidBar.swift`

- [ ] **Step 1: Написать чекеры готовности + падающий selftest**

В `runSelfTests()`:

```swift
    // онбординг: строка чеклиста из статуса (галка/крест + локализованный текст)
    precondition(checklistLine(ok: true, okKey: "ob_cli_ok", missKey: "ob_cli_missing", lang: "en")
                 == "✅ CLIs installed (securetrash, panic, vaultwatch)")
    precondition(checklistLine(ok: false, okKey: "ob_vault_ok", missKey: "ob_vault_missing", lang: "ru")
                 == "❌ Сейф ещё не создан")
```

Run: `./build.sh` → Expected: FAIL — `cannot find 'checklistLine'`.

- [ ] **Step 2: Реализовать онбординг**

File-scope:

```swift
// Строка чеклиста Welcome-окна — чистая для selftest.
func checklistLine(ok: Bool, okKey: String, missKey: String, lang: String? = nil) -> String {
    (ok ? "✅ " + L(okKey, lang: lang) : "❌ " + L(missKey, lang: lang))
}
```

В `AppDelegate` — поля и окно:

```swift
    private var welcomeWindow: NSWindow?

    // Все 3 CLI на PATH? (по одному не проверяем — install.sh ставит комплектом)
    private func clisInstalled() -> Bool {
        for tool in ["securetrash", "panic", "vaultwatch"] {
            if capture("/bin/sh", ["-lc", "command -v \(tool)"]).isEmpty { return false }
        }
        return true
    }

    // Welcome-окно (спека §3): живой чеклист + кнопки-действия. Показ один раз при first-run
    // (didOnboard); всегда доступно из меню «Setup guide…».
    @objc func doWelcome() {
        if let w = welcomeWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 250),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("ob_title")
        w.isReleasedWhenClosed = false
        rebuildWelcome(in: w)
        welcomeWindow = w
        w.center(); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    // Пересборка контента (после каждого действия — чеклист живой).
    private func rebuildWelcome(in w: NSWindow) {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 250))
        var y: CGFloat = 214
        func label(_ s: String, size: CGFloat = 13, color: NSColor = .labelColor) {
            let l = NSTextField(labelWithString: s)
            l.font = .systemFont(ofSize: size)
            l.textColor = color
            l.frame = NSRect(x: 20, y: y, width: 420, height: 18)
            v.addSubview(l); y -= 26
        }
        func actionButton(_ title: String, _ sel: Selector) {
            let b = NSButton(title: title, target: self, action: sel)
            b.bezelStyle = .rounded
            b.frame = NSRect(x: 320, y: y + 22, width: 120, height: 24)
            v.addSubview(b)
        }
        label("🔒 Paranoid Bar", size: 15)
        label(L("ob_sub"), size: 11, color: .secondaryLabelColor)
        let cli = clisInstalled()
        label(checklistLine(ok: cli, okKey: "ob_cli_ok", missKey: "ob_cli_missing"))
        let hasVault = vaultExists()
        label(checklistLine(ok: hasVault, okKey: "ob_vault_ok", missKey: "ob_vault_missing"))
        if !hasVault { actionButton(L("ob_create_btn"), #selector(obCreateVault)) }
        let hk = hotkeyPreset() != "off"
        label((hk ? "✅ " : "⬜ ") + L("ob_hotkey_line") + ": ⌃⌥⇧P (×2)")
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
        UserDefaults.standard.set("ctrl-opt-shift-p", forKey: "panicHotkey")
        registerPanicHotkey(preset: hotkeyPreset())
        if let w = welcomeWindow { rebuildWelcome(in: w) }
    }
    @objc private func obEnableLogin() {
        setLogin(true)
        if let w = welcomeWindow { rebuildWelcome(in: w) }
    }
    @objc private func obDone() { welcomeWindow?.close() }
```

В `applicationDidFinishLaunching` (в конце):

```swift
        // first-run: Welcome один раз; дальше — из меню «Setup guide…»
        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            doWelcome()
        }
```

В `rebuildMenu` после `menu.addItem(item(L("settings_item"), #selector(doSettings)))`:

```swift
        menu.addItem(item(L("setup_item"), #selector(doWelcome)))
```

- [ ] **Step 3: Компиляция + selftest + ручной прогон**

Run: `./build.sh && ./ParanoidBar --selftest`
Expected: `selftest OK`.
Ручной: `defaults delete com.di-kairos.paranoidbar didOnboard 2>/dev/null; ./ParanoidBar` → Welcome-окно с живым чеклистом; кнопки работают; повторный запуск окно не показывает; «Setup guide…» в меню открывает.

- [ ] **Step 4: Commit**

```bash
git add gui/macos/ParanoidBar.swift
git commit -m "feat(gui/macos): first-run Welcome window — readiness checklist with actions"
```

---

### Task 5: macOS — Settings: Language + Hotkey + Setup guide

**Files:**
- Modify: `gui/macos/ParanoidBar.swift` (`doSettings`/`saveSettings`)

- [ ] **Step 1: Расширить окно настроек**

Заменить тело `doSettings` (высота окна 380×230; поля Vault volume / Poll interval сохранить) и добавить попапы. Полный новый вид:

```swift
    private var langPopup: NSPopUpButton?
    private var hotkeyPopup: NSPopUpButton?

    @objc private func doSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 230),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Paranoid Bar — Settings"
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
        lang.addItems(withTitles: ["System", "English", "Русский"])
        switch UserDefaults.standard.string(forKey: "language") ?? "system" {
        case "en": lang.selectItem(at: 1)
        case "ru": lang.selectItem(at: 2)
        default:   lang.selectItem(at: 0)
        }
        v.addSubview(lang); langPopup = lang

        v.addSubview(settingsLabel(L("set_hotkey"), y: 70))
        let hk = NSPopUpButton(frame: NSRect(x: 130, y: 64, width: 150, height: 26))
        hk.addItems(withTitles: ["⌃⌥⇧P", "⌃⌥⇧L", L("hk_off")])
        switch hotkeyPreset() {
        case "ctrl-opt-shift-l": hk.selectItem(at: 1)
        case "off":              hk.selectItem(at: 2)
        default:                 hk.selectItem(at: 0)
        }
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
```

В `saveSettings` перед `settingsWindow?.close()` добавить:

```swift
        if let lp = langPopup {
            let langValue = ["system", "en", "ru"][max(0, lp.indexOfSelectedItem)]
            UserDefaults.standard.set(langValue, forKey: "language")
        }
        if let hp = hotkeyPopup {
            let hkValue = ["ctrl-opt-shift-p", "ctrl-opt-shift-l", "off"][max(0, hp.indexOfSelectedItem)]
            UserDefaults.standard.set(hkValue, forKey: "panicHotkey")
            registerPanicHotkey(preset: hkValue)
        }
```

И ПОСЛЕ `refresh()` в `saveSettings` — ничего больше: `refresh()` перечитает язык (меню перестроится на новом языке).

ВНИМАНИЕ: окно настроек создаётся один раз (`settingsWindow` кэш) — при смене языка заголовки внутри НЕ перестраиваются до перезапуска окна; это ок (меню — главная поверхность). Обнулить кэш при сохранении: `settingsWindow?.close(); settingsWindow = nil` вместо простого `close()`.

- [ ] **Step 2: Компиляция + selftest + ручной прогон**

Run: `./build.sh && ./ParanoidBar --selftest`
Expected: `selftest OK`.
Ручной: Settings → Language: Русский → Save → меню по-русски; Hotkey: Off → хоткей не срабатывает; обратно ⌃⌥⇧P → работает.

- [ ] **Step 3: Commit**

```bash
git add gui/macos/ParanoidBar.swift
git commit -m "feat(gui/macos): settings — language override, hotkey preset, setup guide button"
```

---

### Task 6: macOS — test.sh (гейт для CI/локали)

**Files:**
- Create: `gui/macos/test.sh`

- [ ] **Step 1: Написать test.sh**

```bash
#!/usr/bin/env bash
# Гейт ParanoidBar: компиляция + selftest чистой логики (--selftest, аналог ST_NO_MAIN=1
# у Windows-tray). GUI-поверхность (окна/меню) проверяется руками — см. gui/README.md.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
./ParanoidBar --selftest
echo "gui/macos: build + selftest OK"
```

- [ ] **Step 2: Прогнать**

Run: `chmod +x gui/macos/test.sh && gui/macos/test.sh`
Expected: `selftest OK` + `gui/macos: build + selftest OK`.

- [ ] **Step 3: shellcheck (CI-режим!)**

Run: `shellcheck -S style gui/macos/test.sh`
Expected: пусто (clean).

- [ ] **Step 4: Commit**

```bash
git add gui/macos/test.sh
git commit -m "test(gui/macos): build + selftest gate script"
```

---

### Task 7: Windows — локализация ($PtStrings + Get-PtL)

**Files:**
- Modify: `gui/windows/paranoid-tray.ps1`
- Test: `gui/windows/test/paranoid-tray.Tests.ps1`

- [ ] **Step 1: Падающий Pester-тест**

В `paranoid-tray.Tests.ps1` добавить Describe-блок (структуру существующих блоков посмотреть в файле и повторить: dot-source под `$env:ST_NO_MAIN='1'`):

```powershell
Describe 'Localization' {
    It 'returns en/ru strings and falls back to key' {
        Get-PtL -Key 'vault_closed' -Lang 'en' | Should -Be 'closed'
        Get-PtL -Key 'vault_closed' -Lang 'ru' | Should -Be 'закрыт'
        Get-PtL -Key 'no_such_key' -Lang 'en' | Should -Be 'no_such_key'
    }
    It 'resolves language: override beats system, system falls back to en' {
        Resolve-PtLang -Override 'ru' -SystemLang 'en' | Should -Be 'ru'
        Resolve-PtLang -Override 'system' -SystemLang 'ru' | Should -Be 'ru'
        Resolve-PtLang -Override 'system' -SystemLang 'fr' | Should -Be 'en'
    }
    It 'has identical key sets for en and ru' {
        ($PtStrings.en.Keys | Sort-Object) -join ',' | Should -Be (($PtStrings.ru.Keys | Sort-Object) -join ',')
    }
}
```

- [ ] **Step 2: Прогнать (если pwsh есть локально; иначе шаг = push и смотреть CI в конце Task 11)**

Run: `pwsh -Command "Invoke-Pester gui/windows/test -Output Detailed"`
Expected: FAIL — `Get-PtL` не существует.

- [ ] **Step 3: Реализовать словарь**

В `paranoid-tray.ps1` после статус-функций (перед `Get-PtMenuSpec`):

```powershell
# --- локализация: словарь в коде, зеркало macOS `strings` (ключи 1:1, паритет — Pester).
# Честные формулировки («at risk») переводим без смягчения. ---
$script:PtStrings = @{
    en = @{
        vault_label='Vault:'; vault_open_risk='OPEN — at risk'; vault_closed='closed'; vault_not_setup='not set up'
        fv_label='BitLocker:'; fv_on='ON'; fv_off='off / unknown'
        status_item='Status — full read-only check'; panic_item='PANIC NOW — hide & lock'
        vault_menu='Vault'; vault_close='Close the vault'; vault_open='Open the vault'; vault_create='Create a vault'
        vault_empty='Empty — wipe contents, keep the vault'; vault_destroy='Destroy the vault (irreversible)'
        launcher_item='Open the full launcher (paranoid)'; settings_item='Settings…'; login_item='Start at login'
        setup_item='Setup guide…'; quit_item='Quit Paranoid Bar'
        ttl_expired='TTL expired'; auto_exit_in='auto-exit in'; watching_no_ttl='watching (no TTL)'
        tip_open='Vault is OPEN — at risk while open'; tip_closed='Vault closed'
        notif_ttl_warn='Vault auto-closes in {0}'; notif_ttl_expired='vaultwatch TTL expired — vault is still OPEN'
        notif_long_open='Vault open for 30+ minutes (no vaultwatch)'; notif_panic_arm='Press again to PANIC'
        set_vol='Vault volume:'; set_poll='Poll interval (s):'; set_lang='Language:'; set_hotkey='Panic hotkey:'
        set_save='Save'; set_setup_btn='Show setup guide'; hk_off='Off'
        ob_title='Paranoid Bar — Welcome'
        ob_sub='A status bar over the same signed CLIs. Secrets never pass through the GUI.'
        ob_cli_ok='CLIs installed (securetrash, panic, vaultwatch)'; ob_cli_missing='CLIs not found — install first'
        ob_vault_ok='Vault created'; ob_vault_missing='No vault yet'; ob_create_btn='Create vault…'
        ob_hotkey_line='Panic hotkey'; ob_login_line='Start at login'; ob_enable_btn='Enable'
        ob_risk='An open vault is always "at risk" — the GUI never hides that.'; ob_done='Done'
    }
    ru = @{
        vault_label='Сейф:'; vault_open_risk='ОТКРЫТ — под риском'; vault_closed='закрыт'; vault_not_setup='не создан'
        fv_label='BitLocker:'; fv_on='включён'; fv_off='выкл / неизвестно'
        status_item='Статус — полная read-only проверка'; panic_item='ПАНИКА — спрятать и заблокировать'
        vault_menu='Сейф'; vault_close='Закрыть сейф'; vault_open='Открыть сейф'; vault_create='Создать сейф'
        vault_empty='Очистить — стереть содержимое, сейф оставить'; vault_destroy='Уничтожить сейф (необратимо)'
        launcher_item='Открыть полный лаунчер (paranoid)'; settings_item='Настройки…'; login_item='Запускать при входе'
        setup_item='Гид по настройке…'; quit_item='Выйти из Paranoid Bar'
        ttl_expired='TTL истёк'; auto_exit_in='авто-выход через'; watching_no_ttl='наблюдение (без TTL)'
        tip_open='Сейф ОТКРЫТ — под риском, пока открыт'; tip_closed='Сейф закрыт'
        notif_ttl_warn='Сейф авто-закроется через {0}'; notif_ttl_expired='TTL vaultwatch истёк — сейф всё ещё ОТКРЫТ'
        notif_long_open='Сейф открыт дольше 30 минут (без vaultwatch)'; notif_panic_arm='Нажмите ещё раз для ПАНИКИ'
        set_vol='Том сейфа:'; set_poll='Интервал опроса (с):'; set_lang='Язык:'; set_hotkey='Хоткей паники:'
        set_save='Сохранить'; set_setup_btn='Показать гид'; hk_off='Выкл'
        ob_title='Paranoid Bar — Добро пожаловать'
        ob_sub='Панель статуса поверх тех же подписанных CLI. Секреты через GUI не проходят.'
        ob_cli_ok='CLI установлены (securetrash, panic, vaultwatch)'; ob_cli_missing='CLI не найдены — сначала установите'
        ob_vault_ok='Сейф создан'; ob_vault_missing='Сейф ещё не создан'; ob_create_btn='Создать сейф…'
        ob_hotkey_line='Хоткей паники'; ob_login_line='Запускать при входе'; ob_enable_btn='Включить'
        ob_risk='Открытый сейф всегда «под риском» — GUI этого не прячет.'; ob_done='Готово'
    }
}
# Примечание: fv_label на Windows = BitLocker (честность платформы), на macOS = FileVault.
# Ключ один и тот же — паритет ключей сохранён, значения платформенные.

function Resolve-PtLang {
    param([string]$Override = 'system', [string]$SystemLang = (Get-Culture).TwoLetterISOLanguageName)
    if ($Override -in @('en', 'ru')) { return $Override }
    if ($SystemLang -like 'ru*') { return 'ru' } else { return 'en' }
}
function Get-PtL {
    param([Parameter(Mandatory)][string]$Key, [string]$Lang)
    if (-not $Lang) { $Lang = Resolve-PtLang -Override ((Get-PtSettings).Language) }
    $t = $script:PtStrings[$Lang]
    if ($t -and $t.ContainsKey($Key)) { return $t[$Key] } else { return $Key }
}
```

ВНИМАНИЕ: `Get-PtL` зовёт `Get-PtSettings` — Task 10 добавит поле `Language` в настройки; до этого `(Get-PtSettings).Language` = `$null` → `Resolve-PtLang -Override $null` → system. Чтобы не падало на `[string]$Override` от `$null` — PowerShell приведёт `$null` к `''`, `'' -in @('en','ru')` = false → system-ветка. Ок.

- [ ] **Step 4: Перевести Get-PtMenuSpec и rebuild на Get-PtL**

В `Get-PtMenuSpec`: `$vaultLabel = switch … { 'open' { Get-PtL vault_close } 'closed' { Get-PtL vault_open } default { Get-PtL vault_create } }`; `Label = (Get-PtL status_item)`, `Label = (Get-PtL panic_item)`, `'Empty the vault (crypto-shred)'` → `(Get-PtL vault_empty)`, `(Get-PtL vault_destroy)`, `(Get-PtL launcher_item)`, `(Get-PtL login_item)`, `(Get-PtL settings_item)`, `(Get-PtL quit_item)`.
В `$rebuild` (Start-PtTray): tooltip-строки → `Get-PtL tip_open` / `auto_exit_in` / `Format-PtDuration`; vaultwatch-заголовки → `Get-PtL auto_exit_in` / `watching_no_ttl`.
СУЩЕСТВУЮЩИЕ Pester-тесты, которые матчат англ. лейблы (`'PANIC NOW - hide & lock'` и т.п.), обновить: сравнивать с `Get-PtL -Key … -Lang 'en'` вместо литералов, и в тестовом сетапе форсировать `$env:PT_SETTINGS_FILE` на temp без Language (system=en на CI).

- [ ] **Step 5: Прогнать Pester (локально при наличии pwsh, иначе CI после push)**

Run: `pwsh -Command "Invoke-Pester gui/windows/test -Output Detailed"`
Expected: PASS все.

- [ ] **Step 6: Commit**

```bash
git add gui/windows/paranoid-tray.ps1 gui/windows/test/paranoid-tray.Tests.ps1
git commit -m "feat(gui/windows): RU/EN localization — PtStrings dictionary, menu through Get-PtL"
```

---

### Task 8: Windows — уведомления (движок + BalloonTip)

**Files:**
- Modify: `gui/windows/paranoid-tray.ps1`
- Test: `gui/windows/test/paranoid-tray.Tests.ps1`

- [ ] **Step 1: Падающий Pester-тест движка**

```powershell
Describe 'Notification engine' {
    It 'fires each event once per episode and resets on close' {
        $s = New-PtNotifyState
        $r = Get-PtNotifyEvents -Open $true -Ttl 90 -HasSessions $true -Now 1000000 -State $s
        $r.Events | Should -Be @('ttl_warn')
        $r2 = Get-PtNotifyEvents -Open $true -Ttl 80 -HasSessions $true -Now 1000001 -State $r.State
        $r2.Events | Should -BeNullOrEmpty
        $r3 = Get-PtNotifyEvents -Open $true -Ttl 0 -HasSessions $true -Now 1000002 -State $r2.State
        $r3.Events | Should -Be @('ttl_expired')
        $r4 = Get-PtNotifyEvents -Open $false -Ttl $null -HasSessions $false -Now 1000003 -State $r3.State
        $r4.State.OpenSince | Should -BeNullOrEmpty
    }
    It 'warns once after 30 min open without vaultwatch' {
        $s = New-PtNotifyState
        $r = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $false -Now 1000000 -State $s
        $r.Events | Should -BeNullOrEmpty
        $r2 = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $false -Now 1001801 -State $r.State
        $r2.Events | Should -Be @('long_open')
        $r3 = Get-PtNotifyEvents -Open $true -Ttl $null -HasSessions $false -Now 1003600 -State $r2.State
        $r3.Events | Should -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Реализовать движок (зеркало Swift decideNotifications)**

После vaultwatch-функций в `paranoid-tray.ps1`:

```powershell
# --- уведомления: чистый движок решений (Pester), доставка — NotifyIcon.ShowBalloonTip.
# Правила = спека §2, зеркало Swift decideNotifications: каждое событие один раз за эпизод
# «сейф открыт»; закрытие сейфа сбрасывает эпизод. ---
function New-PtNotifyState {
    [pscustomobject]@{ TtlWarned = $false; TtlExpiredWarned = $false; LongOpenWarned = $false; OpenSince = $null }
}
function Get-PtNotifyEvents {
    param([bool]$Open, [object]$Ttl, [bool]$HasSessions, [int64]$Now, [Parameter(Mandatory)]$State)
    if (-not $Open) { return [pscustomobject]@{ Events = @(); State = (New-PtNotifyState) } }
    $s = [pscustomobject]@{ TtlWarned = $State.TtlWarned; TtlExpiredWarned = $State.TtlExpiredWarned
                            LongOpenWarned = $State.LongOpenWarned; OpenSince = $State.OpenSince }
    if ($null -eq $s.OpenSince) { $s.OpenSince = $Now }
    $events = @()
    if ($null -ne $Ttl) {
        if ($Ttl -gt 0 -and $Ttl -lt 120 -and -not $s.TtlWarned) { $events += 'ttl_warn'; $s.TtlWarned = $true }
        if ($Ttl -eq 0 -and -not $s.TtlExpiredWarned) { $events += 'ttl_expired'; $s.TtlExpiredWarned = $true }
    }
    if (-not $HasSessions -and ($Now - $s.OpenSince) -gt 1800 -and -not $s.LongOpenWarned) {
        $events += 'long_open'; $s.LongOpenWarned = $true
    }
    return [pscustomobject]@{ Events = $events; State = $s }
}
```

- [ ] **Step 3: Встроить в $rebuild (Start-PtTray)**

В `Start-PtTray` перед `$rebuild = {`: `$script:notifyState = New-PtNotifyState`.
В конец `$rebuild`-блока (после foreach меню):

```powershell
        # уведомления: движок решает, BalloonTip доставляет (10с; текст без секретов)
        $now = [int64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $nr = Get-PtNotifyEvents -Open ($state -eq 'open') -Ttl $ttl -HasSessions ($sessions.Count -gt 0) -Now $now -State $script:notifyState
        $script:notifyState = $nr.State
        foreach ($e in $nr.Events) {
            $text = switch ($e) {
                'ttl_warn'    { (Get-PtL notif_ttl_warn) -replace '\{0\}', (Format-PtDuration $ttl) }
                'ttl_expired' { Get-PtL notif_ttl_expired }
                'long_open'   { Get-PtL notif_long_open }
            }
            if ($text) { $notify.ShowBalloonTip(10000, 'Paranoid Tools', $text, [System.Windows.Forms.ToolTipIcon]::Warning) }
        }
```

- [ ] **Step 4: Pester (локально/CI)**

Run: `pwsh -Command "Invoke-Pester gui/windows/test -Output Detailed"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add gui/windows/paranoid-tray.ps1 gui/windows/test/paranoid-tray.Tests.ps1
git commit -m "feat(gui/windows): tray notifications — TTL warn/expired, long-open (mirror of macOS)"
```

---

### Task 9: Windows — глобальный хоткей паники

**Files:**
- Modify: `gui/windows/paranoid-tray.ps1`
- Test: `gui/windows/test/paranoid-tray.Tests.ps1`

- [ ] **Step 1: Падающий Pester-тест чистой логики**

```powershell
Describe 'Panic hotkey' {
    It 'double-press fires only within 2s window' {
        Test-PtPanicShouldFire -Now 1000.0 -ArmedAt $null | Should -BeFalse
        Test-PtPanicShouldFire -Now 1001.5 -ArmedAt 1000.0 | Should -BeTrue
        Test-PtPanicShouldFire -Now 1002.5 -ArmedAt 1000.0 | Should -BeFalse
    }
    It 'maps presets to vk codes, off/garbage to $null' {
        (Get-PtHotkeySpec -Preset 'ctrl-alt-shift-p').Vk | Should -Be 0x50
        (Get-PtHotkeySpec -Preset 'ctrl-alt-shift-l').Vk | Should -Be 0x4C
        Get-PtHotkeySpec -Preset 'off' | Should -BeNullOrEmpty
        Get-PtHotkeySpec -Preset 'garbage' | Should -BeNullOrEmpty
    }
}
```

Примечание паритета: пресеты на Windows называются `ctrl-alt-shift-p` / `ctrl-alt-shift-l` / `off` (Alt = Option).

- [ ] **Step 2: Реализовать логику + P/Invoke**

```powershell
# --- глобальный хоткей паники: RegisterHotKey + скрытое message-окно (WM_HOTKEY=0x0312).
# Двойное нажатие в 2с → panic now БЕЗ confirm (panic обратим); одиночное — взвод + balloon.
# Чистая логика (окно 2с, маппинг пресетов) — Pester; сама регистрация — только GUI-путь. ---
function Test-PtPanicShouldFire {
    param([double]$Now, [object]$ArmedAt, [double]$Window = 2.0)
    if ($null -eq $ArmedAt) { return $false }
    return (($Now - [double]$ArmedAt) -le $Window)
}
# MOD_CONTROL=2 MOD_ALT=1 MOD_SHIFT=4 → 7; vk: P=0x50, L=0x4C.
function Get-PtHotkeySpec {
    param([string]$Preset)
    switch ($Preset) {
        'ctrl-alt-shift-p' { return [pscustomobject]@{ Modifiers = 7; Vk = 0x50 } }
        'ctrl-alt-shift-l' { return [pscustomobject]@{ Modifiers = 7; Vk = 0x4C } }
        default { return $null }
    }
}
```

GUI-часть (в `Start-PtTray`, после создания `$notify`), C#-хелпер один раз:

```powershell
    # Скрытое NativeWindow ловит WM_HOTKEY (RegisterHotKey требует окно; у NotifyIcon его нет).
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class PtHotkeyWindow : NativeWindow {
    public event EventHandler HotkeyPressed;
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public PtHotkeyWindow() { CreateHandle(new CreateParams()); }
    public bool Register(uint mods, uint vk) { UnregisterHotKey(Handle, 1); return RegisterHotKey(Handle, 1, mods, vk); }
    public void Unregister() { UnregisterHotKey(Handle, 1); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312) { var h = HotkeyPressed; if (h != null) h(this, EventArgs.Empty); }
        base.WndProc(ref m);
    }
}
'@
    $script:hotkeyWin = New-Object PtHotkeyWindow
    $script:panicArmedAt = $null
    $script:hotkeyWin.add_HotkeyPressed({
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
        if (Test-PtPanicShouldFire -Now $now -ArmedAt $script:panicArmedAt) {
            $script:panicArmedAt = $null
            Invoke-PtTool -Command 'panic now'
        } else {
            $script:panicArmedAt = $now
            $notify.ShowBalloonTip(3000, 'Paranoid Tools', (Get-PtL notif_panic_arm), [System.Windows.Forms.ToolTipIcon]::Warning)
        }
    })
    $hkSpec = Get-PtHotkeySpec -Preset ((Get-PtSettings).PanicHotkey)
    if ($hkSpec) { [void]$script:hotkeyWin.Register($hkSpec.Modifiers, $hkSpec.Vk) }
```

(Поле `PanicHotkey` в настройках добавляет Task 10; до него `(Get-PtSettings).PanicHotkey` = `$null` → `Get-PtHotkeySpec $null` → `$null` → не регистрируем. Порядок коммитов безопасен.)

- [ ] **Step 3: Pester (локально/CI)**

Run: `pwsh -Command "Invoke-Pester gui/windows/test -Output Detailed"`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add gui/windows/paranoid-tray.ps1 gui/windows/test/paranoid-tray.Tests.ps1
git commit -m "feat(gui/windows): global panic hotkey — RegisterHotKey + 2s double-press"
```

---

### Task 10: Windows — settings-схема (Language/PanicHotkey/Onboarded) + форма

**Files:**
- Modify: `gui/windows/paranoid-tray.ps1`
- Test: `gui/windows/test/paranoid-tray.Tests.ps1`

- [ ] **Step 1: Падающий Pester-тест схемы**

```powershell
Describe 'Settings v2 (language/hotkey/onboarded)' {
    BeforeEach { $env:PT_SETTINGS_FILE = Join-Path $TestDrive 'settings.json' }
    AfterEach  { Remove-Item Env:\PT_SETTINGS_FILE -ErrorAction SilentlyContinue }
    It 'defaults: system language, hotkey on (ctrl-alt-shift-p), not onboarded' {
        $s = Get-PtSettings
        $s.Language | Should -Be 'system'
        $s.PanicHotkey | Should -Be 'ctrl-alt-shift-p'
        $s.Onboarded | Should -BeFalse
    }
    It 'round-trips new fields' {
        Set-PtSettings -VaultVolume 'X:' -PollSeconds 30 -Language 'ru' -PanicHotkey 'off' -Onboarded $true
        $s = Get-PtSettings
        $s.Language | Should -Be 'ru'
        $s.PanicHotkey | Should -Be 'off'
        $s.Onboarded | Should -BeTrue
    }
    It 'sanitizes garbage language/hotkey to defaults' {
        Set-PtSettings -Language 'xx' -PanicHotkey 'garbage'
        (Get-PtSettings).Language | Should -Be 'system'
        (Get-PtSettings).PanicHotkey | Should -Be 'ctrl-alt-shift-p'
    }
}
```

- [ ] **Step 2: Расширить Get/Set-PtSettings**

`Get-PtSettings` — дефолт-объект и чтение:

```powershell
    $s = [pscustomobject]@{ VaultVolume = ''; PollSeconds = 15; Language = 'system'
                            PanicHotkey = 'ctrl-alt-shift-p'; Onboarded = $false }
    …
            if ($null -ne $j.Language)    { $s.Language = [string]$j.Language }
            if ($null -ne $j.PanicHotkey) { $s.PanicHotkey = [string]$j.PanicHotkey }
            if ($null -ne $j.Onboarded)   { $s.Onboarded = [bool]$j.Onboarded }
    …
    # Санация: мусор из руками правленного JSON → дефолты (как clamp у PollSeconds)
    if ($s.Language -notin @('system', 'en', 'ru')) { $s.Language = 'system' }
    if ($s.PanicHotkey -notin @('ctrl-alt-shift-p', 'ctrl-alt-shift-l', 'off')) { $s.PanicHotkey = 'ctrl-alt-shift-p' }
```

`Set-PtSettings`:

```powershell
function Set-PtSettings {
    param([string]$VaultVolume = '', [int]$PollSeconds = 15, [string]$Language = 'system',
          [string]$PanicHotkey = 'ctrl-alt-shift-p', [bool]$Onboarded = $false)
    if ($PollSeconds -lt 5) { $PollSeconds = 5 } elseif ($PollSeconds -gt 3600) { $PollSeconds = 3600 }
    if ($Language -notin @('system', 'en', 'ru')) { $Language = 'system' }
    if ($PanicHotkey -notin @('ctrl-alt-shift-p', 'ctrl-alt-shift-l', 'off')) { $PanicHotkey = 'ctrl-alt-shift-p' }
    $f = Get-PtSettingsFile
    if (-not $f) { return }
    $dir = Split-Path -Parent $f
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [pscustomobject]@{ VaultVolume = $VaultVolume; PollSeconds = $PollSeconds; Language = $Language
                       PanicHotkey = $PanicHotkey; Onboarded = $Onboarded } | ConvertTo-Json | Set-Content -LiteralPath $f
}
```

ВНИМАНИЕ: существующие вызовы `Set-PtSettings -VaultVolume … -PollSeconds …` (settings-форма) теперь сбрасывали бы Language/Hotkey/Onboarded в дефолт — форма ДОЛЖНА передавать все поля (см. Step 3).

- [ ] **Step 3: Расширить Show-PtSettingsForm**

Высота 230; добавить два ComboBox + кнопку гида; лейблы через `Get-PtL`; Save передаёт ВСЕ поля:

```powershell
    $lblLang = New-Object System.Windows.Forms.Label
    $lblLang.Text = (Get-PtL set_lang); $lblLang.SetBounds(12, 86, 110, 20)
    $cbLang = New-Object System.Windows.Forms.ComboBox
    $cbLang.DropDownStyle = 'DropDownList'; $cbLang.SetBounds(130, 83, 150, 22)
    [void]$cbLang.Items.AddRange(@('System', 'English', 'Русский'))
    $cbLang.SelectedIndex = @('system', 'en', 'ru').IndexOf($cur.Language)

    $lblHk = New-Object System.Windows.Forms.Label
    $lblHk.Text = (Get-PtL set_hotkey); $lblHk.SetBounds(12, 120, 110, 20)
    $cbHk = New-Object System.Windows.Forms.ComboBox
    $cbHk.DropDownStyle = 'DropDownList'; $cbHk.SetBounds(130, 117, 150, 22)
    [void]$cbHk.Items.AddRange(@('Ctrl+Alt+Shift+P', 'Ctrl+Alt+Shift+L', (Get-PtL hk_off)))
    $cbHk.SelectedIndex = @('ctrl-alt-shift-p', 'ctrl-alt-shift-l', 'off').IndexOf($cur.PanicHotkey)

    $setup = New-Object System.Windows.Forms.Button
    $setup.Text = (Get-PtL set_setup_btn); $setup.SetBounds(12, 185, 150, 28)
    $setup.Add_Click({ Show-PtWelcomeForm })   # Task 11 определяет; до него кнопку НЕ добавлять в Controls
```

Save-ветка:

```powershell
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-PtSettings -VaultVolume ($tbVol.Text.Trim()) -PollSeconds ([int]$nudPoll.Value) `
            -Language (@('system', 'en', 'ru')[[math]::Max(0, $cbLang.SelectedIndex)]) `
            -PanicHotkey (@('ctrl-alt-shift-p', 'ctrl-alt-shift-l', 'off')[[math]::Max(0, $cbHk.SelectedIndex)]) `
            -Onboarded ([bool]$cur.Onboarded)
        return (Get-PtSettings)
    }
```

И в settings-обработчике `$rebuild` (после применения `$s`): перерегистрировать хоткей:

```powershell
                        $hkSpec = Get-PtHotkeySpec -Preset $s.PanicHotkey
                        if ($hkSpec) { [void]$script:hotkeyWin.Register($hkSpec.Modifiers, $hkSpec.Vk) }
                        else { $script:hotkeyWin.Unregister() }
```

- [ ] **Step 4: Pester (локально/CI)**

Run: `pwsh -Command "Invoke-Pester gui/windows/test -Output Detailed"`
Expected: PASS (вкл. старые settings-тесты — проверить, что они не ждут двухпольного JSON).

- [ ] **Step 5: Commit**

```bash
git add gui/windows/paranoid-tray.ps1 gui/windows/test/paranoid-tray.Tests.ps1
git commit -m "feat(gui/windows): settings v2 — language, hotkey preset, onboarded flag"
```

---

### Task 11: Windows — Welcome-онбординг + кросс-платформенный паритет

**Files:**
- Modify: `gui/windows/paranoid-tray.ps1`
- Test: `gui/windows/test/paranoid-tray.Tests.ps1`

- [ ] **Step 1: Падающий Pester-тест чеклиста**

```powershell
Describe 'Onboarding' {
    It 'builds checklist lines from readiness' {
        Get-PtChecklistLine -Ok $true -OkKey 'ob_cli_ok' -MissKey 'ob_cli_missing' -Lang 'en' |
            Should -Be ([char]0x2705 + ' CLIs installed (securetrash, panic, vaultwatch)')
        Get-PtChecklistLine -Ok $false -OkKey 'ob_vault_ok' -MissKey 'ob_vault_missing' -Lang 'ru' |
            Should -Be ([char]0x274C + ' Сейф ещё не создан')
    }
}
```

- [ ] **Step 2: Реализовать чеклист + Welcome-форма + first-run**

```powershell
# Строка чеклиста Welcome-окна — чистая для Pester (зеркало Swift checklistLine).
function Get-PtChecklistLine {
    param([bool]$Ok, [string]$OkKey, [string]$MissKey, [string]$Lang)
    if ($Ok) { return ([char]0x2705 + ' ' + (Get-PtL -Key $OkKey -Lang $Lang)) }
    return ([char]0x274C + ' ' + (Get-PtL -Key $MissKey -Lang $Lang))
}
function Test-PtClisInstalled {
    foreach ($t in @('securetrash', 'panic', 'vaultwatch')) {
        if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { return $false }
    }
    return $true
}
```

`Show-PtWelcomeForm` — полный код (WinForms, зеркало macOS `doWelcome`):

```powershell
# Welcome-окно (спека §3): живой чеклист + кнопки-действия. Кнопки перерисовывают форму
# (close + reopen — приемлемо для диалога). Секретов не касается.
function Show-PtWelcomeForm {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = (Get-PtL ob_title)
    $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.StartPosition = 'CenterScreen'; $form.ClientSize = New-Object System.Drawing.Size(480, 280)

    $y = 14
    function Add-PtObLabel {
        param($Form, [string]$Text, [ref]$Y, [single]$Size = 9, [object]$Color = $null)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $Text; $l.AutoSize = $false
        $l.SetBounds(16, $Y.Value, 330, 22)
        $l.Font = New-Object System.Drawing.Font('Segoe UI', $Size)
        if ($Color) { $l.ForeColor = $Color }
        $Form.Controls.Add($l); $Y.Value += 28
    }
    function Add-PtObButton {
        param($Form, [string]$Text, [int]$AtY, [scriptblock]$OnClick)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $Text; $b.SetBounds(352, $AtY - 2, 112, 24)
        $b.Add_Click($OnClick)
        $Form.Controls.Add($b)
    }

    Add-PtObLabel $form ([char]0x1F512 + ' Paranoid Bar') ([ref]$y) 11
    Add-PtObLabel $form (Get-PtL ob_sub) ([ref]$y) 8 ([System.Drawing.Color]::Gray)
    Add-PtObLabel $form (Get-PtChecklistLine -Ok (Test-PtClisInstalled) -OkKey 'ob_cli_ok' -MissKey 'ob_cli_missing') ([ref]$y)
    $hasVault = ((Get-PtVaultState) -ne 'none')
    $vaultY = $y
    Add-PtObLabel $form (Get-PtChecklistLine -Ok $hasVault -OkKey 'ob_vault_ok' -MissKey 'ob_vault_missing') ([ref]$y)
    if (-not $hasVault) {
        Add-PtObButton $form (Get-PtL ob_create_btn) $vaultY { Invoke-PtTool -Command 'securetrash vault create' }
    }
    $hkOn = ((Get-PtSettings).PanicHotkey -ne 'off')
    $mark = if ($hkOn) { [char]0x2705 } else { [char]0x2B1C }
    Add-PtObLabel $form ("$mark " + (Get-PtL ob_hotkey_line) + ': Ctrl+Alt+Shift+P (' + [char]0x00D7 + '2)') ([ref]$y)
    $loginOn = [bool](Test-PtAutostart)
    $mark = if ($loginOn) { [char]0x2705 } else { [char]0x2B1C }
    $loginY = $y
    Add-PtObLabel $form ("$mark " + (Get-PtL ob_login_line)) ([ref]$y)
    if (-not $loginOn) {
        Add-PtObButton $form (Get-PtL ob_enable_btn) $loginY { Enable-PtAutostart; $form.Close(); Show-PtWelcomeForm }
    }
    Add-PtObLabel $form ([char]0x26A0 + ' ' + (Get-PtL ob_risk)) ([ref]$y) 8 ([System.Drawing.Color]::DarkOrange)

    $done = New-Object System.Windows.Forms.Button
    $done.Text = (Get-PtL ob_done); $done.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $done.SetBounds(384, 238, 80, 28)
    $form.Controls.Add($done); $form.AcceptButton = $done
    [void]$form.ShowDialog()
}
```

First-run в `Start-PtTray` (после `$settings = Get-PtSettings`):

```powershell
    if (-not $settings.Onboarded) {
        Set-PtSettings -VaultVolume $settings.VaultVolume -PollSeconds $settings.PollSeconds `
            -Language $settings.Language -PanicHotkey $settings.PanicHotkey -Onboarded $true
        Show-PtWelcomeForm
    }
```

Пункт меню: в `Get-PtMenuSpec` после `settings_item` добавить
`[pscustomobject]@{ Label = (Get-PtL setup_item); Command = '__setup__'; Enabled = $true }`,
в `$rebuild` — ветка `elseif ($cmd -eq '__setup__') { $it.Add_Click({ Show-PtWelcomeForm }.GetNewClosure()) }`,
в `Invoke-PtTool` — добавить `__setup__` в игнор-список.
Теперь включить кнопку `$setup` в Controls settings-формы (Task 10 Step 3).

- [ ] **Step 3: Паритет-тест ключей локализации macOS ↔ Windows**

В Pester (словарь ключей Swift достаём грепом по `ParanoidBar.swift` — оба файла в одном репо):

```powershell
Describe 'Cross-platform l10n parity' {
    It 'ps1 key set equals Swift key set' {
        $swift = Get-Content (Join-Path $PSScriptRoot '..\..\macos\ParanoidBar.swift') -Raw
        $swiftKeys = [regex]::Matches($swift, '(?m)^\s*"([a-z0-9_]+)":\s*\(') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $psKeys = $PtStrings.en.Keys | Sort-Object -Unique
        ($psKeys -join ',') | Should -Be ($swiftKeys -join ',')
    }
}
```

- [ ] **Step 4: Pester (локально/CI) — полный прогон**

Run: `pwsh -Command "Invoke-Pester gui/windows/test -Output Detailed"`; если pwsh нет — `git push` и смотреть Actions.
Expected: PASS все (старые + новые).

- [ ] **Step 5: Commit**

```bash
git add gui/windows/paranoid-tray.ps1 gui/windows/test/paranoid-tray.Tests.ps1
git commit -m "feat(gui/windows): first-run Welcome form + l10n parity test with macOS"
```

---

### Task 12: Финал — README, полный прогон, Codex-ревью, push

**Files:**
- Modify: `gui/README.md`

- [ ] **Step 1: Обновить gui/README.md по факту**

Таблица «What's here»: добавить хоткей (⌃⌥⇧P ×2 / Ctrl+Alt+Shift+P ×2), уведомления, Welcome-онбординг, RU/EN. Секцию «Not done yet» переписать честно: осталось — дистрибуция (Apple Developer / Authenticode) и open-core упаковка; settings pane и полиш — сделаны. Упомянуть `macos/test.sh` как гейт.

- [ ] **Step 2: Полный локальный прогон**

Run: `gui/macos/test.sh && bash smoke-test.sh 2>/dev/null || true; shellcheck -S style gui/macos/test.sh gui/macos/build.sh`
Expected: build+selftest OK; shellcheck clean. bats umbrella не трогали — но прогнать `bats test/` для уверенности (49/49).

- [ ] **Step 3: Codex-ревью диффа (процесс проекта, риск-путь panic)**

Run: `git diff 482fd69..HEAD -- gui/ | codex exec --skip-git-repo-check "Adversarial review: GUI-обёртка security-тулов (panic hotkey, уведомления, онбординг). Найди баги, гонки, обход честности (GUI не должен прятать риски), проблемы double-press логики."`
Findings встроить/исправить до push.

- [ ] **Step 4: Commit README + push**

```bash
git add gui/README.md
git commit -m "docs(gui): README reflects Phase B polish — hotkey, notifications, onboarding, RU/EN"
git push origin main
```

- [ ] **Step 5: Проверить Windows CI**

Run: `gh run list --limit 3` → дождаться green на `windows-latest` (Pester).
Expected: success. Если red — читать лог, чинить, повторить.

- [ ] **Step 6: Обновить graphify-граф (§15.2)**

Run: `graphify "/Volumes/X10 Pro/projects/paranoid-tools" --update`
Expected: одна строка «граф обновлён, N файлов».
