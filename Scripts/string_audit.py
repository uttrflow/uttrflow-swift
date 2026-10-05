#!/usr/bin/env python3
"""Counts fixed English literals handed to a view per file, and stops the count ever rising."""

import argparse
import os
import re
import sys

import ratchet

SOURCES = "Sources"
BASELINE = os.path.join("Scripts", "string_baseline.json")

# A string literal as the first argument of a view that shows it to the user.
FIXED_STRING = re.compile(
    r'(?:(?<![\w.])(?:Text|Button|Label)|\.(?:help|accessibilityLabel))\(\s*#*"'
)

COMMENT = re.compile(r"^\s*//")


def literals_in(path):
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if COMMENT.match(line):
                continue
            for _ in FIXED_STRING.finditer(line):
                yield number, line.strip()


def violations(root=SOURCES):
    found = []
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            if name.endswith(".swift"):
                path = os.path.join(directory, name)
                found += [(path, f"{path}:{number}: {text}") for number, text in literals_in(path)]
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    ratchet.add_arguments(parser)
    parser.add_argument("--report", action="store_true", help="list every fixed string")
    arguments = parser.parse_args()

    found = violations()
    counts = {}
    for key, _ in found:
        counts[key] = counts.get(key, 0) + 1

    if arguments.report:
        print("\n".join(text for _, text in found))
        print(f"\n{len(found)} fixed strings in {len(counts)} files")
        return 0
    if arguments.update:
        return ratchet.update(BASELINE, counts, "fixed strings", "a view to move onto String(localized:) later", arguments.after_merge)

    baseline = ratchet.load(BASELINE)
    if not baseline:
        return ratchet.missing(BASELINE, sys.argv[0])
    rises = ratchet.risen(counts, baseline.get("files", {}))
    if rises:
        print("Strings: a view shows text through String(localized:), not a fixed literal.")
        print("These files gained a fixed string:\n")
        for key, text in found:
            if key in rises:
                print(f"  {text}")
        print("\nWrite it as String(localized: \"...\", comment: \"...\"). See Docs/localisation.md.")
        return 1

    print(f"Strings: {len(found)} fixed strings, none higher than the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
