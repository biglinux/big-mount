# 06 — Safe removal

`bigmount --unmount TARGET` unmounts one filesystem. `--safe-remove TARGET`
handles the whole drive and powers it off, and `--gui-remove` is the same in
dialogs (and in the Dolphin menu). The core is `bm_remove_core` in
`usr/lib/big-mount/cli.sh`.

## Sequence

| Phase | What happens |
| --- | --- |
| A — diagnosis | resolve the filesystem and its drive; **refuse** if the drive holds the running system (`/`, `/home`, `/boot`, ... or active swap); record the disk sequence number |
| A2 — services | systemd services that depend on the mounts (`BindsTo=`, `Requires=`, `PartOf=`, `Requisite=` on the `.mount` unit, which includes `RequiresMountsFor=`) are listed, and nothing is done until the user agrees to stop them |
| B — normal attempt | `udisksctl unmount` for every mount of every partition (stacked layers first); polkit decides about passwords |
| C — busy | `org.freedesktop.UDisks2.Error.DeviceBusy` → show what holds it; try again, refresh, or close programs |
| D — verification | the mount table decides, not the answer of udisksctl. A mount that vanished meanwhile counts as success; a "successful" unmount that left the mount counts as failure (bounded to 8 attempts, explicit reason). After the last unmount, **every** partition of the drive is checked again: if anything was mounted again meanwhile (an automounter, a script), nothing is reported as safe |
| D2 — release | `udisksctl unmount` returns when the mount is gone **here**. Two things can still hold the filesystem: the FUSE daemon of an NTFS/exFAT volume, which writes its cache after that, and a bind mount made inside another mount namespace (a container volume). Big-Mount waits until both are gone, up to 60 s, with the "do not disconnect" notice after 2 s. If they stay, it is an error that names the process |
| E — encryption | open LUKS volumes on the drive are locked (`udisksctl lock`), as Plasma does before a safe removal |
| F — power off | `udisksctl power-off`, only for removable drives and only when nothing else (LVM, RAID, swap) uses the drive; 3 attempts, because udev may still be processing the unmount. Internal disks are unmounted, never powered off |

Before every step that cannot be undone, the disk sequence number is read
again. If another device took the name (the drive was pulled and a new one
plugged in), the operation stops and says so.

When an unmount or power-off is still running after 2 seconds, which happens
while pending writes reach the device, a popup says "Writing pending data to
the device. Do not disconnect it yet." It is implemented with `wait -n` on
the operation and a 2-second timer, with no polling.

## Closing programs

Closing is only offered for processes that:

- belong to the user;
- are not part of the desktop session (plasmashell, kwin, dbus, pipewire, ...);
- are not shells (an interactive shell ignores the request; the advice is
  `cd`);
- have **no** file open for writing (closing in the middle of a copy would
  leave an incomplete file).

Closing always needs an explicit confirmation that warns about unsaved
changes. **Cancel is the default button**, so an accidental Enter closes
nothing.

The signal is `SIGTERM` (what closing the window does), never `SIGKILL`.
Before sending it, the start time of the process is compared with the one
recorded at diagnosis, so that a process that inherited the PID is never
hit. The tool waits up to 5 seconds and reports what did not close, then
the unmount is attempted again. If a program opens files again, the device
is reported busy again; there is no automatic loop.

## What does not exist, by design

No code path uses `umount -f`, `umount -l`, `kill -9`, `fuser -k` or
`--force`. A test checks the shipped code for them. There is no forced
unmount without a risk of corruption: when a safe removal is not possible,
the device stays mounted and the reason is shown.

## Final messages (shown only after verification)

| Outcome | Popup |
| --- | --- |
| unmounted and powered off | **Safe to disconnect** — Successfully unmounted and powered off. You can disconnect it now. |
| removable, unmounted, no power-off available | **Safe to disconnect** — Successfully unmounted... you can disconnect it now. |
| internal disk | **Device unmounted** (does not suggest unplugging it) |
| busy | the busy dialog (a decision is needed) |
| holds the running system | **Unable to remove device** |
| authorization refused | **Unable to unmount device** — Permission was not granted. The device remains mounted. |
| still in use after the unmount | **Unable to power off device** — ... Do not disconnect it yet. |
| power-off failed (3 attempts) | **Unable to power off device** — It was unmounted, but powering it off failed. Wait a moment before disconnecting it. |
| services depend on it | persistent dialog **Services use this device** with the list; **Stop them and remove** / **Cancel** (default) |

CLI exit codes: 0 done, 1 error, 2 usage, 3 busy, 4 running system,
5 not authorized, 6 unmounted but still in use, 7 unmounted, the drive
cannot be powered off by the computer, 8 unmounted but the power-off failed,
9 nothing done because services depend on it (`--assume-yes` stops them).

## Real test (round 5)

USB SSD, NTFS, used by a Docker service with `BindsTo=` on its mount:

- `--safe-remove` without `--assume-yes`: exit 9, the service named,
  nothing unmounted, the service still running;
- with `--assume-yes`: 5.1 s in total, exit 0. Journal order: host unmount
  (13:20:59.08), systemd stops the service and its containers, ntfs-3g
  unmounts (59.18), the service is stopped (00.17), then UDisks sends
  SYNCHRONIZE CACHE and powers the drive off (00.18–00.56);
- after reconnecting it, the volume mounted read-write and clean, and the
  service started again by itself (`WantedBy=` the mount unit).

The same operation with v2.1.1 unmounted the volume and then failed to
power the drive off, and it stopped the service without saying so.

## Tests

Unit tests (`tests/lib-tests.sh`, simulated drive):

- two partitions are unmounted, then powered off, in that order;
- one busy partition means busy, and no power-off;
- a device replaced between two steps stops the operation with nothing
  done to the new device;
- a partition mounted again meanwhile means no success;
- LUKS is locked before the power-off;
- internal disks are never powered off;
- races and inconsistent udisks answers;
- the slow-operation notice;
- services bound to a mount: exit 9 with nothing done, then removal after
  consent; `systemctl` names with escapes;
- power-off: 3 attempts, exit 8 with the UDisks reason, exit 7 at once for
  `NotSupported`, success on the second attempt;
- FUSE daemons: recognized by device, never by a similar name, also with
  names longer than 15 characters; the unmount waits for them, and fails
  with `still-writing` after the limit.

Integration (`tests/integration.sh`, real UDisks2 mounts): an NTFS image
through FUSE, held by a bind mount in an unprivileged mount namespace (the
busy view shows it; `--unmount` returns only after it and the FUSE daemon
are gone; v2.1.1 fails both checks); busy device
with cwd, reader, writer and kioworker holders; closing only what is safe;
a GPT drive with two partitions; a device that disappears; the running
system refused; GUI flows with scripted clicks, including an accidental
Enter.
