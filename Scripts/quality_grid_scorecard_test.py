"""Prove that recording grids cannot hide missing, failed or regressing gates."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("quality_grid_scorecard.py")
GROUPS = ["onset", "condition", "number", "inflected", "lexicon", "clip-prefilter"]


def record(suite, identifier="case", **fields):
    return {"version": 1, "suite": suite, "id": identifier, "measurements": {}, "passed": True} | fields


class GridAbsorptionTests(unittest.TestCase):
    def run_absorb(self, records, output, directory):
        source = Path(directory) / "measured.json"
        source.write_text(json.dumps({"records": records}))
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--absorb", str(source), "--output", str(output)],
            capture_output=True, text=True)

    def test_complete_passing_grids_are_recorded_and_compare_equal(self):
        records = [record(group) for group in GROUPS]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "baseline.json"
            absorbed = self.run_absorb(records, output, directory)
            self.assertEqual(absorbed.returncode, 0, absorbed.stdout + absorbed.stderr)
            compared = subprocess.run(
                [sys.executable, str(SCRIPT), "--measured", str(output), "--base", str(output)],
                capture_output=True, text=True)
            self.assertEqual(compared.returncode, 0, compared.stdout + compared.stderr)
            self.assertIn("6 records, 0 problems", compared.stdout)

    def test_missing_family_and_duplicate_case_are_refused(self):
        complete = [record(group) for group in GROUPS]
        for records, reason in [
                (complete[:-1], "missing quality groups"),
                (complete + [complete[0]], "duplicate quality record")]:
            with self.subTest(reason=reason), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "baseline.json"
                result = self.run_absorb(records, output, directory)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(reason, result.stdout)
                self.assertFalse(output.exists())

    def test_failing_current_gate_is_not_recorded(self):
        records = [record(group, passed=group != "onset") for group in GROUPS]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "baseline.json"
            result = self.run_absorb(records, output, directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("existing gate fails", result.stdout)
            self.assertFalse(output.exists())

    def test_regressing_updates_leave_the_previous_record_unchanged(self):
        records = [record(group) for group in GROUPS]
        bucket = record("number", "bucket", failed=0, allowed=1)
        before = records + [bucket]
        for after, reason in [
                (records, "missing measured case"),
                (records + [bucket | {"allowed": 2}], "failure allowance increased"),
                (records + [bucket | {"failed": 1}], "failures rose"),
                (records + [record("number", "bucket")], "bucket gate kind changed")]:
            with self.subTest(reason=reason), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "baseline.json"
                previous = json.dumps({"records": before})
                output.write_text(previous)
                result = self.run_absorb(after, output, directory)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(reason, result.stdout)
                self.assertEqual(output.read_text(), previous)

    def test_improvements_and_new_passing_cases_can_be_recorded(self):
        records = [record(group) for group in GROUPS]
        bucket = record("number", "bucket", failed=1, allowed=1)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "baseline.json"
            output.write_text(json.dumps({"records": records + [bucket]}))
            after = records + [bucket | {"failed": 0}, record("onset", "extra")]
            result = self.run_absorb(after, output, directory)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(len(json.loads(output.read_text())["records"]), 8)

    def test_comparison_still_refuses_an_absent_base(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--measured", "unused.json"],
            capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no absent-base success", result.stderr)


if __name__ == "__main__":
    unittest.main()
