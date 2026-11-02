# 09 — Testing

## Suites

| Suite | What it uses | Result on the development machine |
| --- | --- | --- |
| `tests/run-tests.sh new` | stubs for `blkid`, `lsblk`, `udevadm`, `udisksctl`, `findmnt`, `mount`, `ntfsfix`; paths rewritten to a scratch dir | **115 passed, 0 failed** |
| `tests/run-tests.sh old` | the original script (byte for byte the `biglinux-stable` package 25.12.23), as a reference | its failures are the bugs that were fixed (46 passed, 63 failed) |
| `tests/lib-tests.sh` | the library with simulated facts | **261 passed, 0 failed** |
| `tests/i18n-tests.sh` | the catalog, the generated resources, runtime language selection | **38 passed, 0 failed** |
| `tests/package-check.sh` | `package()` of the PKGBUILD on the checkout | **99 passed, 0 failed** |
| `tests/integration.sh` | disposable images as loop devices mounted by UDisks2, no root; GUI flows with scripted clicks; `BM=/usr/bin/bigmount` tests the installed package | **133 passed, 0 failed, 1 skipped** |
| `shellcheck -x` | shipped code, tests, locale scripts | no findings |
| `bash -n`, `msgfmt --check`, `desktop-file-validate`, `xmllint`, `systemd-analyze verify` | — | pass (part of the suites above) |

The drive manager has three more suites (`tests/drive-tests.sh`,
`tests/gui-tests.py`, `tests/drive-integration.sh`): see
[18](18-drive-final-report.md).

Results of round 8 (2026-10-26), after the last change. What the tests
of round 8 prove is in [14](14-drive-health-and-secure-erase.md), section
4; for round 7, see [12](12-field-report.md).

Skipped in the integration suite: the nested-mount case, which needs root
to create (covered by the unit suite). LUKS runs when `dm_crypt` is loaded
(`sudo modprobe dm_crypt` on a kernel that does not load it by itself); in
round 7 it was not loaded, so it was skipped.
ISO 9660/SquashFS, skipped in earlier rounds, now run.

Double and nested mounts need root to create, so they are covered by the
unit suite instead.

`shfmt` is not installed here and is not used. The code has a deliberate
3-space style in `bigmount` and 4 spaces in the tests, and reformatting
stable code would be a cosmetic change with regression risk.

## Running

```bash
bash tests/run-tests.sh new
bash tests/lib-tests.sh
bash tests/i18n-tests.sh
bash tests/package-check.sh
bash tests/integration.sh                       # needs an active local session
BM=/usr/bin/bigmount bash tests/integration.sh  # against the installed package
bash tests/bench.sh big-mount/usr/bin/bigmount 20
bash tests/measure-session.sh
```

CI (`.github/workflows/tests.yml`, on pull requests and on demand) runs in an
`archlinux` container, with the same tools as BigLinux, and as a normal
user. It runs syntax, shellcheck and every suite except `integration.sh`,
which needs a desktop session with UDisks2. The first green run is
`39802738847`: 92 / 100 / 33 / 41.

What only a person can check is guided by `tests/manual-check.sh`. It runs
inside the desktop session, prepares disposable devices, opens the real
notifications, dialogs and Dolphin menu, and records the answers in
`big-mount-manual-check.txt`. After rebooting with the package installed,
`tests/manual-check.sh --after-boot` collects the boot time, the journal and
the status file, and checks that no NTFS FUSE daemon holds the big-mount
lock.

## Safety of the tests themselves

- Every stub refuses to run without `TESTROOT`.
- `run-tests.sh` and `bench.sh` abort if any disk tool does not resolve to
  its stub. That interlock was added after an incident: on a `noexec`
  directory, bash skipped a stub and ran the real `ntfsfix`/`mount` as a
  normal user. Both refused, and nothing happened.
- The integration suite only touches image files, refuses to run as root
  and releases everything in an `EXIT` trap.
- `package-check.sh` fails if any scratch file or binary is versioned
  (a copy of `/usr/bin/tail` had been committed by mistake once).
