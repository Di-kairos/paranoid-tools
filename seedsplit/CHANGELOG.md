# Changelog

Все заметные изменения seedsplit. Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [0.5.7] — 2026-09-02

### Fixed
- **Windows: `seedsplit` не запускался из PowerShell — «running scripts is disabled on this system».**
  Установщик клал `seedsplit.ps1` рядом с `seedsplit.cmd` в каталоге из PATH, а PowerShell разрешает
  имя команды без расширения в `.ps1` раньше, чем в `.cmd` с тем же именем, и тут же отказывается
  его грузить при стандартной политике запуска (`Restricted`). То есть обёртка, ради которой всё
  и затевалось, не получала управления никогда — кроме вызова из `cmd.exe`. Теперь сам скрипт
  лежит в подкаталоге `lib\`, в PATH видна только `.cmd`, и она стартует
  `pwsh -NoProfile -ExecutionPolicy Bypass` для своего процесса: политика машины не меняется.
  Установка поверх старой убирает `seedsplit.ps1`, оставшийся рядом с обёрткой, — иначе он бы
  продолжал перехватывать имя, и обновление ничего бы не изменило.

## [0.5.6] — 2026-08-13

### Changed
- **Windows-установщик говорит на одном языке.** Сообщения об отказе (несовпадение
  контрольной суммы, отсутствие `ssh-keygen`, отсутствие или провал подписи) были
  русскими, тогда как остальной вывод `install.ps1` — английский; теперь весь скрипт
  английский, как и его happy path.
- **Проект переехал в монорепозиторий [`paranoid-tools`](https://github.com/Di-kairos/paranoid-tools).**
  Код, история и релизы всех пяти инструментов живут теперь в одном репозитории; релизные теги
  получили префикс — этот выпуск опубликован как `seedsplit-v0.5.6`. Прежний репозиторий архивирован,
  его старые релизы продолжают отдаваться.
- **Установщики качают из монорепо по закреплённому тегу.** `releases/latest` в монорепо означает
  «последний релиз любого инструмента», поэтому и `install.sh`, и `windows/install.ps1` всегда
  пиннят собственный тег `seedsplit-vX.Y.Z`; версию по умолчанию сторожит гейт в `release.yml`.
- **Комментарии в коде переведены на английский** для внешних контрибьюторов; строки интерфейса
  остаются двуязычными, русская документация — на месте.
- Приватные сообщения об уязвимостях принимаются теперь в одном месте —
  [advisories монорепо](https://github.com/Di-kairos/paranoid-tools/security/advisories/new).

### Added
- **Дифференциальные тесты криптоядра в CI.** Вторая, написанная с нуля реализация схемы
  SSS2/SSS3 на Python сверяется с bash-реализацией на каждый push: split здесь обязан
  собираться там и наоборот, RS-parity каждой доли пересчитывается независимым кодером,
  property-тесты закрывают порог, смешение наборов и починку опечаток (включая опечатку в
  самом поле parity). README теперь прямо называет статус аудита: реализация собственная,
  независимого аудита не было.

## [0.5.5] — 2026-08-08

### Fixed
- **Скрипт снова запускается под штатным Windows PowerShell 5.1.** Файлы `.ps1` лежали в UTF-8
  без BOM, а 5.1 читает такой файл в системной ANSI-кодировке: на русской Windows кириллица в
  исходнике превращалась в мозаику, кавычки внутри строк рвались, и скрипт падал с `ParserError`
  ещё до первой команды — не работало вообще ничего. Дефект нашёл живой пользователь; CI его не
  видел, потому что гонял только `pwsh` 7, который читает UTF-8 по умолчанию. BOM добавлен во все
  `.ps1`, включая установщик.

### Added
- **CI гоняет тесты под самим Windows PowerShell 5.1**, а не только под `pwsh` 7: парсинг каждого
  `.ps1`, Pester и запуск `seedsplit version` / `--help`. Плюс тест, который падает, если хоть один `.ps1` с не-ASCII
  остался без BOM.
- То же по тестам: `$IsWindows` под 5.1 равен `$null`, из-за чего фикстуры шли по Unix-ветке.


## [0.5.4] — 2026-08-06

### Fixed
- **Установщик Windows работает и под штатным Windows PowerShell 5.1.** Аргументы верификатору
  подписи собирались через `ProcessStartInfo.ArgumentList`, которого в .NET Framework нет, —
  а 5.1 это ровно тот шелл, в котором выполняют однострочник из README. Установка падала бы на
  шаге проверки подписи. Добавлен запасной путь через строку аргументов с корректным
  квотированием (кавычки экранируются, хвостовые обратные слэши удваиваются).

## [0.5.3] — 2026-08-06

### Fixed
- **Установщик больше не плодит вторую копию тула.** Умбрелла `paranoid-tools` ставит всё в
  `~/.local/bin` (без sudo), а этот установщик по умолчанию — в `/usr/local/bin`. Кто ставил
  обоими способами, получал две копии, и какая из них запустится, решал порядок в `PATH`:
  обновление молча не доезжало до пользователя. Теперь при уже установленной копии в
  `~/.local/bin` установка идёт поверх неё; явный `<TOOL>_DEST` по-прежнему сильнее всего.
  Плюс предупреждение, если каталог установки не в `PATH`, — молчать здесь нельзя, иначе
  успешная установка выглядит как несостоявшаяся.

## [0.5.2] — 2026-08-06

### Fixed
- **Установщик Windows больше не может тихо повиснуть на проверке подписи.** `stdout`/`stderr`
  верификатора перенаправлялись, но не вычитывались до `WaitForExit`: `ssh-keygen`, написавший
  больше буфера трубы, вставал на записи, а установщик ждал его вечно. Молча висящая установка
  хуже честного отказа. Потоки теперь дренируются асинхронно; регрессия воспроизведена тестом
  (без дренажа установщик не возвращается).
- **Установщик Windows честно говорит «подпись не сошлась», если верификатор вышел, не дочитав
  данные.** Запись в уже закрытую трубу роняла установку необработанным исключением — вместо
  вердикта пользователь видел аварию.
- **Валидная подпись релиза читалась как подделка и блокировала установку.** Подписанные данные
  уходили в `ssh-keygen` через конвейер PowerShell, а тот дописывает собственный перевод строки:
  верификатор видел 82 байта там, где подписан 81. Проверка не сходилась на НАСТОЯЩЕМ релизе, и,
  поскольку гейт fail-closed, установить seedsplit на Windows с настоящего релиза было нельзя
  вовсе. Остальные четыре тула уже отдавали сырой поток файла — эта копия оставалась последней
  на хрупкой форме. Тест сравнивает то, что реально дошло до верификатора, побайтово.

## [0.5.1] — 2026-08-05

### Changed
- **Перевендорен `securetrash/lib/common.sh`** (пин `221f2c7`). Библиотека получила единый
  на всю экосистему детект примонтированного тома (`_volume_mounted` — читает таблицу
  монтирования, а не наличие каталога) и tri-state FileVault (`_fv_state`: on/off/**unknown**;
  `filevault_on` стал его двоичной обёрткой). Поведение самого seedsplit не меняется — он ни
  одну из этих функций пока не вызывает; синхронизация нужна, чтобы вендоренный блок не
  разъезжался с каноном. Формат долей SSS3 не затронут.

## [0.5.0] — 2026-08-05

### Added
- **Формат долей SSS3 с коррекцией опечаток.** Доля теперь несёт поле parity —
  Рид—Соломон над тем же GF(256), что и само разбиение (4 байта на чанк ≤251 байт тела).
  `combine` чинит **до двух байт с опечаткой на долю** — хоть в теле, хоть в самом поле
  parity — и печатает, что именно починил.
  Зачем: доли живут на бумаге и переписываются руками, а до этого один неверный символ
  убивал долю целиком — контрольная сумма честно говорила «испорчена», но починить было нечем.
- Декодер — Питерсон для t≤2 с перебором корней. Точно про предел: у кода расстояние 5,
  поэтому при трёх и более испорченных байтах декодер может сойтись к ДРУГОМУ кодовому слову,
  а не отказать. Такой кандидат отбрасывается контрольной суммой доли и 128-битным tag'ом
  нагрузки — `combine` отдаёт либо точный секрет, либо ошибку, но держат это именно проверки,
  а не сам декодер.
- Сообщение «починено N байт» печатается только ПОСЛЕ того, как сошёлся tag нагрузки: иначе
  пользователь видел бы «исправлено» у набора, который следом честно отвергнут.
- Оба порта (bash и PowerShell) считают parity **байт-в-байт одинаково** — есть KAT-вектор
  в обоих наборах тестов; доли, нарезанные на macOS, собираются на Windows и наоборот.

### Changed
- `split` печатает `SSS3-<setid>-<T>-<x>-<hexY>-<parity>-<chk4>`.
- Сообщение об ошибке различает «доля повреждена сильнее, чем чинит parity» (SSS3) и прежнее
  «контрольная сумма не сошлась» (SSS2).

### Compatibility
- **Доли SSS2, распечатанные версиями 0.4.x, собираются по-прежнему** — у них просто нет
  parity, чинить нечем. Миграции нет: нужна коррекция — разбей секрет заново.
- Чего parity НЕ кроет (сказано и в README): структурная голова доли (`setid`, `T`, `x`) —
  опечатка там ловится контрольной суммой, но не чинится; пропущенные/лишние символы,
  сдвигающие остаток строки.

## [0.4.2] — 2026-08-03

### Fixed
- **Windows: `split` делает round-trip self-check до печати долей.** Доли
  восстанавливаются из первых T штук тем же путём, что и `combine`, и сверяются с
  исходным секретом; при расхождении — ошибка и выход, ничего не печатается. Иначе
  пользователь мог записать на бумагу доли, которые не собираются обратно. Паритет с bash.
- **`install.sh` fail-closed без `ssh-keygen`** (обход — `ALLOW_UNSIGNED_LEGACY=1`),
  `type -P` вместо `command -v`.

### Changed
- README EN+RU: сниппеты установки проверяют подпись `SHA256SUMS.sig` вшитым ключом,
  а не только сумму; остаточный риск (один ключ подписи) назван прямо.

## [0.4.1] — 2026-07-04

### Security
- **Master passphrase no longer transiently spills to a temp file.** The `-p/--passphrase`
  layer now feeds `openssl -pass fd:3` via a process substitution instead of a `<<<`
  here-string (bash here-strings materialise a temp file), so the passphrase never touches
  disk.

### Fixed
- **`split` now round-trip self-checks the generated shares** — it reconstructs the secret
  from the first T shares via the real `combine` path and aborts before printing anything if
  they don't reconstruct. A data-loss guard against silently emitting unrecoverable shares.

### Added
- **Windows installer verifies the Ed25519 release signature** (fail-closed). Opt-out only
  for a missing verifier/signature via `PT_ALLOW_HASH_ONLY=1`.

### Docs
- RU README now documents the `-p/--passphrase` layer (EN/RU parity); `-p` added to the
  command tables; `SECURITY.md` wire-format note corrected to `SSS2`; test-count/version
  drift fixed. Shares remain **byte-compatible with v0.4.0**.

## [0.4.0] — 2026-06-28

### Added
- **Passphrase layer (`split -p` / `--passphrase`).** Optionally encrypts the secret with
  native **openssl** (AES-256-CBC + PBKDF2, 200k iters) BEFORE Shamir-splitting, so a
  reconstructed threshold of shares still yields only a sealed `openssl enc` container — the
  secret stays protected by the passphrase. `combine` auto-detects the container and prompts
  for the passphrase (env `SEEDSPLIT_PASSPHRASE` for automation/tests; otherwise `/dev/tty`).
  The Shamir core is untouched and stays zero-dependency — only `-p` uses openssl (present by
  default on macOS/Linux). Passphrase is passed to openssl via fd, never argv (`ps`-safe).
  Windows port: `combine` honestly flags a sealed container and emits it for an `openssl enc -d`
  pipeline (no hard openssl dependency in the PowerShell port).

### Notes (deliberately NOT shipped — honesty over snake oil)
- **SLIP-39** is not reimplemented: rolling a crypto standard (GF(256) + RS1024 + wordlist) in
  bash is exactly the kind of unaudited crypto this project refuses to ship. Use a vetted
  SLIP-39 tool for hardware-wallet interop.
- **Decoy / hidden vault** is not added: real plausible deniability needs hidden volumes
  (VeraCrypt-style), which APFS does not support natively; a second visible vault gives ZERO
  deniability (forensics sees both), so shipping it would be snake oil.

## [0.3.3] — 2026-06-26

### Changed
- Репозиторий переехал на `github.com/Di-kairos`; перевыпуск с обновлёнными URL и переподписанными ассетами. Функциональных изменений нет.

## [0.3.2] — 2026-06-25

Первый официальный выпуск с поддержкой Windows.

### Added
- **Windows PowerShell port (beta):** `windows/seedsplit.ps1` + `windows/install.ps1`.
  Доли байт-совместимы с macOS/Linux-версией — KAT-кросс-совместимость зафиксирована
  frozen-набором в Pester и подтверждена на реальном Windows (windows-CI green).

## [0.3.1] — 2026-06-24

Релиз догоняет ассеты до исходников: hardening установщика и подписи, осевший
в `main` после тега `v0.3.0`, теперь попадает в публичный релиз.

### Security
- **install.sh fail-closed:** отсутствие `SHA256SUMS.sig` на релизе теперь прерывает
  установку (обход для старых релизов — `ALLOW_UNSIGNED_LEGACY=1`); отсутствие `ssh-keygen`
  больше не молчит, а громко предупреждает, что подпись не проверена (только целостность).
- **Подпись релиза fail-closed:** `release.yml` прерывает выпуск (`exit 1`), если
  `RELEASE_SIGNING_KEY` не задан, — неподписанный релиз невозможен.

## [0.3.0] — 2026-06-22

Усиление целостности и UX по результатам внешнего аудита крипты + i18n и подпись релизов.

### Changed (ломающее — формат долей)
- **Формат на проводе `SSS1` → `SSS2`** (несовместим со старыми долями; внешних
  пользователей на момент смены нет). Новый префикс явно отвергает смешивание со старыми.
- **integrity-tag 2 → 16 байт (128 бит):** шанс `combine` молча вернуть НЕ тот секрет
  снижен с ~2⁻¹⁶ до ~2⁻¹²⁸.
- **Полный i18n рантайм-сообщений** (`split`/`combine`/`verify` + вся таксономия ошибок):
  английский по умолчанию, русский по `ST_LANG=ru`. Раньше сообщения были захардкожены
  по-русски — дефект для English-primary тула (4 sibling-тула локализуют через `t()`).

### Added
- **Случайный set-id (4-байтный nonce) в каждой доле** — НЕ производный от секрета
  (нет confirmation-оракула). `combine` ДЕТЕРМИНИРОВАННО отвергает доли из разных сплитов.
- **`verify`** — подтвердить, что ≥T долей восстанавливают секрет, БЕЗ его печати.
- **Таксономия ошибок:** различимые сообщения — повреждение (CRC) / разные сплиты (set-id) /
  ниже порога / расходящийся порог T / провал целостности.
- **KAT-векторы:** GF(256)-умножение против эталона FIPS-197 + замороженный SSS2-набор.
- **Подпись релизов (Ed25519, опциональная):** CI подписывает `SHA256SUMS`, `install.sh`
  авто-проверяет подпись поверх контрольной суммы (мягкая деградация). Pubkey в `SECURITY.md`.

### Fixed
- `combine` теперь отвергает набор, где доли **заявляют разный порог T** (раньше брал T
  последней доли).
- Внутреннее восстановление использует `return`, а не `exit` (корректно в `$(...)`).

### Honest limitations
- GF(256)-умножение через log/antilog-таблицы **не constant-time** (тайминговый
  side-channel) — вне модели угроз локального CLI, отмечено в README «Scope & limitations».

### Tests
- bats 37/37 (24 ядро Shamir/verify/таксономия/KAT + 13 dispatcher/flags/vendor).
  shellcheck clean. vendor `--check` — теперь офлайн (хеш блока vs пин, без сети).

## [0.2.0] — 2026-06-20

Первый функциональный срез: рабочее ядро разделения секрета по схеме Шамира.

### Added
- **`split [-n N] [-t T] [--file F]`** — разбивает секрет на N долей так, что любые
  T восстанавливают его, а T−1 не дают о нём ничего (порог Шамира над GF(256)).
  ГСЧ — `/dev/urandom`. Секрет читается из stdin или `--file`, НИКОГДА из argv
  (argv виден в `ps`). По умолчанию `-n 3 -t 2`.
- **`combine [FILE...]`** — восстанавливает секрет из ≥T долей (stdin по строке на
  долю или из файлов).
- **Целостность.** Формат доли `SSS1-<T>-<x>-<hexY>-<chk>`: контрольная сумма ловит
  опечатку в отдельной доле. Секрет упакован как `0x55|len|secret|crc` → `combine`
  либо возвращает ТОЧНЫЙ секрет, либо честно отказывает (порча / доли от разных
  секретов), а не выдаёт мусор.
- **`-v`/`--version`, `-h`/`--help`** флаги (алиасы к `version`/`help`).
- Вендоринг общего `common.sh` (pin `2e3d2dd`) inline + CI-чек дрейфа.
- Checksum-verified `install.sh` (бинарь + `SHA256SUMS` с релизного тега).

### Honest limitations
- Качество долей = качество ГСЧ (`/dev/urandom`). Порог защищает от утечки <T долей,
  но НЕ от потери ≥(N−T+1) долей. Доли безопасны ровно настолько, насколько надёжно
  ты их хранишь и разносишь.
- Совместимости со SLIP-39 / аппаратными кошельками ПОКА НЕТ (собственный формат).
  Подробности — `README.md` «Scope & limitations».

### Tests
- bats 31/31 (13 dispatcher/flags/vendor + 18 ядро Shamir: round-trip всех подмножеств
  порога, отказ при <T долях без утечки, детект порчи/чужого набора, бинарные секреты,
  границы N/T). shellcheck clean. Тесты идут на Linux-CI через PATH-стаб `uname`.

[Unreleased]: https://github.com/Di-kairos/paranoid-tools/compare/seedsplit-v0.5.7...HEAD
[0.5.7]: https://github.com/Di-kairos/paranoid-tools/compare/seedsplit-v0.5.6...seedsplit-v0.5.7
[0.5.6]: https://github.com/Di-kairos/paranoid-tools/releases/tag/seedsplit-v0.5.6
[0.5.4]: https://github.com/Di-kairos/seedsplit/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/Di-kairos/seedsplit/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/Di-kairos/seedsplit/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/Di-kairos/seedsplit/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/Di-kairos/seedsplit/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/Di-kairos/seedsplit/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/Di-kairos/seedsplit/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Di-kairos/seedsplit/compare/v0.3.3...v0.4.0
[0.3.3]: https://github.com/Di-kairos/seedsplit/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/Di-kairos/seedsplit/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/Di-kairos/seedsplit/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Di-kairos/seedsplit/releases/tag/v0.3.0
[0.2.0]: https://github.com/Di-kairos/seedsplit/releases/tag/v0.2.0
