# User Trial Report — Paranoid Tools

Дата: 2026-07-06  
Роль: внешний пользователь, который впервые открыл `Di-kairos/paranoid-tools`, читает README и пытается всё попробовать руками.

## Короткий вердикт

Основной путь для macOS работает: свежий clone без вложенных tool-репозиториев ставит все пять инструментов из подписанных релизов, версии запускаются, проверка релизов проходит, smoke-test проходит при обычном доступе к macOS DiskManagement/hdiutil.

Главные проблемы не в ядре установки, а в первом пользовательском опыте вокруг документации и диагностики:

- `docs/TESTING.md` выглядит как внутренний maintainer-документ, но лежит как пользовательский гайд: в нём локальные пути `/Volumes/X10 Pro/...`, устаревшая версия `securetrash 0.4.10` и неверное ожидаемое число проверок.
- В английском README uninstall-команда всё ещё находится в install-блоке, тогда как русский README уже отделил удаление.
- Русская `ИНСТРУКЦИЯ.md` отстаёт от `README.ru.md`: там осталось широкое «ничего не выполняется, пока не проверено» и предположение, что `~/.local/bin` уже в PATH.
- `panic status` в ограниченном/headless окружении может напечатать частичный отчёт и выйти с кодом `1` из-за `pbpaste | wc -c` под `set -euo pipefail`.
- В текущей среде dashboard лаунчера показывает `FileVault: неизвестно`, а пункт `Статус` сразу ниже говорит `FileVault ВЫКЛЮЧЕН`; для пользователя это выглядит как противоречие.

## Что проверял

### Документы первого входа

Прочитаны:

- `README.md`
- `README.ru.md`
- `GUIDE.md`
- `ИНСТРУКЦИЯ.md`
- `docs/TESTING.md`
- `gui/README.md`

Первое впечатление: позиционирование понятное, честность про ограничения заметна сразу, русский README после правок стал намного яснее. Лучшая входная точка для пользователя сейчас — `README.ru.md`, а не `ИНСТРУКЦИЯ.md` и не `docs/TESTING.md`.

### Fresh install из публичного сценария

Чтобы не смешивать maintainer checkout с внешним clone, я сделал временный архив tracked-файлов без вложенных `securetrash/`, `vaultwatch/`, `panic/`, `ghostdraft/`, `seedsplit/`:

```bash
git archive HEAD | tar -x -C /tmp/paranoid-fresh-user...
```

Потом поставил в отдельный каталог:

```bash
PT_DEST=/tmp/paranoid-fresh-user-bin PATH=/usr/bin:/bin:/usr/sbin:/sbin bash install.sh
```

Результат при обычном сетевом доступе:

```text
securetrash  -> installed from signed release
vaultwatch   -> installed from signed release
panic        -> installed from signed release
ghostdraft   -> installed from signed release
seedsplit    -> installed from signed release
paranoid     -> installed from this repo
```

Проверенные версии:

```text
securetrash 0.4.11
vaultwatch 0.1.6
panic 0.1.7
ghostdraft 0.1.9
seedsplit 0.4.1
paranoid 0.1.0
```

Вывод: публичная установка из signed releases работает.

### Verify releases

Команда:

```bash
bash verify-releases.sh
```

Результат при обычном сетевом доступе:

```text
securetrash  v0.4.11  ok signature + binary verified
vaultwatch   v0.1.6   ok signature + binary verified
panic        v0.1.7   ok signature + binary verified
ghostdraft   v0.1.9   ok signature + binary verified
seedsplit    v0.4.1   ok signature + binary verified

Total: 5 ok, 0 failed
```

В sandbox/ограниченной сети та же команда падала как `assets did not download`; это не проблема релизов, но сообщение можно сделать полезнее: показывать хотя бы `curl` exit code или последний stderr.

### Smoke test

Команда:

```bash
PATH=/tmp/paranoid-fresh-user-bin:/usr/bin:/bin:/usr/sbin:/sbin bash smoke-test.sh
```

