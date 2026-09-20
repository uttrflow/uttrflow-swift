#!/usr/bin/env python3
"""Proves the comment and word-match audits' --update never records a rise without --after-merge."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))

# Each audit, its baseline's name, and a line of Swift that is one violation of it.
AUDITS = {
    "comment_audit.py": ("comment_baseline.json", "// one\n// two\nstruct Example {}\n"),
    "loose_match_audit.py": ("loose_match_baseline.json", "let stem = String(word.prefix(3))\n"),
}


class Workspace:
    """A throwaway tree holding one audit, its baseline and whatever Swift a test writes."""

    def __init__(self, script, baseline):
        self.root = tempfile.mkdtemp(prefix="uttrflow-ratchet-")
        self.script = script
        self.baseline_name = baseline
        os.makedirs(os.path.join(self.root, "Scripts"))
        os.makedirs(os.path.join(self.root, "Sources", "Example"))
        shutil.copy(os.path.join(HERE, script), os.path.join(self.root, "Scripts", script))

    def write(self, name, text):
        with open(os.path.join(self.root, "Sources", "Example", name), "w") as handle:
            handle.write(text)

    def record(self, files):
        with open(self.baseline_path, "w") as handle:
            json.dump({"total": sum(files.values()), "files": files}, handle)

    @property
    def baseline_path(self):
        return os.path.join(self.root, "Scripts", self.baseline_name)

    def baseline(self):
        with open(self.baseline_path) as handle:
            return json.load(handle)

    def run(self, *arguments):
        return subprocess.run(
            [sys.executable, os.path.join("Scripts", self.script), *arguments],
            cwd=self.root,
            capture_output=True,
            text=True,
        ).returncode

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


class RatchetTests(unittest.TestCase):
    def each(self):
        for script, (baseline, violation) in AUDITS.items():
            workspace = Workspace(script, baseline)
            self.addCleanup(workspace.close)
            yield script, workspace, violation

    def test_new_file_is_refused(self):
        for script, workspace, violation in self.each():
            with self.subTest(script=script):
                workspace.record({})
                workspace.write("New.swift", violation)
                self.assertEqual(workspace.run("--update"), 1)
                self.assertEqual(workspace.baseline()["files"], {})
                self.assertEqual(workspace.run(), 1)

    def test_clean_file_that_gains_one_is_refused(self):
        for script, workspace, violation in self.each():
            with self.subTest(script=script):
                workspace.write("Old.swift", violation)
                workspace.write("Clean.swift", "struct Clean {}\n")
                workspace.record({"Sources/Example/Old.swift": 1})
                workspace.write("Clean.swift", violation)
                self.assertEqual(workspace.run("--update"), 1)
                self.assertEqual(workspace.baseline()["files"], {"Sources/Example/Old.swift": 1})

    def test_listed_file_that_rises_is_refused(self):
        for script, workspace, violation in self.each():
            with self.subTest(script=script):
                workspace.write("Old.swift", violation + "\nstruct Gap {}\n" + violation)
                workspace.record({"Sources/Example/Old.swift": 1})
                self.assertEqual(workspace.run("--update"), 1)
                self.assertEqual(workspace.baseline()["files"], {"Sources/Example/Old.swift": 1})

    def test_a_fall_is_recorded(self):
        for script, workspace, violation in self.each():
            with self.subTest(script=script):
                workspace.write("Old.swift", "struct Fixed {}\n")
                workspace.record({"Sources/Example/Old.swift": 1})
                self.assertEqual(workspace.run("--update"), 0)
                self.assertEqual(workspace.baseline()["files"], {})

    def test_after_merge_records_the_rise(self):
        for script, workspace, violation in self.each():
            with self.subTest(script=script):
                workspace.record({})
                workspace.write("New.swift", violation)
                self.assertEqual(workspace.run("--update", "--after-merge"), 0)
                self.assertEqual(workspace.baseline()["files"], {"Sources/Example/New.swift": 1})
                self.assertEqual(workspace.run(), 0)

    def test_first_recording_takes_what_is_there(self):
        for script, workspace, violation in self.each():
            with self.subTest(script=script):
                workspace.write("New.swift", violation)
                self.assertEqual(workspace.run(), 1)
                self.assertEqual(workspace.run("--update"), 0)
                self.assertEqual(workspace.baseline()["files"], {"Sources/Example/New.swift": 1})


if __name__ == "__main__":
    unittest.main(verbosity=1)
