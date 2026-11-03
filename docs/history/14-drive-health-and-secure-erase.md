# 14 — Drive health and Secure Erase

`bigmount --diagnose DISK` and `bigmount --gui-drive-check` (the **Health** section
of the one application, see [gtk-unification](gtk-unification/08-final-report.md)) tell whether a drive
itself has been failing since the computer was started. For a SATA SSD that
locked itself in a protection mode, `bigmount --secure-erase DISK` (or
**Advanced maintenance → Erase data permanently** in the application) can bring it back to work. That
erase is the only operation of Big-Mount that destroys data, so it only
runs at the user's request, after two confirmations and the administrator
password, and its result is checked afterwards.

## 1. The field case (2026-10-26)

A Semp Toshiba IS 1422 notebook, legacy BIOS mode, with an `AL-SSD-256`
SATA SSD (firmware `HP3C09B5`) that still held a Mac layout (GPT, EFI and
APFS). Calamares (BigLinux Community XFCE live, from a Ventoy USB drive)
stopped at:

```text
Command: sfdisk --force --append /dev/sda
Failed to add partition 'New partition' to device '/dev/sda'.
```

The live session showed what happened:

| Observation | Evidence |
| --- | --- |
| The drive stopped answering | `ata1.00: exception Emask 0x0 SAct 0x80000 SErr 0x0 action 0x6 frozen`, `failed command: READ FPDMA QUEUED`, `qc timeout after 15000 msecs`, `hard resetting link` |
| Reads failed | `I/O error, dev sda, sector 73448 op 0x0:(READ)`, later sector 409672 |
| The kernel slowed the link down | `ata1: limiting SATA link speed to 1.5 Gbps` |
| **Writes were acknowledged and dropped** | `wipefs -a` reported the GPT erased, 64 MiB of zeros were written with `oflag=direct`, `parted mklabel msdos` succeeded. A direct read (`iflag=direct`, caches dropped) of sector 1 still returned `EFI PART` with the old disk identifier |
| SMART said nothing useful | `PASSED`, no reallocated or pending sectors; vendor attributes with implausible raw values (80,085 power cycles in 2,268 hours) |
| Security commands were frozen | `hdparm -I`: `supported`, `not enabled`, `not locked`, `frozen` |

`rtcwake -m mem -s 15` (sleep, wake up by itself) unfroze the drive. A
`SECURITY ERASE UNIT` returned in 0.13 s. Afterwards the drive kept what
was written: 1 GiB of random data written and read back at the start, the
middle and the end of the disk had the same SHA-256, at about 120 MB/s, and
the kernel logged no new error. With an empty MBR, Calamares could install.

Disabling NCQ for the session (`echo 1 > /sys/block/sda/device/queue_depth`)
was also done there. It reduces the timeouts of such drives, but it did not
make the writes stick: only the erase did.

The drive is still suspect: it failed once, and the user was told to keep
copies and replace it if the errors come back.

## 2. Drive health (read-only, as the user)

`bm_drive_health DISK` (`usr/lib/big-mount/lib.sh`) reads:

| Source | What | Why there |
| --- | --- | --- |
| Kernel log of this boot (`journalctl -k -b`) | messages naming the disk, its partitions **or its port** | timeouts are reported on the port (`ata1.00: failed command`, `nvme nvme0: I/O ... timeout`), never with the name of the disk; the port comes from the sysfs path of the disk (`.../ata1/host0/...`) or from the NVMe controller |
| UDisks2 `Drive.Ata` | `SmartFailing`, `SmartNumBadSectors` | readable by every user, already cached by UDisks2 |
| udev (`ata_id`) | `ID_ATA_FEATURE_SET_SECURITY`, `..._ENABLED`, `..._FROZEN`, `..._ERASE_UNIT_MIN`, `ID_BUS` | readable by every user; `hdparm -I` would need root |

Findings, most serious first:

| Finding | Evidence |
| --- | --- |
| `smart-failing` | the drive predicts its own failure |
| `timeouts` | `failed command:`, `qc timeout`, `COMRESET failed`, NVMe `I/O ... timeout` |
| `io-errors` | `I/O error, dev sdX`, `Buffer I/O error on dev sdXN`, medium errors |
| `slow-link` | `limiting SATA link speed` |

