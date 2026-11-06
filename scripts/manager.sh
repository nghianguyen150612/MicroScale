#!/bin/sh
# MicroScale lifecycle manager. POSIX sh; never touches Tailscale config or services.
set -eu
umask 077

TAG=v0.2.0-rc.7
REPO=nghianguyen150612/MicroScale
DAEMON=/usr/sbin/tailscaled
CLI=/usr/bin/tailscale
STATE=/etc/microscale
ORIGINAL=$STATE/original
MANAGER_DIR=/usr/lib/microscale
MANAGER=$MANAGER_DIR/manager.sh
COMMAND=/usr/bin/microscale
LEGACY_STATE=/var/lib/microscale
RAM_ROOT=/tmp/microscale-stage
STAGE=""
MODIFIED=0
COMMITTED=0
NAND_STAGING=0

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
runtime_arch() {
    case "$(uname -m)" in
        aarch64|arm64) printf 'arm64\n' ;;
        x86_64|amd64) printf 'amd64\n' ;;
        *) die 'RAM mode supports Linux ARM64 or x86_64 only' ;;
    esac
}
require_ram_platform() {
    [ "$(id -u)" = 0 ] || die 'Root required for RAM staging'
    is_tmpfs /tmp || die '/tmp must be tmpfs to guarantee RAM-only installation'
    runtime_arch >/dev/null
    for dep in sha256sum tar awk grep sed readlink; do
        command -v "$dep" >/dev/null 2>&1 || die "Missing command: $dep"
    done
    [ ! -L "$RAM_ROOT" ] || die 'Refusing a symlinked RAM stage directory'
}
require_platform() {
    require_ram_platform
    [ "$(runtime_arch)" = arm64 ] || die 'Persistent install is supported only on OpenWrt ARM64'
    [ -d /overlay ] || die 'OpenWrt overlay missing; refusing to modify this host'
    [ -d /usr/sbin ] && [ -d /usr/bin ] && [ -d /usr/lib ] || die 'Missing OpenWrt binary directories'
    is_tmpfs /tmp || die '/tmp must be tmpfs for staging'
    command -v readlink >/dev/null 2>&1 || die 'BusyBox readlink required'
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
    if [ "$NAND_STAGING" = 1 ]; then
        rm -f "$DAEMON.next.$$" "$CLI.next.$$" "$DAEMON.restore.$$" "$CLI.restore.$$"
        rm -f "$MANAGER.next.$$" "$MANAGER.restore.$$" "$COMMAND.next.$$" "$COMMAND.restore.$$"
    fi
    [ -z "$STAGE" ] || rm -rf "$STAGE"
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
    arch="$2"
    case "$profile:$arch" in
        small:arm64|micro:arm64|extreme:arm64|small:amd64|micro:amd64|extreme:amd64) ;;
        *) die 'Unsupported profile/architecture combination' ;;
    esac
    name="microscale-$profile-linux-$arch.tar.gz"
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
    grep -Fx "Target: linux/$arch" "$STAGE/build-info.txt" >/dev/null || die 'Target mismatch'
    grep -Fx "MicroScale profile: $profile" "$STAGE/build-info.txt" >/dev/null || die 'Profile mismatch'
    (cd "$STAGE" && sha256sum -c SHA256SUMS) || die 'Executable checksum failed'
    chmod 755 "$STAGE/microscale"
    TS_BE_CLI=1 "$STAGE/microscale" version >/dev/null || die 'CLI cannot execute'
    "$STAGE/microscale" --version >/dev/null || die 'Daemon cannot execute'
}
check_space() {
    # Persistent original backup + new file + temporary destination staging.
    candidate="$1"
    size="$(wc -c < "$candidate" | tr -d ' ')"
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
# A RAM stage is intentionally separate from the system executable paths.
# Only a verified, matching-version stage can be applied to NAND.
ram_stage_ready() {
    [ -d "$RAM_ROOT" ] && [ ! -L "$RAM_ROOT" ] || return 1
    [ -f "$RAM_ROOT/microscale" ] &&
        [ -f "$RAM_ROOT/manifest" ] &&
        [ -f "$RAM_ROOT/manager.sh" ] || return 1
    stage_profile="$(sed -n 's/^profile=//p' "$RAM_ROOT/manifest")"
    stage_release="$(sed -n 's/^release=//p' "$RAM_ROOT/manifest")"
    stage_arch="$(sed -n 's/^arch=//p' "$RAM_ROOT/manifest")"
    stage_hash="$(sed -n 's/^sha256=//p' "$RAM_ROOT/manifest")"
    case "$stage_profile" in small|micro|extreme) ;; *) return 1 ;; esac
    case "$stage_arch" in arm64|amd64) ;; *) return 1 ;; esac
    [ "$stage_release" = "$TAG" ] || return 1
    [ "$stage_arch" = "$(runtime_arch)" ] || return 1
    [ -n "$stage_hash" ] || return 1
    [ "$(sha256sum "$RAM_ROOT/microscale" | awk '{print $1}')" = "$stage_hash" ] || return 1
    [ "$(sha256sum "$RAM_ROOT/manager.sh" | awk '{print $1}')" = "$(sha256sum "$0" | awk '{print $1}')" ] || return 1
    [ -L "$RAM_ROOT/bin/tailscale" ] &&
        [ "$(readlink "$RAM_ROOT/bin/tailscale")" = "../microscale" ] || return 1
    [ -L "$RAM_ROOT/bin/tailscaled" ] &&
        [ "$(readlink "$RAM_ROOT/bin/tailscaled")" = "../microscale" ] || return 1
    [ -x "$RAM_ROOT/microscale" ] || return 1
    return 0
}
ram_status() {
    if ram_stage_ready; then
        info "RAM stage: $stage_profile / $stage_arch / $stage_release (verified)"
        info "RAM CLI: $RAM_ROOT/bin/tailscale"
        info "RAM daemon: $RAM_ROOT/bin/tailscaled"
        info 'Not running, not activated; /usr and VPN state are unchanged'
    elif [ -e "$RAM_ROOT" ] || [ -L "$RAM_ROOT" ]; then
        info 'RAM stage: present but invalid or from another release; apply disabled'
    else
        info 'RAM stage: none'
    fi
}
install_ram() {
    requested="$1"
    require_ram_platform
    choose_profile "$requested"
    arch="$(runtime_arch)"
    info "RAM install: $selected / linux-$arch / $TAG"
    info 'Only /tmp is written. Existing Tailscale binary, daemon and config stay untouched.'
    ask 'Stage binary in RAM? [y/N]: '
    case "$answer" in y|Y|yes|YES) ;; *) info 'Cancelled'; return 0 ;; esac
    if [ -e "$RAM_ROOT" ] || [ -L "$RAM_ROOT" ]; then
        ram_stage_ready || die 'Existing RAM stage is invalid; inspect before using clear-ram'
    fi
    prepare_stage
    download_binary "$selected" "$arch"
    # Download/extraction already occupy tmpfs. Reserve additional space for
    # the durable RAM copy and 32 MiB of available memory for the running router.
    candidate_bytes="$(wc -c < "$STAGE/microscale" | tr -d ' ')"
    candidate_kib=$(( (candidate_bytes + 1023) / 1024 ))
    tmp_free_kib="$(df -k /tmp | awk 'NR==2 {print $4}')"
    mem_available_kib="$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo)"
    case "$tmp_free_kib:$mem_available_kib" in
        *[!0-9:]*|:*|*:) die 'Cannot read tmpfs space or MemAvailable' ;;
    esac
    [ "$tmp_free_kib" -gt $((candidate_kib + 8192)) ] ||
        die 'Not enough tmpfs space to retain a second binary copy in RAM'
    [ "$mem_available_kib" -gt $((candidate_kib + 32768)) ] ||
        die 'Insufficient available memory to stage safely; clear old test files'
    ready="$STAGE/ready"
    mkdir -p "$ready/bin" || die 'Cannot prepare RAM stage'
    cp "$STAGE/microscale" "$ready/microscale" || die 'Cannot stage RAM binary'
    cp "$0" "$ready/manager.sh" || die 'Cannot stage RAM manager'
    chmod 700 "$ready/microscale"
    chmod 700 "$ready/manager.sh"
    ln -s ../microscale "$ready/bin/tailscale"
    ln -s ../microscale "$ready/bin/tailscaled"
    ln -s ../manager.sh "$ready/bin/microscale"
    binary_hash="$(sha256sum "$ready/microscale" | awk '{print $1}')"
    printf 'profile=%s\narch=%s\nrelease=%s\nsha256=%s\n' \
        "$selected" "$arch" "$TAG" "$binary_hash" > "$ready/manifest"
    if [ -d "$RAM_ROOT" ]; then
        mv "$RAM_ROOT" "$STAGE/previous-ram" || die 'Cannot preserve previous RAM stage'
    fi
    if ! mv "$ready" "$RAM_ROOT"; then
        if [ -d "$STAGE/previous-ram" ]; then
            mv "$STAGE/previous-ram" "$RAM_ROOT" || true
        fi
        die 'Failed to publish RAM stage'
    fi
    info "Installed to RAM: $RAM_ROOT"
    info "Test: $RAM_ROOT/bin/tailscale version"
    info 'Rerun install.sh to see Apply RAM to NAND. No daemon has been started.'
}
nand_commit() {
    # Caller has validated the candidate and confirmed NAND installation.
    candidate="$1"
    target_profile="$2"
    check_space "$candidate"
    snapshot_previous
    save_original
    mkdir -p "$MANAGER_DIR" || die 'Cannot create manager directory'
    NAND_STAGING=1
    cp "$candidate" "$DAEMON.next.$$" || die 'Cannot stage executable'
    chmod 755 "$DAEMON.next.$$"
    ln -s "$DAEMON" "$CLI.next.$$" || die 'Cannot stage CLI symlink'
    cp "$0" "$MANAGER.next.$$" || die 'Cannot stage lifecycle manager'
    chmod 755 "$MANAGER.next.$$" || die 'Cannot make manager executable'
    ln -s "$MANAGER" "$COMMAND.next.$$" || die 'Cannot stage microscale CLI symlink'
    hash1="$(sha256sum "$candidate" | awk '{print $1}')"
    hash2="$(sha256sum "$DAEMON.next.$$" | awk '{print $1}')"
    [ "$hash1" = "$hash2" ] || die 'NAND staging checksum mismatch'
    MODIFIED=1
    mv -f "$DAEMON.next.$$" "$DAEMON" || die 'Cannot install executable'
    mv -f "$CLI.next.$$" "$CLI" || die 'Cannot install CLI'
    mv -f "$MANAGER.next.$$" "$MANAGER" || die 'Cannot install lifecycle manager'
    mv -f "$COMMAND.next.$$" "$COMMAND" || die 'Cannot install microscale command'
    printf 'profile=%s\nrelease=%s\n' "$target_profile" "$TAG" > "$STATE/install-state.next.$$"
    mv -f "$STATE/install-state.next.$$" "$STATE/install-state" || die 'Cannot save install state'
    COMMITTED=1
    info "Installed $target_profile ($TAG) to NAND; run: microscale status"
    info 'Tailscale service and authentication have not been touched or restarted'
}
install_binary() {
    profile="$1"
    require_platform
    choose_profile "$profile"
    info "NAND install: $selected / $TAG"
    info 'Tailscale executables and MicroScale metadata only; no service or VPN configuration'
    [ "$selected" = small ] || info 'WARNING: reduced profile has not been VPN-qualified'
    ask 'Write to NAND and preserve original binaries? [y/N]: '
    case "$answer" in y|Y|yes|YES) ;; *) info 'Cancelled'; return 0 ;; esac
    ensure_command_available
    prepare_stage
    download_binary "$selected" arm64
    nand_commit "$STAGE/microscale" "$selected"
}
apply_ram() {
    require_platform
    ram_stage_ready || die 'No verified RAM stage for this release and architecture'
    [ "$stage_arch" = arm64 ] || die 'Persistent OpenWrt installation requires ARM64'
    profile="$stage_profile"
    info "Apply RAM stage to NAND: $profile / $TAG"
    info 'Existing Tailscale executables will be backed up. No service restart.'
    ask 'Apply verified RAM binary to NAND? [y/N]: '
    case "$answer" in y|Y|yes|YES) ;; *) info 'Cancelled'; return 0 ;; esac
    ensure_command_available
    prepare_stage
    cp "$RAM_ROOT/microscale" "$STAGE/microscale" || die 'Cannot snapshot RAM binary'
    staged_hash="$(sha256sum "$STAGE/microscale" | awk '{print $1}')"
    [ "$staged_hash" = "$stage_hash" ] || die 'RAM stage changed before apply'
    nand_commit "$STAGE/microscale" "$profile"
    info 'RAM stage is retained until reboot or clear-ram'
}
clear_ram() {
    require_ram_platform
    if [ ! -d "$RAM_ROOT" ]; then
        info 'No RAM stage to remove'
        return 0
    fi
    ask 'Delete only the /tmp/microscale-stage RAM files? [y/N]: '
    case "$answer" in y|Y|yes|YES) ;; *) info 'Cancelled'; return 0 ;; esac
    rm -rf "$RAM_ROOT" || die 'Cannot remove RAM stage'
    info 'RAM stage deleted; NAND and running Tailscale unchanged'
}
status() {
    if [ -r "$STATE/install-state" ]; then
        info "Managed install: $(tr '\n' ' ' < "$STATE/install-state")"
    else
        info 'Managed install: none'
    fi
    if exists "$DAEMON"; then info 'Daemon binary: present'; else info 'Daemon binary: absent'; fi
    if exists "$CLI"; then info 'CLI binary: present'; else info 'CLI binary: absent'; fi
    ram_status
    if [ -L "$COMMAND" ] && [ "$(readlink "$COMMAND")" = "$MANAGER" ] && [ -f "$MANAGER" ]; then
        info "Manager CLI: $COMMAND -> $MANAGER"
    else
        info 'Manager CLI: not installed'
    fi
}
doctor() {
    status
    if [ -r "$STATE/install-state" ]; then
        [ -L "$COMMAND" ] && [ "$(readlink "$COMMAND")" = "$MANAGER" ] &&
            [ -x "$MANAGER" ] || die 'microscale CLI symlink/manager invalid'
    fi
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
version() {
    info "MicroScale manager $TAG"
    if [ -r "$STATE/install-state" ]; then
        info "Installed: $(tr '\n' ' ' < "$STATE/install-state")"
    fi
}
usage() {
    printf 'Usage: microscale [install-ram|apply|ram-status|clear-ram|install|update|repair|status|doctor|diagnostics|uninstall|version|help] [small|micro|extreme]\n'
}
operation=""
if [ "$#" -gt 0 ]; then operation="$1"; shift; fi
if [ -z "$operation" ]; then
    info '1) Install to RAM (no NAND writes)'
    if ram_stage_ready; then
        info "2) Apply verified RAM stage to NAND ($stage_profile)"
    fi
    info '3) Install/Update directly to NAND'
    info '4) RAM status   5) Status   6) Doctor   7) Diagnostics'
    info '8) Repair       9) Uninstall   0) Clear RAM stage'
    ask 'Action [0-9]: '
    case "$answer" in
        1) operation=install-ram ;;
        2) operation=apply ;;
        3) operation=install ;;
        4) operation=ram-status ;;
        5) operation=status ;;
        6) operation=doctor ;;
        7) operation=diagnostics ;;
        8) operation=repair ;;
        9) operation=uninstall ;;
        0) operation=clear-ram ;;
        *) die 'Invalid menu selection' ;;
    esac
fi
case "$operation" in
    install-ram|ram-install)
        requested=""; [ "$#" -eq 0 ] || requested="$1"; install_ram "$requested" ;;
    apply|apply-nand)
        [ "$#" -eq 0 ] || die 'Apply uses the profile already staged in RAM'; apply_ram ;;
    ram-status) ram_status ;;
    clear-ram) clear_ram ;;
    install|update)
        requested=""; [ "$#" -eq 0 ] || requested="$1"; install_binary "$requested" ;;
    repair)
        [ -r "$STATE/install-state" ] || die 'No existing managed installation'
        requested="$(sed -n 's/^profile=//p' "$STATE/install-state" | head -1)"
        install_binary "$requested"
        ;;
    status) status ;;
    version) version ;;
    doctor) doctor ;;
    diagnostics) diagnostics ;;
    uninstall) uninstall ;;
    --help|-h|help) usage ;;
    *) usage; die "Unknown operation: $operation" ;;
esac
