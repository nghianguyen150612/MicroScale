#!/usr/bin/env bash
# Import strict, non-identifying RAM test results into a reviewable GitHub PR.
set -Eeuo pipefail
fail() { echo "MicroScale report import: $*" >&2; exit 1; }

submit=no
if [[ "${1:-}" == "--submit" ]]; then
  submit=yes
  shift
fi
[[ $# -eq 1 ]] || fail "Usage: bash scripts/import-report.sh [--submit] FILE.tsv"
source_file="$(realpath "$1")"
[[ -f "$source_file" ]] || fail "Missing input TSV"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ -d .git ]] || fail "Run from a Git clone"

# Do not allow arbitrary hostnames, IPs, Tailnet data, command output, or secrets.
# The schema consists solely of fixed enums, numbers, and a UTC timestamp.
awk -F '\t' '
  BEGIN {
    want="utc\tplatform\tarch\tprofile\trelease\telf_bytes\tram_total_kib\tram_available_kib\tcli_version\tdaemon_version\tcli_help\tcli_peak_rss_kib\tcli_elapsed_s\tresult"
    bad=0
  }
  NR==1 { if ($0!=want) bad=1; next }
  {
    if (NF!=14) bad=1
    if ($1 !~ /^[0-9TZ:-]+$/) bad=1
    if ($2 !~ /^(openwrt|linux)$/) bad=1
    if ($3 !~ /^(arm64|amd64)$/) bad=1
    if ($4 !~ /^(small|micro|extreme)$/) bad=1
    if ($5 !~ /^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$/) bad=1
    if ($6 !~ /^[0-9]+$/) bad=1
    if ($7 !~ /^([0-9]+|NA)$/ || $8 !~ /^([0-9]+|NA)$/) bad=1
    if ($9 !~ /^(ok|fail)$/ || $10 !~ /^(ok|fail)$/ || $11 !~ /^(ok|fail)$/) bad=1
    if ($12 !~ /^([0-9]+|NA)$/) bad=1
    if ($13 !~ /^([0-9]+(\.[0-9]+)?|NA)$/) bad=1
    if ($14 !~ /^(PASS|FAIL)$/) bad=1
  }
  END { if (NR<2 || bad) exit 1 }
' "$source_file" || fail "Report rejected: invalid schema or potentially sensitive content"

if [[ "$submit" == yes ]]; then
  command -v gh >/dev/null || fail "gh CLI is required for --submit"
  [[ -z "$(git status --porcelain)" ]] ||
    fail "The Git worktree must be clean before --submit"
  gh auth status >/dev/null || fail "Login to GitHub with gh first"
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p reports
destination="$(mktemp "$root/reports/ram-$timestamp-XXXXXX.tsv")"
cp "$source_file" "$destination"
chmod 644 "$destination"
relative="reports/$(basename "$destination")"
printf 'Validated report: %s\n' "$relative"

if [[ "$submit" == yes ]]; then
  branch="test/ram-$timestamp"
  git switch -c "$branch"
  git add "$relative"
  git commit -m "test: add sanitized MicroScale RAM smoke results"
  git push -u origin "$branch"
  gh pr create --base main --head "$branch" \
    --title "test: RAM-only MicroScale results $timestamp" \
    --body "RAM-only CLI/daemon-version smoke results. No device identifiers, addresses, Tailnet data or credentials. Tests are not evidence of VPN routing functionality."
else
  printf 'To create a PR from this clone later:\n'
  printf '  git switch -c test/ram-%s\n' "$timestamp"
  printf '  git add %s && git commit -m "test: RAM smoke results"\n' "$relative"
  printf '  git push -u origin HEAD && gh pr create --fill\n'
fi
