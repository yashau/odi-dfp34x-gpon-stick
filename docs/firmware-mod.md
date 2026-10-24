# Firmware modification: boot hook

Adds [stick/rc40](../stick/rc40) to the stick's rootfs so `/var/config/rc.local`
runs at every boot. Nothing else in the firmware changes.

## Flash layout

`cat /proc/mtd` on the stick (DFP-34X-2C3, 8 MiB SPI NOR):

| mtd | Name | Size | Contents |
|-----|------|------|----------|
| mtd0 | boot | 256K | U-Boot |
| mtd1/2 | env, env2 | 8K each | U-Boot environment (redundant) |
| mtd3 | config | 240K | JFFS2, mounted on `/var/config` |
| mtd4 | k0 | 1328K | kernel, bank 0 (uImage) |
| mtd5 | r0 | 2512K | rootfs, bank 0 (squashfs) |
| mtd6 | k1 | 1328K | kernel, bank 1 |
| mtd7 | r1 | 2512K | rootfs, bank 1 |

The running bank is in `/proc/cmdline`: `root=31:5` = bank 0, `root=31:7` = bank 1.

The two banks can hold **different firmware versions**. Kernel modules in the
rootfs must match the kernel, so always write the **kernel together with the
rootfs** into the target bank. The flash script copies the running bank's
kernel for you.

## Boot selection

From the U-Boot environment (`nv getenv`):

```
bootcmd=if itest.s ${sw_tryactive} == 2; then run boot_by_commit;else run boot_by_tryactive;fi
boot_by_commit=if itest.s ${sw_commit} == 0;then run set_act0;run b0;else run set_act1;run b1;fi
boot_by_tryactive=if itest.s ${sw_tryactive} == 0;then setenv sw_tryactive 2;setenv sw_active 0;saveenv;run en_wdt;run b0;else setenv sw_tryactive 2;setenv sw_active 1;saveenv;run en_wdt;run b1;fi
```

- `sw_commit` picks the bank used on every normal boot.
- `sw_tryactive=<n>` boots bank `<n>` **once** (with the hardware watchdog
  armed), then resets itself to `2`. The next boot goes back to `sw_commit`.

So a new image is tested with `sw_tryactive`, and only made permanent with
`sw_commit` once it works. If the trial image misbehaves, a power cycle returns
to the committed bank.

## 1. Dump the running firmware

```sh
tools/stick-ssh.sh 'cat /dev/mtdblock5' > r0.bin   # running rootfs (bank 0 example)
tools/stick-ssh.sh 'cat /dev/mtdblock4' > k0.bin   # running kernel
tools/stick-ssh.sh 'cat /dev/mtdblock7' > r1.bin   # backup of the bank you will overwrite
tools/stick-ssh.sh 'cat /dev/mtdblock6' > k1.bin
```

Keep all four as backups.

The rootfs is squashfs 4.0, LZMA, 1 MiB blocks:

```
$ unsquashfs -s r0.bin
Found a valid SQUASHFS 4:0 superblock on r0.bin.
Compression lzma
Block size 1048576
Always-use-fragments option is specified
```

## 2. Build

```sh
tools/build-rootfs.sh r0.bin rootfs-mod.bin
```

This runs Debian's `squashfs-tools` in Docker (so it works from Windows/macOS
too), adds `stick/rc40` as `/etc/init.d/rc40`, and rebuilds with matching
options:

```
mksquashfs root rootfs-mod.bin -comp lzma -b 1048576 -always-use-fragments -all-root -no-xattrs -noappend
```

It checks the result fits the 2512K partition and prints the expected MD5 of the
image padded to the partition size, which the flash script verifies against.
The unpacking happens inside the container's own filesystem, because
unsquashing onto a Windows bind mount breaks symlinks and permissions.

## 3. Flash the inactive bank

The stick has only ~2 MB of free RAM, enough for the rootfs image but not the
kernel as well. The script writes the rootfs first, deletes the uploaded file,
then copies the kernel directly from the running bank.

```sh
tools/stick-ssh.sh 'cat > /var/tmp/rootfs-mod.bin' < rootfs-mod.bin
tools/stick-ssh.sh 'sh -s <expected-padded-md5>' < tools/flash-inactive-bank.sh
```

What it does:

1. Works out the running bank from `/proc/cmdline` and targets the other one
2. `flash_eraseall` + write the rootfs, then compare the partition MD5 with the
   expected padded MD5
3. Erase and copy the running kernel into the target kernel partition, then verify
4. Set `sw_tryactive` to the target bank

It stops on any mismatch before touching the boot settings.

## 4. Try-boot and commit

```sh
tools/stick-ssh.sh reboot
# wait for it to come back
tools/stick-ssh.sh 'grep -o "root=31:[0-9]" /proc/cmdline; ls -l /etc/init.d/rc40; ps | grep rc.local'
```

If it booted from the new bank (`root=31:7` when you started on bank 0) and
`rc.local` is running:

```sh
tools/stick-ssh.sh 'nv setenv sw_commit 1'   # the new bank number
```

If anything is wrong, power-cycle the stick; it boots the committed bank again.

## Reverting

```sh
tools/stick-ssh.sh 'nv setenv sw_commit 0; reboot'   # back to the original bank
```

`/var/config` is shared between banks, so `rc.local` stays in place but simply
isn't started by the stock firmware.
