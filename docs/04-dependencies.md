# 04 — Dependencies

| | 2.6 | 3.0 |
| --- | --- | --- |
| `depends` | bash, util-linux, udisks2, polkit, ntfs-3g, lsof, rsync, smartmontools, python, python-gobject, gtk4, libadwaita>=1.5, libnotify (13) | **bash, coreutils, gawk, glibc, ntfs-3g, sed, systemd, util-linux** (8) |
| `optdepends` | ddrescue, testdisk | big-storage-rescue |
| installed files | 45, 803 KB | 7, 41 KB (with the version file) |

What Big-Mount calls, and the package of each program:

| Package | Programs |
| --- | --- |
| util-linux | `blkid`, `lsblk`, `findmnt`, `mount`, `flock` |
| ntfs-3g | `mount.lowntfs-3g` (NTFS) |
| systemd | `udevadm`; `systemctl` and `journalctl` in `--doctor`; the service itself |
| coreutils | `readlink`, `dirname`, `mkdir`, `ln`, `rm`, `rmdir`, `stat`, `head`, `tail` |
| glibc | `getent` |
| gawk | `awk` |
| sed | `sed` in `--doctor` |

systemd, glibc, gawk, sed and coreutils are on every Arch system, so the five
of them install nothing new. They are listed all the same, as the Arch
packaging guidelines ask for every direct dependency. `namcap` cannot see the
programs a shell script calls, so it marks every one of them "may not be
needed": the table above is the check. FAT32, exFAT, ext4, Btrfs, XFS and F2FS are mounted by kernel drivers,
which need no package.

`udisks2` and `polkit` were needed by the diagnosis and removal tools, not by
the boot run, and are dropped. On a desktop they are pulled in by Plasma or
GNOME anyway.

`big-storage-rescue` is optional, never required and never in conflict:
`tests/package-check.sh` checks it, and that no installed path belongs to it.
