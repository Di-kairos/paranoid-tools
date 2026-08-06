[English](README.md) · **Русский**

# vaultwatch

Честный сторож открытого vault — часть экосистемы [Paranoid Tools](https://github.com/Di-kairos/paranoid-tools).

[![CI](https://github.com/Di-kairos/vaultwatch/actions/workflows/ci.yml/badge.svg)](https://github.com/Di-kairos/vaultwatch/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![platform](https://img.shields.io/badge/platform-macOS-blue)
![shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)

`vaultwatch` активен **только пока vault примонтирован**. Он сужает каналы, по которым
открытый plaintext может утечь (Spotlight, Time Machine), и **восстанавливает всё при
закрытии**. Запускается автоматически из хуков `securetrash vault open/close`.

> **Статус: ранний (v0.1.11, work in progress).** Готовы интеграция (хуки + вендоринг),
> **сторожевое ядро `start`/`stop`** (Spotlight off, Time Machine exclude, cloud-detect,
> session report) и **авто-выход `--ttl`** через **launchd LaunchAgent** (managed-таймер,
> виден в `launchctl list`, чисто снимается через bootout).

## Установка

Checksum-verified установка с релизного тега (как у securetrash) — verify-then-run:

```bash
curl -fsSLO https://github.com/Di-kairos/vaultwatch/releases/latest/download/install.sh
curl -fsSLO https://github.com/Di-kairos/vaultwatch/releases/latest/download/SHA256SUMS
curl -fsSLO https://github.com/Di-kairos/vaultwatch/releases/latest/download/SHA256SUMS.sig
printf '%s\n' 'releases@paranoid-tools namespaces="file" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U' > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools -n file -s SHA256SUMS.sig < SHA256SUMS &&   # подлинность: Ed25519, пришитый ключ
shasum -a 256 -c SHA256SUMS --ignore-missing &&   # целостность: сам install.sh
less install.sh &&                               # прочитать глазами — и только потом:
bash install.sh                                  # тянет vaultwatch + сумму, проверяет, ставит
vaultwatch install-hooks                         # подключить к securetrash
```

Быстрая форма (запуск кода, который ты не читал — выбирай осознанно):

```bash
curl -fsSL https://github.com/Di-kairos/vaultwatch/releases/latest/download/install.sh | bash
```

`install.sh` тянет бинарь и `SHA256SUMS` из неизменного релизного тега и проверяет хеш
**до** установки. Переменные: `VW_VERSION` (конкретный тег), `VW_DEST` (путь установки),
`VW_BASE_URL` (переопределить источник для форков/тестов).

> **Целостность ≠ подлинность (честные границы).** Сумма доказывает, что бинарь совпадает
> с `SHA256SUMS` из **того же релиза** — это ловит повреждение и частичную/кэш-подмену. Подлинность даёт подпись
> Ed25519 над `SHA256SUMS`: её проверяют и сниппет выше, и `install.sh` — по ключу,
> пришитому в этом репо; без проверки установщик отказывает (см. `SECURITY.md`).
> Остаточный риск — один проектный ключ на все пять тулов, см.
> [модель угроз](https://github.com/Di-kairos/paranoid-tools/blob/main/THREAT-MODEL.ru.md). Для воспроизводимости фиксируй версию: `VW_VERSION=0.1.11` вместо `latest`.

> Текущий публичный релиз — **v0.1.11** (подписан, с `install.sh` + `SHA256SUMS`).
> Для воспроизводимости фиксируй его: `VW_VERSION=0.1.11` вместо `latest`.

## Использование

```bash
vaultwatch start [--ttl D] [--force] <mount>   # сторожить vault (обычно из хука post-open)
vaultwatch stop  <mount>                        # восстановить всё + session report (post-close)
vaultwatch status                               # показать активные сессии (только чтение)
vaultwatch install-hooks                        # подключить к securetrash vault open/close
vaultwatch uninstall-hooks                      # убрать (только свои managed-хуки)
vaultwatch version                              # показать версию
```

`--ttl D` — авто-detach тома через `D` (`30m`, `2h`, `45s`, `1d` или голые секунды).
Таймер ставится как **launchd LaunchAgent** (`~/Library/LaunchAgents/com.vaultwatch.ttl.*.plist`,
`RunAtLoad` → спит `D` → дёргает `vaultwatch _ttl_fire <mount>`). По истечении vaultwatch
проверяет открытые файлы (`lsof`) и, если их нет, размонтирует том (`hdiutil detach`) и
восстанавливает состояние. Если файлы открыты — **честно не трогает** том и предупреждает;
`--force` форсирует `hdiutil detach -force` (с подтверждением, риск потери данных).
`stop` (ручное закрытие раньше TTL) снимает LaunchAgent (`bootout` + удаление plist).

`start` запоминает прежнее состояние и сужает каналы утечки; `stop` восстанавливает
**ровно то, что менял** `start` (если Spotlight был уже выключен или vault уже исключён
из Time Machine до сессии — `stop` это не трогает), и печатает отчёт сессии.

**Unmount-guard (macOS).** Если вытолкнуть vault из Finder (или размонтировать мимо
`vaultwatch stop` / post-close-хука securetrash), исключения иначе висели бы до следующего
явного `stop`. Поэтому `start` ставит ещё и launchd-агент с `WatchPaths` на точке монтирования
(`com.vaultwatch.guard.*.plist`): когда том исчезает, срабатывает `vaultwatch _guard_fire` и
восстанавливает всё — **только если том действительно пропал** (срабатывание `WatchPaths` от
записи внутри всё ещё смонтированного vault остаётся no-op). `stop` снимает guard. На Windows
аналог сделан **опросной задачей планировщика** (задержка ~1 мин, не событийно) — см.
`windows/README.md`.

Хуки кладутся в `${ST_HOOK_DIR:-~/.securetrash/hooks}` — тот же каталог, который читает
`securetrash`. Чужие (не-managed) хуки `vaultwatch` не трогает.

### Session report (пример)

```
vaultwatch — session report
  длительность:    24m 18s
  Spotlight:       индексация снова включена для /Volumes/SecretVault
  Time Machine:    исключение снято (добавляла эта сессия)
  cloud daemons:   Dropbox активен — vault ВНЕ его синк-папки
  local snapshots: не обнаружено (tmutil listlocalsnapshots /)
  swap:            не затрагивается (см. limitations)
```

## Архитектура

- Single-file Bash, ноль зависимостей. Нативные примитивы macOS.
- Общее ядро (`lib/common.sh`) **вендорится** из securetrash inline, пиннуто к git-ref;
  `tools/vendor-common.sh --check` ловит дрейф в CI. См. [`paranoid-tools/README.md`](https://github.com/Di-kairos/paranoid-tools#readme).

## Scope & limitations

Базовый принцип экосистемы: честно про пределы. vaultwatch делает **обратимые**
исключения на время сессии и **не**:

- **не закрывает swap** — если во время сессии была memory pressure, фрагменты plaintext
  могли уйти в swap и остаться там до перезаписи. session report говорит это прямо.
- **не удаляет уже снятые локальные снапшоты** Time Machine: `addexclusion` исключает
  vault на будущее, но снапшоты, снятые до старта, остаются. vaultwatch их обнаруживает
  (`tmutil listlocalsnapshots /`) и сообщает в отчёте — не удаляет молча.
- **не редактирует настройки облаков и не удаляет чужие бэкапы.** cloud-детект эвристичен:
  смотрит запущенные процессы (Dropbox/OneDrive/iCloud/Google Drive) и лежит ли mount
  внутри их синк-папок — сообщает «демон X активен, vault внутри/вне его папки», не телепатия.
- **восстанавливает только своё:** если Spotlight был выключен или vault уже был исключён
  из Time Machine до сессии — `stop` оставляет это как есть, не «чинит» чужое состояние.
- **`--ttl` упирается в открытые файлы:** `hdiutil detach` не размонтирует том с открытыми
  дескрипторами. vaultwatch проверяет `lsof` и при занятости **не форсирует** — честно
  предупреждает; `--force` (`detach -force`) только с подтверждением и осознанием риска.

## Windows (beta)

PowerShell-порт уже существует — в [`windows/README.md`](windows/README.md). Он повторяет
логику macOS там, где позволяет платформа: **контролирует индексатор Windows Search** (исключает
mount, восстанавливает при закрытии), а unmount-guard пере-восстанавливает исключение, если том
извлекли мимо `stop`. VSS shadow copies и облачные демоны (OneDrive/Dropbox/Google Drive) —
**репортятся, не контролируются**; pagefile не адресуется. Честный разбор по каналам — в
`windows/README.md`.

> **Beta:** Windows-порт протестирован по логике (Pester на CI), но ещё не проверен на
> реальном Windows-железе. См. [`windows/README.md`](windows/README.md).

## Лицензия

[MIT](LICENSE). Политика безопасности — [SECURITY.md](SECURITY.md), как внести вклад —
[CONTRIBUTING.md](CONTRIBUTING.md).
