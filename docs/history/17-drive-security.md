# 17 — Drive manager: security

## 1. Privileges

The window, the menus, the commands and the copy supervisor all run as the user.
Mounting, unmounting and unlocking go through UDisks2. What needs root goes through
one small helper, `usr/lib/big-mount/bigmount-drive-helper`, started by `pkexec`
(polkit action `org.biglinux.big-mount.drive-helper`, `auth_admin_keep`, with the
path of the helper fixed in the policy).

| Helper command | What it does | Refuses |
| --- | --- | --- |
| `protect DEV` | `blockdev --setro` on the device and everything it sits on | the running system (exit 4); a drive with a volume mounted for writing (exit 3) |
| `unprotect DEV` | `blockdev --setrw` on the same chain | the running system |
| `smart DEV` | prints `smartctl -H -A -i`, and never starts a self-test | more than one drive |
| `partitions DEV STOP [search i386\|gpt]` | prints `testdisk /list`, or its analysis, until the stop file appears | |
| `image DEV FILE MAP RETRIES STOP` | `ddrescue` to a file | see below |

It gets a clean environment from pkexec, resets `PATH`, reads its library from a
fixed path, and checks arguments before using them: only `^/dev/[A-Za-z0-9._/:+-]+$`
without `..`, which must be a block device.

`image` writes as root, so it only writes into a real folder (no symlink in the
path) owned by the user who asked, and to files that are not links and belong to
that user; files it creates are handed to the user before `ddrescue` starts. It
refuses a file on the disk being read. The user cannot signal a root process, so
`cancel` creates a stop file that the helper watches, and so does Stop for
`partitions`: the stop file of both is checked like the image, a path in a real
folder of the user that is not a link, and the helper only tests that it exists.

The folder is the user's, so a name could be swapped for a link while root works.
The image, the map and `MAP.bak` are therefore opened once (a new file with
`O_EXCL`, which never follows a link), checked through `/proc/PID/fd` (the path
they really are, a regular file with one name, of the user or new), and only those
descriptors are used afterwards, by `ddrescue`, `chmod` and `chown`. ddrescue keeps
its own map in a folder of root under `/run`, where it can make its backup, and the
helper copies it to the user's map every 2 s, the previous one first to `MAP.bak`.
A map cut by a power failure is resumed from `MAP.bak`. `tests/drive-integration.sh`
swaps the names for links to a file of root during a run, and checks that file did
not change.

## 2. What is never done

No `fsck`, `mkfs`, `wipefs`, `dd`, `umount -f`, `umount -l`, `kill -9`, `fuser -k`,
`chmod -R`, `chown -R`, `btrfs check --repair`, `ntfsfix`, `eval`.
`tests/drive-tests.sh` greps the shipped code for these, so adding one fails the
suite. The one operation of Big-Mount that destroys data is still only the Secure
Erase of `14`, with its own confirmations.

## 3. Data from devices is untrusted

Labels, models and file names can hold anything:

- JSON goes through `bm_js`. Terminal output has control characters replaced.
- Every label of the window is plain text (`use_markup=False` in `gui/widgets.py`;
  tested with `<b>&amp;<span foreground='red'>x` as a drive and volume name), and
  so are the dialogs of `dialog.py`.
- Commands get arguments as separate words. Items go to rsync through
  `--files-from --from0`, so a file named `-rf` is a name.
- Paths with a line break are refused, because the job files are line based.
- Job ids must match a fixed pattern, so `../../etc` is not a job.

## 4. Passwords of encrypted volumes

In the terminal, `udisksctl unlock` asks for it itself. In the window, the passphrase
goes from the dialog to UDisks2 over D-Bus (`Encrypted.Unlock`). It never appears in
arguments, files or logs. Nothing tries to get around encryption.

## 5. Races

A device can be replaced at any moment. The disk sequence number is checked before
mounting. A job finds its ends again by UUID. Each drive still has the lock of safe
removal for unmounting, and a job has its own lock file, so it cannot run twice.

## 6. Reports

`report --anonymize` hides serial numbers, UUIDs, volume labels (also in mount
points and titles), the home folder and the user name. A label is replaced as data,
never as a pattern. The names of the files of a copy stay: they are what the report
is about. Copy reports stay in the job folder, mode 700.
