#!/usr/bin/env bash
set -Eeuo pipefail
for script in scripts/build.sh scripts/verify.sh scripts/benchmark.sh tests/test_profiles.sh; do
  bash -n "$script"
done
for profile in safe small extreme; do
  test -f "profiles/$profile.env" || exit 1
  # shellcheck disable=SC1090
  source "profiles/$profile.env"
  [[ "$UPSTREAM_VERSION" == v1.104.5 ]] || exit 1
  [[ "$UPSTREAM_COMMIT" == 73a48057aaf5f60e4f770b398e9b7af576b01dbe ]] || exit 1
done
if bash scripts/build.sh invalid >/dev/null 2>&1; then
  echo "Invalid profile must fail" >&2
  exit 1
fi
echo "PASS: three pinned profiles and shell syntax"
