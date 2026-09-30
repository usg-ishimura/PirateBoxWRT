#!/bin/sh
# Crea dist/piratebox_<versione>_<arch>.ipk senza SDK (richiede solo sh, tar, gzip).
# Architettura predefinita "all"; se opkg la rifiuta: ARCH=mips_24kc ./build.sh
# Bundle per router senza internet (scarica uhttpd/ucode dal feed ufficiale, serve curl):
#   ARCH=mips_24kc RELEASE=22.03.4 ./build.sh --offline
set -eu
cd "$(dirname "$0")"

NAME=piratebox
ARCH=${ARCH:-all}
RELEASE=${RELEASE:-22.03.4}
DEPS="uhttpd ucode ucode-mod-fs"
VER=$(sed -n 's/^Version: //p' control/control)
OUT="dist/${NAME}_${VER}_${ARCH}.ipk"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
export COPYFILE_DISABLE=1

if tar --version 2>/dev/null | grep -q GNU; then
	OWNER="--owner=0 --group=0 --numeric-owner --format=ustar"
else
	# opkg non capisce gli header PAX/xattr che bsdtar (macOS) aggiungerebbe
	OWNER="--uid 0 --gid 0 --uname root --gname root --format ustar --no-xattrs"
fi

mkdir -p "$STAGE/data" "$STAGE/control" dist
cp -R root/. "$STAGE/data/"
cp PirateBox-logo.svg "$STAGE/data/www/piratebox/logo.svg"
cp control/* "$STAGE/control/"
find "$STAGE" -name .DS_Store -delete
sed -i.bak "s/^Architecture: .*/Architecture: $ARCH/" "$STAGE/control/control" && rm "$STAGE/control/control.bak"
echo "2.0" > "$STAGE/debian-binary"

find "$STAGE/data" -type d -exec chmod 755 {} +
find "$STAGE/data" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/data/etc/init.d/piratebox" "$STAGE/data/usr/sbin/piratebox-setup" "$STAGE"/data/www/piratebox/cgi-bin/*
chmod 755 "$STAGE/control/postinst" "$STAGE/control/prerm"

# shellcheck disable=SC2086
tar $OWNER -czf "$STAGE/data.tar.gz" -C "$STAGE/data" .
# shellcheck disable=SC2086
tar $OWNER -czf "$STAGE/control.tar.gz" -C "$STAGE/control" .
# shellcheck disable=SC2086
tar $OWNER -czf "$OUT" -C "$STAGE" ./debian-binary ./data.tar.gz ./control.tar.gz

echo "Creato: $OUT"

[ "${1:-}" = --offline ] || exit 0

[ "$ARCH" != all ] || { echo "Con --offline imposta ARCH (es. ARCH=mips_24kc)" >&2; exit 1; }

FEED="https://downloads.openwrt.org/releases/$RELEASE/packages/$ARCH/base"
BUNDLE="$STAGE/${NAME}-offline"
mkdir -p "$BUNDLE/deps"
cp "$OUT" "$BUNDLE/"
cp offline/install.sh "$BUNDLE/install.sh"
chmod 755 "$BUNDLE/install.sh"

curl -fsSL "$FEED/Packages.gz" | gzip -dc > "$STAGE/Packages"

# Risolve ricorsivamente le dipendenze e stampa "file sha256" per ogni pacchetto trovato nel feed
awk -v roots="$DEPS" '
BEGIN { RS = ""; FS = "\n" }
{
	name = ""; dep = ""; fn = ""; sum = ""
	for (i = 1; i <= NF; i++) {
		if ($i ~ /^Package: /) name = substr($i, 10)
		else if ($i ~ /^Depends: /) dep = substr($i, 10)
		else if ($i ~ /^Filename: /) fn = substr($i, 11)
		else if ($i ~ /^SHA256sum: /) sum = substr($i, 12)
	}
	if (name != "") { deps[name] = dep; file[name] = fn; sha[name] = sum }
}
END {
	n = split(roots, q, " "); head = 1; tail = n
	for (i = 1; i <= n; i++) seen[q[i]] = 1
	while (head <= tail) {
		p = q[head++]
		if (!(p in file)) continue
		print file[p], sha[p]
		m = split(deps[p], d, ",")
		for (j = 1; j <= m; j++) {
			gsub(/\(.*\)/, "", d[j]); gsub(/[ \t]/, "", d[j])
			if (d[j] != "" && !(d[j] in seen)) { seen[d[j]] = 1; q[++tail] = d[j] }
		}
	}
}' "$STAGE/Packages" > "$STAGE/wanted"

for r in $DEPS; do
	grep -q "^${r}_" "$STAGE/wanted" || { echo "Pacchetto $r non trovato in $FEED" >&2; exit 1; }
done

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

while read -r f sum; do
	curl -fsSL -o "$BUNDLE/deps/$f" "$FEED/$f"
	[ "$(sha256 "$BUNDLE/deps/$f")" = "$sum" ] || { echo "SHA256 errato: $f" >&2; exit 1; }
done < "$STAGE/wanted"

BOUT="dist/${NAME}-offline_${VER}_${ARCH}.tar.gz"
# shellcheck disable=SC2086
tar $OWNER -czf "$BOUT" -C "$STAGE" "${NAME}-offline"
echo "Creato: $BOUT ($(ls "$BUNDLE/deps" | wc -l | tr -d ' ') dipendenze)"
