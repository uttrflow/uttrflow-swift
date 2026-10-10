#!/usr/bin/env python3
"""Refuses a change to or removal of an existing evaluation case unless the ledger names it.

Adding a case passes. Changing or removing a case that exists on the base commit fails
unless this branch adds a line `<case id> <reason>` to Scripts/corpus_edits.txt, so the
edit to the instrument is a reviewable line of its own in the pull request. Cases are read
from the Swift sources and from the JSON data files under Resources/Corpus alike.
"""

import argparse
import json
import os
import re
import subprocess
from time import sleep
import sys

CORPUS_DIR = "Sources/UttrflowEval"
DATA_DIR = CORPUS_DIR + "/Resources/Corpus"
LEDGER = "Scripts/corpus_edits.txt"
ID_PATTERN = re.compile(r'\bid:\s*"((?:[^"\\]|\\.)*)"')
STRING_LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def git(*args, check=True):
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "git " + " ".join(args) + " failed")
    return result


def strip_comments(source):
    """Blanks comments, keeping string literals intact."""
    out = []
    i = 0
    length = len(source)
    while i < length:
        if source.startswith('"""', i):
            end = source.find('"""', i + 3)
            end = length if end < 0 else end + 3
            out.append(source[i:end])
            i = end
        elif source[i] == '"':
            j = i + 1
            while j < length and source[j] != '"' and source[j] != "\n":
                j += 2 if source[j] == "\\" else 1
            out.append(source[i:j + 1])
            i = j + 1
        elif source.startswith("//", i):
            end = source.find("\n", i)
            i = length if end < 0 else end
        elif source.startswith("/*", i):
            end = source.find("*/", i + 2)
            i = length if end < 0 else end + 2
        else:
            out.append(source[i])
            i += 1
    return "".join(out)


def cases_in(source):
    """Maps each case id to its normalised call text: the innermost parentheses holding `id:`."""
    text = strip_comments(source)
    cases = {}
    stack = []
    i = 0
    length = len(text)
    while i < length:
        char = text[i]
        if text.startswith('"""', i):
            end = text.find('"""', i + 3)
            i = length if end < 0 else end + 3
            continue
        if char == '"':
            j = i + 1
            while j < length and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            i = j + 1
            continue
        if char == "(":
            stack.append(i)
        elif char == ")" and stack:
            start = stack.pop()
            body = text[start:i + 1]
            # String literals are set aside first, so an interpolated id's parentheses are not taken for a call's.
            literals = []
            inner = STRING_LITERAL.sub(lambda m: literals.append(m.group(0)) or f'"{len(literals) - 1}"', body[1:-1])
            depth_zero = re.sub(r"\((?:[^()]|\([^()]*\))*\)", "", inner)
            match = ID_PATTERN.search(depth_zero)
            case_id = literals[int(match.group(1))][1:-1] if match else None
            if case_id is not None and case_id not in cases:
                cases[case_id] = " ".join(body.split())
        i += 1
    return cases


def data_cases_in(text):
    """Maps each case id in a JSON data file to its fields; a `note` explains a case and is no part of it."""
    cases = {}
    for record in json.loads(text):
        fields = {key: value for key, value in record.items() if key != "note"}
        cases.setdefault(str(record.get("id")), json.dumps(fields, sort_keys=True, ensure_ascii=False))
    return cases


def corpus(read_file, paths):
    cases = {}
    for path in paths:
        read = data_cases_in if path.endswith(".json") else cases_in
        for case_id, body in read(read_file(path)).items():
            cases.setdefault(case_id, body)
    return cases


def ledger_ids(text):
    ids = set()
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            ids.add(line.split()[0])
    return ids


def newly_ledgered_ids(base_text, head_text):
    """The ids this branch adds a ledger line for, so a case ledgered once before can be ledgered again."""
    added = set(head_text.splitlines()) - set(base_text.splitlines())
    return ledger_ids("\n".join(added))


