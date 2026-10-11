#!/bin/bash
# The recipe shell for `make verify`, which runs its checks side by side: each recipe line's
# output is held until the line finishes and then printed whole, so two checks never interleave.
output="$(mktemp "${TMPDIR:-/tmp}/uttrflow-verify.XXXXXX")"
trap 'rm -f "$output"' EXIT
/bin/bash "$@" >"$output" 2>&1
status=$?
cat "$output"
exit "$status"
