#!/usr/bin/env bash
set -Eeuo pipefail

# These tests do not install anything or require OpenWrt.
sh -n scripts/install.sh
help="$(sh scripts/install.sh --help)"
grep -q 'three-choice interactive menu' <<<"$help"
grep -q 'never configures, starts, restarts or enables' <<<"$help"
grep -q 'Small' scripts/install.sh
grep -q 'Micro' scripts/install.sh
grep -q 'Small' scripts/install.sh
grep -q 'Micro' scripts/install.sh
grep -q 'Extreme' scripts/install.sh
grep -q 'sha256sum -c' scripts/install.sh
grep -q '^RELEASE_TAG="v0.2.0-rc.4"$' scripts/install.sh

# Installer must contain no service, networking, or authentication commands.
# It is deliberately an installation-only operation; the user manages startup.
if grep -Eq '^[[:space:]]*(uci|iptables|nft|service|systemctl|tailscale up|tailscale set|tailscale login)([[:space:]]|$)' scripts/install.sh; then
    echo "FAIL: installer unexpectedly configures network or services" >&2
    exit 1
fi

# Release workflow must include an installer and the three profiles.
grep -q 'scripts/install.sh' .github/workflows/release.yml
for profile in small micro extreme; do
    grep -q "$profile" .github/workflows/release.yml
done

echo "PASS: standalone interactive installer static tests"