Результат при обычном доступе к macOS DiskManagement/hdiutil:

```text
16 ok
0 failed
2 skipped
All automatic checks passed.
```

Skips ожидаемые:

- `ghostdraft new` требует интерактивный editor.
- `vaultwatch` / `panic` отмечены как disruptive и вынесены в ручную проверку.

Важно: в sandbox smoke-test падал на vault-cycle (`hdiutil: create failed - Устройство не сконфигурировано`, `diskutil apfs list` сообщал `unable to use the DiskManagement framework`). После запуска с обычными правами тот же smoke-test прошёл. Это не пользовательский bug продукта, но это важная пометка для CI/Codex/headless-сред.

### Launcher / TUI

Проверено:

```bash
paranoid version
paranoid help
printf '0\n' | ST_LANG=ru paranoid
printf '1\n\n0\n' | ST_LANG=ru paranoid
PARANOID_UPDATE_CHECK=1 paranoid
```

Что хорошо:

- Лаунчер стартует без аргументов.
- Русская chrome-локализация читаемая.
- До установки инструменты показываются как `(не установлен)` в меню.
- После установки все top-level пункты видны и понятны.
- Update-check по умолчанию молчит; при `PARANOID_UPDATE_CHECK=1` не показал ложных обновлений.

Что смутило:

- Если у пользователя уже есть `~/SecureVault.sparsebundle`, но tool-команды не в PATH, dashboard может показать `Сейф: закрыт`, хотя работать с ним нельзя до установки.
- В моей среде dashboard показал `FileVault: неизвестно`, а `Статус` ниже сказал `FileVault ВЫКЛЮЧЕН`. Это выглядит как расхождение в одном пользовательском потоке.

### Direct CLI checks

Проверено:

```bash
securetrash check
securetrash vault status
vaultwatch status
panic status
seedsplit split -n 3 -t 2
ghostdraft pipe
```

Результаты:

- `securetrash check` честно деградирует, если не может определить disk type.
- `securetrash vault status` корректно увидел существующий closed container.
- `vaultwatch status` показал активную сессию.
- `seedsplit split` работает и выдаёт доли.
- `ghostdraft pipe` работает и не пишет на диск.
- `panic status` в ограниченной среде напечатал начало preflight, но вернул exit code `1`; подробнее ниже.

### Tests / static checks

Проверено:

```bash
bats test/paranoid.bats
shellcheck install.sh paranoid smoke-test.sh verify-releases.sh
bats panic/test/status.bats
```

Результаты:

- `test/paranoid.bats`: 49/49 ok.
- `shellcheck`: clean.
- `panic/test/status.bats`: 9/9 ok.

Это хороший сигнал: проблема `panic status` ниже не покрывается stubbed-тестом текущей реальной среды, но unit-level ожидания по статусу существуют.

### GUI / Phase B

Проверено:

```bash
cd gui/macos
./build.sh
```

Результат при обычном доступе к Swift/Clang cache:

```text
Built ./ParanoidBar
```

Артефакт `gui/macos/ParanoidBar` игнорируется `.gitignore`, рабочее дерево после сборки осталось чистым.

Windows runtime не проверял: `pwsh` / `powershell` в текущем окружении отсутствуют. По файлам `windows/paranoid.ps1` и `gui/windows/paranoid-tray.ps1` видно UTF-8 без BOM; это нормально для `pwsh 7`, но для Windows PowerShell 5.1 остаётся потенциальным encoding-risk, если кто-то всё-таки запустит файл напрямую в 5.1.

## Findings

### 1. `docs/TESTING.md` не готов как внешний пользовательский гайд

Severity: P1 documentation / onboarding

Файл выглядит как инструкция "как самому проверить", но содержит локальные пути и устаревшие ожидания:

