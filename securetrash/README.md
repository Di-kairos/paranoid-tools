**English** · [Русский](README.ru.md)

# SecureTrash

Honest secure file deletion for macOS — no SSD snake oil.

[![CI](https://github.com/Di-kairos/paranoid-tools/actions/workflows/ci-securetrash.yml/badge.svg)](https://github.com/Di-kairos/paranoid-tools/actions/workflows/ci-securetrash.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![platform](https://img.shields.io/badge/platform-macOS%2010.15%2B-blue)
![windows](https://img.shields.io/badge/Windows-beta-orange)
![shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)

Part of the [Paranoid Tools](../README.md) ecosystem.

![SecureTrash demo](demo/demo.gif)

## The problem

When you delete a file and empty the Trash, macOS just marks the space as free.
The data itself stays on disk until something overwrites it. Free tools like
**Disk Drill** or **PhotoRec** happily recover these "deleted" files. The Trash
isn't deletion — it's "out of sight."

## ⚠️ The honest truth about SSDs

> On modern drives, the classic advice to "overwrite the file N times" (`rm -P`,
> the old `srm`, "Secure Empty Trash") does **not** guarantee that your data is
> gone.
>
> The SSD controller decides which physical cells to write to: **wear leveling**
> spreads writes across the drive, **copy-on-write** in APFS writes new versions
> elsewhere, and **TRIM** frees blocks in the background on its own schedule. A
> command to "overwrite this file" never reaches the cells where your bytes
> actually lived.
>
> That's exactly why Apple **removed** `srm` and "Secure Empty Trash" back in
> OS X 10.11 El Capitan — they created a false sense of security.
>
> Most "secure shredders" stay quiet about this and sell overwriting as a
> guarantee. **We don't.**

## What actually protects you

1. **FileVault** — full-disk encryption. The foundation for everything. If the
   drive is encrypted, "deleted" blocks are just ciphertext with no key. This is
   your primary, mandatory layer.
2. **Crypto-shred via `vault`** — keep secrets inside an encrypted container
   (AES-256) from the very start, then destroy the container along with its key.
   With a strong password and no surviving copies/backups/snapshots, the data is
   effectively gone no matter where its blocks physically sit on the SSD.

The vault is **preventive**: it only protects what you create or place inside the
container. It cannot retroactively erase plaintext that already lived on disk
unencrypted — that's what FileVault is for.

## Install

**Recommended — Homebrew** (the formula pins a release tag and verifies its SHA256):

```bash
brew install Di-kairos/tap/securetrash
```

### One-line install via curl

The installer pulls the binary **and `SHA256SUMS` from the release tag** (not from a
moving branch) and verifies the checksum **before** installing — it fails closed on any
mismatch. Quick form:

```bash
curl -fsSL https://github.com/Di-kairos/securetrash/releases/latest/download/install.sh | bash
```

### Verify-then-run (don't trust, verify)

Piping any script into a shell means running code you haven't read. Prefer this — download,
check the checksum, read it, then run:

```bash
base=https://github.com/Di-kairos/securetrash/releases/latest/download
curl -fsSLO "$base/install.sh"
curl -fsSLO "$base/SHA256SUMS"
curl -fsSLO "$base/SHA256SUMS.sig"
printf '%s\n' 'releases@paranoid-tools namespaces="file" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U' > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools -n file -s SHA256SUMS.sig < SHA256SUMS &&   # authenticity: Ed25519, pinned key
shasum -a 256 -c SHA256SUMS --ignore-missing &&   # integrity: verifies install.sh
less install.sh &&                               # read it — then run:
bash install.sh
```

> **Integrity vs authenticity (honest scope).** The checksum proves the downloaded
> binary matches the `SHA256SUMS` published in the **same release** — it catches
> corruption, partial/cached tampering, and stops you running code off the moving `main`
> branch. Authenticity comes from the Ed25519 signature over
> `SHA256SUMS`: the snippet above and `install.sh` both verify it against a key pinned in
> this repo, and the installer fails closed when it can't (see `SECURITY.md`). Another
> channel is **Homebrew**, whose expected hash lives in the tap's git history rather than
> alongside the download. Residual risk: one project key signs all five tools — see the
> ecosystem [threat model](../THREAT-MODEL.md). Pin a specific version with `ST_VERSION=0.5.6` instead of
> `latest` for reproducibility.

### Windows (beta)

A PowerShell port now exists in [`windows/`](windows/README.md). It mirrors the same
honest approach using **BitLocker** (the FileVault equivalent) and crypto-shred via
a BitLocker-encrypted VHDX. On editions without BitLocker, `vault` detects an
installed **VeraCrypt** and tells you to use its own GUI: driving VeraCrypt from the
CLI is deliberately not automated, because its command line takes the password on
argv, where any other process can read it. So VeraCrypt is a manual fallback, not an
automated one. The installer verifies `securetrash.ps1` against `SHA256SUMS` from the
release tag before installing.

```powershell
irm https://github.com/Di-kairos/securetrash/releases/latest/download/install.ps1 | iex
```

> **Beta:** the Windows port is logic-tested (Pester, mocked Windows APIs) but not yet
> validated on real Windows hardware. See [`windows/README.md`](windows/README.md).

### Language

Output is English by default. For Russian, set `ST_LANG=ru` (the tool also honors a
Russian system locale automatically).

## Quickstart

Drop-folder workflow — for everyday deletion:

```bash
securetrash setup          # creates ~/SecureTrash, the sectrash alias, checks FileVault
securetrash check          # honest audit: FileVault + drive type + snapshots + verdict
# drag the files you want gone into ~/SecureTrash
securetrash empty          # empty the folder (overwrite on HDD; on SSD see below)
```

Encrypted container workflow — for secrets (a real guarantee on SSD):

```bash
securetrash vault create   # creates ~/SecureVault.sparsebundle (AES-256), prompts for a password
securetrash vault open      # mounts the container at /Volumes/SecretVault
securetrash vault status    # is the vault currently open or closed?
# work with your secrets inside /Volumes/SecretVault
securetrash vault close     # unmount — the data is encrypted again
securetrash vault destroy   # destroy the container + key (crypto-shred, irreversible)
```

## Commands

| Command | What it does |
|---|---|
| `securetrash check` | Audits FileVault, drive type and local snapshots, gives an honest verdict on guarantees |
| `securetrash setup` | Creates `~/SecureTrash`, installs the `sectrash` alias, warns if FileVault is off |
| `securetrash empty` | Empties `~/SecureTrash` — the plain drop folder, best-effort overwrite; on SSD **not** a guarantee. Not the same as the launcher's "Empty", which is `vault reset` (crypto-shred of the encrypted container) |
| `securetrash shred <path>...` | Deletes a file or folder (best-effort; on SSD **not** a guarantee — see `check`) |
| `securetrash vault create\|open\|close\|destroy\|status` | Encrypted container (AES-256) for crypto-shred |
| `securetrash vault reset [size]` | Empty the vault for real: crypto-shred its contents, then recreate it empty (keeps the container) |
| `securetrash vault destroy-old` | Crypto-shreds a container left set aside by an interrupted `reset` |
| `securetrash version` | Prints the version |

## How it works

The vault is built on **crypto-shred** — erasure by destroying the key.

The container (`sparsebundle`) is encrypted with AES-256 from the moment it's
created: everything you put inside is written to disk as ciphertext. An open
container mounts as a regular volume at `/Volumes/SecretVault`; a closed one is
just an unreadable encrypted image.

When you run `vault destroy`, the container itself is removed along with its
encryption key. Recovery then depends on the strength of your password and on no
copies, backups or snapshots of the container surviving elsewhere. With a strong
password and no leftover copies, the blocks left behind on the SSD are effectively
mathematical noise — recovery tools can read them all day long and find nothing
meaningful.

That's the advantage over overwriting: you **don't need** to reach specific
physical cells (which is impossible on SSDs thanks to wear leveling and TRIM).
Destroying one tiny key renders the entire body of data meaningless at once.

## FAQ

**Can a file be recovered after `shred`?**
On an HDD, `shred`/`empty` makes overwrite passes — best-effort, and it usually
helps, but it is still **not a guarantee** (no control over bad/remapped sectors).
On an SSD it is **not a guarantee** either (wear leveling, COW, TRIM). For secrets,
rely on FileVault + `vault` instead of `shred`.

**Why `vault` instead of overwriting?**
Overwriting tries to scrub specific cells, but on an SSD you have no physical
control over where the controller writes. Crypto-shred sidesteps the problem: the
data is encrypted from the start, and destroying the key makes it unreadable no
matter where the blocks live.

**Does this work without FileVault?**
You won't have the base layer of protection. Without FileVault, "deleted" blocks
on an SSD may be recoverable. Turn FileVault on: System Settings → Privacy &
Security → FileVault. `securetrash check` will verify it.

**Is `vault destroy` safe?**
The operation is **irreversible**: the container and its key are removed for good.
That's why the command asks for explicit confirmation (you have to type `yes`, or
pass `--yes` in scripts). After it runs, recovery depends on your password strength
and on no copies/backups/snapshots of the container remaining elsewhere.

**Does an open vault protect what's inside it?**
Only at rest. While a vault is *mounted*, its plaintext can still leak into swap,
the Spotlight index, Time Machine, or cloud sync. For the highest-value secrets
(a wallet seed phrase, a private key), a crypto-shred vault is the right place to
**store and irreversibly destroy** — but it is not a substitute for offline /
air-gapped handling while the secret is actually open on a running machine.

## Scope & limitations

Honesty is the whole point of this tool, so here is exactly what it does **not** do:

- **Crypto-shred strength is conditional.** `vault destroy` removes the container and
  its key, but the strength of that erasure depends on your **password strength** and on
  **no copies, backups or snapshots** of the container surviving (Time Machine, cloud
  sync, manual copies). A weak password or a leftover backup undoes it.
- **Mounted-vault contents can leak.** While the vault is open, its plaintext contents
  can be indexed or copied by **Spotlight**, written to **swap**, captured by **Time
  Machine**, or pushed by **cloud sync**. SecureTrash does not wipe those locations.
- **Overwriting is best-effort, not a guarantee.** On SSD/APFS it gives no erasure
  guarantee (wear leveling, COW, TRIM); even on HDD it cannot reach bad/remapped sectors.
- **FileVault is the foundation.** Without full-disk encryption, "deleted" blocks may
  still be recoverable. The tool warns you, but it cannot enable FileVault for you.

## Disclaimer

This software is provided "as is," without warranty of any kind (see [LICENSE](LICENSE)).
Security depends on your environment:

- Make sure FileVault is on: `fdesetup status` (should read `FileVault is On.`).
- The `vault` is a **preventive** measure: it protects data created inside it and
  does not retroactively erase anything that already sat on disk unencrypted.
- On SSD/APFS, overwriting individual files offers no erasure guarantee — that's a
  fundamental property of the technology, not a limitation of this tool.
