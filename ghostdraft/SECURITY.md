# Security Policy

ghostdraft is a security tool, so its own correctness matters. Its whole point
is letting you write or view a secret (a seed, password, or key) without leaving
a copy in the usual places — so a bug that quietly leaves the secret behind
defeats the tool. If you find a vulnerability, please report it responsibly.

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

- Anything that causes ghostdraft to **claim a guarantee it does not provide**
  (the project's whole point is honesty about where a secret can end up).
- The draft never reaching a safe location: silently writing the draft to
  on-disk `/tmp` / `$TMPDIR` (APFS) instead of an open vault or RAM disk, or
  proceeding when no safe location exists instead of refusing (exit 3).
- Cleanup failures on exit: the draft not being shredded, or editor residue
  (vim `.swp`/`.swo`/`.swn`/`.un~`, nano `file~`) being left behind next to it.
- The RAM disk not being detached on exit, leaving the draft volume mounted.
- `--clipboard` behaving worse than documented: copying without the explicit
  confirmation, or the auto-clear wiping a *different* clipboard the user set
  after the draft (it must only clear if the clipboard still matches the draft).
- File-permission or path-handling issues (e.g. the draft created without `600`,
  or the shred/clean routines touching files outside the draft).
- Privilege or injection issues in the shell code.

Out of scope:

- **Terminal scrollback, OS swap, and `~/.viminfo`** (registers, last yank,
  search history). These are documented limitations the tool cannot scrub —
  it says so on exit. That's the honest premise, not a bug (see the README
  "Scope & limitations").
- **Fallback overwrite on an SSD is not a guarantee.** When `securetrash shred`
  is unavailable, ghostdraft falls back to overwrite + `rm`, which is best-effort
  on SSD/APFS — exactly the limitation securetrash documents. Real erasure comes
  from RAM-disk detach or closing the encrypted vault (crypto-shred).
- **Using `--clipboard` against the documented warning.** Clipboard managers and
  iCloud Universal Clipboard may keep or sync a copy; this is off by default,
  warned about, and confirmed. Auto-clear cannot undo a copy already taken.
- **On-disk safety of `GHOSTDRAFT_DIR`.** If you point the draft at your own
  path, its on-disk safety is on you — that's the documented contract.

## Supported versions

The latest released version receives security fixes. ghostdraft is pre-1.0;
older tags are not maintained.

## Verifying release signatures

Releases ship a `SHA256SUMS` (integrity) and, once release signing is enabled, a
`SHA256SUMS.sig` (authenticity) produced with a dedicated Ed25519 key shared across
Paranoid Tools. The `install.sh` installer verifies the signature and refuses to
install when it cannot (missing `.sig` or no usable `ssh-keygen`) — fail-closed.
`ALLOW_UNSIGNED_LEGACY=1` is the explicit, deliberate downgrade for pre-signing
releases only (integrity check stays). To verify by hand:

```sh
base=https://github.com/Di-kairos/ghostdraft/releases/latest/download
curl -fsSLO "$base/SHA256SUMS"
curl -fsSLO "$base/SHA256SUMS.sig"
printf '%s namespaces="file" %s\n' \
  releases@paranoid-tools \
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U" \
  > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools \
  -n file -s SHA256SUMS.sig < SHA256SUMS
```

**Release-signing public key** (identity `releases@paranoid-tools`, shared across Paranoid Tools):

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U
```

The private key is held offline by the maintainer (inside a securetrash vault) and a
passphraseless copy lives only in the CI signing secret. If the key is ever rotated,
the new public key is published here and in the installer.
