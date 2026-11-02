#!/bin/bash
# shellcheck disable=SC2016,SC2317,SC2329  # bash -c '...$1' snippets and helpers called through check()
# Internationalization tests: the catalog is complete and up to date, the
# generated resources match their templates, messages keep their printf
# placeholders, and the scripts pick the right language at run time
# (English source, pt_BR, fallback for untranslated languages and entries).
#
# Usage: tests/i18n-tests.sh

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
cd "$REPO" || exit 2

PASS=0 FAIL=0 FAILED=()
check() {
    local msg="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$msg"
    else FAIL=$((FAIL + 1)); FAILED+=("$msg"); printf '  \033[31m✗\033[0m %s\n' "$msg"; fi
}
begin() { echo "— $1"; }
WORK="$(mktemp -d)"
trap 'rm -rf -- "${WORK:?}"' EXIT

msgids() { msgcat --no-wrap "$1" 2>/dev/null | sed -n 's/^msgid "\(.*\)"$/\1/p' | grep -v '^$' | sort -u; }
export -f msgids

echo "========================================="
echo "Internationalization tests"
echo "========================================="

begin "catalog"
POT="$WORK/fresh.pot" bash locale/update-pot.sh
check "locale/big-mount.pot is up to date with the code (run locale/update-pot.sh)" \
    bash -c 'diff <(msgids "$1") <(msgids "$2")' _ "$WORK/fresh.pot" locale/big-mount.pot
