# 02 — Device detection: internal or external

At boot Big-Mount mounts partitions of **internal** disks only. Everything a
user can unplug belongs to UDisks2 and Plasma.

## The problem

Many USB hard disks and SSDs report `RM=0` ("not removable"). The original
script only checked `/sys/block/X/removable` and the text `-usb-` in the
`udisksctl` output. That output requires `udisksd` to be running and udev to
have processed the device, which nothing guarantees at
`After=local-fs.target`. A real case on the development machine:

```text
$ lsblk -dn -o NAME,TYPE,TRAN,RM,HOTPLUG /dev/sdd
sdd  disk usb   0       1          # SanDisk Portable SSD (UAS)
$ udevadm info -q property -n /dev/sdd | grep -E 'ID_BUS|ID_PATH='
ID_BUS=usb
ID_PATH=pci-0000:04:00.0-usb-0:2:1.0-scsi-0:0:0:0
```

## The decision

A device is left to UDisks when **any** of these independent facts is true
for it or for its disk:

| Source | Fact | Covers |
| --- | --- | --- |
| sysfs | `removable = 1` | USB sticks, card readers |
| sysfs (`lsblk TRAN`) | `usb`, `ieee1394`, `sbp` | USB HDD/SSD with `RM=0`, docks, FireWire |
| sysfs (`lsblk HOTPLUG`) | parent port marked removable | USB, NVMe in Thunderbolt/USB4 enclosures |
| sysfs | `device/type = SD` | SD cards in an internal reader (`MMC` is soldered eMMC: internal) |
| udev | `ID_BUS=usb/ieee1394`, `ID_PATH` containing `-usb-` | the same information as seen by udev |
| udev | `ID_DRIVE_FLASH_SD`, `ID_DRIVE_MEDIA_FLASH_SD` | SD cards |
| udev | `UDISKS_SYSTEM=0` | an administrator's rule (eSATA bays) |

The device is **ignored** when `UDISKS_IGNORE=1`. This is the udev property
UDisks exposes as `HintIgnore` (ESP, MSR, Windows recovery), and the
equivalence was checked device by device.

The kernel facts need neither udev nor D-Bus. The udev facts confirm them,
so no single missing or wrong property makes an external disk look internal.

### When udev has not processed a device yet

If a candidate lacks `USEC_INITIALIZED`, bigmount waits **once**
(`udevadm settle --timeout=10`). If the information is still missing, the
device is **not** mounted and a warning goes to the journal. The cost only
exists when the case happens.

### Other cases

| Case | Behavior |
| --- | --- |
| partition in `/etc/fstab` (even `noauto`) | never touched |
| `loop`, `zram`, `ram`, `/dev/mapper`, `dm-*` | skipped |
| LUKS, LVM, RAID/ZFS members, BitLocker, no `TYPE` | skipped, no `mkdir` |
| md RAID | the disk examined is the first member (top of the `PKNAME` chain) |
| device replaced during the scan | different `diskseq`: not mounted |

## Validation

- `bigmount --dry-run` on the development machine, with an empty
  `/proc/mounts`, decides the same three mounts that are active today and
  recognizes `sdd1` as external through
  `transport=usb hotplug ID_BUS=usb ID_PATH=usb`.
- `tests/run-tests.sh` covers USB with `RM=0` through each signal alone,
  multi-partition USB, Thunderbolt NVMe, internal NVMe, SD, eMMC, eSATA,
  late udev, missing udev, virtual devices, containers, fstab and a device
  replaced during the scan.

Still to validate on real hardware: eSATA, NVMe in a Thunderbolt enclosure,
the internal SD reader of a notebook.
