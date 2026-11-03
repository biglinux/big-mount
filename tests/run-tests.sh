#!/bin/bash
# shellcheck disable=SC2016,SC2317,SC2329  # bash -c '...$1' snippets and helpers called through check()
# Unit test harness for bigmount.
# Usage: run-tests.sh {old|new}
# Stubs out blkid, lsblk, udevadm, udisksctl, findmnt, mount, ntfsfix.
# Rewrites hardcoded absolute paths to $TESTROOT/... so filesystem stays untouched.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"

VERSION_LABEL="${1:-new}"
case "$VERSION_LABEL" in
    old) SCRIPT_SRC="$HERE/bigmount.old.sh" ;;
    new) SCRIPT_SRC="$REPO/big-mount/usr/bin/bigmount" ;;
    *)   echo "Usage: $0 {old|new}"; exit 2 ;;
esac

PASS=0
FAIL=0
FAILED_TESTS=()

# Safety interlock: every tool that could touch a real disk must resolve to
# its stub. A stub that cannot be executed (e.g. checkout on a noexec mount)
# would otherwise make bash fall back to the real /usr/bin binary.
for tool in blkid lsblk udevadm udisksctl findmnt mount ntfsfix; do
    resolved="$(PATH="$HERE/stubs:/usr/bin:/bin" command -v "$tool")"
    if [ "$resolved" != "$HERE/stubs/$tool" ]; then
        echo "run-tests: refusing to run, '$tool' resolves to '$resolved', not the stub" >&2
        exit 2
    fi
done

transform_script() {
    local src="$1" dst="$2" root="$3"
    # Placeholder trick: rewrite /run/media first so later /media rule won't recurse into it.
    sed \
        -e "s|/etc/bigmountall-no|$root/etc/bigmountall-no|g" \
        -e "s|/etc/big-mount.conf|$root/etc/big-mount.conf|g" \
        -e "s|/var/lib/sddm|$root/var/lib/sddm|g" \
        -e "s|/var/lib/lightdm|$root/var/lib/lightdm|g" \
        -e "s|/run/media|__RUNMEDIA__|g" \
        -e "s|/run/big-mount|$root/run/big-mount|g" \
        -e "s|/run/lock|$root/run/lock|g" \
        -e "s|/proc/mounts|$root/proc/mounts|g" \
        -e "s|/sys/block|$root/sys/block|g" \
        -e "s|/mnt|$root/mnt|g" \
        -e "s|/media|$root/media|g" \
        -e "s|__RUNMEDIA__|$root/run/media|g" \
        -e '/# root-check$/s/\[ "\$EUID" -ne 0 \]/[ "${FAKE_EUID:-0}" -ne 0 ]/' \
        "$src" > "$dst"
    chmod +x "$dst"
}

setup_root() {
    local root="$1"
    rm -rf "$root"
    mkdir -p "$root/etc" "$root/mnt" "$root/run/media" "$root/run/lock" "$root/proc" \
             "$root/sys/block" "$root/var/lib/sddm" "$root/var/lib/lightdm" \
             "$root/fake-udisksctl" "$root/fake-udev"
    : > "$root/proc/mounts"
    : > "$root/mount.log"
    : > "$root/ntfsfix.log"
    : > "$root/udevadm.log"
    : > "$root/udisksctl.log"
    : > "$root/fake-lsblk"
    : > "$root/fake-blkid"
    : > "$root/fake-fstab"
    echo "User=" > "$root/var/lib/sddm/state.conf"
}

run_script() {
    local root="$1"
    shift
    local tmp="$root/bigmount.patched"
    transform_script "$SCRIPT_SRC" "$tmp" "$root"
    env -i TESTROOT="$root" HOME="$HOME" PATH="$HERE/stubs:/usr/bin:/bin" FAKE_EUID="${FAKE_EUID:-0}" \
        MOUNT_FAIL_DEVS="${MOUNT_FAIL_DEVS:-}" MOUNT_RC_RW="${MOUNT_RC_RW:-}" \
        MOUNT_RC_RO="${MOUNT_RC_RO:-}" MOUNT_FALLBACK_RO="${MOUNT_FALLBACK_RO:-}" bash "$tmp" "$@"
}

report() {
    local name="$1" cond="$2" status="$3"
    if [ "$status" -eq 0 ]; then
        PASS=$((PASS+1))
        printf "  \033[32m✓\033[0m %s — %s\n" "$name" "$cond"
    else
        FAIL=$((FAIL+1))
        FAILED_TESTS+=("$name: $cond")
        printf "  \033[31m✗\033[0m %s — %s\n" "$name" "$cond"
    fi
}
assert_true()  { "$@"; report "$TEST_NAME" "$ASSERT_MSG" $?; }
assert_false() { "$@"; local rc=$?; [ "$rc" -ne 0 ]; report "$TEST_NAME" "$ASSERT_MSG" $?; }

mount_log_has()    { grep -qF -- "$2" "$1/mount.log"; }
mount_log_grep()   { grep -qE -- "$2" "$1/mount.log"; }

begin() { TEST_NAME="$1"; echo "— $1"; }

# ===== TESTS =====

test_disabled() {
    begin "disabled-flag"
    local root="$HERE/tmp-disabled"
    setup_root "$root"
    : > "$root/etc/bigmountall-no"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sda1: LABEL="Data" UUID="aaa" TYPE="ext4"
EOF
    echo "sda1 sda" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sda"; echo 0 > "$root/sys/block/sda/removable"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="mount never called"; assert_false test -s "$root/mount.log"
}

test_ext4_label() {
    begin "ext4-with-label"
    local root="$HERE/tmp-ext4-label"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sda1: LABEL="Data" UUID="aaa" TYPE="ext4"
EOF
    echo "sda1 sda" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sda"; echo 0 > "$root/sys/block/sda/removable"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="mount target = /mnt/Data";   assert_true mount_log_has "$root" "$root/mnt/Data"
    ASSERT_MSG="mount source = /dev/sda1";   assert_true mount_log_has "$root" "/dev/sda1"
    ASSERT_MSG="no ntfsfix";                 assert_false test -s "$root/ntfsfix.log"
    ASSERT_MSG="reverse symlink /mnt/sda1";  assert_true test -L "$root/mnt/sda1"
}

