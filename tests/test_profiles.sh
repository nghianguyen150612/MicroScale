#!/usr/bin/env bash
set -Eeuo pipefail
for script in scripts/build.sh scripts/verify.sh scripts/benchmark.sh tests/test_profiles.sh; do
  bash -n "$script"
done
source profiles/small.env
expected_version="$UPSTREAM_VERSION"
expected_commit="$UPSTREAM_COMMIT"
[[ "$expected_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
[[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]] || exit 1
[[ ! -e profiles/safe.env ]] || { echo "legacy profile found" >&2; exit 1; }
for profile in small micro extreme; do
  [[ -f "profiles/$profile.env" ]] || exit 1
  source "profiles/$profile.env"
  [[ "$UPSTREAM_VERSION" == "$expected_version" ]] || exit 1
  [[ "$UPSTREAM_COMMIT" == "$expected_commit" ]] || exit 1
done
for profile in micro extreme; do
  source "profiles/$profile.env"
  for required in cli osrouter nattraversal netstack outboundproxy health ssh serve acme dns portmapper peerapiserver peerapiclient; do
    case ",$MICRO_KEEP_FEATURES," in
      *,"$required",*) ;;
      *) echo "Missing required NR3053 feature: $required ($profile)" >&2; exit 1 ;;
    esac
  done
done
if bash scripts/build.sh invalid >/dev/null 2>&1; then
  echo "Invalid profile must fail" >&2
  exit 1
fi
echo "PASS: three profiles have identical pinned upstream source"
