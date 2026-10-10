#!/usr/bin/env python3
"""Proves the prediction scorecard refuses precision and wrong-line regressions."""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("predict_scorecard", os.path.join(HERE, "predict_scorecard.py"))
SCORECARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCORECARD)


def result(name, category, hit):
    return {
        "name": name,
        "category": category,
        "typed": "a line",
        "hit": hit,
        "judged": True,
        "conforms": True,
        "elapsedMs": 10,
        "first": "completion",
        "drawn": ["completion"],
    }


def full_fixture_report(results):
    return {
        "results": results,
        "summary": {"total": len(results)},
        "fixtureCatalogueCount": len(results),
        "fullFixtureCatalogue": True,
    }


class PrecisionRatchetTests(unittest.TestCase):
    def setUp(self):
        self.baseline_results = [
            result("chat/right", "chat", True),
            result("chat/wrong", "chat", False),
            result("terminal/right", "terminal", True),
            result("terminal/wrong", "terminal", False),
        ]
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as handle:
            self.baseline_path = handle.name
        self.addCleanup(lambda: os.unlink(self.baseline_path))
        SCORECARD.write_baseline(
            self.baseline_path, self.baseline_results, 0.99, full_fixture_report(self.baseline_results))
        with open(self.baseline_path) as handle:
            self.baseline = json.load(handle)

    def test_unchanged_measured_baseline_passes_even_when_target_is_unmet(self):
        self.assertEqual(SCORECARD.ratchet(self.baseline_results, self.baseline), [])
        self.assertLess(self.baseline["overall"]["right"] / self.baseline["overall"]["shown"], 0.99)

    def test_baseline_records_fixture_identities_and_counts_by_scope(self):
        self.assertEqual(self.baseline["schemaVersion"], 2)
        self.assertEqual(self.baseline["overall"]["fixtureCount"], 4)
        self.assertEqual(
            self.baseline["overall"]["fixtureNames"],
            ["chat/right", "chat/wrong", "terminal/right", "terminal/wrong"],
        )
        self.assertEqual(self.baseline["categories"]["chat"]["fixtureCount"], 2)
        self.assertEqual(
            self.baseline["categories"]["chat"]["fixtureNames"],
            ["chat/right", "chat/wrong"],
        )

    def test_full_catalogue_metadata_is_required_before_baseline_recording(self):
        self.assertEqual(
            SCORECARD.full_catalogue_recording_failures(
                full_fixture_report(self.baseline_results), self.baseline_results),
            [],
        )
        partial = full_fixture_report(self.baseline_results[:-1])
        partial["fixtureCatalogueCount"] = len(self.baseline_results)
        self.assertEqual(
            SCORECARD.full_catalogue_recording_failures(partial, self.baseline_results[:-1]),
            ["baseline recording requires every fixture in the reported catalogue"],
        )
        filtered = dict(full_fixture_report(self.baseline_results), fullFixtureCatalogue=False)
        self.assertEqual(
            SCORECARD.full_catalogue_recording_failures(filtered, self.baseline_results),
            ["baseline recording requires an unfiltered full fixture catalogue report"],
        )

    def test_duplicate_fixture_names_cannot_be_recorded_as_a_baseline(self):
        duplicate = self.baseline_results + [dict(self.baseline_results[0])]
        self.assertEqual(
            SCORECARD.full_catalogue_recording_failures(full_fixture_report(duplicate), duplicate),
            ["baseline recording refuses duplicate fixture names"],
        )

    def test_cli_refuses_to_record_a_filtered_run(self):
        with tempfile.TemporaryDirectory() as directory:
            run_path = os.path.join(directory, "partial.json")
            baseline_path = os.path.join(directory, "baseline.json")
            partial = full_fixture_report(self.baseline_results[:-1])
            partial["fullFixtureCatalogue"] = False
            with open(run_path, "w") as handle:
                json.dump(partial, handle)
            completed = subprocess.run(
                [
                    sys.executable,
                    os.path.join(HERE, "predict_scorecard.py"),
                    run_path,
                    "--record-baseline",
                    baseline_path,
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertFalse(os.path.exists(baseline_path))
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("unfiltered full fixture catalogue", completed.stdout)

    def test_omitted_fixture_fails_even_when_precision_improves(self):
        current = [row for row in self.baseline_results if row["name"] != "chat/wrong"]
        failures = SCORECARD.ratchet(current, self.baseline)
        self.assertIn("overall: fixture set differs (missing 1, unexpected 0)", failures)
        self.assertIn("chat: fixture set differs (missing 1, unexpected 0)", failures)

    def test_added_fixture_fails_even_when_precision_does_not_drop(self):
        current = self.baseline_results + [result("chat/new-right", "chat", True)]
        failures = SCORECARD.ratchet(current, self.baseline)
        self.assertIn("overall: fixture set differs (missing 0, unexpected 1)", failures)
        self.assertIn("chat: fixture set differs (missing 0, unexpected 1)", failures)

    def test_fixture_moved_between_categories_fails(self):
        current = [dict(row) for row in self.baseline_results]
        current[0]["category"] = "terminal"
        failures = SCORECARD.ratchet(current, self.baseline)
        self.assertIn("chat: fixture set differs (missing 1, unexpected 0)", failures)
        self.assertIn("terminal: fixture set differs (missing 0, unexpected 1)", failures)

    def test_legacy_baseline_without_fixture_identities_fails_closed(self):
        legacy = dict(self.baseline, schemaVersion=1)
        self.assertEqual(
            SCORECARD.ratchet(self.baseline_results, legacy),
            ["recorded baseline lacks fixture identities; re-record it with schema version 2"],
        )

    def test_precision_drop_fails_overall_and_category(self):
        current = self.baseline_results + [result("chat/extra-wrong", "chat", False)]
        failures = SCORECARD.ratchet(current, self.baseline)
        self.assertTrue(any(failure.startswith("overall: precision fell") for failure in failures))
        self.assertTrue(any(failure.startswith("chat: precision fell") for failure in failures))

    def test_quieting_a_right_line_fails_even_when_wrong_count_is_unchanged(self):
        current = [row for row in self.baseline_results if row["name"] != "chat/right"]
        failures = SCORECARD.ratchet(current, self.baseline)
        self.assertTrue(any(failure.startswith("overall: precision fell") for failure in failures))
        self.assertTrue(any(failure.startswith("chat: precision fell") for failure in failures))
        self.assertFalse(any("wrong shown rose" in failure for failure in failures))

    def test_wrong_shown_increase_fails_even_when_precision_is_unchanged(self):
        current = self.baseline_results + [
            result("terminal/extra-right", "terminal", True),
            result("terminal/extra-wrong", "terminal", False),
        ]
        failures = SCORECARD.ratchet(current, self.baseline)
        self.assertIn("overall: wrong shown rose 2 -> 3", failures)
        self.assertIn("terminal: wrong shown rose 1 -> 2", failures)
        self.assertFalse(any("precision fell" in failure for failure in failures))

    def test_category_addition_fails(self):
        current = self.baseline_results + [result("mail/right", "mail", True)]
        self.assertIn(
            "fixture categories differ from the recorded baseline",
            SCORECARD.ratchet(current, self.baseline),
        )

    def test_withheld_candidate_is_not_counted_as_wrong_shown(self):
        withheld = result("chat/withheld", "chat", False)
        withheld["drawn"] = []
        self.assertEqual(SCORECARD.summarise([withheld])["shown"], 0)

    def test_cli_keeps_sub_target_baseline_visible_without_failing_unchanged_run(self):
        with tempfile.TemporaryDirectory() as directory:
            run_path = os.path.join(directory, "run.json")
            with open(run_path, "w") as handle:
                json.dump(full_fixture_report(self.baseline_results), handle)
            completed = subprocess.run(
                [
                    sys.executable,
                    os.path.join(HERE, "predict_scorecard.py"),
                    run_path,
                    "--baseline",
                    self.baseline_path,
                ],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(completed.returncode, 0)
        self.assertIn("precision ratchet:\n  PASS", completed.stdout)
        self.assertIn("TARGET NOT MET overall", completed.stdout)

    def test_make_scorecard_gate_fails_on_synthetic_regression(self):
        with tempfile.TemporaryDirectory() as directory:
            run_path = os.path.join(directory, "run.json")
            regressed = self.baseline_results + [result("chat/extra-wrong", "chat", False)]
            with open(run_path, "w") as handle:
                json.dump({"results": regressed}, handle)
            completed = subprocess.run(
                [
                    "make",
                    "--no-print-directory",
                    "predict-scorecard",
                    f"PREDICT_FIXTURE_RUN={run_path}",
                    f"PREDICT_PRECISION_BASELINE={self.baseline_path}",
                ],
                cwd=os.path.dirname(HERE),
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("wrong shown rose", completed.stdout)


if __name__ == "__main__":
    unittest.main()
