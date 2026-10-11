#!/usr/bin/env python3
"""Proves the live-model tally counts a skipped suite as skipped, never as run."""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import live_model_tally  # noqa: E402

NAMES = ["Live one", "Live two", "Live three"]


class TallyTests(unittest.TestCase):
    def test_skipped_suite_is_not_counted_as_run(self) -> None:
        log = '➜ Suite "Live one" skipped: "needs the model"\n✔ Suite "Live two" passed after 1 seconds.\n'
        self.assertEqual(live_model_tally.tally(log, NAMES), (1, 1, ["Live three"]))

    def test_failed_suite_counts_as_run(self) -> None:
        log = '✘ Suite "Live one" failed after 1 seconds.\n'
        self.assertEqual(live_model_tally.tally(log, NAMES[:1]), (1, 0, []))

    def test_every_live_file_declares_a_suite_name(self) -> None:
        tests = live_model_tally.ROOT / "Tests"
        files = list(tests.rglob("*LiveModelTests.swift"))
        self.assertEqual(len(live_model_tally.live_suite_names(tests)), len(files))


if __name__ == "__main__":
    unittest.main()
