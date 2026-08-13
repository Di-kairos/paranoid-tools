# Security Policy

panic is a security tool — a one-step kill-switch that hides and locks your
machine on demand. Its own correctness matters: a panic command that silently
does less than it claims is a security failure. If you find a vulnerability,
please report it responsibly.

## Reporting a vulnerability

**Do not open a public issue for an exploitable vulnerability.**

Use GitHub's private vulnerability reporting:

1. Go to the repository's **Security** tab → **Report a vulnerability**
   (<https://github.com/Di-kairos/panic/security/advisories/new>).
2. Describe the issue, affected versions, and a reproduction if possible.

You'll get a response as soon as reasonably possible. Once a fix is ready, the
advisory is published and you'll be credited unless you prefer to stay anonymous.

## Scope

In scope:

- Anything that causes `panic now` to **claim it hid/locked when it did not**
  (the whole point is that the reported state matches reality).
- The detach logic: detaching the **wrong** volume, or failing to detach a
  mounted disk image under `/Volumes` that it reports as handled.
- Screen-lock that does not actually lock (the `CGSession -suspend` path, or a
  `PANIC_CGSESSION` override that silently no-ops while reporting success).
- Clipboard clearing that leaves the previous contents recoverable.
- `--hard` paths: cloud-daemon kill (`pkill -x`) hitting an unintended process,
  or `_clear_recent_items` deleting files outside `PANIC_SFL_DIR`.
- Privilege or injection issues in the shell code, including unsafe handling of
  mount points with spaces/newlines.

Out of scope (documented limitations, not bugs — see the README "Scope &
limitations"):

- panic **hides and locks, it does not destroy data or wipe swap**. Plaintext
  fragments may remain in swap until overwritten — use `securetrash` to destroy.
  This is the honest premise, not a vulnerability.
- Data corruption from `detach -force` on a volume with open files — a deliberate
  panic trade-off (hiding fast matters more than a clean unmount). There is no
  confirm by design; the safeguard against accidental firing is the explicit
  `now` verb.
- Volumes that are **not** disk images under `/Volumes` (system images mounted
  elsewhere, physical external disks) are intentionally not touched yet.
- `--hard` clears **global** shared file lists (Recent items); per-app "recents"
  inside applications are not erased — documented as a limit, not a bug.

## Supported versions

The latest released version receives security fixes. panic is pre-1.0 (currently
v0.1.15, work in progress); older tags are not maintained.

## Verifying release signatures

Releases ship a `SHA256SUMS` (integrity) and, once release signing is enabled, a
`SHA256SUMS.sig` (authenticity) produced with a dedicated Ed25519 key shared across
Paranoid Tools. The `install.sh` installer verifies the signature and refuses to
install when it cannot (missing `.sig` or no usable `ssh-keygen`) — fail-closed.
`ALLOW_UNSIGNED_LEGACY=1` is the explicit, deliberate downgrade for pre-signing
releases only (integrity check stays). To verify by hand:

```sh
base=https://github.com/Di-kairos/panic/releases/latest/download
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
