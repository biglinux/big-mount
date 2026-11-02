# 03 — Filesystems and mount options

| Type | Boot mount |
| --- | --- |
| NTFS | `mount -t lowntfs-3g -o uid,gid,rw,noatime,exec,MASK,nodev,nofail,x-gvfs-show` |
| FAT32, exFAT (`TYPE` containing `fat`) | `mount -o uid,gid,noatime,rw,MASK,nodev,nofail,x-gvfs-show` |
| ext4, Btrfs, XFS, F2FS and others | `mount -o noatime,rw,nodev,nofail,x-gvfs-show` |

`MASK` is `umask=000` unless `/etc/big-mount.conf` says otherwise (see
below).

## NTFS

- **No `ntfsfix`.** The original script ran it on every boot. It sets the
  dirty bit: Windows then runs chkdsk at every start, and drivers that honor
  the bit (`ntfs3`) refuse writes. This was shown with a disposable image,
  which reported "Volume is scheduled for check" afterwards. ntfs-3g
  recovers the journal by itself (its default `recover` option).
- **Hibernation, Fast Startup, unclean shutdown.** ntfs-3g 2026.7 mounts the
  volume read-only by itself (exit 0). bigmount reads the real state back
  from `/proc/mounts`, records `ro ntfs-readonly` and the notifier tells the
  user why. Versions that refuse (exit 13/14/15 of `ntfs-3g.probe(8)`) are
  retried with `ro`. `remove_hiberfile`, which would delete the Windows
  session, is never used.
- **A failed mount** removes the directory it created; a directory that
  already existed is left alone.

## Decisions

**NTFS driver: `lowntfs-3g` stays.** The BigLinux kernel on the development
machine (7.2.11-1-big) does not even have the `ntfs3` module
(`modinfo ntfs3`: not found), so switching would break mounting. `ntfs3`
also refuses to write to volumes with the dirty bit set, which is exactly
the state the old `ntfsfix` left behind.

**Permissions of FAT/exFAT/NTFS: `umask=000` stays the default.** The
project ranks compatibility above security, and users rely on sharing
between accounts and services. Restricting is opt-in in
`/etc/big-mount.conf`:

| `PERMISSIONS=` | Options | Effect |
| --- | --- | --- |
| `shared` (default) | `umask=000` | every local account reads, writes and runs files |
| `owner` | `dmask=022,fmask=022` | only the last user who logged in writes; everyone reads (`exec` kept for Wine/Steam) |
| `private` | `umask=077` | only the last user who logged in has access |

The file is parsed as data and never sourced. Unknown values fall back to
`shared` with a journal warning, and values are printed as arguments, never
used as printf formats. It is listed in `backup=`, so edits survive upgrades.

## Observed behavior (integration tests, real UDisks2 mounts)

| Type | Result |
| --- | --- |
| ext4 owned by the user | writable |
| ext4 with a root-owned root folder | rw but no permission: case B |
| ext4 with `error_count=3` | writable with a warning; mounted `ro`: case C |
| healthy NTFS | writable (ntfs-3g) |
| hibernated NTFS | ntfs-3g mounts it `ro` by itself: case D; the image stays hibernated (nothing written) |
| FAT32, exFAT | writable |
| GPT disk with ext4 + FAT | both partitions handled; one busy partition stops the whole removal |
| ISO 9660 / SquashFS / LUKS | not testable here: the kernel lacks those modules |
