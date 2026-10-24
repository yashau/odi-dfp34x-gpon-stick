# ODI DFP-34X GPON stick

A guide to running an **ODI DFP-34X** GPON SFP stick in place of an ISP ONT,
plus a small firmware addition that gives the stick a persistent, editable boot
script.

Tested with:

| | |
|---|---|
| Stick | ODI DFP-34X-2C3, Realtek RTL9602C, firmware `V1.0-220923` |
| Routers | MikroTik hEX S (RB760iGS), RouterOS 7.25; UniFi Dream Machine Pro |

Network-specific notes:

- [Calix AXOS OLT](docs/calix-axos.md): identity format, the storm-control
  watchdog it needs, and VLAN translation: the stick tags the PON-side VLAN
  (e.g. 66) itself with Manual/PVID mode, and the router sends untagged.
- [Huawei OLT](docs/huawei.md): identity format, Huawei OMCI mode, and
  transparent VLAN: the router tags the service VLAN (e.g. 100) and the stick
  passes it through.

## Contents

```
stick/rc40                     boot hook added to the stick's rootfs (/etc/init.d/rc40)
stick/rc.local                 base boot script, goes in /var/config/rc.local
examples/calix-axos-rc.local   rc.local for a Calix AXOS OLT (storm-control watchdog)
tools/stick-ssh.sh             SSH wrapper with the legacy algorithms the stick needs
tools/build-rootfs.sh          rebuild a dumped rootfs with rc40 added (uses Docker)
tools/flash-inactive-bank.sh   run on the stick: write rootfs + kernel to the inactive bank
tools/padded-md5.py            expected MD5 of an image padded to its partition size
docs/firmware-mod.md           building, flashing, try-boot, commit, revert
docs/diagnostics.md            diag / omcicli / mib commands
docs/mikrotik.md               RouterOS configuration
docs/calix-axos.md             Calix AXOS OLT specifics
docs/huawei.md                 Huawei OLT specifics
AGENTS.md                      notes for AI agents working on the stick or this repo
```

## 1. Access the stick

Put the stick in a host where its SFP link comes up (a media converter is the
easiest start, see step 5) and connect from that side. The management IP is
set in the web UI.

- Web UI: `http://<stick-ip>/`
- SSH and telnet: `admin` / `admin` by default. The SSH server is an old
  dropbear that only offers legacy algorithms; use
  [tools/stick-ssh.sh](tools/stick-ssh.sh). It allows **one session at a time**.
- The shell is BusyBox 1.12 without `head`, `tail`, `sort`, `od`, `touch` or
  `dmesg`. Filter output on your PC.

Settings: `flash get|set <KEY> [value]`, saved with `mib commit`. Most take
effect after `reboot`. `mib commit` is asynchronous, so wait a few seconds
before rebooting or the change is lost.

## 2. Clone the ONT identity

Values are placeholders; take yours from the ONT label or its web UI.

```sh
flash set GPON_SN VVVVxxxxxxxx          # FSAN: 4-char vendor ID + 8 hex digits
flash set PON_VENDOR_ID VVVV
flash set HW_SERIAL_NO <hex of VVVV><xxxxxxxx>
flash set GPON_PLOAM_PASSWD 00000000000000000000   # if your network uses one, set it here
mib commit
```

Optional, mostly cosmetic: `OUI`, `GPON_ONU_MODEL` / `HW_CWMP_PRODUCTCLASS`,
software and hardware versions (web UI → OMCI info).

**Leave `ELAN_MAC_ADDR` and `MAC_KEY` as shipped.** `MAC_KEY` is an MD5-based
license tied to the MAC. If the MAC changes without a matching key, `omci_app`
exits with `GPON mac_check fail`, and the stick stays in O0 with the laser off.
The MAC isn't used on GPON: data travels in GEM frames, and the WAN connection
(PPPoE, DHCP, ...) uses the router's MAC.

After a reboot, check what the stick actually presents to the OLT:

```
# diag gpon get serial-number
serial number: VVVV 0x........
# diag gpon get onu-state
ONU state: Operation State(O5)
```