test_no_label() {
    begin "ext4-no-label"
    local root="$HERE/tmp-ext4-nolabel"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sda1: UUID="aaa" TYPE="ext4"
EOF
    echo "sda1 sda" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sda"; echo 0 > "$root/sys/block/sda/removable"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="mount target = /mnt/sda1"; assert_true mount_log_has "$root" "$root/mnt/sda1"
    ASSERT_MSG="no reverse symlink created when label==partition"; assert_false test -L "$root/mnt/sda1"
}

test_partlabel_fallback() {
    begin "partlabel-fallback"
    local root="$HERE/tmp-partlabel"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sda1: UUID="aaa" PARTLABEL="GPTName" TYPE="ext4"
EOF
    echo "sda1 sda" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sda"; echo 0 > "$root/sys/block/sda/removable"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="mount target uses PARTLABEL"; assert_true mount_log_has "$root" "$root/mnt/GPTName"
}

test_swap_skipped() {
    begin "swap-skipped"
    local root="$HERE/tmp-swap"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sda1: LABEL="SWAP" TYPE="swap"
EOF
    echo "sda1 sda" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sda"; echo 0 > "$root/sys/block/sda/removable"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="swap never mounted"; assert_false test -s "$root/mount.log"
}

test_squashfs_skipped() {
    begin "squashfs-skipped"
    local root="$HERE/tmp-squashfs"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/loop0: TYPE="squashfs"
EOF
    echo "loop0 " > "$root/fake-lsblk"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="squashfs never mounted"; assert_false test -s "$root/mount.log"
}

test_ntfs_mount() {
    begin "ntfs-mount"
    local root="$HERE/tmp-ntfs"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sdb1: LABEL="Win" TYPE="ntfs"
EOF
    echo "sdb1 sdb" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sdb"; echo 0 > "$root/sys/block/sdb/removable"
    run_script "$root" >/dev/null 2>&1
    # Behaviour change (docs/01-audit.md A3): ntfsfix sets the dirty bit
    # and resets the journal, so it must never run automatically.
    ASSERT_MSG="ntfsfix never invoked [new-only fix]"; assert_false test -s "$root/ntfsfix.log"
    ASSERT_MSG="mount uses lowntfs-3g type"; assert_true mount_log_grep "$root" "-t[[:space:]]+lowntfs-3g"
    ASSERT_MSG="ntfs options include uid=";  assert_true mount_log_grep "$root" "uid=[0-9]+"
}

test_fat_mount() {
    begin "fat-mount"
    local root="$HERE/tmp-fat"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sdc1: LABEL="FATDISK" TYPE="vfat"
EOF
    echo "sdc1 sdc" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sdc"; echo 0 > "$root/sys/block/sdc/removable"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="FAT mounted";              assert_true mount_log_has "$root" "$root/mnt/FATDISK"
    # NEW adds uid/gid for FAT (old omits). Bug exposure:
    ASSERT_MSG="FAT mount options include uid= [new-only fix]"; assert_true mount_log_grep "$root" "uid=[0-9]+"
}

test_usb_skipped() {
    begin "usb-skipped"
    local root="$HERE/tmp-usb"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sdx1: LABEL="Pendrive" TYPE="ext4"
EOF
    echo "sdx1 sdx" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sdx"; echo 1 > "$root/sys/block/sdx/removable"
    # both old + new check sysfs removable, should skip
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="USB/removable not mounted"; assert_false test -s "$root/mount.log"
}

test_hintignore_skipped() {
    begin "hintignore-skipped"
    local root="$HERE/tmp-hintignore"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sdd1: LABEL="Hidden" TYPE="ext4"
EOF
    echo "sdd1 sdd" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sdd"; echo 0 > "$root/sys/block/sdd/removable"
    cat > "$root/fake-udisksctl/sdd1" <<'EOF'
  HintIgnore:                true
EOF
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="HintIgnore skip"; assert_false test -s "$root/mount.log"
}

test_idempotent_already_mounted() {
    begin "already-mounted-idempotent"
    local root="$HERE/tmp-already"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sda1: LABEL="Data" TYPE="ext4"
EOF
    echo "sda1 sda" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sda"; echo 0 > "$root/sys/block/sda/removable"
    # pretend already mounted
    echo "/dev/sda1 $root/mnt/Data ext4 rw 0 0" > "$root/proc/mounts"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="no remount when already mounted"; assert_false test -s "$root/mount.log"
}

test_collision_suffix() {
    begin "label-collision-suffix"
    local root="$HERE/tmp-collision"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sdb1: LABEL="SameName" TYPE="ext4"
EOF
    echo "sdb1 sdb" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sdb"; echo 0 > "$root/sys/block/sdb/removable"
    # another device already holding /mnt/SameName
    mkdir -p "$root/mnt/SameName"
    echo "/dev/sdz9 $root/mnt/SameName ext4 rw 0 0" > "$root/proc/mounts"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="suffix used on collision"; assert_true mount_log_has "$root" "$root/mnt/SameName1"
}

test_compat_symlinks() {
    begin "compat-symlinks-independent"
    local root="$HERE/tmp-compat"
    setup_root "$root"
    # /media already exists as real dir — old version would SKIP creating /mnt/user-mount
    mkdir -p "$root/media"
    cat >"$root/fake-blkid" <<'EOF'
EOF
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="/mnt/user-mount symlink created [new-only fix]"; assert_true test -L "$root/mnt/user-mount"
}

test_nvme_removable_parent() {
    begin "nvme-removable-detection"
    local root="$HERE/tmp-nvme"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/nvme0n1p1: LABEL="NVMeDisk" TYPE="ext4"
EOF
    echo "nvme0n1p1 nvme0n1" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/nvme0n1"; echo 1 > "$root/sys/block/nvme0n1/removable"
    # Old derives parent as "nvme" (broken) → misses removable flag → WRONGLY mounts.
    # New uses lsblk PKNAME → finds "nvme0n1" → removable=1 → skips.
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="NVMe flagged removable is skipped [new-only fix]"; assert_false test -s "$root/mount.log"
}

test_mount_failure_no_symlink() {
    begin "mount-fail-no-symlink"
    local root="$HERE/tmp-mountfail"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sda1: LABEL="FailMe" TYPE="ext4"
EOF
    echo "sda1 sda" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sda"; echo 0 > "$root/sys/block/sda/removable"
    MOUNT_FAIL_DEVS="/dev/sda1" run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="no reverse symlink on mount failure [new-only fix]"; assert_false test -L "$root/mnt/sda1"
}

