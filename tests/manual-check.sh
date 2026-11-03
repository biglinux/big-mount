#!/bin/bash
# Guided manual validation of a real boot with the package installed: what
# automated tests cannot see. Nothing is changed; it only reads.
#
# Usage: tests/manual-check.sh     (after rebooting with the package installed)
#
# Answers are saved to big-mount-manual-check.txt in the current folder.

set -u
BM="${BM:-/usr/bin/bigmount}"
OUT="$PWD/big-mount-manual-check.txt"

ask() { # QUESTION -> records y/n
    local ans
    printf '\n\033[1m%s\033[0m [y/n] ' "$1"
    read -r ans
    case "$ans" in [yYsS]*) ans=yes ;; *) ans=NO ;; esac
    printf '%-4s %s\n' "$ans" "$1" >> "$OUT"
}
say() { printf '\n\033[36m== %s\033[0m\n%s\n' "$1" "$2"; }

: > "$OUT"
say "Version" "$("$BM" --version 2>&1)"
say "Boot time" "$(systemd-analyze blame 2>/dev/null | grep big-mount)"
say "Journal of this boot" "$(journalctl -b -u big-mount --no-pager -o cat 2>/dev/null | tail -n 20)"
say "Status file" "$(cat /run/big-mount/status 2>/dev/null)"
say "Self-check" "$("$BM" --doctor 2>&1)"
ok=yes
for pid in $(pgrep -f 'mount.lowntfs-3g|mount.ntfs-3g'); do
    if sudo ls -l "/proc/$pid/fd" 2>/dev/null | grep -q big-mount.lock; then ok=NO; fi
done
say "NTFS FUSE daemons holding the big-mount lock (must be none)" "$ok"
printf '%-4s %s\n' "$ok" "no FUSE daemon holds the big-mount lock" >> "$OUT"
ok=yes
pgrep -af 'python3|gtk' | grep -q big-mount && ok=NO
say "No graphical program of Big-Mount is running (must be yes)" "$ok"
printf '%-4s %s\n' "$ok" "nothing graphical of Big-Mount runs" >> "$OUT"
say "USB disks" "Plug a USB disk in BEFORE rebooting next time: it must appear in Dolphin, not under /mnt."
lsblk -o NAME,TRAN,RM,HOTPLUG,MOUNTPOINTS
ask "Is every USB disk mounted by Dolphin/UDisks (under /run/media), none under /mnt?"
ask "Are the internal partitions mounted under /mnt, read-write unless --doctor says why not?"
echo; echo "Answers saved to $OUT"
