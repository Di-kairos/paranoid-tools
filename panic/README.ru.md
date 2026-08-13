[English](README.md) · **Русский**

# panic

Kill-switch в один шаг — всё с экрана, vault'ы заперты, одной командой.

[![CI](https://github.com/Di-kairos/panic/actions/workflows/ci.yml/badge.svg)](https://github.com/Di-kairos/panic/actions/workflows/ci.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![platform](https://img.shields.io/badge/platform-macOS-blue)
![windows](https://img.shields.io/badge/Windows-beta-orange)
![shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)

Часть экосистемы [Paranoid Tools](https://github.com/Di-kairos/paranoid-tools).

Сценарий: граница / принуждение / «кто-то идёт». Одной командой `panic now` (или
глобальным хоткеем через `panic hotkey`, по умолчанию `cmd + alt - p`) **спрятать и запереть** всё:
форс-отмонтировать смонтированные тома (включая открытые disk-образы vault'ов), очистить буфер обмена, заблокировать экран.

## Установка

Checksum-verified установка с релизного тега — verify-then-run (не доверяй — проверяй):

```bash
base=https://github.com/Di-kairos/panic/releases/latest/download
curl -fsSLO "$base/install.sh"
curl -fsSLO "$base/SHA256SUMS"
curl -fsSLO "$base/SHA256SUMS.sig"
printf '%s\n' 'releases@paranoid-tools namespaces="file" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U' > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools -n file -s SHA256SUMS.sig < SHA256SUMS &&   # подлинность: Ed25519, пришитый ключ
shasum -a 256 -c SHA256SUMS --ignore-missing &&   # целостность: сам install.sh
less install.sh &&                               # прочитать глазами — и только потом:
bash install.sh                                  # тянет panic + сумму, проверяет, ставит
```

Быстрая форма (одна строка, **пропускает проверку** — выбирай осознанно):

```bash
curl -fsSL https://github.com/Di-kairos/panic/releases/latest/download/install.sh | bash
```

`install.sh` тянет бинарь и `SHA256SUMS` из неизменного релизного тега и проверяет хеш
**до** установки. Переменные окружения: `PANIC_VERSION` (зафиксировать тег вместо `latest`),
`PANIC_DEST` (путь установки), `PANIC_BASE_URL` (переопределить источник для форков/тестов).

> **Целостность ≠ подлинность (честные границы).** Контрольная сумма доказывает, что
> бинарь совпадает с `SHA256SUMS` из того же релиза — это ловит повреждение,
> частичную/кэш-подмену и не даёт запустить код с подвижной ветки `main`. Подлинность даёт подпись Ed25519
> над `SHA256SUMS`: её проверяют и сниппет выше, и `install.sh` — по ключу, пришитому в
> этом репо; без проверки установщик отказывает (см. `SECURITY.md`). Остаточный риск —
> один проектный ключ на все пять тулов, см.
> [модель угроз](https://github.com/Di-kairos/paranoid-tools/blob/main/THREAT-MODEL.ru.md). Зафиксируй конкретную
> версию через `PANIC_VERSION=0.1.15` вместо `latest` для воспроизводимости.

## Использование

```bash
panic status            # только чтение: предпросмотр — что затронет `panic now`
panic now               # спрятать и запереть сейчас
panic now --hard        # + прибить cloud-демоны, почистить «Recent items»
panic hotkey install    # повесить глобальный хоткей (cmd + alt - p) на `panic now`
panic hotkey status     # показать / снять хоткей
panic version           # показать версию (также -v / --version)
panic --help            # показать справку (также -h / help)
```

Явный verb `now` выбран намеренно: kill-switch не должен срабатывать от случайного
`panic` без аргументов (bare `panic` → usage).

Что делает `panic now`:

1. размонтирует все смонтированные disk-образы под `/Volumes` (`hdiutil detach -force`);
2. очищает буфер обмена (`pbcopy </dev/null`);
3. блокирует экран (`CGSession -suspend`, на современных macOS — fallback Ctrl+Cmd+Q
   через `osascript`; при неудаче обоих — честно предупреждает, а не врёт об успехе).

С флагом `--hard` дополнительно: прибивает cloud-демоны (Dropbox, OneDrive, iCloud `bird`,
Google Drive) и чистит глобальные Recent items (shared file lists).

### Глобальный хоткей

Чтобы срабатывало в один шаг, повесь `panic now` на системную горячую клавишу:

```bash
panic hotkey install                 # по умолчанию: cmd + alt - p
panic hotkey install "cmd + shift - escape"   # или своя комбинация
panic hotkey status                  # показать текущий биндинг
panic hotkey uninstall               # снять
```

Настоящий глобальный хоткей на macOS требует резидентного слушателя с правом Accessibility —
на чистом Bash это невозможно. `panic hotkey` использует [`skhd`](https://github.com/koekeishiya/skhd),
крошечный hotkey-демон (`brew install skhd`). Биндинг лежит в явно помеченном managed-блоке
твоего `skhdrc`, так что твои собственные skhd-биндинги не затрагиваются. При первом срабатывании
выдай skhd доступ в **System Settings → Privacy & Security → Accessibility**, иначе хоткей не сработает.

> **`panic hotkey` — только для macOS, и это решение, а не пункт в очереди.** Там он вешается
> через skhd; в Windows аналога нет, а держать фоновый процесс ради слежения за клавиатурой
> panic не станет. Windows и так вешает горячие клавиши там, где им место, — на ярлыке: сделай
> ярлык на `panic.cmd`, открой «Свойства», поставь курсор в поле *Быстрый вызов* и нажми
> `Ctrl+Alt+P`. `panic hotkey` на Windows печатает ровно это, а не делает вид, что такой
> команды нет.

## Архитектура

- Single-file Bash, ноль зависимостей. Нативные примитивы macOS (`hdiutil`,
  `pbcopy`, `CGSession` c fallback `osascript` Ctrl+Cmd+Q для lock).
- Общее ядро (`lib/common.sh`) **вендорится** из securetrash inline, пиннуто к git-ref;
  `tools/vendor-common.sh --check` ловит дрейф в CI. См. [`paranoid-tools/README.md`](https://github.com/Di-kairos/paranoid-tools#readme).
- Форс-отмонтирует смонтированные disk-образы под `/Volumes` напрямую (`hdiutil detach -force`) —
  НЕ зовёт vaultwatch и не запускает vault-close хуки securetrash. Быстро и грубо намеренно;
  риск (форс-detach может потерять несохранённые записи) описан ниже.

## Scope & limitations

Базовый принцип экосистемы: честно про пределы. panic **прячет и запирает**, но:

- **не уничтожает** данные и **не чистит swap** (для уничтожения — `securetrash`);
  фрагменты plaintext могли уйти в swap и остаться там до перезаписи.
- `detach -force` при открытых файлах может **повредить данные** — осознанный
  trade-off режима паники (спрятать важнее), пользователь должен это знать. Нет confirm:
  скорость важнее; защита от случайного запуска — явный verb `now`.
- размонтирует **disk-образы под `/Volumes`** (vault'ы/dmg); system-образы вне `/Volumes`
  не трогает. Физические внешние диски — в следующих паках.
- `--hard` чистит **глобальные** Recent items (shared file lists); per-app «недавние»
  внутри приложений этим НЕ стираются — честно про предел.
- блокировка экрана — сначала `CGSession -suspend` (реальный login-window, не зависит от
  настройки «требовать пароль»), затем fallback Ctrl+Cmd+Q через `osascript` на современных
  macOS (≥12, где legacy-бандл `CGSession` удалён). Fallback требует Accessibility-доступа
  терминалу; если упали **оба** метода — panic **не** утверждает, что экран заперт: громко
  предупреждает и просит запереть вручную. Переопределяемо через `PANIC_CGSESSION` /
  `PANIC_OSASCRIPT`.
- не имитирует «полное стирание за секунду» — это была бы ложь.

## Windows (beta)

PowerShell-порт уже существует — в [`windows/README.md`](windows/README.md). Он повторяет
логику macOS — блокировку рабочей станции, размонтирование томов BitLocker/VeraCrypt и очистку буфера обмена.

> **Beta:** Windows-порт протестирован по логике (Pester на CI), но ещё не проверен на
> реальном Windows-железе. См. [`windows/README.md`](windows/README.md).

## Лицензия

Распространяется под лицензией [MIT](LICENSE). Без каких-либо гарантий — см. файл лицензии.
Сообщить об уязвимости — [SECURITY.md](SECURITY.md). Как внести вклад — [CONTRIBUTING.md](CONTRIBUTING.md).
