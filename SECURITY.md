# Security Policy

This repository is the umbrella: the `paranoid` launcher, the ecosystem installer
(`install.sh`), `verify-releases.sh`, the shared docs and the GUI. The five tools live
in their own repositories and carry their own `SECURITY.md`.

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
