#!/usr/bin/env bash
set -Eeuo pipefail

sh -n scripts/install.sh
sh -n scripts/manager.sh
sh -n scripts/ram-test.sh

expected="$(sed -n 's/^engine_sha=//p' scripts/install.sh)"
actual="$(sha256sum scripts/manager.sh | awk '{print $1}')"
[[ "$expected" == "$actual" ]] || {
  echo "FAIL: bootstrap manager checksum pin is outdated" >&2
  exit 1
}
[[ "$(sed -n 's/^RELEASE_TAG=//p' scripts/install.sh)" == v0.2.0-rc.5 ]] || exit 1
[[ "$(sed -n 's/^TAG=//p' scripts/manager.sh)" == v0.2.0-rc.5 ]] || exit 1

sh scripts/manager.sh --help | grep -q 'install|update|repair|status|doctor|diagnostics|uninstall'
sh scripts/manager.sh status | grep -q 'Managed install'
# No service management or network configuration may appear as executable commands.
for path in scripts/install.sh scripts/manager.sh; do
  if grep -Eq '^[[:space:]]*(uci|iptables|nft|systemctl|service|tailscale up|tailscale set|tailscale login)([[:space:]]|$)' "$path"; then
    echo "FAIL: forbidden service/configuration action in $path" >&2
    exit 1
  fi
done
grep -q "scripts/manager.sh" .github/workflows/release.yml
echo "PASS: bootstrap pin, POSIX manager, lifecycle, and no-service invariant"
