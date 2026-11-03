#!/usr/bin/env bash
set -Eeuo pipefail
bash tests/test_manager.sh
grep -q 'scripts/install.sh' .github/workflows/release.yml
for profile in small micro extreme; do
    grep -q "$profile" .github/workflows/release.yml
done
echo "PASS: installer packaging and profiles"
