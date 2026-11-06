# Real-device RAM tests and repository reports

One test runner is used on physical OpenWrt ARM64 routers and Linux x86_64 VMs. It verifies the downloaded release archive or an existing RAM-stage executable, runs **CLI version, daemon version and CLI help** checks, and records binary size, one-shot CLI RSS and timing when GNU time is available.

These are **non-invasive smoke tests**, not a test of the VPN data plane, connectivity, Exit Node, daemon uptime or Tailscale login.

## Test directly on the device

Download the checksum-pinned bootstrap from [v0.2.1](https://github.com/nghianguyen150612/MicroScale/releases/tag/v0.2.1), then run:

```sh
# For OpenWrt: download this installer into tmpfs (/tmp).
cd /tmp
wget -O install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.1/install.sh
wget -O install.sh.sha256 https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.1/install.sh.sha256
sha256sum -c install.sh.sha256
sh install.sh test-ram all
sh install.sh report
```

If a profile was already staged using Install to RAM, test that **exact staged executable**:

```sh
sh /tmp/install.sh test-ram staged
```

After NAND installation, the short command works as well:

```sh
microscale test-ram all
microscale test-ram staged
microscale report
```

The current run is saved in `/tmp/microscale-ram/latest.tsv`; cumulative history is `/tmp/microscale-ram/results.tsv` (or `/dev/shm/microscale-ram/` if that is the verified tmpfs). The fields contain no hostnames, IP addresses, Tailnet data, credentials, device serials or command stdout.

## Test and submit from Arch in one command

Install `git`, `openssh`, `gh`, `curl` and `bash`. Authenticate GitHub **on Arch, not the router**.

```bash
gh auth login
git clone https://github.com/nghianguyen150612/MicroScale.git
cd MicroScale

# Validates a pinned installer, tests the real device over SSH,
# retrieves the per-run report, validates the allowed schema and opens a PR:
bash scripts/collect-device-report.sh --submit --device "Optional model" root@ROUTER_IP all
```

For a Linux VM, substitute its SSH target. To test an already staged profile, replace `all` with `staged`. Omit `--submit` to see validated results without publishing.

The script uses `ssh` to transfer a checksum-verified bootstrap and retrieve the TSV. No GitHub token, Git CLI or persistence is required on the target. The host-side importer creates a unique branch and **reviewable PR** under `reports/`; nothing is auto-merged.

## Report provenance and limits

Each row includes UTC timestamp, platform category (`openwrt` or `linux`), architecture, profile, release, binary size, guest memory totals, CLI check statuses, optional peak RSS/elapsed time and result. Device identity and network coordinates are intentionally excluded.

These are user-submitted test results, not cryptographically attested hardware measurements. Review the PR and the numerical values before merging to `main`.

The installer never restarts the system daemon, changes Tailscale state, edits DNS, routes or firewall rules. RAM test files disappear on reboot.

## Submit as an external contributor

You do not need write access to MicroScale. The host-side importer will create (or reuse) a fork under your own GitHub account and then open a PR against `nghianguyen150612/MicroScale:main`. The optional `--device` label is provided knowingly by the contributor and must not contain a serial number, hostname or identifiable data.

Already have a copied `latest.tsv` file? Run:

```bash
bash scripts/import-report.sh --validate-only /path/latest.tsv
bash scripts/import-report.sh --submit --device "Optional model" /path/latest.tsv
```

Community PRs are validated by `community-report-validation.yml` using the **trusted main-branch validator**, not code from the external fork. Only TSVs in `reports/community/` are accepted by that workflow, and human review is still required. No automatic merge occurs.

See [CONTRIBUTING.md](../CONTRIBUTING.md).