- `cd "/Volumes/X10 Pro/projects/paranoid-tools" && bash install.sh` (`docs/TESTING.md:14`)
- `securetrash 0.4.10`, хотя текущий релиз `0.4.11` (`docs/TESTING.md:23`)
- `17 ok`, хотя актуальный smoke-output: `16 ok / 0 failed / 2 skipped` (`docs/TESTING.md:36`)
- тот же локальный путь для smoke и verify (`docs/TESTING.md:33`, `docs/TESTING.md:94`)

Почему это важно:

Внешний пользователь, который нашёл `docs/TESTING.md`, не сможет просто скопировать команды. Документ выглядит публичным, но несёт следы локальной машины maintainer'а.

Рекомендация:

- Заменить локальные пути на `cd paranoid-tools` или "из корня репозитория".
- Убрать hard-coded version или обновить до `securetrash 0.4.11`.
- Обновить expected smoke summary до `16 ok / 0 failed / 2 skipped`.
- Явно разделить "проверка публичного clone" и "maintainer checkout with nested tool repos".

### 2. В английском README uninstall всё ещё находится в install-блоке

Severity: P2 onboarding

В `README.md` блок установки содержит:

```bash
git clone ...
cd paranoid-tools
bash install.sh
bash install.sh --uninstall
```

См. `README.md:53-60`.

Русский README уже исправлен и вынес удаление отдельно (`README.ru.md:72-76`).

Почему это важно:

Пользователь может скопировать весь блок целиком и сразу удалить то, что установил. Это особенно неприятно в первом запуске, где человек просто "делает как в README".

Рекомендация:

Сделать английский README симметричным русскому: отдельный mini-section `Uninstall`.

### 3. `ИНСТРУКЦИЯ.md` отстаёт от `README.ru.md`

Severity: P2 documentation consistency

В `ИНСТРУКЦИЯ.md` осталось:

- `~/.local/bin` "уже в твоём PATH" (`ИНСТРУКЦИЯ.md:15`), хотя install script сам предупреждает, если PATH не содержит destination.
- "ничего не выполняется, пока не проверено" (`ИНСТРУКЦИЯ.md:18-19`), хотя более точная формулировка в `README.ru.md` уже объясняет, что верхний `bash install.sh` пользователь запускает сам, а скачанные artifacts проверяются до запуска (`README.ru.md:61-67`).
- "поведение в рантайме" (`ИНСТРУКЦИЯ.md:34`) — мелкая стилистика, но README.ru уже заменил на более естественное "поведение во время работы" (`README.ru.md:156-158`).

Рекомендация:

Синхронизировать короткую инструкцию с текущим `README.ru.md`, особенно install/security wording.

### 4. `panic status` может завершаться с exit code 1 в ограниченном/headless окружении

Severity: P2 behavior / automation

Команда `panic status` заявлена как read-only preflight. В моей ограниченной среде она напечатала:

```text
panic status — read-only preflight (no changes made)
disk images: none mounted
```

и завершилась с кодом `1`, не дойдя до FileVault/cloud checks.

Вероятная причина: строка `panic/panic:333`:

```bash
local clip_size; clip_size="$(pbpaste 2>/dev/null | wc -c | tr -d ' ')"
```

При `set -euo pipefail`, если `pbpaste` падает из-за недоступного pasteboard/session, весь command substitution может оборвать функцию. Stubbed-тесты проходят (`panic/test/status.bats`), но реальная headless/sandbox среда ловит другой класс отказа.

Рекомендация:

Сделать clipboard-status best-effort:

- если `pbpaste` не доступен или падает, печатать `clipboard: unknown` / `буфер: неизвестно`;
- не возвращать non-zero для read-only status только из-за pasteboard;
- добавить тест со stub `pbpaste`, который возвращает non-zero.

### 5. Dashboard и `securetrash check` могут расходиться по FileVault

Severity: P3 UX clarity

В текущей среде:

- dashboard лаунчера: `FileVault: неизвестно`;
- пункт `Статус` / `securetrash check`: `FileVault ВЫКЛЮЧЕН`.

