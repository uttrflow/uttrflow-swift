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

# A call that creates a folder, or a file, or writes a file's bytes. `open(..., O_CREAT, ...)` is
# here because it takes its mode as an argument, so a wrong one is as quiet as an absent one.
PATTERNS = [
    (re.compile(r"\bcreateDirectory\("), "createDirectory"),
    (re.compile(r"\bcreateFile\(atPath:"), "createFile"),
    (re.compile(r"\.write\(to(?:File)?:"), "write(to:)"),
    (re.compile(r"\bO_CREAT\b"), "open(O_CREAT)"),
]

# Each path that may still write for itself, what it is allowed to call, and why. `None` for the
# calls means every one of them; a named set means only those, so a file excused one call is still
# held to the rest.
ALLOWED = {
    "UttrflowCore/Support/PrivateFile.swift": (
        None, "is the helper every other path goes through"),
    "UttrflowEval/": (None, "the evaluation harness, which never ships and writes no user data"),
    "uttrflow-bakeoff/": (None, "a developer tool, run from a terminal against a corpus"),
    "uttrflow-dev/": (None, "a developer tool, run from a terminal"),
    "uttrflow-eval/": (None, "a developer tool, run from a terminal"),
    "UttrflowSpeech/SpeechModelStore.swift": (
        None, "stages downloaded model weights, which are public"),
    "UttrflowSpeech/TokenizerDownload.swift": (
        None, "writes a downloaded tokenizer, which is public"),
    "UttrflowCore/Support/SingleInstanceLock.swift": (
        {"open(O_CREAT)"}, "opens its lock 0600, and needs the descriptor to flock it"),
    "UttrflowAudio/RecordingWriter.swift": (
        {"open(O_CREAT)"}, "opens each recording 0600, and writes through the descriptor"),
}


def allowed(relative, call):
    """Whether this path may make this call for itself."""
    for prefix, (calls, _) in ALLOWED.items():
        if relative == prefix or relative.startswith(prefix):
            return calls is None or call in calls
    return False


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
        with open(path, encoding="utf-8", errors="ignore") as handle:
            for number, line in enumerate(handle, start=1):
                if line.lstrip().startswith("//"):
                    continue
                for pattern, name in PATTERNS:
                    if pattern.search(line) and not allowed(relative, name):
                        found.append((relative, number, name, line.strip()))
    return found


def main():
    print("\nWhat may write its own files")
    for prefix, (calls, reason) in ALLOWED.items():
        named = "every call" if calls is None else ", ".join(sorted(calls))
        print(f"  ✓ {prefix} ({named}) — {reason}")

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
