# 18 — Drive manager: tests and status

Results on the development machine (2026-10-30). The architecture is in
[15](15-drive-architecture.md), the copy engine in [16](16-drive-copy-engine.md)
and security in [17](17-drive-security.md).

## 1. Suites

| Suite | What it uses | Result |
| --- | --- | --- |
| `tests/drive-tests.sh` (new) | fixtures instead of the machine, runs in CI | **180 passed, 0 failed** |
| `tests/gui-tests.py` (new) | the window off screen, a stand-in for `bigmount`, runs in CI | **37 passed, 0 failed** |
| `tests/drive-integration.sh` (new) | real filesystems on loop devices, real UDisks2, real LUKS, device-mapper, by hand | **173 passed, 0 failed** |
| `tests/run-tests.sh new` | boot path | 114 passed, 0 failed (unchanged) |
| `tests/lib-tests.sh` | library | 236 passed, 0 failed (one new) |
| `tests/i18n-tests.sh` | translations | 38 passed, 0 failed |
| `tests/package-check.sh` | PKGBUILD | 69 passed, 0 failed (was 52: the new files) |
| `tests/integration.sh` | existing real scenarios | 134 passed, 0 failed, 1 skipped (needs root) |
| `shellcheck -x`, `bash -n` | as in CI | no findings |

`shfmt` was not run: it is not installed here, and the project had no `shfmt`
configuration to follow. `pytest` is not used: the window tests need only the
standard library.

## 2. What `drive-integration.sh` proves, on real devices

Everything is on disposable images; a guard refuses any device it did not create.

| Scenario | Result |
| --- | --- |
| ext4, Btrfs, XFS, NTFS, exFAT, FAT32 | mounted read-only, confirmed by the mount table, writing fails |
| ext4 with a dirty journal | mounted, and the image is byte for byte what it was |
| Unicode, Latin-1, specials, depth, links | identical tree; links are not followed |
| Items, conflicts (skip, backup, overwrite) | as documented |
| Refusals (same folder, inside, same filesystem, read-only, no room, outside items…) | refused, right exit code |
| Two partitions of one disk | recognized as the same disk |
| Pause, cancel, supervisor and rsync killed as by a power cut | seen as interrupted, resumed, identical tree |
| Real read errors (dm-error) | good files saved, the bad one reported and not counted |
| A read that hangs (dm-delay) | file set aside, the next ones saved, retried later |
| Source unmounted during the copy, back at another mount point | noticed (exit 24), found by UUID, finished |
| Destination full | reason named (exit 21), no partial file with a final name |
| LUKS | locked is seen and refused; unlocked through UDisks2 from the window |
| `protect` through the helper | the kernel confirms it, the device does not change, system disk and bad names refused |
| The running system | `unmount /`, `/home`, `/boot/efi` refused |
| TestDisk, PhotoRec (the real tools) | table listed; a deleted picture found; the image unchanged |
| The menus in a real pty | a complete copy; no colours or boxes in a plain terminal; `NO_COLOR` |
| The window with the real engine | preflight, copy, full check, report |

Also verified read-only on the real machine: the Seagate of `12` (a failing disk) is
reported as critical from the kernel log, in 0.15 s, without any read from it.

## 3. Bugs the real scenarios found

- Btrfs: the first mount of a UUID was taken, so a destination under `/` became
  `/home/var/tmp/…`.
- A file with read errors was counted as copied, because rsync logs it first.
- Names in Latin-1 made the log parser skip lines, so progress never reached 100%.
- Errors of the receiver (disk full) only go to standard error.
- `resume` read the previous state before the new supervisor started.
- `"${A[@]: -8}"` is empty when the array is shorter. **This one also affected
  `--diagnose`, in existing code**: the technical report left out the kernel
  messages when there were few.
- Going back in the assistant replaced the chosen destination, with one that was
  not recommended.
- Icons did not appear when Qt only searched its own resources.
- Unlocking in the window called a D-Bus method that does not exist in PySide6.

Found later, by making the screenshots and a real transcript for the README:

