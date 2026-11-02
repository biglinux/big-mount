# 15 — Drive manager: architecture

`bigmount --drive` (terminal) and `bigmount --gui-drive` (window) diagnose a
drive, mount it without changing it, and copy files off it. Both are thin:
every fact and every operation comes from one engine.

## 1. Layout

```text
usr/bin/bigmount                    boot automount; anything else loads cli.sh
usr/lib/big-mount/
  cli.sh, lib.sh, ui.sh, doctor.sh  existing modes (reused, see 3)
  drive.sh                          --drive: commands, JSON, usage, exit codes
  drive-detect.sh                   one lsblk snapshot: drives, volumes, stacks
  drive-diag.sh                     health level, SMART, read-only mounting
  drive-copy.sh                     preflight checks, jobs, supervisor, reports
  drive-recovery.sh                 ddrescue, TestDisk, PhotoRec
  drive-tui.sh                      the interactive terminal menus
  drive-gui.py, gui/                the application (GTK 4, libadwaita), calls --drive ... --json
  bigmount-drive-helper             the only new privileged code (polkit)
```

The window has no recovery logic. It talks to `bigmount --drive ... --json` only
through `gui/engine.py`, which runs it with `Gio.Subprocess` (a list of arguments,
never a shell line) without blocking. `tests/gui-tests.py` checks that the code
has no `shell=True`, no `os.system` and no other toolkit.

## 2. Nothing of this runs at boot

`usr/bin/bigmount` without options never reads these files, and `cli.sh` only
loads them when `--drive` or `--gui-drive` is asked for. `tests/drive-tests.sh`
checks both. Python and GTK are only touched by `--gui-drive`. The automount and
its policy (removable devices belong to UDisks2 and the desktop) did not change.

## 3. What was reused

| From | Used for |
| --- | --- |
| `bm_facts`, `bm_mounts`, `bm_parse_pairs` | device facts |
| `bm_drive_health` | kernel log and UDisks2 SMART. Extended: it now knows the USB port of a disk (`usb 1-9.1: reset…`) |
| `bm_diagnose_write`, `bm_cause_text` | why a mounted volume cannot be written, in the same words as `--diagnose` |
| `bm_remove_core`, `bm_unmount_all`, `bm_drive_lock` | unmounting, with every check of safe removal |
| `bm_udisks`, `bm_doc_*`, `bm_ui_show` | UDisks2 calls, text output |

## 4. `--gui-drive` already existed

It used to open the drive check with Secure Erase. Now:

Superseded by [gtk-unification](gtk-unification/03-architecture.md): both flags
now open one GTK 4 and libadwaita application, `--gui-drive-check` on the health
of the drive. The PySide6 window and the dialog check are gone; Secure Erase is
still only in `bm_erase_run`.

## 5. Commands

```text
bigmount --drive                         interactive, needs a terminal
bigmount --drive list | inspect | diagnose [--smart] | report
bigmount --drive mount DEV [--read-only] [--protect] [--remount] [--read-write]
bigmount --drive unmount | protect | unprotect | unlock
bigmount --drive destinations --source FOLDER [--need BYTES]
bigmount --drive copy --source S --destination D [--item PATH]...
bigmount --drive jobs | status ID [--watch] | pause ID | cancel ID
bigmount --drive resume ID [--retry-deferred]
bigmount --drive image --source DEV --image FILE [--map FILE] [--retries N]
bigmount --drive partitions TARGET
bigmount --drive carve --source IMAGE --destination FOLDER
```

`--json`, `--dry-run` and `--help` are available where they make sense. Exit
codes: 0 done, 1 error, 2 usage, 3 busy, 4 running system, 5 not authorized,
20 refused by a safety check, 21 no space, 22 finished but files were not copied
or the check found differences, 23 cancelled or paused, 24 a device went away or
did not answer, 25 a tool is missing.

## 6. Levels of health

`bm_ds_level` never calls a drive healthy. The word used is "no alerts", and it
says what that rests on.

| Level | Meaning |
| --- | --- |
| `critical` | the drive reports failure, unreadable sectors, or 3+ read errors |
| `attention` | timeouts, 3+ USB resets, replaced sectors on a hard disk, one read error, CRC errors |
| `normal` | nothing found, and it says in what: SMART and log, log only, SMART only |
| `unknown` | neither the log nor SMART could be read |
| `na` | a disk image |

The field case in numbers: the Seagate of `12` said `PASSED` with 1,848 pending
sectors. The raw counters decide, not the verdict. Diagnosis itself never reads
the device: only `/proc`, `/sys`, udev, UDisks2 and the journal. SMART is read
only on request, because it asks for a password and took over a minute through
that USB bridge.

## 7. Dependencies

Required, as before: `bash`, `udisks2`, `util-linux`, `ntfs-3g`, `lsof`. Optional,
each detected at run time and explained when missing: `rsync` (copying),
`smartmontools`, `ddrescue`, `testdisk`.
