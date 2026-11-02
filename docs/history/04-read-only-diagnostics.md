# 04 — Read-only devices: diagnosis and safe correction

`bigmount --diagnose DEVICE|FOLDER` (terminal) and `bigmount --gui`
(dialog) answer "why can't I write here?". The decision lives in
`bm_diagnose_write` (`usr/lib/big-mount/lib.sh`), checked in this order:

| Case | Evidence (structured whenever possible) | Correction offered |
| --- | --- | --- |
| ok | mounted rw and `access(W_OK)` for the user | — |
| E — write-protected device | `/sys/block/*/ro = 1` (partition or disk) | none (physical lock) |
| G — no write support | mounted type iso9660, udf, squashfs, erofs, hfs/hfsplus, apfs, legacy `ntfs` | none |
| D — unsafe NTFS | NTFS mounted `ro`; reason from `/run/big-mount/status` or from the ntfs-3g journal (asked for `rw`, mounted `Read-Only`) | none: needs Windows |
| C — filesystem errors | `/sys/fs/ext4/*/errors_count`; kernel messages ("Remounting filesystem read-only", "forced readonly", ...) | none; advice to copy the data and check it unmounted |
| F — hardware | kernel `I/O error` messages | none |
| A — mounted `ro`, no known problem | `ro` option, none of the above | **Mount again with writing**: UDisks mounts only, never fstab entries, only when the kernel log is readable |
| B — no permission (POSIX) | rw, root folder owned by another user | **Become owner of the main folder** (UDisks `TakeOwnership`, `recursive=false`, polkit) |
| B — partition holding an operating system | `etc/os-release`, `*/etc/os-release` (Btrfs subvolumes), `@`, `Windows/System32`... | none |
| B — FAT/NTFS of another user | another `uid=` | **Mount again for my user** (UDisks mounts only) |
| folder of another user | a FOLDER was asked about; it is judged under the mount that contains it (`findmnt -T`), and it belongs to someone else | none: the owner is named |
| system partition | `/`, `/boot/efi`, `/usr`, ... of the running system | none |
| swap | the partition is swap space | none |

A whole disk (`/dev/sdd`) is answered with the list of its partitions.

Rules that tests enforce:

- No correction ever runs `fsck`, `ntfsfix`, `chmod -R` or `chown -R`.
- Nothing is remounted `rw` when there is any sign of errors.
- Every correction asks for confirmation and is verified afterwards. On
  failure the user is told that nothing was changed.

## The drive itself

The diagnosis of a filesystem also looks at the drive that holds it
(timeouts on its port, I/O errors, SMART), and says so when the drive
reported errors since boot. A drive that acknowledges writes and keeps
none is described in [14](14-drive-health-and-secure-erase.md).

## Why `ioerr_cnt` is not used as a cause

The healthy USB SSD of the development machine has
`/sys/block/sdd/device/ioerr_cnt = 0xf`. UAS devices count SCSI commands
they do not support, so the counter alone would produce false "failing
disk" alarms.

## A case found on the development machine

`/mnt/root` is the top level of the Btrfs of another BigLinux installation
(`subvolid=5`, with `@`, `@home`, ...). A first version of the "operating
system" check only looked for `etc/os-release` at the root, and offered to
change the owner. That would have let the user rename `@` from Dolphin and
make that system unbootable. The check now also looks one level down, and a
test covers it.
