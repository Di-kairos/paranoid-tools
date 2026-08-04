# Тесты seedsplit (pack 1: scaffold — вендоринг + skeleton + dispatcher).
setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../seedsplit"
  # uname-стаб (-> Darwin) на PATH: ядро будет звать require_macos. macOS-примитивы
  # тесты не трогают; стаб держит require_macos зелёным на Linux-CI (как у panic/ghostdraft).
  STUBS="${BATS_TEST_DIRNAME}/stubs"
  export PATH="$STUBS:$PATH"
}

@test "version prints semver" {
  run bash "$SCRIPT" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"seedsplit"* ]]
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "no args prints usage and exits non-zero" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "help prints usage and exits zero" {
  run bash "$SCRIPT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "--version flag prints version" { run bash "$SCRIPT" --version; [ "$status" -eq 0 ]; [[ "$output" == *"seedsplit"* ]]; }
@test "-v flag prints version" { run bash "$SCRIPT" -v; [ "$status" -eq 0 ]; [[ "$output" == *"seedsplit"* ]]; }
@test "--help flag prints usage" { run bash "$SCRIPT" --help; [ "$status" -eq 0 ]; [[ "$output" == *"Usage:"* ]]; }
@test "-h flag prints usage" { run bash "$SCRIPT" -h; [ "$status" -eq 0 ]; [[ "$output" == *"Usage:"* ]]; }

@test "unknown command exits non-zero" {
  run bash "$SCRIPT" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "vendored common is present and provides primitives" {
  run bash -c "source '$SCRIPT' 2>/dev/null; type info >/dev/null && type confirm >/dev/null && type require_macos >/dev/null && echo OK"
  [[ "$output" == *"OK"* ]]
}

@test "sourcing the script does not run the dispatcher" {
  run bash -c "source '$SCRIPT'; echo SOURCED_OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED_OK"* ]]
  [[ "$output" != *"Usage:"* ]]
}

@test "vendor --check passes (no drift)" {
  run bash "${BATS_TEST_DIRNAME}/../tools/vendor-common.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"синхронен"* ]] || [[ "$output" == *"sync"* ]]
}

@test "split with no secret prints error (not crash) — core is implemented" {
  # split без stdin-секрета и без --file: должен внятно отказать, не падать молча.
  run bash -c "printf '' | bash '$SCRIPT' split"
  [ "$status" -ne 0 ]
}

@test "split on a terminal prompts instead of silently waiting on stdin (P2-1)" {
  # Раньше интерактивный `seedsplit split` молча ждал stdin — читалось как зависание,
  # а набранный секрет оставался в scrollback. Нужен pty: без него ветка не срабатывает.
  command -v script >/dev/null 2>&1 || skip "script(1) unavailable"
  # BSD (macOS): script -q <file> <cmd>; GNU (Linux-CI): script -qec "<cmd>" <file>.
  if script -q /dev/null true >/dev/null 2>&1; then
    out="$( (sleep 0.4; printf 'correct horse battery staple\n'; sleep 0.4) \
            | script -q /dev/null bash "$SCRIPT" split -n 2 -t 2 2>&1 )"
  else
    out="$( (sleep 0.4; printf 'correct horse battery staple\n'; sleep 0.4) \
            | script -qec "bash '$SCRIPT' split -n 2 -t 2" /dev/null 2>&1 )"
  fi
  [[ "$out" == *"Secret to split"* ]] || [[ "$out" == *"Секрет для разбиения"* ]]
  [[ "$out" == *"SSS2-"* ]]                        # доли всё же выданы
  [[ "$out" != *"correct horse battery staple"* ]] # и секрет не отражён эхом
}

@test "TTY input reconstructs byte-for-byte, spaces included (Codex review)" {
  # Дефолтный IFS срезал бы ведущие/хвостовые пробелы, и один и тот же секрет через
  # терминал и через пайп дал бы разные доли. Сверяем восстановленный секрет побайтно.
  command -v script >/dev/null 2>&1 || skip "script(1) unavailable"
  secret='  two spaces  and trailing  '
  if script -q /dev/null true >/dev/null 2>&1; then
    out="$( (sleep 0.4; printf '%s\n' "$secret"; sleep 0.4) \
            | script -q /dev/null bash "$SCRIPT" split -n 2 -t 2 2>&1 )"
  else
    out="$( (sleep 0.4; printf '%s\n' "$secret"; sleep 0.4) \
            | script -qec "bash '$SCRIPT' split -n 2 -t 2" /dev/null 2>&1 )"
  fi
  shares="$(printf '%s\n' "$out" | tr -d '\r' | grep '^SSS2-')"
  [ -n "$shares" ]
  back="$(printf '%s\n' "$shares" | bash "$SCRIPT" combine)"
  [ "$back" = "$secret" ]
}

@test "piped stdin still works and shows no prompt (non-interactive path unchanged)" {
  run bash -c "printf 'correct horse battery staple' | bash '$SCRIPT' split -n 2 -t 2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SSS2-"* ]]
  [[ "$output" != *"Secret to split"* ]]
}

@test "vendor --check detects drift in the vendored block" {
  work="$(mktemp -d)"; mkdir -p "$work/tools"
  cp "${BATS_TEST_DIRNAME}/../seedsplit" "$work/seedsplit"
  cp "${BATS_TEST_DIRNAME}/../tools/vendor-common.sh" "$work/tools/"
  sed 's/_ST_COMMON_LOADED=1/_ST_COMMON_LOADED=999/' "$work/seedsplit" > "$work/seedsplit.mut"
  mv "$work/seedsplit.mut" "$work/seedsplit"
  run bash "$work/tools/vendor-common.sh" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ДРЕЙФ"* ]] || [[ "$output" == *"drift"* ]]
  rm -rf "$work"
}
