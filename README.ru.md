# Paranoid Tools

[English](README.md) · **Русский**

Честные privacy/security-утилиты для macOS — каждая делает одну вещь, без снейкойла.

Зонтик небольших CLI-инструментов вокруг **жизненного цикла секрета**
(seed-фраза / пароль / ключ). Каждый инструмент — отдельный git-репо, single-file
на чистом Bash с **нулём зависимостей**, и честен о пределах своих гарантий.

## Состав

| # | Инструмент | Шаг жизни секрета | Статус |
|---|------------|-------------------|--------|
| 1 | [`securetrash`](https://github.com/Di-kairos/securetrash) | хранить (vault) + уничтожить | v0.4.0 |
| 2 | [`vaultwatch`](https://github.com/Di-kairos/vaultwatch)   | защитить, пока vault открыт | v0.1.0 |
| 3 | [`panic`](https://github.com/Di-kairos/panic)             | мгновенно спрятать по тревоге | v0.1.0 |
| 4 | [`ghostdraft`](https://github.com/Di-kairos/ghostdraft)   | написать/просмотреть без следов | v0.1.0 |
| 5 | [`seedsplit`](https://github.com/Di-kairos/seedsplit)     | распределить секрет на доли (Шамир) | v0.2.0 |

У каждого тула — английский `README.md` (русский в `README.ru.md`), `CHANGELOG.md`,
checksum-verified `install.sh`, CI + release-workflow и обязательная секция
**Scope & limitations** — прочитай её, прежде чем доверять инструменту.

## Установка

Каждый тул ставится независимо verify-then-run скриптом из релиза (см. README тула).
Для личного использования всех пяти сразу — локальный установщик в корне репо:

```bash
git clone https://github.com/Di-kairos/paranoid-tools
cd paranoid-tools
bash install.sh            # ставит все 5 в ~/.local/bin
bash install.sh --uninstall
```

Практический гайд по-русски: [КАК-ПОЛЬЗОВАТЬСЯ.ru.md](КАК-ПОЛЬЗОВАТЬСЯ.ru.md).

## Архитектура

- **Раздельные репо + вендоринг.** Общий код = канонический `securetrash/lib/common.sh`,
  вендорится в каждый tool inline между маркерами `# === BEGIN vendored common (pin: <ref>) ===`.
  Синк-скрипт + CI-чек дрейфа. Без runtime-зависимостей, без build-склейки.
- **Vault-хуки.** `securetrash vault open/close` дёргают `~/.securetrash/hooks/{post-open,post-close}` —
  через них vaultwatch/panic цепляются к жизненному циклу контейнера.
- **Закон экосистемы:** один инструмент = одна задача; честно про пределы
  (`Scope & limitations` в README обязательна); не создавать ложного чувства безопасности.

## Граф навигации

Каждый репо держит свой граф (`<tool>/graphify-out/graph.json`). Cross-repo граф
собирается мерджем:

```bash
bin/rebuild-graph.sh          # мерджит графы всех тулов → graphify-out/merged-graph.json
graphify path "A" "B" --graph graphify-out/merged-graph.json
```

## Лицензия

[MIT](LICENSE). У каждого тул-репо своя MIT `LICENSE`, плюс `SECURITY.md`
(как приватно сообщить об уязвимости) и `CONTRIBUTING.md`.
