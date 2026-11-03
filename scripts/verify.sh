#!/usr/bin/env bash
set -Eeuo pipefail

fail() { printf 'verify.sh: FAIL: %s\n' "$*" >&2; exit 1; }
[[ $# -ge 2 ]] || fail "usage: scripts/verify.sh <binary> <expected-goarch> [baseline-bytes]"
binary="$1"
expected_arch="$2"
baseline_bytes="${3:-0}"
[[ -f "$binary" ]] || fail "binary not found: $binary"
[[ -x "$binary" ]] || fail "binary is not executable: $binary"
command -v readelf >/dev/null || fail "readelf is required to verify ELF architecture"

machine="$(readelf -h "$binary" | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p' | head -n 1)"
case "$expected_arch" in
  arm64) expected_machine='AArch64' ;;
  amd64) expected_machine='Advanced Micro Devices X86-64' ;;
  arm) expected_machine='ARM' ;;
  386) expected_machine='Intel 80386' ;;
  *) fail "unsupported expected GOARCH: $expected_arch" ;;
esac
[[ "$machine" == "$expected_machine" ]] || fail "ELF machine mismatch: expected $expected_machine for $expected_arch, got '${machine:-unknown}'"
if readelf -S "$binary" | grep -Eq '\.debug_(info|line|abbrev|str)'; then
  fail "debug sections remain; expected stripped distribution binary"
fi
size_bytes="$(stat -c '%s' "$binary")"
printf 'Architecture: %s (%s)\nBinary size: %s bytes (%.2f MiB)\n' "$expected_arch" "$machine" "$size_bytes" "$(awk -v n="$size_bytes" 'BEGIN { printf "%.2f", n/1048576 }')"
if [[ "$baseline_bytes" =~ ^[0-9]+$ ]] && (( baseline_bytes > 0 )); then
  delta_bytes=$((size_bytes - baseline_bytes))
  delta_percent="$(awk -v d="$delta_bytes" -v b="$baseline_bytes" 'BEGIN { printf "%+.2f", 100*d/b }')"
  if (( delta_bytes < 0 )); then
    printf 'Size vs baseline: %s bytes (%s%%, smaller)\n' "$delta_bytes" "$delta_percent"
  else
    printf 'Size vs baseline: +%s bytes (%s%%, larger)\n' "$delta_bytes" "$delta_percent"
  fi
fi

host_arch="$(uname -m)"
case "$host_arch" in
  aarch64|arm64) host_goarch=arm64 ;;
  x86_64|amd64) host_goarch=amd64 ;;
  armv7l|armv6l) host_goarch=arm ;;
  i?86) host_goarch=386 ;;
  *) host_goarch=unknown ;;
esac
if [[ "$host_goarch" != "$expected_arch" ]]; then
  printf 'Runtime smoke tests: SKIP (host is %s, binary is %s; run on a compatible Linux host)\n' "$host_arch" "$expected_arch"
  exit 0
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/profiles/small.env"
expected_version="${UPSTREAM_VERSION#v}"
cli_version="$(TS_BE_CLI=1 "$binary" version 2>&1)" || fail "combined CLI version command failed"
[[ "$cli_version" == *"$expected_version"* ]] || fail "unexpected CLI version output: $cli_version"
TS_BE_CLI=1 "$binary" --help >/dev/null 2>&1 || fail "combined CLI --help smoke test failed"
daemon_version="$(env -u TS_BE_CLI "$binary" --version 2>&1)" || fail "combined daemon --version command failed"
[[ "$daemon_version" == *"$expected_version"* ]] || fail "unexpected daemon version output: $daemon_version"
printf 'Runtime smoke tests: PASS (CLI version, CLI help, daemon version)\n'
