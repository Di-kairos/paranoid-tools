# Paranoid Tools

[English](README.md) · **Русский**

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
![platform](https://img.shields.io/badge/platform-macOS%20%C2%B7%20Windows-blue)
![dependencies](https://img.shields.io/badge/dependencies-zero-success)
![releases](https://img.shields.io/badge/releases-Ed25519%20signed-blueviolet)
![tools](https://img.shields.io/badge/tools-5-informational)

Честные privacy/security-утилиты для macOS и Windows — каждая делает одно дело, без шарлатанства.

> **Зачем эти инструменты →** [Манифест Paranoid Tools](MANIFEST.ru.md)

Зонтик небольших CLI-инструментов вокруг **жизненного цикла секрета**
(seed-фраза / пароль / ключ). Каждый инструмент — отдельный git-репозиторий,
один файл-скрипт (чистый Bash на macOS/Linux, PowerShell-порт на Windows) с
**нулём зависимостей**, и честно говорит о пределах своих гарантий.

## Состав

| # | Инструмент | Шаг жизни секрета | Платформа | Версия |
|---|------------|-------------------|-----------|--------|
| 1 | [`securetrash`](https://github.com/Di-kairos/securetrash) | хранить в зашифрованном vault, затем уничтожить | macOS · Windows (beta) | `v0.4.5` |
| 2 | [`vaultwatch`](https://github.com/Di-kairos/vaultwatch)   | сторожить открытый vault | macOS · Windows (beta) | `v0.1.3` |
| 3 | [`panic`](https://github.com/Di-kairos/panic)             | мгновенно спрятать по тревоге | macOS · Windows (beta) | `v0.1.4` |
| 4 | [`ghostdraft`](https://github.com/Di-kairos/ghostdraft)   | написать или просмотреть без следов на диске | macOS · Windows (beta) | `v0.1.3` |
| 5 | [`seedsplit`](https://github.com/Di-kairos/seedsplit)     | разбить секрет на доли (Шамир) | macOS · Windows (beta) | `v0.3.2` |

> **Windows.** У всех пяти инструментов есть PowerShell-порты (beta, покрыты Pester на CI;
> доли seedsplit байт-совместимы с macOS-сборкой). macOS-примитивы — Spotlight, Time Machine,
> `launchd`, `hdiutil` — сопоставлены с Windows-аналогами (Windows Search, VSS, Task Scheduler,
> BitLocker), а где остаются пробелы, об этом честно сказано в каждом инструменте.

У каждого инструмента — английский `README.md` (русский в `README.ru.md`), `CHANGELOG.md`,
установщик `install.sh` с проверкой по контрольной сумме и **подписью Ed25519**, CI и
release-workflow, и обязательный раздел **Scope & limitations** — прочитай его, прежде чем
доверять инструменту.

## Установка

Каждый инструмент ставится отдельно: скрипт сначала проверяет релиз, потом запускает
(см. README инструмента). Чтобы поставить все пять сразу для личного использования —
в корне репозитория есть локальный установщик:

```bash
git clone https://github.com/Di-kairos/paranoid-tools
cd paranoid-tools
bash install.sh            # ставит все 5 в ~/.local/bin
bash install.sh --uninstall
```

> Замечание: `install.sh` копирует скрипты инструментов из рабочей копии, где они уже
> лежат (копия мейнтейнера). Пять инструментов живут в отдельных репозиториях и сюда не
> вшиваются, поэтому свежий клон этого репозитория скриптов не содержит — `install.sh`
> ничего не поставит. Публичным пользователям лучше ставить каждый инструмент его
> собственным установщиком `curl … | bash`, который проверяет релиз перед запуском (ссылки выше).

Практический гайд по-русски: [КАК-ПОЛЬЗОВАТЬСЯ.ru.md](КАК-ПОЛЬЗОВАТЬСЯ.ru.md).

## Лаунчер

`paranoid` — интерактивный лаунчер: дашборд состояния и меню поверх пяти CLI.
Чистый Bash, ноль зависимостей — как и инструменты, которыми он управляет.

Своих секретов не держит и своей криптографии не добавляет: запускает те же подписанные
инструменты и показывает их вывод — вместе с *Scope & limitations* и вердиктами `check` —
без изменений. Запуск без аргументов:

```bash
paranoid          # открывает дашборд и меню
```

Честно: это лаунчер ради удобства, а не скорость настоящей паники — глобальный хоткей
оставлен на будущую нативную фазу. Открытый vault всегда помечается «at risk».
Зеркало на Windows PowerShell теперь тоже есть — `windows/paranoid.ps1` (beta): запуск
`pwsh -File windows/paranoid.ps1` (или положи в PATH под именем `paranoid`); оно управляет
теми же пятью PowerShell-портами.

## Как это устроено

- **Раздельные репозитории + вендоринг.** Общий код — канонический `securetrash/lib/common.sh`;
  он вшивается в каждый инструмент прямо в текст между маркерами `# === BEGIN vendored common (pin: <ref>) ===`.
  Скрипт синхронизации и CI-проверка дрейфа держат копии честными. Ни рантайм-зависимостей, ни шага сборки.
- **Vault-хуки.** `securetrash vault open/close` запускают `~/.securetrash/hooks/{post-open,post-close}` —
  через них vaultwatch и panic цепляются к жизненному циклу контейнера.
- **Закон экосистемы:** один инструмент — одна задача; честно о пределах
  (раздел `Scope & limitations` в README обязателен); никогда не создавать ложного чувства безопасности.

## Лицензия

[MIT](LICENSE). У каждого репозитория-инструмента своя MIT `LICENSE`, плюс `SECURITY.md`
(как приватно сообщить об уязвимости) и `CONTRIBUTING.md`.
