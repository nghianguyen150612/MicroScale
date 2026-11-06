# Community hardware test results

This directory collects **contributor-submitted** RAM-only MicroScale smoke test reports. Anyone can contribute using a personal fork and a GitHub PR; see [CONTRIBUTING.md](../../CONTRIBUTING.md).

Each TSV follows a strict numerical/enumerated schema. Pull requests are reviewed before merge and automated CI checks the schema. A report is **not hardware-attested**: it does not independently verify device ownership, hardware identity or operating environment.

A CLI smoke-test PASS does not certify Tailscale login, VPN dataplane, Exit Node, subnet routing, reconnection or continuous daemon uptime. Failed tests should also be submitted to improve project reliability.

Reports contain no private IP addresses, hostnames, keys or Tailnet metadata. The author may optionally disclose a public device model in their PR description.

[Browse community test PRs](https://github.com/nghianguyen150612/MicroScale/pulls?q=is%3Apr+test%3A+community+RAM).
