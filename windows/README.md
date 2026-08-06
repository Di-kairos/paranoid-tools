# SecureTrash — Windows port (BETA)

> Honest secure deletion for Windows. Mirror of the shipped macOS version.

## ⚠️ BETA disclaimer — read this first

This Windows port is **BETA**. Its **logic is tested via Pester** (dispatch, branching,
i18n, honest verdicts — all Windows-specific commands are mocked), but it has **NOT been
validated on real Windows hardware**: actual BitLocker / VHDX / VeraCrypt behavior is
**unverified**.

- Do not trust it with irreplaceable secrets until you have tested it yourself on a
  throwaway container.
- Contributions with a **real-hardware test pass** (BitLocker VHDX create/open/close/destroy,
  VeraCrypt fallback) are very welcome — that is the open task that takes this out of beta.

## The honesty principle (same as macOS)

Overwriting (`cipher /w`, SDelete) on an **SSD gives no guarantees** — wear leveling, TRIM,
and copy-on-write (ReFS) mean the old blocks may survive. Real protection is:

1. **BitLocker** — full-disk encryption, so deleted data is encrypted at rest.
2. **crypto-shred** — keep secrets inside an encrypted container, then destroy the
   container + key. Recovery then depends on the password/key strength and on the key
   never having been copied elsewhere — not on overwriting the disk. Strong, uncopied
   key destroyed → recovery is computationally infeasible (no absolute guarantee).

## Install

One-liner (PowerShell):

```powershell
irm https://github.com/Di-kairos/securetrash/releases/latest/download/install.ps1 | iex
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
| `check` | Audit the environment — BitLocker status, SSD/HDD verdict, vault availability, honest summary. Prints the BETA banner. |
| `setup` | Create `%USERPROFILE%\SecureTrash` and warn if BitLocker is off. Idempotent. |
| `empty` | Empty `%USERPROFILE%\SecureTrash` (keeps the folder) + honest disk note. |
| `shred <path>...` | Delete file(s)/folder(s), best-effort — on SSD **not** a guarantee + honest disk note. |
| `vault create\|open\|close\|destroy` | Encrypted container (crypto-shred). |
| `vault reset [size]` | Empty the vault for real: crypto-shred its contents, then recreate it empty (keeps the container). |
| `vault status` | Read-only: is the container open (and where it is mounted), closed, or missing. |
| `vault destroy-old` | Crypto-shreds a container left set aside by an interrupted `reset`. |
| `version` | `securetrash 0.5.3 (Windows, beta)`. |

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
  **never** placed on the command line. `open` attaches the VHDX, then runs `Unlock-BitLocker`
  and **verifies** the volume is actually unlocked before reporting it mounted. The backend
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
