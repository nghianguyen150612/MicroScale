#!/bin/sh
# Small, pipe-safe bootstrap: download, verify pinned manager, then execute.
set -eu
umask 077

RELEASE_TAG=v0.2.2
REPO=nghianguyen150612/MicroScale
engine_sha=6ca5035240df8cff60f1761c854c85f086d6c0d09adcc9a809c5eab4e5572bf3

fail() { printf 'MicroScale bootstrap: %s\n' "$*" >&2; exit 1; }
ram_base=''
if awk '$2=="/tmp" && $3=="tmpfs" {ok=1} END{exit !ok}' /proc/mounts; then
    ram_base=/tmp
elif [ "${1:-}" = test-ram ] || [ "${1:-}" = test ] ||
     [ "${1:-}" = report ] || [ "${1:-}" = test-report ]; then
    awk '$2=="/dev/shm" && $3=="tmpfs" {ok=1} END{exit !ok}' /proc/mounts ||
        fail 'No verified tmpfs for RAM test bootstrap'
    ram_base=/dev/shm
else
    fail 'Persistent installer requires RAM-backed /tmp'
fi
command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum is required'
stage="$(mktemp -d "$ram_base/microscale-bootstrap.XXXXXX")" ||
    fail 'Cannot allocate temporary directory'
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
