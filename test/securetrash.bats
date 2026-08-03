setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../securetrash"
}

@test "sourcing the script does not run the dispatcher" {
  run bash -c "source '$SCRIPT'; echo SOURCED_OK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED_OK"* ]]
  [[ "$output" != *"Usage:"* ]]
}

@test "no args prints usage and exits non-zero" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown subcommand exits non-zero with error" {
  run bash "$SCRIPT" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "--version flag prints version" { run bash "$SCRIPT" --version; [ "$status" -eq 0 ]; [[ "$output" == *"securetrash"* ]]; }
@test "-v flag prints version" { run bash "$SCRIPT" -v; [ "$status" -eq 0 ]; [[ "$output" == *"securetrash"* ]]; }
@test "--help flag prints usage" { run bash "$SCRIPT" --help; [ "$status" -eq 0 ]; [[ "$output" == *"Usage:"* ]]; }
@test "-h flag prints usage" { run bash "$SCRIPT" -h; [ "$status" -eq 0 ]; [[ "$output" == *"Usage:"* ]]; }

@test "is_ssd returns true when diskutil reports SSD Yes" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash -c "source '$SCRIPT'; is_ssd / && echo SSD || echo NOTSSD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SSD"* ]]
}

@test "filevault_on returns true when fdesetup says On" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash -c "source '$SCRIPT'; filevault_on && echo FV_ON || echo FV_OFF"
  [[ "$output" == *"FV_ON"* ]]
}

@test "check on SSD + FileVault On gives crypto-shred verdict" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"FileVault"* ]]
  [[ "$output" == *"SSD"* ]]
  [[ "$output" == *"vault"* ]]
}

@test "check warns loudly when FileVault is Off" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks-fvoff:$PATH" bash "$SCRIPT" check
  [[ "$output" == *"FileVault is OFF"* ]] || [[ "$output" == *"FileVault is Off"* ]]
}

@test "check says 'unknown' (not OFF) when FileVault status can't be determined" {
  # Рассинхрон из trial-отчёта: дашборд показывал «неизвестно», а check — «ВЫКЛЮЧЕН».
  # Теперь check тоже tri-state: неопределённый fdesetup → unknown, консервативно, не ложный OFF.
  run env PATH="${BATS_TEST_DIRNAME}/mocks-fvunknown:$PATH" bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]]
  [[ "$output" != *"FileVault is OFF"* ]]
}

@test "check in Russian (ST_LANG=ru) produces Russian output" {
  run env ST_LANG=ru PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"ВКЛЮЧЕН"* ]]
}

@test "setup creates the trash dir and is idempotent" {
  tmp="$(mktemp -d)"
  run env HOME="$tmp" PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" setup
  [ "$status" -eq 0 ]
  [ -d "$tmp/SecureTrash" ]
  run env HOME="$tmp" PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" setup
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
}

@test "setup appends sectrash alias to .zshrc exactly once" {
  tmp="$(mktemp -d)"; touch "$tmp/.zshrc"
  env HOME="$tmp" PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" bash "$SCRIPT" setup
  env HOME="$tmp" PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" bash "$SCRIPT" setup
  count="$(grep -c "alias sectrash=" "$tmp/.zshrc")"
  [ "$count" -eq 1 ]
  rm -rf "$tmp"
}

@test "shred deletes a file and reports honestly on SSD" {
  tmp="$(mktemp -d)"; echo secret > "$tmp/f.txt"
  run env ST_ASSUME_YES=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred "$tmp/f.txt"
  [ "$status" -eq 0 ]
  [ ! -e "$tmp/f.txt" ]
  [[ "$output" == *"FileVault"* ]]
  rm -rf "$tmp"
}

@test "shred on missing path errors" {
  run env ST_ASSUME_YES=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred /no/such/path
  [ "$status" -ne 0 ]
}

@test "shred handles a filename starting with a dash (-- guard)" {
  tmp="$(mktemp -d)"; echo secret > "$tmp/-rf-test"
  run env ST_ASSUME_YES=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred "$tmp/-rf-test"
  [ "$status" -eq 0 ]
  [ ! -e "$tmp/-rf-test" ]
  rm -rf "$tmp"
}

