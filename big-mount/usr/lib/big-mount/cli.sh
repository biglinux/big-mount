# shellcheck shell=bash
#
# big-mount: everything bigmount does besides mounting at boot. Loaded by
# /usr/bin/bigmount only when it is given an option other than --dry-run, so
# the boot run never reads this file.
#
#   --help, --version   what this is, and which code is installed
#   --doctor            is the boot service doing its job? (nothing is changed)
#   old options         the drive manager, the diagnosis and safe removal of
#                       Big-Mount 2.x are now Big Storage Rescue: say where
#
# Plain bash: no GTK, no Python, nothing of Big Storage Rescue is needed.
#
# Exit codes: 0 done, 1 a problem was found (--doctor), 2 usage, or an option
# that moved to Big Storage Rescue.

export TEXTDOMAIN=big-mount
# /usr/lib/big-mount -> /usr/share/locale (a source checkout uses its own)
BM_LIB_DIR="${BIGMOUNT_LIB:-/usr/lib/big-mount}"
export TEXTDOMAINDIR="${BM_LIB_DIR%/lib/big-mount}/share/locale"
# Translations are data: never let a .mo file expand $(...) or variables
shopt -s noexpand_translation 2>/dev/null

BM_VERSION=3.0.0
BM_STATUS_FILE=/run/big-mount/status

bm_usage() {
   printf $"Usage: bigmount [OPTION]"'\n\n'
   # printf pads by bytes: the translated "(none)" is padded by columns
   # shellcheck disable=SC2247  # $"(none)" is a translatable string
   bm_pad $"(none)" 16; printf '  %s %s\n' "$REPLY" $"mount internal partitions (run at boot by big-mount.service)"
   printf '  %-16s %s\n' \
      "--dry-run" $"show what would be mounted, change nothing" \
      "--doctor" $"check the boot service and what it did in this boot" \
      "-V, --version" $"show the version and the source revision" \
      "-h, --help" $"show this help"
   printf '\n%s\n' $"Configuration: /etc/big-mount.conf. To mount again now: sudo systemctl restart big-mount"
   printf '%s\n' $"Diagnosis of devices, safe removal and file rescue: big-storage-rescue (package big-storage-rescue)."
}

bm_main() {
   local cmd="$1"
   shift
   case "$cmd" in
      -h | --help) bm_usage ;;
      -V | --version) bm_cmd_version ;;
      --doctor) bm_cmd_doctor "$@" ;;
      # Started from the autostart folder of whoever turned the notifier of
      # Big-Mount 2.x on: there is nothing to say at every login
      --notifier) return 0 ;;
      --diagnose | --busy | --unmount | --safe-remove | --gui | --gui-remove | --gui-drive | --gui-drive-check | \
         --drive | --secure-erase | --privileged-holders)
         bm_moved "$cmd" "$@"
         ;;
      *)
         printf $"bigmount: unknown option '%s' (see bigmount --help)"'\n' "$cmd" >&2
         return 2
         ;;
   esac
}

# An option of Big-Mount 2.x: the command that does it now
bm_moved() {
   local cmd="$1" new
   shift
   case "$cmd" in
      --drive) new="big-storage-rescue --cli" ;;
      --gui-drive) new="big-storage-rescue --gui" ;;
      --gui-drive-check) new="big-storage-rescue --gui-health" ;;
      --gui) new="big-storage-rescue --gui-diagnose" ;;
      --secure-erase)
         printf '%s\n' $"bigmount: Secure Erase is no longer part of Big-Mount." >&2
         return 2
         ;;
      --privileged-holders) return 2 ;;
      *) new="big-storage-rescue $cmd" ;;
   esac
   printf $"bigmount: %s moved to Big Storage Rescue. Use: %s"'\n' "$cmd" "$new${*:+ $*}" >&2
   if ! command -v big-storage-rescue >/dev/null; then
      printf '%s\n' $"Install it with: sudo pacman -S big-storage-rescue" >&2
   fi
   return 2
}

# Everything but the East Asian wide characters (CJK, its rarer ideographs in
# planes 2 and 3, kana, Hangul, full-width forms), which take two columns
BM_NARROW=$'[!ᄀ-ᅟ⺀-꓏가-힣豈-﫿︰-﹏＀-｠￠-￦\U00020000-\U0003fffd]'

