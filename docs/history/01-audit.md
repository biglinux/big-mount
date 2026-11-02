# 01 — Audit

Two audits are recorded here. The first one covers the original script
(commit `871f392`), before the modernization. The second one covers the
modernized version (commit `ee044f9`, merged as PR #1 and #2).

**Proven** means the finding was reproduced by a test or observed on the
development machine: BigLinux, Plasma 6.7.4 on Wayland, kernel 7.2.11,
udisks2 2.11.2, ntfs-3g 2026.7.7, util-linux 2.42.3, bash 5.3.

Severity:

| Severity | Meaning |
| --- | --- |
| **Critical** | can damage the system or data |
| **High** | loss of access, changes data without consent, or exposes private data |
| **Medium** | wrong behavior |
| **Low** | quality or efficiency |

---

## Round 2 — the modernized version

| # | Severity | Kind | Finding | Status |
| --- | --- | --- | --- | --- |
| B1 | High | proven bug, privacy | "Show programs of all users" wrote the output of the root helper (processes **and file paths of every user**) to a `mktemp` file that was never deleted, one more per use | fixed: removed on return, replacement, EXIT/INT/TERM/HUP; the regression test fails without the fix |
| B2 | Medium | proven bug | `tests/.integ.M8uZ/kioworker`, an 84 kB copy of `/usr/bin/tail` left by an interrupted manual reproduction, was versioned by `git add -A tests` | removed, `.gitignore` covers every scratch dir, `tests/package-check.sh` fails on versioned artifacts or binaries under `tests/` |
| B3 | Medium | proven bug | every read-only warning left a `notify-send` process waiting: without a timeout, Plasma 6 keeps notifications that have buttons open indefinitely (measured: still open after 30 s) | fixed: warnings expire after 15 s |
| B4 | Medium | proven by test | unmount race: a mount that disappeared between the check and `udisksctl` was reported as a failure (`NotMounted`); a "successful" unmount that left the mount produced udisks' success text as the error message | fixed: the mount table decides; explicit reason, bounded retries |
| B5 | Medium | risk | removal did not re-check the disk sequence number, did not re-verify that no partition was mounted again before the power-off, and did not lock open LUKS volumes (which blocks the power-off) | fixed and unit-tested |
| B6 | Medium | proven | after changing messages, `msgmerge` produced 22 fuzzy guesses and **all 22 were wrong** (e.g. "%s is still in use" → "Device still in use", losing `%s`). `msgfmt` drops fuzzy entries, so they would have fallen back to English rather than shown wrong text | all reviewed and translated; `tests/i18n-tests.sh` fails on fuzzy, untranslated or placeholder mismatch |
| B7 | Low | proven | boot messages (`--dry-run` output) and the `.desktop`/polkit strings were outside the gettext catalog; a new language required editing three formats | one catalog; resources generated from English templates |
| B8 | Low | UX, proven by rendering | the busy dialog started with a technical table and had no plain-language explanation; an empty gap after the device details | summary and advice first; compact layout |
| B9 | Low | risk | the default (Enter) button of "Close these programs?" was the confirmation | Cancel is now the default button |
| B10 | Low | proven | the notifier waited an artificial 1 s after each mount: 1044 ms from mount to notification | removed: 45 ms |
| B11 | Info | measurement | `lsof` takes 212 of the 236 ms of `--diagnose`. `lsof -b` is fast only because it finds nothing; a scan of the user's own processes took 111 ms but would reimplement the structured `lsof -F` interface | `lsof` kept |
| B12 | Info | measurement | on Plasma 6, `kdialog --passivepopup` sends the same `org.freedesktop.Notifications.Notify` call (seconds × 1000), as app `kdialog` and without action buttons; using it next to `notify-send` would duplicate notifications | used only as a fallback |
| B13 | Info | fact | in `build-package.yml`, `branches: ["*"]` never matches names containing `/`, so `feature/...` branches never asked for an official build | documented; docs/tests-only pushes ignored |
| B14 | Info | fact | gettext 1.0 writes polkit languages as `pt-BR`; polkit matches POSIX names (`pt_BR`, then `pt`) and the policy always used `pt_BR` | normalized by `locale/compile.sh` |
| B15 | Info | environment | this kernel has no dm-crypt target and no iso9660/squashfs: LUKS and read-only image tests cannot run here | covered by unit tests; listed as manual validation |

Found while testing the **installed** package (round 3):

| # | Severity | Kind | Finding | Status |
| --- | --- | --- | --- | --- |
| B16 | High | latent bug, proven by test | the lock fd was inherited by mount helpers; `mount.lowntfs-3g` lives on as the FUSE daemon, so after the first boot with an NTFS mount every later run (`systemctl restart big-mount`, a manual run) would have waited 60 s for the lock and given up | commands that change the system run with fd 9 closed; the test fails without the fix |
| B17 | Low | found live | at every login the notifier warned "No permission to write" about `/mnt/root`, the Btrfs top level of another BigLinux install: nothing can or should be fixed there | partitions holding an operating system are not announced (`--diagnose` still explains them) |
| — | Info | measurement | the first service run right after installing took 1096 ms; the next ones 21–43 ms as root, and a full `systemctl restart` 33 ms (journal timestamps). The first value could not be reproduced (cold caches after installing) | recorded in 08 |

Found by the first real CI runs (round 3):

| # | Severity | Kind | Finding | Status |
| --- | --- | --- | --- | --- |
| B18 | Low | proven | CI had never really run, because every commit carried `[skip ci]`. On Ubuntu 24.04 the translation checks failed: gettext 0.21 has no short `-k` for `msgfmt`, and it formats generated `.desktop` files differently from gettext 1.0 | `compile.sh` uses `--keyword=` (identical output); CI runs in an `archlinux` container, the base of BigLinux, as a normal user |
| B19 | Low | proven | a translation test depended on the disks of the machine running it (a CI container has none); shellcheck 0.11 reports SC2329 on helpers that are called indirectly | the test uses a fake disk; SC2329 allowed in the tests only |

Found by live tests on the real Plasma screen (round 4, v2.1.1):

| # | Severity | Kind | Finding | Status |
| --- | --- | --- | --- | --- |
| B20 | Low | UX, seen live | the busy summary called any program whose current folder was on the device "a terminal" (it was `sleep`) | only shells and terminals are called terminals; other programs are named ("sleep is running inside a folder of this device") |
| B21 | Low | UX, seen live | `bigmount --busy` on a free device said "*Device* is still in use" followed by "None of your programs is using it" | it now says "*Device* is not in use … It can be unmounted" |
| B22 | Low | UX, seen live | at 200 % the diagnosis needed a scroll bar (the device path and a state line repeating the title) | the path moved to the technical details; the state is shown only when it adds something; `ext4` instead of `EXT4` |
| — | Info | translation | `msgmerge` proposed "%s ainda está em uso" ("still in use") for the new "%s is not in use": the opposite meaning | translated by hand; fuzzy entries are rejected by `tests/i18n-tests.sh` |

Found by tests on real devices after rebooting with v2.1.1 installed (round
5, v2.1.2). The machine has a USB SSD with NTFS that a Docker service
(Immich) uses, with `BindsTo=` on its mount unit.

| # | Severity | Kind | Finding | Status |
| --- | --- | --- | --- | --- |
| B23 | High | proven live | after unmounting an NTFS (FUSE) volume, `udisksctl unmount` returns while `ntfs-3g` is still writing. The power-off then failed, and the CLI said "cannot be powered off by the computer" (exit 7), which is wrong for a USB SSD | after the unmount, Big-Mount waits (up to 60 s, with the "do not disconnect" notice after 2 s) until the FUSE daemon of the device has exited. The power-off gets 3 attempts. A failed power-off has its own exit code 8 and message, and 7 is kept for drives that really cannot be powered off |
| B24 | High | proven live | unmounting the SSD silently stopped the Immich service: systemd stops units with `BindsTo=`/`Requires=`/`PartOf=`/`Requisite=` on a mount unit when it goes away | before unmounting, the services that depend on the mount are listed and the user must confirm (dialog: Cancel is the default; CLI: `--assume-yes` or a question on a terminal; otherwise exit 9 and nothing is done). The text says whether systemd starts them again with the mount (`WantedBy=` the mount unit), as it does for Immich |
| B25 | High | proven by test | a bind mount made inside another mount namespace (a Docker volume, `/immich-ruscher` → `/data`) is not removed by the unmount on the host, so the kernel keeps the filesystem in use. Big-Mount judged only the host mount table, so it would have said "safe to disconnect" | such mounts are detected in `/proc/*/mountinfo` (readable by every user). They are shown in the busy view, and the unmount waits for them like for a FUSE daemon. If they stay, the result is an error that names the process. Copies that follow ours (`shared:`/`master:` of our peer group), and plain copies at the same place, vanish with our unmount on this kernel (measured), so they are ignored |
| B26 | Medium | proven live | `--diagnose FOLDER` judged the root of the partition, not the folder. A folder of another user inside a writable partition was reported as writable | the folder is judged under the mount that contains it (`findmnt -T`); new cause `permission-folder` that names the owner and never offers to change it |
| B27 | Low | seen live | partitions of the running system (`/`, `/boot/efi`) were explained as permission problems ("mounted for another user" for the EFI partition) | new cause **System partition**, no fix offered; the busy section is skipped for them (it listed 463 lines of system processes) |
| B28 | Low | seen live | a swap partition was diagnosed as "not mounted"; a whole disk (`/dev/sdd`) as an unmounted filesystem | swap has its own explanation; a whole disk lists its partitions |
| B29 | Low | proven | `--no-power-off` worked but was missing from `--help` | listed |
| — | Info | caught before release | the first version of the B23 fix compared `/proc/PID/comm` with `mount.lowntfs-3g`, but the kernel keeps 15 characters (`mount.lowntfs-3`), so the internal NTFS and exFAT FUSE daemons were not recognized | the list uses the truncated names; a unit test covers it |
| — | Info | caught before release | a draft message said bound services "do not start again" when the device comes back; for Immich that is false | the text depends on `WantedBy=` |

Found while validating what was still pending, with v2.1.2 installed (round
6, v2.1.3):

| # | Severity | Kind | Finding | Status |
| --- | --- | --- | --- | --- |
| B30 | High | proven | safe removal started from the folder of an encrypted (LUKS) volume left the volume **unlocked**, and on a USB drive it would not have powered the drive off: `lsblk` reports no parent for a device-mapper device asked about directly, so the "drive" was the decrypted volume itself | the drive is found through `/sys/class/block/*/slaves` when there is exactly one parent; a real LUKS integration test replaces a placeholder skip (v2.1.2 fails it) |
| B31 | Medium | proven live | the notifier's `findmnt --poll` inherited the single-instance lock. When the notifier stopped (here: replaced after the upgrade), `findmnt` lived on as an orphan holding the lock, and every new notifier quit silently, until the next mount event | children never get the lock fd; `findmnt` runs with a parent-death signal, so the kernel ends it with the notifier |
| B32 | Low | proven live | as a normal user, `--busy` said "nothing in the system is using it" while a root process held the device: a user cannot see other users' processes | the user is told that none of their programs uses it and that other users' programs are only visible to an administrator; root keeps the plain message |
| B33 | Low | hardening | the administrator helper accepted mounts of the running system: `bigmount-holders /` listed every process of the machine | refused; the running system is never removed anyway |
| B34 | Low | seen live | in Zenity (GNOME), no empty line after the key/value block and lists, unlike KDialog | same spacing in both |
| — | Info | test suite | the integration suite could leave unlocked LUKS loop devices and an orphan `findmnt` behind | its cleanup locks LUKS volumes; the notifier fix removes the orphan |

Not changed, on purpose:

- **Boot path.** It is already minimal: 27 processes, of which one `blkid`,
  one `lsblk` and one `udevadm` are shared. Each mounted partition costs one
  `findmnt`, one `mkdir`, one `mount` and one `ln`. Folding the `findmnt
  --fstab` calls into one would change how fstab tags are matched.
- **The KDialog/notification approach.** Qt/PySide6 was not added. KDialog
  and the notification server cover every interaction.

---

## Round 1 — the original script

| # | Severity | Finding | Fix |
| --- | --- | --- | --- |
| A1 | Critical | a volume labelled `..` was mounted on `/mnt/..`, i.e. **over `/`**; `.` hid `/mnt` | labels validated, control characters removed |
| A2 | Critical | the NTFS FUSE daemon ran inside `big-mount.service`; `systemctl stop/restart big-mount` killed it under the applications using the volume | `KillMode=process` |
| A3 | High | `ntfsfix` on every boot set the NTFS dirty bit ("Volume is scheduled for check"): chkdsk on every Windows boot, `ntfs3` refuses writes | removed |
| A4 | High | hibernated/Fast Startup NTFS: ntfs-3g 2026.7 mounts it read-only **silently**; older versions refused and the partition vanished. Nobody told the user | real state recorded, notification, `ro` retry for exit 13/14/15 |
| A5 | High | the only USB check needed `udisksd` and udev to be ready at boot; USB HDDs/SSDs report `RM=0` | kernel and udev facts combined (see 02) |
| A6 | Medium | `grep 'TYPE=".*fat.*"'` crossed fields: an ext4 partition with a GPT name containing "fat" got FAT options and never mounted | only the `TYPE` value is compared |
| A7 | Medium | stale `/mnt/<device>` symlinks pointed to another disk after the disks changed order | refreshed |
| A8, A9 | Medium | LUKS, LVM, RAID members, untyped partitions, `/dev/mapper`, loop and zram got a `mkdir` and a failing mount, leaving empty directories | skipped; created directories removed on failure |
| A10 | Medium | silent failures | journal priorities, `/run/big-mount/status`, notifier |
| A11 | Medium | tests read the real `/etc/fstab` (one passed for the wrong reason) and could run the real `mount` from a `noexec` checkout | `findmnt` stub, interlock |
| A12, A13 | Low | no lock, no identity check between scan and mount | `flock`, `diskseq` |
| A14 | Low | 194 processes per run | 27 |
| A15 | Low (documented risk) | `umask=000` + `exec` on internal FAT/NTFS | kept as default; opt-in `PERMISSIONS=` |
| A16–A18 | Info | root-owned ext4 roots look read-only; stale os-prober mounts block removal; Plasma's own `lsof` sees only the user's processes | diagnosis tools |

The details of each finding live in the documents 02–10.
