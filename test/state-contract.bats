# The state contract itself: three adapters answer "is the vault open?" — bash
# (securetrash/lib/common.sh), the macOS menu-bar app (Swift) and the Windows tray (PowerShell).
# Nothing in the build forces them to agree, and the one time they drifted the GUI painted a
# green OPEN over a closed vault (AUDIT_2026-08-03 P2-10). Audit 2026-09-07 §16.3 asks for the
# same scenarios checked in every adapter rather than for a rewrite of working interfaces.
#
# This suite does not test vault logic. It tests that the table in test/state-contract.json is
# actually honoured: every rule id appears in every adapter's suite, and the JSON does not quietly
# drop a rule from an adapter's coverage list. Add a rule to the table and three tests go red
# until all three adapters cover it — which is the entire point.

setup() {
  ROOT="${BATS_TEST_DIRNAME}/.."
  CONTRACT="$ROOT/test/state-contract.json"
}

_rule_ids() { grep -o '"id": "[^"]*"' "$CONTRACT" | sed 's/.*: "//; s/"$//'; }

# Suite paths, with the parenthetical note stripped: Swift's suite is the binary's own --selftest,
# which lives in the same file as the implementation.
_suite_files() { grep -o '"suite": "[^"]*"' "$CONTRACT" | sed 's/.*: "//; s/"$//; s/ (.*//'; }

@test "the contract lists rules and adapters at all" {
  [ -f "$CONTRACT" ]
  [ "$(_rule_ids | wc -l | tr -d ' ')" -ge 4 ]
  [ "$(_suite_files | wc -l | tr -d ' ')" -eq 3 ]
}

@test "every adapter suite named by the contract exists" {
  while read -r suite; do
    [ -n "$suite" ] || continue
    [ -f "$ROOT/$suite" ] || { echo "missing suite: $suite"; false; }
  done < <(_suite_files)
}

@test "every state rule is exercised in every adapter's suite" {
  local bad=""
  while read -r id; do
    [ -n "$id" ] || continue
    while read -r suite; do
      [ -n "$suite" ] || continue
      grep -qF -- "$id" "$ROOT/$suite" || bad="$bad$suite does not cover $id"$'\n'
    done < <(_suite_files)
  done < <(_rule_ids)
  [ -z "$bad" ] || { echo "$bad"; false; }
}

@test "every adapter claims coverage of every rule in the table" {
  # The JSON is data a human edits; an adapter silently dropped from a rule's coverage would
  # make the check above pass while the rule went unchecked there.
  local ids adapters bad=""
  ids="$(_rule_ids)"
  # One "covers" block per adapter: count each id inside the adapters section.
  adapters="$(sed -n '/"adapters"/,$p' "$CONTRACT")"
  while read -r id; do
    [ -n "$id" ] || continue
    n="$(printf '%s\n' "$adapters" | grep -cF -- "\"$id\"" || true)"
    [ "$n" -eq 3 ] || bad="$bad$id is claimed by $n adapters, not 3"$'\n'
  done <<< "$ids"
  [ -z "$bad" ] || { echo "$bad"; false; }
}

@test "the implementations named by the contract still exist" {
  # A rename that leaves the table pointing at a function nobody has is how a contract rots.
  while read -r impl; do
    [ -n "$impl" ] || continue
    file="${impl%%:*}"
    symbol="${impl#*:}"
    [ -f "$ROOT/$file" ] || { echo "missing implementation file: $file"; false; }
    if [ "$symbol" != "$impl" ]; then
      grep -qF -- "$symbol" "$ROOT/$file" || { echo "$file has no $symbol"; false; }
    fi
  done < <(grep -o '"implementation": "[^"]*"' "$CONTRACT" | sed 's/.*: "//; s/"$//')
}
