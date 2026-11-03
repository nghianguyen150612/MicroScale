# Release policy

MicroScale generates reproducible ARM64 packages from pinned upstream Tailscale.

- `Safe`: combined CLI + daemon, stripped, unmodified feature set.
- `Small`: upstream `--extra-small`, feature-reduced.
- `Extreme`: Small + UPX packing.
- `scripts/install.sh`: interactive, Tailscale-binaries-only installation, without service start or network configuration.

## Prerelease v0.2.0-rc.2

The prerelease contains `install.sh`, `install.sh.sha256`, and the three ARM64 tar.gz assets and their SHA256 files. Each tarball includes Tailscale upstream license, build metadata and executable hash. The installer itself is tied to the same release tag.

CI verifies source pin, binary architecture/checksums and CLI/daemon smoke tests; it does NOT verify VPN dataplane behavior on NR3053. A prerelease is explicitly not a production support claim.

## Stable gate

A stable release is gated on real NR3053 evidence:

1. CPU/userspace architecture and init/service compatibility.
2. Successful login/CLI and local Tailscale daemon startup for each supported profile.
3. Exit Node and Subnet Router dataplane validation from another client.
4. DNS, Tailscale SSH, restart/reconnect, and reboot persistence if claimed.
5. Checked backup and rollback path, with local LAN administration.

Without this evidence, publish only release candidates and keep configuration and service operation in the user's control.

No Tailscale auth keys or router secrets belong in the public repo.
