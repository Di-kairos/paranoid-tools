# SecureTrash — Windows port (BETA)

> Honest secure deletion for Windows. Mirror of the shipped macOS version.

## ⚠️ BETA disclaimer — read this first

This Windows port is **BETA**. Its **logic is tested via Pester** (dispatch, branching,
i18n, honest verdicts — all Windows-specific commands are mocked, on both PowerShell 7 and
Windows PowerShell 5.1), and the BitLocker VHDX vault — create, open, guard, close, reset,
destroy, a wrong password — has been **walked by hand on one Windows 11 Pro machine**. One
machine is not a field: other editions, other disks and the VeraCrypt fallback remain
**unverified**.

- Do not trust it with irreplaceable secrets until you have tested it yourself on a
  throwaway container.
- Contributions with a test pass on **other hardware** (Windows 10, Enterprise/Education,
  VeraCrypt fallback) are very welcome — that is what takes this out of beta.

## The honesty principle (same as macOS)

Overwriting (`cipher /w`, SDelete) on an **SSD gives no guarantees** — wear leveling, TRIM,
and copy-on-write (ReFS) mean the old blocks may survive. Real protection is:

1. **BitLocker** — full-disk encryption, so deleted data is encrypted at rest.
2. **crypto-shred** — keep secrets inside an encrypted container, then destroy the
   container + key. Recovery then depends on the password/key strength and on the key
   never having been copied elsewhere — not on overwriting the disk. Strong, uncopied
   key destroyed → recovery is computationally infeasible (no absolute guarantee).

## Install (verify-then-run)

Piping an installer straight into `iex` runs code you have not read. Download it with the
signed manifest, check it, read it, and only then run it:

