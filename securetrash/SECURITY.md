# Security Policy

securetrash is a security tool, so its own correctness matters. If you find a
vulnerability, please report it responsibly.

## Reporting a vulnerability

**Do not open a public issue for an exploitable vulnerability.**

Use GitHub's private vulnerability reporting:

1. Go to the repository's **Security** tab → **Report a vulnerability**
   (<https://github.com/Di-kairos/paranoid-tools/security/advisories/new>).
2. Describe the issue, affected versions, and a reproduction if possible.

You'll get a response as soon as reasonably possible. Once a fix is ready, the
advisory is published and you'll be credited unless you prefer to stay anonymous.

## Scope

In scope:

- Anything that causes securetrash to **claim a guarantee it does not provide**
  (the project's whole point is honesty about secure deletion).
- Vault handling: password exposure, weak container creation, unsafe destroy.
- Path handling in `shred` / `empty` that could delete unintended files.
- Privilege or injection issues in the shell / PowerShell code.

Out of scope:

- The documented limitations of overwriting on SSDs (that's the honest premise,
  not a bug — see the README and `docs/blog/`).
- Leaks from an **open** vault via Spotlight / swap / Time Machine / cloud sync
  that are already documented as limitations (improvements welcome as features).

## Supported versions

The latest released version receives security fixes. securetrash is pre-1.0;
older tags are not maintained.

## Verifying release signatures

Releases ship a `SHA256SUMS` (integrity) and, once release signing is enabled, a
`SHA256SUMS.sig` (authenticity) produced with a dedicated Ed25519 key. The
`install.sh` installer verifies the signature and refuses to install when it
cannot (missing `.sig` or no usable `ssh-keygen`) — fail-closed.
`ALLOW_UNSIGNED_LEGACY=1` is the explicit, deliberate downgrade for pre-signing
releases only (integrity check stays). To verify by hand:

```sh
base=https://github.com/Di-kairos/paranoid-tools/releases/download/securetrash-v0.5.7
curl -fsSLO "$base/SHA256SUMS"
curl -fsSLO "$base/SHA256SUMS.sig"
# Trust anchor — the release-signing public key (see below):
printf '%s namespaces="file" %s\n' \
  releases@paranoid-tools \
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9DVd0vNOwa5hyr9gShaCWoNOVnUsrdHVO/WE0wCZkT" \
  > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools \
  -n file -s SHA256SUMS.sig < SHA256SUMS
```

**Release-signing public key** (identity `releases@paranoid-tools`):

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9DVd0vNOwa5hyr9gShaCWoNOVnUsrdHVO/WE0wCZkT
```

The private key is held offline by the maintainer (inside a securetrash vault)
and a passphraseless copy lives only in the CI signing secret. If the key is ever
rotated, the new public key is published here and in the installer.
