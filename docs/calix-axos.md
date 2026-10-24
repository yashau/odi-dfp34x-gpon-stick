# Calix AXOS OLT

Notes for replacing a Calix ONT (tested with a GigaHub 812Gv2) on a network
with a Calix AXOS OLT. The OLT identifies itself in the OMCI log as
`OltVendorId=CALX` (`0x43414c58`), `EquipId=AXOS`.

Two things need handling on top of the generic guide: a 0 kbps storm-control
limit derived from the OLT's rate limiter, and a VLAN translation rule the stick
doesn't apply. The PON-side VLAN in the examples is 66, the subscriber VLAN 10.

## Identity

Calix ONTs use the vendor ID `CXNK`. The FSAN on the label is the GPON serial.

```sh
flash set GPON_SN CXNKxxxxxxxx
flash set PON_VENDOR_ID CXNK
flash set HW_SERIAL_NO 43584E4Bxxxxxxxx   # "CXNK" in hex + the same 8 hex digits
flash set GPON_PLOAM_PASSWD 00000000000000000000
mib commit
```

An all-zero PLOAM password was accepted. Calix's OUI is `F8:85:F9` if you want
to set `OUI` for consistency; leave `ELAN_MAC_ADDR` / `MAC_KEY` alone (see the
main guide).

The OLT also creates a proprietary ME (class 65313) that this firmware doesn't
know. `OMCI_FAKE_OK=1` makes the stick acknowledge it; that was left enabled.

## Storm control

The OLT provisions a `Dot1RateLimiter` for the LAN port:

```
TrafficDescriptor Create(0x3011, PIR=0x00000bb8)   # unknown unicast flood
TrafficDescriptor Create(0x3012, PIR=0x00000bb8)   # broadcast
TrafficDescriptor Create(0x3013, PIR=0x00000bb8)   # multicast
Dot1RateLimiter   Create(0x3010, ParentMePtr=0x0001, TpType=0x01,
                         UsUcFloodRatePtr=0x3011, UsBcRatePtr=0x3012,
                         UsMcPayloadRatePtr=0x3013)
```

This firmware turns it into switch storm control on port 0 (the LAN port) with
**0 kbps** meters:

```
# diag storm-control get broadcast port all
Port State   Meter
0    Enable  1
2    Disable 0
# diag meter get entry 1
Meter idx = 1 , meter rate = 0     Kbps, include IFG = Disable , burst size = 0
```

`multicast` (meter 2) and `unknown-unicast` (meter 0) are set the same way.
Every broadcast from the router is dropped at the LAN port. WAN setup starts
with a broadcast (PPPoE PADI, DHCP DISCOVER), so the connection never comes up,
while unicast to the stick's own IP keeps working. In the counters, `dot1dTpPortInDiscards` on port 0 rises one
for one with `ifInBroadcastPkts` (`diag mib dump counter port 0`).

Turning them off restores traffic immediately:

```sh
diag storm-control set broadcast port 0 state disable
diag storm-control set multicast port 0 state disable
diag storm-control set unknown-unicast port 0 state disable
```

The OLT re-applies the rate limiter on every boot and can re-provision at any
time, so this needs the boot hook from the main guide and a script that keeps
checking: [examples/calix-axos-rc.local](../examples/calix-axos-rc.local)
checks every 10 seconds.

```sh
tools/stick-ssh.sh 'cat > /var/config/rc.local; chmod 755 /var/config/rc.local' < examples/calix-axos-rc.local
```

## VLAN translation

**Method:** stick VLAN Settings → Manual → **PVID 66** (the PON-side VLAN), and
the router sends **untagged**. Details below.

With the Calix ONT, the router sends its WAN traffic (PPPoE in this example)
tagged with the subscriber VLAN (10).
The OLT tells the ONT to translate it to the PON-side VLAN (66).

From the OMCI log:

```
MacBriPortCfgData     Create(0x0101, TPType=0x01 (PPTP UNI), TPPointer=0x0101)
MacBriPortCfgData     Create(0x2401, TPType=0x03 (802.1p mapper), TPPointer=0x2401)
VlanTagFilterData     Create(0x2401, FilterTbl=0x0042..., FwdOp=0x10, NumOfEntries=1)
ExtVlanTagOperCfgData Create(0x0101, AssociationType=0x02 (PPTP UNI), AssociatedMePoint=0x0101)
ExtVlanTagOperCfgData Set(0x0101, InputTPID=0x8100, OutputTPID=0x8100, DsMode=0x00)
ExtVlanTagOperCfgData Set(0x0101, ReceivedFrameVlanTaggingOperTable=0xf800000080050000400f800600080216)
```

`VlanTagFilterData` (ME 84) holds the PON-side VID: `0x0042` = 66. The extended
VLAN entry (ME 171) is four 32-bit words:

| Word | Hex | Fields | Meaning |
|------|-----|--------|---------|
| 1 | `f8000000` | filter outer prio 15, outer VID 4096 | no outer tag |
| 2 | `80050000` | filter inner prio 8, inner VID 10 | single-tagged VID 10, any priority |
| 3 | `400f8006` | remove 1 tag, treatment outer prio 15 | strip the tag, no outer tag added |
| 4 | `00080216` | treatment inner prio 8, VID 66, TPID 6 | add VID 66, copy priority |

```python
w = bytes.fromhex("f800000080050000400f800600080216")
w1, w2, w3, w4 = (int.from_bytes(w[i:i+4], "big") for i in range(0, 16, 4))
print("filter inner VID", (w2 >> 15) & 0x1FFF)    # 10
print("tags to remove", (w3 >> 30) & 0x3)          # 1
print("treatment inner VID", (w4 >> 3) & 0x1FFF)  # 66
```

The stick stores the rule (`omcicli mib get ExtVlanTagOperCfgData`) but the data
path doesn't use it, whatever `VLAN_CFG_TYPE`, `OMCI_OLT_MODE` or `OMCI_TM_OPT`
is set to:

```
# omcicli dump conn
UNI ExtVlan Ptr: 0x00
filter C-TAG Mode: FILTER VID
(PRI,TPID,VID): (0,...,66)
```

So set the PON-side VLAN on the stick and send untagged from the router:

```sh
flash set VLAN_CFG_TYPE 1
flash set VLAN_MANU_MODE 1
flash set VLAN_MANU_TAG_VID 66
mib commit
reboot
```

`omcicli dump conn` then shows `filter C-TAG Mode: NO TAG` with VID 66 added
upstream. On the router, run the WAN client (PPPoE, DHCP, ...) directly on the
interface facing the stick, with no VLAN interface.

## Timing

After a stick power cycle, the WAN connection comes back in about 3 minutes:
boot, ranging, OMCI provisioning, then the watchdog's next pass. A warm reboot
of a MikroTik doesn't power-cycle its SFP cage, so the connection returns as
soon as the router is up.
