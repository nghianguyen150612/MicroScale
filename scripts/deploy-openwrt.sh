#!/usr/bin/env bash
# Host-side Arch/Linux deployment with persistent backup and local-LAN-only guard.
set -Eeuo pipefail
fail() { echo "MicroScale deploy: ERROR: $*" >&2; exit 1; }
usage() {
 cat >&2 <<'USAGE'
Usage:
  scripts/deploy-openwrt.sh preflight root@192.168.3.1
  CONFIRM_LOCAL_LAN=YES scripts/deploy-openwrt.sh apply root@192.168.3.1 BINARY PROFILE
  CONFIRM_LOCAL_LAN=YES scripts/deploy-openwrt.sh restore root@192.168.3.1 BACKUP_DIRECTORY

PROFILE is safe, small or extreme. Small/Extreme additionally require
ALLOW_UNQUALIFIED_PROFILE=YES and local recovery that does not depend on Tailscale.
USAGE
 exit 2
}
[[ $# -ge 2 ]] || usage
action="$1"
target="$2"
[[ "$target" == root@192.168.3.1 ]] || fail "only verified NR3053 target root@192.168.3.1 is supported"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
router_script="$root/scripts/router-transaction.sh"
[[ -f "$router_script" ]] || fail "missing router transaction helper"
for cmd in ssh ip sha256sum; do command -v "$cmd" >/dev/null || fail "missing $cmd"; done
route="$(ip -4 route get 192.168.3.1)" || fail "no route"
case "$route" in
  *" via "*|*" dev tailscale"*|*" dev tun"*|*" dev wg"*)
    fail "router reachable only via gateway/tunnel; use direct local LAN"
    ;;
esac
ssh_options=(-o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=3)
remote() { ssh "${ssh_options[@]}" "$target" "$@"; }
stage="/tmp/microscale-deploy"
remote "mkdir -p '$stage'"
remote "cat > '$stage/router-transaction.sh'" < "$router_script"
remote "chmod 700 '$stage/router-transaction.sh'"
if [[ "$action" == preflight ]]; then
  remote "sh '$stage/router-transaction.sh' preflight '$stage'"
  exit
fi
[[ "${CONFIRM_LOCAL_LAN:-}" == YES ]] || fail "set CONFIRM_LOCAL_LAN=YES only after testing direct-LAN SSH"
if [[ "$action" == apply ]]; then
  [[ $# -eq 4 ]] || usage
  binary="$(realpath "$3")"
  profile="$4"
  case "$profile" in safe) ;; small|extreme)
    [[ "${ALLOW_UNQUALIFIED_PROFILE:-}" == YES ]] ||
      fail "$profile is not device-qualified; set ALLOW_UNQUALIFIED_PROFILE=YES to explicitly test it"
    ;; *) fail "invalid profile";; esac
  [[ -f "$binary" && -x "$binary" ]] || fail "missing executable $binary"
  command -v readelf >/dev/null || fail "readelf required"
  readelf -h "$binary" | grep -q 'Machine:[[:space:]]*AArch64' ||
    fail "binary is not ARM64 ELF"
  remote "sh '$stage/router-transaction.sh' preflight '$stage'"
  bytes="$(stat -c '%s' "$binary")"
  needed_kib=$(( (bytes + 1023)/1024 + 8192 ))
  available_kib="$(remote "df -k /overlay | awk 'NR==2 {print \$4}'")"
  [[ "$available_kib" =~ ^[0-9]+$ ]] || fail "cannot read overlay free space"
  (( available_kib > needed_kib )) ||
    fail "not enough overlay space for atomic install + reserve ($available_kib KiB, require >$needed_kib KiB)"
  backup_base="${MICROSCALE_BACKUP_DIR:-$HOME/.local/share/microscale/backups}"
  backup_dir="$backup_base/$(date -u +%Y%m%dT%H%M%SZ)"
  umask 077
  mkdir -p "$backup_dir"
  remote 'cat /usr/sbin/tailscaled' > "$backup_dir/tailscaled"
  remote 'cat /usr/bin/tailscale' > "$backup_dir/tailscale"
  remote 'cat /etc/init.d/tailscale' > "$backup_dir/init.d.tailscale"
  remote 'tailscale version' > "$backup_dir/version.txt"
  sha256sum "$backup_dir/tailscaled" "$backup_dir/tailscale" > "$backup_dir/SHA256SUMS"
  remote "cat > '$stage/candidate'" < "$binary"
  expected="$(sha256sum "$binary" | awk '{print $1}')"
  observed="$(remote "sha256sum '$stage/candidate' | awk '{print \$1}'")"
  [[ "$expected" == "$observed" ]] || fail "upload checksum mismatch"
  remote "chmod 755 '$stage/candidate'"
  # Verify new binary can start without touching the running service.
  remote "TS_BE_CLI=1 '$stage/candidate' version && '$stage/candidate' --version"
  echo "Persistent original binaries saved to $backup_dir"
  if ! remote "sh '$stage/router-transaction.sh' apply '$stage'"; then
    echo "Installer reported failure. Original binaries are saved at: $backup_dir" >&2
    exit 1
  fi
  remote "sh '$stage/router-transaction.sh' check '$stage'" ||
    fail "post-deploy health failed; run restore using $backup_dir from direct LAN"
  echo "BASIC HEALTH PASSED; verify Exit Node/subnet/DNS/SSH/dataplane and reboot persistence manually."
elif [[ "$action" == restore ]]; then
  [[ $# -eq 3 ]] || usage
  backup_dir="$(realpath "$3")"
  ( cd "$backup_dir" && sha256sum -c SHA256SUMS ) ||
    fail "backup checksum failed"
  remote "cat > '$stage/rollback.tailscaled'" < "$backup_dir/tailscaled"
  remote "cat > '$stage/rollback.tailscale'" < "$backup_dir/tailscale"
  remote "sh '$stage/router-transaction.sh' restore '$stage'"
  remote "sh '$stage/router-transaction.sh' check '$stage'"
else
  usage
fi