test_proc_mounts_prefix_match() {
    begin "proc-mounts-prefix-match"
    local root="$HERE/tmp-prefix"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sda1: LABEL="One" TYPE="ext4"
EOF
    echo "sda1 sda" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sda"; echo 0 > "$root/sys/block/sda/removable"
    # Unrelated device with prefix-matching name already mounted somewhere.
    # Old's `grep "^/dev/$PARTITION"` matches sda10 when looking for sda1 → skips erroneously.
    echo "/dev/sda10 /somewhere ext4 rw 0 0" > "$root/proc/mounts"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="sda1 mounted despite sda10 in mounts [new-only fix]"; assert_true mount_log_has "$root" "/dev/sda1"
}

test_slash_in_label() {
    begin "slash-in-label-sanitized"
    local root="$HERE/tmp-slash"
    setup_root "$root"
    cat >"$root/fake-blkid" <<'EOF'
/dev/sda1: LABEL="Foo/Bar" TYPE="ext4"
EOF
    echo "sda1 sda" > "$root/fake-lsblk"
    mkdir -p "$root/sys/block/sda"; echo 0 > "$root/sys/block/sda/removable"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="slash in label replaced with underscore [new-only fix]"
    assert_true mount_log_has "$root" "$root/mnt/Foo_Bar"
}

# ----- helpers for the scenarios below -----
# disk ROOT DISK [REMOVABLE]: fake sysfs entry for a whole disk
disk() { mkdir -p "$1/sys/block/$2"; echo "${3:-0}" > "$1/sys/block/$2/removable"; }
# lsblk_map ROOT "part parent [TRAN] [HOTPLUG]"...
lsblk_map() { local r="$1"; shift; printf '%s\n' "$@" > "$r/fake-lsblk"; }
udev_props() { local r="$1" n="$2"; shift 2; printf '%s\n' "$@" > "$r/fake-udev/$n"; }
mounted() { awk -v t="$2" '$NF == t { f = 1 } END { exit !f }' "$1/mount.log"; }
status_has() { grep -qF -- "$2" "$1/run/big-mount/status" 2>/dev/null; }

simple_case() { # ROOT BLKID_LINE PART DISK [TRAN] [HOTPLUG]
    setup_root "$1"
    echo "$2" > "$1/fake-blkid"
    lsblk_map "$1" "$3 $4 ${5:-} ${6:-}"
    disk "$1" "$4"
}

# ===== device identification (docs/02-device-detection.md) =====

test_usb_rm0_transport() {
    begin "usb-hdd-rm0-transport-usb"
    local root="$HERE/tmp-usb-rm0"
    simple_case "$root" '/dev/sdd1: LABEL="Externo" TYPE="ntfs"' sdd1 sdd usb 1
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="USB HDD with RM=0 is left to UDisks"; assert_false test -s "$root/mount.log"
    ASSERT_MSG="no ntfsfix on external NTFS"; assert_false test -s "$root/ntfsfix.log"
}

test_usb_rm0_tran_only() {
    begin "usb-rm0-tran-only"
    local root="$HERE/tmp-usb-tran"
    simple_case "$root" '/dev/sdd1: LABEL="SSD" TYPE="exfat"' sdd1 sdd usb 0
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="TRAN=usb alone is enough"; assert_false test -s "$root/mount.log"
}

test_usb_rm0_udev_only() {
    begin "usb-rm0-udev-bus-only"
    local root="$HERE/tmp-usb-udev"
    simple_case "$root" '/dev/sdd1: LABEL="SSD" TYPE="ext4"' sdd1 sdd "" 0
    udev_props "$root" sdd1 "ID_BUS=usb"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="ID_BUS=usb alone is enough"; assert_false test -s "$root/mount.log"
}

test_usb_rm0_idpath_only() {
    begin "usb-rm0-id-path-only"
    local root="$HERE/tmp-usb-path"
    simple_case "$root" '/dev/sdd1: LABEL="Dock" TYPE="ext4"' sdd1 sdd "" 0
    udev_props "$root" sdd1 "ID_PATH=pci-0000:00:14.0-usb-0:2:1.0-scsi-0:0:0:0"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="ID_PATH through USB (dock) is enough"; assert_false test -s "$root/mount.log"
}

test_usb_multi_partition() {
    begin "usb-multi-partition"
    local root="$HERE/tmp-usb-multi"
    setup_root "$root"
    printf '%s\n' '/dev/sde1: LABEL="Win" TYPE="ntfs"' '/dev/sde2: LABEL="Linux" TYPE="ext4"' \
        '/dev/sde3: LABEL="Pen" TYPE="vfat"' > "$root/fake-blkid"
    lsblk_map "$root" "sde1 sde usb 1" "sde2 sde usb 1" "sde3 sde usb 1"
    disk "$root" sde
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="no partition of the USB disk is mounted"; assert_false test -s "$root/mount.log"
}

test_hotplug_nvme_thunderbolt() {
    begin "nvme-thunderbolt-hotplug"
    local root="$HERE/tmp-tbt"
    simple_case "$root" '/dev/nvme1n1p1: LABEL="TBT" TYPE="ext4"' nvme1n1p1 nvme1n1 nvme 1
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="hot-pluggable NVMe enclosure is left to UDisks"; assert_false test -s "$root/mount.log"
}

test_internal_nvme() {
    begin "internal-nvme"
    local root="$HERE/tmp-nvme-int"
    simple_case "$root" '/dev/nvme0n1p3: LABEL="Arquivos" TYPE="btrfs"' nvme0n1p3 nvme0n1 nvme 0
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="internal NVMe mounted at /mnt/Arquivos"; assert_true mounted "$root" "$root/mnt/Arquivos"
    ASSERT_MSG="btrfs gets generic options (no uid=)"; assert_false mount_log_grep "$root" "uid="
}

test_sd_card() {
    begin "sd-card"
    local root="$HERE/tmp-sd"
    simple_case "$root" '/dev/mmcblk0p1: LABEL="CAMERA" TYPE="exfat"' mmcblk0p1 mmcblk0 "" 0
    mkdir -p "$root/sys/block/mmcblk0/device"; echo SD > "$root/sys/block/mmcblk0/device/type"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="SD card in internal reader is left to UDisks"; assert_false test -s "$root/mount.log"
}

