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

Обновлено: 2026-07-09 (сессия 24 — securetrash v0.4.13: Windows BitLocker tri-state в `check`
+ реанимация windows-ci; tap-формула добита с v0.4.7 до v0.4.13. Ранее s20 — РЕЛИЗ-КАТ всей
экосистемы: весь аудит `AUDIT_2026-07-03.md` закрыт/смягчён и ОТГРУЖЕН, P1-2 Ed25519
sig-verify во всех 5 Windows-инсталляторах).

| Tool | Repo | Tag (release) | Version | Статус |
|------|------|---------------|---------|--------|
| securetrash | `Di-kairos/securetrash` | `v0.4.13` | **0.4.13** | CI ✅ · Release подписан ✅ · Windows sig-verify · FileVault/BitLocker unknown/off |
| vaultwatch  | `Di-kairos/vaultwatch`  | `v0.1.6` | **0.1.6** | CI ✅ · Release подписан ✅ · `--force` safety-gate · Win unmount-guard · sig-verify |
| panic       | `Di-kairos/panic`       | `v0.1.8` | **0.1.8** | CI ✅ · Release подписан ✅ · Windows sig-verify · headless-safe status |
| ghostdraft  | `Di-kairos/ghostdraft`  | `v0.1.9` | **0.1.9** | CI ✅ · Release подписан ✅ · Windows sig-verify · non-TTY guard · Warp hint |
| seedsplit   | `Di-kairos/seedsplit`   | `v0.4.1` | **0.4.1** | CI ✅ · Release подписан ✅ · passphrase no-spill · split self-check · sig-verify |

> Формулы Homebrew обновлены на новые теги + sha256 (source-тарбол). `verify-releases.sh` пиннут
> на эти теги. HEAD-колонка убрана — дрейфует; смотри `git -C <tool> describe --tags`.

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
