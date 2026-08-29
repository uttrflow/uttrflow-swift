#!/bin/bash
# Drives Uttrflow's own interface and checks that pressing things changes what it says.
#
# Not screenshots. A screenshot proves a page was drawn; this presses a control and then
# asks the interface what changed — the only way to tell a button that works from one that
# draws correctly and does nothing, which is a failure this product has had repeatedly.
#
#   ./Scripts/UITests/run.sh [rounds]
#
# Needs the app installed at /Applications/Uttrflow.app and Accessibility granted to
# whatever runs this. Every round leaves the stores as it found them.
set -euo pipefail
cd "$(dirname "$0")"
ROUNDS="${1:-1}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if ! pgrep -f "Uttrflow.app/Contents/MacOS/Uttrflow" >/dev/null; then
  echo "Uttrflow is not running. Build it with 'make app', copy it to /Applications and open it."
  exit 2
fi

BIN="$(mktemp -d)/uitest"
xcrun swiftc -O UITest.swift -o "$BIN"
"$BIN" "$ROUNDS"
