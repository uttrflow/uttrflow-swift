#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 VERSION" >&2
    exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
report="Docs/accuracy-reports/$1.md"

{
    "$script_dir/changelog.py" "$1"
    printf '\n---\n\n- Download: https://uttrflow.com/download\n'
    printf -- '- Every build: https://github.com/uttrflow/releases/releases\n'
    if [[ -f "$script_dir/../$report" ]]; then
        printf -- '- Accuracy report: https://github.com/uttrflow/uttrflow-swift/blob/v%s/%s\n' "$1" "$report"
    fi
}