for po in locale/*.po; do
    lang="$(basename "$po" .po)"
    check "$lang: compiles (msgfmt --check)" msgfmt --check -o /dev/null "$po"
    check "$lang: no untranslated message" test -z "$(msgattrib --untranslated --no-obsolete "$po" | grep '^msgid' | tail -n +2)"
    check "$lang: no fuzzy (unreviewed) message" test -z "$(msgattrib --only-fuzzy --no-obsolete "$po" | grep '^msgid' | tail -n +2)"
    check "$lang: listed in locale/LINGUAS" grep -qx "$lang" locale/LINGUAS
    check "$lang: no obsolete message left behind (#~)" bash -c '! grep -q "^#~" "$1"' _ "$po"
    check "$lang: every msgid of the template exists in the translation" \
        test -z "$(comm -23 <(msgids locale/big-mount.pot) <(msgids "$po"))"
    # The same printf directives, in the same order, in msgid and msgstr
    bad="$(python3 -I - "$po" <<'EOF'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
spec = re.compile(r"%[-+ #0]*[0-9]*(?:\.[0-9]+)?[sdiuxXfc%]")
for mid, mstr in re.findall(r'^msgid "(.*)"\nmsgstr "(.*)"$', text, re.M):
    if mid and mstr and spec.findall(mid) != spec.findall(mstr):
        print(mid)
EOF
)"
    check "$lang: placeholders (%s, %d) match in every message" test -z "$bad"
    [ -n "$bad" ] && printf '      %s\n' "$bad"
done

begin "generated catalog matches the translation (run locale/compile.sh)"
DEST="$WORK/gen" bash locale/compile.sh
check "pt_BR .mo" cmp -s <(msgunfmt "$WORK/gen/usr/share/locale/pt_BR/LC_MESSAGES/big-mount.mo") \
    <(msgunfmt big-mount/usr/share/locale/pt_BR/LC_MESSAGES/big-mount.mo)

begin "no user-visible text outside the translation system"
# Exit 1 only: a match (0) fails, and so does an error of grep (2), which prints nothing
check "code and templates are English (no accented letters outside .po/.mo)" \
    bash -c 'LC_ALL=C.UTF-8 grep -rqP "[\x{00C0}-\x{024F}]" "$@"; [ "$?" -eq 1 ]' _ big-mount/usr/bin big-mount/usr/lib locale/*.sh

begin "language chosen at run time"
BM=big-mount/usr/bin/bigmount
help_line() { env -i PATH="$PATH" "$@" bash "$BM" --help 2>/dev/null | head -n1; }
check "LANG=C: English" test "$(help_line LANG=C)" = "Usage: bigmount [OPTION]"
check "LANG=en_US.UTF-8: English" test "$(help_line LANG=en_US.UTF-8)" = "Usage: bigmount [OPTION]"
check "LANG=pt_BR.UTF-8: Portuguese" test "$(help_line LANG=pt_BR.UTF-8)" = "Uso: bigmount [OPÇÃO]"
check "language without translation (de_DE): English" test "$(help_line LANG=de_DE.UTF-8)" = "Usage: bigmount [OPTION]"
check "LANGUAGE=fr:pt_BR falls back to the next language" \
    test "$(help_line LANG=pt_BR.UTF-8 LANGUAGE=fr:pt_BR)" = "Uso: bigmount [OPÇÃO]"
check "errors are translated too" \
    bash -c 'env -i PATH="$PATH" LANG=pt_BR.UTF-8 bash "$1" --bogus 2>&1 | grep -q "opção desconhecida"' _ "$BM"
# bash translates $"..." while parsing a command: a text domain chosen inside
# the same block would come too late (the message stayed English)
if [ "$EUID" -ne 0 ]; then
    check "bigmount without options as a user: explanation translated, even without a terminal" \
        bash -c 'env -i PATH="$PATH" LANG=pt_BR.UTF-8 bash "$1" 2>&1 </dev/null | grep -q "exige direitos de administrador"' _ "$BM"
fi
check "--version translated" bash -c 'env -i PATH="$PATH" LANG=pt_BR.UTF-8 bash "$1" --version | grep -q "revisão:"' _ "$BM"
check "--version: translated labels aligned by characters, not bytes" env LC_ALL=C.UTF-8 bash -c '
    cols="$(env -i PATH="$PATH" LANG=pt_BR.UTF-8 bash "$1" --version | tail -n +2 | while IFS= read -r l; do
        [[ $l =~ ^([^:]*:\ +) ]] && echo "${#BASH_REMATCH[1]}"; done | sort -u | wc -l)"
    [ "$cols" -eq 1 ]' _ "$BM"
check "--doctor translated" bash -c 'env -i PATH="$PATH" LANG=pt_BR.UTF-8 HOME="$HOME" bash "$1" --doctor 2>/dev/null | grep -q "^Resultado: "' _ "$BM"
check "a command that moved is explained in the language of the user" \
    bash -c 'env -i PATH="$PATH" LANG=pt_BR.UTF-8 bash "$1" --drive 2>&1 | grep -q "foi para o Big Storage Rescue"' _ "$BM"

# A translation that lacks one message: that one stays English, the rest is translated
mkdir -p "$WORK/tree/usr/bin" "$WORK/tree/usr/share/locale/pt_BR/LC_MESSAGES"
cp "$BM" "$WORK/tree/usr/bin/"; cp -r big-mount/usr/lib "$WORK/tree/usr/"
msgattrib --no-wrap locale/pt_BR.po | python3 -I -c '
import sys
t = sys.stdin.read()
print(t.replace("msgstr \"Uso: bigmount [OPÇÃO]\"", "msgstr \"\""))' > "$WORK/partial.po"
msgfmt -o "$WORK/tree/usr/share/locale/pt_BR/LC_MESSAGES/big-mount.mo" "$WORK/partial.po"
out="$(env -i PATH="$PATH" LANG=pt_BR.UTF-8 bash "$WORK/tree/usr/bin/bigmount" --help)"
check "incomplete translation: the missing message falls back to English" grep -q "^Usage: bigmount" <<< "$out"
check "incomplete translation: the others are still translated" grep -q "mostra esta ajuda" <<< "$out"

begin "boot messages: translated on a terminal, English in the journal"
# A fake internal disk (stubs of tests/run-tests.sh): independent of the
# disks of the machine running the tests (CI containers have none)
fake="$WORK/fake"; mkdir -p "$fake/fake-udev"
echo '/dev/sdq1: LABEL="I18nTest" TYPE="ext4"' > "$fake/fake-blkid"
echo "sdq1 sdq sata" > "$fake/fake-lsblk"; : > "$fake/fake-fstab"
dry() { env -i PATH="$HERE/stubs:$PATH" TESTROOT="$fake" LANG=pt_BR.UTF-8 bash "$REPO/$BM" --dry-run; }
export -f dry; export HERE REPO BM fake
out_tty="$(script -qec "bash -c dry" /dev/null 2>/dev/null | tr -d '\r')"
out_log="$(dry 2>/dev/null)"
check "the fake disk is planned for mounting" grep -q "I18nTest" <<< "$out_log"
if [ -n "$out_tty" ]; then
    check "terminal: Portuguese" grep -qE "ignorado|montado|deixado" <<< "$out_tty"
else
    printf '  \033[33m-\033[0m terminal (skipped: script(1) unavailable)\n'
fi
check "journal (no terminal): English" bash -c '! grep -qE "ignorado|montado|deixado" <<< "$1" && grep -qE "skipped|mounted|left to UDisks" <<< "$1"' _ "$out_log"

echo ""
echo "========================================="
echo "i18n result: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && printf '  - %s\n' "${FAILED[@]}"
echo "========================================="
exit "$FAIL"
