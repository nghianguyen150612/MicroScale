# Installation

Supports OpenWrt ARM64 with writable `/overlay`. Run as root using a direct LAN connection.

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.3/install.sh && sh /tmp/microscale-install.sh
```

The menu offers **Small** (full features), **Micro** (reduced features), and **Extreme** (reduced + UPX). The script verifies SHA256 checksums and binary execution, then updates only:

- `/usr/sbin/tailscaled`
- `/usr/bin/tailscale` (symlink)

It does **not** start or restart the daemon, run `tailscale up`, or edit DNS, routes, firewall, authentication, or init scripts. A currently running daemon continues using its previous binary until you restart it.

Existing binaries are backed up to `/tmp/microscale-backup.*`; these backups disappear on reboot. Keep another copy if you need persistent rollback, and install through local SSH rather than your only Tailscale connection.

**Micro and Extreme are experimental.** Successful CLI tests do not confirm login, Exit Node, subnet routing, or reconnect. The ARM64 build has not been fully qualified on NR3053.
