#!/bin/sh
# Read-only smoke tests of release executables staged entirely in tmpfs.
# No service control, Tailscale state access, routing, or NAND installation.
set -eu
umask 077

RELEASE_TAG=v0.2.0-rc.4
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
for dep in awk grep tar sha256sum wc date df mkdir; do
    command -v "$dep" >/dev/null 2>&1 || fail "Missing command: $dep"
done

root="$ram_base/microscale-ram"
mkdir -p "$root"
report="$root/results.tsv"
if [ ! -f "$report" ]; then
    printf 'utc\tplatform\tarch\tprofile\trelease\telf_bytes\tram_total_kib\tram_available_kib\tcli_version\tdaemon_version\tcli_help\tcli_peak_rss_kib\tcli_elapsed_s\tresult\n' > "$report"
fi
if [ -f /etc/openwrt_release ]; then platform=openwrt; else platform=linux; fi
ram_total="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
ram_avail="$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo)"
[ -n "$ram_total" ] || ram_total=NA
[ -n "$ram_avail" ] || ram_avail=NA

run_one() {
    profile="$1"
    dir="$root/$arch-$profile"
    mkdir -p "$dir"
    asset="microscale-$profile-linux-$arch.tar.gz"
    base="https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG"
    printf '\n[%s/%s] Downloading to RAM: %s\n' "$arch" "$profile" "$asset"

    fetch "$dir/$asset" "$base/$asset" || fail "Failed to download $asset"
    fetch "$dir/$asset.sha256" "$base/$asset.sha256" || fail "Missing checksum for $asset"
    (cd "$dir" && sha256sum -c "$asset.sha256") || fail "Archive checksum failed: $asset"

    (cd "$dir" && tar -xzf "$asset") || fail "Cannot extract $asset"
    [ -f "$dir/microscale" ] || fail "Executable not present: $asset"
    [ -f "$dir/build-info.txt" ] || fail "Missing build metadata"
    grep -Fx "Target: linux/$arch" "$dir/build-info.txt" >/dev/null ||
        fail "Architecture mismatch in $asset"
    grep -Fx "MicroScale profile: $profile" "$dir/build-info.txt" >/dev/null ||
        fail "Profile mismatch in $asset"
    (cd "$dir" && sha256sum -c SHA256SUMS) || fail "Executable hash mismatch"
    chmod 700 "$dir/microscale"
    elf_bytes="$(wc -c < "$dir/microscale" | tr -d ' ')"

    cli_version=fail
    daemon_version=fail
    cli_help=fail
    if TS_BE_CLI=1 "$dir/microscale" version >/dev/null 2>&1; then cli_version=ok; fi
    if "$dir/microscale" --version >/dev/null 2>&1; then daemon_version=ok; fi
    if TS_BE_CLI=1 "$dir/microscale" --help >/dev/null 2>&1; then cli_help=ok; fi

    peak=NA
    elapsed=NA
    if [ -x /usr/bin/time ] && command -v env >/dev/null 2>&1; then
        if /usr/bin/time -f '%M %e' -o "$dir/time.txt" \
            env TS_BE_CLI=1 "$dir/microscale" version >/dev/null 2>&1; then
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
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$utc" "$platform" "$arch" "$profile" "$RELEASE_TAG" \
        "$elf_bytes" "$ram_total" "$ram_avail" \
        "$cli_version" "$daemon_version" "$cli_help" "$peak" "$elapsed" "$result" >> "$report"
    printf '%s: %s (ELF: %s bytes, CLI RSS peak: %s KiB)\n' \
        "$profile" "$result" "$elf_bytes" "$peak"
    [ "$result" = PASS ]
}

selection=""
if [ "$#" -gt 0 ]; then selection="$1"; fi
if [ "$selection" = "--help" ] || [ "$selection" = "-h" ]; then
    printf 'Usage: sh ram-test.sh [small|micro|extreme|all]\n'
    exit 0
fi
if [ -z "$selection" ]; then
    printf 'Choose RAM test: 1) Small  2) Micro  3) Extreme  4) All: '
    IFS= read -r answer </dev/tty || fail 'Provide a profile argument'
    case "$answer" in 1) selection=small ;; 2) selection=micro ;;
        3) selection=extreme ;; 4) selection=all ;; *) fail 'Invalid selection' ;; esac
fi

printf 'RAM tmpfs: %s | architecture: %s | release: %s\n' "$root" "$arch" "$RELEASE_TAG"
case "$selection" in
    small|micro|extreme) run_one "$selection" ;;
    all)
        failed=0
        for p in small micro extreme; do run_one "$p" || failed=1; done
        [ "$failed" -eq 0 ] || fail 'One or more smoke tests failed'
        ;;
    *) fail 'Choose small, micro, extreme or all' ;;
esac
printf '\nSanitized report (RAM): %s\n' "$report"
printf 'No system binary, service, VPN state, or network configuration was changed.\n'
