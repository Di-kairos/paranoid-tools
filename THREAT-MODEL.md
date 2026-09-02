# Threat model — is this for you?

**English** · [Русский](THREAT-MODEL.ru.md)

Paranoid Tools is not a password manager. It's a small, auditable, local toolkit for a
handful of high-value secrets — a seed phrase, a private key, a recovery code — with no
cloud, no telemetry, and no security promises it can't keep.

It doesn't replace your password manager, your disk encryption, or your anonymity
setup. It closes the gap between them: the moment you need to write a secret down,
store it, keep it guarded while you work, hide it fast, and back it up in pieces.

## Use it when

- You hold a few secrets whose leak you can't undo — crypto seed phrases, master keys,
  recovery codes.
- You want them on your own disk, not in anyone's cloud.
- You can keep one strong password in your head (the vault has no reset).
- You're willing to read what a tool does *not* do — every tool here states it plainly.

## Don't use it when

- **You need a password manager.** Hundreds of logins, browser autofill, cross-device
  sync — that's 1Password, Bitwarden, or KeePassXC. Paranoid Tools handles a few
  high-value secrets, not your everyday credentials.
- **You need anonymity.** Nothing here hides who you are or where you connect from.
  That's Tor, Tails, Qubes territory. See the [manifesto](MANIFEST.md) on privacy vs
  anonymity — the difference matters.
- **You expect miracle deletion on SSD.** `securetrash` will tell you itself: overwriting
  is not a guarantee on SSD/APFS. The real answer is encryption plus crypto-shred, and
  that's what the vault does.
- **Your machine is already compromised.** No local tool survives a keylogger.

## The right tool for the job

| Task | Better fit |
|------|------------|
| All your passwords, every day | 1Password / Bitwarden / KeePassXC |
| A few high-value local secrets | **Paranoid Tools** |
| An encrypted folder in the cloud | Cryptomator |
| Whole-disk protection | FileVault / BitLocker (turn it on — `securetrash check` insists) |
| Anonymity, threat-model OS | Tor Browser / Tails / Qubes |

Several of these compose: FileVault under everything, a password manager for daily
logins, Paranoid Tools for the secrets that are too valuable to live in either.

## What it protects against

- **Secrets at rest.** The vault is a natively encrypted container (AES-256 sparsebundle
  on macOS, BitLocker VHDX on Windows). Closed, it's ciphertext; without the password
  there is nothing to find.
- **Leftover drafts.** `ghostdraft` writes inside the open vault or a RAM disk on macOS —
  no copy in your folders, editor history, or unencrypted temp files. (The Windows port
  falls back to an on-disk temp file when no vault is open, and warns you it did.)
- **Recoverable "deleted" files.** `vault reset` destroys data by destroying the key
  (crypto-shred) instead of pretending an overwrite worked on SSD.
- **A lost backup revealing the secret.** `seedsplit` splits it into Shamir shares:
  fewer than the threshold reveal nothing about the secret's content (a share does
  expose metadata — format, threshold, share number, and the secret's approximate
  length — but not a byte of the payload).
- **The walk-away window.** `vaultwatch` narrows the leak channels it can control
  (Spotlight indexing, Time Machine) while the vault is open, honestly reports the ones
  it can't (running cloud-sync clients), and can close an idle vault on a timer (it
  won't force-detach files in use).
  `panic` detaches mounted disk images, clears the clipboard, and locks the screen — one
  command, or the GUI hotkey.

## What it reduces, honestly

- **Exposure while the vault is open.** An open vault is readable by anyone at your
  machine — the tools shrink the window and the channels, they can't remove it. The GUI
  and the launcher flag an open vault as *at risk* the entire time, on purpose.
- **Traces in system caches.** Some channels (swap, terminal scrollback, cloud copies
  already synced) are outside a userland tool's reach. `ghostdraft` and `vaultwatch`
  name these exceptions in their output instead of staying quiet.

## What it does NOT protect against

- **Malware on your machine.** A keylogger reads the vault password as you type it.
- **Memory forensics while the vault is open.** The key is in RAM; that's how disk
  encryption works.
- **Copies made before you started.** If the secret ever touched a cloud note or a chat,
  that copy is out of scope.
