# 08 — Performance

All numbers are medians of repeated runs on the development machine
(16 CPUs, 9 `blkid` entries: NVMe, 3 SATA, 1 USB SSD, zram). They can be
reproduced with the two scripts below, and no number here is an estimate.

| Script | Measures |
| --- | --- |
| `tests/bench.sh SCRIPT [N]` | the boot path against the **real** devices, with `mount`/`ntfsfix` replaced by stubs and an empty `/proc/mounts` (the boot situation); wall time, CPU, processes created. It aborts unless the stubs are the ones executed |
| `tests/measure-session.sh [BIGMOUNT] [N]` | the session tools on disposable images attached through UDisks2: `--diagnose` time, latency from a mount to the notification, idle cost of the notifier |

## Round 2 (this version, measured before and after)

| Metric | Before (`master` `ee044f9`) | After |
| --- | --- | --- |
| Boot path, wall time (30 runs) | 39.9 ms | 40.1 ms |
| Boot path, CPU | 41 ms | 41 ms |
| Boot path, processes created | 27 | 27 |
| `--diagnose`, writable device (5 runs) | 243 ms | 245 ms |
| `--diagnose`, read-only device | 246 ms | 245 ms |
| Notifier, idle | 2 processes, 9.2 MB RSS, 0 CPU in 10 s | 2 processes, 9.2 MB RSS, 0 CPU in 10 s |
| **Mount → notification** (5 runs) | **1044 ms** | **45 ms** |

- The boot path did not regress. The new translation support costs nothing
  in the journal case: gettext is only set up when stdout is a terminal, and
  `$"..."` is resolved by bash itself.
- The notification latency came from an artificial `sleep 1` after every
  mount event. It was not needed: the check reads the final mount options.
- `--diagnose` is dominated by `lsof` (about 212 of 236 ms, scanning 680
  processes). Faster alternatives were measured and rejected (see 05). The
  cost is only paid on request.

Why the boot path stays at 27 processes: one `blkid`, one `lsblk` and one
`udevadm` are shared by every partition. Each partition that is mounted
costs one `findmnt --fstab`, one `mkdir`, one `mount` and one `ln`. The
fstab lookups could be folded into one call, but that would change how
fstab tags (UUID=, LABEL=, duplicates) are matched, which is not worth a
few milliseconds.

## Round 3 (installed package, real root runs)

Measured on the running system with the package installed:

| Measure | Value |
| --- | --- |
| `bigmount` as root, every partition already mounted (3 runs) | 42.8, 23.5, 21.3 ms |
| `bigmount --dry-run` as root (2 runs) | 40.4, 20.5 ms |
| `systemctl restart big-mount`, Starting → Finished in the journal | 33 ms |
| the very first service run after installing | 1096 ms (not reproduced; cold caches) |
| mount → notification in the real Plasma session | 77 ms |

## Round 5 (safe removal on a real USB SSD)

| Measure | Value |
| --- | --- |
| boot after installing v2.1.1, `systemd-analyze blame` | 716 ms; the three `mount` calls take almost all of it (Btrfs `/mnt/Dados` alone ≈ 380 ms) |
| `--safe-remove` of a USB SSD (NTFS, a Docker service bound to it), including stopping the service and waiting for ntfs-3g | 5.1 s |
| services bound to a mount (`systemctl` queries) | 8 ms |
| FUSE daemons of a device (`/proc/*/comm`) | 7 ms |
| mounts in other namespaces (`/proc/*/mountinfo`, 585 processes) | 70 ms, of which 43 ms is `grep` reading the tables |
| `--busy` on that SSD | 224 ms |

The boot path did not change in this round.

## Round 1 (original script → modernized version)

| Metric | Original | Modernized |
| --- | --- | --- |
| Wall time | 127 ms | 37–40 ms |
| CPU | 129 ms | 38–42 ms |
| Processes | 194 | 27 |
| `ntfsfix` calls | 1 | 0 |
| `udisksctl` D-Bus clients | 10 | 0 |

The last real boot with the original version recorded 1.019 s for
`big-mount.service` (`systemd-analyze blame`), mostly because its first
`udisksctl` call activated `udisksd`. **A real boot with the new version has
not been measured yet**: that needs the package installed and a reboot.
