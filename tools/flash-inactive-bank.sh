#!/bin/sh
# Run ON THE STICK. Writes /var/tmp/rootfs-mod.bin to the inactive bank, copies
# the running kernel next to it, verifies both, and arms a one-time trial boot.
#
#   tools/stick-ssh.sh 'cat > /var/tmp/rootfs-mod.bin' < rootfs-mod.bin
#   tools/stick-ssh.sh 'sh -s <expected-padded-md5>' < tools/flash-inactive-bank.sh
#
# <expected-padded-md5> is printed by tools/build-rootfs.sh (or tools/padded-md5.py).
# Nothing is committed: a power cycle after the trial boot returns to the
# current bank. Commit with `nv setenv sw_commit <bank>` once it works.

IMG=/var/tmp/rootfs-mod.bin
WANT=$1

fail() { echo "ERROR: $*"; exit 1; }

[ -n "$WANT" ] || fail "usage: sh -s <expected-padded-md5>"
[ -f "$IMG" ] || fail "$IMG not found"

if grep -q "root=31:5" /proc/cmdline; then
	BANK=1; K_SRC=/dev/mtdblock4; K_DST=6; R_DST=7
elif grep -q "root=31:7" /proc/cmdline; then
	BANK=0; K_SRC=/dev/mtdblock6; K_DST=4; R_DST=5
else
	fail "cannot tell which bank is running"
fi
echo "running bank $((1 - BANK)), writing bank $BANK (mtd$K_DST kernel, mtd$R_DST rootfs)"

echo "erasing rootfs mtd$R_DST"
flash_eraseall /dev/mtd$R_DST > /dev/null || fail "erase mtd$R_DST"
cat "$IMG" > /dev/mtd$R_DST || fail "write mtd$R_DST"
rm -f "$IMG"   # free RAM before handling the kernel
GOT=$(md5sum /dev/mtdblock$R_DST | cut -d" " -f1)
echo "rootfs md5 $GOT (want $WANT)"
[ "$GOT" = "$WANT" ] || fail "rootfs verify failed, boot settings untouched"

echo "erasing kernel mtd$K_DST, copying $K_SRC"
flash_eraseall /dev/mtd$K_DST > /dev/null || fail "erase mtd$K_DST"
cat $K_SRC > /dev/mtd$K_DST || fail "write mtd$K_DST"
KS=$(md5sum $K_SRC | cut -d" " -f1)
KD=$(md5sum /dev/mtdblock$K_DST | cut -d" " -f1)
echo "kernel md5 $KD (want $KS)"
[ "$KS" = "$KD" ] || fail "kernel verify failed, boot settings untouched"

nv setenv sw_tryactive $BANK
echo "armed: sw_tryactive=$(nv getenv sw_tryactive | cut -d= -f2), sw_commit=$(nv getenv sw_commit | cut -d= -f2)"
echo "reboot to try bank $BANK; commit afterwards with: nv setenv sw_commit $BANK"
