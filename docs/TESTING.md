# TESTING — как самому проверить Paranoid Tools (приватно, до публикации)

Всё остаётся в private. Этот гайд — чтобы ты сам прогнал все 5 инструментов на своём Mac
и убедился, что готово. Команды копируются целиком. macOS.

---

## 0. Поставить все 5 локально (из этого репозитория)

Ставит securetrash, vaultwatch, panic, ghostdraft, seedsplit в `~/.local/bin`
(локально, из рабочей копии — НЕ из GitHub, ничего не публикует):

```bash
cd "/Volumes/X10 Pro/projects/paranoid-tools" && bash install.sh
```

Если `~/.local/bin` не в `PATH`, добавь (zsh):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Проверь: `securetrash version` → `securetrash 0.4.4`.
Удалить всё потом: `bash install.sh --uninstall`.

---

## 1. Автоматический smoke (безопасно, ничего твоего не трогает)

Прогоняет happy-path всех тулов в песочнице (временный HOME, temp-файлы), печатает ✓/✗:

```bash
cd "/Volumes/X10 Pro/projects/paranoid-tools" && bash smoke-test.sh
```

Ожидаемо: `Все автоматические проверки прошли.` (17 ✓). Это покрывает версии, seedsplit
split/combine/verify, ghostdraft pipe+draft, securetrash shred и полный vault-цикл.

---

## 2. Ручная проверка интерактивных частей

Автотест не покрывает то, что требует твоих рук или реально меняет систему. Прогони сам:

### securetrash — реальный vault (твои данные)

```bash
securetrash check                      # честный отчёт: диск, FileVault, доступность vault
securetrash vault create 100m          # создаст ~/SecureVault.sparsebundle (спросит пароль)
securetrash vault open                 # смонтирует в /Volumes/SecretVault (введи пароль)
#  → положи туда файл через Finder, поработай
securetrash vault close                # размонтирует (данные снова зашифрованы)
securetrash vault destroy              # УНИЧТОЖИТ контейнер (спросит yes) — только если не нужен
```

### ghostdraft — эфемерный черновик в RAM (нужен твой $EDITOR)

```bash
export EDITOR=nano                     # или vim/code -w
ghostdraft new                         # откроет редактор на черновике в RAM-диске;
                                       #  по выходу — затрёт и размонтирует, следов на SSD нет
pbpaste | ghostdraft pipe              # показать буфер обмена, НИЧЕГО не записав на диск
```

### vaultwatch — сторож открытого vault (интеграция с securetrash)

```bash
vaultwatch install-hooks               # подключит к securetrash vault open/close
securetrash vault open                 # vaultwatch стартует сам, сузит Spotlight/Time Machine
vaultwatch status                      # что сейчас исключено/под наблюдением
securetrash vault close                # vaultwatch гаснет, восстанавливает исключения
vaultwatch uninstall-hooks             # отключить интеграцию
```

### panic — быстро спрятать тома ⚠️ DISRUPTIVE

`panic` размонтирует/спрячет открытые тома (в т.ч. твой vault) — для экстренной ситуации.
Сначала безопасно осмотрись, «выстреливай» только осознанно:

```bash
panic --help                           # что умеет
panic status                           # что будет затронуто (read-only, безопасно)
#  panic now                           # ⚠️ реально спрячет тома — запускай, понимая последствия
```

---

## 3. Проверить подписанные релизы (аутентичность)

Релизы подписаны Ed25519-ключом `releases@paranoid-tools`. Репо приватные, поэтому ассеты
тянутся через `gh` (с твоим токеном). Одна команда:

```bash
cd "/Volumes/X10 Pro/projects/paranoid-tools" && bash verify-releases.sh
```

Ожидаемо: `Итог: 5 ✓  0 ✗` → `Все релизы подписаны корректно.`

> Не вставляй длинные `gh release download …` вручную в поле ввода — оно переносит строки и
> рвёт команду (`-p` теряет аргумент). Всегда запускай скрипт-файл.

---

## Что НЕ тестируется тут (известные пределы)

- **Windows-порт securetrash** — beta, логика покрыта Pester на CI, но на реальном BitLocker-
  железе не прогонялась. Нужна Windows-машина (за тобой/тестером).
- **Публичный install** (`curl … | bash`, `brew install`) — заработает только после выхода
  репозиториев в public (этап 2). Сейчас приватно → ставь локально (раздел 0) или через `gh`.
- **macOS-only** для 4 ядер — by design.
