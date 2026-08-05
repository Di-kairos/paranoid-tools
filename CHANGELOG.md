# Changelog

Все заметные изменения vaultwatch. Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [0.1.8] — 2026-08-05

### Added
- **`--yes` понимается и здесь.** Раньше флаг был только у securetrash, и подтверждение
  `--ttl --force` можно было пропустить лишь через переменную окружения. Аргументы после
  `--` остаются буквальными, поэтому точка монтирования, буквально названная `--yes`,
  по-прежнему работает.

### Fixed
- **`stop` громко падает, если не смог восстановить.** Раньше при неудачной обратной
  индексации печаталось предупреждение, но код возврата оставался 0 — и post-close-хук
  securetrash с таймером авто-выхода считали сессию чисто закрытой, тогда как том на деле
  оставался неиндексированным, а файл состояния — живым. Оба порта теперь возвращают
  ненулевой код на этом пути; файл состояния сохраняется для повторной попытки.
- **Windows: точка монтирования, кончающаяся обратным слэшем, ломала запланированные
  задачи.** `V:\` уходил в аргумент задачи как `"V:\"`, где хвостовой слэш экранирует
  закрывающую кавычку — задачи TTL и unmount-guard получали искалеченный путь и срабатывали
  вхолостую. Хвостовые слэши удваиваются, как того и ждёт `CommandLineToArgvW`.
- **`install.ps1`: `SHA256SUMS` отдаётся верификатору сырыми байтами.** Подписанные данные
  шли через конвейер PowerShell, который перекодирует текст — BOM или замена переводов
  строк превращали верную подпись в «incorrect signature» и блокировали установку.
- «Unknown command» переведено в русской таблице.

### Changed
- README RU: добавлена потерянная секция про unmount-guard — launchd-страж возвращает
  исключения, если том извлекли мимо `stop`. Факт, а не украшение, и он был только
  в английской версии.
- Ссылка на соседний репозиторий сделана настоящей ссылкой: «See paranoid-tools/README.md»
  — мёртвый путь, когда этот репозиторий читают сам по себе, а именно так к нему и приходят.

## [0.1.7] — 2026-08-03

### Fixed
- **Windows: `stop` после извлечения тома больше не «восстанавливает» в пустоту.** Если том
  исчез (eject/отключение диска), restore помечается N/A, состояние чистится, а перед
  действием идёт повторная проверка — закрывает TOCTOU-гонку. Зеркало bash-политики.
- **`install.sh` fail-closed без `ssh-keygen`.** Раньше отсутствие верификатора молча
  понижало установку до проверки только по хешу; теперь это отказ (обход —
  `ALLOW_UNSIGNED_LEGACY=1`, названный явно). Плюс `type -P`: экспортированная функция
  не может подменить собой верификатор.

### Changed
- README EN+RU: клеймы про подпись приведены в соответствие коду — сниппеты проверяют
  подлинность (`.sig` + вшитый pubkey + `ssh-keygen -Y verify`), шаги сцеплены `&&`,
  остаточный риск (один ключ) назван прямо.

## [0.1.6] — 2026-07-04

### Added
- **Unmount-guard (Windows): авто-восстановление Search-исключения при извлечении тома мимо `stop`.**
  Опрашивающая задача Task Scheduler возвращает исключение Windows Search, когда том извлечён в
  обход `stop`.
- **Проверка Ed25519-подписи в Windows-инсталляторе (fail-closed).** Установка прерывается, если
  подпись не проходит проверку.

### Security / Fixed
- **`--force` теперь настоящий safety-gate при TTL-размонтировании.** Занятый том никогда не
  размонтируется принудительно без явного `--force` + подтверждения.
- **Требуется PowerShell 7 (fail-closed).** На 5.1 — явный отказ вместо тихого no-op.
- **`start` идемпотентен** и больше не перезаписывает сохранённое pre-session состояние.

### Docs
- Честный scope Windows-порта (только Search; VSS/облако — сообщается, pagefile не трогается);
  устранён version-drift.

## [0.1.5] — 2026-06-27

### Added
- **Unmount-guard (macOS): авто-восстановление исключений при извлечении тома мимо `stop`.**
  Раньше Finder-eject (или любой detach в обход securetrash post-close hook) оставлял
  Spotlight-off и Time-Machine-exclusion висеть до следующего явного `vaultwatch stop`. Теперь
  `start` регистрирует launchd-LaunchAgent с `WatchPaths` на mountpoint: когда том исчезает,
  срабатывает `_guard_fire`, который запускает восстановление **только если том реально
  размонтирован** (иначе WatchPaths дёрнулся на запись файла внутри — no-op). `stop` снимает
  guard. Spotlight-restore при отсутствии тома — graceful skip (индексировать несуществующий
  том не нужно; это не ошибка). Windows-порт без изменений (launchd-специфично; на Windows
  по-прежнему явный `stop`/`vault close`).

## [0.1.4] — 2026-06-26

### Changed
- Репозиторий переехал на `github.com/Di-kairos`; перевыпуск с обновлёнными URL и переподписанными ассетами. Функциональных изменений нет.

## [0.1.3] — 2026-06-25

