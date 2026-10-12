"""Proves saved bench scoring requires a baseline when a verdict is requested."""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from dictation_bench_test import CLIP, result_event

ROOT = Path(__file__).resolve().parent.parent


class BenchGateArgumentTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="bench-gate-")
        self.addCleanup(self.scratch.cleanup)
        self.out = Path(self.scratch.name)
        (self.out / "corpus.json").write_text(json.dumps([CLIP]), encoding="utf-8")
        self.run = self.out / "run.jsonl"
        self.run.write_text("BENCH " + json.dumps(result_event("known")) + "\n", encoding="utf-8")

    def score(self, *flags):
        return subprocess.run(
            [sys.executable, str(ROOT / "Scripts/dictation_bench.py"), "--out", str(self.out),
             "score", str(self.run), *flags], capture_output=True, text=True, timeout=30,
            env=dict(os.environ, UTTRFLOW_EVAL=str(ROOT / ".build/debug/uttrflow-eval")))

    def test_a_required_verdict_without_a_baseline_is_refused(self):
        result = self.score("--fail-on-regression")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("--fail-on-regression requires --baseline", result.stderr)

    def test_exploratory_scoring_preserves_the_complete_original_output(self):
        result = self.score()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(len(result.stdout.encode()), 1244)
        self.assertEqual(hashlib.sha256(result.stdout.encode()).hexdigest(),
                         "967df357c5ee1f9af30e74f81c59438ac11e9057e2fd9752cdf023108d622796")

    def test_present_baseline_and_save_precedence_still_produce_a_verdict(self):
        clips = [dict(CLIP, id=f"case-{index}", wav=f"case-{index}.wav") for index in range(24)]
        (self.out / "corpus.json").write_text(json.dumps(clips), encoding="utf-8")
        self.run.write_text("".join("BENCH " + json.dumps(result_event(c["id"])) + "\n"
                                    for c in clips), encoding="utf-8")
        baseline = self.out / "baseline.json"
        saved = self.score("--baseline", str(baseline), "--save-baseline", "--fail-on-regression")
        self.assertEqual(saved.returncode, 0, saved.stdout + saved.stderr)
        self.assertEqual(saved.stderr, "")
        entries = json.loads(baseline.read_text())["entries"]
        self.assertEqual(len(entries), 24)
        self.assertEqual([(e["errors"], e["referenceWordCount"]) for e in entries], [(0, 2)] * 24)
        same = self.score("--baseline", str(baseline), "--fail-on-regression")
        self.assertEqual(same.returncode, 0, same.stdout + same.stderr)
        self.assertEqual(same.stderr, "")
        self.assertIn("verdict: no change detectable", same.stdout)
