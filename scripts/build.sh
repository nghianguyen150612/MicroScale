#!/usr/bin/env bash
set -Eeuo pipefail

fail() { printf 'build.sh: ERROR: %s\n' "$*" >&2; exit 1; }
trap 'status=$?; printf "build.sh: failed at line %s (exit %s): %s\n" "$LINENO" "$status" "$BASH_COMMAND" >&2; exit "$status"' ERR

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-small}"
case "$profile" in small|micro|extreme) ;; *) fail "profile must be small, micro or extreme";; esac
profile_file="$repo_root/profiles/$profile.env"
[[ -f "$profile_file" ]] || fail "missing $profile_file"
# Profiles are trusted repo-controlled shell configuration.
# shellcheck disable=SC1090
source "$profile_file"
: "${UPSTREAM_REPOSITORY:?}"
: "${UPSTREAM_VERSION:?}"
: "${UPSTREAM_COMMIT:?}"

target_goos="${TARGET_GOOS:-linux}"
target_goarch="${TARGET_GOARCH:-arm64}"
[[ "$target_goos" == linux ]] || fail "target OS must be linux"
case "$target_goarch" in amd64|arm64) ;; *) fail "unsupported GOARCH $target_goarch";; esac
[[ "${CGO_ENABLED:-0}" == 0 ]] || fail "CGO must be disabled"
unset TAGS

build_root="${MICROSCALE_BUILD_DIR:-$repo_root/.build}"
upstream_dir="$build_root/tailscale-$UPSTREAM_VERSION"
mkdir -p "$build_root"
if [[ ! -d "$upstream_dir/.git" ]]; then
  git init "$upstream_dir" >&2
  git -C "$upstream_dir" remote add origin "$UPSTREAM_REPOSITORY"
fi
git -C "$upstream_dir" fetch --depth=1 origin "refs/tags/$UPSTREAM_VERSION"
git -C "$upstream_dir" checkout --detach FETCH_HEAD
actual_commit="$(git -C "$upstream_dir" rev-parse HEAD)"
[[ "$actual_commit" == "$UPSTREAM_COMMIT" ]] ||
  fail "upstream pin mismatch (expected $UPSTREAM_COMMIT, got $actual_commit)"

output_dir="$repo_root/dist/$profile/$target_goos-$target_goarch"
mkdir -p "$output_dir"
binary="$output_dir/microscale"
if [[ "$profile" == small ]]; then
  build_args=(--box --strip)
else
  # Reduced features require target-device validation.
  build_args=(--box --extra-small)
fi
(
  cd "$upstream_dir"
  CGO_ENABLED=0 GOOS="$target_goos" GOARCH="$target_goarch" TS_USE_TOOLCHAIN=1 \
    ./build_dist.sh "${build_args[@]}" -o "$binary" ./cmd/tailscaled
)
unpacked_bytes="$(stat -c '%s' "$binary")"
if [[ "$profile" == extreme ]]; then
  command -v upx >/dev/null || fail "Extreme requires UPX (never silently skip packing)"
  upx --best --lzma "$binary"
  upx -t "$binary"
fi
chmod 0755 "$binary"
final_bytes="$(stat -c '%s' "$binary")"
cp "$upstream_dir/LICENSE" "$output_dir/Tailscale-LICENSE"
cat > "$output_dir/build-info.txt" <<INFO
MicroScale profile: $profile
Upstream: $UPSTREAM_REPOSITORY
Upstream version: $UPSTREAM_VERSION
Upstream commit: $actual_commit
Target: $target_goos/$target_goarch
CGO_ENABLED: 0
Combined CLI/daemon: yes (--box/ts_include_cli)
Build flags: ${build_args[*]}
UPX: $(if [[ "$profile" == extreme ]]; then echo yes; else echo no; fi)
Feature qualification: NOT COMPLETE for NR3053
INFO
printf 'profile\tarch\tbefore_upx_bytes\telf_bytes\n%s\t%s\t%s\t%s\n' \
 "$profile" "$target_goarch" "$unpacked_bytes" "$final_bytes" > "$output_dir/size.tsv"
(
 cd "$output_dir"
 sha256sum microscale > SHA256SUMS
 tar -czf "microscale-$profile-linux-$target_goarch.tar.gz" \
    microscale Tailscale-LICENSE build-info.txt SHA256SUMS size.tsv
 sha256sum "microscale-$profile-linux-$target_goarch.tar.gz" > "ARCHIVE.SHA256"
)
printf 'Build %s/%s: %s bytes ELF; %s bytes archive\n' \
 "$profile" "$target_goarch" "$final_bytes" \
 "$(stat -c '%s' "$output_dir/microscale-$profile-linux-$target_goarch.tar.gz")"
