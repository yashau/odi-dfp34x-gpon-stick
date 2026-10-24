# Huawei OLT

Configuration for replacing a Huawei ONT on a network with a Huawei OLT. Only
two things are needed: Huawei OLT mode, and the ONT's details on the Settings
page. No boot hook or watchdog. Example values are from an EchoLife
EG8245W5-6T.

## 1. OLT mode

Not in the web UI; set it over SSH:

```sh
flash set OMCI_OLT_MODE 1    # 1 = Huawei (0 = stock, 2 = ZTE, 3 = custom)
mib commit
```

`OMCI_FAKE_OK` isn't needed.

## 2. Settings page

Web UI → **Settings**, filled in from the Huawei ONT (label, or its web UI
*System Information*). The version and model strings below are the ones for an
EG8245W5-6T; serials are placeholders.

| Field | Value |
|-------|-------|
| GPON SN | `HWTCxxxxxxxx` |
| PLOAM password | the ONT's, or all zeros |
| Vendor ID | `HWTC` |
| Software version 1 / 2 | `V1R007C00S001` |
| OMCC version | `0x80` |
| Product class | `EG8245W5-6T` |
| HW version | `1C9D.A` |
| OUI | `00259e` |
| Device serial number | `48575443xxxxxxxx` (`HWTC` in hex + the same 8 hex digits) |

Leave **MAC** and **MACKEY** as shipped (see the main guide). Apply both
sections, then reboot.

## 3. VLAN

Leave VLAN Settings in **transparent** mode (Manual → Transparent), and tag the
service VLAN on the router: a VLAN interface on the port facing the stick, with
your WAN client (PPPoE, DHCP, ...) on top.

Example with service VLAN **100** on a MikroTik:

```
/interface vlan add name=wan-vlan interface=sfp1 vlan-id=100
/interface pppoe-client add name=pppoe-out1 interface=wan-vlan user=<user> password=<password> add-default-route=yes disabled=no
```

The stick passes the VLAN 100 tag through unchanged, so the router side is the
same as with the original ONT.

## SFP host interface

In a MikroTik hEX S `sfp1` cage: firmware default `LAN_SDS_MODE` (1000BASE-X),
`sfp1` set to `auto-negotiation=no speed=1G-baseT-full`. See [mikrotik.md](mikrotik.md).
