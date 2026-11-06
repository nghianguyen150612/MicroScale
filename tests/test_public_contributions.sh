#!/usr/bin/env bash
set -Eeuo pipefail

bash -n scripts/import-report.sh
bash -n scripts/collect-device-report.sh
bash scripts/import-report.sh --help | grep -q '\-\-device'
bash scripts/collect-device-report.sh --help | grep -q '\-\-submit'

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
header='utc	platform	arch	profile	release	elf_bytes	ram_total_kib	ram_available_kib	cli_version	daemon_version	cli_help	cli_peak_rss_kib	cli_elapsed_s	result'
printf '%s\n' "$header" > "$fixture/good.tsv"
printf '%s\n' '2026-11-06T07:00:00Z	openwrt	arm64	micro	v0.2.1	13369504	492120	120000	ok	ok	ok	44752	0.01	PASS' >> "$fixture/good.tsv"
bash scripts/import-report.sh --validate-only "$fixture/good.tsv" | grep -q 'PASS'
if bash scripts/import-report.sh --validate-only --device 

printf '%s\n' "$header" > "$fixture/invalid.tsv"
printf '%s\n' '2026-11-06T07:00:00Z	openwrt	arm64	micro	v0.2.1	13369504	492120	120000	ok	ok	ok	44752	0.01	PASS	SECRET' >> "$fixture/invalid.tsv"
if bash scripts/import-report.sh --validate-only "$fixture/invalid.tsv" >/dev/null 2>&1; then
  echo 'FAIL: accepted a report with an unsafe extra column' >&2; exit 1
fi
ln -s "$fixture/good.tsv" "$fixture/link.tsv"
if bash scripts/import-report.sh --validate-only "$fixture/link.tsv" >/dev/null 2>&1; then
  echo 'FAIL: accepted symlinked report' >&2; exit 1
fi

mkdir -p "$fixture/clone/scripts" "$fixture/mockbin"
cp scripts/import-report.sh "$fixture/clone/scripts/import-report.sh"
/usr/bin/git -C "$fixture/clone" init -q -b main
/usr/bin/git -C "$fixture/clone" config user.name 'CI Test'
/usr/bin/git -C "$fixture/clone" config user.email 'ci@example.invalid'
printf 'fixture\n' > "$fixture/clone/README.md"
/usr/bin/git -C "$fixture/clone" add .
/usr/bin/git -C "$fixture/clone" commit -qm 'fixture'

# A fake gh client proves public users can fork, push, and open a PR
# without sending any traffic to GitHub during unit testing.
cat > "$fixture/mockbin/gh" <<'MOCKGH'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$1 $2" in
  'auth status') exit 0 ;;
  'api user') echo publictester; exit 0 ;;
  'api repos/publictester/MicroScale')
    [[ -f "$MOCK_ROOT/fork-created" ]] || exit 1
    if [[ "${3:-}" == "--jq" ]]; then
      echo nghianguyen150612/MicroScale
    else
      echo '{}'
    fi
    exit 0 ;;
  'repo fork')
    [[ "$3" == "nghianguyen150612/MicroScale" ]] || exit 1
    [[ "$4" == "--clone=false" ]] || exit 1
    touch "$MOCK_ROOT/fork-created"
    exit 0 ;;
  'pr create')
    printf '%s\n' "$@" > "$MOCK_ROOT/pr-args"
    echo 'https://github.com/nghianguyen150612/MicroScale/pull/999'
    exit 0 ;;
esac
echo "Unexpected fake gh invocation: $*" >&2
exit 1
MOCKGH
cat > "$fixture/mockbin/git" <<'MOCKGIT'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$1" == push ]]; then
  printf '%s\n' "$@" > "$MOCK_ROOT/git-push"
  exit 0
fi
exec /usr/bin/git "$@"
MOCKGIT
chmod 755 "$fixture/mockbin/gh" "$fixture/mockbin/git"

(
  cd "$fixture/clone"
  PATH="$fixture/mockbin:$PATH" MOCK_ROOT="$fixture" \
    bash scripts/import-report.sh --submit --device 'NanoPi R5S' "$fixture/good.tsv"
)
test -f "$fixture/fork-created"
grep -Fxq 'https://github.com/publictester/MicroScale.git' "$fixture/git-push"
grep -q 'publictester:community/ram-' "$fixture/pr-args"
grep -Fxq 'nghianguyen150612/MicroScale' "$fixture/pr-args"
test "$(find "$fixture/clone/reports/community" -name '*.tsv' -type f | wc -l)" -eq 1