@test "--yes flag bypasses confirmation like ST_ASSUME_YES" {
  tmp="$(mktemp -d)"; echo secret > "$tmp/f.txt"
  run env PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred --yes "$tmp/f.txt"
  [ "$status" -eq 0 ]
  [ ! -e "$tmp/f.txt" ]
  rm -rf "$tmp"
}

@test "check on unknown disk type warns about no guarantee" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks-unknown:$PATH" bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not be determined"* ]] || [[ "$output" == *"determine the disk type"* ]]
}

@test "empty clears the trash dir contents but keeps the dir" {
  tmp="$(mktemp -d)"; mkdir -p "$tmp/SecureTrash"; echo x > "$tmp/SecureTrash/a"
  run env HOME="$tmp" ST_ASSUME_YES=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" empty
  [ "$status" -eq 0 ]
  [ -d "$tmp/SecureTrash" ]
  [ -z "$(ls -A "$tmp/SecureTrash")" ]
  rm -rf "$tmp"
}

@test "vault with no subcommand errors" {
  run env PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" bash "$SCRIPT" vault
  [ "$status" -ne 0 ]
  [[ "$output" == *"reset"* ]]
  [[ "$output" == *"destroy"* ]]
}

@test "vault create calls hdiutil create" {
  tmp="$(mktemp -d)"
  run env HOME="$tmp" ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault create
  [ "$status" -eq 0 ]
  [ -f "$tmp/hdiutil_calls.log" ]
  grep -q "create" "$tmp/hdiutil_calls.log"
  rm -rf "$tmp"
}

@test "vault destroy requires confirmation and removes container" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  run env HOME="$tmp" ST_ASSUME_YES=1 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault destroy
  [ "$status" -eq 0 ]
  [ ! -e "$tmp/SecureVault.sparsebundle" ]
  rm -rf "$tmp"
}

@test "vault destroy refuses a path that is not a sparsebundle" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  run env HOME="$tmp" ST_ASSUME_YES=1 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault destroy
  [ "$status" -ne 0 ]
  [ -e "$tmp/SecureVault.sparsebundle" ]
  rm -rf "$tmp"
}

@test "vault reset crypto-shreds the old container then recreates it" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  echo OLD > "$tmp/SecureVault.sparsebundle/bands/marker"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset
  [ "$status" -eq 0 ]
  # recreate step ran (mock logs hdiutil create) and the old band content is gone
  grep -q "create" "$tmp/hdiutil_calls.log"
  [ ! -e "$tmp/SecureVault.sparsebundle/bands/marker" ]
  rm -rf "$tmp"
}

# --- P0-1: securetrash должен уважать ST_VAULT_PATH / ST_VAULT_VOLUME ---
# Иначе GUI/TUI показывают один сейф (через ST_VAULT_*), а destructive-операции
# бьют по захардкоженному дефолту.

@test "ST_VAULT_PATH overrides the container path" {
  run env ST_VAULT_PATH="/tmp/custom-vault.sparsebundle" \
    bash -c "source '$SCRIPT'; printf '%s' \"\$VAULT_PATH\""
  [ "$status" -eq 0 ]
  [[ "$output" == "/tmp/custom-vault.sparsebundle" ]]
}

@test "ST_VAULT_VOLUME overrides the mount point" {
  run env ST_VAULT_VOLUME="/Volumes/CustomVault" \
    bash -c "source '$SCRIPT'; printf '%s' \"\$VAULT_VOLUME\""
  [ "$status" -eq 0 ]
  [[ "$output" == "/Volumes/CustomVault" ]]
}

@test "vault destroy targets the container from ST_VAULT_PATH, not the default" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/custom-vault.sparsebundle/bands"; echo x > "$tmp/custom-vault.sparsebundle/Info.plist"
  # дефолтный контейнер тоже существует — он НЕ должен пострадать
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_VAULT_PATH="$tmp/custom-vault.sparsebundle" \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault destroy
  [ "$status" -eq 0 ]
  [ ! -e "$tmp/custom-vault.sparsebundle" ]
  [ -e "$tmp/SecureVault.sparsebundle" ]
  rm -rf "$tmp"
}

# --- P2-2: reset должен валидировать размер ДО destroy ---
# Иначе опечатка в размере уничтожает старый сейф, а create падает → пользователь без сейфа.

