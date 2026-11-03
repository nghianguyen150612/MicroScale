#!/bin/sh
# MicroScale lifecycle manager. POSIX sh; never touches Tailscale config or services.
set -eu
umask 077

TAG=v0.2.0-rc.6
REPO=nghianguyen150612/MicroScale
DAEMON=/usr/sbin/tailscaled
CLI=/usr/bin/tailscale
STATE=/etc/microscale
ORIGINAL=$STATE/original
MANAGER_DIR=/usr/lib/microscale
MANAGER=$MANAGER_DIR/manager.sh
COMMAND=/usr/bin/microscale
LEGACY_STATE=/var/lib/microscale
STAGE=""
MODIFIED=0
COMMITTED=0

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
info() { printf '[INFO] %s\n' "$*"; }
fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fLsS --proto '=https' --proto-redir '=https' -o "$1" "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$1" "$2"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -O "$1" "$2"
    else
        die 'HTTPS downloader (curl/wget/uclient-fetch) required'
    fi
}
exists() { [ -e "$1" ] || [ -L "$1" ]; }
is_tmpfs() {
    awk -v path="$1" '$2==path && $3=="tmpfs" {ok=1} END{exit !ok}' /proc/mounts
}
require_platform() {
    [ "$(id -u)" = 0 ] || die 'Root required for file installation'
    case "$(uname -m)" in aarch64|arm64) ;; *) die 'Persistent installer only supports OpenWrt ARM64' ;; esac
    [ -d /overlay ] || die 'OpenWrt overlay missing; refusing to modify this host'
    [ -d /usr/sbin ] && [ -d /usr/bin ] && [ -d /usr/lib ] || die 'Missing OpenWrt binary directories'
    is_tmpfs /tmp || die '/tmp must be tmpfs for staging'
    # Older releases stored backups under /var/lib, which can be volatile on OpenWrt.
    # Never silently replace or abandon an existing RC5 rollback record.
    if [ -f "$LEGACY_STATE/install-state" ] && [ ! -f "$STATE/install-state" ]; then
        die 'Existing RC5 state detected in /var/lib/microscale; back it up and migrate before upgrading'
    fi
}
ask() {
    [ -r /dev/tty ] || die 'Interactive terminal required'
    printf '%s' "$1" > /dev/tty
    IFS= read -r answer < /dev/tty || die 'Input unavailable'
}
choose_profile() {
    selected="$1"
    if [ -z "$selected" ]; then
        info '1) Small (full features)'
        info '2) Micro (reduced features; not NR3053-qualified)'
        info '3) Extreme (reduced + UPX; experimental)'
        ask 'Profile [1/2/3]: '
        case "$answer" in
            1) selected=small ;;
            2) selected=micro ;;
            3) selected=extreme ;;
            *) die 'Invalid choice' ;;
        esac
    fi
    case "$selected" in small|micro|extreme) ;; *) die 'Unknown profile' ;; esac
}
restore_entry() {
    snapshot="$1"
    target="$2"
    if exists "$snapshot"; then
        cp -a "$snapshot" "$target.restore.$$" &&
          mv -f "$target.restore.$$" "$target" || return 1
    else
        rm -f "$target" || return 1
    fi
}
cleanup() {
    code="$1"
    trap - 0
    if [ "$code" -ne 0 ] && [ "$MODIFIED" = 1 ] && [ "$COMMITTED" = 0 ]; then
        info 'Restoring files from the RAM transaction snapshot'
        restore_entry "$STAGE/previous-daemon" "$DAEMON" ||
            info 'WARNING: Tailscale daemon rollback failed; verify manually'
        restore_entry "$STAGE/previous-cli" "$CLI" ||
            info 'WARNING: Tailscale CLI rollback failed; verify manually'
        restore_entry "$STAGE/previous-manager" "$MANAGER" ||
            info 'WARNING: manager rollback failed; verify manually'
        restore_entry "$STAGE/previous-command" "$COMMAND" ||
            info 'WARNING: microscale command rollback failed; verify manually'
    fi
    if [ -n "$STAGE" ]; then
        rm -f "$DAEMON.next.$$" "$CLI.next.$$" "$DAEMON.restore.$$" "$CLI.restore.$$"
        rm -f "$MANAGER.next.$$" "$MANAGER.restore.$$" "$COMMAND.next.$$" "$COMMAND.restore.$$"
        rm -rf "$STAGE"
    fi
    exit "$code"
}
trap 'cleanup $?' 0
trap 'exit 130' INT
trap 'exit 143' TERM HUP

