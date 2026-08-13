# Changelog

Все заметные изменения panic. Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [0.1.15] — 2026-08-08

### Fixed
- **Скрипт снова запускается под штатным Windows PowerShell 5.1.** Файлы `.ps1` лежали в UTF-8
  без BOM, а 5.1 читает такой файл в системной ANSI-кодировке: на русской Windows кириллица в
  исходнике превращалась в мозаику, кавычки внутри строк рвались, и скрипт падал с `ParserError`
  ещё до первой команды — не работало вообще ничего. Дефект нашёл живой пользователь; CI его не
  видел, потому что гонял только `pwsh` 7, который читает UTF-8 по умолчанию. BOM добавлен во все
  `.ps1`, включая установщик.

### Added
- **CI гоняет тесты под самим Windows PowerShell 5.1**, а не только под `pwsh` 7: парсинг каждого
  `.ps1`, Pester и запуск `panic version` / `--help`. Плюс тест, который падает, если хоть один `.ps1` с не-ASCII
  остался без BOM.
- Тесты установщика под 5.1 уходили в Unix-ветку (`$IsWindows` существует только с PowerShell 6
  и там был `$null`), подкладывали shim с shebang вместо `.cmd` — проверка подписи на happy-path
  фактически не выполнялась.


## [0.1.14] — 2026-08-06

### Fixed
- **Установщик Windows работает и под штатным Windows PowerShell 5.1.** Аргументы верификатору
  подписи собирались через `ProcessStartInfo.ArgumentList`, которого в .NET Framework нет, —
  а 5.1 это ровно тот шелл, в котором выполняют однострочник из README. Установка падала бы на
  шаге проверки подписи. Добавлен запасной путь через строку аргументов с корректным
  квотированием (кавычки экранируются, хвостовые обратные слэши удваиваются).

## [0.1.13] — 2026-08-06

### Fixed
- **Установщик больше не плодит вторую копию тула.** Умбрелла `paranoid-tools` ставит всё в
  `~/.local/bin` (без sudo), а этот установщик по умолчанию — в `/usr/local/bin`. Кто ставил
  обоими способами, получал две копии, и какая из них запустится, решал порядок в `PATH`:
  обновление молча не доезжало до пользователя. Теперь при уже установленной копии в
  `~/.local/bin` установка идёт поверх неё; явный `<TOOL>_DEST` по-прежнему сильнее всего.
  Плюс предупреждение, если каталог установки не в `PATH`, — молчать здесь нельзя, иначе
  успешная установка выглядит как несостоявшаяся.
- **`panic hotkey` на Windows больше не отвечает «Unknown command».** README документирует эту
  команду, а Windows-порт её не несёт — и молчаливое «неизвестная команда» читалось как
  сломанная установка. Теперь порт называет причину (хоткей на macOS висит через skhd, аналога
  нет, а держать фоновый процесс ради слежения за клавиатурой panic не станет) и даёт рабочий
  путь средствами самой ОС: горячая клавиша вешается на ярлык `panic.cmd` через «Свойства» →
  «Быстрый вызов» → `Ctrl+Alt+P`.

## [0.1.12] — 2026-08-06

### Fixed
- **Установщик Windows больше не может тихо повиснуть на проверке подписи.** `stdout`/`stderr`
  верификатора перенаправлялись, но не вычитывались до `WaitForExit`: `ssh-keygen`, написавший
  больше буфера трубы, вставал на записи, а установщик ждал его вечно. Молча висящая установка
  хуже честного отказа. Потоки теперь дренируются асинхронно; регрессия воспроизведена тестом
  (без дренажа установщик не возвращается).
- **Установщик Windows честно говорит «подпись не сошлась», если верификатор вышел, не дочитав
  данные.** Запись в уже закрытую трубу роняла установку необработанным исключением — вместо
  вердикта пользователь видел аварию.
- Подача подписанных данных переведена с `Start-Process -RedirectStandardInput` на тот же
  `ProcessStartInfo`, что у остальных четырёх. Оба варианта отдают сырые байты, но один
  security-критичный шаг, написанный в пяти установщиках тремя разными способами, — это ровно
  тот способ, которым копия seedsplit уехала на форму, ломавшую установку.

## [0.1.11] — 2026-08-05

### Fixed
- **`status` больше не может назвать включённый FileVault выключенным.** Детект был
  прямым пайпом `fdesetup status | grep -q`: `grep -q` закрывает канал на первом
  совпадении, `fdesetup` ловит SIGPIPE, а `set -o pipefail` делает весь конвейер
  ненулевым — то есть именно совпадение («FileVault is On») могло прочитаться как
  «выключен». Вывод теперь захватывается в переменную, пайпа нет, гонки нет.
  Отсутствие `fdesetup` по-прежнему показывается как «выключен» (fail-closed).

### Changed
- **Перевендорен `securetrash/lib/common.sh`** (пин `221f2c7`): единый на экосистему
  детект примонтированного тома (`_volume_mounted`) и tri-state FileVault (`_fv_state`:
  on/off/unknown, `filevault_on` — его двоичная обёртка).

