# RAM-only tests (OpenWrt ARM64 / Arch x86_64)

These tests do **not** install Tailscale or modify services. RAM results are written under `/tmp/microscale-ram` on OpenWrt and `/dev/shm/microscale-ram` on Arch.

## Router

```sh
cd /tmp
wget -O ram-test.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.5/ram-test.sh
wget -O ram-test.sh.sha256 https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.5/ram-test.sh.sha256
sha256sum -c ram-test.sh.sha256 && sh ram-test.sh all
cat /tmp/microscale-ram/results.tsv
```

## Arch VM (500 MiB)

```sh
cd /dev/shm
curl -fL -o ram-test.sh https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.5/ram-test.sh
curl -fL -o ram-test.sh.sha256 https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.0-rc.5/ram-test.sh.sha256
sha256sum -c ram-test.sh.sha256 && sh ram-test.sh all
cat /dev/shm/microscale-ram/results.tsv
```

## Submit results

Transfer sanitized TSV from router to Arch:

```sh
scp root@192.168.3.1:/tmp/microscale-ram/results.tsv /dev/shm/router-results.tsv
git clone https://github.com/nghianguyen150612/MicroScale.git
cd MicroScale
bash scripts/import-report.sh --submit /dev/shm/router-results.tsv
```

Run `gh auth login` on Arch first; no GitHub credential is required on the router. Review the PR before publishing logs. The test measures CLI/daemon **version smoke checks**, binary sizes and one-shot CLI peak RSS, not sustained VPN routing or daemon uptime.
