# Paranoid Tools — usage guide

Five privacy CLIs for macOS. Each does **one** thing and tells you plainly where the
guarantee ends — it won't promise "100% unrecoverable" where an SSD or macOS can leave a copy.

> Russian version: [ИНСТРУКЦИЯ.md](ИНСТРУКЦИЯ.md).

## Install

```bash
git clone https://github.com/Di-kairos/paranoid-tools
cd paranoid-tools
bash install.sh
```

Installs all five tools plus the `paranoid` launcher into `~/.local/bin` (already on your
PATH). Remove everything: `bash install.sh --uninstall`.

On a fresh clone each tool is pulled from its signed release and verified (Ed25519 signature
+ checksum) before anything runs.

## Updating

There is no `update` command — updating means **re-running the installer**. It pulls the
latest signed release of each tool and overwrites the binary in place:

```bash
cd paranoid-tools
git pull            # refresh the clone (launcher + installer)
bash install.sh     # reinstall all tools at their latest signed releases
```

Check a version: `securetrash version` (or `--version` on any tool).

**Note:** if a tool's runtime behavior changed in the update (e.g. `securetrash vault` now
mounts the volume visibly in Finder), an already-open session is still running the old code.
Reopen it: `securetrash vault close` → `securetrash vault open`.

## Start here — run `paranoid`

The main entry point. One command opens a status dashboard and a menu over all five tools:

```bash
paranoid
```

At the top — a live status line (refreshed every time you return to the menu):

```
Vault:       ● OPEN (/Volumes/SecretVault)   ⚠ at risk while open
FileVault:   ● ON
vaultwatch:  ● active
```

- **Vault** — open or closed. An open vault is flagged "at risk": while it is mounted,
  the data is readable by anyone at your Mac.
- **FileVault** — whether system disk encryption is on.
- **vaultwatch** — whether the open vault is currently guarded (`active`) or there are
  no sessions (`idle`).

Below it — the menu (pick by number):

```
1) Status        — full read-only check (what actually protects you on your hardware)
2) 🔒 PANIC NOW  — hide & lock everything (instant, no confirmation)
3) Vault ▸       — open / close / create, empty, destroy, watch
4) Notepad ▸     — ghostdraft: note (write/edit/copy, vanishes) / show clipboard
5) Secrets ▸     — seedsplit: split / combine
0) Quit
```

The menu is grouped into submenus; **PANIC NOW** stays at the top level so it's one keypress
away. Each submenu has its own `0) Back`.

**3) Vault ▸**
```
1) Open / Close / Create  — label follows the current state
2) Empty                  — crypto-shred everything, keep a fresh empty vault
3) Destroy                — remove the vault and its contents (irreversible)
4) Watch                  — guard / stop the open vault (vaultwatch)
0) Back
```
Watch lives here because vaultwatch's whole job is guarding the *open* vault.

**4) Notepad ▸** — `1) note` (write / edit / copy, vanishes on exit — clipboard auto-clears
~20s), `2) show clipboard` (ghostdraft).

**5) Secrets ▸** — `1) split`, `2) combine` (seedsplit).

The launcher holds no secrets and adds no crypto of its own: it runs the same five signed
CLIs and shows their output verbatim — every caveat and `check` verdict included. Anything
the menu does is available directly via the commands below.

---

## The tools

### 1. securetrash — wipe files, and the encrypted vault

**When:** you need to delete a sensitive file for real, or keep secrets in an encrypted
container.

```bash
securetrash check              # honest verdict: which guarantees are real on your disk
securetrash vault create [size] # create the encrypted vault (size = ceiling, optional)
securetrash vault open         # open (mount) the vault
securetrash vault close        # close the vault
securetrash vault reset [size] # crypto-shred everything, recreate a fresh EMPTY vault
securetrash vault destroy      # remove the vault and its contents (irreversible)
securetrash vault status       # is the vault present / open?
securetrash shred ~/secret.pdf # wipe a single file

# Wipe several at once — list paths, pass a glob, or a whole folder (one confirmation for
# the entire list):
securetrash shred a.pdf b.docx c.key   # an explicit list of files
securetrash shred ~/Out/*.pdf          # every .pdf in Out (the shell expands the glob)
securetrash shred ~/Out/*              # every file in Out, keeping the folder (skips dotfiles)
securetrash shred ~/Out                # the whole Out folder, recursively
```

