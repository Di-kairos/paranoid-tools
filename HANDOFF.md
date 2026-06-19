# HANDOFF — paranoid-tools

Точка передачи между машинами (work Mac Mini → home Air). При «Продолжаем работу»
читать этот файл первым: умбрелла-папка, root-PROGRESS.md нет, состояние — по репо.

## Снимок на закрытие сессии (2026-06-19, сессия 2)

| Репо | HEAD (локально) | Тег | Тесты | Состояние |
|------|------|-----|-------|-----------|
| `paranoid-tools` (umbrella) | `e283ec5` | — | — | pushed ✓ |
| `securetrash` | `bf4ceee` | v0.4.0 | bats | released; CHANGELOG добавлен, pushed ✓ |
| `vaultwatch` | — | v0.1.0 | — | released |
| `panic` | — | v0.1.0 | — | released |
| `ghostdraft` | `cd9937e` | v0.1.0 | bats 21/21 | released, pushed ✓ |
| `seedsplit` | `615b43f`+install | — (ядро v0.2.0) | bats 27/27 | **ядро готово, НЕ запушен** ⚠ |

Экосистема: **5/5 функциональны** (seedsplit получил рабочее ядро в этой сессии).

## Что сделано в этой сессии (сессия 2)

1. **Умбрелла-установщик `install.sh`** — ставит все 5 тулов из рабочей копии X10 в
   `~/.local/bin` одной командой (для личного использования; per-tool install.sh —
   для публичных релизов). `--uninstall` поддержан.
2. **`КАК-ПОЛЬЗОВАТЬСЯ.ru.md`** — практический русский гайд: по каждому тулу что/когда/пример.
3. **seedsplit pack 2 — ядро Shamir над GF(256)** (главное): `split`/`combine` на чистом
   Bash, без зависимостей. log/antilog таблицы (g=3, поли 0x11b), Горнер для split,
   Лагранж-в-нуле для combine (веса считаются один раз). Формат доли `SSS1-T-x-Y-chk`
   (chk ловит опечатку доли), обёртка секрета `0x55|len|secret|crc` (combine либо вернёт
   точный секрет, либо честный отказ при порче/чужом наборе). Ввод секрета stdin/--file.
   27/27 bats, shellcheck clean, VERSION 0.2.0. Боевой smoke: 12-словная seed 3-of-5 ✓.
4. **seedsplit `install.sh`** — release-installer для паритета (не было).
5. **securetrash `CHANGELOG.md`** — реконструирован из тегов v0.1.0..v0.4.0 (паритет-гэп).

## ⚠ ГЛАВНОЕ незакрытое — seedsplit push (всё ещё)

Локальные коммиты seedsplit (`b3e14b0` scaffold, `615b43f` ядро, +install.sh) **не
запушены**. Remote `Di-kairos/seedsplit` (private) пустой. Причина прежняя: коммит
`b3e14b0` содержит `.github/workflows/ci.yml`, а токен на машинах без `workflow`-scope
(`gist, read:org, repo`). GitHub отклоняет push любого коммита, добавляющего workflow,
без этого scope.

X10 несёт локальный `.git` → все коммиты восстановимы на другой машине.

### Как доделать (самый чистый путь)

`gh auth refresh -s workflow` **в НАСТОЯЩЕМ терминале**, не через префикс `!` в Claude
(device-flow требует интерактивной вставки кода — в `!`-контексте не завершается):

```bash
gh auth refresh -s workflow     # открыть URL, вставить код, разрешить scope
gh auth status                  # убедиться: в scopes появился 'workflow'
cd "/Volumes/X10 Pro/projects/paranoid-tools/seedsplit"
git push -u origin main         # зальёт scaffold + ядро + ci.yml; CI должен стать green
gh run list --repo Di-kairos/seedsplit --limit 1   # проверить CI
```

Fallback (если refresh нежелателен): убрать ci.yml из истории (rewrite `b3e14b0`),
push без workflow, вернуть ci.yml отдельным коммитом позже. Рискованнее — refresh проще.

После push: тегнуть seedsplit `v0.2.0` + сделать Release (release.yml уже есть в репо).

## Следующие паки (бэклог)

- **seedsplit:** тег v0.2.0 + Release; опционально SLIP-39-совместимость (отдельный объём).
- **ECOSYSTEM §7:** единый `check`-движок, единый бренд вывода для всех тулов.
- **graphify (§15):** инициализировать `graphify-out` у ghostdraft/panic/seedsplit →
  богаче merged cross-repo граф.
- Мелочь: `--version`/`--help` алиасы к `version`/usage (сейчас работает `version`-сабкоманда).

## Vendoring pin (общий)

Все тулы вендорят `securetrash/lib/common.sh` pin `2e3d2dd` (SHA256 `fdfb0e3c…af75`).
`tools/vendor-common.sh --check` ловит дрейф в CI. seedsplit-ядро проверено — sync ✓.
