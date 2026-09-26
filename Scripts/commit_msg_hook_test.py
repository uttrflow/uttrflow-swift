#!/usr/bin/env python3
"""Proves the commit-msg hook refuses a message for the reason it actually has."""

import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
HOOK = os.path.join(ROOT, ".githooks", "commit-msg")
BLAME = "text that must not be published"


def forbidden_sample():
    """A string matching a tier-1 pattern, built at run time so this file carries no such term."""
    spec = importlib.util.spec_from_file_location("audit", os.path.join(HERE, "disclosure_audit.py"))
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    for group in (audit.NAMES, audit.PHRASES):
        for pattern in group:
            candidate = re.sub(r"\\b|\(\?i\)|[\\^$]", "", pattern.pattern)
            candidate = candidate.replace("s+", " ").replace("[- ]", " ").replace("?", "")
            if pattern.search(candidate):
                return candidate
    return None


class CommitMessageHookTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp(prefix="uttrflow-commit-msg-")

    def run_hook(self, text=None, name="COMMIT_EDITMSG"):
        """Runs the hook over a message file, or over one deliberately never written."""
        path = os.path.join(self.directory, name)
        if text is not None:
            with open(path, "w") as handle:
                handle.write(text)
        return subprocess.run(
            ["bash", HOOK, path], cwd=ROOT, capture_output=True, text=True
        )

    def test_a_plain_message_is_recorded(self):
        run = self.run_hook("Add a line\n\nA body as plain as the subject.\n")
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_a_message_shaped_like_gits_own_flags_is_read_as_text(self):
        run = self.run_hook("Fix --not --remotes=origin handling\n\n--range -x --label z\n")
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_an_unreadable_file_is_not_blamed_on_the_message(self):
        run = self.run_hook(text=None, name="never-written")
        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
        self.assertIn("Could not read the message file", run.stdout)
        self.assertNotIn(BLAME, run.stdout)

    def test_a_forbidden_term_is_still_refused(self):
        sample = forbidden_sample()
        if sample is None:
            self.skipTest("no tier-1 pattern could be turned back into a sample")
        run = self.run_hook(f"Subject line\n\n{sample}\n")
        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
        self.assertIn(BLAME, run.stdout)


class RealMergeTests(unittest.TestCase):
    """Exercises the hook through an actual `git merge --no-ff`, not a bare invocation."""

    def setUp(self):
        self.repo = tempfile.mkdtemp(prefix="uttrflow-merge-hook-")
        subprocess.run(["git", "init", "-q", "-b", "main", self.repo], check=True)
        os.makedirs(os.path.join(self.repo, "Scripts"))
        for name in ("disclosure_audit.py", "disclosure_baseline.json"):
            source = os.path.join(HERE, name)
            if os.path.exists(source):
                with open(source) as handle:
                    contents = handle.read()
                with open(os.path.join(self.repo, "Scripts", name), "w") as handle:
                    handle.write(contents)
        os.makedirs(os.path.join(self.repo, ".githooks"))
        with open(HOOK) as handle:
            hook_text = handle.read()
        installed_hook = os.path.join(self.repo, ".githooks", "commit-msg")
        with open(installed_hook, "w") as handle:
            handle.write(hook_text)
        os.chmod(installed_hook, 0o755)
        self.git(["config", "core.hooksPath", ".githooks"])
        self.git(["config", "user.email", "test@example.invalid"])
        self.git(["config", "user.name", "Test"])
        self.write("README.md", "start\n")
        self.git(["add", "README.md"])
        self.git(["commit", "-q", "-m", "Start"])

    def git(self, args, check=True):
        return subprocess.run(
            ["git", *args], cwd=self.repo, capture_output=True, text=True, check=check
        )

    def write(self, name, text):
        with open(os.path.join(self.repo, name), "w") as handle:
            handle.write(text)

    def test_a_blocked_branch_name_fails_the_merge_before_it_is_created(self):
        sample = forbidden_sample()
        if sample is None:
            self.skipTest("no tier-1 pattern could be turned back into a sample")
        branch = re.sub(r"[^a-zA-Z0-9]+", "-", sample).strip("-").lower()
        self.git(["checkout", "-q", "-b", branch])
        self.write("topic.txt", "harmless\n")
        self.git(["add", "topic.txt"])
        self.git(["commit", "-q", "-m", "Add a harmless file"])
        self.git(["checkout", "-q", "main"])
        merge = self.git(["merge", "--no-ff", branch], check=False)
        self.assertNotEqual(merge.returncode, 0, merge.stdout + merge.stderr)
        log = self.git(["log", "-1", "--format=%s"])
        self.assertNotIn(branch, log.stdout)

    def test_a_safe_merge_still_commits(self):
        self.git(["checkout", "-q", "-b", "topic"])
        self.write("topic.txt", "harmless\n")
        self.git(["add", "topic.txt"])
        self.git(["commit", "-q", "-m", "Add a harmless file"])
        self.git(["checkout", "-q", "main"])
        merge = self.git(["merge", "--no-ff", "topic"], check=False)
        self.assertEqual(merge.returncode, 0, merge.stdout + merge.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=1)
