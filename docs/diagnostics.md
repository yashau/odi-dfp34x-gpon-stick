# Diagnostics

Commands that are useful on the DFP-34X (RTL9602C). `diag` is the Realtek SDK
shell; given a full command line it runs once and exits. `diag <module> get ?`
lists subcommands. Avoid bare `diag`, `europacli` and `ShowStatus`, which are
interactive or loop forever and will hold the single SSH session.

## GPON state

```sh
diag gpon get onu-state          # O1..O7, O5 = operation
diag gpon get serial-number      # the serial actually sent to the OLT
diag gpon get password           # PLOAM password
diag gpon get alarm-status       # LOS, LOF, SF, SD ...
diag gpon get tx                 # laser mode, forced idle
diag gpon show us-flow           # upstream flows: flow ID -> GEM port -> T-CONT
diag gpon show ds-flow
diag gpon get tcont alloc-id <id>
```

## Counters

Per-flow GPON counters are cleared when read:

```sh
diag gpon show counter flow 0        # U/S Eth in vs GEM out, D/S GEM in
diag gpon show counter flow 64       # OMCI flow, useful as a known-good reference
diag gpon show counter tcont 0       # idle bytes = grants used with nothing to send
diag gpon show counter global us-gem
```

Switch port counters (not cleared on read): port 0 = LAN, 2 = PON, 3 = CPU.

```sh
diag mib dump counter port 0 | grep -E "InBroadcast|InUcast|InDiscards"
diag mib dump counter port 2
```

`dot1dTpPortInDiscards` rising together with `ifInBroadcastPkts` on port 0
means broadcasts are dropped on entry (see storm control below).

## OMCI

```sh
omcicli get sn
omcicli get authuptime               # time since the PON came up
omcicli mib get <ME name>            # e.g. Tcont, GemPortCtp, VlanTagFilterData, ExtVlanTagOperCfgData
omcicli dump conn                    # data path built from provisioning
omcicli dump srvflow
omcicli dump qmap                    # priority queues -> T-CONTs
```

### OMCI message log

Records every message the OLT sends and the stick's replies. Provisioning
happens right after activation, so enable it persistently and reboot:

```sh
flash set OMCI_LOGFILE 3         # 1 = raw, 2 = parsed, 3 = both
flash set OMCI_LOGFILE_MASK 0    # all message types
mib commit                       # wait a few seconds
reboot
# after provisioning:
cat /var/tmp/omcilog.par
```

Set `OMCI_LOGFILE 0` again when done.

## Hardware rules

```sh
diag classf get entry valid          # classifier rules (CF) programmed by OMCI
diag classf get upstream-unmatch-act
diag acl get entry valid
diag storm-control get broadcast port all      # also multicast, unknown-unicast
diag meter get entry <n>
diag vlan get state
diag vlan get vlan-table vid <vid>
diag stp get stp-table instance 0 port all
diag pon get t-cont 0 queue-id 0
```

Some `/proc/omci/*` entries print to the kernel log instead of stdout. There's
no `dmesg`, but nothing else reads the log buffer, so `/proc/kmsg` has it:

```sh
cat /proc/kmsg > /var/tmp/k.txt & P=$!; sleep 1; cat /proc/omci/l2 >/dev/null; sleep 2; kill $P; cat /var/tmp/k.txt
```

That also gives you the boot log the first time it's read after boot.

## Run omci_app by hand

If `omci_app` isn't running (and the GPON device never activates), rebuild its
command line from `/etc/runomci.sh` and run it in the foreground to see why:

```sh
sed -e "s/^omci_app /echo omci_app /" -e "s#/etc/runigmp.sh#:#" /etc/runomci.sh > /var/tmp/o.sh
CMD=$(sh /var/tmp/o.sh | grep "^omci_app" | sed "s/ &$//"); echo "$CMD"
$CMD > /var/tmp/omci_start.log 2>&1 & sleep 6; cat /var/tmp/omci_start.log
```

## Config files

| File | Contents |
|------|----------|
| `/var/config/lastgood.xml` | current settings (CS) |
| `/var/config/lastgood_hs.xml` | hardware settings (HS): serial, MAC, `LAN_SDS_MODE` ... |
| `/var/config/lastgood_mp_hs2.xml` | factory HS |
| `/etc/config_default.xml` | shipped defaults |

`flash get <KEY>` / `mib get <KEY>` read either.
