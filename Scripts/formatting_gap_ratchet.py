#!/usr/bin/env python3
"""Measure recorded formatting cases and remove only passing gaps with --absorb."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

REGISTRY = Path("Tests/UttrflowEvalTests/FormattingParityTests.swift")
RULES = Path("Tests/UttrflowEvalTests/RulesCorpusTests.swift")
GOLDEN = Path("Tests/UttrflowEvalTests/Golden/rules.golden")
PAGE = Path("Docs/formatting-parity.md")
BLOCK = re.compile(r"(static let knownGaps: Set<String> = \[)(.*?)(\n    \])", re.S)


def recorded(source, name="knownGaps"):
    match = re.search(BLOCK.pattern.replace("knownGaps", name), source, re.S)
    if not match:
        raise ValueError("knownGaps registry is missing")
    content = re.sub(r"//[^\n]*", "", match.group(2))
    ids = re.findall(r'"([^"\\]+)"', content)
    if len(ids) != len(set(ids)):
        raise ValueError("knownGaps contains duplicate IDs")
    return match, ids


def shrink(source, measurements, name="knownGaps"):
    match, ids = recorded(source, name)
    results = {}
    for row in measurements:
        if not isinstance(row, dict) or set(row) != {"id", "rulesPassed"}:
            raise ValueError("measurement shape is invalid")
        if not isinstance(row["id"], str) or type(row["rulesPassed"]) is not bool:
            raise ValueError("measurement types are invalid")
        if row["id"] in results:
            raise ValueError("measurement contains duplicate IDs")
        results[row["id"]] = row["rulesPassed"]
    if set(results) != set(ids):
        raise ValueError("measurements do not match the complete recorded gap set")
    removed = sorted(key for key, passed in results.items() if passed)
    content = match.group(2)
    for key in removed:
        content, count = re.subn(r'"' + re.escape(key) + r'",?[ \t]*', "", content)
        if count != 1:
            raise ValueError("a measured ID is not uniquely removable")
    updated = source[:match.start(2)] + content + source[match.end(2):]
    if set(recorded(updated, name)[1]) != set(ids) - set(removed):
        raise ValueError("update changes more than the passing IDs")
    return updated, removed


def shrink_rules(source, removed):
    _, ids = recorded(source, "knownFailures")
    closed = set(ids) & set(removed)
    updated, _ = shrink(source, [{"id": key, "rulesPassed": key in closed} for key in ids],
                        "knownFailures")
    pattern = r"(named\.count == )(\d+)( \+ Self\.knownFailures\.count)"
    matches = list(re.finditer(pattern, source))
    if len(matches) != 1:
        raise ValueError("destination count assertion is not uniquely recognised")
    count = int(matches[0].group(2))
    updated = re.sub(pattern, lambda match: match[1] + str(count + len(closed)) + match[3], updated)
    if count + len(ids) != count + len(closed) + len(recorded(updated, "knownFailures")[1]):
        raise ValueError("destination total changes during absorption")
    return updated


def validate_outputs(old_golden, golden, old_page, page, removed):
    def entries(text):
        rows = [line.split("\t", 1) for line in text.splitlines()]
        if any(len(row) != 2 for row in rows):
            raise ValueError("generated golden has malformed rows")
        result = dict(rows)
        if len(result) != len(rows):
            raise ValueError("generated golden has duplicate IDs")
        return result
    before, after = entries(old_golden), entries(golden)
    if before.keys() != after.keys():
        raise ValueError("generation changes the corpus ID set")
    moved = {key for key in before if before[key] != after[key]}
    if moved != set(removed):
        raise ValueError("golden changes are not exactly the measured passing gaps")
    original, generated = old_page.splitlines(), page.splitlines()
    if len(original) != len(generated):
        raise ValueError("generation changes the report structure")
    seen = set()
    for left, right in zip(original, generated):
        if left == right:
            if set(re.findall(r"`([^`]+)`", left)) & set(removed):
                raise ValueError("generated report retains a measured passing gap")
            continue
        cells = left.split("|")
        if len(cells) != 9 or not left.startswith("| "):
            raise ValueError("generation changes unrelated report text")
        ids = re.findall(r"`([^`]+)`", cells[5])
        closed = set(ids) & set(removed)
        if not closed:
            raise ValueError("generation changes an unrelated report row")
        seen.update(closed)
        remaining = [key for key in ids if key not in closed]
        cells[4] = f" {int(cells[4]) + len(closed)} "
        cells[5] = " " + (f"{len(remaining)}: " + ", ".join(f"`{key}`" for key in remaining)
                           if remaining else "0") + " "
        if "|".join(cells) != right:
            raise ValueError("generation changes more than the measured report gaps")
    if seen != set(removed):
        raise ValueError("report does not account for every measured passing gap")


def generated_outputs(root, folder, removed, originals):
    golden, page = Path(folder) / "rules.golden", Path(folder) / "parity.md"
    environment = dict(os.environ, UTTRFLOW_UPDATE_GOLDEN="1",
                       UTTRFLOW_RULES_GOLDEN_OUTPUT=str(golden),
                       UTTRFLOW_PARITY_PAGE_OUTPUT=str(page))
    subprocess.run(["swift", "test", "-j", "4", "--filter",
                    "RulesCorpusTests/matchesGolden|FormattingParityTests/pageMatchesOutputs"],
                   cwd=root, env=environment, check=True)
    texts = golden.read_text(), page.read_text()
    validate_outputs(originals[GOLDEN], texts[0], originals[PAGE], texts[1], removed)
    return texts


def replace_outputs(root, originals, updates):
    """Stage all files; restore completed writes on failure, retaining recovery copies if that fails."""
    folder = Path(tempfile.mkdtemp(prefix=".formatting-gap-backup-", dir=root))
    committed = []
    try:
        for index, path in enumerate(updates):
            (folder / f"old-{index}").write_text(originals[path])
            (folder / f"new-{index}").write_text(updates[path])
        if any((root / path).read_text() != text for path, text in originals.items()):
            raise ValueError("recorded artifacts changed before replacement")
        for index, path in enumerate(updates):
            os.replace(folder / f"new-{index}", root / path)
            committed.append((index, path))
    except (OSError, ValueError):
        try:
            for index, path in reversed(committed):
                os.replace(folder / f"old-{index}", root / path)
        except OSError as error:
            raise ValueError(f"rollback failed; recovery copies retained at {folder}") from error
        shutil.rmtree(folder)
        raise
    shutil.rmtree(folder)


def run(root, absorb):
    registry = root / REGISTRY
    originals = {path: (root / path).read_text() for path in (REGISTRY, RULES, GOLDEN, PAGE)}
    original = originals[REGISTRY]
    outputs = None
    with tempfile.TemporaryDirectory(prefix="uttrflow-parity-") as folder:
        report = Path(folder) / "measurements.json"
        environment = dict(os.environ, UTTRFLOW_PARITY_MEASUREMENTS=str(report))
        subprocess.run(
            ["swift", "test", "-j", "4", "--filter",
             "FormattingParityTests/measuredGapsForAbsorption"],
            cwd=root, env=environment, check=True)
        updated, removed = shrink(original, json.loads(report.read_text()))
        if any((root / path).read_text() != text for path, text in originals.items()):
            raise ValueError("recorded artifacts changed during measurement")
        if absorb and removed:
            outputs = generated_outputs(root, folder, removed, originals)
    if any((root / path).read_text() != text for path, text in originals.items()):
        raise ValueError("recorded artifacts changed while measurement or generation was running")
    rules = shrink_rules(originals[RULES], removed)
    print(f"Measured {len(recorded(original)[1])} recorded gaps.")
    for key in removed:
        print(f"rules pass: {key}")
    if absorb:
        updates = {REGISTRY: updated, RULES: rules}
        if outputs is not None:
            updates.update({GOLDEN: outputs[0], PAGE: outputs[1]})
        replace_outputs(root, originals, updates)
        print(f"Removed {len(removed)} passing gaps; no new gaps added.")
    else:
        print(f"{len(removed)} gaps can be removed with --absorb; registry unchanged.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--absorb", action="store_true", help="remove freshly measured passing gaps")
    args = parser.parse_args()
    try:
        return run(Path(__file__).resolve().parent.parent, args.absorb)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"formatting gap ratchet: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
