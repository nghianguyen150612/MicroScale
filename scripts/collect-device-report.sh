#!/usr/bin/env bash
# Collect RAM-only results from physical OpenWrt/VM devices over SSH.
# GitHub authentication remains on this workstation, not on the device.
set -Eeuo pipefail
fail() { printf 'MicroScale collector: %s\n' "$*" >&2; exit 1; }
submit=false
if [[ "\${1:-}" == "--submit" ]]; then submit=true; shift; fi
[[ $# -ge 1 && $# -le 2 ]] ||
  fail "Usage: bash scripts/collect-device-report.sh [--submit] user@host [small|micro|extreme|all|staged]"
target="$1"
profile="\${2:-all}"
[[ "$target" =~ ^[A-Za-z0-9_.@:-]+$ && "$target" != -* ]] || fail 'Invalid SSH target'
[[ "$profile" =~ ^(small|micro|extreme|all|staged)$ ]] || fail 'Invalid RAM test profile'
root="$(cd "$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$root/scripts/import-report.sh" ]] || fail 'Run from a MicroScale checkout'
for tool in ssh sha256sum bash; do command -v "$tool" >/dev/null || fail "Missing $tool"; done
if [[ "$submit" == true ]]; then
  command -v git >/dev/null || fail 'Git required for PR'
  command -v gh >/dev/null || fail 'GitHub CLI required for PR'
  gh auth status >/dev/null || fail 'Authenticate gh on this workstation'
fi
if [[ -d /dev/shm && -w /dev/shm ]]; then
  workdir="$(mktemp -d /dev/shm/microscale-collect.XXXXXX)"
else
  workdir="$(mktemp -d)"
fi
trap 'rm -rf "$workdir"' EXIT
base=https://github.com/nghianguyen150612/MicroScale/releases/download/v0.2.1
download() {
  if command -v curl >/dev/null; then
    curl -fLsS --connect-timeout 15 --max-time 180 -o "$1" "$2"
  elif command -v wget >/dev/null; then
    wget -q -O "$1" "$2"
  else
    fail 'curl or wget required on workstation'
  fi
}
download "$workdir/install.sh" "$base/install.sh"
download "$workdir/install.sh.sha256" "$base/install.sh.sha256"
(cd "$workdir" && sha256sum -c install.sh.sha256) ||
  fail 'Installer SHA256 mismatch; refusing remote execution'
printf 'Running RAM-only %s test over SSH on %s\n' "$profile" "$target"
# Pass verified bootstrap on stdin: no installer is persisted on the target.
test_rc=0
ssh "$target" "sh -s -- test-ram $profile" < "$workdir/install.sh" || test_rc=$?
if ! ssh "$target" 'for base in /tmp /dev/shm; do
  if [ -f "$base/microscale-ram/latest.tsv" ]; then
    cat "$base/microscale-ram/latest.tsv"
    exit 0
  fi
done
exit 1' > "$workdir/device.tsv"; then
  fail 'Could not collect current-run report over SSH'
fi
bash "$root/scripts/import-report.sh" --validate-only "$workdir/device.tsv" ||
  fail 'Device report rejected; nothing uploaded'
printf 'Validated report from %s:\n' "$target"
cat "$workdir/device.tsv"
if [[ "$submit" == true ]]; then
  bash "$root/scripts/import-report.sh" --submit "$workdir/device.tsv"
  printf 'Report submitted as a reviewable GitHub PR.\n'
else
  printf 'To upload this report into the repository, rerun with --submit.\n'
fi
if [[ "$test_rc" -ne 0 ]]; then
  printf 'Device smoke test returned status %s; inspect results.\n' "$test_rc" >&2
  exit 1
fi
