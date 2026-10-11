"""The formatting gap updater only removes fully measured passing case IDs."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from formatting_gap_ratchet import REGISTRY, RULES, GOLDEN, PAGE, run, shrink, shrink_rules, validate_outputs, replace_outputs

SOURCE = '''before
    static let knownGaps: Set<String> = [
        // A token keeps its mark.
        "case-first", "case-second",
    ]
after-positive-assertions
'''


RULES_SOURCE = SOURCE.replace("knownGaps", "knownFailures") + "#expect(named.count == 8 + Self.knownFailures.count)\n"


class FormattingGapRatchetTests(unittest.TestCase):
    def test_only_passing_case_is_removed_and_surrounding_assertions_stay(self):
        updated, removed = shrink(SOURCE, [
            {"id": "case-first", "rulesPassed": True},
            {"id": "case-second", "rulesPassed": False}])
        self.assertEqual(removed, ["case-first"])
        self.assertNotIn('"case-first"', updated)
        self.assertIn('"case-second"', updated)
        self.assertTrue(updated.endswith("after-positive-assertions\n"))
        self.assertIn("// A token keeps its mark.", updated)

    def test_a_failing_case_leaves_the_registry_byte_identical(self):
        updated, removed = shrink(SOURCE, [
            {"id": key, "rulesPassed": False} for key in ["case-first", "case-second"]])
        self.assertEqual(updated, SOURCE)
        self.assertEqual(removed, [])

    def test_missing_unknown_or_duplicate_measurements_are_rejected(self):
        first = {"id": "case-first", "rulesPassed": True}
        for rows in [[first], [first, first], [first, {"id": "unknown", "rulesPassed": True}]]:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                shrink(SOURCE, rows)

    def test_nonboolean_passes_and_extra_fields_are_rejected(self):
        for invalid in [1, "true", None]:
            with self.subTest(value=invalid), self.assertRaises(ValueError):
                shrink(SOURCE, [{"id": "case-first", "rulesPassed": invalid}])
        with self.assertRaises(ValueError):
            shrink(SOURCE, [{"id": "case-first", "rulesPassed": True, "ignore": True}])

    def test_run_measures_fresh_cases_and_dry_run_does_not_write(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            registry = root / REGISTRY
            registry.parent.mkdir(parents=True)
            registry.write_text(SOURCE)
            for artifact in [RULES, GOLDEN, PAGE]:
                (root / artifact).parent.mkdir(parents=True, exist_ok=True)
                (root / artifact).write_text(RULES_SOURCE if artifact == RULES else "original")
            def measure(command, **kwargs):
                self.assertEqual(command[-1], "FormattingParityTests/measuredGapsForAbsorption")
                self.assertNotIn("--skip-build", command)
                report = Path(kwargs["env"]["UTTRFLOW_PARITY_MEASUREMENTS"])
                report.write_text(json.dumps([
                    {"id": key, "rulesPassed": True} for key in ["case-first", "case-second"]]))
            with patch("formatting_gap_ratchet.subprocess.run", side_effect=measure) as process:
                self.assertEqual(run(root, False), 0)
                process.assert_called_once()
            self.assertEqual(registry.read_text(), SOURCE)
            self.assertEqual((root / RULES).read_text(), RULES_SOURCE)
            self.assertEqual((root / GOLDEN).read_text(), "original")
            self.assertEqual((root / PAGE).read_text(), "original")

    def test_failed_measurement_cannot_absorb_anything(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            registry = root / REGISTRY
            registry.parent.mkdir(parents=True)
            registry.write_text(SOURCE)
            for artifact in [RULES, GOLDEN, PAGE]:
                (root / artifact).parent.mkdir(parents=True, exist_ok=True)
                (root / artifact).write_text(RULES_SOURCE if artifact == RULES else "original")
            with patch("formatting_gap_ratchet.subprocess.run",
                       side_effect=subprocess.CalledProcessError(1, "swift")):
                with self.assertRaises(subprocess.CalledProcessError):
                    run(root, True)
            self.assertEqual(registry.read_text(), SOURCE)

    def test_generated_outputs_remove_only_measured_ids(self):
        old = "| code | both | 3 | 1 | 2: `case-first`, `case-second` | 0 | 0 |"
        new = "| code | both | 3 | 2 | 1: `case-second` | 0 | 0 |"
        validate_outputs("case-first\twrong\ncase-second\told\n",
                         "case-first\tright\ncase-second\told\n", old, new, ["case-first"])
        for invalid in [new.replace("| 3 |", "| 4 |"), new + "\nextra", old]:
            with self.assertRaises(ValueError):
                validate_outputs("case-first\twrong\n", "case-first\tright\n",
                                 old, invalid, ["case-first"])
        with self.assertRaises(ValueError):
            validate_outputs("case-first\twrong\ncase-second\told\n",
                             "case-first\tright\ncase-second\tunrelated\n",
                             old, new, ["case-first"])

    def test_artifacts_changed_during_measurement_or_generation_cannot_absorb(self):
        for phase, changed in [(phase, path) for phase in ["measurement", "generation"]
                              for path in [REGISTRY, RULES, GOLDEN, PAGE]]:
            with self.subTest(path=changed), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                for path, text in [(REGISTRY, SOURCE), (RULES, RULES_SOURCE), (GOLDEN, "original"), (PAGE, "original")]:
                    (root / path).parent.mkdir(parents=True, exist_ok=True)
                    (root / path).write_text(text)
                def measure(command, **kwargs):
                    Path(kwargs["env"]["UTTRFLOW_PARITY_MEASUREMENTS"]).write_text(json.dumps([
                        {"id": key, "rulesPassed": phase == "generation"} for key in ["case-first", "case-second"]]))
                    if phase == "measurement":
                        (root / changed).write_text("external change")
                def generate(*args):
                    (root / changed).write_text("external change")
                    return "candidate", "candidate"
                with patch("formatting_gap_ratchet.subprocess.run", side_effect=measure), \
                     patch("formatting_gap_ratchet.generated_outputs", side_effect=generate):
                    with self.assertRaises(ValueError):
                        run(root, True)
                self.assertEqual((root / REGISTRY).read_text(),
                                 "external change" if changed == REGISTRY else SOURCE)
                self.assertEqual((root / changed).read_text(), "external change")

    def test_partial_write_failure_restores_previous_artifacts(self):
        import os
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            originals = {key: f"old-{index}" for index, key in enumerate([REGISTRY, RULES, GOLDEN, PAGE])}
            for path, text in originals.items():
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).write_text(text)
            replace = os.replace
            def fail_second(source, destination):
                if Path(source).name == "new-3":
                    raise OSError("synthetic write failure")
                replace(source, destination)
            with patch("formatting_gap_ratchet.os.replace", side_effect=fail_second):
                with self.assertRaises(OSError):
                    replace_outputs(root, originals, {key: "new" for key in originals})
            self.assertEqual({key: (root / key).read_text() for key in originals}, originals)

    def test_absorption_requires_every_removed_gap_in_the_corpus(self):
        with self.assertRaises(ValueError):
            validate_outputs("case-first\told\n", "case-first\tnew\n", "", "",
                             ["case-first", "missing-corpus-case"])

    def test_rules_removal_preserves_the_absolute_destination_total(self):
        updated = shrink_rules(RULES_SOURCE, ["case-first", "outside-rules"])
        self.assertIn("named.count == 9 + Self.knownFailures.count", updated)
        self.assertIn('"case-second"', updated)
        self.assertNotIn('"case-first"', updated)
        self.assertEqual(shrink_rules(RULES_SOURCE, []), RULES_SOURCE)
        for invalid in [RULES_SOURCE.replace("8 +", "unknown +"), RULES_SOURCE + RULES_SOURCE]:
            with self.assertRaises(ValueError):
                shrink_rules(invalid, ["case-first"])

    def test_duplicate_registry_ids_are_rejected(self):
        with self.assertRaises(ValueError):
            shrink(SOURCE.replace("case-second", "case-first"), [])


if __name__ == "__main__":
    unittest.main()
