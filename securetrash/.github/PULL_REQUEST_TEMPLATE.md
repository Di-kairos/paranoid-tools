<!-- Thanks for the PR. Keep changes surgical and honest. -->

## What & why

<!-- What does this change and what problem does it solve? -->

## How verified

<!-- Commands you ran. -->

- [ ] `shellcheck securetrash install.sh` clean (if shell touched)
- [ ] `bats test/securetrash.bats` passing (if macOS touched)
- [ ] `Invoke-Pester windows/test` passing (if Windows touched)

## Checklist

- [ ] No new runtime dependency (or justified in the description)
- [ ] User-facing wording stays honest about SSD/shred guarantees
- [ ] Conventional Commit prefix used
