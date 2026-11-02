# 05 — What keeps a device busy

`bigmount --busy TARGET` and the safe-removal dialog collect:

1. **Processes**, from `lsof -w -F pcuLftan -- MOUNTPOINT`, the structured
   field output of lsof. For each open file: PID, user, command, descriptor
   (`cwd`, `rtd`, `txt`, `mem` or a number), mode (`r`/`w`/`u`) and path.
   State and start time come from `/proc/PID/stat`.
2. **Holders without a process**: other mounts of the same device, nested
   mounts, a swap file, a disk image attached to a loop device,
   device-mapper/RAID holders, and mounts of the device inside another mount
   namespace that our unmount does not remove (a container volume). Those
   are found in `/proc/*/mountinfo`, which every user can read. The scan
   costs about 70 ms on a desktop with 585 processes, almost all of it the
   kernel generating each table. When they are the only holder, the summary
   says that a container or sandboxed service has its own mount of the
   device and must be stopped first.

## Plain language first

The dialog opens with a summary and advice that match the holder that
matters most to the user. A writer outranks a terminal, which outranks a
file manager, then an indexer, then anything else:

| Main holder | Summary | Advice |
| --- | --- | --- |
| a file open for writing | "*App* has a file open for writing on this device." | "Let it finish, or cancel the operation in that program, then try again." |
| a shell or a current folder on the device | "A terminal is open in a folder of this device." | "Type cd in that terminal, or close it, then try again." |
| Dolphin, kioworker, other file managers | "*App* is showing or reading files of this device." | "Close the window or tab that shows the device, then try again." |
| Baloo, Tracker | "The file indexer is reading this device." | "It usually finishes in a moment: try again shortly." |
| anything else | "*App* is using files on this device." | "Close that program, then try again." |
| no process, but a system holder | "No program is using it, but the system still is (see below)." | — |

When there are several programs, "In total, N programs are using it." is
added. Then comes the table: application with its technical name in small
print, PID and activity ("Current folder is on the device", "Open for
reading", "Open for writing"). Paths, users and states are in **Technical
details**. There are never percentages, speeds or remaining times, because
an open file is not a transfer.

![The busy device dialog, drawn with GTK 4 since 2.6.0](images/app-dialog-busy.png)

## Why Plasma sometimes only says "one or more files are open"

Plasma's "Disks & Devices" applet runs `lsof` as the user when an unmount
fails (`queryBlockingApps` in `org.kde.plasma.devicenotifier.so`) and names
the application when it finds it. The generic sentence appears when the
holder is invisible to the user:

- a process of root or of another user;
- a second mount. On the development machine `sda1` is mounted at
  `/mnt/Dados` **and** `/var/lib/os-prober/mount`, a leftover of os-prober;
- swap, a loop device, a nested mount.

Big-Mount shows those cases. When no process of the user is found, the dialog
offers **Show programs of all users (administrator)**. That option runs only
`/usr/lib/big-mount/bigmount-holders` through `pkexec`: a read-only helper
with its own polkit action, which only accepts an exact mount point of a
local block device. Its output is deleted as soon as the dialog closes.

## Cost

`lsof` takes about 212 ms on the development machine (680 processes). The
alternatives measured:

- `lsof -b` returns in 1.4 ms because it finds nothing.
- A scan of the user's own processes matched by device number took 111 ms,
  but it would reimplement the access modes and record format that
  `lsof -F` already provides.

`lsof` is kept. It only runs when a diagnosis or an unmount needs it, never
at boot.

## Dolphin integration

Plasma offers no supported extension point to add actions to the failure of
its own unmount. There is also no event to react to: `udisksd` does **not**
log refused unmounts (0 occurrences after dozens provoked by the tests). The
failure only returns over D-Bus to the caller. Detecting it would mean
spying on Plasma's notifications and comparing their translated text, the
kind of fragile interception the project forbids. So Big-Mount provides:

- a Dolphin service menu (submenu "Storage device"): "Why can't I write
  here?" and "Safely remove (shows what keeps it busy)";
- the "Storage Diagnostics" action of the launcher;
- `cd /` before anything else, so that the tool never keeps the device busy
  itself.
