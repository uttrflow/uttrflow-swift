#!/usr/bin/env bash
#
# Asserts that only the two clipboard adapters name `NSPasteboard`.
#
# The platform clipboard offers everything written to it to every Apple device signed into
# the same account, and `prepareForNewContents(with: .currentHostOnly)` is the one line that
# stops it. That line lives in `SystemPasteboard`, along with announcing the write so the
# watcher does not read it back as the user's own copy. A call site that reaches
# `NSPasteboard` directly has neither, so it sends the user's transcript to their phone and
# files it again as a copy.
#
# The rule is therefore structural rather than remembered: one adapter writes the clipboard,
# one reads it, and nothing else in the product knows the platform type exists.
#
# Usage:  ./Scripts/pasteboard_audit.sh
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PACKAGE_ROOT"

# The writer and the reader. Both are excluded from the coverage gate for the same reason:
# they are the untestable edge where the real clipboard begins.
ALLOWED=(
    "Sources/UttrflowInput/SystemInput.swift"
    "Sources/UttrflowClipboard/ClipboardSource+System.swift"
)

printf '\nWho may name NSPasteboard\n'

offenders=()
while IFS= read -r file; do
    allowed=0
    for permitted in "${ALLOWED[@]}"; do
        [[ "$file" == "$permitted" ]] && allowed=1
    done
    [[ $allowed -eq 1 ]] || offenders+=("$file")
done < <(grep -rl --include='*.swift' 'NSPasteboard' Sources | sort)

for permitted in "${ALLOWED[@]}"; do
    if [[ ! -f "$permitted" ]]; then
        printf '  \033[31m✗\033[0m %s is gone; this audit names a file that no longer exists\n' "$permitted" >&2
        exit 1
    fi
done

if [[ ${#offenders[@]} -gt 0 ]]; then
    printf '\n  \033[31m✗\033[0m %d file(s) reach the platform clipboard directly:\n' "${#offenders[@]}" >&2
    for file in "${offenders[@]}"; do printf '    %s\n' "$file" >&2; done
    printf '    A direct write misses the announcement and `.currentHostOnly`, so the text\n' >&2
    printf '    reaches every device signed into the same account. Go through `Pasteboard`.\n\n' >&2
    exit 1
fi

printf '  ✓ only the writer and the reader name it: %s\n' "${ALLOWED[*]}"
printf '\npasteboard audit: every other write goes through the port.\n\n'
