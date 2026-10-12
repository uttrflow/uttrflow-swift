"""Checks display-only bake-off argument refusals without running evaluation."""

from pathlib import Path
import subprocess
import tempfile
import unittest

BINARY = Path(__file__).resolve().parent.parent / ".build/debug/uttrflow-bakeoff"
DIAGNOSTIC = "--against applies to a new bake-off run, not --summarise or --sample."


class BakeoffDisplayArgumentTests(unittest.TestCase):
    def run_display(self, mode, compare=False):
        with tempfile.TemporaryDirectory(prefix="bakeoff-display-") as scratch:
            root = Path(scratch)
            arguments = [str(BINARY), mode, "--results-path", str(root / "absent-results")]
            if compare:
                arguments += ["--against", str(root / "absent-baseline.json")]
            result = subprocess.run(arguments, capture_output=True, text=True, timeout=30)
            self.assertEqual(list(root.iterdir()), [])
            return result

    def test_summary_cannot_report_success_for_a_refused_comparison(self):
        result = self.run_display("--summarise", compare=True)
        self.assertEqual(result.returncode, 64, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("Error: " + DIAGNOSTIC + "\n", result.stderr)

    def test_sample_cannot_report_success_for_a_refused_comparison(self):
        result = self.run_display("--sample", compare=True)
        self.assertEqual(result.returncode, 64, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("Error: " + DIAGNOSTIC + "\n", result.stderr)

    def test_empty_summary_retains_complete_original_output(self):
        result = self.run_display("--summarise")
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, "Nothing measured yet.\n", ""))


if __name__ == "__main__":
    unittest.main()
