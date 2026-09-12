#!/usr/bin/env python3
"""Counts text comparisons that decide word identity by shape, and stops the count ever rising."""

import argparse
import json
import os
import re
import sys

ROOTS = ("Sources",)
BASELINE = os.path.join("Scripts", "loose_match_baseline.json")

# A slice this short is a stem standing in for a word; a longer one is a truncation for display.
STEM_WIDTH = 8

# An argument that is a literal asks about a marker the code names, not about a word it was given.
LITERAL = r"""["']"""

# A fixed-width prefix on the same line as a text comparison: `hasPrefix(typed.prefix(2))`.
PREFIX_COMPARED = re.compile(
    r"\.prefix\(([0-9]+)\)(?=.*(?:hasPrefix\(|hasSuffix\(|==|!=))"
    r"|(?:hasPrefix\(|hasSuffix\(|==|!=).*\.prefix\(([0-9]+)\)"
)

# A fixed-width prefix kept as a String, which is a stem being named: `String(word.prefix(3))`.
PREFIX_KEPT = re.compile(r"String\([^()]*\.prefix\(([0-9]+)\)\)")

# Asking a collection of strings whether any of them swallows mine: `pool.contains(where: { $0.contains(word) })`.
SWALLOWS = re.compile(
    r"\.(?:contains|first|firstIndex|last|lastIndex|allSatisfy|filter)"
    r"\((?:where: *)?\{[^}]*\$0\.(?:contains|hasPrefix|hasSuffix)\( *(?!" + LITERAL + r")[A-Za-z$_]"
)


def findings_in(path):
    """Yields (line_number, tell, text) for every loose word match in the file."""
    for number, line in enumerate(open(path, errors="ignore").read().split("\n"), start=1):
        code = line.split("//")[0]
        for match in PREFIX_COMPARED.finditer(code):
            width = int(match.group(1) or match.group(2))
            if width <= STEM_WIDTH:
                yield number, "a fixed-width prefix decides a text comparison", line.strip()
        for match in PREFIX_KEPT.finditer(code):
            if int(match.group(1)) <= STEM_WIDTH:
                yield number, "a fixed-width prefix is kept as a word", line.strip()
        if SWALLOWS.search(code):
            yield number, "a word is matched by being swallowed by another", line.strip()


def swift_files():
    for root in ROOTS:
        for directory, _, names in os.walk(root):
            if ".build" in directory or ".claude" in directory:
                continue
            for name in sorted(names):
                if name.endswith(".swift"):
                    yield os.path.join(directory, name)


def survey():
    counts, detail = {}, []
    for path in swift_files():
        found = list(findings_in(path))
        if found:
            counts[path] = len(found)
            detail += [(path, line, tell, text) for line, tell, text in found]
    return counts, detail


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true", help="record the current counts")
    parser.add_argument(
        "--after-merge",
        action="store_true",
        help="with --update, accept counts that rose because main moved underneath",
    )
    parser.add_argument("--report", action="store_true", help="list what is left, with the line")
    arguments = parser.parse_args()

    counts, detail = survey()
    total = sum(counts.values())

    if arguments.report:
        for path, line, tell, text in detail:
            print(f"{path}:{line}  {tell}\n    {text}")
        print(f"\n{total} loose word matches in {len(counts)} files")
        return 0

    baseline = json.load(open(BASELINE)) if os.path.exists(BASELINE) else {}

    if arguments.update:
        recorded = baseline.get("files", {})
        risen = {
            path: (recorded[path], count)
            for path, count in counts.items()
            if path in recorded and count > recorded[path]
        }
        if risen and not arguments.after_merge:
            print("Refusing to record a higher count. The baseline only goes down.")
            for path, (was, now) in sorted(risen.items()):
                print(f"  {path}: {was} -> {now}")
            print("\nIf these arrived from main rather than from your own work, re-record")
            print("with --after-merge. The rise then shows in the baseline's diff, where a")
            print("reviewer can see it, rather than passing unremarked.")
            return 1
        if risen:
            print("Absorbing counts that rose with main. Each is a match to tighten later:")
            for path, (was, now) in sorted(risen.items()):
                print(f"  {path}: {was} -> {now}")
        json.dump(
            {"total": total, "files": counts}, open(BASELINE, "w"), indent=2, sort_keys=True
        )
        print(f"Recorded {total} loose word matches across {len(counts)} files.")
        return 0

    if not baseline:
        print(f"No baseline at {BASELINE}. Run: python3 {sys.argv[0]} --update")
        return 1

    recorded = baseline.get("files", {})
    failures = [
        f"{path}:{line}  {tell}\n    {text}"
        for path, line, tell, text in detail
        if counts[path] > recorded.get(path, 0)
    ]

    if failures:
        print("A word is the same word by its form, not by its shape.")
        print("These files gained a text comparison that decides identity by shape:\n")
        for failure in failures:
            print(f"  {failure}")
        print("\nAsk MeaningPreservationGuard.sameForm whether two spellings are one word,")
        print("spelledInto or isWritten whether it is written out, and WordErrorRate.measure")
        print("whether it is still there in order. See issue #189 in PLAN.md.")
        return 1

    print(f"Word matches: {total} loose, none higher than the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
