# 12 — Field report: SDDM permission and `/dev/nvme` errors

Round 7. Starting point: `master` at `f547e4b` (v2.1.3).

## 1. The report

A user wrote that "practically every Big-Mount command" printed:

```text
grep: /var/lib/sddm/state.conf: Permission denied
cat: /sys/block/nvme/removable: No such file or directory
Error looking up object for device /dev/nvme
cat: /sys/block/nvme/removable: No such file or directory
Error looking up object for device /dev/nvme
```

The report added these points:

- it started after an update three to eight weeks earlier;
- the user backs up to USB disks;
- a second computer with a recent BigLinux runs Big-Mount fine, and there
  Big-Mount found a read-only disk and helped to fix it;
- the affected computer also had Plasma and Dolphin problems (invisible
  text, settings that seemed reset, icon spacing in the panel);
- the installed packages differ between the two computers;
- the user was thinking of reinstalling the system.

## 2. Evidence

All of it was gathered on 2026-10-25 on the development machine. That
machine has BigLinux, Plasma 6.7.4, kernel 7.2.12, and an NVMe disk
(`nvme0n1`) with two partitions.

**E1. What the stable repository ships.** The local copy of the
`biglinux-stable` database lists `big-mount 25.12.23-2237`, built on
2025-12-23 22:37 UTC by "BigLinux Package Build". The package was
downloaded from `repo.biglinux.com.br/stable`. Its `/usr/bin/bigmount` is
byte for byte the script of commit `498366d` of `biglinux/big-mount`
("better way to detect LABEL and PARTLABEL", 2025-12-23). That script is
also `tests/bigmount.old.sh` here.

**E2. The fix exists, but did not reach stable.** Commit `cecaf1b` of
`biglinux/big-mount` (2026-04-23) fixed both defects. Its package,
`26.04.24-0149`, is in `biglinux-testing` (built 2026-04-24) and had not
been promoted to `biglinux-stable` six months later.

**E3. Exact reproduction.** The stable script was run as a normal user. To
change nothing, `mount`, `mkdir`, `ln`, `rm` and `ntfsfix` were replaced
by stubs that only print. It printed exactly the five lines of the report:
one for SDDM, and two for each of the two NVMe partitions. Run with
`--diagnose /dev/sdd1`, it printed the same lines, because the script
ignores its arguments.

**E4. Permissions.** `/var/lib/sddm` is `sddm:sddm 0750`. Only root and
SDDM can read `state.conf`.

## 3. Root causes (proven)

| # | Defect in the stable script | Effect |
| --- | --- | --- |
| R1 | `grep ^User= /var/lib/sddm/state.conf` with no readability check | as root (the boot service) it works; when a person runs `bigmount`, it prints *Permission denied* |
| R2 | the parent disk is derived with `sed 's\|[0-9].*\|\|g'`, which cuts the name at the first digit | `sdb1` → `sdb` works, but `nvme0n1p1` → `nvme` and `mmcblk0p1` → `mmcblk`; `/sys/block/nvme/removable` does not exist, and `udisksctl info -b /dev/nvme` fails with *Error looking up object* |
| R3 | arguments are ignored | every `bigmount …` command, including the ones in the README of this fork (`--diagnose`, `--busy`), runs the boot mount as the user |

R2 has a consequence beyond the messages. At boot, run as root, the
removable test always fails for NVMe and MMC devices. So a hot-pluggable
NVMe (Thunderbolt/USB4 enclosure) or an SD card in an internal reader was
mounted under `/mnt` as an internal disk, and `ntfsfix` was run on it when
it was NTFS. NVMe disks in USB enclosures appear as `sdX` and were not
affected. `tests/run-tests.sh old` shows this: `nvme-thunderbolt-hotplug`,
`sd-card` and `nvme-removable-detection` fail on the stable script.

## 4. Why one computer works and the other does not

