#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 VERSION" >&2
    exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

{
    "$script_dir/changelog.py" "$1"
    printf '\n---\n\n- Download: https://uttrflow.com/download\n'
    printf -- '- Every build: https://github.com/uttrflow/releases/releases\n'
}
