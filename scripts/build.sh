#!/bin/sh
# Build one self-contained MicroScale profile from a pinned Tailscale checkout.
set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 {safe|small|extreme} UPSTREAM_DIR OUTPUT_DIR" >&2
    exit 2
fi
profile=$1
case "$profile" in
    safe|small|extreme) ;;
    *) echo "Invalid profile: $profile" >&2; exit 2 ;;
esac

upstream=$(cd "$2" && pwd)
case "$3" in
    /*) out_root=$3 ;;
    *) out_root=$PWD/$3 ;;
esac

arch=${GOARCH:-arm64}
case "$arch" in
    arm64|amd64) ;;
    *) echo "Unsupported GOARCH: $arch" >&2; exit 2 ;;
esac

[ -x "$upstream/build_dist.sh" ] || {
    echo "Missing executable upstream/build_dist.sh" >&2
    exit 1
}
mkdir -p "$out_root/$profile"
target="$out_root/$profile/tailscale.combined"

# Build flags are intentionally verified against pinned Tailscale v1.104.4.
# Safe includes all features; Small/Extreme use upstream's extra-small feature set.
if [ "$profile" = safe ]; then
    set -- --box --strip
else
    set -- --box --extra-small
fi

(
    cd "$upstream"
    CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
        ./build_dist.sh "$@" -o "$target" ./cmd/tailscaled
)
prepack=$(stat -c '%s' "$target")

if [ "$profile" = extreme ]; then
    command -v upx >/dev/null 2>&1 || {
        echo "Extreme requires UPX; refusing to substitute an unpacked binary" >&2
        exit 1
    }
    upx --best --lzma "$target"
    upx -t "$target"
fi

chmod 755 "$target"
ln -sfn tailscale.combined "$out_root/$profile/tailscale"
ln -sfn tailscale.combined "$out_root/$profile/tailscaled"

(
    cd "$out_root/$profile"
    sha256sum tailscale.combined > SHA256SUMS
)

postpack=$(stat -c '%s' "$target")
printf 'profile\tarch\tbytes_before_upx\tbytes_final\n%s\t%s\t%s\t%s\n' \
    "$profile" "$arch" "$prepack" "$postpack" > "$out_root/$profile/metrics.tsv"

archive="$out_root/microscale-$profile-linux-$arch.tar.gz"
tar -czf "$archive" -C "$out_root/$profile" \
    tailscale.combined tailscale tailscaled SHA256SUMS metrics.tsv

(
    cd "$out_root"
    sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256"
)

printf 'Built %s (%s): %s bytes -> %s bytes\n' \
    "$profile" "$arch" "$prepack" "$postpack"
printf 'Archive: %s\n' "$archive"
