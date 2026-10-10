#!/usr/bin/env python3
"""Prove release_quality fails on a regression in each gate, names it, and refuses a gate with no verdict."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import sys
import tempfile
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "release_quality", Path(__file__).resolve().parent / "release_quality.py"
)
assert SPEC and SPEC.loader
release_quality = importlib.util.module_from_spec(SPEC)
sys.modules["release_quality"] = release_quality
SPEC.loader.exec_module(release_quality)

EXPECTED_GATES = [
    "accuracy", "clean-up held-out compare", "perf budget, source", "perf budget, latency",
    "coverage matrix", "contamination", "disclosure history",
]


def check(condition: bool, message: str) -> None:
    if not condition:
        print(f"FAIL: {message}", file=sys.stderr)
        raise SystemExit(1)


def script(code: str) -> list[str]:
    return [sys.executable, "-c", code]


def passing(gate):
    return release_quality.Gate(gate.name, gate.threshold, script("print('0 findings')"),
                                empty_marker=gate.empty_marker)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
        root = Path(tmp)
        real = release_quality.gates(str(root / "absent.json"), str(root / "absent-run"))
        check([gate.name for gate in real] == EXPECTED_GATES, "the gates or their order changed")
        missing = {gate.name for gate in real if gate.missing}
        check(missing == {"clean-up held-out compare", "perf budget, latency"},
              "a gate with no input was not reported as missing it")

        clean = [passing(gate) for gate in real]
        output = root / "dist" / "release-quality.md"
        check(release_quality.release_quality(clean, output, root) == 0, "a clean run failed")
        written = output.read_text(encoding="utf-8")
        check("Every gate passed." in written, "a clean run did not write its verdict")
        check(all(f"| {name} | pass |" in written for name in EXPECTED_GATES), "a passing gate is missing")

        for index, gate in enumerate(real):
            broken = list(clean)
            broken[index] = release_quality.Gate(
                gate.name, gate.threshold, script("print('  ✗ 3 over budget'); print('✓ later line'); raise SystemExit(2)"))
            check(release_quality.release_quality(broken, output, root) == 1,
                  f"a regression in {gate.name} passed")
            written = output.read_text(encoding="utf-8")
            check(f"| {gate.name} | fail |" in written and "exit 2: ✗ 3 over budget" in written,
                  f"the table does not name the failing gate {gate.name}")
            check(f"Not releasable: {gate.name}." in written, f"the summary does not name {gate.name}")

        absent = list(clean)
        absent[1] = real[1]
        check(release_quality.release_quality(absent, output, root) == 1, "a gate with no verdict passed")
        check("| clean-up held-out compare | no verdict |" in output.read_text(encoding="utf-8"),
              "a missing input was not reported as no verdict")

        empty = list(clean)
        empty[4] = release_quality.Gate(real[4].name, real[4].threshold,
                                        script(f"print('{release_quality.NO_TESTS_RAN}')"),
                                        empty_marker=release_quality.NO_TESTS_RAN)
        check(release_quality.release_quality(empty, output, root) == 1, "a filter that ran no tests passed")
    print("release_quality: each gate's regression fails and is named; no verdict fails; a clean run writes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
