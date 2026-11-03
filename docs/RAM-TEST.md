# RAM-only smoke tests

Version: `v0.2.0-rc.4`. Supports Linux ARM64 and x86_64 (AMD64).

## OpenWrt router

Use a normal LAN SSH connection. Check the architecture and tmpfs:

```sh
uname -m
df -h /tmp
awk '$2 == "/tmp" {print $2, $3}' /proc/mounts
```

If the CPU is `aarch64` or `arm64`, run:

```sh
cd /tmp
wget -O ram-test.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.4/ram-test.sh
wget -O ram-test.sh.sha256 https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.4/ram-test.sh.sha256
sha256sum -c ram-test.sh.sha256
sh ram-test.sh all
cat /tmp/microscale-ram/results.tsv
```

This never overwrites `/usr/bin/tailscale` or `/usr/sbin/tailscaled`, and does not start the VPN service. Files and logs remain under `/tmp/microscale-ram` until removed or rebooted.

## Arch Linux VM (500 MiB RAM)

Create an x86_64 VM with 500 MiB RAM, then:

```sh
uname -m
free -m
cd /dev/shm
curl -fL -o ram-test.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.4/ram-test.sh
curl -fL -o ram-test.sh.sha256 https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.4/ram-test.sh.sha256
sha256sum -c ram-test.sh.sha256
sh ram-test.sh all
cat /dev/shm/microscale-ram/results.tsv
```

The script records memory reported by the guest, executable bytes, CLI/daemon-version smoke results, and peak CLI RSS when GNU `/usr/bin/time` is available. No 24/7 daemon, network throughput, or Exit Node performance measurement is implied.

## Submit results to the repo

The TSV contains only allowlisted fields; no IP, device name, Tailnet identity or authentication state. Inspect the report before publishing.

From the Arch host with a GitHub-authenticated clone of MicroScale:

```sh
scp root@192.168.3.1:/tmp/microscale-ram/results.tsv /dev/shm/router-results.tsv
bash scripts/import-report.sh --submit /dev/shm/router-results.tsv
```

The helper validates every field, then opens a **pull request** containing the report. No GitHub token needs to be stored on the router. Alternatively paste `results.tsv` into the ChatGPT conversation and request a PR.

Test output is deliberately limited to non-invasive smoke checks. Micro and Extreme may not support all Tailscale features. Real VPN function tests need a separately authorized setup.
