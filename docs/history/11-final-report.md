# 11 — Final report

## Round 8 (drive health and Secure Erase)

A field case: Calamares could not create a partition on the SATA SSD of a
notebook. The drive timed out, and then acknowledged every write and kept
none. An ATA Secure Erase, after a sleep that unfroze it, brought it back
(14, section 1). Big-Mount now:

- reports the errors of a drive since boot: timeouts on its port, I/O
  errors, a slowed link and SMART, in `--diagnose DISK`, in the diagnosis
  of its filesystems, in `--doctor` and in the new `--gui-drive` dialog,
  also in the launcher;
- erases an internal SATA drive with its own Secure Erase through UDisks2
  (`--secure-erase`, **Erase the whole drive…**), after the user types its
  name, and checks that the old table is gone and a new one is kept.

Tests: boot path 114, library 235, translations 38, packaging 52. The
UDisks2 calls that write and read back the partition table were validated
on a loop device. The erase and the sleep through Big-Mount are left for
the next drive that needs them (14, section 4).

## Round 7 (field report: SDDM and `/dev/nvme` errors, release v2.2.0)

A user reported *Permission denied* on `/var/lib/sddm/state.conf`,
`cat: /sys/block/nvme/removable` and *Error looking up object for device
/dev/nvme* on every command. The cause was found in the
`biglinux-stable` package, not in this code: `big-mount 25.12.23-2237` is
byte for byte the December 2025 script. It reads the SDDM file without
checking, cuts `nvme0n1p1` down to `nvme`, and ignores every option. The
fixed package (26.04.24) had been in `biglinux-testing` for six months. The
messages were reproduced exactly on an NVMe machine with that package.

Auditing this fork against the report found ten smaller problems (F1–F10).
The most visible: `bigmount` run by a user failed with raw errors and a
false "another bigmount is still running"; an unplugged device ended as
"It remains mounted"; two removals of one drive could run at once; and no
version could be traced to its code. All are fixed and tested. There is
now `bigmount --version`, an anonymized read-only `bigmount --doctor`, and
package versions that come from the commit.

Tests: boot path 109, library 179, translations 38, packaging 52,
integration 130 (2 skipped). The new checks fail on the stable script, on
`f547e4b` or on the installed 26.10.22 package. Details:
[12](12-field-report.md), [13](13-versioning-and-doctor.md).

Left open: shipping it through the BigLinux repositories; Thunderbolt
NVMe, SD readers and multi-namespace NVMe on real hardware; looking at the
new dialog on screen; the Plasma symptoms of the reporter's computer,
which are not Big-Mount's (12, section 5).

## Round 6 (the pending validations, release v2.1.3)

With v2.1.2 installed, the remaining items were checked on the machine:

- the Dolphin menu, through Dolphin's own code path;
- accessibility, through the AT-SPI tree that Orca reads;
- Breeze Light at 125 %, and X11;
- the Zenity dialogs of the GNOME edition;
- LUKS, with `dm_crypt` loaded;
- the administrator helper.

That found one high-severity bug: safe removal of an encrypted drive left
it unlocked and would not power it off (B30). It also found a notifier lock
leak that silently disabled the notifier after any restart (B31), an
overclaiming "nothing in the system" message (B32), a helper that accepted
`/` (B33) and a Zenity spacing flaw (B34).

All are fixed. Each fix has a test that fails on v2.1.2: unit 136,
integration 119 (7 checks fail on v2.1.2).

Left for a person: Windows Fast Startup (needs a Windows boot), hearing
Orca, the physical click, the password prompts, other hardware, a real
GNOME session.

## Round 5 (real devices after a reboot, release v2.1.2)

The user installed v2.1.1, rebooted and allowed tests on the connected
devices. The boot was clean (716 ms). The tests found three high-severity
problems in safe removal, all on a USB SSD used by a Docker service
(Immich):

- **B23:** the drive was powered off while `ntfs-3g` was still writing.
  The power-off failed, and the message blamed the drive.
- **B24:** systemd services bound to the mount were stopped without a word.
- **B25:** a container's own mount of the device was not seen, so the
  filesystem could have been reported safe while still in use.

The diagnosis also judged a folder by the root of its partition (B26). It
explained system partitions, swap and whole disks poorly (B27, B28).

All were fixed and tested: 135 unit tests, 110 integration tests (5 of them
fail on v2.1.1), and a real removal, power-off and reconnection of the SSD
in which the service came back by itself. Two mistakes in the first draft
of the fixes were caught before release: FUSE daemon names cut to 15
characters, and a wrong "do not start again" sentence.

