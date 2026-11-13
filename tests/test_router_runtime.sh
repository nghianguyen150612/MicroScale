#!/bin/sh
# Smoke test for the combined CLI/daemon on physical OpenWrt or native Linux.
# A separate socket and memory-only state prevent production VPN changes.
set -eu
bin="${1:?Pass absolute path to combined MicroScale executable}"
[ -x "$bin" ] || { echo "Not executable: $bin" >&2; exit 1; }
tmp="$(mktemp -d /tmp/microscale-runtime.XXXXXX)"
pid=''
cleanup() {
  [ -z "$pid" ] || { kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; }
  rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM
ln -s "$bin" "$tmp/tailscaled"
ln -s "$bin" "$tmp/tailscale"
"$tmp/tailscale" version >/dev/null
"$tmp/tailscaled" --version >/dev/null
"$tmp/tailscaled" --help >"$tmp/help" 2>&1
grep -q 'socks5-server' "$tmp/help" || { echo 'SOCKS5 flag missing' >&2; exit 1; }
"$tmp/tailscaled" --tun=userspace-networking --socks5-server=127.0.0.1:0 \
  --state=mem: --socket="$tmp/sock" >"$tmp/daemon.log" 2>&1 &
pid=$!
sleep 4
kill -0 "$pid" 2>/dev/null || {
  echo 'MicroScale userspace daemon exited early:' >&2
  grep -E 'error|fail|unsupported|panic' "$tmp/daemon.log" >&2 || :
  exit 1
}
[ -S "$tmp/sock" ] || { echo 'Unix socket was not created' >&2; exit 1; }
# A memory-only sidecar is intentionally logged out; `status` can return 1
# in that state. `debug prefs` must still succeed over the new Unix socket.
"$tmp/tailscale" --socket="$tmp/sock" debug prefs >"$tmp/prefs" 2>&1 || {
  echo 'Local daemon IPC failed' >&2; exit 1;
}
grep -q '"LoggedOut": true' "$tmp/prefs" || {
  echo 'Expected isolated logged-out state' >&2; exit 1;
}
echo 'PASS: userspace daemon + SOCKS5 flag + IPC + CLI; VPN/Serve/SSH not yet attested'
