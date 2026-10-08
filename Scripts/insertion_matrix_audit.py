#!/usr/bin/env python3
# Fails when Docs/insertion-test-matrix.md has a scenario without an entry in every cell.
# Usage: Scripts/insertion_matrix_audit.py [--self-test]
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "Docs" / "insertion-test-matrix.md"
CLASS_CELL = re.compile(r"^(not applicable|harness H\d+|manual M\d+)$")
AUTOMATED_CELL = re.compile(r"^`([A-Za-z]+)\.([a-z][A-Za-z0-9]*)`$")


def matrix_rows(text):
    # The rows of the first table under the "## The matrix" heading, header and divider dropped.
    section = text.split("## The matrix", 1)
    if len(section) < 2:
        return None
    rows = []
    for line in section[1].splitlines():
        if line.startswith("## "):
            break
        if line.startswith("|"):
            rows.append([cell.strip() for cell in line.strip().strip("|").split("|")])
        elif rows:
            break
    return rows


def test_exists(tests_text, suite, method):
    return re.search(rf"\b(struct|class) {suite}\b", tests_text) and re.search(rf"\bfunc {method}\(", tests_text)


def problems_in(text, tests_text):
    rows = matrix_rows(text)
    if not rows or len(rows) < 3:
        return ["no matrix table under a '## The matrix' heading"]
    header, body = rows[0], rows[2:]
    found = []
    seen = set()
    procedures = set(re.findall(r"^### ([HM]\d+)$", text, re.MULTILINE))
    for row in body:
        label = row[0] if row else "?"
        if len(row) != len(header):
            found.append(f"{label}: {len(row)} cells, the header has {len(header)}")
            continue
        if label in seen:
            found.append(f"{label}: the id is used twice")
        seen.add(label)
        if not row[1]:
            found.append(f"{label}: no scenario text")
        automated = AUTOMATED_CELL.match(row[2])
        if not automated:
            found.append(f"{label}: the Automated cell is not `Suite.method`")
        elif not test_exists(tests_text, automated.group(1), automated.group(2)):
            found.append(f"{label}: {row[2]} names no test under Tests/")
        for column, cell in zip(header[3:], row[3:]):
            match = CLASS_CELL.match(cell)
            if not match:
                found.append(f"{label}, {column}: '{cell}' is not an entry")
                continue
            procedure = cell.split()[-1]
            if cell != "not applicable" and procedure not in procedures:
                found.append(f"{label}, {column}: no '### {procedure}' section")
    return found


def self_test():
    tests_text = "struct FooTests {\n func barWorks() {}\n}"
    good = (
        "## The matrix\n\n| Id | Scenario | Automated | A |\n|---|---|---|---|\n"
        "| S1 | x | `FooTests.barWorks` | manual M1 |\n\n### M1\n"
    )
    cases = {
        "good": (good, 0),
        "empty cell": (good.replace("manual M1 |", " |"), 1),
        "missing test": (good.replace("barWorks`", "gone`"), 1),
        "missing procedure": (good.replace("### M1", "### M2"), 1),
    }
    ok = True
    for name, (text, expected) in cases.items():
        got = len(problems_in(text, tests_text))
        if got != expected:
            print(f"self-test '{name}': {got} problem(s), expected {expected}", file=sys.stderr)
            ok = False
    return ok


def main():
    if sys.argv[1:] == ["--self-test"]:
        return 0 if self_test() else 1
    if sys.argv[1:]:
        print("usage: insertion_matrix_audit.py [--self-test]", file=sys.stderr)
        return 2
    tests_text = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "Tests").rglob("*.swift"))
    found = problems_in(DOC.read_text(encoding="utf-8"), tests_text)
    for problem in found:
        print(f"Docs/insertion-test-matrix.md: {problem}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
