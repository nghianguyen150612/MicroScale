#!/bin/sh
# Smoke tests only. They do not prove VPN login or Exit Node functionality.
set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 {safe|small|extreme} ARCH OUTPUT_DIR" >&2
    exit 2
fi
profile=$1
arch=$2
root=$3
case "$root" in
    /*) ;;
    *) root=$PWD/$root ;;
esac
dir="$root/$profile"
[ -f "$dir/tailscale.combined" ] || exit 1
[ -L "$dir/tailscale" ] && [ -L "$dir/tailscaled" ] || {
    echo "Missing combined-binary symlinks" >&2; exit 1
}

(
    cd "$dir"
    sha256sum -c SHA256SUMS
)
file "$dir/tailscale.combined"
case "$arch" in
    arm64)
        file "$dir/tailscale.combined" | grep -Eqi 'aarch64|arm64' || exit 1
        runner=qemu-aarch64
        ;;
    amd64)
        file "$dir/tailscale.combined" | grep -Eqi 'x86-64|x86_64' || exit 1
        runner=
        ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 2 ;;
esac

if [ -n "$runner" ]; then
    command -v "$runner" >/dev/null 2>&1 || {
        echo "QEMU is required to smoke-test foreign architecture" >&2
        exit 1
    }
    timeout 45 "$runner" "$dir/tailscale" version
    timeout 45 "$runner" "$dir/tailscale" --help >/dev/null
    timeout 45 "$runner" "$dir/tailscaled" --help >/dev/null
else
    timeout 45 "$dir/tailscale" version
    timeout 45 "$dir/tailscale" --help >/dev/null
    timeout 45 "$dir/tailscaled" --help >/dev/null
fi
echo "PASS: $profile/$arch CLI smoke tests"
