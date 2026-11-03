# MicroScale

**Tailscale, built smaller.**

MicroScale is a build and distribution system for the official [Tailscale](https://github.com/tailscale/tailscale) client on OpenWrt and embedded Linux. It is not a new VPN protocol and does not remove core VPN behavior to make the initial build smaller.

## P001: Safe build

The `safe` profile pins Tailscale `v1.104.5` to commit `73a48057aaf5f60e4f770b398e9b7af576b01dbe`, disables CGO, strips distribution debug sections, and uses upstream's `ts_include_cli` build tag to combine the `tailscale` CLI with the `tailscaled` daemon. No Tailscale feature omission tags are enabled. The upstream source is fetched during builds and is not stored in this repository.

The produced `microscale` executable runs the daemon by default. Set `TS_BE_CLI=1` when invoking its CLI commands. The same file contains both programs; configure the target system's service to run it as the daemon, and use `TS_BE_CLI=1 microscale status` for CLI requests. See upstream `cmd/tailscaled/with_cli.go` for combined binary dispatch behavior.

```sh
./scripts/build.sh safe
./scripts/verify.sh dist/safe/linux-arm64/microscale arm64 41733325
```

Build output includes `Tailscale-LICENSE` and `build-info.txt`. Keep the upstream license notice with any redistributed binary. `LICENSE` covers MicroScale's own repository files; Tailscale code and the combined binary remain subject to Tailscale's BSD 3-Clause license and notices.

GitHub Actions builds and architecture-checks Linux ARM64, then builds a native Linux AMD64 copy to run CLI and daemon version smoke tests. CI reports the ARM64 binary size against the supplied, rounded 39.8 MiB baseline; the comparison is informational because the supplied component sizes are rounded and a full-feature combined binary may be slightly larger. It is not a benchmark of RAM, CPU, or runtime VPN behavior.

## Hardware status

Linux ARM64 is the initial build target. The Viettel NR3053 CPU architecture has **not** been verified, and no binary should be deployed to it until its actual userspace/kernel architecture and ABI are checked. P001 does not modify a router. Exit Node, Subnet Router, reconnect, MagicDNS, and 24/7 operation have not been tested on the NR3053; this project does not claim those runtime behaviors are verified.

## Repository layout

- `profiles/safe.env`: pinned upstream version and conservative build settings.
- `scripts/build.sh`: fetch the pinned upstream source and build the combined binary.
- `scripts/verify.sh`: verify executable format, architecture, stripped debug sections, size, and compatible-host smoke tests.
- `.github/workflows/build.yml`: CI build, verification, SHA256, and artifact upload.

## Roadmap

- P001: repository bootstrap, combined binary, CI.
- P002: benchmark size, RAM, CPU, and startup.
- P003: Safe, Small, and Experimental build profiles.
- P004: OpenWrt installer, backup, and rollback.
- P005: GitHub Releases and upstream version tracking.
