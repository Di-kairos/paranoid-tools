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
| `seedsplit` | `cd49632` | — (ядро v0.2.0) | bats 27/27 | ядро готово, **pushed ✓** (без ci.yml) |

Экосистема: **5/5 функциональны и на GitHub** (seedsplit получил рабочее ядро + залит в этой сессии).

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

## seedsplit push — РЕШЕНО (ci.yml отложен)

seedsplit залит в `Di-kairos/seedsplit` (main = `cd49632`). Историю пересобрали единым
чистым коммитом БЕЗ `.github/workflows/ci.yml` (ветка-сирота → push в main), т.к. токен
без `workflow`-scope (`gist, read:org, repo`) и GitHub отклонял любой коммит, добавляющий
workflow. `ci.yml` лежит локально (untracked, `seedsplit/.github/workflows/ci.yml`) —
сохранён, на код не влияет.

### Остаток по seedsplit (когда будет workflow-scope)
`gh auth refresh -s workflow` **в НАСТОЯЩЕМ терминале** (device-flow в `!`-контексте Claude
не завершается), затем добавить CI отдельным коммитом:
```bash
cd "/Volumes/X10 Pro/projects/paranoid-tools/seedsplit"
git add .github/workflows/ci.yml && git commit -m "ci: add workflow"
git push origin main             # уедет ci.yml; CI станет green
```
Также: тег `v0.2.0` + Release (release.yml уже в репо).

## Следующие паки (бэклог)

- **seedsplit:** тег v0.2.0 + Release; опционально SLIP-39-совместимость (отдельный объём).
- **ECOSYSTEM §7:** единый `check`-движок, единый бренд вывода для всех тулов.
- **graphify (§15):** инициализировать `graphify-out` у ghostdraft/panic/seedsplit →
  богаче merged cross-repo граф.
- Мелочь: `--version`/`--help` алиасы к `version`/usage (сейчас работает `version`-сабкоманда).

## Vendoring pin (общий)

Все тулы вендорят `securetrash/lib/common.sh` pin `2e3d2dd` (SHA256 `fdfb0e3c…af75`).
`tools/vendor-common.sh --check` ловит дрейф в CI. seedsplit-ядро проверено — sync ✓.
