#!/usr/bin/env python3
"""Enforces the one-line comment rule, and stops the count ever rising."""

import argparse
import json
import os
import re
import sys

ROOTS = ("Sources", "Tests")
BASELINE = os.path.join("Scripts", "comment_baseline.json")

# Words that tell the story of how the code got here rather than what it does.
HISTORY = re.compile(
    r"\b("
    r"used to|previously|formerly|originally|no longer|has happened|had happened|"
    r"this reverses|we changed|was written for|nothing ever called|"
    r"before this|until now|it was|there used to|"
    r"has since|since then|turned out|we tried|was then|"
    r"this replaces|which is what it was|at the time"
    r")\b",
    re.IGNORECASE,
)


def comment_kind(line):
    stripped = line.strip()
    if stripped.startswith("///"):
        return "///"
    # A trailing comment on a line of code is not a block and is left alone.
    if stripped.startswith("//"):
        return "//"
    return None


def blocks_in(path):
    """Yields (start_line, length, kind, text) for every run of comment lines."""
    lines = open(path, errors="ignore").read().split("\n")
    index = 0
    while index < len(lines):
        kind = comment_kind(lines[index])
        if not kind:
            index += 1
            continue
        end = index
        while end < len(lines) and comment_kind(lines[end]) == kind:
            end += 1
        yield index + 1, end - index, kind, "\n".join(lines[index:end])
        index = end


def swift_files():
    for root in ROOTS:
        for directory, _, names in os.walk(root):
            if ".build" in directory or ".claude" in directory:
                continue
            for name in sorted(names):
                if name.endswith(".swift"):
                    yield os.path.join(directory, name)


def survey():
    long_blocks = {}
    history = []
    for path in swift_files():
        count = 0
        for line, length, _, text in blocks_in(path):
            if length > 1:
                count += 1
            if HISTORY.search(text):
                history.append((path, line, HISTORY.search(text).group(0)))
        if count:
            long_blocks[path] = count
    return long_blocks, history


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true", help="record the current counts")
    parser.add_argument("--report", action="store_true", help="list what is left, worst first")
    arguments = parser.parse_args()

    long_blocks, history = survey()
    total = sum(long_blocks.values())

    if arguments.report:
        for path, count in sorted(long_blocks.items(), key=lambda item: -item[1])[:40]:
            print(f"{count:4d}  {path}")
        print(f"\n{total} multi-line comment blocks in {len(long_blocks)} files")
        print(f"{len(history)} comments written in the past tense")
        for path, line, phrase in history[:25]:
            print(f"  {path}:{line}  “{phrase}”")
        return 0

    baseline = {}
    if os.path.exists(BASELINE):
        baseline = json.load(open(BASELINE))

    if arguments.update:
        recorded = baseline.get("files", {})
        risen = {
            path: (recorded[path], count)
            for path, count in long_blocks.items()
            if path in recorded and count > recorded[path]
        }
        if risen:
            print("Refusing to record a higher count. The baseline only goes down.")
            for path, (was, now) in sorted(risen.items()):
                print(f"  {path}: {was} -> {now}")
            return 1
        json.dump(
            {"total": total, "files": long_blocks},
            open(BASELINE, "w"),
            indent=2,
            sort_keys=True,
        )
        print(f"Recorded {total} multi-line comment blocks across {len(long_blocks)} files.")
        return 0

    if not baseline:
        print(f"No baseline at {BASELINE}. Run: python3 {sys.argv[0]} --update")
        return 1

    recorded = baseline.get("files", {})
    failures = []
    for path, count in sorted(long_blocks.items()):
        allowed = recorded.get(path, 0)
        if count > allowed:
            failures.append(f"{path}: {count} multi-line comment blocks, was {allowed}")

    if failures:
        print("Comments: one line each, saying what the code does now.")
        print("These files gained multi-line comment blocks:\n")
        for failure in failures:
            print(f"  {failure}")
        print(f"\nSee the comment rule in AGENTS.md.")
        print(f"Shrinking another file does not pay for growing this one.")
        return 1

    print(f"Comments: {total} multi-line blocks, none higher than the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
