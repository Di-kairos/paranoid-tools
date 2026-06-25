# RELEASE-STATE — Paranoid Tools

> Технический снимок версий/тегов/подписей. Раньше жил в `MANIFEST.md`;
> переименован, т.к. `MANIFEST.md` теперь занят манифестом движения (см. также `MANIFEST.ru.md`).

Снимок состояния пяти инструментов экосистемы на момент последнего обновления.

> **Что это и чем НЕ является.** Это *convenience*-снимок (карта «какой коммит/тег у каждого
> тула сейчас»), а **не** строгий lock-файл и **не** git-submodules. Каждый инструмент живёт
> в отдельном репозитории и версионируется независимо; умбрелла лишь агрегирует их для удобства
> чтения и хендоффа между машинами. Источник истины по конкретному тулу — его собственный репозиторий
> и тег. Рассинхрон этой таблицы с реальными HEAD не ломает сборку/установку ни одного тула —
> он лишь означает, что снимок устарел. Обновлять при закрытии сессии вместе с `HANDOFF.md`.

Обновлено: 2026-06-24 (re-release — ассеты догнаны до исходников, все 5 перевыпущены + подписаны).

| Tool | Repo | Tag (release) | HEAD commit | Version | Статус |
|------|------|---------------|-------------|---------|--------|
| securetrash | `Di-kairos/securetrash` | `v0.4.4` | `9032db4` | 0.4.4 | CI ✅ · Release подписан ✅ |
| vaultwatch  | `Di-kairos/vaultwatch`  | `v0.1.2` | `045b8f5` | 0.1.2 | CI ✅ · Release подписан ✅ |
| panic       | `Di-kairos/panic`       | `v0.1.3` | `00cd814` | **0.1.3** | CI ✅ · Release подписан ✅ · Windows (beta) |
| ghostdraft  | `Di-kairos/ghostdraft`  | `v0.1.2` | `8413bcb` | 0.1.2 | CI ✅ · Release подписан ✅ |
| seedsplit   | `Di-kairos/seedsplit`   | `v0.3.2` | `e37ca7e` | **0.3.2** | CI ✅ · Release подписан ✅ · Windows (beta) |

Все пять инструментов — open source, опубликованы публично (исходники и релизы открыты).

## Release drift — закрыт

Все тулы перевыпущены (re-release 2026-06-24): между прошлым тегом и `main` накопились
install.sh/release.yml hardening (fail-closed) и фичи (`status` у vaultwatch/panic) — теги
не содержали их, хотя README документировал. Догнали: bump версий → CHANGELOG → теги →
релизы собраны и **подписаны** Ed25519-ключом (`SHA256SUMS.sig`, провалидировано end-to-end
через `verify-releases.sh`) → `sha256` в `Formula/*.rb` пере-синкнут под новые tarball'ы.
HEAD каждого тула = тег + `chore(formula)` + `docs`-bump версий в README (всё ПОСЛЕ тега —
это норма, не дрейф: формула и доки пере-синкаются под уже выпущенный релиз). Релизные
артефакты соответствуют коду.

## Release signing

Все 5 тулов подписывают `SHA256SUMS` ключом `releases@paranoid-tools` (Ed25519); pubkey
`ssh-ed25519 …scn2U` опубликован в каждом `SECURITY.md`, вшит в `install.sh` (авто-verify).
Приватный ключ — в GH Secrets (`RELEASE_SIGNING_KEY`) + офлайн-бэкап в securetrash vault.

## Vendoring pin

Все 4 тула (vaultwatch/panic/ghostdraft/seedsplit) вендорят `securetrash/lib/common.sh`
с пина `2e3d2dd` (SHA `fdfb0e3c…af75`), офлайн-проверка через `tools/vendor-common.sh --check`.
