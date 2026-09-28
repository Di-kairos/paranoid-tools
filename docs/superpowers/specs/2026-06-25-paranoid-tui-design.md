# paranoid — TUI launcher (Phase A) — design spec

**Date:** 2026-06-25
**Status:** approved for implementation
**Phase:** A (cheap, in-ethos MVP). Phase B (native menu-bar/tray) is out of scope here.

## Purpose

A single interactive launcher that makes the five Paranoid Tools feel like one cohesive
product for a **non-technical privacy audience** (crypto holders, activists, journalists)
who are scared off by a raw terminal. It is a thin **launcher**, not a new tool: it shells
out to the same five signed CLIs and never touches crypto or secrets itself.

See ecosystem direction: `.claude/memory/gui-wrapper-direction.md`.

## Non-goals (YAGNI)

- **No new crypto / no secret handling.** Secrets are typed straight into each CLI's own
  stdin prompt. The launcher never reads, stores, or passes a secret on argv.
- **No global hotkey, no background daemon.** Real-panic-speed via hotkey is Phase B
  (native app). The launcher's `panic` entry is still a terminal action.
- **No Windows port in this phase.** A `paranoid.ps1` mirror is a later, separate task.
- **No config file, no persisted state.** The launcher only *reads* live status from the
  CLIs; it owns no state of its own.
- **No third-party TUI deps** (no whiptail/dialog/ncurses). Pure Bash only — preserves the
  "zero dependencies, fully auditable" ethos.

## Architecture

- A single pure-Bash script `paranoid` living in the **umbrella repo** (`paranoid-tools`),
  installed to `~/.local/bin` by the umbrella `install.sh` (same mechanism as the tools).
- It discovers the five CLIs on `PATH` by name (`command -v securetrash`, etc.). Each tool
  is independent; a missing tool is shown greyed-out with an install hint, never faked.
- **Control flow:** a render→read→dispatch loop.
  1. Render the dashboard (header status + numbered action list).
  2. Read a single key/number.
  3. Dispatch: `exec` the corresponding real CLI, stream its stdout/stderr to the terminal
     (including `Scope & limitations` and `check` verdicts — never hidden), then pause
     ("press Enter") and return to step 1.
  4. `0`/`q` quits.
- The launcher adds **no** flags that change a tool's security behavior; it only chooses
  which subcommand to invoke and forwards interactive prompts.

### Units (each independently testable)

- `_detect_tools` — map of tool→(installed? path). Pure; no side effects.
- `_status_line_vault` / `_status_line_filevault` / `_status_line_vaultwatch` — each returns
  one honest status string by reading a CLI (or a cheap system check), degrading to
  "unknown" rather than guessing.
- `_render_dashboard` — prints header + status block + menu from the above. Pure-ish (only
  reads).
- `_dispatch <choice>` — maps a choice to a CLI invocation; the only unit that execs tools.
- `main` — the loop + signal traps.

## The dashboard

```
  PARANOID TOOLS                              macOS

  Vault:      ● OPEN  (/Volumes/SecretVault)   ⚠ at risk while open
  FileVault:  ● ON
  vaultwatch: ● active — auto-exit in 24m

  1) Status — full read-only check
  2) 🔒 PANIC NOW — hide & lock (confirm)
  3) Vault — open / close
  4) Split a secret (seedsplit)
  5) Combine shares (seedsplit)
  6) Ghostdraft — ephemeral note / pipe
  7) Watch vault — guard + TTL (vaultwatch)
  0) Quit
```

- Status dots: `●` green = safe/closed state, yellow = attention (e.g. vault open),
  grey = unknown / tool absent. Color only on a TTY (mirror common.sh convention).
- The "⚠ at risk while open" note is **mandatory** when a vault is mounted — the launcher
  must never make an open vault look safe (honesty constraint).

## Actions → CLI mapping

| # | Label | Invokes |
|---|-------|---------|
| 1 | Status | `securetrash check` + `vaultwatch status` (read-only), concatenated |
| 2 | Panic now | confirm, then `panic now` (offer `--hard` as a sub-prompt) |
| 3 | Vault open/close | `securetrash vault open` / `… close` (sub-menu by current state) |
| 4 | Split | `seedsplit split` (interactive; secret via its stdin) |
| 5 | Combine | `seedsplit combine` |
| 6 | Ghostdraft | sub-menu: `ghostdraft new` / `ghostdraft pipe` |
| 7 | Watch | `vaultwatch start` with an optional `--ttl` prompt |

A menu entry whose tool is not installed is rendered greyed-out and, if chosen, prints the
one-line install hint for that tool instead of running anything.

## I18n

`ST_LANG`/locale detection identical to the ecosystem (en default, ru when locale starts
with `ru`). All launcher chrome (labels, prompts, hints) localized; tool output passes
through verbatim (the tools localize themselves).

## Error handling

- Tool not on `PATH` → greyed entry + install hint; never crash.
- CLI exits non-zero → show its stderr, return to the menu (loop survives).
- `Ctrl-C` inside a sub-action → trap returns to the dashboard, does **not** exit the
  launcher; `Ctrl-C` at the dashboard → clean exit.
- Invalid menu input → reprint the menu, no error spam.

## Honesty constraints (non-negotiable, from gui-wrapper-direction)

- Never hide `Scope & limitations` or `check` verdicts — they stream through unaltered.
- An open vault is always flagged "at risk while open".
- `panic now` always confirms before acting (it is destructive to the open session).
- The launcher claims nothing the underlying tool does not.

## Testing (bats, mirrors ecosystem pattern)

- Dashboard renders with all-present / some-absent tool sets (stub CLIs on `PATH`).
- Each menu choice dispatches to the correct CLI (assert via stub that records argv).
- Missing-tool choice prints the install hint and runs nothing.
- `panic` requires confirmation (declining runs nothing).
- Quit paths (`0`, `q`).
- Locale: ru vs en chrome strings.
- No-arg launch enters the loop; `--help`/`version` behave.

## File layout

```
paranoid-tools/
  paranoid                # the launcher (pure Bash)
  test/paranoid.bats      # bats suite (with on-PATH stub tools)
  install.sh              # extended to also install `paranoid`
  README.md / README.ru.md# add a short "paranoid launcher" section
  CHANGELOG.md            # new (umbrella has none yet) or a README note
```

## Build process (per Di-kairos directive)

Implementation runs with: mandatory re-check, **three-brain (ТриМозга) cross-review**,
**parallel agents** for independent pieces, a **full run** (bats + shellcheck + manual
smoke), and **commit only at the very end** after everything is green.

## Out of scope / next phases

- `paranoid.ps1` Windows mirror (separate task).
- Phase B native menu-bar (macOS SwiftUI) / system-tray (Windows) — the paid open-core
  convenience layer.