- Mutation checks were run on the new tests: each one was made to fail
  against a broken version before being trusted. For example, the
  temporary-file privacy test first passed even without the fix, because
  `TMPDIR` was not exported. It was corrected and now fails without the fix.

## Coverage

**Devices:**

- internal SATA/NVMe;
- USB HDD/SSD with `RM=0` (each signal alone);
- multi-partition USB, GPT disk with ext4 + FAT (real);
- Thunderbolt NVMe, SD, eMMC, eSATA;
- similar names (`sda1`/`sda10`);
- virtual devices, containers;
- device replaced during the scan or during a removal;
- device that disappears.

**Filesystems:**

- healthy NTFS, hibernated NTFS (real image) and silent fallback;
- inconsistent NTFS;
- FAT32, exFAT;
- ext4 with recorded errors, Btrfs, XFS, F2FS;
- HFS+ (unit);
- unknown types, read-only.

**States:**

- rw;
- clean `ro` (the remount is really performed);
- no permission;
- partition holding an operating system (Btrfs `@`, Windows);
- write-protected;
- busy (shell with cwd, reader, writer, kioworker);
- refused then completed unmount, partial failure, mount reappearing;
- inconsistent udisks answers;
- running system;
- no session, no notification server, no KDialog.

**Notifications:**

- 5 s transient information;
- 15 s warnings with actions;
- exactly one path;
- body escaped;
- `kdialog --passivepopup` fallback;
- plain text without a desktop;
- once per device and cause.

**Languages:**

- `LANG=C`, `en_US.UTF-8`, `pt_BR.UTF-8`;
- an untranslated language (`de_DE`), the `LANGUAGE` fallback chain;
- an incomplete catalog (the missing entry falls back to English);
- placeholders kept, Unicode and long values;
- journal kept in English.

**Security:**

- no destructive command in shipped code;
- no closing of writers, shells, session or foreign processes;
- reused PIDs never signalled, SIGTERM only;
- wrong partition never unmounted;
- no false success;
- labels with `$()`, backticks, quotes, `..`, Unicode and HTML never run
  or inject anything;
- config values never executed or used as printf formats;
- dialogs never confirm by themselves, and Enter is safe;
- the administrator process list is never left behind.

## Validated on the installed package (Plasma 6.7.4, Wayland)

- `BM=/usr/bin/bigmount tests/integration.sh`: 97 passed, 0 failed,
  3 skipped (same as the checkout).
- `systemctl restart big-mount` with `/mnt/Basic_data_partition` (NTFS)
  mounted: the `mount.lowntfs-3g` FUSE daemon stayed alive and the volume
  stayed readable. The old version killed it.
- Real notifications in the session: captured with `dbus-monitor`, app
  "Big-Mount", `desktop-entry=big-mount`, 15 s, actions "details"/"help",
  77 ms after the mount, and no `notify-send` left after 16 s. This test is
  what found B17 (see 01).
- Language selection of the installed files (`C`, `en_US`, `pt_BR`,
  `de_DE` → English), and the polkit action registered with its exec path.

## Validated live on the Plasma screen (round 4)

Dialogs were opened by the real `kdialog` on the user's desktop (Breeze,
dark, pt_BR and English), with disposable devices, and captured. A
screenshot is taken only after KWin (`kdotool`) confirms three things: the
active window has class `org.kde.kdialog`, it belongs to the PID that was
just started, and it has the expected title.