prepare_stage() {
    is_tmpfs /tmp || die 'RAM-backed /tmp is required'
    STAGE="$(mktemp -d /tmp/microscale-lifecycle.XXXXXX)" || die 'Cannot create RAM staging directory'
}
snapshot_previous() {
    if exists "$DAEMON"; then cp -a "$DAEMON" "$STAGE/previous-daemon"; fi
    if exists "$CLI"; then cp -a "$CLI" "$STAGE/previous-cli"; fi
    if exists "$MANAGER"; then cp -a "$MANAGER" "$STAGE/previous-manager"; fi
    if exists "$COMMAND"; then cp -a "$COMMAND" "$STAGE/previous-command"; fi
}
ensure_command_available() {
    # Never overwrite an unrelated executable or command named microscale.
    if exists "$COMMAND"; then
        if [ ! -L "$COMMAND" ] ||
           [ "$(readlink "$COMMAND")" != "$MANAGER" ]; then
            die "$COMMAND is already used by another program"
        fi
    fi
}
save_original() {
    # Initial originals and state persist for uninstall, as in Beszel's manager.
    # Abort rather than installing without a rollback record.
    [ -f "$STATE/install-state" ] && return 0
    # A completed uninstall can be followed by a new installation.
    # Refresh only manager-owned backups, not Tailscale state or config.
    if [ -f "$STATE/install-state.restored" ]; then
        rm -rf "$ORIGINAL" || die 'Cannot refresh restored backup set'
        rm -f "$STATE/install-state.restored"
    fi
    mkdir -p "$ORIGINAL"
    # Never overwrite a previous partial backup while state is missing.
    if exists "$ORIGINAL/tailscaled" || exists "$ORIGINAL/tailscale" ||
       [ -f "$ORIGINAL/no-daemon" ] || [ -f "$ORIGINAL/no-cli" ]; then
        die 'Original backup exists without install-state; inspect /etc/microscale before retrying'
    fi
    if exists "$DAEMON"; then cp -a "$DAEMON" "$ORIGINAL/tailscaled" || die 'Cannot preserve original daemon'; else : > "$ORIGINAL/no-daemon"; fi
    if exists "$CLI"; then cp -a "$CLI" "$ORIGINAL/tailscale" || die 'Cannot preserve original CLI'; else : > "$ORIGINAL/no-cli"; fi
}
download_binary() {
    profile="$1"
    name="microscale-$profile-linux-arm64.tar.gz"
    base="https://github.com/$REPO/releases/download/$TAG"
    fetch "$STAGE/$name" "$base/$name" || die "Cannot download $name"
    fetch "$STAGE/$name.sha256" "$base/$name.sha256" || die 'Cannot download archive checksum'
    (cd "$STAGE" && sha256sum -c "$name.sha256") || die 'Archive checksum failed'
    # Exact expected file entries; prevent traversal or outside-tmpfs writes.
    tar -tzf "$STAGE/$name" | awk '
       $0 !~ /^(microscale|Tailscale-LICENSE|build-info.txt|SHA256SUMS|size.tsv)$/ {bad=1}
       END {exit bad}
    ' || die 'Unexpected archive entry'
    (cd "$STAGE" && tar -xzf "$name") || die 'Extraction failed'
    grep -Fx 'Target: linux/arm64' "$STAGE/build-info.txt" >/dev/null || die 'Target mismatch'
    grep -Fx "MicroScale profile: $profile" "$STAGE/build-info.txt" >/dev/null || die 'Profile mismatch'
    (cd "$STAGE" && sha256sum -c SHA256SUMS) || die 'Executable checksum failed'
    chmod 755 "$STAGE/microscale"
    TS_BE_CLI=1 "$STAGE/microscale" version >/dev/null || die 'CLI cannot execute'
    "$STAGE/microscale" --version >/dev/null || die 'Daemon cannot execute'
}
check_space() {
    # Persistent original backup + new file + temporary destination staging.
    size="$(wc -c < "$STAGE/microscale" | tr -d ' ')"
    original_bytes=0
    if [ ! -f "$STATE/install-state" ]; then
        if [ -f "$DAEMON" ]; then original_bytes="$(wc -c < "$DAEMON" | tr -d ' ')"; fi
        if [ -f "$CLI" ]; then
            cli_size="$(wc -c < "$CLI" | tr -d ' ')"
            original_bytes=$((original_bytes + cli_size))
        fi
    fi
    # Reserve space for on-flash binary staging, the original backup,
    # the manager executable, and existing filesystem overhead.
    manager_bytes="$(wc -c < "$0" | tr -d ' ')"
    required=$(( (size + original_bytes + manager_bytes + 1023) / 1024 + 8192 ))
    free_kib="$(df -k /overlay | awk 'NR==2 {print $4}')"
    case "$free_kib" in ''|*[!0-9]*) die 'Cannot read overlay free space' ;; esac
    [ "$free_kib" -gt "$required" ] || die "Not enough overlay for binary and persistent rollback backup ($free_kib KiB free; need >$required KiB)"
}
install_binary() {
    profile="$1"
    require_platform
    choose_profile "$profile"
    info "Operation: $operation / $selected / $TAG"
    info 'Only Tailscale executables and MicroScale manager metadata will change.'
    info 'No services, VPN configuration, routes, DNS or firewall will be modified.'
    if [ "$selected" != small ]; then
        info 'WARNING: reduced profile is not yet qualified for your router'
    fi
    ask 'Proceed? [y/N]: '
    case "$answer" in y|Y|yes|YES) ;; *) info 'Cancelled'; return 0 ;; esac
    ensure_command_available
    prepare_stage
    download_binary "$selected"
    check_space
    snapshot_previous
    save_original
    mkdir -p "$MANAGER_DIR" || die 'Cannot create manager directory'

    # New binaries and manager are staged on their destination filesystems.
    cp "$STAGE/microscale" "$DAEMON.next.$$" || die 'Cannot stage executable'
    chmod 755 "$DAEMON.next.$$"
    ln -s "$DAEMON" "$CLI.next.$" || die 'Cannot stage CLI symlink'
    cp "$0" "$MANAGER.next.$" || die 'Cannot stage lifecycle manager'
    chmod 755 "$MANAGER.next.$" || die 'Cannot make manager executable'
    ln -s "$MANAGER" "$COMMAND.next.$" || die 'Cannot stage microscale CLI symlink'
    hash1="$(sha256sum "$STAGE/microscale" | awk '{print $1}')"
    hash2="$(sha256sum "$DAEMON.next.$$" | awk '{print $1}')"
    [ "$hash1" = "$hash2" ] || die 'NAND staging checksum mismatch'
    MODIFIED=1
    mv -f "$DAEMON.next.$$" "$DAEMON" || die 'Cannot install executable'
    mv -f "$CLI.next.$$" "$CLI" || die 'Cannot install CLI'
    # Keep a dedicated manager under /usr/lib and user-facing CLI in /usr/bin.
    mv -f "$MANAGER.next.$" "$MANAGER" || die 'Cannot install lifecycle manager'
    mv -f "$COMMAND.next.$" "$COMMAND" || die 'Cannot install microscale command'
    printf 'profile=%s\nrelease=%s\n' "$selected" "$TAG" > "$STATE/install-state.next.$"
    mv -f "$STATE/install-state.next.$$" "$STATE/install-state" || die 'Cannot save install state'
    COMMITTED=1
    info "Installed $selected ($TAG); run: microscale status"
    info "Manager: $MANAGER | State: $STATE"
    info 'Existing daemon process is unchanged until you manually restart it'
}
status() {
    if [ -r "$STATE/install-state" ]; then
        info "Managed install: $(tr '\n' ' ' < "$STATE/install-state")"
    else
        info 'Managed install: none'
    fi
    if exists "$DAEMON"; then info 'Daemon binary: present'; else info 'Daemon binary: absent'; fi
    if exists "$CLI"; then info 'CLI binary: present'; else info 'CLI binary: absent'; fi
}
doctor() {
    status
    if exists "$DAEMON"; then
        if TS_BE_CLI=1 "$DAEMON" version >/dev/null 2>&1 &&
           "$DAEMON" --version >/dev/null 2>&1; then
            info 'Combined CLI/daemon: PASS'
        else
            die 'Combined executable version smoke check failed'
        fi
    else
        die 'Tailscale daemon executable absent'
    fi
    info 'Doctor does not test VPN connectivity, routes, or daemon runtime'
}
diagnostics() {
    status
    uname -m
    df -h /overlay
    awk '/^MemTotal:|^MemAvailable:/ {print}' /proc/meminfo
    info 'No Tailnet or Tailscale state data collected'
}
uninstall() {
    require_platform
    [ -r "$STATE/install-state" ] || die 'No managed installation; nothing removed'
    [ -d "$ORIGINAL" ] || die 'Original rollback directory missing'
    ask 'Restore original Tailscale binaries? [y/N]: '
    case "$answer" in y|Y|yes|YES) ;; *) info 'Cancelled'; return 0 ;; esac
    prepare_stage
    snapshot_previous
    MODIFIED=1
    if exists "$ORIGINAL/tailscaled"; then
        cp -a "$ORIGINAL/tailscaled" "$DAEMON.restore.$$" &&
          mv -f "$DAEMON.restore.$$" "$DAEMON" || die 'Cannot restore original daemon'
    elif [ -f "$ORIGINAL/no-daemon" ]; then
        rm -f "$DAEMON"
    else
        die 'Original daemon backup state inconsistent'
    fi
    if exists "$ORIGINAL/tailscale"; then
        cp -a "$ORIGINAL/tailscale" "$CLI.restore.$$" &&
          mv -f "$CLI.restore.$$" "$CLI" || die 'Cannot restore original CLI'
    elif [ -f "$ORIGINAL/no-cli" ]; then
        rm -f "$CLI"
    else
        die 'Original CLI backup state inconsistent'
    fi
    mv -f "$STATE/install-state" "$STATE/install-state.restored"
    COMMITTED=1
    info 'Original binary files restored. Tailscale state/config/service untouched.'
    info 'Manager and original backups retained for inspection.'
}
usage() {
    printf 'Usage: sh manager.sh [install|update|repair|status|doctor|diagnostics|uninstall] [small|micro|extreme]\n'
}
operation=""
if [ "$#" -gt 0 ]; then operation="$1"; shift; fi
if [ -z "$operation" ]; then
    info '1) Install/Update  2) Status  3) Doctor  4) Diagnostics  5) Repair  6) Uninstall'
    ask 'Action [1-6]: '
    case "$answer" in
        1) operation=install ;; 2) operation=status ;; 3) operation=doctor ;;
        4) operation=diagnostics ;; 5) operation=repair ;;
        6) operation=uninstall ;; *) die 'Invalid menu selection' ;;
    esac
fi
case "$operation" in
    install|update) requested=""; [ "$#" -eq 0 ] || requested="$1"; install_binary "$requested" ;;
    repair)
        [ -r "$STATE/install-state" ] || die 'No existing managed installation'
        requested="$(sed -n 's/^profile=//p' "$STATE/install-state" | head -1)"
        install_binary "$requested"
        ;;
    status) status ;;
    doctor) doctor ;;
    diagnostics) diagnostics ;;
    uninstall) uninstall ;;
    --help|-h|help) usage ;;
    *) usage; die "Unknown operation: $operation" ;;
esac
