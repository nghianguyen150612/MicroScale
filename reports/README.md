# RAM test reports

Reports are imported using `scripts/import-report.sh`. Each TSV contains only the allowed metrics and PASS/FAIL results from RAM-only smoke tests.

Never upload raw Tailscale logs, `tailscale status`, auth keys, device hostnames, IP addresses, or Tailnet configuration. Open a PR for review rather than committing unreviewed raw output to main.

## Public contributions

Contributors without write access can use `scripts/import-report.sh --submit latest.tsv` on a computer with GitHub CLI. The script creates a personal fork and opens a PR. See [CONTRIBUTING.md](../CONTRIBUTING.md).

Accepted community reports live in [community/](community/README.md). CI only verifies allowed report fields and file boundaries; it cannot confirm that a real device actually produced a measurement.
