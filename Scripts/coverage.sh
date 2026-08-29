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

swift test --enable-code-coverage "$@"

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