Первый выпуск с поддержкой Windows — завершает Windows-охват экосистемы (5/5).

### Added
- **Windows PowerShell port (beta):** `windows/vaultwatch.ps1` + `windows/install.ps1`.
  `start [--ttl D] [--force] <mount>` исключает каталог из Windows Search (атрибут
  `NotContentIndexed`), планирует авто-dismount через Task Scheduler (по истечении —
  `Lock-BitLocker -ForceDismount`), проверяет cloud-демоны (OneDrive/Dropbox/Google Drive)
  и репортит существующие VSS shadow copies. `stop` восстанавливает ровно изменённое и
  печатает session report; `status` — активные сессии; `install-hooks`/`uninstall-hooks` —
  managed `.cmd`-хуки. ЧЕСТНО: Windows не даёт чисто исключить backup из CLI, поэтому
  snapshots только РЕПОРТЯТСЯ (не удаляются), pagefile не затрагивается. Pester покрывает
  оркестровку с замоканными Search/Scheduler/BitLocker/VSS (windows-CI).

## [0.1.2] — 2026-06-24

Релиз догоняет ассеты до исходников: команда `status` и hardening установщика/подписи,
которые осели в `main` после тега `v0.1.1`, теперь попадают в публичный релиз.

### Added
- **`status`** — read-only обзор активных watch-сессий (что охраняется, с какого момента,
  активный `--ttl`-таймер). Ни одного изменяющего вызова — безопасно звать в любой момент.

### Fixed
- **`stop`/`--ttl`:** результат `hdiutil detach` проверяется явно, а провал восстановления
  (Spotlight/Time Machine) не теряется молча — попадает в session report.

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
- Homebrew `Formula/vaultwatch.rb`, `LICENSE`/`SECURITY.md`/`CONTRIBUTING.md`,
  English-primary README + `README.ru.md`, флаги `-v`/`--version`, `-h`/`--help`.

### Fixed
- **Офлайн `vendor --check`:** хеш вшитого common-блока против запиннутого SHA, без сети
  (раньше падал 404 после ухода securetrash в private → красный CI).

## [0.1.0] — 2026-06-19

Первый функциональный срез: честный сторож открытого vault для macOS.

### Added
- **Интеграция с securetrash:** `install-hooks` / `uninstall-hooks` ставят managed
  `post-open`/`post-close` в `${ST_HOOK_DIR:-~/.securetrash/hooks}`, не трогая чужие хуки.
- **Сторожевое ядро `start <mount>`:** запоминает прежнее состояние Spotlight и
  выключает индексацию (`mdutil -i off`); исключает том из Time Machine
  (`tmutil addexclusion`) **только если он ещё не исключён**; эвристический
  cloud-детект (Dropbox/OneDrive/iCloud/Google Drive — процесс + расположение
  синк-папки относительно vault); пишет per-mount session-state.
- **`stop <mount>`:** восстанавливает **ровно то, что менял** `start` (не «чинит»
  чужое состояние) и печатает session report (длительность, Spotlight, Time Machine,
  cloud-демоны, локальные снапшоты, честная строка про swap).
- **Авто-выход `--ttl D`** (`30m`/`2h`/`45s`/`1d`/секунды) через **launchd LaunchAgent**:
  managed one-shot job (`RunAtLoad` → sleep → `_ttl_fire`), виден в `launchctl list`,
  снимается через `bootout`. По истечении: `lsof`-проверка → `hdiutil detach` свободного
  тома, иначе честное предупреждение; `--force` → `detach -force` с подтверждением.
  `stop` отменяет таймер (bootout + удаление plist).
- Вендоринг общего ядра `lib/common.sh` из securetrash inline-маркерами + CI-чек дрейфа.
- Дистрибуция: checksum-verified `install.sh` (бинарь + `SHA256SUMS` с релизного тега),
  `release.yml` собирает ассеты на push тега `v*`.

### Honest limitations
- Не закрывает swap; не удаляет уже снятые локальные снапшоты Time Machine (только
  сообщает о них); cloud-детект эвристичен; `--ttl` не размонтирует том с открытыми
  файлами без `--force`. Подробности — `README.md` «Scope & limitations».

### Tests
- bats 46/46 (12 интеграция/хуки + 22 start/stop + 12 ttl/launchd), shellcheck clean.
- Тесты идут на Linux-CI через PATH-стабы (`uname/mdutil/tmutil/pgrep/lsof/hdiutil/launchctl`).
- Real-device smoke на macOS: start/stop/`--ttl` на живом sparsebundle, launchd
  bootstrap/bootout-цикл, plist валиден (`plutil -lint`).

[Unreleased]: https://github.com/Di-kairos/vaultwatch/compare/v0.1.8...HEAD
[0.1.8]: https://github.com/Di-kairos/vaultwatch/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/Di-kairos/vaultwatch/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/Di-kairos/vaultwatch/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/Di-kairos/vaultwatch/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/Di-kairos/vaultwatch/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/Di-kairos/vaultwatch/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Di-kairos/vaultwatch/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Di-kairos/vaultwatch/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Di-kairos/vaultwatch/releases/tag/v0.1.0
