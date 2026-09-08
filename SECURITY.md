# Security Policy

This repository is the monorepo: the `paranoid` launcher, the ecosystem installer
(`install.sh`), `verify-releases.sh`, the shared docs, the GUI, and all five tools
(`securetrash`, `vaultwatch`, `panic`, `ghostdraft`, `seedsplit`), each of which also
carries its own `SECURITY.md` for tool-specific scope.

## Reporting a vulnerability

**Do not open a public issue for an exploitable vulnerability.**

Use GitHub's private vulnerability reporting:

1. Go to the **Security** tab → **Report a vulnerability**
   (<https://github.com/Di-kairos/paranoid-tools/security/advisories/new>).
2. Describe the issue, the affected version or commit, and a reproduction if possible.

All five tools live in this repository, so this is the single reporting channel —
name the affected tool (securetrash, vaultwatch, panic, ghostdraft, seedsplit,
the launcher, or the GUI) in the report.

## Scope

In scope for this repository:

- **`install.sh`** — anything that lets an unverified or substituted artifact be
  installed: signature or checksum verification that can be skipped, downgraded or
  spoofed; the pinned public key being bypassable; a failure that reports success.
- **`paranoid`** — the launcher executing code from a directory the user did not
  intend (the `Update` item resolves an installer path), or misreporting state in a
  way that leads someone to act on a false belief (e.g. showing a vault as closed
  while it is mounted).
- **`verify-releases.sh`** — reporting a release as verified when it is not.
- **Docs** — a claimed guarantee the code does not provide. In this project a
  misleading claim *is* a security defect, not a documentation nit.

Out of scope here (report upstream or in the tool's repo):

- Behaviour of `hdiutil`, BitLocker, VeraCrypt, `skhd` or `openssl` themselves.
- The limits already stated in [THREAT-MODEL.md](THREAT-MODEL.md) — notably that
  overwriting on an SSD is not a guarantee, that an open vault is readable by anyone
  at the machine, and that a single Ed25519 key signs all five tools.

## Release signing

Releases are signed with an Ed25519 key (`releases@paranoid-tools`); the public key is
published in each tool's `SECURITY.md` and pinned inside every installer. The same key
covers all five tools — the blast radius of a compromise, and the absence of in-band
revocation, are described in [THREAT-MODEL.md](THREAT-MODEL.md#verify-dont-trust).

To check the published releases yourself, without trusting the installer:

```bash
bash verify-releases.sh
```

It checks all four signed files of every release — the tool, its PowerShell twin and
both installers — and treats anything that did not download as a failure, not a pass.

### What protects the process that produces those signatures

A signature proves where an artifact came from; it does not protect the place it comes
from. Stated plainly, because the honesty is the point:

- **One person maintains this project.** There is no second reviewer, and no release
  requires anyone else's approval. Do not read "signed" as "independently reviewed".
- **Releases are cut by `release.yml` from a tag**, in a job whose token is scoped to
  `contents: write`; every other workflow runs with a read-only token, and every
  external action is pinned by commit SHA rather than a moving tag.
- **The signing key lives in Actions secrets** of this repository. Anyone who can push
  a tag here can therefore produce a correctly signed artifact — the release process
  and the source sit in the same trust zone. That is the honest boundary of what the
  signature buys you.
- **`main` blocks force-pushes and deletion; it does not require review.** A repository
  ruleset denies non-fast-forward pushes and branch deletion, with no bypass for anyone,
  the maintainer included: credentials that leak can still add a commit, but they cannot
  quietly rewrite what is already published or erase the branch. Requiring pull requests
  or review would be ceremony with one maintainer, and is deliberately not enabled — that
  part remains what it looks like, a project with a single pair of eyes.

### If the signing key is compromised

There is no in-band revocation — an installer pins the public key, so a key that has
leaked keeps verifying until users update. The plan, in order:

1. Publish the compromise at the top of this file and of the root `README.md`, naming
   the last release believed to be honest and the date the key must no longer be
   trusted. Assume users see this before they see anything else.
2. Generate a new Ed25519 key offline, replace the Actions secret, and re-sign and
   re-publish every current release under the new key.
3. Update the pinned public key in every installer, in `verify-releases.sh` and in each
   `SECURITY.md`, and cut a new patch release of all five tools so a normal update path
   carries the new pin.
4. Keep the old key's fingerprint published as revoked, so an artifact signed with it
   can be recognized as untrusted after the fact rather than merely failing quietly.
