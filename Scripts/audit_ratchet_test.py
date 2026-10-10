#!/usr/bin/env python3
"""Proves the audit scripts hold: the ratchets refuse a rise, and the disclosure gate is reachable."""

import base64
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
    "layering_audit.py": ("layering_baseline.json", "import AppKit\n"),
    "closed_list_audit.py": ("closed_list_baseline.json", 'let cues: Set<String> = ["git", "npm", "yarn", "pnpm"]\n'),
}


class Workspace:
    """A throwaway tree holding one audit, its baseline and whatever Swift a test writes."""

    def __init__(self, script, baseline):
        self.root = tempfile.mkdtemp(prefix="uttrflow-ratchet-")
        self.script = script
        self.baseline_name = baseline
        os.makedirs(os.path.join(self.root, "Scripts"))
        os.makedirs(os.path.join(self.root, "Sources", "Example"))
        for name in (script, "ratchet.py"):
            shutil.copy(os.path.join(HERE, name), os.path.join(self.root, "Scripts", name))
        with open(os.path.join(self.root, "Package.swift"), "w") as handle:
            handle.write("let package = Package(name: \"Example\", targets: [])\n")
        with open(os.path.join(self.root, "Scripts", "module_layers.json"), "w") as handle:
            handle.write('{"modules": {}}\n')

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

    def test_a_new_past_tense_comment_is_refused(self):
        workspace = Workspace("comment_audit.py", "comment_baseline.json")
        self.addCleanup(workspace.close)
        workspace.write("Old.swift", "// Reads the file.\nstruct Old {}\n")
        workspace.record({})
        self.assertEqual(workspace.run("--update"), 0)
        self.assertEqual(workspace.baseline()["past_tense"], 0)
        workspace.write("Old.swift", "// This used to read the file.\nstruct Old {}\n")
        self.assertEqual(workspace.run(), 1)
        self.assertEqual(workspace.run("--update"), 1)
        self.assertEqual(workspace.baseline()["past_tense"], 0)

    def test_first_recording_takes_what_is_there(self):
        for script, workspace, violation in self.each():
            with self.subTest(script=script):
                workspace.write("New.swift", violation)
                self.assertEqual(workspace.run(), 1)
                self.assertEqual(workspace.run("--update"), 0)
                self.assertEqual(workspace.baseline()["files"], {"Sources/Example/New.swift": 1})


class ExclusionSizeTests(unittest.TestCase):
    """An oversized coverage exclusion may shrink but never grow past the size it was accepted at."""

    PATH = "Uttrflow/AppDelegate.swift"

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="uttrflow-exclusion-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.baseline = os.path.join(self.root, "exclusion_baseline.json")
        shutil.copy(os.path.join(HERE, "exclusion_baseline.json"), self.baseline)
        # Pinned to the tree as it stands, so these tests prove the rules, not whether main is in step.
        self.record(0, measured=True)

    def run_report(self, *arguments):
        return subprocess.run(
            [sys.executable, os.path.join(HERE, "coverage_report.py"), *arguments],
            cwd=os.path.dirname(HERE),
            env={**os.environ, "EXCLUSION_BASELINE": self.baseline},
            capture_output=True,
            text=True,
        )

    def recorded(self):
        with open(self.baseline) as handle:
            return json.load(handle)["files"]

    def record(self, delta, measured=False):
        """Moves the recorded size of the file by `delta`; -1 leaves the tree one line past it."""
        files = self.recorded()
        if measured:
            sources = os.path.join(os.path.dirname(HERE), "Sources")
            for path in files:
                with open(os.path.join(sources, path), encoding="utf-8") as handle:
                    files[path] = len(handle.read().splitlines())
        files[self.PATH] += delta
        with open(self.baseline, "w") as handle:
            json.dump({"total": sum(files.values()), "files": files}, handle)
        return files[self.PATH]

    def test_a_grown_exclusion_is_refused(self):
        self.record(-1)
        done = self.run_report("--check-exclusions")
        self.assertEqual(done.returncode, 1)
        self.assertIn(f"{self.PATH} is", done.stderr)

    def test_update_refuses_the_rise(self):
        was = self.record(-1)
        self.assertEqual(self.run_report("--update").returncode, 1)
        self.assertEqual(self.recorded()[self.PATH], was)

    def test_after_merge_records_the_rise(self):
        was = self.record(-1)
        self.assertEqual(self.run_report("--update", "--after-merge").returncode, 0)
        self.assertEqual(self.recorded()[self.PATH], was + 1)

    def test_a_fall_is_recorded(self):
        was = self.record(1)
        self.assertEqual(self.run_report("--update").returncode, 0)
        self.assertEqual(self.recorded()[self.PATH], was - 1)


