#!/usr/bin/env python3
"""Proves eval refuses malformed arguments before starting a measurement."""

import json
import os
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BINARY = os.path.join(ROOT, ".build", "debug", "uttrflow-eval")


class TranscribeLimitArgumentTests(unittest.TestCase):
    """Drives the built executable and checks validation before corpus setup."""

    def run_with(self, *arguments):
        return subprocess.run(
            [BINARY, "transcribe", *arguments], capture_output=True, text=True, timeout=120
        )

    def assert_refused(self, option, expected):
        # Joined with "=", since a separate "-1" reads as an option rather than a value.
        finished = self.run_with(f"{option}=-1")
        self.assertEqual(finished.returncode, 64, finished.stderr)
        said = finished.stdout + finished.stderr
        self.assertIn(expected, said)
        self.assertIn("usage:", said.lower())
        self.assertNotIn("Nothing to measure", said)

    def test_negative_findings_is_refused(self):
        self.assert_refused("--findings", "--findings must be zero or greater")

    def test_negative_passage_limit_is_refused(self):
        self.assert_refused("--passage-limit", "--passage-limit must be zero or greater")

    def test_zero_limits_are_accepted(self):
        with tempfile.TemporaryDirectory(prefix="uttrflow-eval-results-") as results:
            finished = self.run_with(
                "--findings", "0", "--passage-limit", "0", "--summarise", "--results-path", results
            )
        self.assertEqual(finished.returncode, 0, finished.stderr)
        self.assertIn("Nothing measured yet.", finished.stdout)
        self.assertNotIn("usage:", (finished.stdout + finished.stderr).lower())


class SweepGridArgumentTests(unittest.TestCase):
    """Drives command validation before table reads and valid-grid record creation."""

    def run_with(self, grid, table, record):
        return subprocess.run(
            [BINARY, "sweep", "--from-table", table, "--parameter", "doubt",
             "--grid", grid, "--record", record],
            capture_output=True, text=True, timeout=120,
        )

    def test_malformed_components_are_refused_before_table_io(self):
        grids = ["0.2,bad,0.3", "0.2,,0.3", ",0.2,0.3", "0.2,0.3,",
                 "0.2, ,0.3", "0.2,nan,0.3", "0.2,inf,0.3", "bad", "0.2"]
        with tempfile.TemporaryDirectory(prefix="sweep-grid-") as directory:
            table = os.path.join(directory, "absent.json")
            record = os.path.join(directory, "record.json")
            for grid in grids:
                with self.subTest(grid=grid):
                    finished = self.run_with(grid, table, record)
                    self.assertEqual(finished.returncode, 64, finished.stderr)
                    said = finished.stdout + finished.stderr
                    self.assertIn("--grid", said)
                    self.assertNotIn("cannot read the fit table", said)
                    self.assertFalse(os.path.exists(record))

    def test_valid_grid_records_all_values_including_whitespace_and_exponents(self):
        rows = []
        for split in ["development", "heldout"]:
            for label in ["wrong", "right"]:
                for _ in range(100):
                    rows.append({"ordinal": len(rows), "split": split, "language": "english",
                                 "label": label, "features": [0.1 if label == "wrong" else 0.9]})
        with tempfile.TemporaryDirectory(prefix="sweep-grid-") as directory:
            table = os.path.join(directory, "table.json")
            record = os.path.join(directory, "record.json")
            with open(table, "w", encoding="utf-8") as stream:
                json.dump({"schemaVersion": 1, "featureSpecVersion": 1, "rows": rows}, stream)
            finished = self.run_with(" 3e-1 , 0.2 ", table, record)
            self.assertEqual(finished.returncode, 0, finished.stderr)
            with open(record, encoding="utf-8") as stream:
                saved = json.load(stream)
            self.assertEqual(saved["grid"], [0.2, 0.3])
            self.assertEqual([trial["value"] for trial in saved["trials"]], [0.2, 0.3])


