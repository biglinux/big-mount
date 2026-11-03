# 01 — What Big-Mount does

Big-Mount mounts the partitions of the **internal** disks at boot, under
`/mnt/<label>` (the filesystem label, else the GPT partition name, else the
device name, as in `/mnt/sdb3`), so that they are there for every program and
service from the start. That is all.

- `big-mount.service` (oneshot, after `local-fs.target`) runs `/usr/bin/bigmount`
  as root once per boot and ends. NTFS volumes keep their FUSE daemon
  (`KillMode=process`); nothing else stays running.
- Removable, hot-pluggable, USB, FireWire, SD and Thunderbolt devices are left to
  UDisks2 (Plasma, Dolphin). Partitions listed in `/etc/fstab` (also `noauto`),
  swap, containers (LUKS, LVM, RAID members), virtual devices and anything
  udev hides are never touched.
- `/etc/big-mount.conf`: who may write to FAT, exFAT and NTFS partitions
  (`PERMISSIONS=shared|owner|private`). `/etc/bigmountall-no` disables it.
- It writes what it did to `/run/big-mount/status` (device, UUID, mount point,
  state, reason) and to the journal.
- NTFS volumes that Windows left hibernated or unclean are mounted read-only,
  never repaired.

What it no longer does: diagnosis of devices, what keeps a device busy, safe
removal, drive health, file rescue, disk images, notifications, a graphical
application, Secure Erase. The first ones are
[Big Storage Rescue](https://github.com/biglinux/big-storage-rescue); Secure
Erase is part of neither (see 02-split.md).