```powershell
$base = "https://github.com/Di-kairos/paranoid-tools/releases/download/securetrash-v0.5.8"
irm "$base/install.ps1"    -OutFile install.ps1
irm "$base/SHA256SUMS"     -OutFile SHA256SUMS
irm "$base/SHA256SUMS.sig" -OutFile SHA256SUMS.sig
# authenticity: the Ed25519 signature over the manifest, against the key pinned in this repo
'releases@paranoid-tools namespaces="file" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9DVd0vNOwa5hyr9gShaCWoNOVnUsrdHVO/WE0wCZkT' | Set-Content allowed_signers -Encoding ascii
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools -n file -s SHA256SUMS.sig < SHA256SUMS
# integrity: install.ps1's own hash must appear in that manifest
(Get-FileHash install.ps1 -Algorithm SHA256).Hash.ToLower() -eq
  ((Select-String -Path SHA256SUMS -Pattern 'install\.ps1$').Line -split '\s+')[0]
# read it, then:
pwsh -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

The installer pulls `securetrash.ps1` **and `SHA256SUMS` from the release tag** (not a
moving branch) and verifies the checksum before installing — it aborts on any mismatch.
It downloads `securetrash.ps1` to `%LOCALAPPDATA%\Programs\securetrash\`, writes a
`securetrash.cmd` shim, and adds that folder to your user PATH. Open a new terminal, then:

```powershell
securetrash check
securetrash setup
```

Requires **PowerShell 5.1+** (Windows PowerShell or PowerShell 7).

## Commands

| Command | What it does |
|---|---|
| `check` | Audit the environment — BitLocker status (read without administrator rights, in a millisecond), SSD/HDD verdict, vault availability, whether this console can run the vault, honest summary. Prints the BETA banner. |
| `setup` | Create `%USERPROFILE%\SecureTrash` and warn if BitLocker is off. Idempotent. |
| `empty` | Empty `%USERPROFILE%\SecureTrash` (keeps the folder) + honest disk note. |
| `shred <path>...` | Delete file(s)/folder(s), best-effort — on SSD **not** a guarantee + honest disk note. |
| `vault create\|open\|close\|destroy` | Encrypted container (crypto-shred). |
| `vault reset [size]` | Empty the vault for real: crypto-shred its contents, then recreate it empty (keeps the container). |
| `vault status` | Read-only: is the container open (and where it is mounted), closed, or missing. |
| `vault destroy-old` | Crypto-shreds a container left set aside by an interrupted `reset`. |
| `version` | `securetrash 0.5.8 (Windows, beta)`. |

Flags: `--yes` skips confirmation prompts (for scripts). `version`/`help` also accept the
`-v`/`--version` and `-h`/`--help` spellings, same as the macOS version.

Sizes accept the same suffixes as the macOS version (`vault create 5g`, `reset 500m`); a bare
number is megabytes. Output follows the same contract too: normal output goes to stdout,
warnings and errors to stderr — so `securetrash check > report.txt` keeps the report.

Environment knobs: `ST_LANG=ru` (Russian output), `ST_ASSUME_YES=1` (skip confirmations,
equivalent to `--yes`), `ST_VAULT_NO_REVEAL=1` (after `vault open`, do **not** pop the mounted
volume in Explorer — same opt-out as macOS). `ST_VAULT_PASS=...` is a **test-only** hook for non-interactive runs —
do not use it for real secrets (it puts the password in an environment variable). In normal use
the vault password is read interactively as a `SecureString`.

## Vault: native BitLocker vs VeraCrypt

The `vault` command branches automatically:

- **Native (BitLocker cmdlets present, e.g. Windows Pro/Enterprise):** creates a **VHDX**
  via `diskpart` (no Hyper-V dependency), formats it NTFS, and protects it with
  `Enable-BitLocker -PasswordProtector`. The password is kept as a `SecureString` and is
  **never** placed on the command line. `open` attaches the VHDX **without a drive letter**,
  runs `Unlock-BitLocker` on the volume itself and **verifies** it is actually unlocked, and
  only then asks Windows for a letter — so Explorer never opens a locked volume and BitLocker
  never pops its own "unlock drive" prompt next to ours; a wrong password leaves nothing
  attached. The backend
  used to create a container is recorded in a sidecar `<vault>.backend` file so that `open` /
  `close` / `destroy` always dispatch through the correct backend.
- **VeraCrypt (no BitLocker, but VeraCrypt installed):** automated VeraCrypt vault creation is
  **not supported in this BETA**. VeraCrypt's CLI cannot take a password without putting it on
  the command line (where it leaks via `ps` / WMI / ETW). Instead, the tool prints an honest
  message and exits non-zero, instructing you to **create and mount the container with the
  VeraCrypt GUI** (which prompts for the password securely), then move your secrets onto the
  mounted drive.
- **Neither available:** the tool **honestly refuses** — it tells you to enable BitLocker or
  install VeraCrypt and exits non-zero. No silent "as if encrypted" behavior.

`destroy` dismounts the container (BitLocker backend) and deletes the backing file =
crypto-shred. Recovery then depends on the password strength and on no copies / backups /
snapshots (VSS, File History, cloud sync) remaining — it is **not** an absolute guarantee.

> The vault protects only what is created/moved **inside** it. Plaintext that already lived
> outside is not erased by this — for that you need BitLocker on the whole disk. While the vault
> is **mounted**, its contents can still leak via Windows Search, swap / pagefile, VSS shadow
> copies or cloud sync.

## Deletion note (honest)

`securetrash shred` / `empty` delete the files and then run a **best-effort** free-space
overwrite with `cipher /w` on the affected drive (this can be **slow**). On **SSDs and
copy-on-write filesystems**, overwriting is **not a guarantee** — wear leveling, TRIM and COW
mean old blocks may survive. The tool says so plainly and never claims "overwrite done" as a
guarantee. For real protection use **BitLocker** (full-disk encryption) + `securetrash vault`
(crypto-shred).

## Tests

```powershell
Invoke-Pester windows/test -Output Detailed
```

All Windows-specific cmdlets/executables are mocked, so the suite runs on any platform with
PowerShell (including macOS/Linux `pwsh`). It verifies dispatch, i18n, branching and honest
output — not real crypto behavior (see BETA disclaimer).

## See also

- macOS version and project overview: [`../README.md`](../README.md)