class AccentGroupBoundArgumentTests(unittest.TestCase):
    """Drives the saved-count CLI without loading a model."""

    def run_with(self, rows, *arguments):
        return subprocess.run(
            [BINARY, "accent-groups", "--rows", rows, *arguments],
            capture_output=True, text=True, timeout=30,
        )

    def test_invalid_bounds_are_refused_before_reading_rows(self):
        with tempfile.TemporaryDirectory(prefix="accent-bound-") as folder:
            missing = os.path.join(folder, "missing.tsv")
            for bound in ["0", "-0.001", "nan", "inf", "-inf", "1e-320", "1e-19"]:
                with self.subTest(bound=bound):
                    finished = self.run_with(missing, f"--decision-bound={bound}")
                    self.assertEqual(finished.returncode, 64, finished.stderr)
                    self.assertIn("--decision-bound must be finite and positive", finished.stderr)
                    self.assertIn("usage:", finished.stderr.lower())
                    self.assertNotIn("cannot read the counts table", finished.stderr)

    def test_default_and_representable_positive_bounds_keep_their_report(self):
        with tempfile.TemporaryDirectory(prefix="accent-bound-") as folder:
            rows = os.path.join(folder, "counts.tsv")
            with open(rows, "w", encoding="utf-8") as output:
                output.write("speaker-a\tgroup-a\tverified\t0\t10\t0\t0\n")
            default = self.run_with(rows)
            self.assertEqual(default.returncode, 0, default.stderr)
            self.assertIn("insufficient evidence (needs 3000 decisions)", default.stdout)
            controls = [("0.001", 3000), ("0.1", 30), ("2", 2), ("1e-18", 3 * 10**18)]
            for bound, needed in controls:
                with self.subTest(bound=bound):
                    finished = self.run_with(rows, f"--decision-bound={bound}")
                    self.assertEqual(finished.returncode, 0, finished.stderr)
                    expected = default.stdout.replace("needs 3000 decisions", f"needs {needed} decisions")
                    self.assertEqual(finished.stdout, expected)
                    self.assertNotIn("usage:", finished.stderr.lower())


    def write_count_rows(self, path, counts):
        with open(path, "w", encoding="utf-8") as output:
            output.write("\n")
            for speaker in ["speaker-a", "speaker-b"]:
                fields = [speaker, "group-a", "verified", *(str(count) for count in counts)]
                output.write("\t".join(fields) + "\n\n")

    def test_negative_saved_count_fields_are_refused(self):
        with tempfile.TemporaryDirectory(prefix="accent-count-") as folder:
            rows = os.path.join(folder, "counts.tsv")
            for field in range(4):
                with self.subTest(field=field):
                    counts = [0, 10, 2000, 0]
                    counts[field] = -1
                    self.write_count_rows(rows, counts)
                    finished = self.run_with(rows)
                    self.assertEqual(finished.returncode, 64, finished.stderr)
                    self.assertIn("line 1 is not a counts row", finished.stderr)
                    self.assertIn("usage:", finished.stderr.lower())
                    self.assertNotIn("group\tlabel", finished.stdout)

    def test_zero_and_insertion_counts_keep_the_existing_report(self):
        header = (
            "group\tlabel\tspeakers\twords\tdecisions\tWER\tinterval\tMDD\tfalse override\t"
            "seams\tseam rate\n"
        )
        controls = [
            ([0, 0, 0, 0],
             "group-a\tverified\t2\t0\t0\t0.0%\t+0.0..+0.0\t+0.0\t"
             "insufficient evidence (needs 3000 decisions)\t0\t-\n"),
            ([20, 10, 0, 0],
             "group-a\tverified\t2\t20\t0\t200.0%\t+200.0..+200.0\t+0.0\t"
             "insufficient evidence (needs 3000 decisions)\t0\t-\n"),
            ([0, 10, 1, 3],
             "group-a\tverified\t2\t20\t2\t0.0%\t+0.0..+0.0\t+0.0\t"
             "insufficient evidence (needs 3000 decisions)\t0\t-\n"),
        ]
        with tempfile.TemporaryDirectory(prefix="accent-count-") as folder:
            rows = os.path.join(folder, "counts.tsv")
            for counts, expected in controls:
                with self.subTest(counts=counts):
                    self.write_count_rows(rows, counts)
                    finished = self.run_with(rows)
                    self.assertEqual(finished.returncode, 0, finished.stderr)
                    self.assertEqual(finished.stdout, header + expected)
                    self.assertEqual(finished.stderr, "")


