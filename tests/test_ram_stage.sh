#!/usr/bin/env bash
set -Eeuo pipefail

sh -n scripts/manager.sh
sh scripts/manager.sh help | grep -q 'install-ram'
sh scripts/manager.sh help | grep -q 'apply'

# This is a fixture-run manager with substituted RAM paths and mocked NAND
# commit. No network, /usr, /etc or Tailscale state is ever touched.
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
printf '#!/bin/sh\nprintf "test-binary\\n"\n' > "$fixture/mockbin"
chmod 700 "$fixture/mockbin"
awk -v dir="$fixture" '
    /^operation=""$/ {
        print "RAM_ROOT=\"" dir "/ram\""
        print "require_ram_platform() { :; }"
        print "require_platform() { :; }"
        print "runtime_arch() { echo arm64; }"
        print "ensure_command_available() { :; }"
        print "ask() { answer=y; }"
        print "prepare_stage() { STAGE=\"$(mktemp -d \"" dir "/tx.XXXXXX\")\"; }"
        print "download_binary() { cp \"" dir "/mockbin\" \"$STAGE/microscale\"; }"
        print "nand_commit() { cp \"$1\" \"" dir "/applied\"; printf \"%s\\n\" \"$2\" > \"" dir "/profile\"; }"
    }
    { print }
' scripts/manager.sh > "$fixture/manager.sh"
chmod 700 "$fixture/manager.sh"

sh "$fixture/manager.sh" ram-status | grep -q 'none'
sh "$fixture/manager.sh" install-ram micro
test -f "$fixture/ram/microscale"
test -f "$fixture/ram/manifest"
test -L "$fixture/ram/bin/tailscale"
test -L "$fixture/ram/bin/tailscaled"
sh "$fixture/manager.sh" ram-status | grep -q 'micro /'
test ! -f "$fixture/applied"

# Applying is a separate interaction and uses exactly the staged binary.
sh "$fixture/manager.sh" apply
cmp "$fixture/mockbin" "$fixture/applied"
grep -Fxq 'micro' "$fixture/profile"

# A modified stage cannot be applied.
printf 'tampered\n' >> "$fixture/ram/microscale"
sh "$fixture/manager.sh" ram-status | grep -q 'invalid'
rm -f "$fixture/applied"
if sh "$fixture/manager.sh" apply >/dev/null 2>&1; then
    echo 'FAIL: applying a corrupted RAM stage was accepted' >&2
    exit 1
fi
test ! -f "$fixture/applied"

# The actual code path must use a verified RAM snapshot, not a new download.
apply_fn="$(sed -n '/^apply_ram() {/,/^}/p' scripts/manager.sh)"
grep -q 'ram_stage_ready' <<< "$apply_fn"
grep -q 'cp "$RAM_ROOT/microscale"' <<< "$apply_fn"
grep -q 'nand_commit' <<< "$apply_fn"
if grep -Eq 'download_binary|tailscale up|service .*restart' <<< "$apply_fn"; then
    echo 'FAIL: apply redownloads or configures Tailscale' >&2
    exit 1
fi

echo 'PASS: RAM stage → verified NAND apply fixture, tamper rejection and no system writes'
