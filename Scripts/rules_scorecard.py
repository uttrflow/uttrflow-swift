#!/usr/bin/env python3
"""Compares a rules scorecard with the one recorded on the base commit, for `make eval`.

A scorecard is what `uttrflow-eval rules-scorecard` writes: every corpus case, its category,
and whether the rules alone pass it. The comparison fails when a case that passed on the base
now fails, unless this branch names it in Scripts/scorecard_accepted.txt, or when a category's
pass rate falls by more than the threshold. A case that newly passes, or a case the base did
not have, never fails it. `--update` records the measured scorecard as the new point of
comparison.
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECORDED = ROOT / "Scripts" / "rules_scorecard.json"
ACCEPTED = ROOT / "Scripts" / "scorecard_accepted.txt"
# Percentage points a category may fall, across the regressions this branch accepts.
THRESHOLD = 1.0


class VerdictError(ValueError):
    """A scorecard contains a verdict the producer does not emit."""


def read_cases(path):
    with open(path) as handle:
        cases = json.load(handle)["cases"]
    for case, entry in cases.items():
        if entry["verdict"] not in ("pass", "fail"):
            raise VerdictError(f"{case}: verdict must be pass or fail")
    return cases


def read_accepted(path):
    """The case ids named in an accepted-regressions file, one `<case id> <reason>` per line."""
    if path is None or not Path(path).exists():
        return set()
    names = set()
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            names.add(line.split()[0])
    return names


def rates(cases):
    """Each category's pass rate in percent, with its counts."""
    totals = {}
    for entry in cases.values():
        passed, count = totals.get(entry["category"], (0, 0))
        totals[entry["category"]] = (passed + (entry["verdict"] == "pass"), count + 1)
    return {category: (100.0 * passed / count, passed, count) for category, (passed, count) in totals.items()}


def compare(base, measured, accepted, threshold=THRESHOLD):
    """The problems that fail the comparison, and the regressions this branch accepted."""
    regressed = sorted(
        case
        for case, entry in base.items()
        if entry["verdict"] == "pass" and measured.get(case, {}).get("verdict") == "fail"
    )
    problems = [
        f"{case} passed on the base and fails now; name it in {ACCEPTED.relative_to(ROOT)} to accept it"
        for case in regressed
        if case not in accepted
    ]
    shared = {case: entry for case, entry in measured.items() if case in base}
    before, after = rates({case: base[case] for case in shared}), rates(shared)
    for category, (rate, _, _) in sorted(before.items()):
        now = after.get(category, (rate, 0, 0))[0]
        if rate - now > threshold:
            problems.append(f"{category} fell from {rate:.1f}% to {now:.1f}%, more than {threshold:.1f} points")
    return problems, [case for case in regressed if case in accepted]


def markdown(base, measured, problems, accepted):
    """The scorecard as a pull request comment."""
    before, after = rates(base), rates(measured)
    improved = sorted(
        case
        for case, entry in measured.items()
        if entry["verdict"] == "pass" and base.get(case, {}).get("verdict") != "pass"
    )
    lines = ["### Rules scorecard", "", "| Category | Base | This branch |", "|---|---:|---:|"]
    for category in sorted(set(before) | set(after)):
        old = before.get(category)
        new = after.get(category)
        cell = lambda value: f"{value[1]}/{value[2]} ({value[0]:.1f}%)" if value else "-"
        lines.append(f"| {category} | {cell(old)} | {cell(new)} |")
    lines.append("")
    lines.append(f"Newly passing: {len(improved)}. Accepted regressions: {len(accepted)}.")
    if problems:
        lines += ["", "**Failing:**", *[f"- {problem}" for problem in problems]]
    return "\n".join(lines) + "\n"


