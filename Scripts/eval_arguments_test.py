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


if __name__ == "__main__":
    unittest.main(verbosity=1)
