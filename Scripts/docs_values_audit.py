#!/usr/bin/env python3
"""Fails where a number marked `<!-- count:Type.member -->N` or `<!-- value:Type.member -->N` in a document disagrees with Sources/."""

import os
import re
import subprocess
import sys
import tempfile

MARKER = re.compile(r"<!--\s*(count|value):([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*-->\s*([0-9][0-9,_]*(?:\.[0-9]+)?)?")
NUMBER = r"(-?[0-9][0-9_]*(?:\.[0-9]+)?)"
OPENERS = {"[": "]", "(": ")", "{": "}"}


def declaring_files(root, type_name):
    """Swift sources under Sources/ that declare or extend `type_name`."""
    pattern = re.compile(r"\b(?:struct|class|enum|actor|extension|protocol)\s+" + re.escape(type_name) + r"\b")
    found = []
    for directory, _, names in os.walk(os.path.join(root, "Sources")):
        for name in sorted(names):
            if name.endswith(".swift"):
                path = os.path.join(directory, name)
                text = open(path, errors="ignore").read()
                if pattern.search(text):
                    found.append((path, text))
    return found


def skip_string_or_comment(text, index):
    """The index just past a string literal or comment starting at `index`, or `index` when none starts there."""
    if text.startswith("//", index):
        end = text.find("\n", index)
        return len(text) if end < 0 else end
    if text.startswith("/*", index):
        end = text.find("*/", index + 2)
        return len(text) if end < 0 else end + 2
    if text.startswith('"""', index):
        end = text.find('"""', index + 3)
        return len(text) if end < 0 else end + 3
    if text[index] == '"':
        position = index + 1
        while position < len(text) and text[position] != '"':
            position += 2 if text[position] == "\\" else 1
        return position + 1
    return index


def literal_entries(text, start):
    """The number of top-level entries in the collection literal opening at `text[start]`."""
    depth = 0
    entries = 0
    pending = False
    index = start
    while index < len(text):
        skipped = skip_string_or_comment(text, index)
        if skipped != index:
            pending = pending or depth > 0
            index = skipped
            continue
        character = text[index]
        if character in OPENERS:
            if depth == 1:
                pending = True
            depth += 1
        elif character in OPENERS.values():
            depth -= 1
            if depth == 0:
                return entries + (1 if pending else 0)
        elif character == "," and depth == 1:
            entries += 1 if pending else 0
            pending = False
        elif depth >= 1 and not character.isspace() and character != ":":
            pending = True
        index += 1
    return None


def count_of(root, type_name, member):
    """Entries in the literal assigned to `Type.member`, or an error string."""
    declaration = re.compile(r"\b(?:let|var)\s+" + re.escape(member) + r"\b[^=\n]*=\s*(?:(?:Set|Array)\s*\(\s*)?")
    results = []
    for path, text in declaring_files(root, type_name):
        for match in declaration.finditer(text):
            if match.end() < len(text) and text[match.end()] == "[":
                results.append(literal_entries(text, match.end()))
    if len(results) != 1 or results[0] is None:
        return None, f"{type_name}.{member} is not one collection literal under Sources/ ({len(results)} found)"
    return results[0], None


def value_of(root, type_name, member):
    """The numeric default declared for `Type.member`, or an error string."""
    declaration = re.compile(r"\b" + re.escape(member) + r"\s*(?::\s*[\w.?]+\s*)?=\s*" + NUMBER + r"\b")
    values = set()
    for _, text in declaring_files(root, type_name):
        for match in declaration.finditer(text):
            values.add(float(match.group(1).replace("_", "")))
    if len(values) != 1:
        return None, f"{type_name}.{member} has {len(values)} numeric defaults under Sources/, not one"
    return values.pop(), None


def documents(root):
    """Markdown files git knows about, tracked or not, outside ignored paths."""
    listed = subprocess.run(
        ["git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "*.md"],
        capture_output=True, text=True, check=False)
    if listed.returncode == 0:
        return [path for path in listed.stdout.splitlines() if os.path.isfile(os.path.join(root, path))]
    return [os.path.relpath(os.path.join(d, n), root) for d, _, names in os.walk(root) for n in names if n.endswith(".md")]


def findings(root):
    """One line per marked number that disagrees with the code, and the number of markers checked."""
    problems = []
    checked = 0
    for document in sorted(documents(root)):
        for number, line in enumerate(open(os.path.join(root, document), errors="ignore"), start=1):
            for match in MARKER.finditer(line):
                checked += 1
                kind, type_name, member, written = match.groups()
                where = f"{document}:{number}"
                if written is None:
                    problems.append(f"{where}: the {kind} marker for {type_name}.{member} is not followed by a number")
                    continue
                stated = float(written.replace(",", "").replace("_", ""))
                real, error = (count_of if kind == "count" else value_of)(root, type_name, member)
                if error:
                    problems.append(f"{where}: {error}")
                elif real != stated:
                    shown = int(real) if real == int(real) else real
                    problems.append(f"{where}: says {written}, but {type_name}.{member} is {shown}")
    return problems, checked


FIXTURE_SOURCE = """\
public enum Table {
    // a comment, with commas, [brackets]
    static let rows: [(String, String)] = [
        ("a, b", "x"), ("c", "y"),
        ("d", "z"),
    ]
    static let words: Set<String> = Set(["one", "two"])
}
public struct Windowing {
    public init(pause: Double = 0.4, length: Double = 30) {}
}
"""


def self_test():
    """Proves the audit passes agreeing prose and names the line of prose that is off by one."""
    with tempfile.TemporaryDirectory() as root:
        os.makedirs(os.path.join(root, "Sources", "Mod"))
        os.makedirs(os.path.join(root, "Docs"))
        with open(os.path.join(root, "Sources", "Mod", "Table.swift"), "w") as source:
            source.write(FIXTURE_SOURCE)
        good = os.path.join(root, "Docs", "good.md")
        with open(good, "w") as document:
            document.write("A table of <!-- count:Table.rows -->3 rows and <!-- count:Table.words -->2 words.\n"
                           "Pause <!-- value:Windowing.pause -->0.4 s up to <!-- value:Windowing.length -->30 s.\n")
        problems, checked = findings(root)
        if problems or checked != 4:
            print(f"self-test: agreeing prose was flagged ({checked} markers): {problems}", file=sys.stderr)
            return False
        with open(os.path.join(root, "Docs", "bad.md"), "w") as document:
            document.write("\nA table of <!-- count:Table.rows -->4 rows; <!-- value:Windowing.pause -->0.5 s;"
                           " <!-- count:Table.missing -->1.\n")
        problems, _ = findings(root)
        expected = ["Docs/bad.md:2: says 4", "Docs/bad.md:2: says 0.5", "Docs/bad.md:2: Table.missing"]
        if len(problems) != 3 or not all(any(p.startswith(e) for p in problems) for e in expected):
            print(f"self-test: drift was not named by document and line: {problems}", file=sys.stderr)
            return False
    print("  ✓ docs_values_audit self-test: agreement passes, an off-by-one table fails with its line")
    return True


def main(arguments):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if arguments == ["--self-test"]:
        return 0 if self_test() else 1
    if arguments:
        print("usage: docs_values_audit.py [--self-test]", file=sys.stderr)
        return 2
    problems, checked = findings(root)
    for problem in problems:
        print(problem, file=sys.stderr)
    if checked == 0:
        print("no count or value markers found; the audit is looking at nothing", file=sys.stderr)
        return 1
    if problems:
        return 1
    print(f"  ✓ {checked} marked numbers agree with the code")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
