# OpenWrt ARM64 installer

The MicroScale installer uses a checksum-pinned bootstrap, a separate POSIX shell lifecycle manager, and a short CLI command.

## Quick Start

Run as root over local LAN SSH:

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.2/install.sh && sh /tmp/microscale-install.sh
```

The bootstrap downloads the release's `manager.sh`, checks the SHA256 digest pinned in `install.sh`, then runs the verified local copy. **Choose Install to RAM first**. Pick the profile and confirm staging. Restart the same installer to apply the verified RAM stage to NAND.

## Two-step RAM → NAND workflow

```sh
# 1. Run installer and choose "Install to RAM" + Small/Micro/Extreme.
sh /tmp/microscale-install.sh

# 2. Try the binary in RAM without using the system daemon.
/tmp/microscale-stage/bin/tailscale version
/tmp/microscale-stage/bin/tailscaled --version

# 3. Run the installer again; choose "Apply RAM to NAND".
sh /tmp/microscale-install.sh
```

The installer shows **Apply RAM to NAND** only when the stage has a matching release, architecture and SHA256 digest. Apply copies the staged binary (it does not redownload it), performs the original-binary backup and NAND free-space checks, then updates the executable paths. It does not start Tailscale. The RAM stage survives installer exits, but is erased on reboot or by `clear-ram`.

RAM layout:

```text
/tmp/microscale-stage/
  microscale             (combined binary)
  manager.sh             (verified lifecycle manager copy)
  manifest               (profile, arch, release, SHA256)
  bin/tailscale          → ../microscale
  bin/tailscaled         → ../microscale
  bin/microscale         → ../manager.sh
```

**No files under `/usr` or `/etc` are changed in RAM mode.** Running Tailscale processes and configuration remain untouched.

## RAM test and logging

`microscale test-ram all` runs the same smoke tests on real ARM64 OpenWrt devices and Linux x86_64 VMs. `microscale test-ram staged` tests exactly the current RAM-stage binary, with SHA256 verification. `microscale report` displays sanitized results from tmpfs; the latest run is `latest.tsv`. See [how to collect and submit results](DEVICE-REPORTS.md).

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
microscale install-ram micro
microscale ram-status
microscale apply          # Only with verified pending RAM stage
microscale clear-ram
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

In NAND mode, the manager only changes Tailscale executable paths and MicroScale's own program/metadata. It never runs `tailscale up`, changes network configuration, touches Tailnet secrets, starts/restarts a service, or enables boot startup. Existing daemon processes retain their old binary until users restart them separately.

A backup is kept persistently in `/etc/microscale/original`; because the device may have limited NAND, the installer refuses writes when it cannot reserve sufficient space. `uninstall` restores original binaries and retains manager/backup records for safe reinstallation.

## Migrating from RC5

RC5 stored the manager and backups at `/var/lib/microscale`. On OpenWrt this may be volatile, so **do not reboot or delete that directory before inspecting it** if you previously used RC5 for a persistent installation. RC6 refuses to install over a detected RC5 install-state without migration. Make a backup of original files and confirm the existing state first. The change of paths is not an automatic data migration.

For quick CLI measurement rather than a staged install, use the separate [RAM-only smoke tests](RAM-TEST.md). Real NR3053 Exit Node/subnet routing and RC6 installer transactions have not yet been device-validated.

## External-backup NR3053 adoption (v0.2.2)

The generic `microscale install`/`apply` transaction insists on a full on-device
rollback backup. With the original CLI and daemon totaling nearly 40 MiB, this
exceeds NR3053's free overlay. **Do not bypass `check_space`** to run a generic
install. For an existing installation already manually replaced after checksummed
backups on an Arch host, the maintainer can install the manager, write
`/etc/microscale/install-state` and the `/etc/microscale/external-backup` marker,
and use `microscale status`/`doctor` for observation.

When that marker exists, `microscale uninstall` intentionally refuses to delete
or restore anything because no local original binary exists. Restore is performed
by SSH from the Arch host, using the independently SHA-256-verified original
binaries and restarting only the existing `tailscale` service. Keep LAN SSH
independent of Tailnet availability. Do not delete the Arch backup while the
external marker is installed. This is an exceptional, manually reviewed device
workflow, **not** the generic one-click installer.
