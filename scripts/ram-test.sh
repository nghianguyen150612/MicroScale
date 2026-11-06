#!/bin/sh
# Read-only smoke tests of release executables staged entirely in tmpfs.
# No service control, Tailscale state access, routing, or NAND installation.
set -eu
umask 077

RELEASE_TAG=v0.2.1
REPOSITORY=nghianguyen150612/MicroScale

fail() { printf 'MicroScale RAM test: %s\n' "$*" >&2; exit 1; }
fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fLsS --connect-timeout 15 --max-time 180 -o "$1" "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$1" "$2"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -O "$1" "$2"
    else
        fail 'HTTPS downloader required (curl, wget or uclient-fetch)'
    fi
}
is_tmpfs() {
    awk -v path="$1" '$2 == path && $3 == "tmpfs" { ok=1 } END { exit !ok }' /proc/mounts
}
case "$(uname -m)" in
    aarch64|arm64) arch=arm64 ;;
    x86_64|amd64) arch=amd64 ;;
    *) fail "Unsupported CPU: $(uname -m). Use arm64 or x86_64." ;;
esac
if is_tmpfs /tmp; then
    ram_base=/tmp
elif is_tmpfs /dev/shm; then
    ram_base=/dev/shm
else
    fail 'No verified tmpfs at /tmp or /dev/shm; refusing disk writes'
fi
for dep in awk grep tar sha256sum wc date df mkdir ln; do
    command -v "$dep" >/dev/null 2>&1 || fail "Missing command: $dep"
done

root="$ram_base/microscale-ram"
[ ! -L "$root" ] || fail "Refusing symlinked report directory"
mkdir -p "$root"
report="$root/results.tsv"
[ ! -L "$report" ] || fail "Refusing symlinked report file"
latest="$root/latest.tsv"
[ ! -L "$latest" ] || fail "Refusing symlinked latest report"
if [ ! -f "$report" ]; then
    printf 'utc\tplatform\tarch\tprofile\trelease\telf_bytes\tram_total_kib\tram_available_kib\tcli_version\tdaemon_version\tcli_help\tcli_peak_rss_kib\tcli_elapsed_s\tresult\n' > "$report"
fi
printf 'utc\tplatform\tarch\tprofile\trelease\telf_bytes\tram_total_kib\tram_available_kib\tcli_version\tdaemon_version\tcli_help\tcli_peak_rss_kib\tcli_elapsed_s\tresult\n' > "$latest"
if [ -f /etc/openwrt_release ]; then platform=openwrt; else platform=linux; fi
ram_total="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
ram_avail="$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo)"
[ -n "$ram_total" ] || ram_total=NA
[ -n "$ram_avail" ] || ram_avail=NA

