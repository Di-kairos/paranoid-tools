# bin/release-notes.sh writes the body of a GitHub release from the tool's CHANGELOG. Until it
# existed, thirteen release pages carried one line each — a compare link — and no word on how to
# verify the six files sitting right above it.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../bin/release-notes.sh"
  ROOT="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$ROOT/bin" "$ROOT/demo"
  cp "$SCRIPT" "$ROOT/bin/"
  cat > "$ROOT/demo/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Fixed
- not this one

## [1.2.3] — 2026-01-02

### Fixed
- **the thing.** Was broken, now is not.

## [1.2.30] — 2025-12-01

### Changed
- a decoy with a longer version number

## [1.2.2] — 2025-11-01

- older
EOF
}

@test "the body carries exactly the tagged version's section, and the verify block" {
  run bash "$ROOT/bin/release-notes.sh" demo demo-v1.2.3
  [ "$status" -eq 0 ]
  [[ "$output" == *"**the thing.**"* ]]
  [[ "$output" != *"decoy"* ]]
  [[ "$output" != *"not this one"* ]]
  [[ "$output" != *"older"* ]]
  [[ "$output" == *"ssh-keygen -Y verify"* ]]
  [[ "$output" == *"releases/download/demo-v1.2.3"* ]]
}

@test "a previous tag adds the compare link; none adds nothing" {
  run bash "$ROOT/bin/release-notes.sh" demo demo-v1.2.3 --prev demo-v1.2.2
  [[ "$output" == *"compare/demo-v1.2.2...demo-v1.2.3"* ]]
  run bash "$ROOT/bin/release-notes.sh" demo demo-v1.2.3
  [[ "$output" != *"compare/"* ]]
}

@test "an English summary file goes first" {
  printf 'Short and in English.\n' > "${BATS_TEST_TMPDIR}/sum.md"
  run bash "$ROOT/bin/release-notes.sh" demo demo-v1.2.3 --summary "${BATS_TEST_TMPDIR}/sum.md"
  [[ "${lines[0]}" == "Short and in English." ]]
}

@test "a version the changelog does not know is a refusal, not an empty page" {
  run bash "$ROOT/bin/release-notes.sh" demo demo-v9.9.9
  [ "$status" -ne 0 ]
  [[ "$output" == *"no section for 9.9.9"* ]]
}