test_sd_card_udev_flag() {
    begin "sd-card-udev-flag"
    local root="$HERE/tmp-sd-udev"
    simple_case "$root" '/dev/sdf1: LABEL="CARD" TYPE="vfat"' sdf1 sdf "" 0
    udev_props "$root" sdf1 "ID_DRIVE_FLASH_SD=1"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="ID_DRIVE_FLASH_SD is enough"; assert_false test -s "$root/mount.log"
}

test_emmc_internal() {
    begin "emmc-internal"
    local root="$HERE/tmp-emmc"
    simple_case "$root" '/dev/mmcblk1p3: LABEL="Dados" TYPE="ext4"' mmcblk1p3 mmcblk1 "" 0
    mkdir -p "$root/sys/block/mmcblk1/device"; echo MMC > "$root/sys/block/mmcblk1/device/type"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="soldered eMMC is internal"; assert_true mounted "$root" "$root/mnt/Dados"
}

test_esata_udisks_system() {
    begin "esata-udisks-system-0"
    local root="$HERE/tmp-esata"
    simple_case "$root" '/dev/sdg1: LABEL="Bay" TYPE="ext4"' sdg1 sdg sata 0
    udev_props "$root" sdg1 "UDISKS_SYSTEM=0"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="UDISKS_SYSTEM=0 (eSATA rule) is left to UDisks"; assert_false test -s "$root/mount.log"
}

test_udev_settle_then_mount() {
    begin "udev-late-then-settled"
    local root="$HERE/tmp-udev-late"
    simple_case "$root" '/dev/sda1: LABEL="Data" TYPE="ext4"' sda1 sda sata 0
    : > "$root/fake-udev/sda1.uninit"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="udevadm settle requested once"; assert_true grep -q "udevadm settle" "$root/udevadm.log"
    ASSERT_MSG="mounted after udev finished"; assert_true mounted "$root" "$root/mnt/Data"
}

test_udev_never_ready() {
    begin "udev-never-ready"
    local root="$HERE/tmp-udev-never"
    simple_case "$root" '/dev/sda1: LABEL="Data" TYPE="ext4"' sda1 sda sata 0
    : > "$root/fake-udev/sda1.uninit-forever"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="unknown device is not mounted"; assert_false test -s "$root/mount.log"
}

test_virtual_devices() {
    begin "virtual-devices-skipped"
    local root="$HERE/tmp-virtual"
    setup_root "$root"
    printf '%s\n' '/dev/mapper/luks-1234: LABEL="Crypt" TYPE="ext4"' '/dev/dm-3: TYPE="xfs"' \
        '/dev/loop3: LABEL="Img" TYPE="ext4"' '/dev/zram0: TYPE="ext4"' > "$root/fake-blkid"
    lsblk_map "$root" "loop3" "zram0"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="mapper/dm/loop/zram never mounted"; assert_false test -s "$root/mount.log"
}

test_non_filesystems() {
    begin "containers-and-members-skipped"
    local root="$HERE/tmp-nonfs"
    setup_root "$root"
    printf '%s\n' '/dev/sda1: UUID="a" TYPE="crypto_LUKS" PARTLABEL="cofre"' \
        '/dev/sda2: UUID="b" TYPE="LVM2_member"' '/dev/sda3: UUID="c" TYPE="linux_raid_member"' \
        '/dev/sda4: TYPE="isw_raid_member"' '/dev/sda5: TYPE="BitLocker"' \
        '/dev/sda6: PARTLABEL="Microsoft reserved partition" PARTUUID="x"' > "$root/fake-blkid"
    lsblk_map "$root" "sda1 sda" "sda2 sda" "sda3 sda" "sda4 sda" "sda5 sda" "sda6 sda"
    disk "$root" sda
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="no mount attempted"; assert_false test -s "$root/mount.log"
    ASSERT_MSG="no directory left in /mnt"; assert_false test -e "$root/mnt/cofre"
    ASSERT_MSG="no directory for the MSR"; assert_false test -e "$root/mnt/Microsoft_reserved_partition"
}

test_fstab_managed() {
    begin "fstab-managed-skipped"
    local root="$HERE/tmp-fstab"
    simple_case "$root" '/dev/sda1: LABEL="Data" TYPE="ext4"' sda1 sda sata 0
    echo /dev/sda1 > "$root/fake-fstab"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="partition in /etc/fstab is never touched"; assert_false test -s "$root/mount.log"
}

test_device_swapped_during_scan() {
    begin "device-swapped-during-scan"
    local root="$HERE/tmp-swapped"
    simple_case "$root" '/dev/sda1: LABEL="Data" TYPE="ext4"' sda1 sda sata 0
    echo 7 > "$root/sys/block/sda/diskseq"
    : > "$root/fake-udev/sda.swap-diskseq"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="not mounted when diskseq changed"; assert_false test -s "$root/mount.log"
}

# ===== filesystems and options (docs/03-filesystem-support.md) =====

test_fat_regex_bug() {
    begin "ext4-partlabel-containing-fat"
    local root="$HERE/tmp-fatregex"
    simple_case "$root" '/dev/sda1: LABEL="Dados" UUID="x" TYPE="ext4" PARTLABEL="backup-fat32-old"' sda1 sda sata 0
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="ext4 mounted"; assert_true mounted "$root" "$root/mnt/Dados"
    ASSERT_MSG="ext4 does not get FAT options [new-only fix]"; assert_false mount_log_grep "$root" "uid=|umask="
}

test_exfat_options() {
    begin "exfat-options"
    local root="$HERE/tmp-exfat"
    simple_case "$root" '/dev/sda2: LABEL="Shared" TYPE="exfat"' sda2 sda sata 0
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="exFAT gets uid/gid/umask"; assert_true mount_log_grep "$root" "uid=[0-9]+,gid=[0-9]+,.*umask=000"
}

test_generic_filesystems() {
    begin "xfs-f2fs-generic-options"
    local root="$HERE/tmp-generic"
    setup_root "$root"
    printf '%s\n' '/dev/sda1: LABEL="X" TYPE="xfs"' '/dev/sda2: LABEL="F" TYPE="f2fs"' > "$root/fake-blkid"
    lsblk_map "$root" "sda1 sda sata" "sda2 sda sata"
    disk "$root" sda
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="XFS mounted"; assert_true mounted "$root" "$root/mnt/X"
    ASSERT_MSG="F2FS mounted"; assert_true mounted "$root" "$root/mnt/F"
    ASSERT_MSG="no FAT/NTFS-only options"; assert_false mount_log_grep "$root" "uid=|umask="
}

