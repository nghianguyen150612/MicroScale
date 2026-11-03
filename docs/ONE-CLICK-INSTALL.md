# MicroScale one-command installer

Target: **OpenWrt with ARM64 userspace and a writable `/overlay`**. The supplied binary is Linux ARM64. This release is experimental until real-router functional qualification is complete.

## Install

Connect to the router using SSH over the local LAN (preferably with a recovery session available) and run as root:

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.2/install.sh && sh /tmp/microscale-install.sh
```

The script presents a numbered choice:

- **1 — Safe:** Combined CLI/daemon, full upstream feature set; larger executable.
- **2 — Small:** Upstream `--extra-small`, omits some features. Not functionally tested on NR3053.
- **3 — Extreme:** Small with UPX compression; highest risk and not functionally tested on NR3053.

The installer will ask again before writing anything. It first downloads the release archive and detached SHA256, validates the archive and contained executable, tries `tailscale version` and the daemon version, and checks NAND free space. It makes RAM-only copies of existing files before replacing two paths:

```
/usr/sbin/tailscaled    (single combined executable)
/usr/bin/tailscale      (symlink -> /usr/sbin/tailscaled)
```

**The script installs binaries only.** It does not call `tailscale up`, `tailscale login`, start/restart/enable/disable init scripts, configure Exit Node/Subnet Router, change UCI, set DNS, edit firewall or routes, change Tailscale state, or reboot the router. Installation of an updated on-disk executable does **not** update a daemon process already running; you must handle service restart manually.

## Recovery

The original binaries are temporarily retained under the `/tmp/microscale-backup.XXXXXX` directory printed by the script. **This backup disappears on reboot.** Copy these files to another machine before reboot if long-term rollback is needed. The script attempts rollback if its own file replacement fails, but power loss during NAND writes is not fully recoverable from an in-RAM backup.

For a manual binary-only restore while the RAM backup is present (example; replace the path with the one printed by the installer):

```sh
BACKUP=/tmp/microscale-backup.XXXXXX
# Only use a verified backup directory from this installer.
[ -f "$BACKUP/tailscaled" ] && cp -a "$BACKUP/tailscaled" /usr/sbin/tailscaled
[ -f "$BACKUP/tailscale" ] && cp -a "$BACKUP/tailscale" /usr/bin/tailscale
```

The example is for regular-file backups. An original CLI symlink requires symlink-aware restoration. Do not restore an executable by writing in place while it is being executed; use a temporary file and rename for production recovery.

## Limits

- Supports ARM64 only; unsupported CPUs are rejected without changes.
- Linux binaries are loaded directly from the release. The script does not install missing libraries or modules.
- A successful CLI version check is **not** evidence that Exit Node, login, subnet routing, MagicDNS, Tailscale SSH, or reconnect work.
- No new init service is created for a first-time installation. The user configures and operates Tailscale themselves.
- Never invoke the installer over the only active Tailscale SSH/VPN connection if loss of management access would be unrecoverable.