**Bottom line:** on an SSD, overwriting (`rm -P`) gives no guarantee. The real protection is
keeping secrets inside the `vault` (it's encrypted), where "delete" means destroying the key.
That's exactly what `check` explains for your hardware. `securetrash shred` is best-effort on
SSD, not a guarantee — for a guarantee, the files should have lived in a vault you then
`destroy`.

**The open vault in Finder.** After `vault open` the volume shows up like any disk — in the
Finder sidebar (Locations) and on the desktop, and its window opens by itself. Closed the
window? The volume is still mounted: reopen it from the sidebar, or run `open
/Volumes/SecretVault`, or in Finder press `Cmd+Shift+G` → `/Volumes/SecretVault`. **Ejecting**
the volume from Finder unmounts it — the same as `vault close`, and your secrets are encrypted
at rest again. Want maximum privacy (the volume kept off the sidebar and desktop)? Open with
`ST_VAULT_HIDDEN=1 securetrash vault open`; then the only way to bring the window back is the
`open` command.

**Empty the vault for sure.** `securetrash vault reset` (Vault ▸ → 2, Empty) crypto-shreds the
current container — it throws the key away — and recreates a fresh, **empty** vault in its place.
Why not just delete the files inside? Wiping files in place inside a live vault on an SSD is only
best-effort: the same key still decrypts whatever blocks are left behind. The one real
irreversibility guarantee is destroying the container's key, so "empty" literally means
*destroy + recreate*. You're left with a working (empty) vault, ready to use again. This covers
the everyday workflow: accumulate files → wipe everything for certain → keep working.
securetrash asks you to type `yes` and set a password for the fresh vault.

**Vault size (a ceiling, not reserved space).** When the launcher creates a vault — or empties
one and recreates it — it asks for a size. This is only an upper limit: the container
(sparsebundle on macOS, VHDX on Windows) is thin and grows as you add files, so picking a large
cap costs you nothing up front. Press Enter for the default (1 GB). On macOS the format is like
`5g` / `500m`; on Windows it's a number of megabytes (e.g. `5120`).

**Delete the vault entirely.** `securetrash vault destroy` removes the container
(`~/SecureVault.sparsebundle`) and crypto-shreds it — the key is gone, the icon disappears
from the sidebar and desktop. **Irreversible: everything inside is gone for good.** Copy out
anything you need first, and close any Finder windows or apps holding the volume open — if it
can't unmount, `destroy` refuses and keeps the container intact.

### 2. vaultwatch — guard of an open vault

**When:** you opened a vault and don't want it sitting open and leaking into Spotlight, Time
Machine, or the cloud. Usually it runs itself through securetrash's hooks.

```bash
vaultwatch install-hooks                       # one-time: wire it to vault open/close
vaultwatch start --ttl 30m /Volumes/MyVault    # manual: guard + auto-close after 30 min
vaultwatch stop /Volumes/MyVault               # drop the guard and print a report
vaultwatch status                              # which vaults are guarded right now
```

**Bottom line:** after `install-hooks` you can forget about it — `securetrash vault open`
raises the guard, `close` drops it.

### 3. panic — hide everything, now

**When:** someone walks up and you need everything off the screen instantly.

```bash
panic now            # close vaults, unmount images, clear the clipboard, lock the screen
panic now --hard     # the same + kill cloud daemons
panic hotkey install # bind it to a global hotkey (cmd + alt - p), see panic's README
```

**Bottom line:** `panic` hides and locks, but doesn't destroy data. For real speed, bind it to
a global hotkey with `panic hotkey`.

### 4. ghostdraft — a draft that leaves no disk trace

**When:** you need to jot down a secret (a password, a seed, a note) that must not land on
disk.

```bash
ghostdraft new              # ephemeral draft; on exit — shred + clean the editor's traces
ghostdraft new --clipboard  # the same + put the result on the clipboard (with a prompt)
pbpaste | ghostdraft pipe   # show the clipboard in the terminal, writing nothing to disk
```

**First decide which job you're doing — these are two different things:**

- **Write a secret → hand it over / paste it once → let it vanish.** That's `ghostdraft new`.
  The file lives inside the open `vault` (or on a RAM disk if no vault is open) and is shredded
  when you leave the editor. Writing keys here "to keep" makes no sense — they're gone after
  you exit. To grab the result before it vanishes, see `--clipboard` below.
- **Keep keys and copy them into apps over and over.** That's *not* `ghostdraft new` (it
  shreds on exit). Make a plain file **inside the open vault** — `/Volumes/SecretVault/keys.txt`
  — edit and copy from it as needed, and `securetrash vault close` re-encrypts it on disk.
  That's your persistent, encrypted store.

