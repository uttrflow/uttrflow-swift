#!/usr/bin/env python3
"""Prove flake_report finds differing outcomes and refuses an expired quarantine."""

from __future__ import annotations

import contextlib
import datetime as dt
import io
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "flake_report", Path(__file__).resolve().parent / "flake_report.py"
)
assert SPEC and SPEC.loader
flake_report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(flake_report)

RUN = """<testsuites><testsuite name="t">
<testcase classname="Audio" name="steady()"/>
<testcase classname="Audio" name="timer()">{timer}</testcase>
<testcase classname="Audio" name="skipped()"><skipped/></testcase>
</testsuite></testsuites>"""


def check(condition: bool, message: str) -> None:
    if not condition:
        print(f"FAIL: {message}", file=sys.stderr)
        raise SystemExit(1)


def check_reporting(root: Path) -> None:
    """Checks executed denominators and unobserved counts through the CLI parser."""
    green, red, skipped, missing = [root / f"{name}.xml" for name in ("green", "red", "skip", "missing")]
    green.write_text(RUN.format(timer=""), encoding="utf-8")
    red.write_text(RUN.format(timer="<failure/>"), encoding="utf-8")
    skipped.write_text(RUN.format(timer="<skipped/>"), encoding="utf-8")
    missing.write_text("<testsuites/>", encoding="utf-8")
    quarantine = root / "report-quarantine.json"
    quarantine.write_text(json.dumps([{"test": "Audio/timer()"}]), encoding="utf-8")
    cases = [
        ("complete", [green, red, red], "2/3 failed  Audio/timer() [quarantined]"),
        ("skipped", [green, red, skipped], "1/2 failed  Audio/timer() [quarantined] [1 unobserved]"),
        ("missing", [green, red, missing], "1/2 failed  Audio/timer() [quarantined] [1 unobserved]"),
        ("both", [green, red, skipped, missing], "1/2 failed  Audio/timer() [quarantined] [2 unobserved]"),
    ]
    problems = []
    for name, paths, expected in cases:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = flake_report.main([*(str(path) for path in paths), "--quarantine", str(quarantine)])
        lines = output.getvalue().splitlines()
        if code != 0 or lines[1:] != ["  " + expected]:
            problems.append(f"{name}: expected {expected!r}, got {lines[1:]!r} (exit {code})")
        else:
            print(f"flake_report CLI: {name} observed-count control passed")
    check(not problems, "\n".join(problems))


def check_ownership(root: Path) -> None:
    """Checks that quarantine ownership names a positive ASCII issue number."""
    quarantine = root / "owner-quarantine.json"
    invalid = [" ", "no-issue", "-1", "0", "000", "1.5", "1 2", "١", "1\n", True, 1]
    problems = []
    for owner in invalid:
        quarantine.write_text(json.dumps([
            {"test": "Audio/timer()", "owner_issue": owner, "expires": "2026-01-10"}
        ]), encoding="utf-8")
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            code = flake_report.main([
                "--check-quarantine", "--quarantine", str(quarantine), "--today", "2026-01-10"
            ])
        if code != 1 or "owner_issue" not in errors.getvalue():
            problems.append(f"owner {owner!r}: expected ownership refusal, got exit {code}")
    check(not problems, "\n".join(problems))
    for owner in ["1", "42", "0001"]:
        quarantine.write_text(json.dumps([
            {"test": "Audio/timer()", "owner_issue": owner, "expires": "2026-01-10"}
        ]), encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            code = flake_report.main([
                "--check-quarantine", "--quarantine", str(quarantine), "--today", "2026-01-10"
            ])
        check(code == 0, f"valid owner {owner!r} was refused")
    print("flake_report CLI: invalid owners refused, positive ASCII issue strings accepted")


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        green, red = root / "a.xml", root / "b.xml"
        green.write_text(RUN.format(timer=""), encoding="utf-8")
        red.write_text(RUN.format(timer="<failure message='late'/>"), encoding="utf-8")
        runs = [flake_report.outcomes(green), flake_report.outcomes(red), flake_report.outcomes(red)]
        check(flake_report.differing(runs) == {"Audio/timer()": 2}, "differing outcome not found")
        check("Audio/skipped()" not in runs[0], "a skipped test was counted as a pass")
        check(flake_report.differing(runs[1:]) == {}, "a steady failure was called flaky")

        today = dt.date(2026, 1, 10)
        live = {"test": "Audio/timer()", "owner_issue": "1", "expires": "2026-01-10"}
        expired = dict(live, expires="2026-01-09")
        check(flake_report.quarantine_problems([live], today) == [], "a live quarantine was refused")
        check(len(flake_report.quarantine_problems([expired], today)) == 1, "expiry not refused")
        check(len(flake_report.quarantine_problems([{"test": "x"}], today)) == 1, "no owner accepted")

        file = root / "q.json"
        file.write_text(json.dumps([expired]), encoding="utf-8")
        args = ["--check-quarantine", "--quarantine", str(file), "--today", "2026-01-10"]
        check(flake_report.main(args) == 1, "an expired quarantine passed the audit")
        check_reporting(root)
        check_ownership(root)
    print("flake_report: differing outcomes found, expired quarantine refused")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
