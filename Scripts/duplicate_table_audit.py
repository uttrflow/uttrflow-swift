#!/usr/bin/env python3
"""Finds word tables copied into a second file, and stops the number of copies ever rising."""

import argparse
import os
import re
import sys

import ratchet
from closed_list_audit import swift_files, without_comments

BASELINE = os.path.join("Scripts", "duplicate_table_baseline.json")

# A table this wide is a vocabulary; below it, overlap is chance rather than copying.
TABLE_WIDTH = 6

# Shared members over the smaller table's size at which two tables are one table written twice.
OVERLAP = 0.6

LITERAL = r'"(?:[^"\\\n]|\\.)*"'
ELEMENT = rf"\s*({LITERAL})\s*(?::\s*(?:{LITERAL}|[^,\"\n]+?)\s*)?"
BODY = re.compile(rf"(?:{ELEMENT},)*{ELEMENT},?\s*")


def members(body):
    """The string members of an array or set body, or the keys of a dictionary body; None when any element is not a literal."""
    if not BODY.fullmatch(body):
        return None
    return [literal[1:-1] for literal in re.findall(ELEMENT, body)]


def tables_in(path):
    """Yields (line_number, member_set) for every literal string table of TABLE_WIDTH or more members."""
    with open(path, errors="ignore") as source:
        code = without_comments(source.read())
    for match in re.finditer(r"\[([^\[\]]*)\]", code):
        found = members(match.group(1))
        if found is None or len(set(found)) < TABLE_WIDTH:
            continue
        yield code.count("\n", 0, match.start()) + 1, frozenset(found)


def overlapping_pairs(tables):
    """Each pair of tables in different files sharing at least OVERLAP of the smaller one."""
    pairs = []
    for index, (path, line, words) in enumerate(tables):
        for other_path, other_line, other_words in tables[index + 1:]:
            if other_path == path:
                continue
            shared = len(words & other_words)
            if shared >= OVERLAP * min(len(words), len(other_words)):
                pairs.append(((path, line, words), (other_path, other_line, other_words), shared))
    return pairs


def survey(paths):
    tables = [(path, line, words) for path in paths for line, words in tables_in(path)]
    pairs = overlapping_pairs(tables)
    counts = {}
    for first, second, _ in pairs:
        for path, _, _ in (first, second):
            counts[path] = counts.get(path, 0) + 1
    return counts, pairs


def describe(table, other, shared):
    path, line, words = table
    other_path, other_line, other_words = other
    sample = ", ".join(sorted(words & other_words)[:5])
    return f"{path}:{line} shares {shared} of {len(words)} members with {other_path}:{other_line} ({sample})"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    ratchet.add_arguments(parser)
    parser.add_argument("--report", action="store_true", help="list every pair of overlapping tables")
    arguments = parser.parse_args()

    counts, pairs = survey(list(swift_files()))
    total = len(pairs)

    if arguments.report:
        for first, second, shared in pairs:
            print(describe(first, second, shared))
        print(f"\n{total} overlapping table pairs across {len(counts)} files")
        return 0

    if arguments.update:
        return ratchet.update(BASELINE, counts, "duplicate table pairings", "a copy to fold into its home later", arguments.after_merge)

    baseline = ratchet.load(BASELINE)
    if not baseline:
        return ratchet.missing(BASELINE, sys.argv[0])

    risen = ratchet.risen(counts, baseline.get("files", {}))
    failures = []
    for first, second, shared in pairs:
        if first[0] in risen:
            failures.append(describe(first, second, shared))
        if second[0] in risen:
            failures.append(describe(second, first, shared))

    if failures:
        print("A word table has one home. These files gained a table that copies one elsewhere:\n")
        for failure in failures:
            print(f"  {failure}")
        print("\nUse the existing table named after \"with\", or move both into one shared home.")
        print("See Docs/agents/code-quality.md, \"Duplicate word tables\".")
        return 1

    print(f"Duplicate table pairings: {total}, none higher than the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
