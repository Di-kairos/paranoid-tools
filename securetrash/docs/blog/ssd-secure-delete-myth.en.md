# Why overwriting files doesn't work on SSDs

*The story every "secure delete" tool tells you — and why it's a lie on modern hardware.*

---

## The promise

Open almost any "secure file shredder" and you'll read the same pitch: deleting
a file only removes its directory entry; the bytes stay on disk until something
reuses them. So the tool *overwrites* the file — with zeros, with random data,
sometimes 3, 7, or 35 times — and now the data is "gone forever."

On a spinning hard drive, in 2005, that was roughly true. On the SSD in your
laptop today, it ranges from *unreliable* to *meaningless*. Here's why.

## How overwriting used to work

A hard disk drive (HDD) maps each logical block to a fixed physical location.
Logical block 12345 is *this* magnetic spot on *this* platter. When you tell the
drive to write zeros to block 12345, the head goes to that exact spot and
flips the magnetization. The old data is physically gone, replaced in place.
(Even HDDs reassign defective sectors and keep hidden areas, so overwriting
misses the odd remapped block — but the in-place model holds for normal sectors.)

This is why classic tools like `shred`, `rm -P`, or the old Gutmann 35-pass
method could make a real claim: overwrite the block and the original is
destroyed. (Modern research showed even a *single* pass is enough on HDDs — the
fancy multi-pass methods are folklore — but the underlying model was sound.)

The model rests on one assumption: **logical block address = fixed physical
location, and writes happen in place.**

SSDs throw that assumption out.

## How SSDs actually store data

A solid-state drive can't overwrite in place. NAND flash is written in *pages*
(kilobytes) but can only be *erased* in much larger *blocks* — from hundreds of
KB to many MB, depending on the generation. A page must be erased before it can
be rewritten, and each cell wears out after a limited number of erase cycles.
Erasing in place on every write would be slow and would wear the drive out fast.

So every SSD hides a translation layer — the **Flash Translation Layer (FTL)** —
between the logical blocks your OS sees and the physical cells. The FTL does
several things that quietly defeat overwriting:

- **Wear leveling.** To spread wear evenly, the FTL constantly moves data to
  fresh cells. "Overwrite logical block 12345" almost never lands on the same
  physical cell as the original. Your overwrite goes to a *new* page; the old
  page is just marked stale and sits there, still recoverable via the controller
  or raw NAND access, until garbage collection eventually erases it — on the
  controller's schedule, not yours.

- **Copy-on-write & remapping.** Updating part of a page means the FTL writes a
  whole new page elsewhere and remaps the pointer. The old version remains in
  flash.

- **Over-provisioning.** SSDs ship with more physical flash than they advertise,
  reserved for the FTL — anywhere from a few percent to tens of percent (common
  nominal levels are ~7%, 14%, 28%, but it's device-specific). Your OS *cannot
  address* this hidden area at all — yet copies of your data routinely live
  there. No overwrite command can reach it.

- **Bad-block remapping.** When a cell degrades, the FTL retires it and copies
  the data to a spare. The retired cell may still hold readable data and is now
  permanently outside your reach.

The result: when you "overwrite" a file on an SSD, you are writing *new* data to
*some* physical cells while one or more readable copies of the original sit in
cells you cannot name, cannot address, and cannot command. You have no guarantee
of destruction. You often have a near-guarantee of *survival*, at least for a
while.

## "But what about TRIM?"

TRIM is the command that lets the OS tell the SSD "these blocks are free now."
It helps performance and *can* lead to the data being erased during garbage
collection — but:

- TRIM is asynchronous. Erasure happens whenever the controller decides, which
  could be seconds or hours later, or not before someone images the drive.
- TRIM behavior is not uniform. On SATA a drive may be non-deterministic,
  Deterministic Read After TRIM (DRAT), or Deterministic Read Zero After TRIM
  (RZAT); NVMe exposes its own deallocate-read behavior. You can't portably rely
  on it.
- TRIM gives the host no guarantee that hidden stale copies, the over-provisioned
  area, or remapped bad blocks have actually been erased.

TRIM is a *best-effort cleanup*, not a *secure-erase guarantee*. Treating it as
one is exactly the mistake.

## So what actually works?

Two honest answers.

**1. Hardware sanitize.** ATA Sanitize and NVMe Sanitize (and a correctly
implemented drive secure-erase) ask the *controller itself* to wipe the flash
behind the FTL, including over-provisioned cells that hold user data. When
implemented correctly they work — but implementations have historically been
buggy or outright lied about completion (the UCSD FAST'11 study found drives
that reported success while all data survived), they wipe the *whole drive* (not
one file), and they're awkward to invoke safely. Useful for decommissioning a
disk, useless for "shred this one file now."

**2. Encryption + crypto-shred.** This is the one that scales to a single file
and survives all the FTL trickery — *provided* the data was encrypted before it
was ever written, the key is unique and strong, and every copy of the key is
actually destroyed. If your data only ever exists as ciphertext, then the
physical bytes scattered across wear-leveled cells, over-provisioning, and
retired blocks are all **useless noise without the key**. Destroy every copy of
the key and the ciphertext — addressable or not — becomes permanently
undecryptable. You don't need to reach the hidden cells, because what's in them
was never readable to begin with.

The catch is the word *every*: a key recoverable from a backup, a keychain, a
container header/keybag still sitting in stale NAND, or a known passphrase
breaks the guarantee — as does plaintext that leaked to swap, temp, or cache
before encryption. NIST SP 800-88r2 spells these out.

This is why full-disk encryption (FileVault, BitLocker, LUKS) is the real
baseline for a lost or decommissioned *device*, and why a per-file or
per-container key — destroyed deliberately — is the real "shred a file" answer
on a live system.

## What securetrash does about it

[securetrash](https://github.com/Di-kairos/securetrash) is a small, dependency-free
CLI built around this honesty:

- It **won't pretend** that overwriting shreds an SSD. Its own output says
  overwriting is best-effort, not a guarantee.
- Its core protection is **crypto-shred**: you keep sensitive files in an
  encrypted AES-256 vault (a macOS sparsebundle). `vault destroy` removes the
  encrypted container and the key material its contents depend on — so, as long
  as the passphrase isn't recoverable from a backup or keychain, the bands
  become unrecoverable noise regardless of what the flash controller did with the
  physical bytes.
- It's presented as **preventive**: set up the vault *before* you have secrets to
  protect, so they never touch unencrypted flash in the first place.

```bash
brew install Di-kairos/tap/securetrash
```

## Takeaways

- On an SSD, "overwrite N times to securely delete a file" is **not a guarantee**
  and often not even close.
- The FTL, wear leveling, over-provisioning, and remapping put readable copies of
  your data in places no overwrite command can reach.
- Real protection is **encryption + crypto-shred** (per file) or **hardware
  sanitize** (whole drive) — not `rm -P`.
- A security tool should tell you this instead of selling you a comforting myth.

*securetrash is MIT-licensed and readable end to end:
<https://github.com/Di-kairos/securetrash>*
