#!/usr/bin/env python3
"""Proves the disclosure audit reads every revision range the pre-push hook hands it."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT = os.path.join(HERE, "disclosure_audit.py")


class Repository:
    """A throwaway repository with one commit and one remote, so a range has something to name."""

    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="uttrflow-disclosure-")
        self.git("init", "--initial-branch=main")
        self.git("config", "user.email", "tests@example.com")
        self.git("config", "user.name", "Tests")
        with open(os.path.join(self.root, "README.md"), "w") as handle:
            handle.write("A line that says nothing either gate objects to.\n")
        self.git("add", "README.md")
        self.git("commit", "-m", "Add a readme")
        self.git("remote", "add", "origin", self.root)

    def git(self, *arguments):
        subprocess.run(["git", *arguments], cwd=self.root, capture_output=True, text=True)

    def head(self):
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=self.root, capture_output=True, text=True
        ).stdout.strip()

    def audit(self, named):
        return subprocess.run(
            [sys.executable, AUDIT, "--range", named], cwd=self.root, capture_output=True, text=True
        )

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


class RangeTests(unittest.TestCase):
    def setUp(self):
        self.repository = Repository()
        self.addCleanup(self.repository.close)

    def test_a_two_dot_range_is_read(self):
        run = self.repository.audit(f"{self.repository.head()}~0..{self.repository.head()}")
        self.assertEqual(run.returncode, 0, run.stderr)

    def test_a_new_branch_range_carrying_gits_own_flags_is_read(self):
        run = self.repository.audit(f"{self.repository.head()} --not --remotes=origin")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("commit(s)", run.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=1)