run_one() {
    profile="$1"
    dir="$root/$arch-$profile"
    [ ! -L "$dir" ] || fail "Refusing symlinked binary test directory"
    mkdir -p "$dir"
    asset="microscale-$profile-linux-$arch.tar.gz"
    base="https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG"
    printf '\n[%s/%s] Downloading to RAM: %s\n' "$arch" "$profile" "$asset"

    if [ "$mode" = staged ]; then
        stage=/tmp/microscale-stage
        is_tmpfs /tmp || fail "Staged test requires RAM-backed /tmp"
        [ -d "$stage" ] && [ ! -L "$stage" ] || fail "Missing RAM stage"
        [ -f "$stage/microscale" ] && [ -f "$stage/manifest" ] ||
            fail "RAM stage incomplete"
        stage_arch="$(sed -n 's/^arch=//p' "$stage/manifest")"
        stage_version="$(sed -n 's/^release=//p' "$stage/manifest")"
        stage_profile="$(sed -n 's/^profile=//p' "$stage/manifest")"
        stage_sha="$(sed -n 's/^sha256=//p' "$stage/manifest")"
        [ "$stage_arch" = "$arch" ] && [ "$stage_version" = "$RELEASE_TAG" ] &&
        [ "$stage_profile" = "$profile" ] && [ -n "$stage_sha" ] ||
            fail "RAM stage profile/architecture/release mismatch"
        [ "$(sha256sum "$stage/microscale" | awk '{print $1}')" = "$stage_sha" ] ||
            fail "RAM-stage checksum mismatch"
        for name in tailscale tailscaled; do
            [ -L "$stage/bin/$name" ] &&
            [ "$(readlink "$stage/bin/$name")" = ../microscale ] ||
                fail "RAM stage CLI/daemon link mismatch"
        done
        cli="$stage/bin/tailscale"
        daemon="$stage/bin/tailscaled"
        elf_bytes="$(wc -c < "$stage/microscale" | tr -d ' ')"
    else
        fetch "$dir/$asset" "$base/$asset" || fail "Failed to download $asset"
        fetch "$dir/$asset.sha256" "$base/$asset.sha256" || fail "Missing checksum for $asset"
        (cd "$dir" && sha256sum -c "$asset.sha256") || fail "Archive checksum failed: $asset"
        tar -tzf "$dir/$asset" | awk '
           $0 !~ /^(microscale|Tailscale-LICENSE|build-info.txt|SHA256SUMS|size.tsv)$/ {bad=1}
           END {exit bad}
        ' || fail "Unsafe archive content"
        (cd "$dir" && tar -xzf "$asset") || fail "Cannot extract $asset"
        [ -f "$dir/microscale" ] && [ -f "$dir/build-info.txt" ] || fail "Incomplete archive"
        grep -Fx "Target: linux/$arch" "$dir/build-info.txt" >/dev/null || fail "Architecture mismatch"
        grep -Fx "MicroScale profile: $profile" "$dir/build-info.txt" >/dev/null || fail "Profile mismatch"
        (cd "$dir" && sha256sum -c SHA256SUMS) || fail "Executable checksum FAILED"
        chmod 700 "$dir/microscale"
        ln -sf microscale "$dir/tailscale"
        ln -sf microscale "$dir/tailscaled"
        cli="$dir/tailscale"
        daemon="$dir/tailscaled"
        elf_bytes="$(wc -c < "$dir/microscale" | tr -d ' ')"
    fi

    cli_version=fail
    daemon_version=fail
    cli_help=fail
    if "$cli" version >/dev/null 2>&1; then cli_version=ok; fi
    if "$daemon" --version >/dev/null 2>&1; then daemon_version=ok; fi
    if "$cli" --help >/dev/null 2>&1; then cli_help=ok; fi

    peak=NA
    elapsed=NA
    if [ -x /usr/bin/time ] && command -v env >/dev/null 2>&1; then
        if /usr/bin/time -f '%M %e' -o "$dir/time.txt" \
            env "$cli" version >/dev/null 2>&1; then
            read peak elapsed < "$dir/time.txt" || true
            [ -n "$peak" ] || peak=NA
            [ -n "$elapsed" ] || elapsed=NA
        fi
    fi

    result=FAIL
    if [ "$cli_version" = ok ] && [ "$daemon_version" = ok ] &&
       [ "$cli_help" = ok ]; then
        result=PASS
    fi
    utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    line="$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
        "$utc" "$platform" "$arch" "$profile" "$RELEASE_TAG" \
        "$elf_bytes" "$ram_total" "$ram_avail" \
        "$cli_version" "$daemon_version" "$cli_help" "$peak" "$elapsed" "$result")"
    printf '%s\n' "$line" >> "$report"
    printf '%s\n' "$line" >> "$latest"
    printf '%s: %s (ELF: %s bytes, CLI RSS peak: %s KiB)\n' \
        "$profile" "$result" "$elf_bytes" "$peak"
    [ "$result" = PASS ]
}

selection=""
if [ "$#" -gt 0 ]; then selection="$1"; fi
if [ "$selection" = "--help" ] || [ "$selection" = "-h" ]; then
    printf 'Usage: sh ram-test.sh [small|micro|extreme|all|staged]\n'
    exit 0
fi
mode=release
if [ -z "$selection" ]; then
    printf 'RAM test: 1) Small  2) Micro  3) Extreme  4) All  5) Staged: '
    IFS= read -r answer </dev/tty || fail 'Provide a profile argument'
    case "$answer" in 1) selection=small ;; 2) selection=micro ;;
        3) selection=extreme ;; 4) selection=all ;;
        5) selection=staged ;; *) fail 'Invalid selection' ;; esac
fi

printf 'RAM tmpfs: %s | architecture: %s | release: %s\n' "$root" "$arch" "$RELEASE_TAG"
case "$selection" in
    small|micro|extreme) run_one "$selection" ;;
    staged)
        mode=staged
        [ -r /tmp/microscale-stage/manifest ] || fail "No RAM stage to test"
        staged_profile="$(sed -n 's/^profile=//p' /tmp/microscale-stage/manifest)"
        case "$staged_profile" in small|micro|extreme) ;; *) fail "Invalid RAM stage profile" ;; esac
        run_one "$staged_profile" ;;
    all)
        failed=0
        for p in small micro extreme; do run_one "$p" || failed=1; done
        [ "$failed" -eq 0 ] || fail 'One or more smoke tests failed'
        ;;
    *) fail 'Choose small, micro, extreme or all' ;;
esac
printf '\nCurrent-run report: %s\n' "$latest"
printf 'Cumulative report: %s\n' "$report"
printf 'No system binary, service, VPN state, or network configuration was changed.\n'
