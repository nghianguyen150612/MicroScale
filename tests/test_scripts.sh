#!/bin/sh
set -eu
for script in scripts/build.sh scripts/verify.sh tests/test_scripts.sh; do
    sh -n "$script"
done
if sh scripts/build.sh unknown /tmp /tmp >/dev/null 2>&1; then
    echo "Invalid profiles must fail" >&2
    exit 1
fi
if sh scripts/verify.sh unknown arch >/dev/null 2>&1; then
    echo "Incomplete verification arguments must fail" >&2
    exit 1
fi
echo "PASS: syntax and profile validation"
