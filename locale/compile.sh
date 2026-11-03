#!/bin/bash
# Build big-mount/usr/share/locale/<lang>/LC_MESSAGES/big-mount.mo from
# locale/*.po. The .mo files are committed: the PKGBUILD only copies
# big-mount/. Languages are listed in locale/LINGUAS.
# DEST=DIR writes the results into another tree (used by tests).
set -e
cd "$(dirname "$0")/.."
dest="${DEST:-big-mount}"
for po in locale/*.po; do
    lang="$(basename "$po" .po)"
    dir="$dest/usr/share/locale/$lang/LC_MESSAGES"
    mkdir -p "$dir"
    msgfmt --check -o "$dir/big-mount.mo" "$po"
done
