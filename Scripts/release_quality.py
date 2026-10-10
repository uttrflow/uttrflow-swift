#!/usr/bin/env python3
"""Run every release quality gate in order, print a pass or fail table, and write it for the release notes.

`make release-quality` runs it before a candidate is tagged; RELEASING.md step four starts with it.
A gate whose input is missing reports "no verdict", which fails the command like a regression does.
It tags nothing.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / "dist" / "release-quality.md"
LAYER_CONTRIBUTION = "dist/layer-contribution.md"
PASS, FAIL, NO_VERDICT = "pass", "fail", "no verdict"
NO_TESTS_RAN = "No matching test cases were run"


@dataclass
class Gate:
    name: str
    threshold: str
    command: list[str]
    missing: str = ""
    empty_marker: str = ""
    appendix: str = ""


@dataclass
class Result:
    gate: Gate
    verdict: str
    evidence: str
    appendix: str = ""


def swift_test(filter_pattern: str) -> list[str]:
    return ["xcrun", "swift", "test", "--skip-update", "--filter", filter_pattern]


def gates(bakeoff_baseline: str, bench_run: str) -> list[Gate]:
    make = os.environ.get("MAKE", "make")
    python = sys.executable
    baseline_missing = "" if bakeoff_baseline and Path(bakeoff_baseline).is_file() else (
        "no saved bake-off result: pass BAKEOFF_BASELINE=<file>")
    run_missing = "" if bench_run and Path(bench_run).exists() else (
        "no `uttrflow-dev bench` run: pass RUN=<path>")
    return [
        Gate("accuracy", "no slice worse than Scripts/accuracy_baseline.json",
             [make, "accuracy-gate"]),
        Gate("seam score", "no long-form clip with more seam artefacts than Scripts/seam_score_baseline.json",
             [make, "seam-score"]),
        Gate("clean-up held-out compare", "no case regression and a held-out verdict that is not over-fitted",
             [make, "bakeoff", f"ARGS=--against {bakeoff_baseline}"], missing=baseline_missing),
        Gate("perf budget, source", "every energy and memory check holds and still bites",
             [python, "Scripts/perf_budget_audit.py", "--self-test"]),
        Gate("perf budget, latency", "each stage's p95 within its budget",
             [python, "Scripts/perf_budget_audit.py", "--latency", bench_run], missing=run_missing),
        Gate("coverage matrix", "every class at its covered floor and every page matches the corpus",
             swift_test(r"UttrflowEvalTests\.(CodeMix|Destination|Formatting|Genre)MatrixTests"),
             empty_marker=NO_TESTS_RAN),
        Gate("contamination", "0 corpus passages in tuned-on text; splits disjoint",
             swift_test(r"UttrflowEvalTests\.(ContaminationAudit|SourceLiteralContamination"
                        r"|CorpusSplit|TranscriptionSplit)Tests"),
             empty_marker=NO_TESTS_RAN),
        Gate("layer contribution", "every degraded path above the floor; each layer's verdict is listed below",
             ["env", f"UTTRFLOW_LAYER_CONTRIBUTION={ROOT / LAYER_CONTRIBUTION}",
              *swift_test(r"UttrflowEvalTests\.DegradedPathMatrixTests")],
             empty_marker=NO_TESTS_RAN, appendix=LAYER_CONTRIBUTION),
        Gate("disclosure history", "0 findings on every commit of every ref",
             [python, "Scripts/disclosure_audit.py", "--history"]),
    ]


FAILURE_MARKS = ("✗", "FAIL", "error:")


def summary_line(text: str, failed: bool) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if failed:
        lines = [line for line in lines if line.startswith(FAILURE_MARKS)] or lines
        return lines[0] if lines else "no output"
    return lines[-1] if lines else "no output"


def run(gate: Gate, cwd: Path) -> Result:
    if gate.missing:
        return Result(gate, NO_VERDICT, gate.missing)
    print(f"==> {gate.name}: {' '.join(gate.command)}", flush=True)
    appendix = cwd / gate.appendix if gate.appendix else None
    if appendix:
        appendix.unlink(missing_ok=True)
    try:
        completed = subprocess.run(gate.command, cwd=cwd, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, check=False)
    except OSError as error:
        return Result(gate, NO_VERDICT, f"could not start: {error}")
    sys.stdout.write(completed.stdout)
    if gate.empty_marker and gate.empty_marker in completed.stdout:
        return Result(gate, NO_VERDICT, "the filter matched no tests")
    if appendix and completed.returncode == 0 and not appendix.is_file():
        return Result(gate, NO_VERDICT, f"passed without writing {gate.appendix}")
    verdict = PASS if completed.returncode == 0 else FAIL
    evidence = summary_line(completed.stdout, verdict == FAIL)
    if verdict == FAIL:
        evidence = f"exit {completed.returncode}: {evidence}"
    text = appendix.read_text(encoding="utf-8") if appendix and appendix.is_file() else ""
    return Result(gate, verdict, evidence, text)


def table(results: list[Result]) -> str:
    rows = ["| Gate | Verdict | Threshold | Result |", "|---|---|---|---|"]
    for result in results:
        cells = [result.gate.name, result.verdict, result.gate.threshold, result.evidence]
        rows.append("| " + " | ".join(cell.replace("|", "\\|") for cell in cells) + " |")
    return "\n".join(rows)


def report(results: list[Result], commit: str) -> str:
    failed = [result.gate.name for result in results if result.verdict != PASS]
    summary = "Every gate passed." if not failed else "Not releasable: " + ", ".join(failed) + "."
    appendices = "".join(f"\n{result.appendix.rstrip()}\n" for result in results if result.appendix)
    return f"# Release quality\n\nCommit `{commit}`.\n\n{table(results)}\n\n{summary}\n{appendices}"


def head_commit(cwd: Path) -> str:
    completed = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=cwd,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=False)
    return completed.stdout.strip() or "unknown"


def release_quality(all_gates: list[Gate], output: Path, cwd: Path) -> int:
    results = [run(gate, cwd) for gate in all_gates]
    text = report(results, head_commit(cwd))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print()
    print(text)
    print(f"Wrote {output}")
    return 0 if all(result.verdict == PASS for result in results) else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bakeoff-baseline", default="", help="the saved bake-off result to compare against")
    parser.add_argument("--bench-run", default="", help="a `uttrflow-dev bench` run for the latency budget")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="where the Markdown result is written")
    options = parser.parse_args(argv)
    return release_quality(gates(options.bakeoff_baseline, options.bench_run), Path(options.output), ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
