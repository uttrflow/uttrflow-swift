#!/usr/bin/env python3
"""Counts text split into words by a hand-written separator outside WordTokens, and stops the count ever rising."""

import argparse
import os
import re
import sys

import ratchet
from closed_list_audit import without_comments

ROOTS = (
    os.path.join("Sources", "UttrflowAI"),
    os.path.join("Sources", "UttrflowPipeline"),
    os.path.join("Sources", "UttrflowCore", "Cleaning"),
    os.path.join("Sources", "UttrflowEval"),
)
BASELINE = os.path.join("Scripts", "word_split_baseline.json")

# The one file allowed to decide where a word ends.
SEAM = "WordTokens.swift"

# A separator chosen per call: the labelled argument, or the same predicate as a trailing closure.
SPLIT = re.compile(r"\.split\s*(?:\(\s*whereSeparator\s*:|\{)")


def findings_in(path):
    """Yields (line_number, line_text) for every hand-written word split in the file."""
    with open(path, errors="ignore") as source:
        text = source.read()
    code = without_comments(text)
    lines = text.splitlines()
    for match in SPLIT.finditer(code):
        line = code.count("\n", 0, match.start()) + 1
        yield line, lines[line - 1].strip() if line <= len(lines) else ""


def swift_files():
    for root in ROOTS:
        for directory, _, names in os.walk(root):
            for name in sorted(names):
                if name.endswith(".swift") and name != SEAM:
                    yield os.path.join(directory, name)


def survey():
    counts, detail = {}, []
    for path in swift_files():
        found = list(findings_in(path))
        if found:
            counts[path] = len(found)
            detail += [(path, line, text) for line, text in found]
    return counts, detail


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    ratchet.add_arguments(parser)
    parser.add_argument("--report", action="store_true", help="list every hand-written word split, with its line")
    arguments = parser.parse_args()

    counts, detail = survey()
    total = sum(counts.values())

    if arguments.report:
        for path, line, text in detail:
            print(f"{path}:{line}  {text}")
        print(f"\n{total} hand-written word splits in {len(counts)} files")
        return 0

    if arguments.update:
        return ratchet.update(BASELINE, counts, "hand-written word splits", "a split to move onto WordTokens later", arguments.after_merge)

    baseline = ratchet.load(BASELINE)
    if not baseline:
        return ratchet.missing(BASELINE, sys.argv[0])

    recorded = baseline.get("files", {})
    failures = [f"{path}:{line}  {text}" for path, line, text in detail if counts[path] > recorded.get(path, 0)]

    if failures:
        print("Where a word ends is decided once, in WordTokens, not at each call site.")
        print("These files gained a split with a hand-written separator:\n")
        for failure in failures:
            print(f"  {failure}")
        print("\nCall WordTokens with the profile the caller needs instead.")
        print("See Docs/agents/code-quality.md, \"Word splits\".")
        return 1

    print(f"Hand-written word splits: {total}, none higher than the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
