# Changelog

Все заметные изменения seedsplit. Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версионирование — [SemVer](https://semver.org/lang/ru/).

## [Unreleased]

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

[Unreleased]: https://github.com/Di-kairos/seedsplit/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/Di-kairos/seedsplit/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Di-kairos/seedsplit/compare/v0.3.3...v0.4.0
[0.3.3]: https://github.com/Di-kairos/seedsplit/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/Di-kairos/seedsplit/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/Di-kairos/seedsplit/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/Di-kairos/seedsplit/releases/tag/v0.3.0
[0.2.0]: https://github.com/Di-kairos/seedsplit/releases/tag/v0.2.0