class DisclosureRangeTests(unittest.TestCase):
    """`--range` has to accept a range that carries git's own flags, not just `A..B`.

    A branch on its first push has no remote counterpart to subtract, so pre-push asks for
    what no remote holds yet -- `<sha> --not --remotes=origin` -- rather than replaying the
    whole history of the project. That reached argparse as unrecognised arguments, it exited
    2, and the hook read a usage error as "something must not be published": every first
    push of every branch was refused, with a usage message under a notice about forbidden
    text. The gate was unreachable rather than strict.

    #1030 fixed it by quoting the range in the hook and splitting it here with `shlex`, and
    landed without tests. These are those tests. Both call shapes in this repository are
    exercised -- pre-push's flag-bearing range and the Quality workflow's `A..B` -- along
    with the proof that a real violation is still caught through this path, so the fix
    cannot be undone by a later tidy without something going red.
    """

    # Decoded at run time for the reason disclosure_audit.py gives for its own constants:
    # spelled out here, the phrase would be a violation sitting in a tracked file, and the
    # tree scan would match it on every run.
    FORBIDDEN = base64.b64decode("Z2l0aHViIHN0YXJz").decode()

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="uttrflow-disclosure-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        os.makedirs(os.path.join(self.root, "Scripts"))
        shutil.copy(
            os.path.join(HERE, "disclosure_audit.py"),
            os.path.join(self.root, "Scripts", "disclosure_audit.py"),
        )
        self.git("init", "--quiet", "--initial-branch=main")
        self.git("config", "user.email", "nobody@example.invalid")
        self.git("config", "user.name", "Audit Self Test")
        self.commit("A line of ordinary prose about dictation.\n", "Add a line")

    def git(self, *arguments):
        return subprocess.run(
            ["git", *arguments], cwd=self.root, capture_output=True, text=True, check=True
        )

    def commit(self, text, message):
        with open(os.path.join(self.root, "notes.txt"), "a") as handle:
            handle.write(text)
        self.git("add", ".")
        self.git("commit", "--quiet", "--message", message)
        return self.git("rev-parse", "HEAD").stdout.strip()

    def audit(self, *arguments):
        return subprocess.run(
            [sys.executable, os.path.join("Scripts", "disclosure_audit.py"), *arguments],
            cwd=self.root,
            capture_output=True,
            text=True,
        )

    def test_the_new_branch_form_is_accepted(self):
        head = self.git("rev-parse", "HEAD").stdout.strip()
        done = self.audit("--range", f"{head} --not --remotes=origin")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_the_two_dot_form_is_accepted(self):
        first = self.git("rev-parse", "HEAD").stdout.strip()
        second = self.commit("Another line.\n", "Add another line")
        done = self.audit("--range", f"{first}..{second}")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_an_empty_range_is_refused_rather_than_scanning_the_tree(self):
        self.assertEqual(self.audit("--range").returncode, 2)

    def test_a_forbidden_commit_message_is_still_refused(self):
        self.commit("Another line.\n", f"Chase {self.FORBIDDEN} this quarter")
        head = self.git("rev-parse", "HEAD").stdout.strip()
        self.assertEqual(self.audit("--range", f"{head} --not --remotes=origin").returncode, 1)

    def test_a_co_author_trailer_is_refused(self):
        self.commit("Another line.\n", "Add a line\n\nCo-Authored-By: Someone <someone@example.invalid>")
        head = self.git("rev-parse", "HEAD").stdout.strip()
        self.assertEqual(self.audit("--range", f"{head} --not --remotes=origin").returncode, 1)

    def test_a_forbidden_added_line_is_still_refused(self):
        self.commit(f"We should talk about {self.FORBIDDEN}.\n", "Add a line")
        head = self.git("rev-parse", "HEAD").stdout.strip()
        self.assertEqual(self.audit("--range", f"{head} --not --remotes=origin").returncode, 1)


if __name__ == "__main__":
    unittest.main(verbosity=1)