**Copy a secret once (via the launcher):**

1. `paranoid` → `4` (Notepad) → `1` (note).
2. The editor opens (`vim` with soft wrap — a long key won't run off the edge or get broken by
   inserted newlines). Type the secret, then exit. **How to quit vim (reliable way):** press
   **`Esc`**, then type **`ZZ`** to save & exit, or **`ZQ`** to quit **without** saving (discard
   the draft). The colon commands **`:wq`** (save) / **`:q!`** (discard) also work — `Esc`, then
   colon, the command, `Enter`. An always-visible hint line is shown at the bottom.
   > ⚠️ The **F2/F3** keys (save/discard) are also mapped, but **some terminals (e.g. Warp)
   > intercept them** before they reach vim — so rely on `Esc` → `ZZ`/`ZQ`, not the F-keys.
3. ghostdraft asks to confirm copying to the clipboard — answer `yes`.
4. Paste the secret into the app you need (`Cmd+V`).
5. After ~20 seconds the clipboard wipes itself — but only if you haven't overwritten it in the
   meantime (copied something else). The draft itself is already shredded by then.

The same directly, without the menu: `ghostdraft new --clipboard`.

**Bottom line:** ghostdraft makes no "zero traces" claim where the OS itself leaves them (swap,
terminal scrollback, and for `vim`, `~/.viminfo`) — it lists them honestly on exit. The default
editor `vim -i NONE` disables `~/.viminfo` and maps **F2** (save & exit) / **F3** (discard) so
new users are never trapped in `-- INSERT --`; on Windows the default editor is notepad. Set your
own `$EDITOR` and these mappings don't apply — your editor is left untouched. The clipboard is
dangerous by nature (clipboard
managers, iCloud Universal Clipboard), which is why copying is explicit, confirmed, and
auto-wiped.

### 5. seedsplit — split a secret into shares (Shamir's scheme)

**When:** you have a seed phrase, master password, or private key, and you don't want a single
carrier (a slip of paper, a flash drive, a backup) to be one point of failure. You split it
into N parts so that any **T** of them rebuild the secret, while T−1 reveal **nothing**.

```bash
# Split a seed into 5 shares, threshold 3 (any 3 of 5 restore it). Secret via stdin:
printf '%s' "legal winner thank year wave ..." | seedsplit split -n 5 -t 3
# → 5 lines like SSS1-3-1-<hex>-<chk>. Spread them across different places.

# Rebuild from any 3 shares (one share per line):
seedsplit combine < my-3-shares.txt
# or: pbpaste | seedsplit combine
```

**Bottom line:**
- The secret is fed via **stdin or `--file`**, never as an argument (an argument is visible in
  `ps`).
- Each share carries a checksum — a typo while entering a share gets caught.
- Shares from different secrets, or corrupted ones, make `combine` refuse honestly instead of
  returning garbage (an integrity check is built in).
- ⚠️ No SLIP-39 / hardware-wallet compatibility yet — this is its own format. Shares are exactly
  as safe as how well you store and separate them.

---

## A typical session

```bash
securetrash vault open    # opened the vault — vaultwatch raised its guard automatically
ghostdraft new            # jotted a secret; it landed inside the vault, no trace outside
# ...working...
panic now                 # someone walked up — closed everything and locked the screen
```

## Tips

- Any tool with no arguments, or an unknown command, prints its own help.
- Run `securetrash check` first: it explains what actually protects you on your hardware and
  what doesn't.
- Don't remember the commands? Open `paranoid` and work through the menu.
