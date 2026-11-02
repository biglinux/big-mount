# 03 — Architecture

```
/usr/bin/bigmount                     boot run (no option) and --dry-run; everything in bash builtins
/usr/lib/big-mount/cli.sh             --help, --version, --doctor, old options (loaded only for them)
/usr/lib/big-mount/version            commit and date of the build (written by the PKGBUILD)
/usr/lib/systemd/system/big-mount.service
/usr/share/libalpm/hooks/big-mount.hook   enables the service on installation
/etc/big-mount.conf                   PERMISSIONS
/run/big-mount/status                 what the last runs did (tab-separated, v1)
/run/lock/big-mount.lock              one run at a time (fd 9, never inherited by mount helpers)
```

The boot run, in one pass:

1. one snapshot of `blkid`, `lsblk` (topology, `TRAN`, `RM`, `HOTPLUG`),
   `/proc/mounts` and the disk sequence numbers;
2. cheap filters (swap, containers, virtual devices, already mounted), then
   one `udevadm info` call for all candidates (waits once for udev when needed);
3. for each partition: external? in `/etc/fstab`? a safe mount point name;
   the disk sequence number again; `mount` with the options of its filesystem;
4. the real state (a driver may fall back to read-only by itself) goes to the
   journal and to `/run/big-mount/status`.

Details and the reasons: `docs/history/02-device-detection.md`,
`03-filesystem-support.md`, `08-performance.md`.

## Format of `/run/big-mount/status`

```
# big-mount status v1: DEVICE UUID MOUNTPOINT STATE REASON
/dev/sda2	1234-ABCD	/mnt/Windows	ro	ntfs-hibernated
```

`STATE`: `rw`, `ro` or `failed`. `REASON`: `-`, `ntfs-hibernated`,
`ntfs-unclean`, `ntfs-inconsistent`, `ntfs-readonly`, `readonly-fallback`,
`mount-exit-N`. Big Storage Rescue reads it to explain why a partition is
read-only; it is the only interface between the two, and it is read-only for
everyone but this script.
