# Contribute real-device test results

MicroScale welcomes **community-run RAM smoke tests** from OpenWrt routers, ARM64 devices and Linux x86_64 VMs. Anyone with a GitHub account can contribute through a **fork and pull request**—write access to MicroScale is not required.

## 1. Run the test

On the device, use the checksum-verified [v0.2.1 installer](https://github.com/nghianguyen150612/MicroScale/releases/tag/v0.2.1):

```sh
cd /tmp
wget -O install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.1/install.sh
wget -O install.sh.sha256 https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.1/install.sh.sha256
sha256sum -c install.sh.sha256 && sh install.sh test-ram all
```

Use `test-ram staged` to test a previously installed RAM-stage profile. Do not use `apply`: the community benchmark does not require NAND installation.

## 2. Submit a PR from your computer

On any Linux computer with `git`, `gh`, `openssh`, and `bash`, authenticate GitHub **locally**:

```bash
gh auth login
gh auth setup-git
git clone https://github.com/nghianguyen150612/MicroScale.git
cd MicroScale
bash scripts/collect-device-report.sh --submit --device "Optional public model name" root@ROUTER_IP all
```

The script runs the test over SSH, obtains the sanitized report, validates its fields and opens a pull request. **It creates or reuses your personal fork if you do not have repository write access.** No GitHub token goes to the router. You may omit `--device` to keep the hardware model private.

Already have a `latest.tsv`? Copy it onto your computer and run:

```bash
bash scripts/import-report.sh --submit --device "Optional public model name" /path/to/latest.tsv
```

Omit `--submit` to validate and stage the file locally without publishing it. The command prints the pull request link after successful submission.

## What the report proves

The 14-column TSV includes test time, OS family, CPU architecture, profile, release, binary size, memory totals, one-shot CLI RSS/time (when available), and CLI/daemon version/help PASS or FAIL. The result is **contributor-reported evidence**, not independently authenticated hardware proof.

A PASS does **not** prove login, traffic forwarding, Exit Node, subnet routing, network performance, reboot persistence or 24/7 stability. To claim those features, separate and controlled tests are necessary.

## Review and privacy

- Do not upload full Tailscale diagnostics, auth keys, machine identifiers, hostnames, LAN/public IPs, serial numbers or Tailnet settings.
- The device model is optional, voluntarily disclosed in the PR description, and not added to the TSV.
- Automated checks validate TSV structure and permitted values only. A maintainer reviews the PR before merging; CI cannot verify that the reported hardware really ran the test.
- Both PASS and FAIL results are welcome. Do not change results to look better.

Accepted reports are visible in [reports/community](reports/community/README.md), with their Git commit and PR history. We do not award a fabricated compatibility badge or claim certified device support.
