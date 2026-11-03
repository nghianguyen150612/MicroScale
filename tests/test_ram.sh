#!/usr/bin/env bash
set -Eeuo pipefail

sh -n scripts/ram-test.sh
bash -n scripts/import-report.sh
sh scripts/ram-test.sh --help | grep -q 'small|micro|extreme|all'
grep -q '^RELEASE_TAG=v0.2.0-rc.4$' scripts/ram-test.sh

# Invalid/free-form records containing potentially private details must be rejected.
sample="$(mktemp)"
trap 'rm -f "$sample"' EXIT
printf '%s\n' 'utc	platform	arch	profile	release	elf_bytes	ram_total_kib	ram_available_kib	cli_version	daemon_version	cli_help	cli_peak_rss_kib	cli_elapsed_s	result' > "$sample"
printf '%s\n' '2026-11-03T08:00:00Z	linux	amd64	small	v0.2.0-rc.4	1000	512000	400000	ok	ok	ok	10000	0.01	PASS	private-hostname' >> "$sample"
if bash scripts/import-report.sh "$sample" >/dev/null 2>&1; then
    echo 'FAIL: unsafe report accepted' >&2
    exit 1
fi

# Smoke tests must not change host services, state, or persistent Tailscale binaries.
if grep -Eq '^[[:space:]]*(uci|iptables|nft|systemctl|service|tailscale up|tailscale set|tailscale login)([[:space:]]|$)' scripts/ram-test.sh; then
    echo 'FAIL: system mutation detected in RAM test script' >&2
    exit 1
fi
echo 'PASS: RAM-only script syntax, usage and import safety checks'
