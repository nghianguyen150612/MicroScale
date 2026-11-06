#!/usr/bin/env bash
set -Eeuo pipefail
sh -n scripts/manager.sh
sh -n scripts/ram-test.sh
bash -n scripts/collect-device-report.sh
bash -n scripts/import-report.sh
sh scripts/manager.sh help | grep -q 'test-ram'
sh scripts/ram-test.sh --help | grep -q 'staged'
bash scripts/collect-device-report.sh --help >/dev/null 2>&1 && {
  echo 'Collector should reject missing SSH target' >&2; exit 1;
}
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' 'utc	platform	arch	profile	release	elf_bytes	ram_total_kib	ram_available_kib	cli_version	daemon_version	cli_help	cli_peak_rss_kib	cli_elapsed_s	result' > "$tmp/good.tsv"
printf '%s\n' '2026-11-06T07:00:00Z	openwrt	arm64	micro	v0.2.1	13369504	492120	120000	ok	ok	ok	44752	0.01	PASS' >> "$tmp/good.tsv"
bash scripts/import-report.sh --validate-only "$tmp/good.tsv" >/dev/null
# Extra field (e.g. hostname or leaked Tailnet token) is not allowed.
cp "$tmp/good.tsv" "$tmp/bad.tsv"
printf '\tsecret-hostname\n' >> "$tmp/bad.tsv"
if bash scripts/import-report.sh --validate-only "$tmp/bad.tsv" >/dev/null 2>&1; then
  echo 'Unsafe report accepted' >&2; exit 1
fi
# Ensure the manager only fetches the same release-pinned RAM tester.
grep -Fq 'fetch "$STAGE/ram-test.sh.sha256"' scripts/manager.sh
grep -Fq '(cd "$STAGE" && sha256sum -c ram-test.sh.sha256)' scripts/manager.sh
grep -Fq 'sh "$STAGE/ram-test.sh"' scripts/manager.sh
grep -Fq 'latest="$root/latest.tsv"' scripts/ram-test.sh
grep -Fq 'ssh "$target" "sh -s -- test-ram $profile"' scripts/collect-device-report.sh
# Test must not mutate service, Tailnet, firewall or system Tailscale binary.
for script in scripts/ram-test.sh scripts/collect-device-report.sh; do
  if grep -Eq '^[[:space:]]*(systemctl|service|uci|iptables|nft|tailscale up|tailscale set|tailscale login)([[:space:]]|$)' "$script"; then
    echo "Forbidden system mutation: $script" >&2; exit 1
  fi
done
echo 'PASS: unified device/VM RAM test and sanitized host-side PR flow'
