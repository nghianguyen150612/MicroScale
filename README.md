# MicroScale

Compact Tailscale builds for OpenWrt ARM64, using pinned [Tailscale](https://github.com/tailscale/tailscale) source.

## Profiles

| Profile | Build | ARM64 binary |
| --- | --- | ---: |
| **Small** | Full features, combined CLI/daemon, stripped | 40.00 MiB |
| **Micro** | Reduced features (`--extra-small`) | 12.75 MiB |
| **Extreme** | Micro + UPX | 3.43 MiB |

Sizes are from Tailscale v1.104.5 CI builds, not NAND usage. Micro and Extreme have not been validated for VPN routing on NR3053.

## Install

Run as root on an ARM64 OpenWrt device with local SSH access:

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.3/install.sh && sh /tmp/microscale-install.sh
```

Choose **Small**, **Micro**, or **Extreme**. The installer verifies checksums and installs only `/usr/sbin/tailscaled` and `/usr/bin/tailscale`. It does not start services or configure the VPN. Backups are kept in `/tmp` until reboot. See [installation notes](docs/ONE-CLICK-INSTALL.md).

## Build

```sh
bash scripts/build.sh small
bash scripts/build.sh micro
bash scripts/build.sh extreme   # Requires UPX
```

Linux ARM64 is the default build target. Outputs are in `dist/<profile>/linux-arm64/`.

MicroScale is independent of Tailscale. Upstream code and binaries retain the [BSD-3-Clause license](THIRD_PARTY_NOTICES.md).