**Supported by the evidence, not verified on the user's computers:** the
two computers run different packages. Read-only diagnosis, the feature
that "solved the read-only disk" on the second computer, exists only in
this fork (v2.x) or in a manually installed release. The stable script
cannot do it at all. The affected computer has the stable package (E1),
and its messages match it exactly (E3). Reinstalling the system would not
help if it reinstalls the same stable package.

**Not proven:** why it "started three to eight weeks ago". Nothing in the
stable package changed in that period: it is from December 2025. The
messages only appear when a person runs `bigmount`. At boot, as root, the
SDDM line does not exist, and the NVMe lines only go to the journal. A
likely explanation is that the user started to run `bigmount` by hand in
that period, for example following instructions written for the fork, but
this has not been confirmed. `bigmount --doctor` (see 13) now answers that
question on the user's computer. Even the legacy script does not prevent
running it from a checkout:
`bash big-mount/usr/bin/bigmount --doctor` checks the installed
`/usr/bin/bigmount` and names the defect it carries.

## 5. The other symptoms of the report

Invisible text in Dolphin, settings that seem reset and the panel spacing
are **not caused by Big-Mount**, in any version. Big-Mount writes only
these paths:

- `/mnt`, `/media` and `/run/big-mount` (boot);
- `/run/lock/big-mount.lock`;
- `$XDG_RUNTIME_DIR/big-mount-*.lock`;
- `~/.local/state/big-mount/notified`.

It never writes Plasma or Qt settings, themes or `~/.config`. No causal
link is claimed.

For a separate diagnosis, without changing anything:

```bash
bigmount --doctor                          # section "Outside Big-Mount":
                                           #  - files in ~/.config that do not belong to you
                                           #    (left by GUI programs run with sudo; Plasma
                                           #    cannot save them, so settings seem to reset)
                                           #  - packages with newer versions pending
LC_ALL=C pacman -Qkk plasma-workspace dolphin 2>&1 | grep -v ' 0 altered'  # changed files
find ~/.config -maxdepth 2 ! -user "$USER"                       # same as the doctor
```

The usual causes are an update that stopped half-way, a system updated
only in part, a theme not yet ported to the installed Plasma version, and
settings files owned by root. All of them are fixed by a full update
(`sudo pacman -Syu`). Files owned by root are given back with `chown` by an
administrator. Holding Plasma back, or updating only some packages, is
never recommended: Arch-based systems are only consistent as a whole.

## 6. Problems found in this fork during the audit

The current code no longer has R1 to R3: `lsblk` PKNAME and sysfs are used
for parents, `state.conf` is read only when readable, and options are
dispatched. Auditing it against the report still found these:

| # | Problem (v2.1.3) | Fix |
| --- | --- | --- |
| F1 | `bigmount` run by a user: a raw *Permission denied* on the lock file, then the false *another bigmount is still running* | the boot mode explains that it is the job of `big-mount.service` and exits 5. The message is translated: bash resolves `$"…"` while it parses, so the text domain is chosen in a command of its own before the block that prints it. A lock file that cannot be opened has its own message |
| F2 | every unusable target got one generic message; `/dev/nvme0` (the NVMe **controller**, a character device) was not explained | `bm_resolve` classifies `missing`, `controller`, `not-block`, `not-local`, `unavailable`. The controller message names its namespaces from sysfs |
| F3 | `udisksctl`'s *Error looking up object* (no D-Bus error name) was classified `unknown`. A device unplugged during a removal ended as "It remains mounted. Nothing was forced. Error looking up object…" | classified `no-object`. The removal stops with `RM_GONE=1`, and the notification is **Device disconnected**: "check the files when you connect it again" |
| F4 | Take ownership built the UDisks2 object path from the device name (only `-` escaped) | the object path comes from `udisksctl info`, so a name UDisks2 does not know stops before any D-Bus call |
| F5 | two removals of the same drive could run at once (double click on the Dolphin action, or the action plus a terminal) | per-drive `flock` in the private `$XDG_RUNTIME_DIR`, released with `flock -u` even if a notification inherited the fd; exit 10 |
| F6 | a graphical command on a device that could not be found showed a short notification | dialog **Unable to access storage device**, with *Try again* / *Technical details* / *Close*. A folder that is simply not on a local device still gets a notification |
| F7 | the overview table used `printf %-18.18s`, which counts bytes: accented labels were misaligned and could be cut in the middle of a character | `bm_pad` counts characters, and long cells end in `…` |
| F8 | `BIGMOUNT_LIB` was `/usr/bin/../lib/big-mount`, so checks for "the packaged copy" never matched | normalized with `readlink -f` |
| F9 | with no usable last login, files on FAT/NTFS belonged to UID 1000 even if no such account existed. An SDDM user name that no longer exists was used silently. `/etc/login.defs` was ignored | unknown names are reported. The fallback is the first account in `UID_MIN..UID_MAX`, or root, never a made-up UID |
| F10 | no way to tell which code is installed: the version was the build time, and there was no `--version` | see [13](13-versioning-and-doctor.md) |

