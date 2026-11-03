#!/bin/sh
# BusyBox ash. Executes only on an OpenWrt router. Never call without LAN SSH.
set -eu
action="${1:-}"
stage="${2:-/tmp/microscale-deploy}"
old_daemon=/usr/sbin/tailscaled
old_cli=/usr/bin/tailscale
service=/etc/init.d/tailscale
rollback_daemon="$stage/rollback.tailscaled"
rollback_cli="$stage/rollback.tailscale"
candidate="$stage/candidate"

say() { echo "MicroScale router: $*" >&2; }
fail() { say "ERROR: $*"; exit 1; }

require_service() {
    [ -x "$service" ] || fail "no known /etc/init.d/tailscale service; refuse to modify"
}
health() {
    [ -x "$old_daemon" ] || return 1
    [ -x "$old_cli" ] || return 1
    "$old_cli" version >/dev/null 2>&1 || return 1
    i=0
    while [ "$i" -lt 12 ]; do
        if "$old_cli" status --json 2>/dev/null |
           grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
            return 0
        fi
        sleep 2
        i=$((i + 1))
    done
    return 1
}
restore() {
    require_service
    [ -f "$rollback_daemon" ] || fail "original daemon not staged"
    [ -f "$rollback_cli" ] || fail "original CLI not staged"
    cp "$rollback_daemon" /usr/sbin/.microscale-restore.new
    chmod 755 /usr/sbin/.microscale-restore.new
    mv -f /usr/sbin/.microscale-restore.new "$old_daemon"
    cp "$rollback_cli" /usr/bin/.microscale-restore-cli.new
    chmod 755 /usr/bin/.microscale-restore-cli.new
    mv -f /usr/bin/.microscale-restore-cli.new "$old_cli"
    "$service" restart
    say "Original binaries restored; verify actual VPN functionality"
}
case "$action" in
  preflight)
    require_service
    [ -f "$old_daemon" ] && [ -f "$old_cli" ] || fail "missing installed Tailscale"
    case "$(uname -m)" in aarch64|arm64) ;; *) fail "router architecture is not ARM64";; esac
    say "Architecture: $(uname -m)"
    df -k /overlay
    "$old_cli" version
    "$old_cli" status || fail "existing Tailscale is not healthy"
    ;;
  apply)
    require_service
    [ -f "$candidate" ] || fail "missing candidate"
    [ -x "$old_daemon" ] && [ -x "$old_cli" ] || fail "missing original binaries"
    # Backup on RAM: the host must have saved persistent backup separately.
    cp "$old_daemon" "$rollback_daemon"
    cp "$old_cli" "$rollback_cli"
    old_sum="$(sha256sum "$candidate" | awk '{print $1}')"
    [ -n "$old_sum" ] || fail "cannot hash candidate"
    # Write temporary copy on UBIFS. Rename is confined to /usr/sbin.
    cp "$candidate" /usr/sbin/.microscale-next.new
    chmod 755 /usr/sbin/.microscale-next.new
    [ "$(sha256sum /usr/sbin/.microscale-next.new | awk '{print $1}')" = "$old_sum" ] ||
      fail "NAND copy checksum mismatch"
    mv -f /usr/sbin/.microscale-next.new "$old_daemon"
    # Upstream combined binary selects CLI when invoked as 'tailscale'.
    ln -sf /usr/sbin/tailscaled "$old_cli"
    if ! "$service" restart; then
        say "restart failed, restoring"
        restore
        exit 1
    fi
    if ! health; then
        say "running-state health failed, restoring"
        restore
        exit 1
    fi
    touch "$stage/committed"
    say "Basic health passed. Exit Node and subnet routing still require end-to-end validation."
    ;;
  restore)
    restore
    ;;
  check)
    require_service
    health || fail "Tailscale backend not Running"
    say "Backend is Running; this is not an Exit Node dataplane test"
    ;;
  *) fail "usage: router-transaction.sh {preflight|apply|restore|check} STAGE" ;;
esac
