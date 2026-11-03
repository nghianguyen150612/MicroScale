#!/bin/sh
# MicroScale interactive binary-only installer for OpenWrt/Linux ARM64.
# Installs only the Tailscale CLI and daemon executable files.
# Does NOT enable/start/restart services or change routes, DNS, auth, firewall, or configuration.
set -eu
umask 077

RELEASE_TAG="v0.2.0-rc.3"
REPOSITORY="nghianguyen150612/MicroScale"
DAEMON="/usr/sbin/tailscaled"
CLI="/usr/bin/tailscale"
workdir=""
backupdir=""
modified=0
committed=0
staged_daemon=""
staged_cli=""

say() { printf '%s\n' "$*"; }
fail() { printf 'MicroScale ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'HELP'
MicroScale installer — download and install Tailscale binaries only.
Usage: sh install.sh [--profile small|micro|extreme] [--help]

Without --profile, the installer shows a three-choice interactive menu.
Installation still requires an explicit confirmation.
It never configures, starts, restarts or enables Tailscale services.
HELP
}

fetch() {
    destination="$1"
    url="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --connect-timeout 15 --max-time 180 -o "$destination" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$destination" "$url"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -O "$destination" "$url"
    else
        fail "Need curl, wget, or uclient-fetch with HTTPS support"
    fi
}

restore_one() {
    target="$1"
    name="$2"
    if [ -e "$backupdir/$name" ] || [ -L "$backupdir/$name" ]; then
        cp -a "$backupdir/$name" "$target.microscale-restore.$$" || return 1
        mv -f "$target.microscale-restore.$$" "$target" || return 1
    else
        rm -f "$target" || return 1
    fi
}

cleanup() {
    code="$1"
    trap - 0
    if [ "$code" -ne 0 ] && [ "$modified" -eq 1 ] && [ "$committed" -eq 0 ]; then
        say "Installation failed after writing files. Attempting binary rollback..." >&2
        restore_one "$DAEMON" tailscaled || say "WARNING: daemon rollback failed" >&2
        restore_one "$CLI" tailscale || say "WARNING: CLI rollback failed" >&2
        say "Manual recovery copies, if needed: $backupdir" >&2
    fi
    [ -z "$staged_daemon" ] || rm -f "$staged_daemon"
    [ -z "$staged_cli" ] || rm -f "$staged_cli"
    [ -z "$workdir" ] || rm -rf "$workdir"
    exit "$code"
}
trap 'cleanup $?' 0
trap 'exit 130' 2
trap 'exit 143' 15

profile=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --profile)
            [ "$#" -ge 2 ] || fail "--profile requires a value"
            profile="$2"
            shift 2
            ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

[ "$(id -u)" -eq 0 ] || fail "Run as root"
case "$(uname -m)" in
    aarch64|arm64) ;;
    *) fail "Only ARM64 Linux is supported by this release; detected $(uname -m)" ;;
esac
[ -d /usr/sbin ] && [ -d /usr/bin ] || fail "Missing /usr/sbin or /usr/bin"
[ -d /overlay ] || fail "OpenWrt overlay not found; refusing an unverified filesystem"
for command in sha256sum tar awk wc mktemp cp mv ln df; do
    command -v "$command" >/dev/null 2>&1 || fail "Missing command: $command"
done

if [ -z "$profile" ]; then
    say "====================================="
    say " MicroScale $RELEASE_TAG — installer"
    say "====================================="
    say "1) Small   — full features (~40 MiB)"
    say "2) Micro   — reduced features (~13 MiB), not yet device-tested"
    say "3) Extreme — reduced + UPX (~3.4 MiB), not yet device-tested"
    printf 'Choose profile [1/2/3]: '
    IFS= read -r answer </dev/tty || fail "Interactive terminal required"
    case "$answer" in
        1) profile=small ;;
        2) profile=micro ;;
        3) profile=extreme ;;
        *) fail "No profile selected" ;;
    esac
fi
case "$profile" in small|micro|extreme) ;; *) fail "Invalid profile: $profile";; esac

say ""
say "Selected: $profile ($RELEASE_TAG, linux/arm64)"
if [ "$profile" != small ]; then
    say "WARNING: This profile omits upstream features and has not been qualified on NR3053."
    say "It may lack functions you need; install only if you can restore locally."
