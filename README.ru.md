# Paranoid Tools

[English](README.md) · **Русский**

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![platform](https://img.shields.io/badge/platform-macOS%20%C2%B7%20Windows-blue)
![dependencies](https://img.shields.io/badge/dependencies-zero-success)
![releases](https://img.shields.io/badge/releases-Ed25519%20signed-blueviolet)
![tools](https://img.shields.io/badge/tools-5-informational)

Честные privacy/security-утилиты для macOS и Windows — каждая делает одну вещь, без снейкойла.

> **Зачем эти инструменты →** [Манифест Paranoid Tools](MANIFEST.ru.md)

Зонтик небольших CLI-инструментов вокруг **жизненного цикла секрета**
(seed-фраза / пароль / ключ). Каждый инструмент — отдельный git-репо, single-file
скрипт (чистый Bash на macOS/Linux, PowerShell-порт на Windows) с **нулём
зависимостей**, и честен о пределах своих гарантий.

## Состав

| # | Инструмент | Шаг жизни секрета | Платформа | Версия |
|---|------------|-------------------|-----------|--------|
| 1 | [`securetrash`](https://github.com/Di-kairos/securetrash) | хранить в зашифрованном vault, затем уничтожить | macOS · Windows (beta) | `v0.4.4` |
| 2 | [`vaultwatch`](https://github.com/Di-kairos/vaultwatch)   | сторожить открытый vault | macOS · Windows (beta) | `v0.1.3` |
| 3 | [`panic`](https://github.com/Di-kairos/panic)             | мгновенно спрятать по тревоге | macOS · Windows (beta) | `v0.1.3` |
| 4 | [`ghostdraft`](https://github.com/Di-kairos/ghostdraft)   | написать/просмотреть без следов на диске | macOS · Windows (beta) | `v0.1.3` |
| 5 | [`seedsplit`](https://github.com/Di-kairos/seedsplit)     | распределить секрет на доли (Шамир) | macOS · Windows (beta) | `v0.3.2` |

> **Windows.** Все пять инструментов имеют PowerShell-порты (beta, покрыты Pester на CI;
> доли seedsplit байт-совместимы с macOS-сборкой). macOS-примитивы — Spotlight, Time Machine,
> `launchd`, `hdiutil` — маппятся на Windows-эквиваленты (Windows Search, VSS, Task Scheduler,
> BitLocker), а пробелы честно репортятся по каждому инструменту.

У каждого тула — английский `README.md` (русский в `README.ru.md`), `CHANGELOG.md`,
checksum-verified и **подписанный Ed25519** `install.sh`, CI + release-workflow и
обязательная секция **Scope & limitations** — прочитай её, прежде чем доверять инструменту.

## Установка

Каждый тул ставится независимо verify-then-run скриптом из релиза (см. README тула).
Для личного использования всех пяти сразу — локальный установщик в корне репо:

```bash
git clone https://github.com/Di-kairos/paranoid-tools
cd paranoid-tools
bash install.sh            # ставит все 5 в ~/.local/bin
bash install.sh --uninstall
```

> Замечание: `install.sh` копирует скрипты тулов из рабочей копии, где они уже
> лежат (чекаут мейнтейнера). Пять тулов живут в отдельных репо и сюда не
> вендорятся, поэтому свежий клон этого репо скриптов тулов не содержит —
> `install.sh` не установит ничего. Публичным пользователям ставить каждый тул
> его собственным verify-then-run установщиком `curl … | bash` (ссылки выше).

Практический гайд по-русски: [КАК-ПОЛЬЗОВАТЬСЯ.ru.md](КАК-ПОЛЬЗОВАТЬСЯ.ru.md).

## Лаунчер

`paranoid` — интерактивный лаунчер: дашборд состояния плюс меню поверх пяти CLI.
Чистый Bash, ноль зависимостей — как и тулы, которыми он управляет.

Своих секретов не держит и своей крипты не добавляет: запускает те же подписанные
тулы и показывает их вывод — вместе с *Scope & limitations* и вердиктами `check` —
без изменений. Запуск без аргументов:

```bash
paranoid          # открывает дашборд + меню
```

Честно: это лаунчер ради удобства, а не скорость настоящей паники — глобальный
хоткей — дело будущей нативной фазы. Открытый vault всегда помечается «at risk».
Пока это macOS Bash; зеркало на Windows PowerShell в планах.

## Архитектура

- **Раздельные репо + вендоринг.** Общий код = канонический `securetrash/lib/common.sh`,
  вендорится в каждый tool inline между маркерами `# === BEGIN vendored common (pin: <ref>) ===`.
  Синк-скрипт + CI-чек дрейфа. Без runtime-зависимостей, без build-склейки.
- **Vault-хуки.** `securetrash vault open/close` дёргают `~/.securetrash/hooks/{post-open,post-close}` —
  через них vaultwatch/panic цепляются к жизненному циклу контейнера.
- **Закон экосистемы:** один инструмент = одна задача; честно про пределы
  (`Scope & limitations` в README обязательна); не создавать ложного чувства безопасности.

## Лицензия

[MIT](LICENSE). У каждого тул-репо своя MIT `LICENSE`, плюс `SECURITY.md`
(как приватно сообщить об уязвимости) и `CONTRIBUTING.md`.
