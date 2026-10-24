# MikroTik (RouterOS 7)

Tested on a hEX S (RB760iGS), RouterOS 7.25. Examples use `sfp1` for the stick,
`10.0.2.1` as the stick's management IP, and PPPoE as the example WAN service;
adjust to your setup.

## SFP port

The hEX S `sfp1` is a 1.25 Gbps cage, so the stick must be in a 1G mode
(`LAN_SDS_MODE=1`, see the main guide).

```
/interface ethernet set sfp1 auto-negotiation=no speed=1G-baseT-full
```

**Cold boot with the stick inserted.** If the hEX S boots with `sfp1` empty,
the port can stay at `no-link` afterwards whatever the settings. Power the
router off, insert the stick, power on. After that, warm reboots are fine, and a
warm `/system reboot` doesn't power-cycle the SFP, so the stick stays registered.

`/interface ethernet monitor sfp1 once` shows `sfp-module-present`,
`sfp-rx-loss` (fibre light) and `status`. Module present with no rx-loss but
`no-link` means the host interface isn't agreeing (mode or port settings).

## Stick management

Give the router an address in the stick's subnet on the same port, and
masquerade so other LAN hosts can reach the stick's web UI and SSH:

```
/ip address add address=10.0.2.2/24 interface=sfp1
/ip firewall nat add chain=srcnat action=masquerade dst-address=10.0.2.0/24 out-interface=sfp1 comment=stick-mgmt place-before=0
```

The stick has no default route, so without the NAT rule only the router itself
can reach it.

## WAN

Run the WAN service your ISP uses on the port facing the stick: directly on
`sfp1` when the stick tags (Manual/PVID mode, e.g. on a Calix AXOS OLT), or on a
VLAN interface when the stick is transparent (e.g. replacing a Huawei ONT).

Example with PPPoE, untagged:

```
/interface pppoe-client add name=pppoe-out1 interface=sfp1 user=<user> password=<password> add-default-route=yes disabled=no
```

Example with PPPoE, tagged:

```
/interface vlan add name=wan-vlan interface=sfp1 vlan-id=<service-vlan>
/interface pppoe-client add name=pppoe-out1 interface=wan-vlan user=<user> password=<password> add-default-route=yes disabled=no
```

For DHCP, use `/ip dhcp-client add interface=<sfp1 or wan-vlan>` instead.
Masquerade out of the WAN interface as usual.

## Using a media converter instead

With the stick in a media converter connected to an Ethernet port, the stick
needs `LAN_SDS_MODE=3` and the router port stays on auto-negotiation. Move the
management address, NAT rule and WAN client to that port.

## Upgrading RouterOS without internet

On a 16 MB device the root folder is a RAM disk, so a package uploaded there is
installed on the next reboot:

```
# on a PC with internet
curl -O https://download.mikrotik.com/routeros/<version>/routeros-<version>-mmips.npk
scp routeros-<version>-mmips.npk admin@<router>:/
# on the router
/system reboot
/system routerboard upgrade
/system reboot
```
