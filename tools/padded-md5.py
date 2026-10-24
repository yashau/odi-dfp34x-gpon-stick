#!/usr/bin/env python3
"""MD5 of an image padded with 0xFF (erased flash) to its partition size.

    padded-md5.py rootfs-mod.bin            # rootfs partition, 0x274000
    padded-md5.py k0.bin 0x14c000           # kernel partition

Compare with `md5sum /dev/mtdblockN` on the stick after writing.
"""
import hashlib
import sys

path = sys.argv[1]
size = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x274000
data = open(path, "rb").read()
if len(data) > size:
    sys.exit(f"{path} is {len(data)} bytes, larger than the partition ({size})")
print(hashlib.md5(data + b"\xff" * (size - len(data))).hexdigest())
