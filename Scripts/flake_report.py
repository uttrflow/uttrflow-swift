#!/usr/bin/env python3
"""Find tests whose outcome differs between runs, and refuse an expired quarantine.

Report mode reads two or more JUnit XML files written by
`swift test --parallel --xunit-output <file>` (Swift Testing writes
`<file stem>-swift-testing.xml` beside it) and prints every test that passed in one run
and failed in another, with its failure count. A test listed in the quarantine file is
still run and still printed, marked as quarantined; nothing is skipped.

Check mode (`--check-quarantine`) reads `Scripts/flake_quarantine.json` and exits 1 when
an entry has passed its expiry date or lacks an owner issue. `make flake-audit` runs it,
so a quarantine cannot outlive its deadline unnoticed. Docs/test-flakes.md has the rule.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

QUARANTINE = Path(__file__).resolve().parent / "flake_quarantine.json"
REQUIRED_FIELDS = ("test", "owner_issue", "expires")


def outcomes(path: Path) -> dict[str, bool]:
    """Maps each test id in one JUnit file to whether it passed."""
    result: dict[str, bool] = {}
    for case in ET.parse(path).getroot().iter("testcase"):
        test_id = f"{case.get('classname', '')}/{case.get('name', '')}"
        failed = case.find("failure") is not None or case.find("error") is not None
        if case.find("skipped") is not None:
            continue
        result[test_id] = result.get(test_id, True) and not failed
    return result


def differing(runs: list[dict[str, bool]]) -> dict[str, int]:
    """Tests that passed in at least one run and failed in at least one, with failure counts."""
    seen: dict[str, list[bool]] = {}
    for run in runs:
        for test_id, passed in run.items():
            seen.setdefault(test_id, []).append(passed)
    return {
        test_id: results.count(False)
        for test_id, results in sorted(seen.items())
        if True in results and False in results
    }


def load_quarantine(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"{path} must hold a JSON list")
    return data


def quarantine_problems(entries: list[dict[str, str]], today: dt.date) -> list[str]:
    problems: list[str] = []
    for index, entry in enumerate(entries):
        missing = [field for field in REQUIRED_FIELDS if not entry.get(field)]
        if missing:
            problems.append(f"entry {index} lacks {', '.join(missing)}")
            continue
        owner = entry["owner_issue"]
        if (
            not isinstance(owner, str)
            or not owner.isascii()
            or not owner.isdecimal()
            or not owner.strip("0")
        ):
            problems.append(f"{entry['test']}: owner_issue must be a positive ASCII issue number")
            continue
        try:
            expires = dt.date.fromisoformat(entry["expires"])
        except ValueError:
            problems.append(f"{entry['test']}: expiry {entry['expires']!r} is not YYYY-MM-DD")
            continue
        if expires < today:
            problems.append(
                f"{entry['test']}: quarantine expired {expires} (owner #{entry['owner_issue']});"
                " fix the cause or remove the test"
            )
    return problems


def report(paths: list[Path], quarantine: list[dict[str, str]]) -> int:
    runs = [outcomes(path) for path in paths]
    flaky = differing(runs)
    quarantined = {entry.get("test") for entry in quarantine}
    print(f"{len(runs)} runs, {len(set().union(*runs))} tests, {len(flaky)} with differing outcomes")
    for test_id, failures in flaky.items():
        mark = " [quarantined]" if test_id in quarantined else ""
        executed = sum(test_id in run for run in runs)
        unobserved = len(runs) - executed
        missing = f" [{unobserved} unobserved]" if unobserved else ""
        print(f"  {failures}/{executed} failed  {test_id}{mark}{missing}")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("runs", nargs="*", type=Path, help="JUnit XML files, one per run")
    parser.add_argument("--check-quarantine", action="store_true")
    parser.add_argument("--quarantine", type=Path, default=QUARANTINE)
    parser.add_argument("--today", type=dt.date.fromisoformat, default=dt.date.today())
    args = parser.parse_args(argv)
    entries = load_quarantine(args.quarantine)
    if args.check_quarantine:
        problems = quarantine_problems(entries, args.today)
        for problem in problems:
            print(f"flake-audit: {problem}", file=sys.stderr)
        if not problems:
            print(f"flake-audit: {len(entries)} quarantined tests, none expired")
        return 1 if problems else 0
    if len(args.runs) < 2:
        parser.error("report mode needs at least two run files")
    return report(args.runs, entries)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