(
  cd "$fixture/clone"
  PATH="$fixture/mockbin:$PATH" MOCK_ROOT="$fixture" \
    bash scripts/import-report.sh --submit "$fixture/good.tsv"
)
# The new submission is based on main, not on the first submission.
test "$(find "$fixture/clone/reports/community" -name '*.tsv' -type f | wc -l)" -eq 1
test "$(cd "$fixture/clone" && /usr/bin/git diff --name-only main HEAD | wc -l)" -eq 1

echo 'PASS: community schema, forks and isolated report PR branches'
Router\nFake-certified' "$fixture/good.tsv" >/dev/null 2>&1; then
  echo 'FAIL: multiline public model label accepted' >&2; exit 1
fi

printf '%s\n' "$header" > "$fixture/invalid.tsv"
printf '%s\n' '2026-11-06T07:00:00Z	openwrt	arm64	micro	v0.2.1	13369504	492120	120000	ok	ok	ok	44752	0.01	PASS	SECRET' >> "$fixture/invalid.tsv"
if bash scripts/import-report.sh --validate-only "$fixture/invalid.tsv" >/dev/null 2>&1; then
  echo 'FAIL: accepted a report with an unsafe extra column' >&2; exit 1
fi
ln -s "$fixture/good.tsv" "$fixture/link.tsv"
if bash scripts/import-report.sh --validate-only "$fixture/link.tsv" >/dev/null 2>&1; then
  echo 'FAIL: accepted symlinked report' >&2; exit 1
fi

mkdir -p "$fixture/clone/scripts" "$fixture/mockbin"
cp scripts/import-report.sh "$fixture/clone/scripts/import-report.sh"
/usr/bin/git -C "$fixture/clone" init -q -b main
/usr/bin/git -C "$fixture/clone" config user.name 'CI Test'
/usr/bin/git -C "$fixture/clone" config user.email 'ci@example.invalid'
printf 'fixture\n' > "$fixture/clone/README.md"
/usr/bin/git -C "$fixture/clone" add .
/usr/bin/git -C "$fixture/clone" commit -qm 'fixture'

# A fake gh client proves public users can fork, push, and open a PR
# without sending any traffic to GitHub during unit testing.
cat > "$fixture/mockbin/gh" <<'MOCKGH'
#!/usr/bin/env bash
set -Eeuo pipefail
case "$1 $2" in
  'auth status') exit 0 ;;
  'api user') echo publictester; exit 0 ;;
  'api repos/publictester/MicroScale')
    [[ -f "$MOCK_ROOT/fork-created" ]] || exit 1
    if [[ "${3:-}" == "--jq" ]]; then
      echo nghianguyen150612/MicroScale
    else
      echo '{}'
    fi
    exit 0 ;;
  'repo fork')
    [[ "$3" == "nghianguyen150612/MicroScale" ]] || exit 1
    [[ "$4" == "--clone=false" ]] || exit 1
    touch "$MOCK_ROOT/fork-created"
    exit 0 ;;
  'pr create')
    printf '%s\n' "$@" > "$MOCK_ROOT/pr-args"
    echo 'https://github.com/nghianguyen150612/MicroScale/pull/999'
    exit 0 ;;
esac
echo "Unexpected fake gh invocation: $*" >&2
exit 1
MOCKGH
cat > "$fixture/mockbin/git" <<'MOCKGIT'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$1" == push ]]; then
  printf '%s\n' "$@" > "$MOCK_ROOT/git-push"
  exit 0
fi
exec /usr/bin/git "$@"
MOCKGIT
chmod 755 "$fixture/mockbin/gh" "$fixture/mockbin/git"

(
  cd "$fixture/clone"
  PATH="$fixture/mockbin:$PATH" MOCK_ROOT="$fixture" \
    bash scripts/import-report.sh --submit --device 'NanoPi R5S' "$fixture/good.tsv"
)
test -f "$fixture/fork-created"
grep -Fxq 'https://github.com/publictester/MicroScale.git' "$fixture/git-push"
grep -q 'publictester:community/ram-' "$fixture/pr-args"
grep -Fxq 'nghianguyen150612/MicroScale' "$fixture/pr-args"
test "$(find "$fixture/clone/reports/community" -name '*.tsv' -type f | wc -l)" -eq 1

(
  cd "$fixture/clone"
  PATH="$fixture/mockbin:$PATH" MOCK_ROOT="$fixture" \
    bash scripts/import-report.sh --submit "$fixture/good.tsv"
)
# The new submission is based on main, not on the first submission.
test "$(find "$fixture/clone/reports/community" -name '*.tsv' -type f | wc -l)" -eq 1
test "$(cd "$fixture/clone" && /usr/bin/git diff --name-only main HEAD | wc -l)" -eq 1

echo 'PASS: community schema, forks and isolated report PR branches'
