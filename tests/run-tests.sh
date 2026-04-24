#!/bin/bash
# Unit test harness for bigmount.
# Usage: run-tests.sh {old|new}
# Stubs out blkid, lsblk, udisksctl, mount, ntfsfix.
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

transform_script() {
    local src="$1" dst="$2" root="$3"
    # Placeholder trick: rewrite /run/media first so later /media rule won't recurse into it.
    sed \
        -e "s|/etc/bigmountall-no|$root/etc/bigmountall-no|g" \
        -e "s|/var/lib/sddm|$root/var/lib/sddm|g" \
        -e "s|/var/lib/lightdm|$root/var/lib/lightdm|g" \
        -e "s|/run/media|__RUNMEDIA__|g" \
        -e "s|/proc/mounts|$root/proc/mounts|g" \
        -e "s|/sys/block|$root/sys/block|g" \
        -e "s|/mnt|$root/mnt|g" \
        -e "s|/media|$root/media|g" \
        -e "s|__RUNMEDIA__|$root/run/media|g" \
        "$src" > "$dst"
    chmod +x "$dst"
}

setup_root() {
    local root="$1"
    rm -rf "$root"
    mkdir -p "$root/etc" "$root/mnt" "$root/run/media" "$root/proc" \
             "$root/sys/block" "$root/var/lib/sddm" "$root/var/lib/lightdm" \
             "$root/fake-udisksctl"
    : > "$root/proc/mounts"
    : > "$root/mount.log"
    : > "$root/ntfsfix.log"
    : > "$root/fake-lsblk"
    : > "$root/fake-blkid"
    echo "User=" > "$root/var/lib/sddm/state.conf"
}

run_script() {
    local root="$1"
    local tmp="$root/bigmount.patched"
    transform_script "$SCRIPT_SRC" "$tmp" "$root"
    env -i TESTROOT="$root" HOME="$HOME" PATH="$HERE/stubs:/usr/bin:/bin" \
        MOUNT_FAIL_DEVS="${MOUNT_FAIL_DEVS:-}" bash "$tmp"
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
    ASSERT_MSG="ntfsfix invoked";            assert_true grep -qF "/dev/sdb1" "$root/ntfsfix.log"
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
