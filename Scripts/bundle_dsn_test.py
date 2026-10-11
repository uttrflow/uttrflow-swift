#!/usr/bin/env python3
"""Exercise distribution preflight without a certificate or packaging work."""

import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


class DistributionDSNTests(unittest.TestCase):
    def run_distribution(self, value):
        environment = os.environ.copy()
        environment.pop("SENTRY_DSN", None)
        environment.pop("UTTRFLOW_SIGNING_IDENTITY", None)
        if value is not None:
            environment["SENTRY_DSN"] = value
        return subprocess.run(
            ["bash", str(Path(__file__).with_name("bundle.sh")), "distribution"],
            env=environment, capture_output=True, text=True, check=False,
        )

    def test_blank_values_stop_before_identity_or_packaging(self):
        for value in (None, "", " ", "\t", "\n", " \t\n "):
            with self.subTest(value=repr(value)):
                result = self.run_distribution(value)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("distribution mode needs a nonblank SENTRY_DSN", result.stderr)
                self.assertNotIn("Developer ID", result.stderr)

    def test_nonblank_value_reaches_identity_preflight_without_disclosure(self):
        value = "synthetic-dsn-marker"
        result = self.run_distribution(value)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("distribution mode needs a Developer ID", result.stderr)
        self.assertNotIn(value, result.stdout + result.stderr)

    def test_other_modes_keep_blank_environment_optional(self):
        gate = Path(__file__).with_name("crash_reporting_gate.py")
        for mode in ("development", "local", "rehearsal"):
            for value in ("", " \t\n "):
                with self.subTest(mode=mode, value=repr(value)):
                    environment = os.environ.copy()
                    environment["SENTRY_DSN"] = value
                    result = subprocess.run(
                        ["python3", str(gate), "environment", mode], env=environment,
                        capture_output=True, text=True, check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout + result.stderr, "")

    def test_artifact_rejects_nonstring_and_nondictionary_without_disclosure(self):
        marker = "synthetic-private-marker"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            for value in ([marker], {"SentryDSN": [marker]}, {"SentryDSN": 42}):
                with self.subTest(value=value):
                    path.write_bytes(plistlib.dumps(value))
                    result = subprocess.run(
                        ["python3", str(Path(__file__).with_name("crash_reporting_gate.py")),
                         "plist", str(path)], capture_output=True, text=True, check=False,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("the image needs a nonblank SentryDSN", result.stderr)
                    self.assertNotIn(marker, result.stdout + result.stderr)
                    self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
