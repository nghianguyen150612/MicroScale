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
- **Install to RAM first** — stage a checksummed executable under `/tmp/microscale-stage` without changing system binaries; rerun installer to apply the same verified profile to NAND.
- **RAM-only testing** — use the same `test-ram` command on physical OpenWrt and Linux VMs, including verified staged binaries, with sanitized per-run TSV logs.
- **Repository evidence** — collect physical-device logs by SSH from Arch and open a reviewed GitHub PR without giving the router a token.
- **Binary-only scope** — never automatically configure a Tailnet, DNS, firewall, routes or services.

## Quick Start

> Requires root, a supported **ARM64 OpenWrt** system, working HTTPS download tools, writable overlay space and direct LAN SSH. Review the [compatibility notes](#compatibility) first.

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.2/install.sh && sh /tmp/microscale-install.sh
```

Choose **Install to RAM** and a Small/Micro/Extreme profile. Test the staged binary:

```sh
/tmp/microscale-stage/bin/tailscale version
/tmp/microscale-stage/bin/tailscaled --version
```

Run the same installer command again. When the stage checksum is valid, the menu gains **Apply RAM to NAND**. Only this action (or direct NAND install) changes system binaries. Nothing starts or restarts the Tailscale service.

After applying to NAND, the persistent `microscale` command is available in your shell.

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
microscale install-ram micro
microscale ram-status
microscale test-ram staged
microscale test-ram all
microscale report
microscale apply   # Commit verified staged RAM binary to NAND
microscale clear-ram
microscale install micro
microscale update micro
microscale repair
microscale status
microscale diagnostics
microscale doctor
microscale version
microscale uninstall
```

RAM staging writes only under `/tmp` (tmpfs) and disappears after reboot. NAND operations require root and interactive confirmation. Uninstall restores original Tailscale binaries; it does not erase Tailscale configuration. See [installer details](docs/ONE-CLICK-INSTALL.md).

## Build profiles

| Profile | Optimization | ARM64 executable* |
| --- | --- | ---: |
| **Small** | Full upstream feature set, stripped combined binary | 40.00 MiB |
| **Micro** | Upstream reduced-feature, NR3053-compatible | 19.50 MiB |
| **Extreme** | Micro + UPX packing | 5.06 MiB |

*Measured with pinned Tailscale v1.104.5. ELF size is not the same as NAND usage on compressed filesystems.*

## Compatibility and validation

| Platform | Status |
| --- | --- |
| OpenWrt ARM64 (NR3053) | **Micro v0.2.2 userspace daemon, SOCKS5, SSH preference and 5 Serve endpoints verified after service restart** |
| OpenWrt ARM64 — Exit Node / 24-hour uptime / reboot | **Not validated** (Exit Node intentionally off) |
| Linux x86_64 | Build and CI smoke tests PASS; 500 MiB VM test pending |
| Other architectures | Not currently packaged |

[Physical NR3053 results](reports/openwrt-arm64-2026-11-03-rc4.md) show Micro had the lowest measured one-shot CLI RSS. These results do not establish daemon uptime, Exit Node support or subnet routing.

**NR3053 deployment note (v0.2.2):** The original reduced build omits
`netstack` and `outboundproxy`. This prevents OpenWrt's userspace-only
Tailscale service from starting and removes its localhost SOCKS5 listener.
The NR3053 also uses Tailscale Serve and SSH. The `micro` and
`extreme` build profiles now retain those features via upstream's feature-tag
mechanism. The old v0.2.1 binaries remain incompatible and have not been overwritten.
Micro v0.2.2 was tested on NR3053 after restart with working SSH/LAN, Tailscale
VPN, SOCKS5, and all five Serve endpoints; long-term uptime and reboot are not
claimed. Preserve an external original-binary backup
when the overlay cannot hold an on-device rollback copy.


## Test without installing

Use the installer **Install to RAM** option for a staged executable that can later be applied to NAND, or download [`ram-test.sh`](docs/RAM-TEST.md) for automatic smoke measurements. Neither changes system executables or services.

## Community-tested hardware

**Anyone can contribute test results—even without push access.** Run the RAM test on your device and let the contributor script create a fork and pull request automatically.

```bash
gh auth login
gh auth setup-git
git clone https://github.com/nghianguyen150612/MicroScale.git
cd MicroScale
bash scripts/collect-device-report.sh --submit --device "Optional device model" root@ROUTER_IP all
```

Already have a `latest.tsv`? Use `bash scripts/import-report.sh --submit /path/to/latest.tsv`. Credentials stay on the contributor's computer. Results are reviewed and stored under [community hardware reports](reports/community/README.md). **These are user-reported CLI smoke tests, not certified VPN compatibility.** See [CONTRIBUTING.md](CONTRIBUTING.md).

## Build from source

```sh
TARGET_GOARCH=arm64 bash scripts/build.sh micro
TARGET_GOARCH=amd64 bash scripts/build.sh micro
```

## License

MicroScale maintains its own packaging code; upstream Tailscale licenses and notices remain applicable to distributed Tailscale binaries. See [third-party notices](THIRD_PARTY_NOTICES.md).
