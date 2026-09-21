#!/usr/bin/env python3
"""Proves nothing in the shipped app makes a folder or writes a file except through PrivateFile."""

# The local store holds what was dictated, what was copied and what the suggestions learned, and
# none of it is ever sent anywhere — so the file modes are the whole of its protection. Foundation
# writes under the process umask, which is 022 on a Mac, so a plain `data.write(to:)` lands at 0644
# and a plain `createDirectory` at 0755. `PrivateFile` is the one place that writes 0600 into 0700.
#
# This audit exists because the fix is mechanical and the coverage is not: a store added next year
# will reach for `data.write(to:)` like every store before it did, and nothing about that line looks
# wrong. Docs/local-store-permissions.md is the longer form.
#
# Every allowed path states its reason here and prints it on every run, the way the coverage
# exclusions do. An exclusion is never silent.

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Sources")

# A call that creates a folder or writes a file's bytes.
PATTERNS = [
    (re.compile(r"\bcreateDirectory\("), "createDirectory"),
    (re.compile(r"\bcreateFile\(atPath:"), "createFile"),
    (re.compile(r"\.write\(to(?:File)?:"), "write(to:)"),
]

# Each path that may still write for itself, and why it is allowed to.
ALLOWED = {
    "UttrflowCore/Support/PrivateFile.swift": "is the helper every other path goes through",
    "UttrflowEval/": "the evaluation harness, which never ships and writes no user data",
    "uttrflow-bakeoff/": "a developer tool, run from a terminal against a corpus",
    "uttrflow-dev/": "a developer tool, run from a terminal",
    "uttrflow-eval/": "a developer tool, run from a terminal",
    "UttrflowSpeech/SpeechModelStore.swift": "stages downloaded model weights, which are public",
    "UttrflowSpeech/TokenizerDownload.swift": "writes a downloaded tokenizer, which is public",
}


def allowed(relative):
    """The reason this path may write for itself, or nothing if it may not."""
    for prefix, reason in ALLOWED.items():
        if relative == prefix or relative.startswith(prefix):
            return reason
    return None


def swift_files():
    for folder, _, names in os.walk(SOURCES):
        for name in sorted(names):
            if name.endswith(".swift"):
                path = os.path.join(folder, name)
                yield path, os.path.relpath(path, SOURCES)


def findings():
    """Every line outside the allowed paths that creates a folder or writes a file itself."""
    found = []
    for path, relative in swift_files():
        if allowed(relative):
            continue
        with open(path, encoding="utf-8", errors="ignore") as handle:
            for number, line in enumerate(handle, start=1):
                if line.lstrip().startswith("//"):
                    continue
                for pattern, name in PATTERNS:
                    if pattern.search(line):
                        found.append((relative, number, name, line.strip()))
    return found


def main():
    print("\nWhat may write its own files")
    for prefix, reason in ALLOWED.items():
        print(f"  ✓ {prefix} — {reason}")

    found = findings()
    if found:
        print("\nWriting outside PrivateFile, where the mode is nobody's decision:")
        for relative, number, name, line in found:
            print(f"  ✗ Sources/{relative}:{number}: {name} — {line}")
        print(
            "\nA folder made this way is 0755 and a file written this way is 0644. Write through"
            "\n`PrivateFile`, or state here why this path is different. See"
            "\nDocs/local-store-permissions.md."
        )
        return 1

    print("\nstore permissions audit: every local store writes for its owner alone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
