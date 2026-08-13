[English](README.md) · **Русский**

# ghostdraft

Эфемерный черновик для чувствительного текста — часть экосистемы
[Paranoid Tools](../README.md).

Написать/просмотреть seed, пароль или ключ так, чтобы после закрытия следов не
осталось в обычных местах (`~/.*_history`, tmp, recent docs, editor backups/viminfo).

[![CI](https://github.com/Di-kairos/paranoid-tools/actions/workflows/ci-ghostdraft.yml/badge.svg)](https://github.com/Di-kairos/paranoid-tools/actions/workflows/ci-ghostdraft.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![platform](https://img.shields.io/badge/platform-macOS-blue)
![windows](https://img.shields.io/badge/Windows-beta-orange)
![shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)

> **Статус: ранний (v0.1.18).** Готовы `pipe` (просмотр без записи на диск) и `new`
> (черновик в открытом vault / на RAM-диске → `$EDITOR` → shred + чистка editor-следов
> по выходу), включая опциональный `--clipboard` (опасно, с подтверждением + авто-очистка).

## Установка

Checksum-verified установка с релизного тега — verify-then-run (не доверяй — проверяй).
Прогнать скрипт через `| bash` — значит запустить код, который ты не читал, поэтому лучше так:

```bash
base=https://github.com/Di-kairos/paranoid-tools/releases/download/ghostdraft-v0.1.19
curl -fsSLO "$base/install.sh"
curl -fsSLO "$base/SHA256SUMS"
curl -fsSLO "$base/SHA256SUMS.sig"
printf '%s\n' 'releases@paranoid-tools namespaces="file" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U' > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools -n file -s SHA256SUMS.sig < SHA256SUMS &&   # подлинность: Ed25519, пришитый ключ
shasum -a 256 -c SHA256SUMS --ignore-missing &&   # целостность: сам install.sh
less install.sh &&                               # прочитать глазами — и только потом:
bash install.sh                                  # тянет ghostdraft + сумму, проверяет, ставит
```

Быстрая форма (если доверяешь источнику):

```bash
curl -fsSL https://github.com/Di-kairos/paranoid-tools/releases/download/ghostdraft-v0.1.19/install.sh | bash
```

`install.sh` тянет бинарь и `SHA256SUMS` из неизменного релизного тега и проверяет хеш
**до** установки. Переменные окружения: `GHOSTDRAFT_VERSION` (зафиксировать тег вместо
`latest`), `GHOSTDRAFT_DEST` (путь установки), `GHOSTDRAFT_BASE_URL` (переопределить
источник для форков/тестов).

> **Целостность ≠ подлинность (честные границы).** Сумма доказывает, что бинарь совпадает
> с `SHA256SUMS` из того же релиза — ловит повреждение и не даёт запустить код с подвижной
> `main`. Подлинность даёт подпись Ed25519 над `SHA256SUMS`:
> её проверяют и сниппет выше, и `install.sh` — по ключу, пришитому в этом репо; без
> проверки установщик отказывает (см. `SECURITY.md`). Остаточный риск — один проектный
> ключ на все пять тулов, см.
> [модель угроз](../THREAT-MODEL.ru.md).

> Текущий публичный релиз — **v0.1.18** (подписан, с `install.sh` + `SHA256SUMS`).
> Для воспроизводимости фиксируй его: `GHOSTDRAFT_VERSION=0.1.18` вместо `latest`.

## Использование

```bash
ghostdraft new            # эфемерный черновик в открытом vault / на RAM-диске
ghostdraft new --clipboard # + положить в буфер и очистить через N сек (ОПАСНО, см. ниже)
pbpaste | ghostdraft pipe # просмотреть из буфера, на диск не писать ничего
ghostdraft version        # показать версию (также -v / --version)
ghostdraft --help         # справка (также -h)
```

**Как выйти из дефолтного редактора (vim).** `new` открывает `vim` (с мягким переносом и
без `~/.viminfo`), если `$EDITOR` не задан. Он открывается **сразу готовым к печати** — обычный
vim стартует в normal-режиме, где буквы это команды и текст никуда не попадает.
Чтобы выйти: **`Ctrl-D`** — сохранить и выйти,
**`Ctrl-X`** — выйти без сохранения. Обе работают из любого режима: жать `Esc` заранее не нужно,
внизу всегда висит подсказка. `Esc` → `ZZ`/`ZQ` и `:wq` / `:q!` по-прежнему работают для тех, кто
знает vim; **F2/F3** тоже назначены, но некоторые терминалы (например Warp) их перехватывают до
vim. Запись макросов намеренно отключена: промах по `ZQ` включал её, и редактор после этого
выглядел зависшим.

## Архитектура

- Single-file Bash, ноль зависимостей. Нативные примитивы macOS (`hdiutil` для RAM-диска,
  `$EDITOR`/nano). `new` предпочитает писать **внутрь открытого vault** securetrash.
- Общее ядро (`lib/common.sh`) **вендорится** из securetrash inline, пиннуто к git-ref;
  `tools/vendor-common.sh --check` ловит дрейф в CI. См. [`paranoid-tools/README.md`](../README.md).

## Куда `new` пишет черновик (по приоритету)

1. **`$GHOSTDRAFT_DIR`** — если задан и доступен на запись (override для своих сценариев;
   безопасность на диске — на твоей совести).
2. **Открытый vault securetrash** (`/Volumes/SecretVault`, переопределяется
   `$ST_VAULT_VOLUME`) — зашифрован; закрытие vault даёт crypto-shred.
3. **RAM-диск** (`hdiutil attach -nomount ram://` + HFS+) — живёт в RAM, исчезает при
   detach по выходу; не синкается, не ложится на SSD.
4. **Ничего из этого недоступно → отказ** (exit 3). НЕ пишем молча в `/tmp` на APFS.

## Scope & limitations

> Принцип экосистемы: честно про пределы — здесь особенно легко скатиться в снейкойл,
> поэтому НЕ обещаем «ноль следов»:
> - **на macOS `/dev/shm` НЕТ**; `/tmp`/`$TMPDIR` лежат на APFS (на диске). Настоящая
>   in-memory — только RAM-диск (`hdiutil attach -nomount ram://`), его и используем;
> - **что вычищаем по выходу:** сам черновик (`securetrash shred`, иначе overwrite+rm),
>   vim swap/undo (`.swp`/`.swo`/`.swn`/`.un~`), nano backup (`file~`), и detach нашего
>   RAM-диска;
> - **что вычистить НЕ можем** (и честно об этом говорим): scrollback терминала, swap ОС,
>   `~/.viminfo` (регистры/последний yank/история поиска). Это вне досягаемости утилиты;
> - **`--clipboard` для seed опасен** (clipboard-менеджеры + Universal Clipboard синкает
>   буфер в iCloud на другие устройства) — по умолчанию ВЫКЛ, при включении требует
>   подтверждения; авто-очистка через `${GHOSTDRAFT_CLIP_SECS:-20}` с, но лишь если буфер
>   не сменился, и она НЕ отменяет уже снятую копию;
> - **fallback-shred на SSD — не гарантия** (ровно об этом предупреждает securetrash);
>   реальное стирание даёт RAM-disk detach или crypto-shred закрытого vault.

## Windows (beta)

PowerShell-порт уже существует — в [`windows/README.md`](windows/README.md). Он повторяет
логику macOS честными Windows-заменами: черновик идёт в открытый vault, а без него — в
on-disk temp-каталог с ACL только для владельца и fallback shred (RAM-диска на Windows
нет — README порта говорит об этом прямо); плюс очистка clipboard и чистка Notepad/editor
backups и jump lists / recent.

> **Beta:** Windows-порт протестирован по логике (Pester на CI), но ещё не проверен на
> реальном Windows-железе. См. [`windows/README.md`](windows/README.md).

## Лицензия

[MIT](LICENSE). Сообщения о безопасности — [SECURITY.md](SECURITY.md), вклад —
[CONTRIBUTING.md](CONTRIBUTING.md).