def findings(base_cases, head_cases, newly_ledgered):
    problems = []
    for case_id, body in sorted(base_cases.items()):
        if case_id in newly_ledgered:
            continue
        if case_id not in head_cases:
            problems.append(f"removed: {case_id}")
        elif head_cases[case_id] != body:
            problems.append(f"changed: {case_id}")
    return problems


def resolve_base(run=git):
    if os.environ.get("CORPUS_EDIT_BASE"):
        return os.environ["CORPUS_EDIT_BASE"]
    head = run("rev-parse", "HEAD").stdout.strip()
    for ref in ("origin/main", "main"):
        found = run("merge-base", "HEAD", ref, check=False)
        if found.returncode == 0 and found.stdout.strip():
            # The first ref that exists decides; a stale local main never stands in for it.
            base = found.stdout.strip()
            if base != head:
                return base
            break
    # HEAD is on main, or a pull-request checkout is one shallow merge commit: its first parent is the base.
    parent = run("rev-parse", "--verify", "--quiet", "HEAD^1", check=False).stdout.strip()
    if parent:
        return parent
    return fetched_first_parent(run)


def fetched_first_parent(run=git, attempts=3, pause=sleep):
    """HEAD's first parent, fetched by id when a shallow checkout lacks it; None, saying why, if it cannot be."""
    # A shallow commit still names its parents in its header, though `HEAD^1` cannot be walked to.
    header = run("cat-file", "-p", "HEAD", check=False).stdout.split("\n\n", 1)[0]
    parents = [line.split()[1] for line in header.splitlines() if line.startswith("parent ")]
    if not parents:
        return None
    parent, failure = parents[0], ""
    for attempt in range(attempts):
        if run("cat-file", "-e", parent + "^{commit}", check=False).returncode == 0:
            return parent
        fetch = run("fetch", "--quiet", "--no-tags", "--depth=1", "origin", parent, check=False)
        failure = (getattr(fetch, "stderr", "") or "").strip()
        if fetch.returncode == 0:
            return parent
        if attempt + 1 < attempts:
            pause(2 ** attempt)
    print(f"corpus-edit-audit: could not fetch the base commit {parent}: {failure}", file=sys.stderr)
    return None


def corpus_paths(lister):
    return sorted(
        p for p in lister()
        if (p.startswith(CORPUS_DIR + "/") and p.endswith(".swift"))
        or (p.startswith(DATA_DIR + "/") and p.endswith(".json"))
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="commit to compare against (default: merge base with main)")
    args = parser.parse_args()
    base = args.base or resolve_base()
    if base is None:
        print("corpus-edit-audit: no base commit to compare against", file=sys.stderr)
        return 1

    def base_file(path):
        return git("show", f"{base}:{path}").stdout

    def head_file(path):
        with open(path, encoding="utf-8") as handle:
            return handle.read()

    base_paths = corpus_paths(lambda: git("ls-tree", "-r", "--name-only", base, CORPUS_DIR).stdout.split())
    head_paths = corpus_paths(lambda: git("ls-files", "--cached", "--others", "--exclude-standard", CORPUS_DIR).stdout.split())
    head_paths = [p for p in head_paths if os.path.exists(p)]
    base_ledger = git("show", f"{base}:{LEDGER}", check=False).stdout
    head_ledger = head_file(LEDGER) if os.path.exists(LEDGER) else ""
    newly_ledgered = newly_ledgered_ids(base_ledger, head_ledger)

    problems = findings(corpus(base_file, base_paths), corpus(head_file, head_paths), newly_ledgered)
    if problems:
        print(f"corpus-edit-audit: {len(problems)} existing evaluation case(s) changed against {base[:12]}:")
        for problem in problems:
            print(f"  {problem}")
        print(f"Add new cases instead, or add a line '<case id> <reason>' to {LEDGER} for each.")
        return 1
    print("corpus-edit-audit: no existing evaluation case changed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