## Round 4 (live tests on the real screen, release v2.1.1)

The dialogs and notifications were exercised on the real Plasma desktop of
the development machine, with disposable devices (see 09). Three wording and
layout problems seen there were fixed (B20–B22), and `--busy` on a free
device now says it is not in use. The README shows real screenshots. During
this round a screenshot safeguard failed once (it captured the user's
terminal instead of the dialog); those files were deleted unopened, and the
capture rule now requires class, PID and title to match.

## Round 3 (installed package, release v2.1.0)

The package built from round 2 was installed on the development machine
and tested there:

- integration suite against `/usr/bin/bigmount`;
- a live service restart with a mounted NTFS volume;
- real Plasma notifications;
- root timings.

Two problems found that way were fixed: B16, the lock fd inherited by the
NTFS FUSE daemon, which would have blocked every later run; and B17,
warnings at every login about partitions holding another operating system.

`pkgbuild/PKGBUILD` now builds this fork, because the official repository
does not have the code yet. It gained `pkgbuild/big-mount.install`, which
only prints messages. Releases: `v2.0.0` (round 1) and `v2.1.0` (rounds 2
and 3), each with its package attached.

## Round 2 (branch `feature/bigmount-ng-2`)

Starting point: `master` at `ee044f9`, the modernized version. Mounting at
boot behaves exactly as before. The boot path was measured before and after
(40 ms, 27 processes, both times), and every existing suite still passes.

### Bugs fixed

| # | Finding |
| --- | --- |
| B1 | the administrator process list (other users' processes and paths) was left in `/tmp`, one file per use |
| B2 | a test artifact (a copy of `/usr/bin/tail`) was versioned |
| B3 | every read-only warning left a `notify-send` process waiting indefinitely |
| B4 | unmount races reported false failures; a "successful" unmount that left the mount produced a misleading message |
| B5 | removal did not re-check the disk identity or re-verify mounts before the power-off, and did not lock open LUKS volumes |
| B6 | 22 wrong fuzzy translations produced by `msgmerge` |
| B7 | boot messages, `.desktop` and polkit strings outside the catalog |
| B8 | the busy dialog started with a technical table, without a plain explanation |
| B9 | Enter confirmed "Close these programs?" |
| B10 | an artificial 1 s delay before every notification |

### Improvements

- English source everywhere, one gettext catalog for scripts, `.desktop`
  files and the polkit policy, and a complete pt_BR translation (249
  messages). Boot messages are translated on a terminal and stay English
  in the journal.
- Notifications: a single path. Information disappears after 5 s, problems
  after 15 s and stay in the history, and decisions are persistent dialogs.
  Durations are defined in one place, and
  `kdialog --passivepopup` is the fallback.
- Busy dialog: a plain-language summary and advice from the holder that
  matters most, before the technical details.
- "Writing pending data, do not disconnect" when an unmount takes more than
  2 s.
- Safe removal: race-safe unmount, disk identity checked before every
  irreversible step, final re-verification, LUKS locked before the
  power-off.
- New suites: `tests/i18n-tests.sh`, `tests/package-check.sh` and
  `tests/measure-session.sh`, plus integration cases for a GPT drive with
  two partitions, a vanishing device and an accidental Enter.
- CI runs translations and packaging. `build-package.yml` is documented
  (work branches never trigger an official build) and ignores docs/tests-only
  pushes.
- Documentation and README in English, with English file names.

### Measurements

See 08. Mount → notification went from 1044 ms to 45 ms; everything else is
unchanged.

### Limits and manual validation

See the end of 09. Notably:

- nothing was verified on a real Plasma screen (Breeze, scaling, Orca, the
  Dolphin menu);
- LUKS and read-only images need a kernel with those modules;
- the power-off of a real USB drive and a real boot with the package
  installed are still pending. Installing the package needs root, which was
  not available to the automation.

## Round 1 (merged as PR #1 and #2)

- Boot fixes A1–A14 (see 01): mounting over `/`, the FUSE daemon killed by
  the service, `ntfsfix` on every boot, silent read-only NTFS, USB disks
  with `RM=0`, the FAT regex, stale symlinks, empty directories, untested
  fstab isolation, races.
- Introduced the diagnosis, busy-device inspection, safe removal, the
  notifier, the Dolphin menu, the launcher, the pt_BR translation,
  `/etc/big-mount.conf`, and the test suites.

From round 3 to 2.6.0, `pkgbuild/PKGBUILD` built `ruscher/big-mount`. With the
pull request that brings this work to `biglinux/big-mount`, it builds the
official repository again.
