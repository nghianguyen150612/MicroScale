#!/usr/bin/env bash
# Size measurements on any host; native-only CLI/daemon runtime samples.
# CI measurements are NOT estimates of RAM/CPU on the NR3053.
set -Eeuo pipefail
[[ $# -eq 3 ]] || { echo "usage: benchmark.sh PROFILE ARCH BINARY" >&2; exit 2; }
profile="$1"
arch="$2"
binary="$(realpath "$3")"
[[ -f "$binary" && -x "$binary" ]] || { echo "missing executable: $binary" >&2; exit 1; }
directory="$(dirname "$binary")"
output="$directory/benchmark.tsv"
elf_bytes="$(stat -c '%s' "$binary")"
archive="$directory/microscale-$profile-linux-$arch.tar.gz"
archive_bytes=0
[[ -f "$archive" ]] && archive_bytes="$(stat -c '%s' "$archive")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
host="$(uname -m)"
native=no
case "$host:$arch" in x86_64:amd64|aarch64:arm64) native=yes ;; esac
printf 'profile\tarch\telf_bytes\tarchive_bytes\tcli_mean_seconds\tcli_peak_rss_kib\tdaemon_rss_kib\tqualifier\n' > "$output"
if [[ "$native" != yes ]]; then
  printf '%s\t%s\t%s\t%s\tNA\tNA\tNA\tnon-native\n' \
    "$profile" "$arch" "$elf_bytes" "$archive_bytes" >> "$output"
  cat "$output"; exit 0
fi

command -v /usr/bin/time >/dev/null || { echo "GNU /usr/bin/time required" >&2; exit 1; }
: > "$tmp/cli.tsv"
for i in 1 2 3 4 5; do
  /usr/bin/time -f '%e %M' -o "$tmp/time" env TS_BE_CLI=1 \
      "$binary" version >"$tmp/cli.out" 2>"$tmp/cli.err"
  cat "$tmp/time" >> "$tmp/cli.tsv"
done
read -r mean peak < <(awk '{ total+=$1; if ($2>peak) peak=$2 } END { printf "%.3f %d\n", total/NR, peak }' "$tmp/cli.tsv")

# The daemon is started without signing in or changing host routes.
# A failure here is recorded, not misreported as qualified VPN operation.
daemon_rss=NA
socket="$tmp/tailscaled.sock"
log="$tmp/daemon.log"
env -u TS_BE_CLI "$binary" --tun=userspace-networking --state=mem: \
  --socket="$socket" > "$log" 2>&1 &
pid=$!
sleep 3
if kill -0 "$pid" 2>/dev/null; then
  daemon_rss="$(awk '/^VmRSS:/ { print $2 }' "/proc/$pid/status" 2>/dev/null || true)"
  [[ -n "$daemon_rss" ]] || daemon_rss=NA
fi
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tCI-no-login\n' \
  "$profile" "$arch" "$elf_bytes" "$archive_bytes" "$mean" "$peak" "$daemon_rss" >> "$output"
cat "$output"