test_ntfs_hibernated() {
    begin "ntfs-hibernated-read-only"
    local root="$HERE/tmp-ntfs-hiber"
    simple_case "$root" '/dev/sdb3: LABEL="Windows" UUID="BE02" TYPE="ntfs"' sdb3 sdb sata 0
    MOUNT_RC_RW="/dev/sdb3=14" run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="read-only retry"; assert_true mount_log_grep "$root" "lowntfs-3g -o uid=[0-9]+,gid=[0-9]+,ro,"
    ASSERT_MSG="never remove_hiberfile"; assert_false mount_log_grep "$root" "remove_hiberfile"
    ASSERT_MSG="status says ro + hibernated"; assert_true status_has "$root" "ro	ntfs-hibernated"
    ASSERT_MSG="no ntfsfix"; assert_false test -s "$root/ntfsfix.log"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="a restart keeps the reason"; assert_true status_has "$root" "ro	ntfs-hibernated"
}

test_ntfs_silent_readonly_fallback() {
    begin "ntfs-driver-falls-back-to-read-only"
    local root="$HERE/tmp-ntfs-fallback"
    simple_case "$root" '/dev/sdb3: LABEL="Windows" UUID="BE02" TYPE="ntfs"' sdb3 sdb sata 0
    MOUNT_FALLBACK_RO="/dev/sdb3" run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="single mount call (driver handled it)"; assert_true test "$(grep -c '^mount' "$root/mount.log")" -eq 1
    ASSERT_MSG="real state recorded: ro ntfs-readonly"; assert_true status_has "$root" "ro	ntfs-readonly"
}

test_write_protected_fallback() {
    begin "write-protected-device-read-only-fallback"
    local root="$HERE/tmp-wp-fallback"
    simple_case "$root" '/dev/sda1: LABEL="Old" UUID="w" TYPE="ext4"' sda1 sda sata 0
    MOUNT_FALLBACK_RO="/dev/sda1" run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="real state recorded: ro readonly-fallback"; assert_true status_has "$root" "ro	readonly-fallback"
}

test_ntfs_inconsistent_unmountable() {
    begin "ntfs-inconsistent-fails-cleanly"
    local root="$HERE/tmp-ntfs-bad"
    simple_case "$root" '/dev/sdb3: LABEL="Quebrado" UUID="BE02" TYPE="ntfs"' sdb3 sdb sata 0
    MOUNT_RC_RW="/dev/sdb3=13" MOUNT_RC_RO="/dev/sdb3=13" run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="status records the failure"; assert_true status_has "$root" "failed	ntfs-inconsistent"
    ASSERT_MSG="created directory removed"; assert_false test -e "$root/mnt/Quebrado"
    ASSERT_MSG="no reverse symlink"; assert_false test -L "$root/mnt/sdb3"
}

test_failed_mount_keeps_existing_dir() {
    begin "failed-mount-keeps-preexisting-dir"
    local root="$HERE/tmp-keepdir"
    simple_case "$root" '/dev/sda1: LABEL="Old" TYPE="ext4"' sda1 sda sata 0
    mkdir -p "$root/mnt/Old"; : > "$root/mnt/Old/.keep"
    MOUNT_FAIL_DEVS="/dev/sda1" run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="pre-existing directory untouched"; assert_true test -e "$root/mnt/Old/.keep"
}

# ===== permission policy (/etc/big-mount.conf) =====

test_permissions_default_shared() {
    begin "permissions-default-is-shared"
    local root="$HERE/tmp-perm-default"
    simple_case "$root" '/dev/sdb1: LABEL="Win" TYPE="ntfs"' sdb1 sdb sata 0
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="no config file: umask=000 as before"; assert_true mount_log_grep "$root" ",umask=000,"
}

test_permissions_owner() {
    begin "permissions-owner"
    local root="$HERE/tmp-perm-owner"
    setup_root "$root"
    printf '%s\n' '/dev/sdb1: LABEL="Win" TYPE="ntfs"' '/dev/sdb2: LABEL="Pen" TYPE="exfat"' \
        '/dev/sdb3: LABEL="Lin" TYPE="ext4"' > "$root/fake-blkid"
    lsblk_map "$root" "sdb1 sdb sata" "sdb2 sdb sata" "sdb3 sdb sata"
    disk "$root" sdb
    printf '# comment\n  PERMISSIONS = owner   # trailing comment\n' > "$root/etc/big-mount.conf"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="NTFS: owner writes, others read"; assert_true mount_log_grep "$root" "lowntfs-3g .*,dmask=022,fmask=022,"
    ASSERT_MSG="exFAT: owner writes, others read"; assert_true mount_log_grep "$root" "noatime,rw,dmask=022,fmask=022,.*/dev/sdb2"
    ASSERT_MSG="no umask=000 left"; assert_false mount_log_grep "$root" "umask=000"
    ASSERT_MSG="ext4 unaffected"; assert_true mount_log_grep "$root" "-o noatime,rw,nodev,nofail,x-gvfs-show /dev/sdb3"
}

test_permissions_private_and_bad_value() {
    begin "permissions-private-and-invalid"
    local root="$HERE/tmp-perm-private"
    simple_case "$root" '/dev/sdb1: LABEL="Win" TYPE="vfat"' sdb1 sdb sata 0
    echo "PERMISSIONS=private" > "$root/etc/big-mount.conf"
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="private: umask=077"; assert_true mount_log_grep "$root" ",umask=077,"
    simple_case "$root" '/dev/sdb1: LABEL="Win" TYPE="vfat"' sdb1 sdb sata 0
    printf 'PERMISSIONS=%%s%%n$(touch %s/PWNED)\n' "$root" > "$root/etc/big-mount.conf"
    local out; out="$(run_script "$root" 2>&1)"
    ASSERT_MSG="value with printf directives is printed, not interpreted"; assert_true grep -qF "unknown value '%s%n" <<<"$out"
    ASSERT_MSG="invalid value falls back to shared"; assert_true mount_log_grep "$root" ",umask=000,"
    ASSERT_MSG="config is data, never executed"; assert_false test -e "$root/PWNED"
}

# ===== labels and paths (docs/10-security.md) =====

