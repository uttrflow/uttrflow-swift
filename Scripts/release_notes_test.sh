#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/Scripts"
cp "$repo_root/Scripts/changelog.py" "$test_root/Scripts/changelog.py"
cp "$repo_root/CHANGELOG.md" "$test_root/CHANGELOG.md"

notes="$("$repo_root/Scripts/release_notes.sh" 26.0926.0)"
[[ -n "$notes" ]] || { echo "error: release notes were empty" >&2; exit 1; }
grep -Fq -- '- Download: https://uttrflow.com/download' <<<"$notes" || {
    echo "error: release notes omitted the download link" >&2
    exit 1
}
grep -Fq -- '- Every build: https://github.com/uttrflow/releases/releases' <<<"$notes" || {
    echo "error: release notes omitted the every-build link" >&2
    exit 1
}
if "$repo_root/Scripts/release_notes.sh" 0.0.0 >"$test_root/missing.out" 2>"$test_root/missing.err"; then
    echo "error: release notes rendered a version with no changelog section" >&2
    exit 1
fi

cp "$repo_root/Scripts/release_notes.sh" "$test_root/Scripts/release_notes.sh"
if grep -Fq -- '- Accuracy report:' <<<"$("$test_root/Scripts/release_notes.sh" 26.0926.0)"; then
    echo "error: release notes linked an accuracy report that was never written" >&2
    exit 1
fi
mkdir -p "$test_root/Docs/accuracy-reports"
printf '# Accuracy report\n' > "$test_root/Docs/accuracy-reports/26.0926.0.md"
reported="$("$test_root/Scripts/release_notes.sh" 26.0926.0)"
grep -Fq -- '- Accuracy report: https://github.com/uttrflow/uttrflow-swift/blob/v26.0926.0/Docs/accuracy-reports/26.0926.0.md' <<<"$reported" || {
    echo "error: release notes omitted the accuracy report path" >&2
    exit 1
}

sed "s/printf -- '- Every build:/printf '- Every build:/" \
    "$repo_root/Scripts/release_notes.sh" > "$test_root/Scripts/release_notes.sh"
chmod +x "$test_root/Scripts/release_notes.sh"
if "$test_root/Scripts/release_notes.sh" 26.0926.0 >"$test_root/bug.out" 2>"$test_root/bug.err"; then
    echo "error: release notes passed with the old leading-dash printf bug" >&2
    exit 1
fi

printf 'release notes test passed, including the accuracy report path and the leading-dash printf regression\n'
