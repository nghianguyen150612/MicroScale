#!/usr/bin/env bash
set -Eeuo pipefail

sh -n scripts/manager.sh
sh scripts/manager.sh help | grep -q 'install-ram'
sh scripts/manager.sh help | grep -q 'apply'

# Entire fixture uses temporary paths, never actual /usr or /etc.
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
sed "s|^RAM_ROOT=/tmp/microscale-stage$|RAM_ROOT=$fixture/staged|" \
    scripts/manager.sh > "$fixture/manager.sh"
chmod 700 "$fixture/manager.sh"

sh "$fixture/manager.sh" ram-status | grep -q 'none'
mkdir -p "$fixture/staged/bin"
printf 'fixture-binary-only\n' > "$fixture/staged/microscale"
chmod 700 "$fixture/staged/microscale"
cp "$fixture/manager.sh" "$fixture/staged/manager.sh"
chmod 700 "$fixture/staged/manager.sh"
ln -s ../microscale "$fixture/staged/bin/tailscale"
ln -s ../microscale "$fixture/staged/bin/tailscaled"
ln -s ../manager.sh "$fixture/staged/bin/microscale"

case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo 'Unsupported fixture host architecture' >&2; exit 1 ;;
esac
digest="$(sha256sum "$fixture/staged/microscale" | awk '{print $1}')"
printf 'profile=micro\narch=%s\nrelease=v0.2.0-rc.7\nsha256=%s\n' \
    "$arch" "$digest" > "$fixture/staged/manifest"
sh "$fixture/manager.sh" ram-status | grep -q 'micro /'
# Corrupted staged file must fail integrity checks and not be eligible for apply.
printf 'tampered\n' >> "$fixture/staged/microscale"
sh "$fixture/manager.sh" ram-status | grep -q 'invalid'
if sh "$fixture/manager.sh" apply >/dev/null 2>&1; then
    echo 'FAIL: applying a corrupted RAM stage was accepted' >&2
    exit 1
fi

# Apply must consume the RAM snapshot, never fetch a fresh profile or start services.
apply_fn="$(sed -n '/^apply_ram() {/,/^}/p' scripts/manager.sh)"
grep -q 'ram_stage_ready' <<< "$apply_fn"
grep -q 'cp "$RAM_ROOT/microscale"' <<< "$apply_fn"
grep -q 'nand_commit' <<< "$apply_fn"
if grep -Eq 'download_binary|tailscale up|service .*restart' <<< "$apply_fn"; then
    echo 'FAIL: apply redownloads or configures Tailscale' >&2
    exit 1
fi

echo 'PASS: RAM stage manifest verification, corruption rejection and apply gating'
