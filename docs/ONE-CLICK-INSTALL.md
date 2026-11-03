# OpenWrt ARM64 lifecycle installer

The installer uses a small `install.sh` bootstrap that downloads `manager.sh` from the pinned MicroScale release, checks its SHA256 digest against a checksum embedded in the bootstrap, and executes the verified local file. The manager is POSIX `/bin/sh` and reads menu input from `/dev/tty`.

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.5/install.sh
sh /tmp/microscale-install.sh
```

Choose a lifecycle operation and optionally a profile: Small (full), Micro (reduced), Extreme (UPX-packed reduced). The manager supports `install`, `update`, `repair`, `status`, `doctor`, `diagnostics`, and `uninstall` (restore original binaries). To check an existing installation:

```sh
sh /var/lib/microscale/manager.sh status
sh /var/lib/microscale/manager.sh doctor
```

The manager only installs `/usr/sbin/tailscaled` and a `/usr/bin/tailscale` symlink, plus its own metadata and original binary backup in `/var/lib/microscale`. It verifies release archive SHA256, executable SHA256, architecture, and free overlay space. It attempts an in-session rollback if a file update fails. Insufficient NAND capacity causes a refusal, not an unsafe install.

**No service changes:** no `tailscale up`, daemon restart, systemd/init management, UCI, DNS, firewall, exit-node config, or authentication-state edits. An already-running Tailscale daemon continues using its old executable until you choose to restart it yourself. Uninstall restores binaries and preserves all Tailscale configuration/data.

Micro and Extreme are experimental on NR3053. Always retain direct LAN SSH access before persistent installation. For non-invasive experimentation, use [RAM-only testing](RAM-TEST.md) instead.
