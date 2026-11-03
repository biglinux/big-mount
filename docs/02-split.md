# 02 — The split (Big-Mount 3.0)

Done on 2026-11-02, branch `feature/automount-only` from
`feature/biglinux-2.6.0` (`40612ab`), **after** Big Storage Rescue was built
from the same history and its tests passed
(`biglinux/big-storage-rescue`, branch `feature/migrate-from-big-mount`).

## Kept

| File | Change |
| --- | --- |
| `usr/bin/bigmount` | comments only: the boot path is identical (checked with a diff without comments) |
| `etc/big-mount.conf` | none |
| `usr/lib/systemd/system/big-mount.service` | none |
| `usr/share/libalpm/hooks/big-mount.hook` | none |
| `usr/lib/big-mount/cli.sh` | rewritten, 271 lines instead of 1624: `--help`, `--version`, `--doctor` (the service only), and the old options |
| `usr/share/locale/pt_BR/LC_MESSAGES/big-mount.mo` | the 66 messages that remain |

## Moved to Big Storage Rescue

`lib.sh`, `ui.sh`, the diagnosis, busy and removal parts of `cli.sh` and
`doctor.sh`, `drive.sh`, `drive-detect.sh`, `drive-diag.sh`, `drive-copy.sh`,
`drive-recovery.sh`, `drive-tui.sh`, `drive-gui.py`, `dialog.py`, `gui/`,
`bigmount-drive-helper`, `bigmount-holders`, the polkit policy, the launcher,
the Dolphin service menu, the notifier entry, the icon, their translations,
and their tests (`lib-tests`, `drive-tests`, `integration`,
`drive-integration`, `gui-tests`, `gui-e2e`, `measure-*`, `readme-screenshots`).

## Removed, in neither package

Secure Erase (`drive-erase.sh`, `bm_erase_*`, `--secure-erase`,
`--drive erase-check`, the maintenance page). It destroys data and does not
belong in a mount service or in a rescue tool. Its code, review and tests are
in the history of both repositories, last at `40612ab`, and in
`docs/history/14-drive-health-and-secure-erase.md`.

## Old options

Plain bash in `cli.sh`, without loading anything else and without needing the
new package. Exit code 2.

| Old | Answer |
| --- | --- |
| `--drive [ARGS]` | `bigmount: --drive moved to Big Storage Rescue. Use: big-storage-rescue --cli [ARGS]` |
| `--gui-drive`, `--gui-drive-check` | `big-storage-rescue --gui`, `--gui-health` |
| `--gui DEV` | `big-storage-rescue --gui-diagnose DEV` |
| `--diagnose`, `--busy`, `--unmount`, `--safe-remove`, `--gui-remove` | the same option of `big-storage-rescue` |
| `--secure-erase` | `bigmount: Secure Erase is no longer part of Big-Mount.` |
| `--notifier` | nothing, exit 0 (an autostart entry of 2.x may still start it at login) |

When `big-storage-rescue` is not installed, the answer of an option that moved
adds how to install it (`--secure-erase` has no new home, so it does not).
The pacman script says the same once, before the update replaces the files,
and warns when a copy or image of the 2.x drive manager is still running.
