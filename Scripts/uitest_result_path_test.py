#!/usr/bin/env python3
"""Proves a second `make uitest` can reach the runner without a stale result bundle in the way.

Drives Scripts/uitest_result_path.sh directly, which needs no Xcode project, no app bundle and
no windowing session — the thing it does is filesystem-only, ahead of the real xcodebuild call.
"""

import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "uitest_result_path.sh")


class ResultBundlePathTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="uttrflow-uitest-result-")
        self.addCleanup(self.tmp.cleanup)
        self.path = os.path.join(self.tmp.name, "uitest.xcresult")

    def run_script(self):
        return subprocess.run(
            [SCRIPT, self.path], capture_output=True, text=True, timeout=30
        )

    def test_a_path_with_nothing_there_is_returned_unchanged(self):
        finished = self.run_script()
        self.assertEqual(finished.returncode, 0, finished.stderr)
        self.assertEqual(finished.stdout.strip(), self.path)
        self.assertFalse(os.path.exists(self.path))

    def test_an_existing_bundle_is_moved_aside_not_deleted(self):
        os.mkdir(self.path)
        with open(os.path.join(self.path, "marker"), "w") as f:
            f.write("the first run's result")

        finished = self.run_script()

        self.assertEqual(finished.returncode, 0, finished.stderr)
        # The path handed back is the same one xcodebuild is told to write to next.
        self.assertEqual(finished.stdout.strip(), self.path)
        self.assertFalse(os.path.exists(self.path), "the old bundle is in the way of the new one")

        archived = [
            name
            for name in os.listdir(self.tmp.name)
            if name != "uitest.xcresult" and name.startswith("uitest-")
        ]
        self.assertEqual(len(archived), 1, archived)
        with open(os.path.join(self.tmp.name, archived[0], "marker")) as f:
            self.assertEqual(f.read(), "the first run's result")

    def test_two_consecutive_runs_both_reach_a_usable_destination(self):
        """The exact scenario in the issue: `make uitest` twice in a row."""
        os.mkdir(self.path)
        first = self.run_script()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertFalse(os.path.exists(self.path))

        # A second real run would write a fresh bundle at the same path before testing again.
        os.mkdir(self.path)
        second = self.run_script()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout.strip(), self.path)
        self.assertFalse(os.path.exists(self.path))

        # Both prior results survive, under distinct names.
        archived = [name for name in os.listdir(self.tmp.name) if name != "uitest.xcresult"]
        self.assertEqual(len(archived), 2, archived)

    def test_a_dangling_result_link_is_preserved_and_the_destination_can_be_created(self):
        target = os.path.join(self.tmp.name, "missing-result")
        os.symlink(target, self.path)
        finished = self.run_script()
        self.assertEqual(finished.returncode, 0, finished.stderr)
        self.assertEqual(finished.stdout, self.path + "\n")
        self.assertFalse(os.path.lexists(self.path))
        archived = os.listdir(self.tmp.name)
        self.assertEqual(len(archived), 1)
        saved = os.path.join(self.tmp.name, archived[0])
        self.assertTrue(os.path.islink(saved))
        self.assertEqual(os.readlink(saved), target)
        self.assertFalse(os.path.exists(target))
        os.mkdir(self.path)
        self.assertTrue(os.path.isdir(self.path))

    def test_dangling_archive_entries_are_preserved_and_the_suffix_advances(self):
        stamp = "20260101T000000"
        clock = os.path.join(self.tmp.name, "clock")
        os.mkdir(clock)
        date = os.path.join(clock, "date")
        with open(date, "w") as handle:
            handle.write(f"#!/bin/sh\nprintf '%s\\n' '{stamp}'\n")
        os.chmod(date, 0o700)
        base = self.path.removesuffix(".xcresult")
        prior = [f"{base}-{stamp}.xcresult", f"{base}-{stamp}-1.xcresult"]
        targets = [os.path.join(self.tmp.name, f"missing-{index}") for index in range(2)]
        for path, target in zip(prior, targets):
            os.symlink(target, path)
        os.mkdir(self.path)
        with open(os.path.join(self.path, "marker"), "w") as handle:
            handle.write("current synthetic result")
        finished = subprocess.run([SCRIPT, self.path], capture_output=True, text=True, timeout=30,
                                  env=dict(os.environ, PATH=clock + os.pathsep + os.environ["PATH"]))
        expected = f"{base}-{stamp}-2.xcresult"
        self.assertEqual(finished.returncode, 0, finished.stderr)
        self.assertEqual(finished.stdout, self.path + "\n")
        self.assertEqual(finished.stderr, f"Previous UI test result kept at {expected}\n")
        for path, target in zip(prior, targets):
            self.assertTrue(os.path.islink(path))
            self.assertEqual(os.readlink(path), target)
        with open(os.path.join(expected, "marker")) as handle:
            self.assertEqual(handle.read(), "current synthetic result")
        self.assertFalse(os.path.lexists(self.path))
        os.mkdir(self.path)
        self.assertTrue(os.path.isdir(self.path))

    def test_a_regular_result_file_is_preserved_before_the_destination_is_created(self):
        with open(self.path, "w") as handle:
            handle.write("previous synthetic result")
        finished = self.run_script()
        self.assertEqual(finished.returncode, 0, finished.stderr)
        self.assertEqual(finished.stdout, self.path + "\n")
        self.assertFalse(os.path.lexists(self.path))
        archived = os.listdir(self.tmp.name)
        self.assertEqual(len(archived), 1)
        with open(os.path.join(self.tmp.name, archived[0])) as handle:
            self.assertEqual(handle.read(), "previous synthetic result")
        os.mkdir(self.path)
        self.assertTrue(os.path.isdir(self.path))

    def test_missing_argument_is_refused(self):
        finished = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=30)
        self.assertNotEqual(finished.returncode, 0)
        self.assertIn("usage:", finished.stdout + finished.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=1)