test_dot_labels() {
    begin "dot-and-dotdot-labels"
    local root="$HERE/tmp-dots"
    setup_root "$root"
    printf '%s\n' '/dev/sda1: LABEL=".." TYPE="ext4"' '/dev/sda2: LABEL="." TYPE="ext4"' > "$root/fake-blkid"
    lsblk_map "$root" "sda1 sda sata" "sda2 sda sata"
    disk "$root" sda
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="never mounts on /mnt/.. [new-only fix]"; assert_false mount_log_has "$root" "$root/mnt/.."
    ASSERT_MSG="never mounts on /mnt/. [new-only fix]"; assert_false mount_log_grep "$root" "$root/mnt/\.( |$)"
    ASSERT_MSG="falls back to /mnt/sda1"; assert_true mounted "$root" "$root/mnt/sda1"
    ASSERT_MSG="falls back to /mnt/sda2"; assert_true mounted "$root" "$root/mnt/sda2"
}

test_unicode_label() {
    begin "unicode-label-preserved"
    local root="$HERE/tmp-unicode"
    simple_case "$root" '/dev/sda1: LABEL="Fotos Família ✓" TYPE="ext4"' sda1 sda sata 0
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="UTF-8 kept, spaces replaced"; assert_true mounted "$root" "$root/mnt/Fotos_Família_✓"
}

test_quoted_label() {
    begin "escaped-quote-in-label"
    local root="$HERE/tmp-quote"
    simple_case "$root" '/dev/sda1: LABEL="My \"Disk\"" UUID="q" TYPE="ext4"' sda1 sda sata 0
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="label unescaped as one path component"; assert_true mounted "$root" "$root/mnt/My_\"Disk\""
}

test_label_command_substitution() {
    begin "label-is-never-executed"
    local root="$HERE/tmp-inject"
    simple_case "$root" '/dev/sda1: LABEL="$(touch PWNED)`touch PWNED2`" TYPE="ext4"' sda1 sda sata 0
    (cd "$root" && run_script "$root" >/dev/null 2>&1)
    ASSERT_MSG="no command executed from label"; assert_false test -e "$root/PWNED"
    ASSERT_MSG="no backtick executed from label"; assert_false test -e "$root/PWNED2"
}

test_stale_reverse_symlink() {
    begin "stale-reverse-symlink-refreshed"
    local root="$HERE/tmp-stale-link"
    setup_root "$root"
    mkdir -p "$root/mnt/Data" "$root/mnt/Other"
    ln -s "$root/mnt/Data" "$root/mnt/sdb1"
    printf '%s\n' '/dev/sda1: LABEL="Data" TYPE="ext4"' '/dev/sdb1: LABEL="Other" TYPE="ext4"' > "$root/fake-blkid"
    lsblk_map "$root" "sda1 sda sata" "sdb1 sdb sata"
    disk "$root" sda; disk "$root" sdb
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="/mnt/sdb1 points to sdb1's mount [new-only fix]"
    assert_true test "$(readlink "$root/mnt/sdb1")" = "$root/mnt/Other"
    ASSERT_MSG="/mnt/sda1 points to sda1's mount"
    assert_true test "$(readlink "$root/mnt/sda1")" = "$root/mnt/Data"
}

# ===== operation =====

test_dry_run() {
    begin "dry-run"
    local root="$HERE/tmp-dry"
    simple_case "$root" '/dev/sda1: LABEL="Data" TYPE="ext4"' sda1 sda sata 0
    local out
    out="$(run_script "$root" --dry-run 2>&1)"
    ASSERT_MSG="no mount executed"; assert_false test -s "$root/mount.log"
    ASSERT_MSG="no directory created"; assert_false test -e "$root/mnt/Data"
    ASSERT_MSG="plan printed"; assert_true grep -q "dry-run: mount -o noatime,rw" <<<"$out"
    ASSERT_MSG="no status file written"; assert_false test -e "$root/run/big-mount/status"
}

test_status_and_lock() {
    begin "status-file-and-lock"
    local root="$HERE/tmp-status"
    simple_case "$root" '/dev/sda1: LABEL="Data" UUID="u-1" TYPE="ext4"' sda1 sda sata 0
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="status entry"; assert_true status_has "$root" "/dev/sda1	u-1	$root/mnt/Data	rw	-"
    ASSERT_MSG="status header"; assert_true status_has "$root" "# big-mount status v1"
    ASSERT_MSG="lock file used"; assert_true test -e "$root/run/lock/big-mount.lock"
    ASSERT_MSG="mount helpers do not inherit the lock (FUSE daemons outlive bigmount)"; assert_false test -s "$root/fd.log"
}

test_lock_released_with_fuse_daemon() {
    begin "lock-free-while-ntfs-daemon-lives"
    local root="$HERE/tmp-lock-fuse"
    simple_case "$root" '/dev/sdb3: LABEL="Win" UUID="w" TYPE="ntfs"' sdb3 sdb sata 0
    run_script "$root" >/dev/null 2>&1
    ASSERT_MSG="second run is not blocked by the first one's lock"
    assert_true bash -c 'exec 9>"$1"; flock -n 9' _ "$root/run/lock/big-mount.lock"
}

# ===== field report (docs/12-field-report.md) =====
# A user ran bigmount on a computer with an NVMe disk and got, for every
# command: "grep: /var/lib/sddm/state.conf: Permission denied",
# "cat: /sys/block/nvme/removable: No such file or directory" and
# "Error looking up object for device /dev/nvme". These fail on the
# script of the biglinux-stable package (tests/bigmount.old.sh).

