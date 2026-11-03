#!/usr/bin/env bash
set -Eeuo pipefail
bash -n scripts/deploy-openwrt.sh
sh -n scripts/router-transaction.sh
# Any unknown/non-LAN destination must be rejected before SSH/network access.
if bash scripts/deploy-openwrt.sh preflight root@203.0.113.1 >/dev/null 2>&1; then
  echo "FAIL: invalid router destination accepted" >&2
  exit 1
fi
echo "PASS: install scripts parse and reject non-local destination"
