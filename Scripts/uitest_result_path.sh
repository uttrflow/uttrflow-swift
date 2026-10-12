#!/usr/bin/env bash
# Clears the way for xcodebuild's -resultBundlePath, which refuses to run if that path exists.
set -euo pipefail

path="${1:?usage: uitest_result_path.sh <resultBundlePath>}"

# A prior run's bundle is moved aside, not deleted, so it stays on disk for debugging; the
# timestamp in its name is what makes a second archive in the same second not collide.
if [[ -e "$path" || -L "$path" ]]; then
    stamp="$(date +%Y%m%dT%H%M%S)"
    base="${path%.xcresult}"
    archived="${base}-${stamp}.xcresult"
    suffix=1
    while [[ -e "$archived" || -L "$archived" ]]; do
        archived="${base}-${stamp}-${suffix}.xcresult"
        suffix=$((suffix + 1))
    done
    mv "$path" "$archived"
    printf 'Previous UI test result kept at %s\n' "$archived" >&2
fi

printf '%s\n' "$path"
