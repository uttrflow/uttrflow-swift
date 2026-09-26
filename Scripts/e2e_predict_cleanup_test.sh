#!/usr/bin/env bash
set -euo pipefail

# Proves the live prediction harness removes its scratch directory and compiled helper on
# exit, including a preflight failure — before any app is driven or a key is sent.
#
# mktemp -d on macOS ignores $TMPDIR (it prefers the per-user Darwin temp directory), so
# the only reliable way to find the harness's own WORK directory is to read it back out
# of an xtrace, rather than pointing $TMPDIR somewhere this test controls.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT

# Does not exist, so the harness's first preflight check ("no log at ...") fails before it
# compiles the helper, opens an app, or sends a key.
missing_log="$test_tmp/no-such-log.txt"
report="$test_tmp/report.md"
trace="$test_tmp/trace.log"

set +e
PREDICT_LOG="$missing_log" bash -x "$repo_root/Scripts/e2e_predict.sh" "$report" >"$test_tmp/output.log" 2>"$trace"
status=$?
set -e

if [ "$status" -ne 2 ]; then
    echo "error: expected the missing-log preflight check to exit 2, got $status" >&2
    cat "$test_tmp/output.log" "$trace" >&2
    exit 1
fi

work="$(LC_ALL=C sed -n 's/^+ WORK=//p' "$trace" | head -n1)"  # the trace carries non-UTF-8 bytes BSD sed rejects under a UTF-8 locale
if [ -z "$work" ]; then
    echo "error: could not find the harness's WORK directory in its trace" >&2
    exit 1
fi

if [ -e "$work" ]; then
    echo "error: a preflight failure left the scratch directory behind: $work" >&2
    rm -rf "$work"
    exit 1
fi

printf 'e2e predict cleanup test passed\n'