Связанные места:

- launcher получает `unknown`, если `fdesetup status` не содержит строго `FileVault is On` / `FileVault is Off` (`paranoid:184-193`);
- `securetrash check` трактует `filevault_on == false` как OFF (`securetrash/securetrash:328-331`).

Почему это важно:

Пользователь видит два разных ответа в одном потоке и не понимает, у него FileVault off или статус не удалось определить.

Рекомендация:

Согласовать модель:

- либо `securetrash check` должен различать `off` и `unknown`;
- либо dashboard должен показывать тот же conservative warning, что `securetrash check`;
- лучший вариант: `FileVault: unknown — cannot determine, assume not protected`.

### 6. `verify-releases.sh` слишком мало говорит при сетевом сбое

Severity: P3 diagnostics

В ограниченной сети verifier показывал только:

```text
assets did not download (network?)
```

При обычном сетевом доступе всё прошло 5/5, так что проблема не в релизах.

Рекомендация:

Для user-facing диагностики добавить:

- `curl` exit code;
- последний stderr;
- возможно 1 retry на DNS/429/timeout;
- явное различие между `SHA256SUMS`, `.sig` и binary download failure.

## Что уже хорошо

- Public install из fresh checkout действительно ставит все инструменты из signed releases.
- Release verification проходит 5/5.
- Core smoke path проходит при нормальном доступе к macOS DiskManagement.
- Лаунчер аккуратно показывает missing tools, не притворяется, что они установлены.
- Update-check opt-in и не шумит на актуальных версиях.
- `shellcheck` чистый.
- Bats coverage для launcher хорошая: 49/49.
- GUI macOS source компилируется, build artifact игнорируется git'ом.
- Русский `README.ru.md` уже заметно лучше короткой инструкции: точнее про macOS-only, PowerShell 7, uninstall и signed artifacts.

## Рекомендованный порядок исправлений

1. Обновить `docs/TESTING.md`: убрать локальные пути, версию `0.4.10`, expected `17 ok`, добавить пометку про sandbox/DiskManagement.
2. Синхронизировать `ИНСТРУКЦИЯ.md` с `README.ru.md`.
3. Вынести uninstall из install-блока в `README.md`.
4. Сделать `panic status` устойчивым к падению `pbpaste`.
5. Согласовать FileVault `unknown/off` между `paranoid` и `securetrash`.
6. Улучшить диагностику `verify-releases.sh` при сетевых ошибках.
7. Если Windows 5.1 не поддерживается как пользовательский путь, явно держать всю документацию вокруг `pwsh 7`; если 5.1 всё же важен, решить UTF-8 BOM/encoding story для файлов с русскими строками.

## Команды, которые стоит оставить как smoke для релиза

```bash
bash -n install.sh paranoid smoke-test.sh verify-releases.sh
shellcheck install.sh paranoid smoke-test.sh verify-releases.sh
bats test/paranoid.bats
bats panic/test/status.bats
bash verify-releases.sh
bash smoke-test.sh
```

Для публичного install path отдельно:

```bash
tmp="$(mktemp -d)"
git archive HEAD | tar -x -C "$tmp"
PT_DEST="$(mktemp -d)" PATH=/usr/bin:/bin:/usr/sbin:/sbin bash "$tmp/install.sh"
```

Этот сценарий важен, потому что maintainer checkout с вложенными tool-репо идёт по другому пути: копирует локальные рабочие версии, а не скачивает signed releases.

## Ограничения этой проверки

- Windows runtime не проверялся: `pwsh` / `powershell` отсутствуют в текущем окружении.
- `panic now` не запускался: команда intentionally disruptive.
- Реальный пользовательский vault не уничтожался; vault-cycle проверялся только во временном HOME smoke-test'а.
- GUI app был собран, но не запускался как persistent menu-bar agent.
- Часть сетевых/DiskManagement проверок в Codex sandbox падала; те же операции были повторены с обычными правами и прошли.
