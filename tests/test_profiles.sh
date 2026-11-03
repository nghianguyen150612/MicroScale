#!/usr/bin/env bash
set -Eeuo pipefail
for script in scripts/build.sh scripts/verify.sh scripts/benchmark.sh tests/test_profiles.sh; do
  bash -n "$script"
done
source profiles/safe.env
expected_version="$UPSTREAM_VERSION"
expected_commit="$UPSTREAM_COMMIT"
[[ "$expected_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
[[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]] || exit 1
for profile in safe small extreme; do
  [[ -f "profiles/$profile.env" ]] || exit 1
  source "profiles/$profile.env"
  [[ "$UPSTREAM_VERSION" == "$expected_version" ]] || exit 1
  [[ "$UPSTREAM_COMMIT" == "$expected_commit" ]] || exit 1
done
if bash scripts/build.sh invalid >/dev/null 2>&1; then
  echo "Invalid profile must fail" >&2
  exit 1
fi
echo "PASS: three profiles have identical pinned upstream source"
