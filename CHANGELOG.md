# Changelog

Все заметные изменения securetrash. Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

## [0.5.0] — 2026-08-03

### Added
- **`vault destroy-old`** — штатный способ убрать контейнер, отставленный прерванным
  `reset`. Раньше инструмент сообщал, что рядом лежит `<vault>.old` с прежними данными,
  но убрать его можно было только руками. Отдельная команда, а не часть `destroy`: цели
  разные, и смешивать их в одном подтверждении — прямой путь удалить не то. Состояние
  «размонтирован» проверяется дважды — до промпта и непосредственно перед удалением,
  потому что подтверждение ждёт ввода сколько угодно, а сам инструмент советует
  примонтировать контейнер и забрать данные.
- **`check` и заметка после `shred`/`empty` показывают локальные снимки.** Снимок,
  сделанный пока файл ещё лежал вне сейфа, хранит его полную копию, и `shred` туда не
  дотянется. Считаются все снимки APFS кроме откатных точек установщика: список только
  по `com.apple.TimeMachine.*` пропустил бы Carbon Copy Cloner и Arq и выдал бы
  «снимков нет» там, где копия есть. На Windows — теневые копии VSS, и только при правах
  администратора: без них провайдер отдаёт пустой список, а не ошибку.

### Fixed
- **Окно потери данных в `vault reset` закрыто.** Раньше `destroy` шёл первым, и падение
  `create` (нет места, отказ hdiutil/diskpart, Ctrl-C на промпте пароля, отказ
  Enable-BitLocker) оставляло пользователя вообще без сейфа. Теперь старый контейнер
  отставляется в сторону, новый создаётся на его месте, и только после успеха старый
  крипто-шредится. Откат навешен trap'ом (EXIT/INT/TERM/HUP/QUIT), а не только на ветку
  ошибки: прерывание приходит именно на промпте пароля, уже после переноса. Уцелевший
  `.old` — данные пользователя, поэтому `reset` отказывается его перезаписывать, а не
  сносит молча. Восстановление на место не выполняется, если путь занят: `mv dir dir`
  положил бы старый сейф внутрь недоделанного нового и вернул успех.
- **Windows: суффикс отставленного контейнера идёт перед расширением**
  (`SecureVault.old.vhdx`). `Get-DiskImage` принимает только `.vhd/.vhdx/.iso`, поэтому
  при `SecureVault.vhdx.old` любая проверка состояния отвечала бы `unknown` и
  fail-closed отказом — контейнер нельзя было бы ни проверить, ни удалить.
- **Провал crypto-shred больше не молчит.** Если старый контейнер удалить не удалось,
  рядом с новым сейфом остаётся копия, расшифровываемая старым паролем; теперь об этом
  сказано прямо, а не выдано за успешный reset.
- **`Get-CimInstance Win32_ShadowCopy` получил `-OperationTimeoutSec 10`** — зависший
  VSS/WMI иначе подвешивал бы каждый `shred`.

### Notes
- Тесты: bats 81 → 96, Pester 86 → 109. Добавлены реально-файловые тесты пары
  aside/restore (моки скрывали два Windows-дефекта) и проверка отказа при смонтированном
  `.old`.

## [0.4.13] — 2026-07-09

### Fixed
- **Windows: `check` различает BitLocker `off` и `unknown`** — зеркало macOS-фикса v0.4.12.
  Раньше отсутствие cmdlet'а `Get-BitLockerVolume` (Windows Home) или неопределяемый статус
  трактовались как «ВЫКЛЮЧЕН»; теперь tri-state `Get-StBitLockerState` печатает честное
  «BitLocker: неизвестно — считай, что диск НЕ защищён». Булев `Get-StBitLockerOn`
  (guard в setup/rm-путях) не тронут. Pester +1.
