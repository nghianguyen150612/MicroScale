# MicroScale

Compact Tailscale binaries built from pinned [Tailscale](https://github.com/tailscale/tailscale) source.

| Profile | Feature set | ARM64 executable |
| --- | --- | ---: |
| Small | Full | 40.00 MiB |
| Micro | Reduced | 12.75 MiB |
| Extreme | Reduced + UPX | 3.43 MiB |

Sizes reflect Tailscale v1.104.5 CI builds, not NAND usage. Packages are available for Linux ARM64 and AMD64.

## Install on OpenWrt ARM64

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.5/install.sh && sh /tmp/microscale-install.sh
```

The interactive installer follows a checksum-pinned bootstrap/manager layout, like Beszel-iOS. Available operations are **install, update, repair, status, doctor, diagnostics and uninstall**. It only manages Tailscale executable files, its own manager metadata, and original binary backups. It does **not** start or restart Tailscale, configure Exit Node, DNS, firewall, routes, or modify authentication/state. The user controls all VPN operations.

After installation, use `sh /var/lib/microscale/manager.sh status` or `doctor`. See [installation details](docs/ONE-CLICK-INSTALL.md).

## RAM-only test (no installation)

```sh
wget -O /tmp/ram-test.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.5/ram-test.sh
wget -O /tmp/ram-test.sh.sha256 https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.5/ram-test.sh.sha256
cd /tmp && sha256sum -c ram-test.sh.sha256 && sh ram-test.sh all
```

See [RAM tests](docs/RAM-TEST.md) and [real NR3053 measurements](reports/openwrt-arm64-2026-11-03-rc4.md). Micro/Extreme are not yet qualified for Exit Node or subnet routing.

## Build

```sh
TARGET_GOARCH=arm64 bash scripts/build.sh micro
TARGET_GOARCH=amd64 bash scripts/build.sh micro
```

MicroScale is independent of Tailscale. Upstream [BSD-3-Clause notices](THIRD_PARTY_NOTICES.md) are included in release packages.
