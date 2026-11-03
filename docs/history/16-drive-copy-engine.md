# 16 — Copying off a drive

## 1. What a real failing disk taught us

On 2026-10-30 a Seagate ST1000DM003 (1,848 pending sectors, behind a USB 2.0
bridge) had two folders copied off it, with a power cut in the middle. The engine
is that procedure made general. Each rule comes from something that happened:

| What happened | Rule |
| --- | --- |
| One unreadable 4 KiB page took 3 min 36 s to fail, and the next one the same. A single 3.7 MB photo held the copy for ten minutes | A file that does not advance for `--stall-seconds` (90) is set aside, and the copy goes on; while the destination is still writing it gets four times as long. 15,464 files got through this way, with one set aside |
| `ntfs-3g` serves one request at a time: even `stat` and `mountpoint` hung behind that read | The mount table is read from `/proc`. Everything else that touches the source has a time limit, including `lsblk` for free space |
| A click in Dolphin mounted the disk read-write, and `ntfs-3g` tried to write its MFT at once | `--protect` blocks writing on the block device (`blockdev --setro`), and a read-only mount is what the manager offers. Rescue never needs writing |
| Dolphin copied in place: after the power cut, truncated files had their final names | rsync writes to a temporary folder, syncs (`--fsync`) and renames. A file with its final name is complete |
| `SMART: PASSED` | The raw counters decide (15, section 6) |
| Resets of a USB disk name the port (`usb 1-9.1`), never `sdb` | `bm_drive_port` knows USB ports |
| After reconnecting, the device name can change | A job remembers UUIDs and finds the mount point again |
| Measuring `Pictures` with `du` hit the bad area | A drive at risk is not scanned: no total, no invented percentage |

## 2. A job

```text
~/.local/state/big-mount/jobs/20261030-140000-abcd/   (mode 700)
  job.conf       what was asked, with the UUIDs of both ends
  state.env      how far it got, replaced atomically
  items0         selected items, NUL separated
  events.log     rsync log: what was sent
  rsync.out      rsync stderr: what went wrong in this run (rsync.old: earlier runs)
  deferred.txt   set aside   excludes.txt  the same, as anchored patterns
  failed.txt     not copied, with the reason
  differences.txt, verify.out   the comparison at the end
  report.txt, report.json
```

States: `pending`, `analyzing`, `running`, `verifying`, `stopping`, `paused`,
`completed`, `cancelled`, `failed`, `needs-attention`, and `interrupted`, which
is not stored: a job marked as running whose supervisor is gone (compared by PID
and process start time) was interrupted.

The supervisor is started with `setsid`, so closing the window or the terminal
does not stop the copy, and it holds no privileges.

## 3. What counts as copied

The rsync log is not enough, and this was found by testing with real read errors:

- A file is logged (`>f…`) **before** its read errors are known. A failed attempt
  is taken back when `WARNING`/`ERROR: … failed verification` arrives.
- Errors of the receiver (disk full, a name the destination refuses) only appear
  on standard error, so both records are read.
- A file sent just before rsync was stopped is sent again by the next pass. Names
  seen recently count once.
- `rsync -8`, and the log parsed as bytes: otherwise a name in Latin-1 from an old
  disk makes the regular expression silently skip the line.
- A root-owned `lost+found` that cannot be read is excluded and is not a failure.

`completed` means no file was set aside or failed, and the check found no
difference. Anything else is `needs-attention`, with the list.

## 4. Protections

`bm_cp_check` writes nothing. It refuses: the same folder; a destination inside
the source or the reverse (real paths, so a symlink does not fool it); the same
filesystem; a read-only or unwritable destination; items outside the source; a
measured total that does not fit. With an explicit option only: the same physical
disk (compared through partitions, LUKS and LVM with `lsblk -s`), a destination on
a drive with critical alerts, a source at risk mounted with writing enabled.

rsync runs with fixed options: `-rlt -8 --one-file-system --no-specials
--no-devices`. Links are copied as links and never followed. Nothing is ever
deleted. Existing files: `--on-conflict skip` (default), `backup` (the old one goes
to `.big-mount-backup-ID`) or `overwrite`.

## 5. Progress

Real numbers only:

- With a healthy source, `rsync -n` measures the total first: files and bytes.
- On a drive at risk nothing is walked. Copying a whole volume shows the used
  space, marked `≈`; a selection shows no total at all. Then there is no percentage
  and no time left, and the window shows a busy bar.
- Bytes come from the log plus the position of the open file in
  `/proc/PID/fdinfo`. The speed is measured over the last 20 s.
- An image reports the map of ddrescue: physical progress, not files.

## 6. Stopping and resuming

`pause` and `cancel` write to `control`; the supervisor sends SIGTERM to rsync,
which removes its temporary file. Never SIGKILL. While a read is stuck in the
driver this waits for it, and the state says `stopping`.

`resume ID` runs rsync again with the same options, at the mount point where the
UUIDs are now. Resuming works per file: a large file that was interrupted starts
over. For a disk image, ddrescue resumes from its map.

`resume ID --retry-deferred` tries what was set aside once more, with a limit of
600 s per file. This reads damaged areas again and puts more strain on the disk,
so it only happens on request. More than 100 files set aside stops the copy: the
drive is probably getting worse.

## 7. Verification

| `--verify` | What it does | Reads the source |
| --- | --- | --- |
| `basic` (default) | rsync confirms each file with a checksum as it copies | no more |
| `metadata` | names, sizes and dates compared at the end | metadata |
| `full` | content compared at the end | **everything again**: on a drive at risk it warns |

## 8. Known limits

- Names that are not valid UTF-8 are copied by the engine, but the window cannot
  select them individually: use **Copy everything** or the terminal.
- A file of 4 GiB or more on FAT32 is listed as failed. It is warned about first.
- Permissions and owners: kept only between Linux filesystems, and owners are
  not preserved because the copy does not run as root.
- XFS and Btrfs with an unclean log cannot be mounted without replaying it: UDisks2
  does not accept `norecovery`, so the manager explains it and suggests an image.
