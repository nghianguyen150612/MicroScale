# Release policy

- **P001**: full-feature Safe baseline. CI proves build and CLI/daemon smoke tests only.
- **P002/P003**: three profiles; report raw ELF bytes, archive bytes and host-only benchmarks, plus honest missing metrics. Small/Extreme are unqualified until device tests.
- **P004**: local-LAN-only deploy/restore tooling. No deployment from CI.
- **P005**: release-candidate packages via GitHub Actions only after CI. Workflow only accepts tags `vX.Y.Z-rc.N`; it never creates a stable release.

A stable release requires evidence from NR3053: correct CPU ABI, successful fresh login/CLI management, Exit Node and subnet dataplane validation from another tailnet client, MagicDNS, Tailscale SSH, reconnect under WAN interruption, persistence after reboot, and tested rollback. This release candidate is not proof of any such result.

Workflow: once `release.yml` lands on main, the initial push creates `v0.2.0-rc.1` if release build passes. For later candidates use GitHub Actions > MicroScale release candidate > Run workflow with a new -rc.N tag. Each archive contains its checksum, license and build provenance. Never publish private Tailscale state/keys.