fi
say "Only /usr/sbin/tailscaled and /usr/bin/tailscale will be installed/replaced."
say "NO service start/restart, NO tailscale up, NO config/DNS/firewall changes."
say "Original binaries will be backed up in /tmp until reboot."
printf 'Proceed with binary-only installation? [y/N]: '
IFS= read -r confirmation </dev/tty || fail "Interactive confirmation required"
case "$confirmation" in y|Y|yes|YES) ;; *) say "Cancelled. Nothing changed."; exit 0;; esac

workdir="$(mktemp -d /tmp/microscale-install.XXXXXX)" || fail "Cannot create RAM workspace"
asset="microscale-$profile-linux-arm64.tar.gz"
base="https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG"
say "Downloading pinned $asset..."
fetch "$workdir/$asset" "$base/$asset" || fail "Could not download release archive"
fetch "$workdir/$asset.sha256" "$base/$asset.sha256" || fail "Could not download checksum"
(
    cd "$workdir"
    sha256sum -c "$asset.sha256"
) || fail "Release checksum verification FAILED; nothing installed"

tar -xzf "$workdir/$asset" -C "$workdir" || fail "Invalid release archive"
[ -f "$workdir/microscale" ] || fail "Executable missing from release archive"
[ -f "$workdir/build-info.txt" ] || fail "Build metadata missing"
grep -q '^Target: linux/arm64$' "$workdir/build-info.txt" ||
    fail "Release target mismatch"
(
    cd "$workdir"
    sha256sum -c SHA256SUMS
) || fail "Executable checksum FAILED"
chmod 755 "$workdir/microscale"
TS_BE_CLI=1 "$workdir/microscale" version ||
    fail "Candidate CLI cannot execute on this router"
"$workdir/microscale" --version ||
    fail "Candidate daemon version check failed"

bytes="$(wc -c < "$workdir/microscale" | tr -d ' ')"
needed_kib=$(( (bytes + 1023) / 1024 + 4096 ))
available_kib="$(df -k /overlay | awk 'NR==2 {print $4}')"
case "$available_kib" in *[!0-9]*|'') fail "Cannot read available overlay space";; esac
[ "$available_kib" -gt "$needed_kib" ] ||
    fail "Not enough NAND space for safe replacement (need >$needed_kib KiB free, have $available_kib KiB)"

backupdir="$(mktemp -d /tmp/microscale-backup.XXXXXX)" ||
    fail "Cannot create RAM backup"
if [ -e "$DAEMON" ] || [ -L "$DAEMON" ]; then
    cp -a "$DAEMON" "$backupdir/tailscaled" || fail "Cannot back up old daemon"
fi
if [ -e "$CLI" ] || [ -L "$CLI" ]; then
    cp -a "$CLI" "$backupdir/tailscale" || fail "Cannot back up old CLI"
fi

# Stage on the destination filesystem, then rename; never overwrite an
# executable inode in-place while a daemon may still be running.
staged_daemon="/usr/sbin/.microscale-tailscaled.$$"
staged_cli="/usr/bin/.microscale-tailscale.$$"
cp "$workdir/microscale" "$staged_daemon" || fail "Cannot stage binary on NAND"
chmod 755 "$staged_daemon" || fail "Cannot chmod staged binary"
stage_hash="$(sha256sum "$staged_daemon" | awk '{print $1}')"
source_hash="$(sha256sum "$workdir/microscale" | awk '{print $1}')"
[ "$stage_hash" = "$source_hash" ] || fail "NAND staging checksum mismatch"
ln -s "$DAEMON" "$staged_cli" || fail "Cannot stage CLI symlink"

modified=1
mv -f "$staged_daemon" "$DAEMON" || fail "Cannot install daemon"
staged_daemon=""
mv -f "$staged_cli" "$CLI" || fail "Cannot install CLI symlink"
staged_cli=""
committed=1

say ""
say "Installed: $profile ($RELEASE_TAG)"
say "Daemon: $DAEMON"
say "CLI:    $CLI"
say "RAM backup: $backupdir (lost on reboot)"
say "No VPN configuration or service lifecycle action was performed."
say "Any existing running tailscaled process retains its previous executable until you restart it yourself."
df -h /overlay
