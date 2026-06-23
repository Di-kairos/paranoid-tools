# Session 07 Kickoff

## Что читать первым

1. `HANDOFF.md` — снимок состояния (HEAD всех репо, bats/Pester счётчики).
2. `progress-report-session06.md` — что сделано в сессии 6.

## Снимок на момент закрытия (2026-06-23)

| Репо | HEAD | bats/Pester |
|------|------|-------------|
| umbrella | `f3a3ae7` | — |
| securetrash | `d70802d` | 63/63 bats + 65/65 Pester |
| vaultwatch | `5bc2e89` | 56/56 bats |
| panic | `d4a7c99` | 33/33 bats |
| ghostdraft | `206c82b` | 26/26 bats |
| seedsplit | `1e2c3f1` | 37/37 bats |

**Всего: 215/215 bats · 65/65 Pester · shellcheck clean · CI green**

Все 5 репо PRIVATE. Подписи live. smoke-test.sh: 17/17 ✅

## Фокус сессии 07

**По приоритету:**

1. **Ручной интерактив-QA** (`TESTING.md §2`) — нужен живой `/Volumes/SecretVault`:
   - реальный `securetrash vault open/close` (интерактивный пароль — в обычном Терминале)
   - `ghostdraft new` с `$EDITOR`
   - `vaultwatch status` после `install-hooks`
   - `panic status` (read-only, безопасно)

2. **Шаг 4** (Mr. Di): бэкап `~/paranoid-release-key` в vault → `securetrash shred ~/paranoid-release-key`

3. **Этап 2 (go public)** — ТОЛЬКО по явному «да» Mr. Di:
   - 5 репо → public
   - Убрать 4 "private" заметки: vaultwatch README.md/ru, ghostdraft README.md/ru
   - Homebrew tap `Di-kairos/homebrew-tap`: добавить формулы для vaultwatch/panic/ghostdraft/seedsplit (сейчас только securetrash.rb и он устарел)
   - public install-smoke: `curl|bash install.sh` + `brew install`

4. **Блок 3 (roadmap)** — сознательно отложен: SLIP-39, passphrase-слой, decoy-vault.

## Нет открытых технических долгов.
