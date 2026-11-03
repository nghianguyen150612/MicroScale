#!/usr/bin/env bash
set -Eeuo pipefail

for script in scripts/install.sh scripts/manager.sh scripts/ram-test.sh; do
    sh -n "$script"
done

expected="$(sed -n 's/^engine_sha=//p' scripts/install.sh)"
actual="$(sha256sum scripts/manager.sh | awk '{print $1}')"
[[ "$expected" == "$actual" ]] || {
    echo "FAIL: bootstrap manager checksum pin is outdated" >&2
    exit 1
}
[[ "$(sed -n 's/^RELEASE_TAG=//p' scripts/install.sh)" == v0.2.0-rc.7 ]]
[[ "$(sed -n 's/^TAG=//p' scripts/manager.sh)" == v0.2.0-rc.7 ]]

sh scripts/manager.sh help | grep -q 'microscale'
sh scripts/manager.sh version | grep -q 'MicroScale manager'
sh scripts/manager.sh status | grep -q 'Managed install'
sh scripts/manager.sh ram-status | grep -q 'RAM stage'
sh scripts/manager.sh help | grep -q 'install-ram'

# The OpenWrt layout and symlink must be explicitly implemented, not merely documented.
for literal in \
  'STATE=/etc/microscale' \
  'MANAGER_DIR=/usr/lib/microscale' \
  'COMMAND=/usr/bin/microscale' \
  'MANAGER=$MANAGER_DIR/manager.sh' \
  'ln -s "$MANAGER" "$COMMAND.next.$$"' \
  'chmod 755 "$MANAGER.next.$$"' \
  'mv -f "$COMMAND.next.$$" "$COMMAND"'; do
    grep -Fq "$literal" scripts/manager.sh || {
        echo "FAIL: missing layout/CLI implementation: $literal" >&2
        exit 1
    }
done

# Unrelated commands must never be replaced by the microscale alias.
grep -Fq 'ensure_command_available' scripts/manager.sh
grep -Fq 'readlink "$COMMAND"' scripts/manager.sh

# Guard against mismatched staging paths ($ instead of $$) on BusyBox ash.
if grep -En '\.(next|restore)\.\$["[:space:]]' scripts/manager.sh; then
    echo 'FAIL: malformed PID-suffixed transaction path' >&2
    exit 1
fi

# Preserve the original no-service, no-auth and no-routing contract.
for path in scripts/install.sh scripts/manager.sh; do
    if grep -Eq '^[[:space:]]*(uci|iptables|nft|systemctl|service|tailscale up|tailscale set|tailscale login)([[:space:]]|$)' "$path"; then
        echo "FAIL: forbidden service/configuration action in $path" >&2
        exit 1
    fi
done
grep -Fq 'scripts/manager.sh' .github/workflows/release.yml
echo 'PASS: pinned bootstrap, OpenWrt layout, symlink and binary-only lifecycle'
