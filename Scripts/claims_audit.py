#!/usr/bin/env python3
"""Fails when user-facing text makes a privacy, accuracy, speed or rewriting claim that Docs/claims.json does not register."""
import datetime
import json
import re
import sys
import tempfile
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
REGISTER = Path("Docs/claims.json")
SOURCE_DIRS = (Path("Sources/UttrflowUX"), Path("Sources/Uttrflow"))
PROSE_FILES = (Path("README.md"),)
KINDS = {"privacy", "accuracy", "speed", "availability", "rewrite"}
CLAIM = re.compile(
    r"\b(most accurate|fastest|best|instant(ly)?|at the speed of"
    r"|never (\w+ )?(read|keep|kept|send|sent|upload|save|saved|store|leave|change)\w*"
    r"|stays? on (this|your) Mac"
    r"|rewrit\w*|word choice|polish\w*|improves? your|rephrase\w*|rephrasing\w*"
    r"|\d+(\.\d+)?\s?(ms|%)(?!\w))",
    re.IGNORECASE,
)
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def literal_lines(text):
    """(line number, text) for every line of every Swift string literal, comments skipped."""
    found = []
    block = False
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if block:
            if stripped.startswith('"""'):
                block = False
            else:
                found.append((number, stripped))
            continue
        if stripped.startswith("//"):
            continue
        if stripped.endswith('"""') and stripped.count('"""') == 1:
            block = True
            continue
        found.extend((number, segment) for segment in LITERAL.findall(line))
    return found


def candidates(root):
    """(file, line, text) for every user-facing line that matches the claim pattern."""
    found = []
    for directory in SOURCE_DIRS:
        for source in sorted((root / directory).rglob("*.swift")):
            relative = source.relative_to(root).as_posix()
            for number, text in literal_lines(source.read_text(errors="ignore")):
                if CLAIM.search(text):
                    found.append((relative, number, text))
    for prose in PROSE_FILES:
        if (root / prose).is_file():
            for number, text in enumerate((root / prose).read_text(errors="ignore").splitlines(), 1):
                if CLAIM.search(text):
                    found.append((prose.as_posix(), number, text.strip()))
    return found


def test_names(root):
    names = set()
    for test in (root / "Tests").rglob("*.swift"):
        names.update(re.findall(r"\bfunc\s+(\w+)\s*\(", test.read_text(errors="ignore")))
    return names


def make_targets(root):
    makefile = root / "Makefile"
    text = makefile.read_text(errors="ignore") if makefile.is_file() else ""
    return set(re.findall(r"^([A-Za-z0-9_-]+):", text, re.MULTILINE))


def evidence_problem(root, claim, tests, targets):
    """Why a registered claim's evidence does not stand, or None."""
    evidence = claim.get("evidence") or {}
    if "test" in evidence:
        return None if evidence["test"] in tests else f"no test named {evidence['test']} in Tests/"
    if "command" in evidence:
        target = evidence["command"].removeprefix("make ").strip()
        return None if target in targets else f"no Makefile target {target}"
    if "doc" in evidence:
        return None if (root / evidence["doc"]).is_file() else f"no file {evidence['doc']}"
    if "none" in evidence:
        return None
    return "evidence must name a test, a make command, a doc, or none with the reason"


def findings(root, today):
    problems = []
    try:
        claims = json.loads((root / REGISTER).read_text())["claims"]
    except (OSError, ValueError, KeyError) as error:
        return [f"{REGISTER}: unreadable ({error})"]
    tests, targets = test_names(root), make_targets(root)
    used = set()
    for path, number, text in candidates(root):
        match = next((c for c in claims if c.get("file") == path and c.get("text", "\0") in text), None)
        if match is None:
            problems.append(f"{path}:{number}  unregistered claim: {text[:100]}")
        else:
            used.add(match["id"])
    for claim in claims:
        name = claim.get("id", "?")
        if claim.get("kind") not in KINDS:
            problems.append(f"{REGISTER}  {name}: kind must be one of {sorted(KINDS)}")
        problem = evidence_problem(root, claim, tests, targets)
        if problem:
            problems.append(f"{REGISTER}  {name}: {problem}")
        try:
            expires = datetime.date.fromisoformat(claim.get("expires", ""))
        except ValueError:
            problems.append(f"{REGISTER}  {name}: expires must be a YYYY-MM-DD date")
        else:
            if today > expires:
                problems.append(f"{REGISTER}  {name}: evidence expired {expires}; re-check it or reword the text")
        if name not in used:
            problems.append(f"{REGISTER}  {name}: its text no longer appears in {claim.get('file')}; delete the entry")
    return problems


def self_test():
    today = datetime.date(2030, 1, 1)
    with tempfile.TemporaryDirectory() as work:
        root = Path(work)
        (root / "Docs").mkdir()
        (root / "Sources/UttrflowUX").mkdir(parents=True)
        (root / "Tests").mkdir()
        (root / "Tests/T.swift").write_text("func voiceStaysLocal() {}\n")
        (root / "Makefile").write_text("offline-audit: ## x\n")
        (root / "Sources/UttrflowUX/A.swift").write_text(
            'let a = "Your voice never leaves your Mac."\n// "fastest" in a comment\nlet b = """\n    Words in 200 ms.\n    """\n'
        )
        register = {"claims": [
            {"id": "voice", "file": "Sources/UttrflowUX/A.swift", "text": "never leaves your Mac", "kind": "privacy",
             "evidence": {"test": "voiceStaysLocal"}, "expires": "2030-06-01"},
            {"id": "speed", "file": "Sources/UttrflowUX/A.swift", "text": "Words in 200 ms", "kind": "speed",
             "evidence": {"command": "make offline-audit"}, "expires": "2030-06-01"},
        ]}
        (root / REGISTER).write_text(json.dumps(register))
        good = findings(root, today)
        (root / "Sources/UttrflowUX/B.swift").write_text('let c = "The fastest dictation."\n')
        unregistered = findings(root, today)
        (root / "Sources/UttrflowUX/B.swift").write_text('let c = "Standard also rewrites grammar."\n')
        rewrite = findings(root, today)
        expired = findings(root, datetime.date(2031, 1, 1))
        register["claims"][0]["evidence"] = {"test": "gone"}
        (root / REGISTER).write_text(json.dumps(register))
        missing = findings(root, today)
    if good or len(unregistered) != 1 or len(rewrite) != 1 or len(expired) != 3 or len(missing) != 2:
        print(f"claims self-test failed: good={good} unregistered={unregistered} rewrite={rewrite} expired={expired}"
              f" missing={missing}",
              file=sys.stderr)
        return 1
    return 0


def main():
    if "--self-test" in sys.argv[1:] and self_test() != 0:
        return 1
    problems = findings(PACKAGE_ROOT, datetime.date.today())
    for problem in problems:
        print(problem)
    if problems:
        print(f"claims-audit: {len(problems)} problem(s); register the claim in {REGISTER} with its evidence, or reword it",
              file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