Damaged sectors counted by SMART are **shown but are not a finding**. Drives
replace a few of them with spare ones in normal use. The SSD of the
development machine (`KINGSTON SHFS37A480G`) has one, works fine, and an
alarm for it would be the same kind of false "failing disk" warning that
`ioerr_cnt` would give (04). Probing noise (`EXT4-fs (sda): VFS: Can't find
ext4 filesystem`) and a link that comes back up are not errors either. An
`I/O error, dev sdab` is never counted for `sda`.

Where it appears:

- `bigmount --diagnose DISK`: the drive first, then each of its filesystems.
  The exit code is 1 when the drive has a finding.
- `bigmount --diagnose PARTITION` and the **Why can't I write here?**
  dialog: one paragraph saying that the drive reported errors. The dialog
  then offers **Check the drive…**.
- `bigmount --gui-drive-check [DISK]`: the application, opened on **Health**,
  the same page as **Check drive** in `bigmount --gui-drive`.
- `bigmount --doctor`: a warning for each drive with a finding.

The session notifier does not watch drives: kernel errors do not produce
mount events, and a periodic scan would cost power for every user.

## 3. Secure Erase

### 3.1 Which drives

`bm_erase_check` refuses, with the reason shown to the user:

| Refusal | Why |
| --- | --- |
| a partition, or a folder | the command erases a whole drive; the drive must be named |
| a drive without a disk sequence number (`/sys/block/*/diskseq`) | the confirmation is bound to it; without it another drive under the same name could not be told apart |
| the drive of the running system (a system mount point, active swap) | start from a live USB drive instead |
| a removable or hot-plug drive (USB, FireWire, eSATA bay) | USB-SATA bridges may not pass security commands through safely, and a bad one can lock the drive |
| not an ATA drive on an ATA port (`ID_BUS=ata`) | NVMe has other commands (format, sanitize), not covered here |
| no ATA security feature set | nothing to call |
| a security password already set | erasing would need that password; a drive left locked cannot be used at all |

### 3.2 Sequence

1. **What will be lost.** The drive, every partition with label, size and
   filesystem, the time the drive announces, the partition table that will
   be written, and a warning that it cannot be undone. **Cancel is the
   default button.**
2. **Typed confirmation.** The name of the drive (`sda`) must be typed
   exactly. A slip of the mouse cannot erase a drive, and neither can an
   Enter pressed out of habit.
3. **One operation per drive.** The same per-drive lock as safe removal.
4. **Release.** `bm_remove_core release`: every filesystem of the drive is
   unmounted through UDisks2 and every open LUKS volume is locked. Busy
   programs and dependent services get the same dialogs as a safe removal.
   Nothing is ever powered off.
5. **Frozen.** Most firmwares freeze the security commands at power-on.
   The user is asked whether the computer may sleep. As root, `rtcwake`
   wakes it up after 20 s. As a user, logind suspends it and the power
   button wakes it up. Then `Block.Rescan` makes udev run `ata_id` again,
   until the drive is no longer frozen (about 3 minutes of awake time at
   most).
6. **Erase.** `org.freedesktop.UDisks2.Drive.Ata.SecurityEraseUnit` with
   `enhanced=false`. UDisks2 asks for the administrator password (polkit
   `org.freedesktop.udisks2.ata-secure-erase`, `auth_admin_keep`), opens
   the drive with `O_EXCL` (so it refuses a drive in use), sets and clears
   its temporary password, and has the drive read again at the end. The
   disk sequence number seen at confirmation is checked first: a drive that
   took the name in the meantime is never touched. The call may last twice
   the time the drive announced.
7. **Verification.**
   - The old partition table must be gone. If the drive still returns it,
     it accepted the command and did nothing.
   - An empty partition table is written through UDisks2 (`Block.Format`):
     GPT when the computer started in UEFI mode, MBR otherwise, which is
     what an installer on this computer expects. `Block.Rescan` reads it
     again, and it must come back with the expected type and a new
     identifier. Writing the table may ask for the password once more.

