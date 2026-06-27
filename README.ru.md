<div align="center">

[English](README.md) · **Русский**

<img src="assets/logo.svg" alt="Paranoid Tools" width="620">

### Честные privacy/security-утилиты для macOS и Windows — каждая делает одно дело, без шарлатанства.

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
&nbsp;![platform](https://img.shields.io/badge/platform-macOS%20%C2%B7%20Windows-blue)
&nbsp;![dependencies](https://img.shields.io/badge/dependencies-zero-success)
&nbsp;![releases](https://img.shields.io/badge/releases-Ed25519%20signed-blueviolet)
&nbsp;![tools](https://img.shields.io/badge/tools-5-informational)

**[Манифест](MANIFEST.ru.md)** &nbsp;·&nbsp; **[Инструменты](#состав)** &nbsp;·&nbsp; **[Установка](#установка)** &nbsp;·&nbsp; **[Лаунчер](#лаунчер)**

<img src="assets/dashboard.svg" alt="Лаунчер paranoid: дашборд состояния и меню поверх пяти инструментов" width="560">

</div>

> **Не доверяй — проверяй.** Релизы подписаны Ed25519 · ноль зависимостей · один читаемый
> файл на инструмент · shellcheck-clean. Каждое ограничение названо прямо — см. *Scope &amp;
> limitations* у каждого инструмента. Сторонний аудит мы не заявляем: код мал настолько,
> что его можно прочитать самому.

Зонтик небольших CLI-инструментов вокруг **жизненного цикла секрета**
(seed-фраза / пароль / ключ). Каждый инструмент — отдельный git-репозиторий,
один файл-скрипт (чистый Bash на macOS/Linux, PowerShell-порт на Windows) с
**нулём зависимостей**, и честно говорит о пределах своих гарантий.

## Состав

| # | Инструмент | Шаг жизни секрета | Платформа | Версия |
|---|------------|-------------------|-----------|--------|
| 1 | [`securetrash`](https://github.com/Di-kairos/securetrash) | хранить в зашифрованном vault, очистить или уничтожить | macOS · Windows (beta) | `v0.4.10` |
| 2 | [`vaultwatch`](https://github.com/Di-kairos/vaultwatch)   | сторожить открытый vault | macOS · Windows (beta) | `v0.1.4` |
| 3 | [`panic`](https://github.com/Di-kairos/panic)             | мгновенно спрятать по тревоге | macOS · Windows (beta) | `v0.1.5` |
| 4 | [`ghostdraft`](https://github.com/Di-kairos/ghostdraft)   | написать или просмотреть без следов на диске | macOS · Windows (beta) | `v0.1.6` |
| 5 | [`seedsplit`](https://github.com/Di-kairos/seedsplit)     | разбить секрет на доли (Шамир) | macOS · Windows (beta) | `v0.3.3` |

> **Windows.** У всех пяти инструментов есть PowerShell-порты (beta, покрыты Pester на CI;
> доли seedsplit байт-совместимы с macOS-сборкой). macOS-примитивы — Spotlight, Time Machine,
> `launchd`, `hdiutil` — сопоставлены с Windows-аналогами (Windows Search, VSS, Task Scheduler,
> BitLocker), а где остаются пробелы, об этом честно сказано в каждом инструменте.

У каждого инструмента — английский `README.md` (русский в `README.ru.md`), `CHANGELOG.md`,
установщик `install.sh` с проверкой по контрольной сумме и **подписью Ed25519**, CI и
release-workflow, и обязательный раздел **Scope & limitations** — прочитай его, прежде чем
доверять инструменту.

## Установка

Одна команда ставит все пять инструментов и лаунчер в `~/.local/bin`:

```bash
git clone https://github.com/Di-kairos/paranoid-tools
cd paranoid-tools
bash install.sh            # ставит все 5 + лаунчер paranoid
bash install.sh --uninstall
```

На свежем клоне каждый инструмент тянется из своего **подписанного релиза** по схеме
verify-then-run: установщик проверяет подпись Ed25519 над `SHA256SUMS`, затем контрольную
сумму install.sh самого инструмента и только потом запускает его — а тот, в свою очередь,
проверяет бинарь до установки. Ничего не выполняется, пока не проверено. Закрепить версию —
`PT_PANIC_VERSION=0.1.5`; сменить каталог — `PT_DEST=/usr/local/bin`.

Нужен только один инструмент или хочется пройти каждый шаг руками? В README каждого
инструмента есть отдельный verify-then-run сниппет и однострочная быстрая форма. См. [состав](#состав).

### Обновление

Команды `update` нет — обновление означает **повторный запуск установщика**. Он тянет
последний подписанный релиз каждого инструмента и перезаписывает бинарь на месте:

```bash
cd paranoid-tools
git pull            # обновить клон (лаунчер + установщик)
bash install.sh     # переустановить все инструменты на последних подписанных релизах
```

Версию инструмента смотри через `securetrash version` (или `--version` у любого). Если в
обновлении изменилось рантайм-поведение (напр. `securetrash vault` теперь монтирует том
видимо в Finder), уже открытая сессия держит старый код — переоткрой её: `securetrash vault
close`, затем `securetrash vault open`.

Практические гайды: **[English](GUIDE.md)** · [Русский](ИНСТРУКЦИЯ.md).

## Лаунчер

`paranoid` — интерактивный лаунчер: дашборд состояния и меню поверх пяти CLI.
Чистый Bash, ноль зависимостей — как и инструменты, которыми он управляет. Меню
сгруппировано в подменю — **Сейф** (открыть/закрыть · очистить · уничтожить · сторожить),
**Блокнот** (ghostdraft), **Секреты** (seedsplit) — а *Статус* и *ПАНИКА* в один нажим
оставлены наверху. **Очистить** crypto-shred'ит содержимое сейфа и даёт новый пустой
(настоящая гарантия, в отличие от перезаписи файлов на месте на SSD).

Своих секретов не держит и своей криптографии не добавляет: запускает те же подписанные
инструменты и показывает их вывод — вместе с *Scope & limitations* и вердиктами `check` —
без изменений. Запуск без аргументов:

```bash
paranoid          # открывает дашборд и меню
```

<div align="center">
<img src="demo/demo.gif" alt="Лаунчер paranoid: живой дашборд состояния, затем проверка только на чтение — всё из одного меню" width="720">
</div>

Честно: это лаунчер ради удобства, а не скорость настоящей паники. Для мгновенной
системной кнопки паники — `panic hotkey install` (глобальный хоткей через skhd, см. README
panic). Открытый vault всегда помечается «at risk».
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