- `--drive status ID` exited with 1 for a job that was read correctly.
- `report --anonymize` kept the UUID, and the label in mount points and titles.
- The list of drives shrank and cut model names, and the window opened at 1109 px
  because a job page reserved room for buttons it never shows together.
- A window closed while a command ran raised an exception from the signal.
- A line of raw state (`running 61000000`) in the output of a copy without a terminal.

Found by opening the installed window on a real screen: with Plasma fonts in Portuguese
the five tools of a drive did not fit in one row, the last was cut, and a horizontal
scroll bar appeared. Off screen, with other fonts, they fit.

One crash remains unexplained: `malloc(): unaligned tcache chunk detected`, once, in
the screenshot script, when it changed the palette of the application with a second
window still around. The manager never does that. It did not happen again in 6 more
runs of that script, nor in 12 runs of one window with the real engine, under load,
with devices coming and going. The dark picture now runs in a process of its own.

## 4. Status against the definition of done

| # | Item | Status |
| --- | --- | --- |
| 1 | `--gui-drive` opens a working window | **Tested**: the installed package on a real Plasma 6.7 screen (Wayland, Portuguese, real drives), and off screen with the real engine. Opened and read on screen; a copy through the window ran off screen only |
| 2 | `--drive` terminal manager | **Tested**, in a real pty |
| 3 | Consistent identification | **Tested** on SATA, NVMe, USB (real) and fixtures; **SD and eMMC by fixture only** |
| 4 | Diagnosis explains problems | **Tested**, including a real failing disk |
| 5 | Mounting respects integrity | **Tested** |
| 6 | Copy between devices | **Tested** |
| 7 | Real, understandable progress | **Tested** |
| 8 | Safe cancel | **Tested** |
| 9 | Resume | **Tested**, per file |
| 10 | Source and destination protections | **Tested** |
| 11 | Reports reflect results | **Tested** |
| 12 | Automated tests pass | **Tested** |
| 13 | Does not weigh on the system | **Tested** for boot (nothing loaded); no long measurement of the window |
| 14 | KDE and UDisks2 integration | **UDisks2 tested. Dolphin and launcher entries are generated and validated, but not clicked** |
| 15 | Package stays installable | **Tested**: built from `master` with `makepkg`, installed with `pacman -U` over the December 2025 script, `pacman -Qkk` clean, polkit action registered. Both integration suites pass against `/usr/bin/bigmount` |
| 16 | Old functions still work | **Tested**: the old suites, unchanged, and `--gui-drive-check` |
| 17 | Documentation | Done |

## 5. Not validated

- **pkexec and polkit**: the policy is installed and known to polkit, but the helper
  only ran through `sudo` in the tests. The password dialog was not seen.
- **Real ddrescue**: it is not installed here, and nothing is installed without
  asking. The job around it was tested with a stand-in, so its options
  (`--idirect`, `--no-scrape`, `--retry-passes`) and resuming from a real map are
  not proven. The map parser was tested on a sample in the documented format.
- **`smart` of the helper on a real disk**: not run, to spare the failing disk and
  not to ask for a password. The parser was tested on the real values of that disk.
- **Unplugging for real**: the disconnect is simulated with a lazy unmount in the
  test only. Plug events in the window (`udevadm monitor`) were not exercised.
- **LVM, RAID and multi-device Btrfs**: detected from fixtures, not from real ones.
- **A screen reader**: names and focus are tested, not the experience.

## 6. Known limits and risks

- Resuming works per file: a large interrupted file starts over.
- Unmounted XFS and Btrfs with an unclean log are not opened: UDisks2 does not
  accept their no-replay options. The manager explains this and suggests an image.
- Protection (`--protect`) lasts until the drive is disconnected. A click in Dolphin
  after reconnecting mounts it read-write again, which is the policy of UDisks2 and
  the desktop, left unchanged on purpose.
- Clicking a failing disk in Dolphin before the manager opens can still write to it.
- A file that fails read is lost for that copy even if part of it was readable: the
  manager does not save partial files. An image keeps what can be read.
- The first read of a damaged area can take minutes, and `cancel` waits for it.