@test "vault reset with an invalid size refuses and keeps the old container" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  echo OLD > "$tmp/SecureVault.sparsebundle/bands/marker"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset "not-a-size"
  [ "$status" -ne 0 ]
  # старый контейнер и его содержимое НЕ тронуты (destroy не выполнялся)
  [ -e "$tmp/SecureVault.sparsebundle/bands/marker" ]
  rm -rf "$tmp"
}

@test "vault reset with size 0 refuses and keeps the old container" {
  # 0 проходит формат-regex, но create на нём падает → сейф был бы уничтожен зря
  # (Codex review AUDIT_2026-08-03 P0-1; паритет с ps1).
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  echo OLD > "$tmp/SecureVault.sparsebundle/bands/marker"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset "0"
  [ "$status" -ne 0 ]
  [ -e "$tmp/SecureVault.sparsebundle/bands/marker" ]
  rm -rf "$tmp"
}

@test "vault create with an invalid size refuses before touching hdiutil" {
  tmp="$(mktemp -d)"
  run env HOME="$tmp" ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault create "not-a-size"
  [ "$status" -ne 0 ]
  [ ! -f "$tmp/hdiutil_calls.log" ]
  rm -rf "$tmp"
}

@test "vault reset detaches first when the vault is mounted" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_MOCK_VAULT_ATTACHED=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset
  [ "$status" -eq 0 ]
  grep -q "detach /dev/disk99" "$tmp/hdiutil_calls.log"
  grep -q "create" "$tmp/hdiutil_calls.log"
  rm -rf "$tmp"
}

@test "vault reset refuses when no container exists" {
  tmp="$(mktemp -d)"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset
  [ "$status" -ne 0 ]
  rm -rf "$tmp"
}

@test "vault reset refuses a path that is not a sparsebundle (keeps it)" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset
  [ "$status" -ne 0 ]
  [ -e "$tmp/SecureVault.sparsebundle" ]
  rm -rf "$tmp"
}

@test "vault reset aborts (keeps container) if mounted and detach fails" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_MOCK_VAULT_ATTACHED=1 ST_MOCK_DETACH_FAIL=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset
  [ "$status" -ne 0 ]
  [ -e "$tmp/SecureVault.sparsebundle" ]
  ! grep -q "create" "$tmp/hdiutil_calls.log"
  rm -rf "$tmp"
}

@test "vault reset passes a custom size to create" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset 5g
  [ "$status" -eq 0 ]
  grep -q "5g" "$tmp/hdiutil_calls.log"
  rm -rf "$tmp"
}

# --- reset: между «старого сейфа уже нет» и «новый готов» не должно быть окна ---
# Раньше reset делал destroy → create подряд: падение create (нет места, отказ hdiutil,
# Ctrl-C на промпте пароля) оставляло пользователя вообще без сейфа. Теперь старый
# контейнер отставляется в .old и крипто-шредится только после успешного create.

@test "vault reset restores the old container when create fails" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  echo OLD > "$tmp/SecureVault.sparsebundle/bands/marker"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_VAULT_PASS=test1234 ST_MOCK_CREATE_FAIL=1 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset
  [ "$status" -ne 0 ]
  # старый сейф вернулся на место вместе с содержимым, хвоста .old нет
  [ -e "$tmp/SecureVault.sparsebundle/bands/marker" ]
  [ ! -e "$tmp/SecureVault.sparsebundle.old" ]
  # и пользователю сказано, что откат произошёл
  [[ "$output" == *"rolled back"* ]] || [[ "$output" == *"откачен"* ]]
  rm -rf "$tmp"
}

@test "vault reset leaves no aside copy of the old container on success" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  echo OLD > "$tmp/SecureVault.sparsebundle/bands/marker"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset
  [ "$status" -eq 0 ]
  # новый контейнер реально на месте и имеет форму sparsebundle
  [ -d "$tmp/SecureVault.sparsebundle" ]
  [ -e "$tmp/SecureVault.sparsebundle/Info.plist" ]
  # старое содержимое не пережило reset ни на месте, ни в .old
  [ ! -e "$tmp/SecureVault.sparsebundle.old" ]
  [ ! -e "$tmp/SecureVault.sparsebundle/bands/marker" ]
  rm -rf "$tmp"
}

