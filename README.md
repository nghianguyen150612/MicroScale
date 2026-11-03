# MicroScale

Compact Tailscale builds for embedded Linux, using pinned [Tailscale](https://github.com/tailscale/tailscale) source.

## Profiles

| Profile | Build | ARM64 binary |
| --- | --- | ---: |
| **Small** | Full features, stripped, combined CLI/daemon | 40.00 MiB |
| **Micro** | Reduced features | 12.75 MiB |
| **Extreme** | Micro + UPX | 3.43 MiB |

Builds target **Linux ARM64 and x86_64 (AMD64)**. ARM64 sizes above are from Tailscale v1.104.5 CI; storage savings depend on filesystem compression.

## RAM-only test

Download `ram-test.sh` and its checksum from [v0.2.0-rc.4](https://github.com/nghianguyen150612/MicroScale/releases/tag/v0.2.0-rc.4). Save them in `/tmp` on OpenWrt or `/dev/shm` on Arch, verify SHA256, then run:

```sh
sh ram-test.sh all
```

The script detects ARM64/x86_64, downloads and executes the three profiles **entirely in tmpfs**, and saves a sanitized `results.tsv` there. It neither installs system binaries nor changes running services, VPN state or network settings. These smoke tests **do not validate VPN routing**. See [RAM testing and report submission](docs/RAM-TEST.md).

## Persistent installation (optional)

The separate [installer](docs/ONE-CLICK-INSTALL.md) writes binary files to the OpenWrt overlay. **Do not use it for RAM-only testing.**

## Build

```sh
TARGET_GOARCH=amd64 bash scripts/build.sh small
TARGET_GOARCH=amd64 bash scripts/build.sh micro
TARGET_GOARCH=amd64 bash scripts/build.sh extreme
```

Change `TARGET_GOARCH` to `arm64` for ARM64 builds. Extreme requires UPX.

MicroScale is independent of Tailscale; binaries retain the upstream [BSD-3-Clause license](THIRD_PARTY_NOTICES.md).
