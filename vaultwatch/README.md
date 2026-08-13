**English** · [Русский](README.ru.md)

# vaultwatch

An honest watchdog for an open vault — part of the [Paranoid Tools](../README.md) ecosystem.

[![CI](https://github.com/Di-kairos/paranoid-tools/actions/workflows/ci-vaultwatch.yml/badge.svg)](https://github.com/Di-kairos/paranoid-tools/actions/workflows/ci-vaultwatch.yml)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![platform](https://img.shields.io/badge/platform-macOS-blue)
![windows](https://img.shields.io/badge/Windows-beta-orange)
![shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)

`vaultwatch` is active **only while a vault is mounted**. It narrows the channels through
which open plaintext can leak (Spotlight, Time Machine) and **restores everything on close**.
It runs automatically from the `securetrash vault open/close` hooks.

> **Status: early (v0.1.14, work in progress).** Done: integration (hooks + vendoring),
> the **watchdog core `start`/`stop`** (Spotlight off, Time Machine exclude, cloud-detect,
> session report), and **auto-exit `--ttl`** via a **launchd LaunchAgent** (a managed timer,
> visible in `launchctl list`, cleanly removed via bootout).

## Install

Checksum-verified install from the release tag (same approach as securetrash). Prefer
verify-then-run — download, check the checksum, read it, then run:

```bash
curl -fsSLO https://github.com/Di-kairos/vaultwatch/releases/latest/download/install.sh
curl -fsSLO https://github.com/Di-kairos/vaultwatch/releases/latest/download/SHA256SUMS
curl -fsSLO https://github.com/Di-kairos/vaultwatch/releases/latest/download/SHA256SUMS.sig
printf '%s\n' 'releases@paranoid-tools namespaces="file" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICb2nz4EliRJIU0ExeF41klE/zlyo7XFY119mfzscn2U' > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I releases@paranoid-tools -n file -s SHA256SUMS.sig < SHA256SUMS &&   # authenticity: Ed25519, pinned key
shasum -a 256 -c SHA256SUMS --ignore-missing &&   # integrity: verifies install.sh
less install.sh &&                               # read it — then run:
bash install.sh                                  # pulls vaultwatch + checksum, verifies, installs
vaultwatch install-hooks                         # wire into securetrash
```

Quick form (this runs code you haven't read — choose deliberately):

```bash
curl -fsSL https://github.com/Di-kairos/vaultwatch/releases/latest/download/install.sh | bash
```

`install.sh` pulls the binary and `SHA256SUMS` from the immutable release tag and verifies
the hash **before** installing. Environment variables: `VW_VERSION` (pin a specific tag),
`VW_DEST` (install path), `VW_BASE_URL` (override the source for forks/tests).

> **Integrity vs authenticity (honest scope).** The checksum proves the binary matches the
> `SHA256SUMS` published in the **same release** — it catches corruption and partial/cached
> tampering. Authenticity comes from the Ed25519 signature
> over `SHA256SUMS`: the snippet above and `install.sh` both verify it against a key
> pinned in this repo, and the installer fails closed when it can't (see `SECURITY.md`).
> Residual risk: one project key signs all five tools — see the ecosystem
> [threat model](../THREAT-MODEL.md). Pin a version with `VW_VERSION=0.1.14` instead of `latest`
> for reproducibility.

> The current public release is **v0.1.14** (signed, with `install.sh` + `SHA256SUMS`).
> Pin it for reproducibility with `VW_VERSION=0.1.14` instead of `latest`.

## Usage

```bash
vaultwatch start [--ttl D] [--force] <mount>   # guard a vault (normally from the post-open hook)
vaultwatch stop  <mount>                        # restore everything + session report (post-close)
vaultwatch status                               # show active sessions (read-only)
vaultwatch install-hooks                        # wire into securetrash vault open/close
vaultwatch uninstall-hooks                      # remove (only the hooks it manages)
vaultwatch version                              # show the version
```

`--ttl D` auto-detaches the volume after `D` (`30m`, `2h`, `45s`, `1d`, or bare seconds).
The timer is installed as a **launchd LaunchAgent**
(`~/Library/LaunchAgents/com.vaultwatch.ttl.*.plist`, `RunAtLoad` → sleeps `D` → fires
`vaultwatch _ttl_fire <mount>`). When it fires, vaultwatch checks for open files (`lsof`)
and, if there are none, unmounts the volume (`hdiutil detach`) and restores state. If files
are open it **honestly leaves the volume alone** and warns; `--force` forces
`hdiutil detach -force` (with confirmation, risk of data loss). `stop` (a manual close before
the TTL) tears the LaunchAgent down (`bootout` + plist removal).

`start` records the prior state and narrows leak channels; `stop` restores **exactly what
`start` changed** (if Spotlight was already off, or the vault was already excluded from Time
Machine before the session, `stop` leaves that as-is) and prints a session report.

**Unmount-guard (macOS).** Ejecting the vault from Finder (or any detach that bypasses
`vaultwatch stop` / securetrash's post-close hook) would otherwise leave the exclusions
hanging until the next explicit `stop`. `start` also registers a launchd LaunchAgent with
`WatchPaths` on the mountpoint (`com.vaultwatch.guard.*.plist`); when the volume disappears it
fires `vaultwatch _guard_fire`, which restores everything **only if the mount is truly gone**
(a `WatchPaths` hit from a write inside the still-mounted vault is a no-op). `stop` removes the
guard. Windows has an equivalent guard via a **polling Task Scheduler task** (~1 min latency, not
event-driven) — see `windows/README.md`.

Hooks are placed in `${ST_HOOK_DIR:-~/.securetrash/hooks}` — the same directory `securetrash`
reads. vaultwatch does not touch foreign (non-managed) hooks.

`ST_LANG=ru` switches output to Russian (ecosystem-shared locale variable; defaults to English,
otherwise inferred from `LC_ALL`/`LANG`). Honored on both macOS and the Windows port.

### Session report (example)

```
vaultwatch — session report
  duration:        24m 18s
  Spotlight:       indexing re-enabled for /Volumes/SecretVault
  Time Machine:    exclusion removed (added by this session)
  cloud daemons:   Dropbox active — vault was OUTSIDE its sync folder
  local snapshots: none observed (tmutil listlocalsnapshots /)
  swap:            NOT addressed (see limitations)
```

## Architecture

- Single-file Bash, zero dependencies. Native macOS primitives.
- The shared core (`lib/common.sh`) is **vendored** inline from securetrash, pinned to a
  git-ref; `tools/vendor-common.sh --check` catches drift in CI. See [`paranoid-tools/README.md`](../README.md).

## Scope & limitations

The core principle of the ecosystem: be honest about the limits. vaultwatch makes
**reversible** exclusions for the duration of the session and does **not**:

- **Does not close swap** — if there was memory pressure during the session, fragments of
  plaintext may have been written to swap and remain there until overwritten. The session
  report says this plainly.
- **Does not delete local Time Machine snapshots that were already taken:** `addexclusion`
  excludes the vault going forward, but snapshots taken before start remain. vaultwatch
  detects them (`tmutil listlocalsnapshots /`) and reports them — it does not silently delete.
- **Does not edit cloud settings or delete anyone's backups.** Cloud detection is heuristic:
  it inspects running processes (Dropbox/OneDrive/iCloud/Google Drive) and whether the mount
  sits inside their sync folders — it reports "daemon X is active, vault inside/outside its
  folder", not telepathy.
- **Restores only its own changes:** if Spotlight was already off, or the vault was already
  excluded from Time Machine before the session, `stop` leaves it as-is — it does not "fix"
  state it did not set.
- **`--ttl` is blocked by open files:** `hdiutil detach` will not unmount a volume with open
  descriptors. vaultwatch checks `lsof` and, when the volume is busy, **does not force** it —
  it warns honestly; `--force` (`detach -force`) only with confirmation and awareness of the risk.

## Windows (beta)

A PowerShell port now exists in [`windows/README.md`](windows/README.md). It mirrors the
macOS logic where the platform allows: it **controls the Windows Search indexer** (excludes the
mount, restores on close) and an unmount-guard re-restores it if the volume is ejected past
`stop`. VSS shadow copies and cloud-sync daemons (OneDrive/Dropbox/Google Drive) are **reported,
not controlled**; the pagefile is not addressed. See `windows/README.md` for the honest per-channel
breakdown.

> **Beta:** the Windows port is logic-tested (Pester on CI) but not yet validated on real
> Windows hardware. See [`windows/README.md`](windows/README.md).

## License

[MIT](LICENSE). Report security issues via [SECURITY.md](SECURITY.md); contributions via
[CONTRIBUTING.md](CONTRIBUTING.md).
