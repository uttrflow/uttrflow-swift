#!/usr/bin/env bash
#
# Enforces the per-module line-coverage floor.
#
# Coverage is gated per module rather than across the package so that a large,
# well-tested module cannot mask an untested one.
set -euo pipefail

THRESHOLD="${COVERAGE_THRESHOLD:-95}"
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PACKAGE_ROOT"

# Exclusions and their reasons live in coverage_report.py, which prints them.

# CI has been losing this run's output entirely on an intermittent crash: the log just
# stops, with no error and no exit code, well before the timeout. Tee-ing to a file means
# the run's own output survives on disk even if the terminal stream that produced it dies
# mid-write, so a later step can still show what the crash interrupted.
TEST_LOG="$PACKAGE_ROOT/.build/swift-test-output.log"
mkdir -p "$(dirname "$TEST_LOG")"
set +e
swift test --enable-code-coverage "$@" 2>&1 | tee "$TEST_LOG"
TEST_STATUS="${PIPESTATUS[0]}"
set -e
if [[ "$TEST_STATUS" -ne 0 ]]; then
    echo "error: swift test exited $TEST_STATUS — last 300 lines of $TEST_LOG:" >&2
    tail -n 300 "$TEST_LOG" >&2
    exit "$TEST_STATUS"
fi
python3 "$PACKAGE_ROOT/Scripts/live_model_tally.py" "$TEST_LOG"

BIN_PATH="$(swift build --show-bin-path)"
PROFDATA="$BIN_PATH/codecov/default.profdata"
TEST_BINARY="$(find "$BIN_PATH" -name '*.xctest' -maxdepth 1 -print -quit)/Contents/MacOS/$(basename "$(find "$BIN_PATH" -name '*.xctest' -maxdepth 1 -print -quit)" .xctest)"

if [[ ! -f "$PROFDATA" || ! -f "$TEST_BINARY" ]]; then
    echo "error: coverage artifacts not found (profdata: $PROFDATA, binary: $TEST_BINARY)" >&2
    exit 1
fi

xcrun llvm-cov export \
    -instr-profile "$PROFDATA" \
    -format=text \
    "$TEST_BINARY" \
    | THRESHOLD="$THRESHOLD" PACKAGE_ROOT="$PACKAGE_ROOT" \
      python3 "$PACKAGE_ROOT/Scripts/coverage_report.py"