## [0.1.10] — 2026-08-05

### Fixed
- **`hotkey` больше не переписывает права на `skhdrc`.** Снятие управляемого блока
  подменяло весь конфиг через `mv` — и чужой `skhdrc` возвращался с владельцем текущего
  пользователя и правами `0600` от `mktemp`, а временная копия оставалась на диске, если
  падал `awk`. Содержимое теперь вливается обратно в существующий файл, а копия удаляется
  на обоих путях.
- «Unknown command» переведено в русской таблице.

### Changed
- Документация: в таблице команд `hotkey status` был описан так, будто он ещё и удаляет
  хоткей; в таблице соответствий для Windows значился `rundll32` для блокировки экрана,
  хотя порт с самого начала зовёт `LockWorkStation` через P/Invoke — именно потому, что
  код возврата `rundll32` ничего не говорит о том, заблокировался ли экран.
- Ссылка на соседний репозиторий сделана настоящей ссылкой: «See paranoid-tools/README.md»
  — мёртвый путь, когда этот репозиторий читают сам по себе.

## [0.1.9] — 2026-08-03

### Fixed
- **`install.sh` fail-closed без `ssh-keygen`.** Отсутствие верификатора больше не
  понижает установку до проверки только по хешу — это отказ (обход
  `ALLOW_UNSIGNED_LEGACY=1`). `type -P` не даёт экспортированной функции притвориться
  верификатором.

### Changed
- **Честный теглайн: «всё с экрана», а не «всё».** panic прячет и запирает — он не
  уничтожает данные, и формулировка теперь это отражает буквально.
- README EN+RU: сниппеты установки проверяют подпись, а не только сумму; остаточный
  риск назван. RU-версия получила потерянное предупреждение про `curl | bash`.

## [0.1.8] — 2026-07-06

### Fixed
- **`panic status` больше не падает с кодом 1 в headless/ограниченной среде.** Read-only
  preflight обрывался, если `pbpaste` не мог прочитать pasteboard: под `set -euo pipefail`
  упавший `pbpaste` в `clip_size="$(pbpaste | wc -c | …)"` ронял всю подстановку и функцию,
  так что проверки FileVault/cloud не выполнялись. Теперь отказ `pbpaste` изолирован
  (`|| pb_ok=0`), буфер честно помечается «неизвестно», а статус доходит до конца. bats 9 → 10.

## [0.1.7] — 2026-07-04

### Added
- **Windows-инсталлятор проверяет Ed25519-подпись релиза** (fail-closed; отказ
  разрешён только при отсутствии верификатора/подписи через `PT_ALLOW_HASH_ONLY=1`).

### Docs
- Исправлены overclaim'ы: panic **форс-отмонтирует тома напрямую** — он не вызывает
  vaultwatch и не запускает vault-close хуки securetrash; задокументирован fallback
  CGSession→Ctrl+Cmd+Q на macOS ≥12; помечено, что `curl|bash` one-liner пропускает
  верификацию; EN/RU parity + фиксы version-drift.

## [0.1.6] — 2026-06-29

### Fixed
- **Честная блокировка экрана.** Раньше `panic now` всегда печатал «locked screen», даже
  когда лок молча падал: на macOS ≥12 legacy-бандл `CGSession` удалён. Теперь `_lock_screen`
  пробует `CGSession -suspend` → fallback Ctrl+Cmd+Q через `osascript` и **возвращает статус**;
  отчёт говорит «screen locked.» только по факту, иначе громко предупреждает (нужен
  Accessibility-доступ терминалу). Override: `PANIC_CGSESSION` / `PANIC_OSASCRIPT`.
- **Windows-зеркало честности.** PowerShell-порт больше не утверждает «locked screen» вслепую:
  `Invoke-PnLockScreen` перешёл с `rundll32 ...,LockWorkStation` (exit-код helper-процесса,
  не лока) на P/Invoke `user32!LockWorkStation` — честный bool API; при провале — warn, не ложь.
- **SIGPIPE на `panic now | head`.** Многострочный пост-отчёт под `set -euo pipefail` ронял
  exit-код успешной паники в 141 при закрытом потребителем pipe. Отчёт сделан best-effort
  (`trap '' PIPE` + `|| true`).

## [0.1.5] — 2026-06-26

### Changed
- Репозиторий переехал на `github.com/Di-kairos`; перевыпуск с обновлёнными URL и переподписанными ассетами. Функциональных изменений нет.

## [0.1.4] — 2026-06-26

