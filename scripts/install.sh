#!/bin/sh
# Small, pipe-safe bootstrap: download, verify pinned manager, then execute.
set -eu
umask 077

RELEASE_TAG=v0.2.0-rc.7
REPO=nghianguyen150612/MicroScale
engine_sha=48161da5be5a760aa5a0265c1c5003a657957dc5183760ac1e0bdb35cad52e3f

fail() { printf 'MicroScale bootstrap: %s\n' "$*" >&2; exit 1; }
awk '$2=="/tmp" && $3=="tmpfs" {ok=1} END{exit !ok}' /proc/mounts ||
    fail 'Refusing to stage lifecycle manager outside RAM-backed /tmp'
command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum is required'
stage="$(mktemp -d /tmp/microscale-bootstrap.XXXXXX)" || fail 'Cannot allocate temporary directory'
trap 'rm -rf "$stage"' 0
trap 'exit 130' INT
trap 'exit 143' TERM HUP

url="https://github.com/$REPO/releases/download/$RELEASE_TAG/manager.sh"
if command -v curl >/dev/null 2>&1; then
    curl -fLsS --proto '=https' --proto-redir '=https' -o "$stage/manager.sh" "$url" ||
        fail 'Cannot download manager'
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$stage/manager.sh" "$url" || fail 'Cannot download manager'
elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -O "$stage/manager.sh" "$url" || fail 'Cannot download manager'
else
    fail 'HTTPS downloader required'
fi
actual="$(sha256sum "$stage/manager.sh" | awk '{print $1}')"
[ "$actual" = "$engine_sha" ] || fail 'Pinned manager checksum mismatch'
sh "$stage/manager.sh" "$@"
