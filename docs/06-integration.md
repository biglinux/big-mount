# 06 — With Big Storage Rescue

Big-Mount works alone. When `big-storage-rescue` is also installed:

- it finds the partitions Big-Mount mounted (through the kernel and UDisks2,
  like any other mount) and reads `/run/big-mount/status` to say why one is
  read-only (for example `ntfs-hibernated`: Windows Fast Startup);
- its `--doctor` shows whether `big-mount.service` is enabled and ran, and what
  failed at boot;
- it never changes `/etc/big-mount.conf`, never restarts the service, and
  unmounts a partition of Big-Mount only when the person asks for it;
- `bigmount --doctor` points to `big-storage-rescue --diagnose DEVICE` for the
  reason of a failed or read-only mount.

| Installed | Result |
| --- | --- |
| Big-Mount 3.0 alone | mounts at boot; old options say where they went |
| Big Storage Rescue alone | everything works; it says Big-Mount is not installed |
| both | one application in the menu; diagnosis uses the boot status |
| Big Storage Rescue + Big-Mount 2.6 | no file conflict; two applications until Big-Mount is updated |
| Big-Mount 2.6 → 3.0 with a copy of 2.6 running | the copy goes on; Big Storage Rescue brings it over when it ends |
| either removed | the other is untouched |

No file is owned by both packages (`tests/package-check.sh` in both
repositories), and neither declares `conflicts`, `replaces` or `provides` for
the other. Every row of the table above was checked with real pacman
transactions in scratch roots (`tests/coexistence-check.sh` in Big Storage
Rescue, 18 checks, 2026-11-02), except the running copy, which is covered by
the migration tests of Big Storage Rescue.