That rule exists because a first attempt identified the window by PID
alone, and `kdotool search --pid` without a pattern returned an unrelated
window (the user's terminal). Those captures were deleted without being
opened.

| Check | Result |
| --- | --- |
| diagnosis at 100 %, 150 %, 200 % (`QT_SCALE_FACTOR`) | readable; 200 % needed a scroll bar, fixed (B22) and captured again without one |
| busy dialog | plain summary first; the wrong "terminal" wording was found here (B20) and fixed |
| "Close these programs?" | **Cancel** carries the default focus frame: Enter closes nothing |
| closing a dialog | equals Cancel: the busy device stayed mounted, exit code 3 |
| safe removal of a free device through `--gui-remove` | unmounted, then "Device unmounted" shown 0.35 s later, 5000 ms, transient |
| read-only warning from the notifier | shown 2.42 s after the mount, 15000 ms, kept in the history |
| real disks, read only (`--diagnose`, `--busy`) | the USB SSD is recognized (`usb`, `hotplug=1`) and writable; internal NTFS ok; the contradictory `--busy` wording on a free device was found here (B21) |

The README screenshots are these real captures.

## Validated on real devices after a reboot with v2.1.1 (round 5)

| Check | Result |
| --- | --- |
| boot | 716 ms in `systemd-analyze blame`; `/mnt/Basic_data_partition` (NTFS), `/mnt/root` and `/mnt/Dados` (Btrfs) mounted read-write; status file correct; notifier running |
| `--diagnose` on every device | found B26–B28 (folder judged at the partition root, system partitions, swap, whole disk, a 463-line busy section) |
| `--busy` on the USB SSD | found B25: the Docker volume of the Immich service (`tini`, `/data`) |
| `--safe-remove` of the USB SSD with v2.1.1 | unmounted, power-off failed (ntfs-3g still writing, B23), the CLI blamed the drive, and Immich was stopped without warning (B24) |
| the same with this version | without `--assume-yes`: exit 9, nothing touched; with it: exit 0 in 5.1 s, powered off after ntfs-3g and the containers ended (journal order in 06) |
| reconnection (USB port toggled through sysfs) | mounted again in 5 s, read-write, clean; Immich started again by itself |
| FUSE daemons by name | the internal `mount.lowntfs-3g` is found despite the 15-character `comm` |

The integration suite checks the new release logic with an NTFS image held
by a bind mount in an unprivileged mount namespace. Against the installed
v2.1.1 it fails 5 checks, and against this version none.

A root-made namespace and an unprivileged one behave the same here: a plain
copy of the mount vanishes with the unmount on the host, and a bind mount
made inside the namespace survives it (kernel 7.2.11).

## Validated with v2.1.2 installed (round 6)

| Item | How | Result |
| --- | --- | --- |
| USB SSD connected during boot | boot of round 5 | mounted by UDisks under `/run/media`, absent from the status file and from `/mnt` |
| Dolphin menu | `KFileItemActions` probe (Dolphin's code path) + KIO launch | correct entries in pt_BR/en, folders only; both actions launch, and the removal completes after "Try again" |
| Accessibility (what Orca reads) | AT-SPI tree of every dialog, buttons pressed through AT-SPI | titles, plain text and named buttons; default focus on the safe button; Cancel focused in "Close these programs?" |
| Breeze Light, 125 % | temporary `XDG_CONFIG_HOME`, `QT_SCALE_FACTOR=1.25` | readable, no scroll bar |
| X11 | XWayland client | same layout and accessibility |
| GNOME edition (Zenity 4.2) | `BM_UI=zenity` | diagnosis, busy dialog, options list and "Close these programs?" (Cancel focused; Cancel closes nothing, nothing unmounted); spacing fixed (B34) |
| LUKS | real encrypted loop drive formatted through UDisks | B30 found and fixed |
| administrator helper | run as root through sudo against a device held by a root process | lists the holder; refuses `/`, `/home`, `/boot/efi` (B33) |
| notifier after an upgrade | replaced the running v2.1.1 notifier | B31 found and fixed |

## Manual validation still needed (needs hardware or a person)

1. Windows Fast Startup: enable it in Windows, shut Windows down, start
   BigLinux. `/mnt/Basic_data_partition` must come up read-only, with one
   notification after login. (On this machine `hiberfil.sys` currently has
   no hibernation image, so the partition is mounted read-write.)
2. Hearing Orca read the dialogs (the AT-SPI tree it uses was checked).
3. The physical right-click in Dolphin (its code path was checked).
4. The password prompts of "Show programs of all users" (pkexec) and
   "Become owner" (UDisks), both `auth_admin_keep`.
5. Power-off of a USB HDD; eSATA, Thunderbolt NVMe, an internal SD reader.
6. A real GNOME session, and several users logged in at once.