### 3.3 Outcomes

| Exit code | Dialog | Meaning |
| --- | --- | --- |
| 0 | **Drive erased** | erased, and a new table was kept: install or partition it |
| 1 | **Unable to erase the drive** | refused (see 3.1), the drive went away, or UDisks2 reported an error |
| 2 | — | wrong usage: a partition was named, or no terminal |
| 3 | **Unable to erase the drive** | still in use; nothing erased |
| 4 | **Unable to erase the drive** | holds the running system |
| 5 | — / **Unable to erase the drive** | cancelled, name not typed, or password refused |
| 9 | — | services depend on it and the user did not agree to stop them |
| 10 | notification | another operation on the drive is in progress |
| 11 | **The drive is still locked** | still frozen after sleeping; nothing erased |
| 12 | **The drive is failing** | the erase was ignored, or the new table was not kept: replace the drive |
| 12 | **Drive erased, not verified** | erased, but the table could not be written; check it by hand |

### 3.4 Design decisions

- **UDisks2, not `hdparm`.** No new privileged code: polkit decides, the
  password is asked by the session agent, and UDisks2 already handles the
  temporary password and the exclusive open. Big-Mount still widens no
  permission. `hdparm` is not a dependency.
- **Not enhanced.** Not every drive supports the enhanced erase, and for
  recovery the normal one is enough.
- **Verification by reading back a partition table.** The symptom is
  "acknowledged and dropped". A write through UDisks2, followed by a fresh
  probe of the drive, is the smallest check that tells it, and it leaves
  the drive in the state an installer expects. It does not test every
  block. A drive that fails again later will show it in the kernel log,
  and the diagnosis will report it.
- **Sleep only with consent.** Suspending interrupts everything else
  running, so it is a separate question, never a side effect.

## 4. Tests

- `tests/lib-tests.sh`, *drive health*: the port of SATA and NVMe disks; the
  kernel lines of the field case give `timeouts io-errors slow-link`, with
  the noise ignored and `sdab` not counted for `sda`; a partition error
  counts for its drive; NVMe timeouts; a healthy boot; one replaced sector
  is not an alarm; SMART failing first; SMART disabled; unreadable log;
  USB bridge; password; a non-numeric estimate.
- *who may be erased*: every refusal of 3.1.
- *Secure Erase: only what was confirmed, and checked afterwards*:
  `bm_erase_run` with UDisks2 simulated: success and the order of the
  calls; another drive under the name; a partition mounted again; LUKS or
  LVM still open; still frozen; password refused; UDisks2 answering
  frozen; the erase ignored (field case), and nothing written on top of
  it; the table not kept; the old identifier read back; the table not
  written.
- *Secure Erase in the terminal and in dialogs*: a wrong or missing name
  does nothing; frozen and sleep refused or accepted; a failing drive; the
  system appearing on the drive meanwhile; Cancel as default; a name that
  is almost right; success shown in a dialog; the drive lock released, and
  respected.
- *release before an erase*: LUKS locked, nothing powered off, even for a
  removable drive.
- `tests/run-tests.sh`, *secure-erase-only-on-request*:
  `SecurityEraseUnit` and `Block.Format` appear once in the shipped code,
  inside `bm_erase_run`. That function is called only by the terminal
  command and the dialog, and the boot script knows nothing about it. A
  call added to the notifier fails this test (checked by mutation).

Validated on hardware:

- the health report of the development machine: three SATA drives, one
  NVMe drive, one USB SSD. Ports, frozen state and erase estimates match
  `udevadm info`, and the replaced sector of one SSD is shown without an
  alarm.
- `Block.Format` (MBR and GPT) and `Block.Rescan` through `bm_gdbus`, read
  back with a new identifier, on a UDisks2 loop device.

Not yet run on hardware: the `SecurityEraseUnit` call and the
sleep-to-unfreeze path *through this code*. The field case used `hdparm`
and `rtcwake` by hand. The next drive that needs it should be erased with
`bigmount --secure-erase`, and the result reported here.
