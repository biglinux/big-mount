# 05 — Tests

| Suite | What | Result (2026-11-02) |
| --- | --- | --- |
| `tests/run-tests.sh new` | the boot run with stubbed `blkid`, `lsblk`, `udevadm`, `findmnt`, `mount`, `ntfsfix`: internal and external devices (USB with RM=0, Thunderbolt NVMe, SD, eMMC, eSATA), fstab, NTFS hibernated/unclean/inconsistent, FAT/exFAT options, Btrfs and others, permissions, labels with quotes, Unicode, `$(…)`, collisions, udev not ready, a disk swapped during the scan, the lock and FUSE daemons, a user running it, no destructive command shipped; **new**: `--help`, `--version`, `--doctor`, every old option and its answer, only the automount shipped, no Python/GTK/dialog/recovery tool | **132 passed** (115 before: 5 Secure Erase checks removed, 22 added) |
| `tests/i18n-tests.sh` | catalog complete and current, placeholders, language at run time, boot messages English in the journal and translated on a terminal | **299 passed**: every check for each of the 31 languages, CJK alignment of `--help` and `--version` |
| `tests/package-check.sh` | `package()` on the checkout: 6 files and one translation per language with their modes and nothing else, dependencies, no file of Big Storage Rescue, systemd unit verifies, `KillMode=process` | **95 passed** (one `.mo` per language) |
| ShellCheck, `bash -n` | everything shipped and the tests | clean |
| `tests/bench.sh SCRIPT` | the boot run against the real devices of a machine, `mount` stubbed | not run this time: the boot path is unchanged (identical without comments), and one disk of the development machine was being imaged |
| `tests/manual-check.sh` | after a real boot: time, journal, status file, `--doctor`, FUSE daemons, nothing graphical running, USB disks left to UDisks | by hand, after installing the package |

Not run: a real boot with the new package (it is not installed on the
development machine; see 07-result.md).