# Уцелевший .old — это данные пользователя (прерванный reset или его ручной бэкап).
# Снести его молча = потерять единственную копию. reset обязан отказаться.
@test "vault reset refuses when a .old container is already there and keeps it" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  mkdir -p "$tmp/SecureVault.sparsebundle.old/bands"; echo PRECIOUS > "$tmp/SecureVault.sparsebundle.old/bands/junk"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault reset
  [ "$status" -ne 0 ]
  # обе копии целы, ничего не создавалось
  [ -e "$tmp/SecureVault.sparsebundle.old/bands/junk" ]
  [ -e "$tmp/SecureVault.sparsebundle/bands" ]
  [ ! -f "$tmp/hdiutil_calls.log" ] || ! grep -q "create" "$tmp/hdiutil_calls.log"
  rm -rf "$tmp"
}

@test "vault commands point at a leftover .old so the user knows where the data is" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  mkdir -p "$tmp/SecureVault.sparsebundle.old"; echo x > "$tmp/SecureVault.sparsebundle.old/Info.plist"
  run env HOME="$tmp" PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault status
  [[ "$output" == *"SecureVault.sparsebundle.old"* ]]
  rm -rf "$tmp"
}

@test "vault create reports failure instead of claiming success" {
  # Утверждаем только то, что гарантирует код: ненулевой выход и явное сообщение.
  # Уборку частичного контейнера после падения hdiutil securetrash НЕ делает —
  # заявлять это тестом (мок падает до записи) значило бы проверять мок, а не код.
  tmp="$(mktemp -d)"
  run env HOME="$tmp" ST_VAULT_PASS=test1234 ST_MOCK_CREATE_FAIL=1 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault create
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not create the container"* ]] || [[ "$output" == *"Не удалось создать контейнер"* ]]
  rm -rf "$tmp"
}

# --- снимки: главный канал, по которому «стёртый» файл выживает ---
# shred и crypto-shred про снимки ничего не знают, поэтому инструмент обязан
# сказать о них сам — пользователь иначе считает, что удалил файл насовсем.

@test "check reports Time Machine snapshots when they exist" {
  run env ST_MOCK_SNAPSHOTS=3 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"snapshots: 3"* ]] || [[ "$output" == *"снимков APFS: 3"* ]]
}

@test "check does not count installer rollback snapshots as document history" {
  run env ST_MOCK_SNAPSHOTS=0 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  # в моке всегда есть com.apple.os.update-* — он не должен считаться снимком TM
  [[ "$output" == *"none right now"* ]] || [[ "$output" == *"снимков APFS сейчас нет"* ]]
}

@test "check counts third-party snapshots too, not just Time Machine ones" {
  # CCC/Arq держат ровно такую же полную копию — allowlist по com.apple.TimeMachine.*
  # выдал бы бодрое «снимков нет» там, где копия есть.
  run env ST_MOCK_SNAPSHOTS=0 ST_MOCK_SNAPSHOTS_CCC=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"snapshots: 1"* ]] || [[ "$output" == *"снимков APFS: 1"* ]]
}

@test "check stays honest when tmutil cannot be read" {
  run env ST_MOCK_TMUTIL_FAIL=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"Could not read local snapshots"* ]] || [[ "$output" == *"Не удалось прочитать локальные снимки"* ]]
}

@test "shred warns about snapshots holding a full copy" {
  tmp="$(mktemp -d)"; echo secret > "$tmp/file.txt"
  run env ST_ASSUME_YES=1 ST_MOCK_SNAPSHOTS=2 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred "$tmp/file.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FULL copy"* ]] || [[ "$output" == *"ПОЛНУЮ копию"* ]]
  rm -rf "$tmp"
}

@test "shred refuses a protected system path (/)" {
  run env ST_ASSUME_YES=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred /
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected"* ]] || [[ "$output" == *"защищ"* ]]
  [ -d / ]
}

@test "shred refuses \$HOME itself but the dir survives" {
  tmp="$(mktemp -d)"; echo x > "$tmp/keep.txt"
  run env HOME="$tmp" ST_ASSUME_YES=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred "$tmp"
  [ "$status" -ne 0 ]
  [ -d "$tmp" ]
  [ -e "$tmp/keep.txt" ]
  rm -rf "$tmp"
}

