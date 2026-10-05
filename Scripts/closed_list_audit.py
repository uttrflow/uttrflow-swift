#!/usr/bin/env python3
"""Counts closed word lists written into Swift code, and stops the count ever rising."""

import argparse
import os
import re
import sys

import ratchet

ROOTS = ("Sources",)
BASELINE = os.path.join("Scripts", "closed_list_baseline.json")

# A literal collection holding this many words or more is a closed list rather than a named marker.
LIST_WIDTH = 4

# One word, or a short phrase of words: what a rule keyed to speech compares against.
WORD = re.compile(r"[A-Za-z][A-Za-z'’-]*(?: [A-Za-z][A-Za-z'’-]*)*")


def without_comments(text):
    """Blanks `//` and `/* */` comments outside string literals, keeping newlines so line numbers hold."""
    out, index, length = [], 0, len(text)
    while index < length:
        if text.startswith('"""', index):
            end = text.find('"""', index + 3)
            end = length if end < 0 else end + 3
            out.append(text[index:end])
            index = end
        elif text[index] == '"':
            end = index + 1
            while end < length and text[end] not in '"\n':
                end += 2 if text[end] == "\\" else 1
            out.append(text[index:end + 1])
            index = end + 1
        elif text.startswith("//", index):
            end = text.find("\n", index)
            index = length if end < 0 else end
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            end = length if end < 0 else end + 2
            out.append(re.sub(r"[^\n]", " ", text[index:end]))
            index = end
        else:
            out.append(text[index])
            index += 1
    return "".join(out)


def string_elements(body):
    """The elements of a bracket body when every element is a plain string literal, else None."""
    elements = []
    for part in re.split(r",", body):
        part = part.strip()
        if not part:
            continue
        match = re.fullmatch(r'"((?:[^"\\]|\\.)*)"', part)
        if not match:
            return None
        elements.append(match.group(1))
    return elements


def findings_in(path):
    """Yields (line_number, word_count, first_words) for every closed word list in the file."""
    with open(path, errors="ignore") as source:
        code = without_comments(source.read())
    for match in re.finditer(r"\[([^\[\]]*)\]", code):
        elements = string_elements(match.group(1))
        if elements is None:
            continue
        words = [element for element in elements if WORD.fullmatch(element)]
        if len(words) >= LIST_WIDTH and len(words) == len(elements):
            line = code.count("\n", 0, match.start()) + 1
            yield line, len(words), ", ".join(words[:5])


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
            detail += [(path, line, size, words) for line, size, words in found]
    return counts, detail


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    ratchet.add_arguments(parser)
    parser.add_argument("--report", action="store_true", help="list every closed list, with its line")
    arguments = parser.parse_args()

    counts, detail = survey()
    total = sum(counts.values())

    if arguments.report:
        for path, line, size, words in detail:
            print(f"{path}:{line}  {size} words: {words}")
        print(f"\n{total} closed word lists holding {sum(item[2] for item in detail)} words in {len(counts)} files")
        return 0

    if arguments.update:
        return ratchet.update(BASELINE, counts, "closed word lists", "a list to move into data later", arguments.after_merge)

    baseline = ratchet.load(BASELINE)
    if not baseline:
        return ratchet.missing(BASELINE, sys.argv[0])

    recorded = baseline.get("files", {})
    failures = [
        f"{path}:{line}  {size} words: {words}"
        for path, line, size, words in detail
        if counts[path] > recorded.get(path, 0)
    ]

    if failures:
        print("A rule is a data or configuration change, not another word list in the code.")
        print(f"These files gained a literal collection of {LIST_WIDTH} or more words:\n")
        for failure in failures:
            print(f"  {failure}")
        print("\nName the property the words share and decide by it, or move the list into a data file.")
        print("See Docs/agents/code-quality.md, \"Closed word lists\".")
        return 1

    print(f"Closed word lists: {total}, none higher than the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
