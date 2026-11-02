# Big-Mount

Mounts the partitions of the **internal** disks at boot, under `/mnt/<label>`,
so that they are there for every program and service from the start. Made for
[BigLinux](https://www.biglinux.com.br) (Manjaro/Arch). Removable and USB
devices are left to the desktop (UDisks2, Plasma, Dolphin), and partitions in
`/etc/fstab` are never touched.

> Big-Mount 2.x also had a drive manager, diagnosis of read-only devices, safe
> removal and file rescue. Since 3.0 they are a separate application,
> **[Big Storage Rescue](https://github.com/biglinux/big-storage-rescue)**
> (`sudo pacman -S big-storage-rescue`). Big-Mount only mounts.

## 1. Installation

```bash
sudo pacman -S big-mount
```

The pacman hook enables `big-mount.service`; it runs at the next boot. To mount
now: `sudo systemctl start big-mount`. Dependencies: bash, util-linux, ntfs-3g.

```bash
bigmount --dry-run    # what would be mounted, changing nothing
bigmount --doctor     # is the service doing its job? what happened at boot?
bigmount --version
```

## 2. Automatic mounting at boot

### 2.1 Sequence

```text
big-mount.service (Type=oneshot, After=local-fs.target, KillMode=process)
└─ /usr/bin/bigmount
   1. exits if /etc/bigmountall-no exists
   2. locks /run/lock/big-mount.lock (flock), so two runs never overlap
   3. creates the compatibility links /media -> /mnt and /mnt/user-mount -> /run/media
   4. finds the last user (SDDM, LightDM, or the first UID >= 1000), reads /etc/big-mount.conf
   5. takes one snapshot of the system:
        the diskseq of every disk, blkid, lsblk -P, /proc/mounts
   6. pass 1: drops what is not a filesystem, what is virtual and what is already mounted
   7. asks udev about every candidate in a single call (udevadm info),
      and waits for udev ONCE (udevadm settle) if a device is not processed yet
   8. pass 2, for each candidate, in blkid order:
        hidden by UDisks? external? listed in fstab? -> not mounted
        choose /mnt/<label>, check the diskseq again, mount, read the real state back
   9. writes /run/big-mount/status
```

### 2.2 What is never mounted

| Case | Why |
| --- | --- |
| partition in `/etc/fstab` (even `noauto`) | the administrator's explicit configuration always wins |
| already mounted | no double mounts |
| `swap`, `squashfs` | not user data |
| `crypto_LUKS`, `BitLocker`, `LVM2_member`, RAID/ZFS/bcache members, no `TYPE` | containers, not filesystems |
| `loop*`, `zram*`, `ram*`, `/dev/mapper/*`, `dm-*` | virtual devices, set up by whoever uses them |
| `UDISKS_IGNORE=1` | ESP, MSR, Windows recovery (what UDisks calls `HintIgnore`) |
| an **external** device | belongs to UDisks/Plasma (see below) |
| udev still has no information after the wait | without facts, there is no telling whether it is external |
| `diskseq` changed during the scan | the disk was replaced; the decision no longer holds |

### 2.3 How an external device is recognized

Many USB hard disks and SSDs report `RM=0` ("not removable"), so the decision
combines **independent sources**. Any one of them is enough to leave the
device to UDisks:

| Source | Fact | Examples |
| --- | --- | --- |
| kernel (sysfs) | `/sys/block/X/removable = 1` | USB sticks, card readers |
| kernel (`lsblk TRAN`) | `usb`, `ieee1394`, `sbp` | USB HDD/SSD with `RM=0`, docks, FireWire |
| kernel (`lsblk HOTPLUG`) | port marked removable | USB, NVMe in Thunderbolt/USB4 enclosures |
| kernel (sysfs) | `device/type = SD` | SD card in an internal reader (`MMC` is soldered eMMC: internal) |
| udev | `ID_BUS=usb`/`ieee1394`, `ID_PATH` containing `-usb-` | the same information, seen by udev |
| udev | `ID_DRIVE_FLASH_SD=1`, `ID_DRIVE_MEDIA_FLASH_SD=1` | SD cards |
| udev | `UDISKS_SYSTEM=0` | an administrator's rule, e.g. for eSATA bays ([4.3](#43-esata-bays-and-other-special-cases)) |

To see the decision for every device (excerpt from the development machine):

```console
$ sudo bigmount --dry-run
/dev/nvme0n1p1: skipped, hidden by udev/UDisks (UDISKS_IGNORE)
/dev/nvme0n1p2: skipped, listed in /etc/fstab
/dev/sdd1: left to UDisks, external device (transport=usb hotplug ID_BUS=usb ID_PATH=usb)
dry-run: mkdir -p /mnt/Basic_data_partition
dry-run: mount -t lowntfs-3g -o uid=1000,gid=1007,rw,noatime,exec,umask=000,nodev,nofail,x-gvfs-show /dev/sdb3 /mnt/Basic_data_partition
/dev/sdb3: would be mounted ntfs on /mnt/Basic_data_partition (rw)
/dev/sdb1: skipped, hidden by udev/UDisks (UDISKS_IGNORE)
dry-run: mkdir -p /mnt/Dados
dry-run: mount -o noatime,rw,nodev,nofail,x-gvfs-show /dev/sda1 /mnt/Dados
/dev/sda1: would be mounted btrfs on /mnt/Dados (rw)
```

`--dry-run` creates no directory, mounts nothing and writes no status file.
It works as a normal user, but as root `blkid` sees every partition. On a
terminal the messages follow your language; in the journal they stay in
English.

### 2.4 Mount point name

1. The filesystem `LABEL`; without one, the `PARTLABEL` (GPT partition
   name); without both, the device name (`sdb3`).
2. Spaces, `/` and control characters become `_`. Accents and Unicode are
   kept (`Family Photos` → `/mnt/Family_Photos`).
3. `.` and `..` are rejected (`..` would mount over `/`), and so are labels
   longer than 200 bytes. In both cases the device name is used.
4. If `/mnt/<name>` is used by **another** device, a number is added:
   `Data1`, `Data2`... Empty directories and stale links are reused.
5. The link `/mnt/<device>` → `/mnt/<label>` is created (`/mnt/sda1` →
   `/mnt/Data`). An old link pointing elsewhere, for example after the disks
   changed order, is updated. A real directory or file at that path is never
   touched.

The label comes from the device and is untrusted: it never goes through
`eval`, `echo` or a shell.

### 2.5 Mount options

| Filesystem | Command |
| --- | --- |
| NTFS | `mount -t lowntfs-3g -o uid=U,gid=G,rw,noatime,exec,MASK,nodev,nofail,x-gvfs-show` |
| FAT32, exFAT (`TYPE` containing `fat`) | `mount -o uid=U,gid=G,noatime,rw,MASK,nodev,nofail,x-gvfs-show` |
| ext4, Btrfs, XFS, F2FS and others | `mount -o noatime,rw,nodev,nofail,x-gvfs-show` |

- `U`/`G`: UID and GID of the last user who logged in.
- `MASK`: `umask=000` by default; see [`PERMISSIONS`](#41-etcbig-mountconf).
- `x-gvfs-show`: shows the partition in Dolphin and Nautilus.
- ext4/Btrfs/XFS keep the filesystem's own permissions.

### 2.6 Windows NTFS partitions

- **No `ntfsfix`.** Older versions ran `ntfsfix` on every boot. It marks the
  volume as "needs to be checked" (the dirty bit): Windows then runs chkdsk
  at every start, and drivers such as `ntfs3` refuse to write. ntfs-3g
  recovers the journal by itself when needed.
- **Windows hibernated or with Fast Startup:** ntfs-3g mounts the volume
  read-only on its own. Big-Mount reads the real state back from
  `/proc/mounts`, records the reason; `big-storage-rescue --diagnose` explains it. ntfs-3g
  versions that refuse (exit codes 13, 14 and 15 of `ntfs-3g.probe(8)`) are
  retried with `ro`. `remove_hiberfile`, which would delete the Windows
  session, is never used.
- To write again, shut Windows down completely (Shift + Shut down) or
  disable Fast Startup.

### 2.7 Status file

`/run/big-mount/status` (root, 0644, cleared at every boot) has one line per
mount made at boot. It is read by `bigmount --doctor` and by Big Storage
Rescue, with fields separated by tabs:

```text
# big-mount status v1: DEVICE UUID MOUNTPOINT STATE REASON
/dev/sda1	12a560b3-...	/mnt/Data	rw	-
/dev/sdb3	BE0256040255C1D7	/mnt/Basic_data_partition	ro	ntfs-readonly
/dev/sdc5	-	/mnt/Old	failed	mount-exit-32
```

| `STATE` | Possible `REASON` |
| --- | --- |
| `rw` | `-` |
| `ro` | `ntfs-readonly`, `ntfs-hibernated`, `ntfs-inconsistent`, `ntfs-unclean`, `readonly-fallback` |
| `failed` | the NTFS reasons, or `mount-exit-N` |

### 2.8 Logs

```bash
journalctl -b -u big-mount            # what happened during this boot
journalctl -b -u big-mount -p warning # warnings and errors only
systemd-analyze blame | grep big-mount
```

Example messages:

```text
/dev/sda1: mounted btrfs on /mnt/Data (rw)
/dev/sdd1: left to UDisks, external device (transport=usb hotplug ID_BUS=usb ID_PATH=usb)
/dev/sdb3: the driver mounted ntfs read-only on its own (ntfs-readonly)        [warning]
/dev/sdc5: mount of ext4 on /mnt/Old failed (exit 32)                          [error]
waiting for udev to finish processing /dev/sde1
```

### 2.9 The systemd service

```ini
[Unit]
Description=BigLinux automount internal partitions
After=local-fs.target
RequiresMountsFor=/mnt

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bigmount
KillMode=process
```

`KillMode=process` matters: the NTFS FUSE daemon (`mount.lowntfs-3g`) is
started inside the service. With the default `control-group`, a `systemctl
restart big-mount` killed it and the volume vanished under the programs
using it. Nothing stays resident: the script ends within milliseconds.

## 3. Why is a partition read-only, or not mounted?

`bigmount --doctor` lists what failed or was mounted read-only at this boot,
with the reason (`ntfs-hibernated`, `mount-exit-32`…). For the full
explanation, the health of the drive, and the way to fix it or rescue its
files, use Big Storage Rescue: `big-storage-rescue --diagnose /dev/sdXN`.

## 4. Configuration

### 4.1 `/etc/big-mount.conf`

```ini
# Who may write to INTERNAL FAT, exFAT and NTFS partitions mounted under /mnt
PERMISSIONS=shared
```

| Value | Mount options | Effect |
| --- | --- | --- |
| `shared` (default) | `umask=000` | every local account reads, writes and runs files: the behavior of every previous version |
| `owner` | `dmask=022,fmask=022` | only the last user who logged in writes; everyone reads (running programs stays allowed, for Wine/Steam) |
| `private` | `umask=077` | only the last user who logged in has access |

- Applies to internal FAT/exFAT/NTFS. ext4, Btrfs, XFS, etc. keep their own
  permissions.
- The file is parsed as data, never executed. An unknown value is reported
  in the journal and `shared` is used.
- It is kept on package updates (`backup=` in the PKGBUILD).
- Apply without rebooting: `sudo systemctl restart big-mount`. Partitions
  that are already mounted keep their options until they are mounted again.

### 4.2 Disable the automatic mounting

```bash
sudo touch /etc/bigmountall-no      # disable
sudo rm /etc/bigmountall-no         # enable again
```

### 4.3 eSATA bays and other special cases

The kernel does not mark eSATA ports as removable. For Big-Mount (and
UDisks) to treat an eSATA disk as external, add a udev rule:

```bash
# find the path of the disk
udevadm info --query=property --name=/dev/sdX | grep ID_PATH=

sudo tee /etc/udev/rules.d/99-esata.rules <<'EOF'
ENV{ID_PATH}=="pci-0000:00:17.0-ata-5*", ENV{UDISKS_SYSTEM}="0"
EOF
sudo udevadm control --reload && sudo udevadm trigger
```

To **prevent** an internal partition from being mounted, either put it in
`/etc/fstab` with `noauto`, or hide it entirely with
`ENV{UDISKS_IGNORE}="1"`.

To mount a partition somewhere else or with other options, put it in
`/etc/fstab`. Big-Mount never touches partitions listed there.

## 5. Commands of Big-Mount 2.x

They print the command that does the same now and exit with code 2:

| 2.x | Now |
| --- | --- |
| `bigmount --drive …` | `big-storage-rescue --cli …` |
| `bigmount --gui-drive`, `--gui-drive-check` | `big-storage-rescue --gui`, `--gui-health` |
| `bigmount --gui DEV` | `big-storage-rescue --gui-diagnose DEV` |
| `bigmount --diagnose`, `--busy`, `--unmount`, `--safe-remove`, `--gui-remove` | `big-storage-rescue` with the same option |
| `bigmount --secure-erase` | not available any more |

## 6. Development

```bash
bash tests/run-tests.sh new     # the boot run with stubbed devices
bash tests/i18n-tests.sh        # translations
bash tests/package-check.sh     # package() on this checkout
bash tests/bench.sh big-mount/usr/bin/bigmount   # the boot run on the real devices, mount stubbed
tests/manual-check.sh           # after a real boot with the package installed
```

Technical notes: [docs/](docs) (01–07); the history of 2.x, including the
reasons behind the device detection, is in [docs/history](docs/history).

## 7. License

[GNU General Public License v3.0](LICENSE).
