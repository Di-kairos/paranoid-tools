# HANDOFF — paranoid-tools

Точка передачи между машинами. При «Продолжаем работу» читать первым: умбрелла-папка,
root-PROGRESS.md нет, состояние — по репо. Всё закоммичено и **запушено** (рабочие деревья
чистые); на другой машине поднимается с GitHub + X10.

## Снимок (2026-06-23, сессия 5 — аудит-3 ЗАКРЫТ: все 5×P1 + 2×P2 + 1×P3)

| Репо | HEAD | VERSION | Latest tag/Release | bats | CI |
|------|------|---------|--------------------|------|-----|
| umbrella | `29cf9b2` | — | — | — | — |
| securetrash | `2f40015` | 0.4.2 | v0.4.2 ✅подписан | 61/61 | ✅ |
| vaultwatch | `ea35706` | 0.1.1 | v0.1.1 ✅подписан | 56/56 | ✅ |
| panic | `e1771de` | 0.1.1 | v0.1.1 ✅подписан | 33/33 | ✅ |
| ghostdraft | `1868c7e` | 0.1.1 | v0.1.1 ✅подписан | 26/26 | ✅ |
| seedsplit | `c1c964f` | **0.3.0** | v0.3.0 ✅подписан | 37/37 | ✅ |

Все 5 репо **PRIVATE**. CI зелёный у всех. Всего bats 213/213.
Снимок tool/repo/tag/commit/status — в `RELEASE-STATE.md` (convenience, не lock-файл;
бывш. `MANIFEST.md`, переименован — теперь `MANIFEST.md` = манифест движения).

✅ **Release drift ЗАКРЫТ:** все тулы перевыпущены — bump версий → CHANGELOG → теги →
релизы собраны и **подписаны** Ed25519 (`SHA256SUMS.sig`, подпись провалидирована
end-to-end) → `sha256` в формулах пере-синкнут под новые tarball'ы. HEAD = тег + один
`chore(formula)`-коммит (формула коммитится после тега — норма). Артефакты = коду.

## Сессия 5 — итог + фокус сессии 6

**Сессия 5 закрыта.** Аудит #3 (AUDIT_FINDINGS.md) — 5×P1 + 2×P2 + 1×P3 — ЗАКРЫТ полностью.

Закрытые находки:
- P1 securetrash: shred mount-root guard + v0.4.2 (pubkey в release assets).
- P1 vaultwatch: close/TTL postconditions (detach verify + mdutil fail keeps state).
- P2 panic: `status` команда (read-only preflight, 9 тестов).
- P2 vaultwatch: `status` команда (active-session view, 3 теста).
- P3: README securetrash v0.4.0→v0.4.2; ShellCheck SC2015 в smoke-test.sh/verify-releases.sh.

**Фокус сессии 6 (по приоритету):**
1. **Ручной интерактив-QA** (Mr. Di, по `TESTING.md` §2): реальный `securetrash vault`
   (лучше в обычном Терминале — интерактивный ввод пароля), `ghostdraft new` с `$EDITOR`,
   `vaultwatch` хуки, `panic` (disruptive — сперва `panic status`).
2. **Шаг 4** (Mr. Di): бэкап `~/paranoid-release-key` в vault + `securetrash shred` с диска.
3. **BitLocker hardware-smoke** — нужна Windows-машина (Mr. Di/тестер). Не блокер.
4. **Этап 2 (go public)** — ТОЛЬКО по явному «да» Mr. Di: репо → public, sync Homebrew-tap
   `Di-kairos/homebrew-tap` новыми формулами (сейчас устарел: указывает на старые теги, и в нём
   только `securetrash.rb` — нужны все 5), public install-smoke (`curl|bash`, `brew install`).
5. **Блок 3 (roadmap)** — SLIP-39, passphrase-слой, decoy-vault, новые тулы. Сознательно отложено.

