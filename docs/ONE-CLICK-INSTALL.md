# OpenWrt ARM64 installer

The MicroScale installer uses a checksum-pinned bootstrap, a separate POSIX shell lifecycle manager, and a short CLI command.

## Quick Start

Run as root over local LAN SSH:

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.6/install.sh && sh /tmp/microscale-install.sh
```

The bootstrap downloads the release's `manager.sh`, checks the SHA256 digest pinned in `install.sh`, then runs the verified local copy. Choose the profile and confirm installation.

## Installed paths

| Path | Purpose |
| --- | --- |
| `/usr/lib/microscale/manager.sh` | Persistent lifecycle manager |
| `/usr/bin/microscale` | Symlink to the manager |
| `/etc/microscale/install-state` | Installed version/profile |
| `/etc/microscale/original/` | Persistent backup of original binary files |
| `/usr/sbin/tailscaled` | Tailscale combined executable |
| `/usr/bin/tailscale` | Symlink to the combined executable |

`/etc` is persistent under a writable OpenWrt overlay, while `/var` may point to RAM. MicroScale does **not** use `/var/lib` for new installs.

## Commands

```sh
microscale                # Interactive menu
microscale version
microscale help
microscale status
microscale doctor
microscale diagnostics
microscale install micro
microscale update micro
microscale repair
microscale uninstall      # Restore original binaries
```

The manager only changes Tailscale executable paths and MicroScale's own program/metadata. It never runs `tailscale up`, changes network configuration, touches Tailnet secrets, starts/restarts a service, or enables boot startup. Existing daemon processes retain their old binary until users restart them separately.

A backup is kept persistently in `/etc/microscale/original`; because the device may have limited NAND, the installer refuses writes when it cannot reserve sufficient space. `uninstall` restores original binaries and retains manager/backup records for safe reinstallation.

## Migrating from RC5

RC5 stored the manager and backups at `/var/lib/microscale`. On OpenWrt this may be volatile, so **do not reboot or delete that directory before inspecting it** if you previously used RC5 for a persistent installation. RC6 refuses to install over a detected RC5 install-state without migration. Make a backup of original files and confirm the existing state first. The change of paths is not an automatic data migration.

For non-destructive testing, use [RAM-only smoke tests](RAM-TEST.md). Real NR3053 Exit Node/subnet routing and RC6 installer transactions have not yet been device-validated.
