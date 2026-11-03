# OpenWrt ARM64 RAM smoke test — 2026-11-03

- Target: OpenWrt 21.02-SNAPSHOT, BusyBox 1.33.2, Linux `aarch64`
- Physical memory: 492120 KiB (~480.6 MiB); swap: none
- Test location: `/tmp` (tmpfs, 240.3 MiB total)
- Release: `v0.2.0-rc.4`
- Checks: release script and archive SHA256, CLI version, daemon version, CLI help, one `/usr/bin/time` CLI peak RSS and elapsed time per invocation
- Attempts: two per profile, **6/6 PASS**
- Evidence: [raw numeric results](openwrt-arm64-2026-11-03-rc4.tsv), transcribed from router console; URLs containing signed GitHub release download tokens were intentionally excluded

| Profile | Executable bytes | Peak CLI RSS KiB (attempts) | CLI elapsed s | Result |
| --- | ---: | ---: | ---: | --- |
| Small | 41,943,200 | 118,928 / 118,256 | 0.03 / 0.03 | PASS |
| Micro | 13,369,504 | 44,752 / 44,496 | 0.01 / 0.01 | PASS |
| Extreme | 3,592,972 | 66,032 / 66,032 | 0.78 / 0.78 | PASS |

The `/tmp` space reported 42.7 MiB used before downloading and 121.0 MiB used after the run (an increase of ~78.3 MiB). This is RAM-backed filesystem space usage, not the resident set of a long-running daemon.

**Scope:** These checks did not start or restart the system Tailscale service, sign in, modify VPN configuration, verify Exit Node/subnet routing, exercise userspace networking, or measure sustained daemon RSS. Strong feature compatibility and 24/7 suitability remain unverified.

**Interpretation:** Micro had the lowest sampled CLI RSS and fastest invocation here. Extreme's smaller executable incurred a much slower CLI invocation and larger CLI RSS than Micro, consistent with UPX unpacking overhead. Further, repeated and controlled testing is required for causal conclusions.
