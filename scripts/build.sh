#!/usr/bin/env bash
set -Eeuo pipefail

fail() { printf 'build.sh: ERROR: %s\n' "$*" >&2; exit 1; }
trap 'status=$?; printf "build.sh: ERROR: command failed at line %s (exit %s): %s\n" "$LINENO" "$status" "$BASH_COMMAND" >&2; exit "$status"' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-safe}"
profile_file="$repo_root/profiles/${profile}.env"
[[ -f "$profile_file" ]] || fail "unknown profile '$profile' (expected profiles/<name>.env)"
# Profiles are trusted repository configuration files containing shell assignments.
# shellcheck disable=SC1090
source "$profile_file"

: "${UPSTREAM_REPOSITORY:?profile must define UPSTREAM_REPOSITORY}"
: "${UPSTREAM_VERSION:?profile must define UPSTREAM_VERSION}"
: "${UPSTREAM_COMMIT:?profile must define UPSTREAM_COMMIT}"
target_goos="${TARGET_GOOS:-${PROFILE_TARGET_GOOS:-linux}}"
target_goarch="${TARGET_GOARCH:-${PROFILE_TARGET_GOARCH:-arm64}}"
cgo_enabled="${CGO_ENABLED:-${PROFILE_CGO_ENABLED:-0}}"
build_tags="${BUILD_TAGS:-${PROFILE_BUILD_TAGS:-ts_include_cli}}"
[[ "$cgo_enabled" == 0 ]] || fail "CGO_ENABLED must be 0 for the Safe profile"
[[ "$build_tags" == ts_include_cli ]] || fail "Safe profile requires only ts_include_cli; feature omission tags are not allowed"

build_root="${MICROSCALE_BUILD_DIR:-$repo_root/.build}"
upstream_dir="$build_root/tailscale-$UPSTREAM_VERSION"
mkdir -p "$build_root"
if [[ ! -d "$upstream_dir/.git" ]]; then
  rm -rf "$upstream_dir"
  git init "$upstream_dir" >&2
  git -C "$upstream_dir" remote add origin "$UPSTREAM_REPOSITORY"
fi
printf 'Fetching upstream Tailscale %s...\n' "$UPSTREAM_VERSION"
git -C "$upstream_dir" fetch --depth=1 origin "refs/tags/$UPSTREAM_VERSION"
git -C "$upstream_dir" checkout --detach FETCH_HEAD
actual_commit="$(git -C "$upstream_dir" rev-parse HEAD)"
[[ "$actual_commit" == "$UPSTREAM_COMMIT" ]] || fail "upstream pin mismatch: expected $UPSTREAM_COMMIT, got $actual_commit"

output_dir="$repo_root/dist/$profile/$target_goos-$target_goarch"
binary="$output_dir/microscale"
mkdir -p "$output_dir"
printf 'Building combined CLI + daemon: %s/%s, CGO_ENABLED=%s, tags=%s\n' "$target_goos" "$target_goarch" "$cgo_enabled" "$build_tags"
(
  cd "$upstream_dir"
  CGO_ENABLED="$cgo_enabled" GOOS="$target_goos" GOARCH="$target_goarch" \
    TAGS="$build_tags" TS_USE_TOOLCHAIN=1 \
    ./build_dist.sh --strip -o "$binary" ./cmd/tailscaled
)
chmod 0755 "$binary"
cp "$upstream_dir/LICENSE" "$output_dir/Tailscale-LICENSE"
cat > "$output_dir/build-info.txt" <<INFO
MicroScale version: $(cat "$repo_root/VERSION")
Upstream: $UPSTREAM_REPOSITORY
Upstream version: $UPSTREAM_VERSION
Upstream commit: $actual_commit
Target: $target_goos/$target_goarch
CGO_ENABLED: $cgo_enabled
Build tags: $build_tags
Build mode: upstream combined CLI + daemon (ts_include_cli)
INFO
printf 'Built %s (%s bytes)\n' "$binary" "$(stat -c '%s' "$binary")"
