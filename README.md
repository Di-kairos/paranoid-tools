# Paranoid Tools

Зонтичная папка экосистемы честных privacy/security-утилит вокруг жизненного цикла
секрета (seed/пароль/ключ). Каждый инструмент — **отдельный git-репо**, single-file,
чистый Bash, ноль зависимостей. Папка — организационный слой на X10 (порядок + общий граф).

North-star и спеки: `securetrash/ECOSYSTEM.md`.

## Состав

| # | Инструмент | Шаг жизни секрета | Статус | Репо |
|---|------------|-------------------|--------|------|
| 1 | `securetrash` | хранить (vault) + уничтожить | ✅ v0.4.0 released | Di-kairos/securetrash |
| 2 | `vaultwatch`  | защитить, пока vault открыт | ✅ v0.1.0 released | Di-kairos/vaultwatch |
| 3 | `panic`       | мгновенно спрятать по тревоге | спека | — |
| 4 | `ghostdraft`  | написать/просмотреть без следов | спека | — |
| 5 | `seedsplit`   | распределить (Shamir/SLIP-39) | идея (опц.) | — |

## Архитектура

- **Раздельные репо + вендоринг.** Общий код = канонический `securetrash/lib/common.sh`,
  вендорится в каждый tool inline между маркерами `# === BEGIN vendored common (pin: <ref>) ===`.
  Синк-скрипт + CI-чек дрейфа. Без runtime-зависимостей, без build-склейки.
- **Vault-хуки.** `securetrash vault open/close` дёргают `~/.securetrash/hooks/{post-open,post-close}` —
  через них vaultwatch/panic цепляются к жизненному циклу контейнера (см. `securetrash/CLAUDE.md`).
- **Закон экосистемы:** один инструмент = одна задача; честно про пределы (`Scope & limitations`
  в README обязательна); не создавать ложного чувства безопасности.

## Граф навигации (связи между частями)

Каждый репо держит свой граф (`<tool>/graphify-out/graph.json`, refresh: `graphify update <tool>`).
Cross-repo граф экосистемы собирается мерджем:

```bash
bin/rebuild-graph.sh          # мерджит графы всех тулов → graphify-out/merged-graph.json
graphify path "A" "B" --graph graphify-out/merged-graph.json
graphify explain "X" --graph graphify-out/merged-graph.json
```

Merged-граф оживает со 2-го инструмента (для merge нужно ≥2 графа).
