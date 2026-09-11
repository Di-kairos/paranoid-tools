# TESTING — как самому проверить Paranoid Tools

Этот гайд — чтобы ты сам прогнал все 5 инструментов на своём Mac и убедился, что готово.
Все команды запускаются **из корня склонированного репозитория** (`git clone … && cd
paranoid-tools`). macOS.

---

## 0. Поставить все 5

Ставит securetrash, vaultwatch, panic, ghostdraft, seedsplit в `~/.local/bin`:

```bash
bash install.sh
```

> **Один путь по умолчанию — подписанный.** Установщик всегда тянет каждый инструмент из его
> **подписанного релиза**, даже если рядом в монорепозитории лежат рабочие копии `securetrash/`,
> `vaultwatch/` и т.д. Локальные копии ставятся только по явному `PT_DEV=1`, и этот режим кричит
> о себе баннером: подписи в нём не проверяются. То есть проверять публичный путь на рабочем
> клоне ничего не мешает — достаточно не выставлять `PT_DEV`.

Если `~/.local/bin` не в `PATH`, добавь (zsh):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Проверь: `securetrash version` печатает версию и она совпадает с последним тегом репозитория.
Удалить всё потом: `bash install.sh --uninstall`.

---

## 1. Автоматический smoke (безопасно, ничего твоего не трогает)

Прогоняет happy-path всех тулов в песочнице (временный HOME, temp-файлы), печатает ✓/✗:

```bash
bash smoke-test.sh
```

Ожидаемо: `Все автоматические проверки прошли.` (**16 ✓ / 0 ✗ / 2 пропущено**). Это покрывает
версии, seedsplit split/combine/verify, ghostdraft pipe+draft, securetrash shred и полный
vault-цикл; пропускаются `ghostdraft new` (нужен интерактивный редактор) и disruptive-части
`vaultwatch`/`panic`.

> **Sandbox / headless.** Vault-цикл требует macOS DiskManagement (`hdiutil`/`diskutil apfs`).
> В ограниченной среде (Codex sandbox, headless-CI) он может упасть с `unable to use the
> DiskManagement framework` — это не баг продукта, а среда. Запусти с обычными правами на
> реальном Mac — vault-цикл пройдёт.

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

Релизы подписаны Ed25519-ключом `releases@paranoid-tools`. Репозитории публичны — ассеты
тянутся обычным `curl`, без `gh` и без токена («don't trust, verify» доступно любому). Одна команда:

```bash
bash verify-releases.sh
```

Ожидаемо: `Итог: 5 ✓  0 ✗` → `Все релизы подписаны корректно, и все файлы соответствуют манифесту.`
Проверяются все четыре подписанных файла каждого релиза (инструмент, его `.ps1`-двойник и оба
установщика); всё, что не скачалось, считается провалом, а не успехом.

---

## Что НЕ тестируется тут (известные пределы)

- **Windows-порты** — beta: логика покрыта Pester на CI под pwsh 7 и Windows PowerShell 5.1,
  а живой путь (установка, лаунчер, трей, BitLocker-сейф от `create` до `destroy`, хоткей
  паники) пройден руками на одной машине с Windows 11 Pro (s45–s48). Другие редакции, диски и
  VeraCrypt-fallback не прогонялись — нужна другая Windows-машина (за тобой/тестером).
- **Публичный install** (клон + `bash install.sh`, `brew install securetrash`) — рабочий путь
  для внешних пользователей; ссылки на per-tool installers — в каждом README. Установки вида
  `curl … | bash` мы не предлагаем: конвейер запускает установщик раньше, чем его можно прочитать.
- **macOS-only** для 4 ядер — by design.