def verdict_controls(script, root):
    """Checks comparison and recording admission through the actual CLI."""
    base = {str(index): {"category": "fixture", "verdict": "pass"} for index in range(1000)}
    baseline, measured = root / "base.json", root / "measured.json"
    recorded = script.parent / "rules_scorecard.json"
    failures = []
    for name, verdict in [("unknown", "unknown"), ("null", None), ("boolean", True)]:
        invalid = {**base, "0": {"category": "fixture", "verdict": verdict}}
        for side in ("base", "measured", "update"):
            baseline.write_text(json.dumps({"cases": invalid if side == "base" else base}))
            measured.write_text(json.dumps({"cases": base if side == "base" else invalid}))
            recorded.write_bytes(b"unchanged recorded bytes")
            arguments = ["--update"] if side == "update" else ["--base", str(baseline)]
            result = subprocess.run(
                [sys.executable, str(script), *arguments, "--measured", str(measured)],
                capture_output=True, text=True)
            refused = result.returncode == 1 and "verdict must be pass or fail" in result.stderr
            retained = side != "update" or recorded.read_bytes() == b"unchanged recorded bytes"
            if not refused or not retained:
                failures.append(f"{name}/{side}: malformed verdict admitted or recorded bytes changed")
    measured.write_text(json.dumps({"cases": base}, indent=2) + "\n")
    result = subprocess.run(
        [sys.executable, str(script), "--update", "--measured", str(measured)],
        capture_output=True, text=True)
    expected = f"rules scorecard: recorded {measured} as Scripts/rules_scorecard.json\n"
    if (result.returncode, result.stdout, result.stderr) != (0, expected, ""):
        failures.append("valid/update: existing successful recording output changed")
    if recorded.read_bytes() != measured.read_bytes():
        failures.append("valid/update: recording did not retain exact source bytes")
    return failures


def verdict_self_test():
    """Uses a private copied script so recording controls never write the baseline."""
    with tempfile.TemporaryDirectory() as scratch:
        root = Path(scratch)
        scripts = root / "Scripts"
        scripts.mkdir()
        script = scripts / "rules_scorecard.py"
        script.write_bytes(Path(__file__).read_bytes())
        failures = verdict_controls(script, root)
    for failure in failures:
        print(f"rules scorecard self-test: FAILED: {failure}", file=sys.stderr)
    if not failures:
        print("rules scorecard self-test: 9 malformed admissions refused; valid recording bytes preserved")
    return bool(failures)


def self_test():
    """Proves the comparison fails on what it must and passes on what it must not fail."""
    base = {
        "a": {"category": "everyday", "verdict": "pass"},
        "b": {"category": "everyday", "verdict": "fail"},
        "c": {"category": "technical", "verdict": "pass"},
    }
    checks = [
        ("an unchanged scorecard passes", compare(base, dict(base), set())[0] == []),
        (
            "a newly passing case passes",
            compare(base, {**base, "b": {"category": "everyday", "verdict": "pass"}}, set())[0] == [],
        ),
        (
            "a new case passes",
            compare(base, {**base, "d": {"category": "everyday", "verdict": "fail"}}, set())[0] == [],
        ),
        (
            "a regression fails",
            len(compare(base, {**base, "c": {"category": "technical", "verdict": "fail"}}, set(), 100)[0]) == 1,
        ),
        (
            "an accepted regression inside the threshold passes",
            compare(base, {**base, "c": {"category": "technical", "verdict": "fail"}}, {"c"}, 100)[0] == [],
        ),
        (
            "an accepted regression past the threshold fails",
            len(compare(base, {**base, "c": {"category": "technical", "verdict": "fail"}}, {"c"})[0]) == 1,
        ),
        ("a removed case is the corpus audit's, not this one's", compare(base, {"a": base["a"]}, set())[0] == []),
    ]
    failed = [name for name, held in checks if not held]
    for name in failed:
        print(f"rules scorecard self-test: FAILED: {name}", file=sys.stderr)
    if verdict_self_test():
        failed.append("malformed verdict admission")
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--measured", help="the scorecard this branch writes")
    parser.add_argument("--base", help="the scorecard recorded on the base commit")
    parser.add_argument("--base-accepted", help="the accepted-regressions file on the base commit")
    parser.add_argument("--markdown", help="also write the comparison as a pull request comment here")
    parser.add_argument("--update", action="store_true", help="record --measured as Scripts/rules_scorecard.json")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        return self_test()
    try:
        measured = read_cases(arguments.measured)
        if arguments.update:
            shutil.copyfile(arguments.measured, RECORDED)
            print(f"rules scorecard: recorded {arguments.measured} as {RECORDED.relative_to(ROOT)}")
            return 0
        base = read_cases(arguments.base) if arguments.base and Path(arguments.base).exists() else None
    except VerdictError as error:
        print(f"rules scorecard: {error}", file=sys.stderr)
        return 1
    if not arguments.base or not Path(arguments.base).exists():
        print("rules scorecard: the base records no scorecard, so there is nothing to compare with")
        return 0
    accepted = read_accepted(ACCEPTED) - read_accepted(arguments.base_accepted)
    problems, accepted_regressions = compare(base, measured, accepted)
    report = markdown(base, measured, problems, accepted_regressions)
    if arguments.markdown:
        Path(arguments.markdown).write_text(report)
    print(report)
    for problem in problems:
        print(f"rules scorecard: {problem}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
