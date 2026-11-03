# MicroScale measurement methodology

Profiles: Safe (combined + strip), Small (upstream extra-small), Extreme (Small + UPX).

## Metrics
- `elf_bytes`: actual executable file bytes, including packed executable for Extreme.
- `archive_bytes`: distribution .tar.gz size. **Do not confuse with NAND space occupied.**
- `cli_mean_seconds`: mean wall time over five native `tailscale version` invocations.
- `cli_peak_rss_kib`: highest peak memory observed across those five native invocations.
- `daemon_rss_kib`: one resident set sample after three seconds with userspace networking and `--state=mem:`, **without authenticating**.
- `qualifier`: host/no-login caveat. CPU/RSS results are from CI virtual machines, not the router.

Benchmark numbers from different runner architectures are not comparable as if they came from one hardware target. Compression on UBIFS means saved NAND bytes differ from ELF byte differences.

## Required device qualification before install
1. Record `uname -m`, `tailscale version`, `df -h /overlay` and the existing init-script command line.
2. Confirm local-LAN SSH recovery that does not depend on Tailscale.
3. Ensure CLI login and `tailscale up` work for the chosen profile.
4. Validate Exit Node routing, Subnet Router, MagicDNS, Tailscale SSH, reconnect and persistence after reboot **on NR3053 itself**.
5. If any required feature fails, reject the profile; never claim pass from CI smoke tests.