test_field_report_messages() {
    begin "field-report-sddm-and-nvme"
    local root="$HERE/tmp-field"
    setup_root "$root"
    printf '%s\n' '/dev/nvme0n1p1: UUID="AB12-CD34" TYPE="vfat" PARTLABEL="EFI system partition"' \
        '/dev/nvme0n1p2: LABEL="Arquivos" UUID="u-2" TYPE="ext4"' > "$root/fake-blkid"
    lsblk_map "$root" "nvme0n1p1 nvme0n1 nvme 0" "nvme0n1p2 nvme0n1 nvme 0"
    disk "$root" nvme0n1
    echo "User=$(id -un)" > "$root/var/lib/sddm/state.conf"
    chmod 000 "$root/var/lib/sddm/state.conf"
    run_script "$root" >/dev/null 2>"$root/stderr"
    chmod 644 "$root/var/lib/sddm/state.conf"
    if [ "$EUID" -ne 0 ]; then
        ASSERT_MSG="an unreadable SDDM state file gives no 'Permission denied'"
        assert_false grep -q 'state.conf' "$root/stderr"
    fi
    ASSERT_MSG="never reads /sys/block/nvme/ (a device name cut at the first digit)"
    assert_false grep -q '/sys/block/nvme/' "$root/stderr"
    ASSERT_MSG="UDisks2 is never asked about /dev/nvme"
    assert_false grep -qE '/dev/nvme( |$)' "$root/udisksctl.log"
    ASSERT_MSG="no error output at all"
    assert_false test -s "$root/stderr"
    ASSERT_MSG="the internal NVMe partition is still mounted"
    assert_true mounted "$root" "$root/mnt/Arquivos"
}

test_mmc_name_not_cut() {
    begin "field-report-mmc-name"
    local root="$HERE/tmp-field-mmc"
    simple_case "$root" '/dev/mmcblk0p1: LABEL="CAMERA" TYPE="exfat"' mmcblk0p1 mmcblk0 "" 0
    echo 1 > "$root/sys/block/mmcblk0/removable"
    run_script "$root" >/dev/null 2>"$root/stderr"
    ASSERT_MSG="never reads /sys/block/mmcblk/ (cut name)"; assert_false grep -q '/sys/block/mmcblk/' "$root/stderr"
    ASSERT_MSG="removable card read through its real name is left to UDisks"; assert_false test -s "$root/mount.log"
}

test_user_runs_boot_mode() {
    begin "user-runs-bigmount-without-options"
    local root="$HERE/tmp-user-run" rc
    simple_case "$root" '/dev/sda1: LABEL="Data" TYPE="ext4"' sda1 sda sata 0
    : > "$root/run/lock/big-mount.lock"; chmod 444 "$root/run/lock/big-mount.lock"
    FAKE_EUID=1000 run_script "$root" >"$root/stdout" 2>"$root/stderr"; rc=$?
    ASSERT_MSG="exit 5 (not authorized)"; assert_true test "$rc" -eq 5
    ASSERT_MSG="explains that big-mount.service does it at boot"; assert_true grep -q 'big-mount.service' "$root/stderr"
    ASSERT_MSG="no raw permission error"; assert_false grep -qi 'permission denied\|negada' "$root/stderr"
    ASSERT_MSG="not the misleading 'another bigmount is still running'"; assert_false grep -q 'still running' "$root/stderr" "$root/stdout"
    ASSERT_MSG="nothing mounted"; assert_false test -s "$root/mount.log"
}

test_unknown_last_user() {
    begin "sddm-names-unknown-account"
    local root="$HERE/tmp-ghost" first
    simple_case "$root" '/dev/sda1: LABEL="Win" TYPE="ntfs"' sda1 sda sata 0
    echo "User=no-such-account-$$" > "$root/var/lib/sddm/state.conf"
    first="$(getent passwd | awk -F: '$3 >= 1000 && $3 <= 60000 { print $3; exit }')"
    run_script "$root" >"$root/stdout" 2>&1
    ASSERT_MSG="an unknown account is reported"; assert_true grep -q 'no-such-account' "$root/stdout"
    if [ -n "$first" ]; then
        ASSERT_MSG="files belong to the first person account (uid=$first)"; assert_true mount_log_has "$root" "uid=$first,"
    else
        ASSERT_MSG="no person account: files belong to root, never a made-up uid"; assert_true mount_log_has "$root" "uid=0,"
    fi
}

test_lock_file_unwritable() {
    begin "lock-file-cannot-be-opened"
    local root="$HERE/tmp-lock-ro"
    [ "$EUID" -eq 0 ] && { echo "  (skipped as root: permissions are not enforced)"; return; }
    simple_case "$root" '/dev/sda1: LABEL="Data" TYPE="ext4"' sda1 sda sata 0
    : > "$root/run/lock/big-mount.lock"; chmod 444 "$root/run/lock/big-mount.lock"
    run_script "$root" >"$root/stdout" 2>"$root/stderr"
    ASSERT_MSG="says the lock file cannot be opened"; assert_true grep -q 'cannot open the lock file' "$root/stdout"
    ASSERT_MSG="not the misleading 'another bigmount is still running'"; assert_false grep -q 'still running' "$root/stdout"
    ASSERT_MSG="no raw shell error"; assert_false test -s "$root/stderr"
}

# ===== safety policy: forbidden operations in shipped code =====

test_no_destructive_commands() {
    begin "no-destructive-commands-shipped"
    local hits
    # Executable lines only (comments and user-facing help text excluded)
    hits="$(grep -rnE '(^|[;&|[:space:]])(ntfsfix|mkfs(\.[a-z0-9]+)?|wipefs|fsck(\.[a-z0-9]+)?|e2fsck|xfs_repair|sgdisk|parted|fdisk)[[:space:]]|btrfs[[:space:]]+check|umount[[:space:]]+-[a-zA-Z]*[fl]|kill[[:space:]]+-(9|KILL|SIGKILL)|fuser[[:space:]]+-[a-zA-Z]*k|chmod[[:space:]]+-R|chown[[:space:]]+-R|remove_hiberfile|--force' \
        "$REPO/big-mount" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v 'printf \$"' || true)"
    [ -n "$hits" ] && printf '%s\n' "$hits"
    ASSERT_MSG="no repair/format/force/kill -9/recursive chmod in big-mount/"; assert_true test -z "$hits"
}

# ===== the options besides the boot run (cli.sh) =====

