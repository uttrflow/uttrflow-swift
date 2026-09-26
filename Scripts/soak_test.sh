#!/usr/bin/env bash
# Proves soak.sh's growth report compares the union of class names — see #827. An inner
# join silently dropped any class absent from the first snapshot, which hid exactly the
# new object populations a long-running accumulation investigation needs to see.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

first="$test_root/sample-1.tsv"
last="$test_root/sample-6.tsv"

# Four cases in one pair of snapshots: a class that grew, a brand-new class absent from
# the first snapshot, a class that vanished by the last snapshot, and a class name with
# an internal space, to prove the tab-delimited parsing does not split on it.
printf '10\tExistingClass\n5\tVanishingClass\n7\tClass With Spaces\n' > "$first"
printf '11\tExistingClass\n1000\tNewlyLeakedClass\n9\tClass With Spaces\n' > "$last"

report="$("$repo_root/Scripts/soak.sh" --compare "$first" "$last")"

if ! grep -q 'NewlyLeakedClass' <<<"$report"; then
    echo "error: a class absent from the first snapshot did not appear in the report:" >&2
    printf '%s\n' "$report" >&2
    exit 1
fi
if ! grep -qE '^ *1000 +0.*NewlyLeakedClass' <<<"$report"; then
    echo "error: NewlyLeakedClass did not report its full count as growth from zero:" >&2
    printf '%s\n' "$report" >&2
    exit 1
fi
if grep -q 'VanishingClass' <<<"$report"; then
    echo "error: a class that disappeared by the last snapshot was reported as positive growth:" >&2
    printf '%s\n' "$report" >&2
    exit 1
fi
if ! grep -qE '^ *1 +10.*ExistingClass' <<<"$report"; then
    echo "error: an existing class's growth was not reported correctly:" >&2
    printf '%s\n' "$report" >&2
    exit 1
fi
if ! grep -q 'Class With Spaces' <<<"$report"; then
    echo "error: a class name containing spaces did not survive parsing:" >&2
    printf '%s\n' "$report" >&2
    exit 1
fi

# The original snapshots stay on disk afterward, for manual investigation.
if [[ ! -f "$first" || ! -f "$last" ]]; then
    echo "error: comparing the snapshots must not delete or overwrite them" >&2
    exit 1
fi
if [[ "$(cat "$first")" != $'10\tExistingClass\n5\tVanishingClass\n7\tClass With Spaces' ]]; then
    echo "error: the first snapshot was modified by the comparison" >&2
    exit 1
fi

printf 'soak growth-report test passed\n'
