# MANIFEST — Paranoid Tools

Снимок состояния пяти инструментов экосистемы на момент последнего обновления.

> **Что это и чем НЕ является.** Это *convenience*-снимок (карта «какой коммит/тег у каждого
> тула сейчас»), а **не** строгий lock-файл и **не** git-submodules. Каждый инструмент живёт
> в отдельном репозитории и версионируется независимо; умбрелла лишь агрегирует их для удобства
> чтения и хендоффа между машинами. Источник истины по конкретному тулу — его собственный репозиторий
> и тег. Рассинхрон этой таблицы с реальными HEAD не ломает сборку/установку ни одного тула —
> он лишь означает, что снимок устарел. Обновлять при закрытии сессии вместе с `HANDOFF.md`.

Обновлено: 2026-06-22 (release-блок закрыт — все тулы перевыпущены + подписаны).

| Tool | Repo | Tag (release) | HEAD commit | Version | Статус |
|------|------|---------------|-------------|---------|--------|
| securetrash | `Di-kairos/securetrash` | `v0.4.1` | `81459ed` | 0.4.1 | CI ✅ · Release подписан ✅ (asset pubkey-gap, фикс в v0.4.2) |
| vaultwatch  | `Di-kairos/vaultwatch`  | `v0.1.1` | `867f4de` | 0.1.1 | CI ✅ · Release подписан ✅ |
| panic       | `Di-kairos/panic`       | `v0.1.1` | `c555af8` | 0.1.1 | CI ✅ · Release подписан ✅ |
| ghostdraft  | `Di-kairos/ghostdraft`  | `v0.1.1` | `1868c7e` | 0.1.1 | CI ✅ · Release подписан ✅ |
| seedsplit   | `Di-kairos/seedsplit`   | `v0.3.0` | `c1c964f` | **0.3.0** | CI ✅ · Release подписан ✅ |

Все пять репозиториев **private**. Делать public — только по явному согласию (этап 2 = маркетинг).

## Release drift — закрыт

Все тулы перевыпущены (2026-06-22): bump версий → CHANGELOG → теги → релизы собраны и
**подписаны** Ed25519-ключом (`SHA256SUMS.sig`, подпись провалидирована end-to-end) →
`sha256` в `Formula/*.rb` пере-синкнут под новые tarball'ы. HEAD каждого тула = тег + один
`chore(formula)`-коммит (формула всегда коммитится ПОСЛЕ тега — это норма, не дрейф).
Релизные артефакты соответствуют коду.

## Release signing

Все 5 тулов подписывают `SHA256SUMS` ключом `releases@paranoid-tools` (Ed25519); pubkey
`ssh-ed25519 …scn2U` опубликован в каждом `SECURITY.md`, вшит в `install.sh` (авто-verify).
Приватный ключ — в GH Secrets (`RELEASE_SIGNING_KEY`) + офлайн-бэкап в securetrash vault.

## Vendoring pin

Все 4 тула (vaultwatch/panic/ghostdraft/seedsplit) вендорят `securetrash/lib/common.sh`
с пина `2e3d2dd` (SHA `fdfb0e3c…af75`), офлайн-проверка через `tools/vendor-common.sh --check`.
