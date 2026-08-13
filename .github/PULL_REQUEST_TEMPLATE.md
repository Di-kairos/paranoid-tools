<!-- Thanks for the PR. Keep changes surgical and honest. -->

## What & why

<!-- What does this change and what problem does it solve? Which tool(s)? -->

## How verified

<!-- Commands you ran. -->

- [ ] `shellcheck` clean on every shell file touched
- [ ] `bats <tool>/test/` passing (if a tool's macOS side touched)
- [ ] `bats test/` passing (if the launcher/installer touched)
- [ ] `Invoke-Pester <tool>/windows/test` passing (if Windows touched)

## Checklist

- [ ] No new runtime dependency (or justified in the description)
- [ ] User-facing wording stays honest about what the tools can and cannot guarantee
- [ ] Conventional Commit prefix used
