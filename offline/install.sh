#!/bin/sh
# Installs PirateBox and any missing dependencies, without internet. Run as root on the router.
cd "$(dirname "$0")" || exit 1

installed=$(opkg list-installed)
todo=
for f in deps/*.ipk; do
	n=$(basename "$f")
	n=${n%%_*}
	printf '%s\n' "$installed" | grep -q "^$n - " || todo="$todo $f"
done

if [ -n "$todo" ]; then
	echo "Installing missing dependencies:$todo"
	# shellcheck disable=SC2086
	opkg install $todo || exit 1
fi

opkg install ./piratebox_*.ipk