@test "vault status reports CLOSED when container exists but not mounted" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  run env HOME="$tmp" PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault status
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLOSED"* ]] || [[ "$output" == *"ЗАКРЫТ"* ]]
  rm -rf "$tmp"
}

@test "vault status reports OPEN when image is attached" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  run env HOME="$tmp" ST_MOCK_VAULT_ATTACHED=1 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault status
  [ "$status" -eq 0 ]
  [[ "$output" == *"OPEN"* ]] || [[ "$output" == *"ОТКРЫТ"* ]]
  rm -rf "$tmp"
}

@test "vault open on an already-mounted image does not attach again" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  run env HOME="$tmp" ST_MOCK_VAULT_ATTACHED=1 ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault open
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already open"* ]] || [[ "$output" == *"Уже открыт"* ]]
  ! grep -q "^attach" "$tmp/hdiutil_calls.log"
  rm -rf "$tmp"
}

@test "vault destroy detaches by dev-node when attached" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_MOCK_VAULT_ATTACHED=1 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault destroy
  [ "$status" -eq 0 ]
  [ ! -e "$tmp/SecureVault.sparsebundle" ]
  grep -q "detach /dev/disk99" "$tmp/hdiutil_calls.log"
  rm -rf "$tmp"
}

@test "vault open mounts with a fixed mountpoint and is browseable by default" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  run env HOME="$tmp" ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault open
  [ "$status" -eq 0 ]
  grep -q "mountpoint" "$tmp/hdiutil_calls.log"
  # По умолчанию том виден в Finder → НЕ -nobrowse (иначе закрыл окно = забыл смонтированным).
  ! grep -q "nobrowse" "$tmp/hdiutil_calls.log"
  rm -rf "$tmp"
}

@test "vault open hides the volume (-nobrowse) when ST_VAULT_HIDDEN=1" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  run env HOME="$tmp" ST_VAULT_PASS=test1234 ST_VAULT_HIDDEN=1 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault open
  [ "$status" -eq 0 ]
  grep -q "nobrowse" "$tmp/hdiutil_calls.log"
  rm -rf "$tmp"
}

@test "vault open reveals the mounted volume in Finder" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  run env HOME="$tmp" ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault open
  [ "$status" -eq 0 ]
  grep -q "/Volumes/SecretVault" "$tmp/open_calls.log"
  rm -rf "$tmp"
}

@test "vault open skips the Finder reveal when ST_VAULT_NO_REVEAL=1" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  run env HOME="$tmp" ST_VAULT_PASS=test1234 ST_VAULT_NO_REVEAL=1 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault open
  [ "$status" -eq 0 ]
  [ ! -f "$tmp/open_calls.log" ]
  rm -rf "$tmp"
}

@test "vault destroy aborts (keeps container) if mounted and detach fails" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_MOCK_VAULT_ATTACHED=1 ST_MOCK_DETACH_FAIL=1 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault destroy
  [ "$status" -ne 0 ]
  [ -e "$tmp/SecureVault.sparsebundle" ]
  [[ "$output" == *"MOUNTED"* ]] || [[ "$output" == *"СМОНТИРОВАН"* ]]
  rm -rf "$tmp"
}

@test "vault destroy aborts (keeps container) when mount state is unknown" {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/SecureVault.sparsebundle/bands"; echo x > "$tmp/SecureVault.sparsebundle/Info.plist"
  run env HOME="$tmp" ST_ASSUME_YES=1 ST_MOCK_INFO_FAIL=1 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault destroy
  [ "$status" -ne 0 ]
  [ -e "$tmp/SecureVault.sparsebundle" ]
  rm -rf "$tmp"
}

@test "shred refuses a system file via canonicalization (/etc/hosts -> /private/etc)" {
  run env ST_ASSUME_YES=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred /etc/hosts
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected"* ]] || [[ "$output" == *"защищ"* ]]
  [ -e /etc/hosts ]
}

@test "shred refuses a symlink-to-system with trailing slash" {
  tmp="$(mktemp -d)"; ln -s /System "$tmp/slink"
  run env ST_ASSUME_YES=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred "$tmp/slink/"
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected"* ]] || [[ "$output" == *"защищ"* ]]
  [ -d /System ]
  rm -rf "$tmp"
}

