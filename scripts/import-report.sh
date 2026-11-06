#!/usr/bin/env bash
# Accept allowlisted RAM measurements and optionally open a community PR.
# GitHub authentication is required only on the contributor's workstation.
set -Eeuo pipefail

UPSTREAM=nghianguyen150612/MicroScale
fail() { printf 'MicroScale report: %s\n' "$*" >&2; exit 1; }
usage() {
  printf 'Usage: bash scripts/import-report.sh [--validate-only|--submit] [--device MODEL] FILE.tsv\n'
}

submit=false
validate_only=false
device=""
while (($#)); do
  case "$1" in
    --submit) submit=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --device)
      (($# >= 2)) || fail 'Missing device model'
      device="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) fail "Unknown option: $1" ;;
    *) break ;;
  esac
done
(($# == 1)) || { usage >&2; exit 1; }
[[ "$submit" != true || "$validate_only" != true ]] ||
  fail '--submit and --validate-only cannot be combined'
if [[ -n "$device" ]]; then
  [[ ${#device} -le 80 && "$device" =~ ^[[:alnum:]][[:alnum:][:space:]._+()/,-]*$ ]] ||
    fail 'Device model must contain only printable model-name characters (max 80)'
fi

# Check the caller's path BEFORE resolving symlinks.
[[ -f "$1" && ! -L "$1" ]] || fail 'Missing or symlinked input file'
source_file="$(realpath "$1")"
bytes="$(wc -c < "$source_file" | tr -d ' ')"
[[ "$bytes" =~ ^[0-9]+$ && "$bytes" -le 262144 ]] ||
  fail 'Report is too large (maximum 256 KiB)'

# Only an allowlisted TSV schema is accepted; no logs, IPs, hostnames or secrets.
awk -F '\t' '
  BEGIN {
    header="utc\tplatform\tarch\tprofile\trelease\telf_bytes\tram_total_kib\tram_available_kib\tcli_version\tdaemon_version\tcli_help\tcli_peak_rss_kib\tcli_elapsed_s\tresult"
    bad=0
  }
  NR==1 { if ($0!=header) bad=1; next }
  {
    if (NF!=14 || NR>1001) bad=1
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
' "$source_file" || fail 'Invalid report, unsupported columns or potential sensitive data'
if [[ "$validate_only" == true ]]; then
  echo 'PASS: sanitized RAM report schema'
  exit 0
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ -d .git ]] || fail 'Clone MicroScale with git before importing'
if [[ "$submit" == true ]]; then
  for dep in git gh; do command -v "$dep" >/dev/null || fail "Missing $dep"; done
  [[ -z "$(git status --porcelain)" ]] ||
    fail 'Your Git worktree must be clean before opening a PR'
  gh auth status >/dev/null || fail 'Run gh auth login on your workstation'
  login="$(gh api user --jq .login)" || fail 'Cannot determine GitHub account'
  [[ "$login" =~ ^[A-Za-z0-9-]+$ ]] || fail 'Invalid GitHub account name'
  if [[ "$login" == "${UPSTREAM%%/*}" ]]; then
    push_url="https://github.com/$UPSTREAM.git"
  else
    fork="$login/MicroScale"
    if gh api "repos/$fork" >/dev/null 2>&1; then
      parent="$(gh api "repos/$fork" --jq '.parent.full_name // ""')" ||
        fail 'Cannot inspect existing repository'
      [[ "$parent" == "$UPSTREAM" ]] ||
        fail "Existing $fork is not a fork of $UPSTREAM"
    else
      echo "Creating your public fork: $fork"
      gh repo fork "$UPSTREAM" --clone=false ||
        fail "Could not create fork $fork"
    fi
    push_url="https://github.com/$fork.git"
  fi
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p reports/community
destination="$(mktemp "$root/reports/community/ram-$stamp-XXXXXX.tsv")"
cp "$source_file" "$destination"
chmod 644 "$destination"
relative="${destination#"$root/"}"
printf 'Sanitized report: %s\n' "$relative"

if [[ "$submit" == false ]]; then
  printf 'To submit: bash scripts/import-report.sh --submit "%s"\n' "$source_file"
  exit 0
fi

branch="community/ram-$stamp-$(basename "$destination" .tsv | tail -c 7)"
git switch -c "$branch"
git add -- "$relative"
git commit -m "test: submit community RAM measurements"
if ! git push "$push_url" "HEAD:refs/heads/$branch"; then
  fail 'Could not push to your fork. On your workstation run: gh auth setup-git, then retry git push'
fi

body='Community-submitted RAM-only Tailscale CLI/daemon smoke results.

- Verification: strict TSV schema and checksum-pinned release test runner
- Scope: version/help smoke checks only; NOT evidence of VPN dataplane, Exit Node, reboot persistence or endurance
- Source: contributor-reported, not independently hardware-attested
- Privacy: no hostnames, IP addresses, auth keys, Tailnet data or raw process logs

Please check the submitted TSV and device details before merging.'
if [[ -n "$device" ]]; then
  body="$body

- Contributor-disclosed device model: $device (unverified, no serial numbers)"
fi
gh pr create --repo "$UPSTREAM" --base main --head "$login:$branch" \
  --title "test: community RAM report ($stamp)" --body "$body" ||
  fail 'Branch pushed, but GitHub PR creation failed; create a PR from the pushed branch'