### Added
- **`panic hotkey`** — глобальный хоткей паники через [`skhd`](https://github.com/koekeishiya/skhd):
  `install [combo]` / `uninstall` / `status`. По умолчанию `cmd + alt - p` → `panic now`.
  Биндинг живёт в managed-блоке `skhdrc` (чужие skhd-биндинги не трогает). Честно: чистый
  Bash глобальный хоткей на macOS невозможен — нужен резидентный слушатель с правом
  Accessibility, поэтому используем skhd (`brew install skhd`). Windows-хоткей пока не подключён.
- Тесты: +8 bats (`test/hotkey.bats`) + skhd-стаб.

## [0.1.3] — 2026-06-25

Первый выпуск с поддержкой Windows.

### Added
- **Windows PowerShell port (beta):** `windows/panic.ps1` + `windows/install.ps1`.
  `panic now` запирает разблокированные BitLocker-тома (`Lock-BitLocker -ForceDismount`),
  размонтирует тома VeraCrypt (`VeraCrypt /d /f`), чистит буфер обмена и блокирует экран
  (`rundll32 user32.dll,LockWorkStation`); `--hard` дополнительно прибивает cloud-демоны
  и чистит Recent items. `status` — read-only preflight (BitLocker on/off, разблокированные
  тома, cloud-демоны). panic — сплошные side-effect'ы, поэтому Pester покрывает оркестровку
  с замоканными системными примитивами (windows-CI). Поведение зеркалит macOS-версию.

## [0.1.2] — 2026-06-24

Релиз догоняет ассеты до исходников: команда `status` и hardening установщика/подписи,
осевшие в `main` после тега `v0.1.1`, теперь попадают в публичный релиз.

### Added
- **`status`** — read-only preflight: FileVault on/off, смонтированные disk image'ы под
  `/Volumes`, активные cloud-демоны. Показывает, что именно сделает `panic now`, ничего
  не трогая. Безопасно звать до паники.

### Security
- **install.sh fail-closed:** отсутствие `SHA256SUMS.sig` на релизе теперь прерывает
  установку (обход для старых релизов — `ALLOW_UNSIGNED_LEGACY=1`); отсутствие `ssh-keygen`
  больше не молчит, а громко предупреждает, что подпись не проверена (только целостность).
- **Подпись релиза fail-closed:** `release.yml` прерывает выпуск (`exit 1`), если
  `RELEASE_SIGNING_KEY` не задан, — неподписанный релиз невозможен.

## [0.1.1] — 2026-06-22

### Added
- **Подпись релизов (Ed25519, опциональная):** CI подписывает `SHA256SUMS`, `install.sh`
  авто-проверяет подпись поверх контрольной суммы (мягкая деградация). Pubkey в `SECURITY.md`.
- Homebrew `Formula/panic.rb`, `LICENSE`/`SECURITY.md`/`CONTRIBUTING.md`,
  English-primary README + `README.ru.md`, флаги `-v`/`--version`, `-h`/`--help`.

### Fixed
- **Офлайн `vendor --check`:** хеш вшитого common-блока против запиннутого SHA, без сети.

## [0.1.0] — 2026-06-19

Первый функциональный срез: kill-switch на один шаг для macOS.

### Added
- **`panic now`** — спрятать и запереть: размонтировать все смонтированные disk image'ы
  под `/Volumes` (`hdiutil detach -force`; mountpoints парсятся из `hdiutil info`,
  устойчиво к пробелам; system-образы вне `/Volumes` не трогаются), очистить буфер
  обмена (`pbcopy </dev/null`), заблокировать экран (`CGSession -suspend`, переопределяемо
  через `PANIC_CGSESSION`). Без confirm — режим паники; защита от случайного запуска —
  явный verb `now` (bare `panic` → usage).
- **`--hard`** — дополнительно прибить cloud-демоны (`pkill -x` Dropbox/OneDrive/bird/
  Google Drive, best-effort) и почистить глобальные Recent items (shared file lists).
- Вендоринг общего ядра `lib/common.sh` из securetrash inline-маркерами + CI-чек дрейфа.
- Дистрибуция: checksum-verified `install.sh` (бинарь + `SHA256SUMS` с релизного тега),
  `release.yml` собирает ассеты на push тега `v*`.

### Honest limitations
- panic ПРЯЧЕТ и ЗАПИРАЕТ, но **не уничтожает** и **не чистит swap** (для уничтожения —
  securetrash). `detach -force` при открытых файлах может повредить данные (осознанный
  trade-off паники). `--hard` чистит только глобальные Recent items — per-app «недавние»
  внутри приложений не стираются. Подробности — `README.md` «Scope & limitations».

### Tests
- bats 20/20 (8 scaffold + 7 now + 5 --hard), shellcheck clean.
- Тесты идут на Linux-CI через PATH-стабы (`uname/hdiutil/pbcopy/pkill`) + `PANIC_CGSESSION`/
  `PANIC_SFL_DIR` overrides.
- Real-device smoke на macOS: `now` распарсил живой `hdiutil info` и размонтировал тест-образ.

[Unreleased]: https://github.com/Di-kairos/panic/compare/v0.1.14...HEAD
[0.1.14]: https://github.com/Di-kairos/panic/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/Di-kairos/panic/compare/v0.1.12...v0.1.13
[0.1.12]: https://github.com/Di-kairos/panic/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/Di-kairos/panic/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/Di-kairos/panic/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/Di-kairos/panic/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/Di-kairos/panic/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/Di-kairos/panic/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/Di-kairos/panic/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/Di-kairos/panic/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/Di-kairos/panic/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/Di-kairos/panic/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Di-kairos/panic/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Di-kairos/panic/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Di-kairos/panic/releases/tag/v0.1.0