- **windows-ci реанимирован (красный с v0.4.11):** фейковый ssh-keygen в тестах
  установщика стал `ssh-keygen.cmd` (файл без расширения Windows не исполняет —
  happy-path supply-chain теста падал fail-closed'ом), destroy-тесты получили
  default-мок `Test-Path` под strict-режим Pester 6. Поведение установщика и CLI
  не менялось — только тест-инфраструктура. bats 78/78 + Pester 76/76.

## [0.4.12] — 2026-07-06

### Fixed
- **`check` теперь различает FileVault `off` и `unknown`.** Раньше вердикт был бинарным
  (`filevault_on`: On / не-On), поэтому недоступный или непонятный вывод `fdesetup` трактовался
  как «ВЫКЛЮЧЕН» — и расходился с дашбордом лаунчера, который показывал «неизвестно». Теперь
  `check` использует tri-state (`on`/`off`/`unknown`, как у лаунчера): при неопределённом статусе
  печатает «FileVault: неизвестно — считай, что диск НЕ защищён» вместо ложного «OFF».
  Вендоренный примитив `filevault_on` не тронут. bats 72 → 73.

## [0.4.11] — 2026-07-04

### Added
- **Windows-установщик проверяет Ed25519-подпись релиза** — `ssh-keygen -Y verify` поверх
  `SHA256SUMS`, fail-closed. Отказ от проверки возможен только через `PT_ALLOW_HASH_ONLY=1`
  (при отсутствии верификатора или файла подписи).
- **`vault reset` задокументирован** в таблицах команд (macOS README + Windows README).

### Security
- **`VAULT_PATH`/`VAULT_VOLUME` учитывают `ST_VAULT_PATH`/`ST_VAULT_VOLUME`** — GUI/TUI и
  деструктивный CLI теперь бьют по одному и тому же сейфу (раньше могли указывать на разные).
- **`vault reset` валидирует аргумент размера ДО уничтожения** контейнера (нет частичного
  разрушения при неверном размере).
- **Windows `vault open` идемпотентен** — повторный вызов на уже открытом сейфе безопасен.

### Changed
- Смягчены формулировки про `shred` — соответствуют честному рантайм-поведению на SSD.
- Исправлен version-drift в документации.

## [0.4.10] — 2026-06-27

### Added
- **`securetrash vault reset [size]`** — опустошить сейф с РЕАЛЬНОЙ гарантией безвозвратности:
  crypto-shred контейнера (выкинуть ключ) + создать новый пустой (новый ключ → старое мертво
  навсегда). Покрывает воркфлоу «накопил файлы → бах, гарантированно стёрто → работаю дальше».
  Почему не in-place: перезапись файлов внутри живого сейфа на SSD — best-effort (тот же ключ
  продолжает расшифровывать остаточные band-блоки); единственный честный способ — выкинуть ключ.
  Один confirm на всю операцию; запрос пароля нового сейфа. Размер нового контейнера опционален.
- Windows-порт: `vault reset` зеркалит ту же логику (VHDX destroy+recreate, fail-closed по
  unmounted-состоянию).

### Changed
- Рефактор `cmd_vault`: общие внутренние операции (`_vault_create_now`/`_vault_assert_destroyable`/
  `_vault_destroy_now`) переиспользуются `destroy` и `reset` (DRY). Поведение create/destroy не менялось.

## [0.4.9] — 2026-06-26

### Changed
- **`vault open` теперь монтирует том ВИДИМЫМ в Finder по умолчанию** (убран `-nobrowse`).
  Причина: спрятанный том после закрытия окна «невидим» — пользователь не понимает, где сейф,
  и легко забывает его смонтированным; а открытый vault «под угрозой» — это бóльший риск, чем
  сама видимость в сайдбаре. Видимость даёт и штатный выход: «извлечь» из Finder автоматически
  размонтирует том. Старое приватное поведение (вне сайдбара/рабочего стола) — opt-in через
  `ST_VAULT_HIDDEN=1`. На Windows том всегда был виден (буква диска) — поведение сошлось.
  NB: при «извлечь» из Finder post-close хук securetrash не срабатывает (vaultwatch-исключения
  снимутся при следующем явном `vault close` или по TTL) — на безопасность не влияет.

## [0.4.8] — 2026-06-26

### Changed
- **Windows-паритет vault reveal.** `securetrash.ps1`: после монтирования контейнера том
  открывается в Explorer (`explorer.exe <drive>:\`) — зеркало macOS `open <mountpoint>` из
  0.4.7. Reveal best-effort (ошибка запуска Explorer не роняет успешный open) и идёт после
  post-open хука. Отключить: `ST_VAULT_NO_REVEAL=1` (та же переменная, что и на macOS).

## [0.4.7] — 2026-06-26

### Changed
- **`vault open` теперь открывает том в Finder.** Раньше образ монтировался с `-nobrowse`
  (приватность — том не висит в боковой панели / на рабочем столе), и открытый сейф было
  попросту не видно: пользователь не понимал, куда класть файлы. Теперь после монтирования
  выполняется явный `open <mountpoint>` — окно сейфа всплывает, как при двойном клике по dmg,
  а `-nobrowse` по-прежнему держит том вне сайдбара. Отключить: `ST_VAULT_NO_REVEAL=1`.

## [0.4.6] — 2026-06-26

### Changed
- Репозиторий переехал на `github.com/Di-kairos`; перевыпуск с обновлёнными URL и переподписанными ассетами. Функциональных изменений нет.

## [0.4.5] — 2026-06-25

Исправление Windows-интеграции экосистемы: vault-хуки на Windows теперь действительно срабатывают.

### Fixed
- **Windows vault hooks (F1):** `securetrash vault open/close` на Windows раньше НЕ запускал
  хуки `~/.securetrash/hooks/post-open.cmd` / `post-close.cmd`, хотя `vaultwatch install-hooks`
  их туда клал, а доки обещали авто-охрану. Открытый vault оставался без присмотра (Windows
  Search-исключения и TTL-автозакрытие не включались). Порт приведён к контракту macOS
  (`_run_vault_hook`): хук запускается только если файл есть; его падение лишь предупреждает
  и не роняет vault-операцию. Пост-монтажные действия best-effort — ошибка sidecar/хука не
  превращает успешный `open` в провал.
- **Активный том в sidecar (F1/F2):** securetrash выбирает первую свободную букву динамически;
  теперь при `open` она пишется в `<vault>.vhdx.mount` (ACL-защищён, хранит только букву диска —
  не секрет), читается при `close` для post-close хука и лаунчером `paranoid` для корректного
  определения смонтированного тома. Чистится при `close`/`destroy`.

### Tests
- +6 Pester: post-open/post-close hook dispatch, жизненный цикл mount-sidecar, no-op хука без
  файла, override `ST_HOOK_DIR`.

## [0.4.4] — 2026-06-24

Полиш-релиз: паритет постуры установщика с sibling-тулами + чистка публичного репозитория.

### Security
- **`install.sh`:** при вшитом pubkey, но отсутствии `ssh-keygen` установщик теперь громко
  предупреждает, что подпись НЕ проверена (только целостность по SHA256), вместо молчаливого
  пропуска. Паритет с vaultwatch/panic/ghostdraft/seedsplit.

### Housekeeping
- Из публичного репозитория убраны dev-kitchen артефакты (внутренние `CLAUDE.md`, `ECOSYSTEM.md`,
  `PROGRESS.md`, `docs/promo/`, `docs/sessions/`) — теперь gitignored, в релизный tarball не попадают.

## [0.4.3] — 2026-06-23

### Fixed
- **Release signing fail-closed:** выпуск прерывается, если `RELEASE_SIGNING_KEY` не задан —
  релиз без подписи больше невозможен (раньше молча откатывался до checksum-only).
- **`install.sh` fail-closed на отсутствие `.sig`:** установщик жёстко отказывает, если подпись
  релиза отсутствует (для легаси-релизов до v0.4.2 — явный `ALLOW_UNSIGNED_LEGACY=1`).
- **Windows `shred` — reparse-point guard:** junction/symlink удаляется как запись, без рекурсии
  в target.
- **Windows-порт: синхронизирована версия** (`securetrash.ps1` отставал — был 0.4.1 при Bash 0.4.2).

## [0.4.2] — 2026-06-23

### Fixed
- **`shred` — guard на mount-root:** отказывается шредить `/Volumes/<name>` (прямые потомки
  `/Volumes`) — защищает внешние диски и точку монтирования самого vault от случайного
  рекурсивного удаления. Раньше защищён был только сам `/Volumes`.
- **`install.sh` — pubkey подписи релиза:** ассеты v0.4.1 собрали до встраивания pubkey;
  `RELEASE_SIGNING_PUBKEY` был пуст, авто-проверка молча пропускалась. Ассеты релиза v0.4.2
  содержат правильный pubkey — проверка подписи в установщике работает.

## [0.4.1] — 2026-06-22

### Added
- **Подпись релизов (Ed25519, опциональная):** CI подписывает `SHA256SUMS`, `install.sh`
  авто-проверяет подпись поверх контрольной суммы. Мягкая деградация — нет ключа/подписи
  не ломает установку. Pubkey опубликован в `SECURITY.md`.
- Флаги-алиасы `-v`/`--version` и `-h`/`--help`.
- Канонический `lib/common.sh` — источник вендоринга для экосистемы Paranoid Tools.
- Хуки `vault open/close` (`post-open`/`post-close`) — точка интеграции vaultwatch/panic.

### Fixed
- **Windows `vault destroy` — fail-closed (tri-state):** не удаляет backing-файл, пока том
  смонтирован или состояние не определено; mounted → размонтировать и перепроверить.
- **Windows `shred` — protected-path guard:** отказ для корней дисков и системных деревьев
  (Windows, Program Files, ProgramData, корень Users, профиль).

### Changed
- **Windows: честный tri-state детект диска** (ssd/hdd/unknown) — неизвестный тип больше не
  выдаётся за HDD с обнадёживающим «перезапись помогает».
- Честная формулировка crypto-shred в `windows/README`; landing-install тянется с релизного
  тега (а не с подвижной `main`) с проверкой.

## [0.4.0] — 2026-06-18

### Added
- **Checksum-verified `install.sh`** (F-2): бинарь и `SHA256SUMS` тянутся с релизного
  тега, хеш проверяется ДО установки — закрывает supply-chain риск «curl|bash из main».

### Changed
- **`vault destroy` — fail-closed:** никогда не удаляет, пока контейнер смонтирован или
  состояние неизвестно (защита от случайного уничтожения живого vault).
- Hardening: закреплён mountpoint vault, самохостинг шрифтов в доках, FAQ про угрозу
  открытого vault.

## [0.3.0] — 2026-06-17

### Added
- **PowerShell-порт под Windows (beta)** с Pester-тестами и CI.

### Fixed
- Security-hardening: честные формулировки гарантий, `--` guard'ы на путях, проверка
  целевого тома, права `0700`, флаг `--yes`.
- Windows: пароли не через argv, валидация diskpart, `-LiteralPath`, разблокировка
  BitLocker, отслеживание backend.
- Де-пиннинг version-теста.

## [0.2.0] — 2026-06-17

### Added
- **i18n:** вывод по умолчанию на английском, русский — через `ST_LANG=ru`.
- Демо-gif и английский README/guide как основной (русский — вторичный).

## [0.1.0] — 2026-06-17

Первый публичный срез: безопасное удаление + шифрованный vault (crypto-shred) для macOS.

### Added
- **`check`** — честный аудит окружения (FileVault, тип диска SSD/HDD) и вердикт, какие
  гарантии реальны на данном железе.
- **`vault create|open|close|destroy|status`** — шифрованный контейнер; «уничтожение» =
  крипто-шреддинг (удаление ключа), что реально на SSD в отличие от перезаписи.
- **`shred`**, **`setup`**, **`empty`** — удаление файлов/папок, инициализация `~/SecureTrash`.
- README, LICENSE, гайд.

### Honest limitations
- На SSD перезапись (`rm -P`) гарантий НЕ даёт (wear leveling, COW, TRIM) — для секретов
  использовать `vault` превентивно. Подробности — `README.md` «Scope & limitations».

[Unreleased]: https://github.com/Di-kairos/securetrash/compare/v0.4.13...HEAD
[0.5.0]: https://github.com/Di-kairos/securetrash/compare/v0.4.13...v0.5.0
[0.4.13]: https://github.com/Di-kairos/securetrash/compare/v0.4.12...v0.4.13
[0.4.12]: https://github.com/Di-kairos/securetrash/compare/v0.4.11...v0.4.12
[0.4.11]: https://github.com/Di-kairos/securetrash/compare/v0.4.10...v0.4.11
[0.4.10]: https://github.com/Di-kairos/securetrash/compare/v0.4.9...v0.4.10
[0.4.9]: https://github.com/Di-kairos/securetrash/compare/v0.4.8...v0.4.9
[0.4.8]: https://github.com/Di-kairos/securetrash/compare/v0.4.7...v0.4.8
[0.4.7]: https://github.com/Di-kairos/securetrash/compare/v0.4.6...v0.4.7
[0.4.6]: https://github.com/Di-kairos/securetrash/compare/v0.4.5...v0.4.6
[0.4.5]: https://github.com/Di-kairos/securetrash/compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com/Di-kairos/securetrash/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/Di-kairos/securetrash/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/Di-kairos/securetrash/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/Di-kairos/securetrash/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Di-kairos/securetrash/releases/tag/v0.4.0
[0.3.0]: https://github.com/Di-kairos/securetrash/releases/tag/v0.3.0
[0.2.0]: https://github.com/Di-kairos/securetrash/releases/tag/v0.2.0
[0.1.0]: https://github.com/Di-kairos/securetrash/releases/tag/v0.1.0
