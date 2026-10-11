#!/usr/bin/env python3
"""Prints how many live-model suites a test run ran and how many it skipped.

A live-model suite lives in a file named `*LiveModelTests.swift`; its display name is read
from the file's `@Suite("...")`. Usage: live_model_tally.py <swift-test-output.log>
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUITE_NAME = re.compile(r'@Suite\(\s*"([^"]+)"')


def live_suite_names(tests_root: pathlib.Path) -> list[str]:
    names = []
    for path in sorted(tests_root.rglob("*LiveModelTests.swift")):
        match = SUITE_NAME.search(path.read_text(encoding="utf-8"))
        if match:
            names.append(match.group(1))
    return names


def tally(log: str, names: list[str]) -> tuple[int, int, list[str]]:
    ran, skipped, missing = 0, 0, []
    for name in names:
        outcome = re.search(r'Suite "' + re.escape(name) + r'" (passed|failed|skipped)', log)
        if outcome is None:
            missing.append(name)
        elif outcome.group(1) == "skipped":
            skipped += 1
        else:
            ran += 1
    return ran, skipped, missing


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    log = pathlib.Path(argv[1]).read_text(encoding="utf-8", errors="replace")
    names = live_suite_names(ROOT / "Tests")
    ran, skipped, missing = tally(log, names)
    print(f"live-model tests: {ran} run, {skipped} skipped")
    for name in missing:
        print(f"  not in this run: {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