@test "shred refuses a direct /Volumes mount root" {
  run env ST_ASSUME_YES=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred /Volumes/ExternalDrive
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected"* ]] || [[ "$output" == *"защищ"* ]]
}

@test "shred refuses the vault mountpoint path" {
  run env ST_ASSUME_YES=1 PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" shred /Volumes/SecretVault
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected"* ]] || [[ "$output" == *"защищ"* ]]
}

@test "vault open runs the post-open hook with the mountpoint" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  hooks="$tmp/hooks"; mkdir -p "$hooks"
  printf '#!/usr/bin/env bash\necho "$1" > "%s/open.marker"\n' "$tmp" > "$hooks/post-open"
  chmod +x "$hooks/post-open"
  run env HOME="$tmp" ST_HOOK_DIR="$hooks" ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault open
  [ "$status" -eq 0 ]
  [ -f "$tmp/open.marker" ]
  grep -q "SecretVault" "$tmp/open.marker"
  rm -rf "$tmp"
}

@test "vault close runs the post-close hook" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  hooks="$tmp/hooks"; mkdir -p "$hooks"
  printf '#!/usr/bin/env bash\ntouch "%s/close.marker"\n' "$tmp" > "$hooks/post-close"
  chmod +x "$hooks/post-close"
  run env HOME="$tmp" ST_MOCK_VAULT_ATTACHED=1 ST_HOOK_DIR="$hooks" \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault close
  [ "$status" -eq 0 ]
  [ -f "$tmp/close.marker" ]
  rm -rf "$tmp"
}

@test "vault open succeeds when no hook is installed" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  run env HOME="$tmp" ST_HOOK_DIR="$tmp/nonexistent" ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault open
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
}

@test "vault post-open hook failure does not fail the open" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  hooks="$tmp/hooks"; mkdir -p "$hooks"
  printf '#!/usr/bin/env bash\nexit 3\n' > "$hooks/post-open"
  chmod +x "$hooks/post-open"
  run env HOME="$tmp" ST_HOOK_DIR="$hooks" ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault open
  [ "$status" -eq 0 ]
  [[ "$output" == *"hook failed"* ]] || [[ "$output" == *"ошибкой"* ]]
  rm -rf "$tmp"
}

@test "vault open does NOT fire post-open when already mounted" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  hooks="$tmp/hooks"; mkdir -p "$hooks"
  printf '#!/usr/bin/env bash\ntouch "%s/open.marker"\n' "$tmp" > "$hooks/post-open"
  chmod +x "$hooks/post-open"
  run env HOME="$tmp" ST_MOCK_VAULT_ATTACHED=1 ST_HOOK_DIR="$hooks" ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault open
  [ "$status" -eq 0 ]
  [ ! -e "$tmp/open.marker" ]
  rm -rf "$tmp"
}

@test "vault post-close hook failure does not fail the close" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  hooks="$tmp/hooks"; mkdir -p "$hooks"
  printf '#!/usr/bin/env bash\nexit 3\n' > "$hooks/post-close"
  chmod +x "$hooks/post-close"
  run env HOME="$tmp" ST_MOCK_VAULT_ATTACHED=1 ST_HOOK_DIR="$hooks" \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault close
  [ "$status" -eq 0 ]
  [[ "$output" == *"hook failed"* ]] || [[ "$output" == *"ошибкой"* ]]
  rm -rf "$tmp"
}

@test "non-executable vault hook is skipped" {
  tmp="$(mktemp -d)"; touch "$tmp/SecureVault.sparsebundle"
  hooks="$tmp/hooks"; mkdir -p "$hooks"
  printf '#!/usr/bin/env bash\ntouch "%s/open.marker"\n' "$tmp" > "$hooks/post-open"
  chmod -x "$hooks/post-open" 2>/dev/null || true
  run env HOME="$tmp" ST_HOOK_DIR="$hooks" ST_VAULT_PASS=test1234 \
    PATH="${BATS_TEST_DIRNAME}/mocks:$PATH" \
    bash "$SCRIPT" vault open
  [ "$status" -eq 0 ]
  [ ! -e "$tmp/open.marker" ]
  rm -rf "$tmp"
}