## 7. Tests

Each fix has a test that fails without it. The suites were run on the
development machine after the last change.

| Suite | Result | Fails on |
| --- | --- | --- |
| `run-tests.sh new` | 109 passed, 0 failed | — |
| `run-tests.sh old` (stable script) | 46 passed, 63 failed | the field-report tests fail there: *Permission denied*, `/sys/block/nvme/`, `udisksctl … /dev/nvme`, `/sys/block/mmcblk/` |
| `run-tests.sh` against `f547e4b` | 8 new checks fail | F1 and F9: user run, lock file, unknown SDDM account |
| `lib-tests.sh` | 179 passed, 0 failed | F2–F7, `--version`, `--doctor` |
| `i18n-tests.sh` | 38 passed, 0 failed | runtime translation of the F1 message; `--version` labels aligned by characters; no obsolete catalog entries |
| `package-check.sh` | 52 passed, 0 failed | commit-derived `pkgver`, a PKGBUILD that survives makepkg writing it back, version file, `conflicts=` |
| `integration.sh` (real UDisks2 mounts of loop images) | 130 passed, 0 failed, 2 skipped | against the installed 26.10.22 package, 13 checks fail; 8 of them are the new ones (disconnected message, concurrent removal, `--doctor`, GUI dialog) |
| `shellcheck -x`, `bash -n` | clean | — |

The new regression tests:

- `field-report-sddm-and-nvme`: two NVMe partitions and an unreadable
  `state.conf`. Nothing may appear on stderr, `/sys/block/nvme/` must not
  be read, and `/dev/nvme` must never be passed to `udisksctl`. The
  `udisksctl` stub now fails, like the real one, for names that are not
  block devices.
- `field-report-mmc-name`, `user-runs-bigmount-without-options`,
  `sddm-names-unknown-account`, `lock-file-cannot-be-opened`.
- In the library: `/dev/nvme` is refused as missing, a real controller
  (`/dev/nvme0` on this machine) as a controller, and a real NVMe
  partition resolves to its namespace. UDisks2 objects come from UDisks2.
  Lock contention, `bm_pad`, and the GUI dialog are covered too.
- In the integration suite: a detached loop device in the GUI; a second
  removal while the lock is held (exit 10, still mounted), then a success;
  `--doctor` leaves the mount table identical and prints none of the
  mounted test labels or `$HOME`.

## 8. Residual risks and what is still open

- **Distribution.** The stable repository keeps shipping the December 2025
  script until BigLinux merges this work into `biglinux/big-mount` and
  promotes the package. That step is outside this repository.
- Thunderbolt NVMe, internal SD readers and multi-namespace NVMe were
  tested with stubs and with this machine's single-namespace NVMe, not on
  that hardware.
- The **Unable to access storage device** dialog was exercised through
  scripted KDialog calls, not looked at on screen in this round.
- The Plasma symptoms were not examined on the affected computer.