class MissingBaselineGateTests(unittest.TestCase):
    """Drives saved-run comparison without model setup."""

    def write_run(self, folder):
        measured = os.path.join(folder, "measured.json")
        baseline = os.path.join(folder, "baseline.json")
        entries = [
            {"caseID": f"case-{index:02}", "language": "english", "stresses": [],
             "errors": 0, "referenceWordCount": 10, "isUnscorable": False, "scoresOutput": False,
             "recordingIdentity": f"synthetic-{index:02}"} for index in range(24)
        ]
        report = {"label": "synthetic", "recordedAt": "2026-01-01T00:00:00Z",
                  "normalisation": [], "entries": entries}
        with open(measured, "w", encoding="utf-8") as stream:
            json.dump(report, stream)
        return measured, baseline, report

    def compare(self, measured, baseline, *flags):
        return subprocess.run(
            [BINARY, "compare", "--measured", measured, "--baseline", baseline, *flags],
            capture_output=True, text=True, timeout=30,
        )

    def diagnostic(self, baseline):
        return (f"No baseline at {baseline}. Write one with --save-baseline once you are happy "
                "with these numbers.\n")

    def test_missing_baseline_fails_when_a_verdict_is_required(self):
        with tempfile.TemporaryDirectory(prefix="baseline-gate-") as folder:
            measured, baseline, _ = self.write_run(folder)
            finished = self.compare(measured, baseline, "--fail-on-regression")
            self.assertEqual(finished.returncode, 1, finished.stderr)
            self.assertEqual(finished.stdout, self.diagnostic(baseline))
            self.assertEqual(finished.stderr, "")
            self.assertFalse(os.path.exists(baseline))

    def test_missing_baseline_exploration_keeps_its_exact_diagnostic(self):
        with tempfile.TemporaryDirectory(prefix="baseline-gate-") as folder:
            measured, baseline, _ = self.write_run(folder)
            finished = self.compare(measured, baseline)
            self.assertEqual(finished.returncode, 0, finished.stderr)
            self.assertEqual(finished.stdout, self.diagnostic(baseline))
            self.assertEqual(finished.stderr, "")
            self.assertFalse(os.path.exists(baseline))

    def test_save_precedence_and_present_comparison_keep_their_reports(self):
        with tempfile.TemporaryDirectory(prefix="baseline-gate-") as folder:
            measured, baseline, report = self.write_run(folder)
            saved = self.compare(measured, baseline, "--save-baseline", "--fail-on-regression")
            self.assertEqual(saved.returncode, 0, saved.stderr)
            self.assertEqual(saved.stdout, f"\nBaseline written to {baseline}. Later runs are measured against it.\n")
            self.assertEqual(saved.stderr, "")
            with open(baseline, encoding="utf-8") as stream:
                self.assertEqual(json.load(stream), report)
            exploratory = self.compare(measured, baseline)
            gated = self.compare(measured, baseline, "--fail-on-regression")
            for finished in [exploratory, gated]:
                self.assertEqual(finished.returncode, 0, finished.stderr)
                self.assertEqual(finished.stderr, "")
                self.assertIn("verdict: no change detectable", finished.stdout)
                self.assertNotIn("too few utterances to judge", finished.stdout)
            self.assertEqual(gated.stdout, exploratory.stdout)
            self.assertEqual(self.compare(measured, baseline, "--fail-on-regression").stdout, gated.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=1)
