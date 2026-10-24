#!/bin/sh
# Rebuild a dumped stick rootfs with stick/rc40 added as /etc/init.d/rc40.
#
#   tools/build-rootfs.sh <rootfs-dump.bin> <output.bin>
#
# Needs Docker. Unpacking and repacking happen inside the container's own
# filesystem; unsquashing onto a Windows bind mount breaks symlinks.
set -eu

[ $# -eq 2 ] || { echo "usage: $0 <rootfs-dump.bin> <output.bin>" >&2; exit 1; }

# Absolute directory path in a form Docker accepts. Git Bash's `pwd` gives
# /c/... paths that Docker Desktop can't mount; `pwd -W` gives C:/... there.
absdir() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

REPO=$(absdir "$(dirname "$0")/..")
IN_DIR=$(absdir "$(dirname "$1")"); IN_FILE=$(basename "$1")
OUT_DIR=$(absdir "$(dirname "$2")"); OUT_FILE=$(basename "$2")
PART_SIZE=$((0x274000))   # r0/r1 partition size (2512 KiB)

# Git Bash on Windows would otherwise rewrite the container paths.
export MSYS_NO_PATHCONV=1

docker run --rm \
	-v "$IN_DIR:/in:ro" -v "$OUT_DIR:/out" -v "$REPO/stick:/stick:ro" \
	-e IN_FILE="$IN_FILE" -e OUT_FILE="$OUT_FILE" -e PART_SIZE="$PART_SIZE" \
	debian:bookworm-slim sh -euc '
		apt-get update -qq >/dev/null
		apt-get install -y -qq squashfs-tools python3-minimal >/dev/null 2>&1
		mkdir -p /work && cd /work
		unsquashfs -s "/in/$IN_FILE" | grep -E "Compression|Block size"
		unsquashfs -d root "/in/$IN_FILE" >/dev/null
		tr -d "\r" < /stick/rc40 > root/etc/init.d/rc40
		chmod 755 root/etc/init.d/rc40
		mksquashfs root "/out/$OUT_FILE" -comp lzma -b 1048576 -always-use-fragments \
			-all-root -no-xattrs -noappend >/dev/null
		size=$(stat -c %s "/out/$OUT_FILE")
		echo "image: $size bytes (partition $PART_SIZE)"
		[ "$size" -le "$PART_SIZE" ] || { echo "image too large" >&2; exit 1; }
		unsquashfs -d check "/out/$OUT_FILE" >/dev/null
		echo "rc40 in image:"; ls -l check/etc/init.d/rc40
		python3 -c "import hashlib,sys; b=open(sys.argv[1],\"rb\").read(); b+=b\"\xff\"*(int(sys.argv[2])-len(b)); print(\"expected padded md5:\", hashlib.md5(b).hexdigest())" \
			"/out/$OUT_FILE" "$PART_SIZE"
	'
