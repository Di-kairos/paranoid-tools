# HANDOFF — paranoid-tools

Точка передачи между машинами. При «Продолжаем работу» читать первым: умбрелла-папка,
root-PROGRESS.md нет, состояние — по репо. Всё закоммичено и **запушено** (рабочие деревья
чистые); на другой машине поднимается с GitHub + X10.

## Снимок (2026-06-21, конец сессии 3 — аудит-driven polish, В ПРОЦЕССЕ)

| Репо | HEAD | VERSION | Latest tag/Release | bats | CI |
|------|------|---------|--------------------|------|-----|
| umbrella | `<this commit>` | — | — | — | — |
| securetrash | `4d4b147` | 0.4.0 | v0.4.0 | 59/59 | ✅ |
| vaultwatch | `0145699` | 0.1.0 | v0.1.0 | 50/50 | ✅ |
| panic | `6673d65` | 0.1.0 | v0.1.0 | 24/24 | ✅ |
| ghostdraft | `e5c5d5e` | 0.1.0 | v0.1.0 | 26/26 | ✅ |
| seedsplit | `4ee148f` | **0.3.0** | v0.2.0 ⚠ | 37/37 | ✅ |

Все 5 репо **PRIVATE**. CI зелёный у всех. Всего bats 196/196.
Снимок tool/repo/tag/commit/status — в `MANIFEST.md` (convenience, не lock-файл).

⚠ **Release drift (ожидаемый, чинится в release-блоке В КОНЦЕ):** у ВСЕХ тулов HEAD
впереди последнего тега (post-tag правки: флаги, legal, EN-README, vendor-fix; seedsplit —
ещё и крипта 0.3.0). Релизные артефакты пока НЕ равны коду. Это пункт №1 плана — закрывается
в самом конце (bump версий + ретег + пере-нарезка релизов).

## Контекст: работаем по 2 аудитам (оба прочитаны, план согласован)

Mr. Di заказал 2 внешних аудита (release-гигиена + крипто/безопасность). План разбит на
Блок 1 (точно делаем) / Блок 2 (Windows+подпись) / Блок 3 (сознательно НЕ делаем: SLIP-39,
passphrase-слой, decoy-vault, новые тулы — в roadmap). Locked-рефайнменты второго ревьюера
учтены (random set-id, формат SSS2, и т.д.).

## Сделано в сессии 3

1. **seedsplit крипто v0.3.0** (отревьюено Mr. Di перед коммитом): формат `SSS1→SSS2`;
   **random set-id** (4-байт nonce, НЕ H(secret) — нет confirmation-оракула); integrity-tag
   **2→16 байт** (128 бит); **`verify`** (проверка без печати секрета); таксономия ошибок
   (повреждение/разные сплиты/ниже порога/разный T/целостность); фикс declared-T;
   `_recover_secret_hex` через `return` (не exit). KAT: GF FIPS-197 + замороженный набор.
2. **vendor-check → ОФЛАЙН** во всех 4 тулах: хеш вшитого блока vs запиннутый COMMON_SHA256,
   без сети (раньше fetch из raw.githubusercontent падал 404 после ухода securetrash в
   private → красный CI у всех; теперь робастно).
3. seedsplit **README en+ru + CHANGELOG** под v0.3.0.
4. Попутно: KAT-тест чинён под bash 5 (strict-режим sourced-скрипта).

## Два вопроса к Mr. Di — ОТВЕЧЕНЫ (сессия 4)

1. **i18n seedsplit** → «да, делаю сейчас». ✅ Сделано (commit `4ee148f`).
2. **Signing-ключ** → «генерить сейчас». ⏳ Запланировано в Блоке 2 (порядок: после Windows
   fail-closed). Выделенный `paranoid-tools-release-signing` ed25519, pubkey в README/SECURITY,
   приватный ключ держит Mr. Di (в securetrash vault); `ssh-keygen -Y sign` + `allowed_signers`
   + шаг verify в install.sh.

## Остаток плана (порядок исполнения)

**Блок 1 — ЗАВЕРШЁН (сессия 4):**
- [x] i18n seedsplit + перевод ассертов тестов на английский (`4ee148f`, 37/37).
- [x] wording-честность: ghostdraft Formula desc (`69f00ee`); securetrash windows/README (`f9fbdb9`).
- [x] ghostdraft RAM-mountpoint → уникальное имя (urandom-суффикс) + mountpoint из diskutil,
  detach по dev-node, +тест (`e5c5d5e`, 26/26).
- [x] securetrash `docs/index.html`: install one-liners → release-download (verify) (`4d4b147`).
- [x] umbrella `MANIFEST.md` (convenience-снимок, не lock-файл) + заметка здесь.

**Блок 2:**
- [ ] Windows fail-closed: `securetrash/windows/securetrash.ps1` `vault destroy` дисмаунтит
  и всё равно удаляет (~стр.683) → сделать fail-closed как macOS; добавить protected-path
  guard для `shred`; tri-state disk detection. + Pester-тесты. Пометить «Pester green,
  hardware smoke pending» (реально на Windows прогонит Mr. Di). Правка fail-closed безопасна
  даже без прогона (деградирует в «отказался», не в «разрушил»).
- [ ] Подпись релизов (см. вопрос 2).

**В САМОМ КОНЦЕ — release-блок (иначе drift вернётся):**
- [ ] bump версий: securetrash 0.4.1, vaultwatch/panic/ghostdraft 0.1.1, seedsplit уже 0.3.0.
- [ ] CHANGELOG [Unreleased]→версия у каждого; тег `vX.Y.Z` → `release.yml` нарежет релиз.
- [ ] **ПЕРЕ-СИНК `sha256` в каждой `Formula/<tool>.rb`** против НОВОГО release-tarball
  (иначе `brew install` отвалится checksum mismatch). Метод проверки sha (private repo):
  `curl -sL -H "Authorization: token $(gh auth token)" https://github.com/Di-kairos/<t>/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256`.
- [ ] Обновить umbrella `MANIFEST` под новые теги/SHA.

## Прочее
- Память проекта на X10: `.claude/memory/` (publication-gate, monetization-open). Симлинк
  настроен. **Монетизация:** решено open-core + донат; куда донатить — TBD (этап 2).
- graphify в umbrella НЕ инициализирован (нет `graphify-out/graph.json`) — при желании
  первичный `/graphify`.
- Все 5 репо private; делать public ТОЛЬКО по явному согласию Mr. Di (этап 2 = маркетинг).

## Vendoring pin
Все 4 тула вендорят `securetrash/lib/common.sh` pin `2e3d2dd` (SHA `fdfb0e3c…af75`).
`tools/vendor-common.sh --check` — теперь офлайн, sync во всех 4 ✓.