# bm_width TEXT: the terminal columns TEXT takes, in REPLY
bm_width() {
   local wide="${1//$BM_NARROW/}"
   REPLY=$((${#1} + ${#wide}))
}

# Pad TEXT to WIDTH terminal columns (not bytes: translations have accents,
# and CJK characters take two columns)
bm_pad() {
   local s="${1//[[:cntrl:]]/?}" w="$2"
   bm_width "$s"
   printf -v REPLY '%s%*s' "$s" $((REPLY < w ? w - REPLY : 0)) ""
}

# ---------------------------------------------------------------------------
# --version

# bm_version_info: V_REVISION, V_DATE, V_SOURCE (where the code came from)
# and V_PKG (the installed package, when this is the packaged copy).
# The PKGBUILD writes $BM_LIB_DIR/version as KEY=value lines; it is read as
# data and every value is checked, never sourced.
bm_version_info() {
   local f="$BM_LIB_DIR/version" key val top
   V_REVISION="" V_DATE="" V_SOURCE="" V_PKG=""
   if [ -r "$f" ]; then
      while IFS='=' read -r key val; do
         case "$key" in
            revision) [[ $val =~ ^[0-9a-f]{7,40}(-dirty)?$ ]] && V_REVISION="$val" ;;
            date) [[ $val =~ ^[0-9T:+-]+Z?$ ]] && V_DATE="$val" ;;
            source) [[ $val =~ ^https://[A-Za-z0-9./_-]+$ ]] && V_SOURCE="$val" ;;
         esac
      done < "$f"
   else
      # A source checkout: ask git, when there is one
      if command -v git >/dev/null && top="$(git -C "$BM_LIB_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
         V_REVISION="$(git -C "$top" describe --always --dirty --tags 2>/dev/null)"
         V_DATE="$(TZ=UTC git -C "$top" log -1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd 2>/dev/null)"
      fi
      V_SOURCE=$"source checkout (not installed by a package)"
   fi
   if [ "$BM_LIB_DIR" = /usr/lib/big-mount ] && command -v pacman >/dev/null; then
      V_PKG="$(pacman -Qqo /usr/bin/bigmount 2>/dev/null | head -n1)"
      [ -n "$V_PKG" ] && V_PKG="$(pacman -Q -- "$V_PKG" 2>/dev/null)"
   fi
}

bm_cmd_version() {
   local l_pkg=$"package:" l_rev=$"revision:" l_src=$"source:" l w=0
   bm_version_info
   # Labels are aligned by terminal columns (accents, CJK)
   for l in "$l_pkg" "$l_rev" "$l_src"; do
      bm_width "$l"; [ "$REPLY" -gt "$w" ] && w="$REPLY"
   done
   printf 'Big-Mount %s\n' "$BM_VERSION"
   [ -n "$V_PKG" ] && { bm_pad "$l_pkg" "$w"; printf '  %s %s\n' "$REPLY" "$V_PKG"; }
   [ -n "$V_REVISION" ] || V_REVISION=$"unknown"
   bm_pad "$l_rev" "$w"; printf '  %s %s\n' "$REPLY" "$V_REVISION${V_DATE:+ ($V_DATE)}"
   [ -n "$V_SOURCE" ] && { bm_pad "$l_src" "$w"; printf '  %s %s\n' "$REPLY" "$V_SOURCE"; }
   return 0
}

# ---------------------------------------------------------------------------
# --doctor: the boot service, what it did, its configuration. Nothing is
# changed, and the report never prints labels or mount points (they carry the
# names people gave their disks).

# bm_dr LEVEL TEXT [DETAIL]. LEVEL: ok | info | warn | fail
bm_dr() {
   local level="$1" text="$2" detail="${3:-}" tag
   case "$level" in
      ok) tag=" OK " ;;
      info) tag="INFO" ;;
      warn) tag="WARN"; DR_WARN=$((DR_WARN + 1)) ;;
      fail) tag="FAIL"; DR_FAIL=$((DR_FAIL + 1)) ;;
   esac
   if [ -n "$DR_COLOR" ]; then
      case "$level" in
         ok) tag=$'\e[32m'"$tag"$'\e[0m' ;;
         warn) tag=$'\e[33m'"$tag"$'\e[0m' ;;
         fail) tag=$'\e[1;31m'"$tag"$'\e[0m' ;;
      esac
   fi
   printf '  [%s] %s\n' "$tag" "${text//[[:cntrl:]]/?}"
   [ -n "$detail" ] && printf '         %s\n' "${detail//$'\n'/$'\n'         }"
   return 0
}

# Messages with data: a translated FORMAT and its ARGS, into REPLY
# shellcheck disable=SC2059
bm_fmt() { local f="$1"; shift; printf -v REPLY -- "$f" "$@"; }