⚠ Известный нюанс окружения: длинные/многострочные команды РВУТСЯ в поле ввода Claude Code
(перенос строки отрывает флаг от аргумента — словил 3×: секрет, verify). Всё многострочное —
только в скрипт-файлы (`smoke-test.sh`, `verify-releases.sh`), запуск короткой командой.

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
- [x] Windows fail-closed `vault destroy` (tri-state + postcondition, `f2cd68c`),
  protected-path guard для `shred` (`0df6fd1`), tri-state disk detection ssd/hdd/unknown
  (`015d358`). Pester зелёный на windows-latest (CI). **Hardware smoke pending** —
  реальный BitLocker-прогон на Windows за Mr. Di (правки безопасны: деградируют в «отказ»).
- [x] **Подпись релизов — ВШИТА во все 5 тулов** (non-breaking, CI зелёный у всех):
  securetrash `32d3c6b`, vaultwatch `f1913e3`, panic `4532c91`, ghostdraft `5b223a5`,
  seedsplit `739e9cb`. У каждого: release.yml подписывает SHA256SUMS секретом
  `RELEASE_SIGNING_KEY` (скип, если секрета нет → релиз остаётся checksum-verified);
  install.sh авто-verify `.sig` против вшитого pubkey (мягкая деградация); SECURITY.md —
  секция + опубликованный pubkey. Ключ выдан: `releases@paranoid-tools`, pubkey
  `ssh-ed25519 AAAA…scn2U`. **GH-секрет `RELEASE_SIGNING_KEY` залит во все 5 репо** (сессия 4)
  → релизы v0.4.1/v0.1.1/v0.3.0 подписаны, подпись провалидирована end-to-end. Signing LIVE.

### ⚠ Осталось Mr. Di — ТОЛЬКО шаг 4 (бэкап ключа; шаг 3 секрет УЖЕ залит)

```bash
# 4) Офлайн-бэкап приватного ключа в vault, затем стереть с диска (pub оставить — публичный):
securetrash vault open
cp ~/paranoid-release-key "/Volumes/SecretVault/paranoid-release-key"
securetrash vault close
securetrash shred ~/paranoid-release-key
```

**Release-блок — ЗАКРЫТ (сессия 4):**
- [x] bump версий: securetrash 0.4.1, vaultwatch/panic/ghostdraft 0.1.1, seedsplit 0.3.0.
- [x] CHANGELOG [Unreleased]→версия у каждого; теги запушены → `release.yml` собрал+подписал релизы.
- [x] пере-синк `sha256` в `Formula/*.rb` против новых tarball'ов (5 коммитов `chore(formula)`).
- [x] umbrella `MANIFEST` обновлён под новые теги/SHA + секция signing.

**Тест-харнес для self-QA (сессия 4, всё приватно):**
- `smoke-test.sh` — безопасный автотест всех 5 в песочнице (17 ✓ на macOS); запуск
  `bash smoke-test.sh`. Покрывает версии, seedsplit roundtrip, ghostdraft pipe+draft,
  securetrash shred + полный vault-цикл (vault-блок скипается, если `/Volumes/SecretVault` занят).
- `TESTING.md` — гайд Mr. Di: локальная установка (`install.sh` ставит все 5 в `~/.local/bin`,
  проверено 5/5), автотест, ручной тест интерактива (реальный vault, ghostdraft-редактор,
  vaultwatch-хуки, panic) + проверка подписи релизов через `gh` (auth, т.к. private).

## Прочее
- Память проекта на X10: `.claude/memory/` (publication-gate, monetization-open). Симлинк
  настроен. **Монетизация:** решено open-core + донат; куда донатить — TBD (этап 2).
- graphify в umbrella НЕ инициализирован (нет `graphify-out/graph.json`) — при желании
  первичный `/graphify`.
- Все 5 репо private; делать public ТОЛЬКО по явному согласию Mr. Di (этап 2 = маркетинг).

## Vendoring pin
Все 4 тула вендорят `securetrash/lib/common.sh` pin `2e3d2dd` (SHA `fdfb0e3c…af75`).
`tools/vendor-common.sh --check` — теперь офлайн, sync во всех 4 ✓.