# Big-Mount only mounts: what it did is diagnosed by Big Storage Rescue. Its
# own options never load a toolkit or another package, and the old ones say
# where they went.
test_options_and_moved_commands() {
    begin "options-and-moved-commands"
    local b="$REPO/big-mount/usr/bin/bigmount" out rc
    out="$(LANGUAGE=C bash "$b" --help)"; rc=$?
    ASSERT_MSG="--help works"; assert_true test "$rc" -eq 0
    ASSERT_MSG="  ... and names --dry-run, --doctor and --version"; assert_true bash -c '[[ $1 == *--dry-run* && $1 == *--doctor* && $1 == *--version* ]]' _ "$out"
    ASSERT_MSG="  ... and says where diagnosis and rescue are"; assert_true grep -q 'big-storage-rescue' <<< "$out"
    ASSERT_MSG="--version names Big-Mount"; assert_true bash -c 'bash "$1" --version | grep -q "^Big-Mount [0-9]"' _ "$b"
    LANGUAGE=C bash "$b" --doctor --fix >/dev/null 2>&1; rc=$?
    ASSERT_MSG="--doctor takes no option (it never changes anything)"; assert_true test "$rc" -eq 2
    out="$(LANGUAGE=C PATH=/usr/bin:/bin bash "$b" --drive copy --source /x 2>&1)"; rc=$?
    ASSERT_MSG="--drive: exit 2"; assert_true test "$rc" -eq 2
    ASSERT_MSG="  ... with the command that does it now, arguments kept"; assert_true grep -q 'big-storage-rescue --cli copy --source /x' <<< "$out"
    for pair in "--gui-drive:big-storage-rescue --gui" "--gui-drive-check:big-storage-rescue --gui-health" "--gui:big-storage-rescue --gui-diagnose" \
                "--diagnose:big-storage-rescue --diagnose" "--busy:big-storage-rescue --busy" "--unmount:big-storage-rescue --unmount" \
                "--safe-remove:big-storage-rescue --safe-remove" "--gui-remove:big-storage-rescue --gui-remove"; do
        out="$(LANGUAGE=C bash "$b" "${pair%%:*}" /dev/sdz1 2>&1)"; rc=$?
        ASSERT_MSG="${pair%%:*} points to ${pair#*:}"; assert_true bash -c '[ "$1" -eq 2 ] && [[ $2 == *"Use: $3 /dev/sdz1"* ]]' _ "$rc" "$out" "${pair#*:}"
    done
    out="$(LANGUAGE=C bash "$b" --secure-erase /dev/sdz 2>&1)"; rc=$?
    ASSERT_MSG="--secure-erase: refused, and no other tool is suggested"; assert_true bash -c '[ "$1" -eq 2 ] && [[ $2 == *"no longer part"* && $2 != *big-storage-rescue* ]]' _ "$rc" "$out"
    out="$(bash "$b" --notifier 2>&1)"; rc=$?
    ASSERT_MSG="--notifier (an old autostart entry): quiet, exit 0"; assert_true test "$rc:$out" = "0:"
    LANGUAGE=C bash "$b" --bogus >/dev/null 2>&1; rc=$?
    ASSERT_MSG="an unknown option: exit 2"; assert_true test "$rc" -eq 2
}

test_nothing_but_the_automount() {
    begin "nothing-but-the-automount"
    local lib="$REPO/big-mount/usr/lib/big-mount" files expect l
    files="$(cd "$REPO/big-mount" && find . -type f | sed 's|^\./||' | sort)"
    expect="$(
        printf '%s\n' etc/big-mount.conf usr/bin/bigmount usr/lib/big-mount/cli.sh \
            usr/lib/systemd/system/big-mount.service usr/share/libalpm/hooks/big-mount.hook
        while read -r l; do echo "usr/share/locale/$l/LC_MESSAGES/big-mount.mo"; done < "$REPO/locale/LINGUAS"
    )"
    ASSERT_MSG="only the automount and its translations are shipped (got: $(tr '\n' ' ' <<< "$files"))"
    assert_true test "$files" = "$(sort <<< "$expect")"
    code() { grep -rniE "$1" "$REPO/big-mount/usr/bin" "$lib" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'; }
    ASSERT_MSG="no Python, GTK or dialog anywhere"; assert_false code 'python|gi\.repository|gtk|libadwaita|kdialog|zenity|notify-send|pkexec'
    ASSERT_MSG="no copy, image or recovery tool"; assert_false code '\b(rsync|ddrescue|testdisk|photorec|smartctl|lsof)\b' 
    ASSERT_MSG="the boot run never reads cli.sh before an option"; assert_true bash -c 'awk "/cli.sh/ { print NR; exit }" "$1" | grep -q . && [ "$(grep -n "^DRY_RUN=\"\"" "$1" | cut -d: -f1)" -lt "$(grep -n "cli.sh\" ||" "$1" | cut -d: -f1)" ]' _ "$SCRIPT_SRC"
}

# ===== run all =====
echo "========================================="
echo "Running tests against: $VERSION_LABEL"
echo "script: $SCRIPT_SRC"
echo "========================================="

test_disabled
test_ext4_label
test_no_label
test_partlabel_fallback
test_swap_skipped
test_squashfs_skipped
test_ntfs_mount
test_fat_mount
test_usb_skipped
test_hintignore_skipped
test_idempotent_already_mounted
test_collision_suffix
test_compat_symlinks
test_nvme_removable_parent
test_mount_failure_no_symlink
test_proc_mounts_prefix_match
test_slash_in_label
test_usb_rm0_transport
test_usb_rm0_tran_only
test_usb_rm0_udev_only
test_usb_rm0_idpath_only
test_usb_multi_partition
test_hotplug_nvme_thunderbolt
test_internal_nvme
test_sd_card
test_sd_card_udev_flag
test_emmc_internal
test_esata_udisks_system
test_udev_settle_then_mount
test_udev_never_ready
test_virtual_devices
test_non_filesystems
test_fstab_managed
test_device_swapped_during_scan
test_fat_regex_bug
test_exfat_options
test_generic_filesystems
test_ntfs_hibernated
test_ntfs_silent_readonly_fallback
test_write_protected_fallback
test_ntfs_inconsistent_unmountable
test_failed_mount_keeps_existing_dir
test_permissions_default_shared
test_permissions_owner
test_permissions_private_and_bad_value
test_dot_labels
test_unicode_label
test_quoted_label
test_label_command_substitution
test_stale_reverse_symlink
test_dry_run
test_status_and_lock
test_lock_released_with_fuse_daemon
test_field_report_messages
test_mmc_name_not_cut
test_user_runs_boot_mode
test_unknown_last_user
test_lock_file_unwritable
test_no_destructive_commands
if [ "$VERSION_LABEL" = new ]; then
    test_options_and_moved_commands
    test_nothing_but_the_automount
fi

echo ""
echo "========================================="
echo "$VERSION_LABEL result: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    printf "  - %s\n" "${FAILED_TESTS[@]}"
fi
echo "========================================="

# clean tmp dirs
rm -rf "$HERE"/tmp-*

exit "$FAIL"