- **Snapshots and backups holding an older copy.** A local APFS snapshot (Time Machine,
  Carbon Copy Cloner, Arq) or a Volume Shadow Copy taken while a file was still outside
  the vault holds a full copy of it. `shred` cannot reach inside one, and a single file
  cannot be removed from a snapshot — only the whole snapshot. `securetrash check` reports
  how many exist; the defence is to create secrets inside the vault, where a snapshot only
  ever captures ciphertext. See the "putting files into the vault" section of `GUIDE.md`.
- **Physical coercion.** `panic` hides and locks — it does not wipe, and it won't make
  anyone un-see what they already saw.
- **Network surveillance or attribution.** The tools themselves never touch the network;
  the launcher's opt-in update check contacts GitHub for a version number, nothing more.
- **A weak vault password.** Crypto-shred and Shamir math don't help against
  `password123`.

## Where Windows copies your text

Windows keeps helpful copies of things, in places nobody thinks about when typing a seed
phrase. This is the map for the Windows port — what each channel is, and what the tools do
about it. Where a tool cannot win, it says so rather than staying quiet.

| Channel | What lands there | What we do |
|---------|------------------|------------|
| **Clipboard history** (Win+V) | Every copy you made, not just the last one. **Cloud Clipboard** syncs them to your Microsoft account and other devices. | `panic now` clears the history through the documented WinRT call, and names what it cannot reach: pinned items, and anything already synced off this machine. `ghostdraft --clipboard` warns before it copies. |
| **Notepad tabs** (`TabState`) | The full text of *unsaved* Notepad tabs, on disk, surviving reboots. A standard forensic artifact with off-the-shelf parsers. | `ghostdraft new` no longer uses an editor at all by default — the draft is typed into the console and never reaches disk. With `$EDITOR` set to Notepad it warns by name. Nothing deletes those files: they hold your other notes too. `panic status` counts them. |
| **Volume Shadow Copies** (VSS) | A full copy of any file that was outside the vault when a shadow copy was taken. `shred` cannot reach inside one; a single file cannot be removed from a shadow copy, only the whole copy. | `securetrash check` and the `vaultwatch` session report count them — tri-state, so "could not read" never prints as "none". Files created *inside* the vault are safe: a shadow copy captures the container as ciphertext. |
| **MFT-resident data** | A file under roughly 700 bytes — the size of a seed phrase or a key — has no data blocks of its own on NTFS: it lives inside its MFT record. `cipher /w` overwrites free clusters and never the MFT. | Named by `securetrash check` and after every `shred`. No userland tool reaches in there; the answer is to create the secret inside the vault. |
| **Pagefile** (swap) | Plaintext paged out of RAM while you worked. | Not addressed by any of these tools, and said so in every relevant output. Encrypting the pagefile is a system setting, not something a userland tool should silently flip. |
| **Windows Search index** | Names and content of files indexed while the vault is open. | `vaultwatch` sets `NotContentIndexed` on the mounted volume for the session and restores it afterwards — including when the vault is ejected past `vaultwatch stop`. It stops *future* indexing, not what was already indexed. |
| **Recent items and jump lists** | Paths and titles of files you opened — metadata, not content. | `panic now --hard` clears both. |
| **Console scrollback** | Whatever you typed or displayed, for as long as the window lives (and longer, if your terminal persists it). | `ghostdraft` clears the screen after a console draft and names scrollback as outside its reach; `pipe` says the same. |

Two of these — the pagefile and whatever a cloud already synced — are outside a userland
tool's reach entirely. They are on this page instead of being quietly omitted.

## Verify, don't trust

Every tool is a single readable file — audit it before you run it. Installs are
checksum- and signature-verified (Ed25519).

**One signing key covers all five tools, and that is a real limitation.** The same
Ed25519 key signs every release, its private half lives in GitHub Actions secrets, and
the public half is pinned inside the installers. So whoever obtains that key — or lands
a change in any one repository's `release.yml` — can sign a release the installers will
accept for the *whole* ecosystem, not just one tool. There is no in-band revocation
either: a compromised key is replaced by publishing a new one here and in the
installers, which only helps people who reinstall afterwards. If that matters for your
case: pin an exact version, and check `SHA256SUMS` yourself with `verify-releases.sh`
rather than trusting the installer to do it for you. Each tool's README carries its own
*Scope & limitations* with the fine print of that specific tool; this page is the map,
those are the territory.

*Free / open source · MIT · [manifesto](MANIFEST.md) · [usage guide](GUIDE.md)*
