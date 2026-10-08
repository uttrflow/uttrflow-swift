#!/bin/bash
# Drives `uttrflow-dev insert` into the insertion fixture once per fault mode, only while nobody is at this Mac.
#
#   ./Scripts/e2e_insertion.sh [max-idle-wait-seconds] [mode-regex]
#
# Needs Accessibility granted to the shell running it. Each case launches the fixture with one mode, inserts
# into its focused field, then asserts the line `insert` prints, its exit status, and what the field holds.
# The fixture and its modes are in Docs/insertion.md under "The insertion fixture".
set -euo pipefail

MAX_WAIT="${1:-600}"
ONLY="${2:-.}"
IDLE_REQUIRED=30
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d)"
HELPER="$WORK/helper"
FIXTURE_PID=""
finish() {
  [ -n "$FIXTURE_PID" ] && kill "$FIXTURE_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap finish EXIT
# shellcheck source=idle_gate.sh
source "$HERE/idle_gate.sh"

# mode|focused field|--via|text inserted|status insert exits with|line insert prints|what the field read holds
# after|field read, when not the focused one
CASES=(
  "faithful|text|accessibility|hello there|0|Inserted via accessibility|hello there"
  "changes-nothing|text|accessibility|hello there|1||"
  "drops-keys|text|paste|hello there|0|Inserted via pasteboard, unconfirmed.|"
  "substitutes|multiline|paste|it's -- \"fine\"|0|Inserted via pasteboard, unconfirmed.|it’s — “fine”"
  "caps-length|text|accessibility|the quick brown fox|1||the quick brown "
  "late-write|text|accessibility|hello there|1||hello there"
  "steals-focus|text|paste|hello there|0|Inserted via pasteboard|hello there|multiline"
  "closes-window|text|paste|hello there|0|Inserted via pasteboard|"
  "marks-text|text|accessibility|hello there|0|Inserted via accessibility|nihello there"
)

field_value() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]], end="")' "$1" "$2"
}

run_case() {
  local mode="$1" field="$2" via="$3" text="$4" status="$5" line="$6" expected="$7" read="${8:-$2}"
  local report="$WORK/$mode.json" output actual code=0
  "$ROOT/.build/debug/uttrflow-insertion-fixture" --mode "$mode" --focus "$field" --report "$report" &
  FIXTURE_PID=$!
  for _ in $(seq 50); do [ -s "$report" ] && break; sleep 0.1; done
  sleep 0.5
  output="$("$ROOT/.build/debug/uttrflow-dev" insert --delay 0 --via "$via" "$text" 2>&1)" || code=$?
  sleep 0.3
  actual="$(field_value "$report" "$read")"
  kill "$FIXTURE_PID" 2>/dev/null; wait "$FIXTURE_PID" 2>/dev/null || true
  FIXTURE_PID=""
  if [ "$code" = "$status" ] && [ "$actual" = "$expected" ] && { [ -z "$line" ] || grep -qF "$line" <<<"$output"; }; then
    printf 'PASS %s\n' "$mode"
    return 0
  fi
  printf 'FAIL %s: exit %s (want %s), field %q (want %q)\n%s\n' "$mode" "$code" "$status" "$actual" "$expected" "$output"
  return 1
}

cd "$ROOT"
swift build --disable-sandbox --product uttrflow-insertion-fixture >/dev/null
swift build --disable-sandbox --product uttrflow-dev >/dev/null
xcrun swiftc -O "$HERE/e2e_predict_helper.swift" -o "$HELPER"

waited=0
until awk -v a="$(idle_seconds)" -v b="$IDLE_REQUIRED" 'BEGIN { exit !(a >= b) }' && ! screen_locked; do
  [ "$waited" -ge "$MAX_WAIT" ] && { echo "the user was never idle ${IDLE_REQUIRED}s within ${MAX_WAIT}s; nothing was run" >&2; exit 4; }
  sleep 5; waited=$((waited + 5))
done

failed=0
for entry in "${CASES[@]}"; do
  IFS='|' read -r mode field via text status line expected read <<<"$entry"
  [[ "$mode" =~ $ONLY ]] || continue
  screen_locked && { echo "the screen locked; stopping" >&2; exit 4; }
  run_case "$mode" "$field" "$via" "$text" "$status" "$line" "$expected" "$read" || failed=1
done
exit "$failed"
