# RAM test reports

Reports are imported using `scripts/import-report.sh`. Each TSV contains only the allowed metrics and PASS/FAIL results from RAM-only smoke tests.

Never upload raw Tailscale logs, `tailscale status`, auth keys, device hostnames, IP addresses, or Tailnet configuration. Open a PR for review rather than committing unreviewed raw output to main.
