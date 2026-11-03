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

## One-command interactive install (OpenWrt ARM64)

**Release candidate:** `v0.2.0-rc.2`. SSH into the router **over local LAN**, as root. Paste this single command:

```sh
wget -O /tmp/microscale-install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.2/install.sh && sh /tmp/microscale-install.sh
```

The installer presents a menu: `1 = Safe`, `2 = Small`, `3 = Extreme`. It requires confirmation, downloads a release asset and SHA256 checksum, verifies the archive and executable, checks the ARM64 target and available NAND space, and atomically installs the combined binary as `/usr/sbin/tailscaled` plus a `/usr/bin/tailscale` symlink.

**Only the Tailscale binaries are installed or replaced.** It does **not** install dependencies, enable/start/restart the service, run `tailscale up`, modify auth state, DNS, firewall, network, init files, or configure Exit Node/Subnet Router. The user manages service startup and Tailscale configuration afterward. An already-running daemon continues using its previous executable until the user restarts it.

Original executable copies are temporarily saved under `/tmp/microscale-backup.*` for recovery during the current boot only. Installer refuses non-ARM64 targets and unsupported filesystem setups. Small/Extreme have NOT been functionally qualified on NR3053; they may lack required functions. **This release is experimental, not production-qualified.**

Read [installer details](docs/ONE-CLICK-INSTALL.md) and [release policy](docs/RELEASE-POLICY.md). Do not install through your only Tailscale management connection.

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
