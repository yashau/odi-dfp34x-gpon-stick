# AGENTS.md

Guidance for AI agents working on this repo or on an ODI DFP-34X stick.

## Repo conventions

- Docs are a guide, not a log: describe what to configure and why, not the
  history of how it was found.
- Generic content goes in `README.md` and `docs/*.md`; anything specific to an
  OLT or ISP setup goes in its own doc (`docs/calix-axos.md`,
  `docs/huawei.md`) and `examples/`.
- Never commit real identities or credentials: GPON serials, PLOAM passwords,
  MACs, `MAC_KEY`s, WAN logins, public IPs, router names, ISP or location
  names. Use placeholders such as `CXNKxxxxxxxx`, `<user>`, `10.0.2.1`.
- Never commit firmware images or partition dumps.
- Everything that runs on the stick or in containers must keep LF line endings
  (`.gitattributes` enforces it). Check scripts with `sh -n`.
- `stick/rc.local` stays generic; network-specific loops go in
  `examples/<network>-rc.local`.

## Talking to the stick

- Use `tools/stick-ssh.sh`. The dropbear server needs legacy KEX, host key and
  cipher options; Paramiko can't negotiate them. Supply the password through
  `SSH_ASKPASS` with `SSH_ASKPASS_REQUIRE=force` for unattended runs.
- **Only one SSH session at a time.** A second connection is reset during key
  exchange. A command that hangs holds the slot: always wrap calls in
  `timeout`, and kill only your own stale `ssh` process, never every `ssh`.
- Don't run interactive or looping programs: bare `diag`, `europacli`,
  `ShowStatus`. Always give `diag` a full command line.
- BusyBox 1.12 lacks `head`, `tail`, `sort`, `od`, `touch`, `dmesg`, `wc`;
  filter on the PC side. Create files with `echo x > file`.
- Background processes started over SSH die when the session closes; detach
  with `(cmd </dev/null >/dev/null 2>&1 &)`.
- `/proc/omci/*` and boot messages go to the kernel log; read `/proc/kmsg`
  briefly in the background (see `docs/diagnostics.md`).
- GPON per-flow counters are clear-on-read; switch port counters are not.

## Changing settings

- `flash set` / `mib set`, then `mib commit`. The commit is asynchronous: wait a
  few seconds and confirm in `/var/config/lastgood*.xml` before rebooting, or
  the change is lost.
- Most settings (VLAN mode, OLT mode, `LAN_SDS_MODE`, identity) are read at
  boot and need a reboot. `omcicli set ...` changes only the running OMCI stack.

## Lockout traps

Each of these cuts off management access until a power cycle or worse:

- `diag vlan set state enable` while port 0's PVID is 0.
- A `LAN_SDS_MODE` the host can't link with. Use the `sds_confirm` one-shot in
  `stick/rc.local` when trying modes.
- Changing `ELAN_MAC_ADDR` without a matching `MAC_KEY` (stops `omci_app`, so
  the stick never activates on the PON).

Ask the user before any of these, before rebooting a router, and before
anything that drops their internet connection.

## Flashing

- Never write the running bank. `/proc/cmdline`: `root=31:5` = bank 0,
  `root=31:7` = bank 1.
- Back up both kernel and rootfs of the target bank first.
- Write kernel and rootfs together; the banks can hold different versions.
- Verify every write against the padded MD5 (`tools/padded-md5.py`).
- Boot the new bank with `sw_tryactive` first; set `sw_commit` only after it's
  confirmed working. `tools/flash-inactive-bank.sh` does all of this.
- The stick has ~2 MB of free RAM: delete uploaded images as soon as they're
  written.

## Timing

After the stick powers up, allow about 3 minutes before the WAN connection is
expected to work (boot, ranging, OMCI provisioning, `rc.local` loop). Don't
conclude it has failed sooner.

PPPoE in the docs is an example; don't assume it's the WAN service in use.
