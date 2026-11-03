#!/bin/bash
# Regenerate locale/big-mount.pot from the $"..." strings of the scripts
# (bash --dump-po-strings) and merge it into locale/*.po. Run it after
# changing any message, then translate the new entries and run
# locale/compile.sh.
# POT=FILE writes the template elsewhere and merges nothing (used by tests).
set -e
cd "$(dirname "$0")/.."
pot="${POT:-locale/big-mount.pot}"
{
    printf 'msgid ""\nmsgstr ""\n"Project-Id-Version: big-mount\\n"\n'
    printf '"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n\n'
    for f in big-mount/usr/bin/bigmount big-mount/usr/lib/big-mount/*.sh; do
        bash --dump-po-strings "$f"
    done
} | msguniq --no-wrap -o "$pot" -
[ -z "${POT:-}" ] || exit 0
for po in locale/*.po; do
    [ -e "$po" ] || continue
    msgmerge --quiet --no-wrap --update --backup=none "$po" locale/big-mount.pot
    msgattrib --no-obsolete --no-wrap -o "$po" "$po"
done