`omcicli set sn` only changes the OMCI-layer copy, not this PLOAM serial.

## 3. VLAN

| Mode | Keys | Behaviour |
|------|------|-----------|
| Auto | `VLAN_CFG_TYPE=0` | follow the VLAN rules the OLT sends over OMCI |
| Manual, transparent | `VLAN_CFG_TYPE=1`, `VLAN_MANU_MODE=0` | pass frames as they are |
| Manual, PVID | `VLAN_CFG_TYPE=1`, `VLAN_MANU_MODE=1`, `VLAN_MANU_TAG_VID=<vid>` | tag untagged LAN frames with `<vid>`, strip it downstream |

Web UI → **VLAN Settings**. These are passed to `omci_app` at startup, so they
need a reboot. To see the VLAN the OLT expects on the PON side:
`omcicli mib get VlanTagFilterData`.

## 4. Persistent boot script

The rootfs is read-only squashfs, and the stock boot never runs anything from
the writable config partition (`/var/config`, JFFS2). Runtime settings made with
`diag` are lost on every reboot, and some are overwritten whenever the OLT
re-provisions the stick.

The firmware addition here is one file:

- [stick/rc40](stick/rc40) is added to the rootfs as `/etc/init.d/rc40`. The
  stock `/etc/init.d/rcS` runs `rc0`…`rc63` in order, so it runs at boot and
  starts `/var/config/rc.local` in the background if that file exists.

`/var/config/rc.local` is then an ordinary script you can edit at any time
without reflashing. Start from [stick/rc.local](stick/rc.local), or a network
example such as [examples/calix-axos-rc.local](examples/calix-axos-rc.local).

```sh
tools/stick-ssh.sh 'cat > /var/config/rc.local; chmod 755 /var/config/rc.local' < stick/rc.local
```

Building and flashing the rootfs: [docs/firmware-mod.md](docs/firmware-mod.md).
The stick has two firmware banks and a try-once boot, so the original bank
stays intact and a bad image is undone by a power cycle.

## 5. SFP host interface

`LAN_SDS_MODE` selects the electrical interface on the SFP edge connector:

| Value | Interface | Speed |
|-------|-----------|-------|
| 1 | 1000BASE-X | 1G (firmware default) |
| 3 | SGMII MAC | 1G |
| 4–6 | (H)SGMII / 2500BASE-X | 2.5G |
| 7 | SGMII Force | 1G |

| Host | Stick | Host port |
|------|-------|-----------|
| MikroTik hEX S `sfp1` | `LAN_SDS_MODE=1` (runs as `7`) | `auto-negotiation=no speed=1G-baseT-full` |
| Media converter | `LAN_SDS_MODE=3` | copper side on auto-negotiation |

The running mode is shown by `cat /proc/lan_sds/lan_sds_cfg`. It's applied early
in boot by `/etc/runlansds.sh`, so a change needs a reboot.

A mode that doesn't link cuts off access to the stick. [stick/rc.local](stick/rc.local)
has a one-shot safety for trying a mode:

```sh
flash set LAN_SDS_MODE 1
mib commit
echo 1 > /var/config/sds_confirm
```

On the next boot the new mode is live, but `rc.local` saves `3` again and
removes the flag. If the new mode works, save it again without the flag; if
not, one more power cycle in a media converter brings mode 3 back.

## 6. Router

Run whatever WAN service your ISP uses (PPPoE, DHCP or static; the examples use
PPPoE) on the interface facing the stick, tagged or untagged depending on the
stick's VLAN mode. Add an address in the stick's management subnet to reach its
web UI and SSH. See [docs/mikrotik.md](docs/mikrotik.md), including the hEX S
`sfp1` boot quirk.

## 7. Verify

```sh
diag gpon get onu-state                 # O5
ps | grep rc.local                      # boot script running
diag gpon show counter flow 0           # U/S and D/S GEM counters increasing
```

## Disclaimer

Only use an identity that belongs to your own service, keep the original
firmware bank until the new one is proven, and keep backups of every partition
you overwrite. No firmware images are included here.

## License

MIT, see [LICENSE](LICENSE).
