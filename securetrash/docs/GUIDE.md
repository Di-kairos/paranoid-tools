**English** · [Русский](GUIDE.ru.md)

# SecureTrash — guide

A friendly walkthrough of how to use SecureTrash and what happens under the hood.
If you just want the quickstart, it's in the [README](../README.md). This goes
deeper.

## The idea: a Trash folder you drop files into

The core everyday workflow is simple: you have a `~/SecureTrash` folder. Anything
that lands there is considered "to be deleted." Whenever you like, you empty it
with a single command.

### Step 1. Setup

```bash
securetrash setup
```

This command:

- creates the `~/SecureTrash` folder;
- adds a `sectrash` alias to `~/.zshrc` (a shorthand for `securetrash empty`);
- checks FileVault and warns you if it's off.

After that, restart your terminal so the alias gets picked up.

### Step 2. Check your environment

```bash
securetrash check
```

This is an honest audit. It tells you:

- whether **FileVault** is on (the primary layer of protection);
- what kind of drive you have — **SSD/APFS** or **HDD**;
- the verdict: what you can actually rely on.

Run `check` at least once so you understand your situation. If FileVault is off,
turn it on before you count on any "secure deletion."

### Step 3. Drop files in and empty

Drag everything you want gone into `~/SecureTrash` (via Finder or `mv`). When
you're ready:

```bash
securetrash empty
# or the short alias:
sectrash
```

The command asks for confirmation (you type `yes`), then empties the folder.

## Honestly, what "secure" means here

Guides like this used to claim that overwriting a file multiple times makes
recovery "practically impossible." **That isn't true for SSDs.**

On modern SSD/APFS, overwriting an individual file does **not** guarantee
erasure:

- **wear leveling** — the controller distributes writes across physical cells, so
  a "overwrite this file" command never hits the original cells;
- **copy-on-write** in APFS — changes are written to a new location and the old
  copy remains;
- **TRIM** — blocks are freed in the background, on the drive's schedule, not
  yours.

That's why Apple removed `srm` and "Secure Empty Trash" back in OS X 10.11.

What this means in practice:

- **On an HDD**, overwriting (several passes) is best-effort and usually helps —
  but it is still **not a guarantee** (no control over bad/remapped sectors).
- **On an SSD**, overwriting is "better than nothing" but **not a guarantee**.
  Real guarantees come from only two mechanisms:
  1. **FileVault** — full-disk encryption (turn it on, no exceptions);
  2. **`securetrash vault`** — an encrypted container with crypto-shred (for secrets).

`securetrash empty` and `securetrash shred` say this honestly in their output,
depending on your drive type.

## Under the hood: what `securetrash empty` does

If you want to understand the mechanics, the manual equivalent of
`securetrash empty` is:

```bash
chmod -R u+w ~/SecureTrash/*     # remove write protection so the files can be deleted
rm -rfP ~/SecureTrash/*          # delete with an overwrite attempt (-P)
```

The `-P` flag on `rm` makes overwrite passes before deleting. Be honest
with yourself about it: **on an SSD this flag does no harm but gives no
guarantee** — for the reasons above (wear leveling, COW, TRIM). On an HDD it is
best-effort and usually helps, but still cannot reach bad/remapped sectors, so it
is not an absolute guarantee either.

In other words, `-P` is "best effort," not magic. Don't confuse effort with a
guarantee.

## The real guarantee for secrets: vault

If you need to genuinely get rid of sensitive data on an SSD, don't drop it into a
regular folder and hope overwriting will save you. Use an encrypted container from
the start:

```bash
securetrash vault create    # ~/SecureVault.sparsebundle, AES-256, prompts for a password
securetrash vault open      # mounts at /Volumes/SecretVault
# add and edit secrets directly in /Volumes/SecretVault
securetrash vault close     # unmount — only ciphertext remains on disk
securetrash vault destroy   # remove the container and key (crypto-shred)
```

Why this works where overwriting is helpless: the data sits on disk encrypted from
the very first second. By destroying the key (`destroy`), you turn the entire body
of data into meaningless noise — no matter which physical SSD cells it's smeared
across. The catch: this holds only as long as the **password was strong** and
**no copy, backup or snapshot** of the container survives elsewhere (Time Machine,
cloud sync, manual copies). And while the vault is **open**, its plaintext contents
can still leak via Spotlight, swap or Time Machine — SecureTrash does not wipe those.

Remember the preventive nature of this: the vault only protects what was created
or moved **inside** it. A file that already sat on disk in the clear is not
retroactively erased by creating a container — for that case, only FileVault works
as the underlying layer.

## Quick checklist

- [ ] FileVault is on (`fdesetup status` → `FileVault is On.`)
- [ ] You ran `securetrash setup` and `securetrash check`
- [ ] Everyday junk goes through `~/SecureTrash` + `securetrash empty`
- [ ] Secrets go only through `securetrash vault`, with a final `destroy`