bm_dr_install() {
   local f st own mode
   printf '\n%s\n' "Big-Mount"
   bm_version_info
   bm_dr info "Big-Mount $BM_VERSION, ${V_REVISION:-?}${V_DATE:+ ($V_DATE)}" "$V_PKG"
   for f in /usr/bin/bigmount /usr/lib/systemd/system/big-mount.service; do
      [ -e "$f" ] && continue
      bm_fmt $"Missing file of the package: %s" "$f"
      bm_dr fail "$REPLY" $"Reinstall the big-mount package."
   done
   # bigmount runs as root at boot: nobody else may change it
   for f in /usr/bin/bigmount /usr/lib/big-mount /usr/lib/big-mount/* /etc/big-mount.conf; do
      [ -e "$f" ] || continue
      st="$(stat -c '%U %a' -- "$f" 2>/dev/null)" || continue
      own="${st% *}" mode="${st#* }"
      if [ "$own" != root ] || (( 8#$mode & 8#022 )); then
         bm_fmt $"Unsafe owner or permissions: %s (%s)" "$f" "$st"
         bm_dr fail "$REPLY" $"Reinstall the big-mount package."
      fi
   done
}

bm_dr_service() {
   local enabled active result frag dropins s line n=0 failed=() warns=()
   printf '\n%s\n' $"Boot service (big-mount.service)"
   if [ -e /etc/bigmountall-no ]; then
      bm_dr info $"/etc/bigmountall-no exists: mounting at boot is disabled on purpose"
   fi
   enabled="$(systemctl is-enabled big-mount.service 2>/dev/null)"
   active="$(systemctl is-active big-mount.service 2>/dev/null)"
   while IFS='=' read -r s line; do
      case "$s" in
         Result) result="$line" ;;
         FragmentPath) frag="$line" ;;
         DropInPaths) dropins="$line" ;;
      esac
   done < <(systemctl show -p Result -p FragmentPath -p DropInPaths big-mount.service 2>/dev/null)
   case "$enabled" in
      enabled) bm_dr ok $"Enabled at boot" ;;
      "") bm_dr fail $"Not found by systemd" $"Reinstall the big-mount package." ;;
      *) bm_fmt $"Not enabled at boot (%s)" "$enabled"; bm_dr warn "$REPLY" $"Enable it: sudo systemctl enable big-mount" ;;
   esac
   if [ "$active" = active ] && [ "${result:-success}" = success ]; then
      bm_dr ok $"Ran in this boot"
   elif [ "$enabled" = enabled ]; then
      bm_fmt $"State in this boot: %s (%s)" "${active:-?}" "${result:-?}"
      bm_dr warn "$REPLY" $"See: journalctl -b -u big-mount"
   fi
   if [ -n "${frag:-}" ] && [[ $frag != /usr/lib/systemd/system/* ]]; then
      bm_fmt $"The unit is replaced by %s" "$frag"
      bm_dr warn "$REPLY" $"A copy in /etc/systemd/system overrides the package: remove it unless it is intended."
   fi
   [ -n "${dropins:-}" ] && { bm_fmt $"Drop-in files change the unit: %s" "$dropins"; bm_dr info "$REPLY"; }

   # What the boot run did, without mount points (they carry the labels)
   if [ -r "$BM_STATUS_FILE" ]; then
      while IFS=$'\t' read -r dev _ _ s line; do
         [[ $dev == /dev/* ]] || continue
         n=$((n + 1))
         [ "$s" = failed ] && failed+=("$dev: $line")
         [ "$s" = ro ] && warns+=("$dev: $line")
      done < "$BM_STATUS_FILE"
      bm_fmt $"Partitions handled by Big-Mount at boot: %d" "$n"; bm_dr info "$REPLY"
      [ "${#failed[@]}" -gt 0 ] && bm_dr warn $"Failed at boot" "$(printf '%s\n' "${failed[@]}")"
      [ "${#warns[@]}" -gt 0 ] && bm_dr warn $"Mounted read-only at boot" "$(printf '%s\n' "${warns[@]}")"
   fi

   if [ -r /etc/big-mount.conf ]; then
      s="$(sed -n 's/^[[:space:]]*PERMISSIONS[[:space:]]*=[[:space:]]*\([^#[:space:]]*\).*/\1/p' /etc/big-mount.conf | tail -n1)"
      case "${s:-shared}" in
         shared | owner | private) bm_fmt $"Configuration: PERMISSIONS=%s" "${s:-shared}"; bm_dr ok "$REPLY" ;;
         *) bm_dr warn $"Configuration: unknown PERMISSIONS value, shared is used" "/etc/big-mount.conf" ;;
      esac
   fi

   if journalctl -b -q -n 1 -u big-mount.service >/dev/null 2>&1; then
      mapfile -t warns < <(journalctl -b -q --no-pager -o cat -p warning -u big-mount.service 2>/dev/null \
         | sed -E 's#/(mnt|media|run/media)/[^ ]*#/\1/…#g' | tail -n 10)
      if [ "${#warns[@]}" -gt 0 ] && [ -n "${warns[0]}" ]; then
         bm_dr warn $"Warnings in the journal of this boot" "$(printf '%s\n' "${warns[@]}")"
      fi
   else
      bm_dr info $"The journal is not readable by this user: boot messages not checked"
   fi
}

bm_cmd_doctor() {
   if [ "$#" -gt 0 ]; then
      printf $"bigmount: unknown option '%s' (see bigmount --help)"'\n' "$1" >&2
      return 2
   fi
   DR_WARN=0 DR_FAIL=0 DR_COLOR=""
   [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && DR_COLOR=1
   printf '%s\n' $"Big-Mount check (nothing is changed; labels and mount points are left out)"
   bm_dr_install
   bm_dr_service
   printf '\n'
   printf $"Result: %d problem(s), %d warning(s)."'\n' "$DR_FAIL" "$DR_WARN"
   if command -v big-storage-rescue >/dev/null; then
      printf '%s\n' $"Why a partition is read-only or failed to mount, and the health of its drive: big-storage-rescue --diagnose DEVICE"
   else
      printf '%s\n' $"To find out why a partition is read-only or failed to mount, install big-storage-rescue."
   fi
   [ "$DR_FAIL" -eq 0 ]
}
