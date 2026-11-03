# MicroScale

[![License](https://img.shields.io/github/license/nghianguyen150612/MicroScale)](LICENSE)
[![Release](https://img.shields.io/github/v/release/nghianguyen150612/MicroScale?include_prereleases)](https://github.com/nghianguyen150612/MicroScale/releases)
[![Build](https://github.com/nghianguyen150612/MicroScale/actions/workflows/build.yml/badge.svg)](https://github.com/nghianguyen150612/MicroScale/actions/workflows/build.yml)

**Tailscale, built smaller.** Three reproducible build profiles for compact OpenWrt/Linux devices, without forking upstream Tailscale.

**English** | [Tiếng Việt](README.vi.md)

> Upstream: [Tailscale](https://github.com/tailscale/tailscale). This is an independent build/packaging project, not an official Tailscale distribution.

## Why MicroScale?

Embedded devices often have limited flash and RAM. MicroScale packages a combined Tailscale CLI/daemon at three optimization levels and provides checksum-verified downloads, non-destructive RAM tests, and optional binary-only installation.

## Features

- **Small / Micro / Extreme** — choose full features, reduced features, or reduced features packed with UPX.
- **ARM64 + x86_64** — two Linux architectures in each release.
- **One-command installer** — profile selection and a persistent `microscale` management command.
- **Safe bootstrap** — download, verify a pinned SHA256 digest, then execute `manager.sh`.
- **Lifecycle commands** — install, update, repair, status, diagnostics, doctor, version, uninstall.
- **RAM-only testing** — measure CLI size and one-shot RSS without installing or restarting Tailscale.
- **Binary-only scope** — never automatically configure a Tailnet, DNS, firewall, routes or services.

## Quick Start

> Requires root, a supported **ARM64 OpenWrt** system, working HTTPS download tools, writable overlay space and direct LAN SSH. Review the [compatibility notes](#compatibility) first.

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.6/install.sh && sh /tmp/microscale-install.sh
```

Choose **Install/Update** and your preferred profile. After installation, the `microscale` command is available in your shell.

```sh
microscale
microscale help
microscale version
microscale status
microscale doctor
```

No Tailscale service is started or restarted, and your existing authentication/state are left untouched.

## Installer architecture

```text
install.sh (release-pinned bootstrap)
   │ download → SHA256 verify → execute
   ▼
manager.sh (POSIX shell)
   ├── /usr/lib/microscale/manager.sh
   ├── /usr/bin/microscale → /usr/lib/microscale/manager.sh
   ├── /etc/microscale/ (installer state + original binary backup)
   ├── /usr/sbin/tailscaled
   └── /usr/bin/tailscale → /usr/sbin/tailscaled
```

`/etc/microscale` is used for persistent OpenWrt state. The manager stays in `/usr/lib`, and the short command is a symlink in `/usr/bin`. Tailscale's own configuration files are not modified.

## CLI administration

```sh
microscale install micro
microscale update micro
microscale repair
microscale status
microscale diagnostics
microscale doctor
microscale version
microscale uninstall
```

Operations that write files require root and interactive confirmation. Uninstall restores original Tailscale binaries; it does not erase Tailscale configuration. See [installer details](docs/ONE-CLICK-INSTALL.md).

## Build profiles

| Profile | Optimization | ARM64 executable* |
| --- | --- | ---: |
| **Small** | Full upstream feature set, stripped combined binary | 40.00 MiB |
| **Micro** | Upstream reduced-feature build | 12.75 MiB |
| **Extreme** | Micro + UPX packing | 3.43 MiB |

*Measured with pinned Tailscale v1.104.5. ELF size is not the same as NAND usage on compressed filesystems.*

## Compatibility and validation

| Platform | Status |
| --- | --- |
| OpenWrt ARM64 (NR3053) | **6/6 RAM-only CLI smoke tests PASS** |
| OpenWrt ARM64 — full VPN service / Exit Node | **Not yet validated** |
| Linux x86_64 | Build and CI smoke tests PASS; 500 MiB VM test pending |
| Other architectures | Not currently packaged |

[Physical NR3053 results](reports/openwrt-arm64-2026-11-03-rc4.md) show Micro had the lowest measured one-shot CLI RSS. These results do not establish daemon uptime, Exit Node support or subnet routing.

## Test without installing

Download and checksum-verify [`ram-test.sh`](docs/RAM-TEST.md) from the release, then run it in RAM. No system executables or services are changed.

## Build from source

```sh
TARGET_GOARCH=arm64 bash scripts/build.sh micro
TARGET_GOARCH=amd64 bash scripts/build.sh micro
```

## License

MicroScale maintains its own packaging code; upstream Tailscale licenses and notices remain applicable to distributed Tailscale binaries. See [third-party notices](THIRD_PARTY_NOTICES.md).
