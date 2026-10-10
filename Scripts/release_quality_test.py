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
    "accuracy", "seam score", "clean-up held-out compare", "perf budget, source", "perf budget, latency",
    "coverage matrix", "contamination", "layer contribution", "disclosure history",
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
        absent[2] = real[2]
        check(release_quality.release_quality(absent, output, root) == 1, "a gate with no verdict passed")
        check("| clean-up held-out compare | no verdict |" in output.read_text(encoding="utf-8"),
              "a missing input was not reported as no verdict")

        empty = list(clean)
        empty[5] = release_quality.Gate(real[5].name, real[5].threshold,
                                        script(f"print('{release_quality.NO_TESTS_RAN}')"),
                                        empty_marker=release_quality.NO_TESTS_RAN)
        check(release_quality.release_quality(empty, output, root) == 1, "a filter that ran no tests passed")

        layers = next(index for index, gate in enumerate(real) if gate.appendix)
        silent = list(clean)
        silent[layers] = release_quality.Gate(real[layers].name, real[layers].threshold, script("print('ok')"),
                                              appendix="dist/layer-contribution.md")
        check(release_quality.release_quality(silent, output, root) == 1,
              "a contribution gate that wrote no table passed")
        writes = ("from pathlib import Path; Path('dist').mkdir(exist_ok=True); "
                  "Path('dist/layer-contribution.md').write_text('| formatting | keep |')")
        table = list(clean)
        table[layers] = release_quality.Gate(real[layers].name, real[layers].threshold, script(writes),
                                             appendix="dist/layer-contribution.md")
        check(release_quality.release_quality(table, output, root) == 0, "a contribution gate with a table failed")
        check("| formatting | keep |" in output.read_text(encoding="utf-8"),
              "the layer contribution table is missing from the result")
    print("release_quality: each gate's regression fails and is named; no verdict fails; a clean run writes;"
          " the layer contribution table is in the result")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
