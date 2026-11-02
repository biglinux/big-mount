# 04 — Dependencies

| | 2.6 | 3.0 |
| --- | --- | --- |
| `depends` | bash, util-linux, udisks2, polkit, ntfs-3g, lsof, rsync, smartmontools, python, python-gobject, gtk4, libadwaita>=1.5, libnotify (13) | **bash, util-linux, ntfs-3g** (3) |
| `optdepends` | ddrescue, testdisk | big-storage-rescue |
| installed files | 45, 803 KB | 7, 41 KB (with the version file) |

What the boot run calls: `blkid`, `lsblk`, `findmnt`, `mount`, `flock`
(util-linux), `mount.lowntfs-3g` (ntfs-3g), `udevadm` (systemd), `getent`
(glibc), `awk` (gawk), `readlink`, `mkdir`, `ln`, `rm`, `rmdir` (coreutils).
systemd, glibc, gawk and coreutils are part of every Arch base system and are
not listed, as before.

`udisks2` and `polkit` were needed by the diagnosis and removal tools, not by
the boot run, and are dropped. On a desktop they are pulled in by Plasma or
GNOME anyway.

`big-storage-rescue` is optional, never required and never in conflict:
`tests/package-check.sh` checks it, and that no installed path belongs to it.
