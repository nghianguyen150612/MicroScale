# MicroScale

**Tailscale, built smaller.** An independent, reproducible build/packaging system for OpenWrt and embedded Linux; **not** a Tailscale fork or an official Tailscale product.

## Three profiles

| Profile | Tailscale upstream mode | ARM64 ELF | Compressed release archive | Readiness |
| --- | --- | ---: | ---: | --- |
| Safe | combined CLI+daemon, stripped, full-feature | 40.00 MiB | 13.61 MiB | CLI smoke test only |
| Small | combined, `--extra-small` reduced features | 12.75 MiB | 4.93 MiB | Not NR3053-qualified |
| Extreme | Small plus UPX `--best --lzma` | 3.43 MiB | 3.43 MiB | Experimental, not NR3053-qualified |

Measurements: GitHub Actions [PR #3](https://github.com/nghianguyen150612/MicroScale/pull/3), Tailscale `v1.104.5` pinned at commit `73a48057aaf5f60e4f770b398e9b7af576b01dbe`. File size and .tar.gz size **are not equal to real NAND savings** on compressed UBIFS.

The reduced profiles intentionally omit userspace networking; the no-login userspace daemon benchmark cannot run, showing `NA` for daemon RSS. A real OpenWrt kernel-TUN test is mandatory before approving either profile. CI CLI smoke tests do not establish Exit Node, Subnet Router, login, MagicDNS or Tailscale SSH compatibility.

## Build on Linux

Use a Go toolchain compatible with upstream, Git, Bash, GNU binutils and UPX for the Extreme profile. Upstream's pinned toolchain is invoked via `TS_USE_TOOLCHAIN=1`.

```bash
git clone https://github.com/nghianguyen150612/MicroScale.git
cd MicroScale
bash tests/test_profiles.sh

TARGET_GOARCH=arm64 bash scripts/build.sh safe
TARGET_GOARCH=arm64 bash scripts/build.sh small
TARGET_GOARCH=arm64 bash scripts/build.sh extreme
```

Artifacts are written to `dist/<profile>/linux-arm64/`. Each includes a single combined executable named `microscale`, a license, build metadata, checksums and a separate tar.gz archive.

The combined upstream binary launches the CLI when invoked with basename `tailscale`, or with `TS_BE_CLI=1`. The daemon is invoked as `tailscaled` or `microscale`.

## Benchmarks

```bash
TARGET_GOARCH=amd64 bash scripts/build.sh safe
bash scripts/verify.sh dist/safe/linux-amd64/microscale amd64
bash scripts/benchmark.sh safe amd64 dist/safe/linux-amd64/microscale
```

See [benchmark methodology](benchmarks/README.md). CLI RSS/startup is measured on GitHub runners and is not a prediction of router RAM consumption.

## Safety

- **Never** deploy Small/Extreme directly on a router without independent LAN SSH and a verified rollback.
- Do not update NAND partitions, bootloader, or firmware layout as part of this project.
- Tailscale auth keys and local state must not be checked into GitHub.
- A successful build is not a VPN functionality qualification.
- Do not mark a release stable until Exit Node/subnet/DNS/SSH/reconnect/reboot and rollback are validated on the real NR3053.

## Roadmap

- P001: initial full-feature Safe baseline (merged via PR #2)
- P002/P003: independent three-profile benchmark and validation pipeline (PR #3)
- P004: host-controlled OpenWrt installer and restore workflow
- P005: prerelease artifacts, SHA256 and pinned source provenance
- P006 (later): automatic upstream version PRs and requalification

Tailscale upstream code is BSD-3-Clause licensed. Build artifacts preserve `Tailscale-LICENSE`; MicroScale is independent.
