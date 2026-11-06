# RAM-only tests — OpenWrt and Linux VMs

The same test runner checks the Tailscale CLI/daemon version and help output on physical routers and virtual machines. It does not change the active VPN, service, routes or configuration.

## On OpenWrt (tmpfs)

```sh
cd /tmp
wget -O install.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.1/install.sh
wget -O install.sh.sha256 https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.1/install.sh.sha256
sha256sum -c install.sh.sha256
sh install.sh test-ram all
sh install.sh report
```

Use `test-ram staged` to test the exact profile previously placed in RAM. Once installed to NAND, the shortcut is `microscale test-ram all` / `microscale report`.

Reports remain in tmpfs: `/tmp/microscale-ram/latest.tsv` for the current run and `results.tsv` for cumulative history. Linux VMs with disk-backed `/tmp` use `/dev/shm/microscale-ram/`.

## On Arch: run a device test and save it to GitHub

```bash
gh auth login
git clone https://github.com/nghianguyen150612/MicroScale.git
cd MicroScale
bash scripts/collect-device-report.sh --submit root@ROUTER_IP all
```

For a VM, replace `root@ROUTER_IP` with its SSH target. This performs the same test over SSH, fetches the sanitized report and opens a reviewable PR. No GitHub credential is placed on the target.

More details: [device reports](DEVICE-REPORTS.md). These are CLI smoke tests, not Exit Node, DNS, VPN throughput or sustained daemon qualification.
