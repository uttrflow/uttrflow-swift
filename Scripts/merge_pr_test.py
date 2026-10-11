#!/usr/bin/env python3
"""Proves explicit squash metadata and failure boundaries using a private mock CLI."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
HEAD = "1" * 40
COMMIT = "2" * 40
# Split the forbidden trailer so the test source is not itself a prohibited message.
TRAILER = "Co-" + "authored-by: Fixture <fixture@example.com>"
MOCK = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ["MERGE_TEST_STATE"])
s = json.loads(p.read_text()); args = sys.argv[1:]; s["calls"].append(args)
if args[:2] == ["pr", "view"]:
    print(json.dumps({"state": s["state"], "isDraft": s["draft"], "baseRefName": s["base"],
                      "headRefOid": s["head"], "mergeCommit": {"oid": s["commit"]}}))
elif args[:2] == ["pr", "merge"]:
    if s["fail"] or ("--match-head-commit" in args and
       args[args.index("--match-head-commit") + 1] != s["merge_head"]):
        p.write_text(json.dumps(s)); sys.exit(1)
    s["state"] = "MERGED"
    if "--body-file" in args:
        s["message"] = args[args.index("--subject") + 1] + "\\n\\n" + Path(
            args[args.index("--body-file") + 1]).read_text()
    else: s["message"] = "Synthetic subject\\n\\n" + s["trailer"]
    if s["inject"]: s["message"] += "\\n" + s["trailer"]
elif args[0] == "api": print(json.dumps({"sha": s["api_sha"], "message": s["message"]}))
else: sys.exit(2)
p.write_text(json.dumps(s))
'''


class MergeGuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="uttrflow-merge-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = self.root / "state.json"
        self.data = dict(state="OPEN", draft=False, base="main", head=HEAD, merge_head=HEAD,
                         commit=COMMIT, api_sha=COMMIT, fail=False, inject=False,
                         trailer=TRAILER, message="", calls=[])
        self.write()
        self.body = self.root / "body.txt"
        self.body.write_text("Synthetic repair with measured focused proof.\n")
        mock = self.root / "gh"
        mock.write_text(MOCK)
        mock.chmod(0o700)
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ["PATH"],
                        MERGE_TEST_STATE=str(self.state))

    def write(self):
        self.state.write_text(json.dumps(self.data))

    def run_guard(self):
        return subprocess.run(
            [sys.executable, str(HERE / "merge_pr.py"), "123", "--repo", "fixture/repository",
             "--expected-head", HEAD, "--subject", "Synthetic repair", "--body-file", str(self.body)],
            env=self.env, capture_output=True, text=True)

    def calls(self):
        return json.loads(self.state.read_text())["calls"]

    def test_default_squash_fails_strict_gate_but_explicit_guard_passes(self):
        subprocess.run(["gh", "pr", "merge", "123", "--squash", "--admin"],
                       env=self.env, check=True, capture_output=True)
        message = json.loads(self.state.read_text())["message"]
        bad = subprocess.run([sys.executable, str(HERE / "disclosure_audit.py"), "--text"],
                             input=message, text=True, capture_output=True)
        self.assertNotEqual(bad.returncode, 0)
        self.write()
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        merged = next(c for c in self.calls() if c[:2] == ["pr", "merge"])
        for flag in ["--subject", "--body-file", "--squash", "--admin", "--match-head-commit"]:
            self.assertIn(flag, merged)
        self.assertEqual(merged[merged.index("--match-head-commit") + 1], HEAD)
        self.assertEqual(json.loads(self.state.read_text())["message"],
                         "Synthetic repair\n\n" + self.body.read_text())
        self.assertEqual(self.calls()[-1], ["api", f"repos/fixture/repository/git/commits/{COMMIT}"])

    def test_bad_body_is_rejected_before_any_cli_mutation(self):
        self.body.write_text(TRAILER)
        self.assertNotEqual(self.run_guard().returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_empty_body_and_bad_subject_fail_before_cli(self):
        self.body.write_text("")
        self.assertNotEqual(self.run_guard().returncode, 0)
        self.assertEqual(self.calls(), [])
        self.body.write_text("Synthetic body.")
        result = subprocess.run(
            [sys.executable, str(HERE / "merge_pr.py"), "123", "--repo", "fixture/repository",
             "--expected-head", HEAD, "--subject", "Synthetic\n" + TRAILER,
             "--body-file", str(self.body)], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_live_head_change_is_rejected_before_merge(self):
        self.data["head"] = "3" * 40
        self.write()
        self.assertNotEqual(self.run_guard().returncode, 0)
        self.assertEqual(len(self.calls()), 1)

    def test_non_open_draft_and_wrong_base_are_rejected(self):
        for key, value in [("state", "CLOSED"), ("draft", True), ("base", "other")]:
            with self.subTest(key=key):
                original = self.data[key]
                self.data[key] = value
                self.write()
                self.assertNotEqual(self.run_guard().returncode, 0)
                self.assertEqual(len(self.calls()), 1)
                self.data[key] = original

    def test_failed_merge_or_head_race_stops_without_post_merge_api(self):
        for key, value in [("fail", True), ("merge_head", "3" * 40)]:
            with self.subTest(key=key):
                original = self.data[key]
                self.data[key] = value
                self.write()
                self.assertNotEqual(self.run_guard().returncode, 0)
                self.assertEqual(len(self.calls()), 2)
                self.data[key] = original

    def test_bad_server_message_or_wrong_commit_cannot_report_success(self):
        for key, value in [("inject", True), ("api_sha", "3" * 40)]:
            with self.subTest(key=key):
                original = self.data[key]
                self.data[key] = value
                self.write()
                result = self.run_guard()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("post-merge verification failed", result.stderr)
                self.assertEqual(sum(c[:2] == ["pr", "merge"] for c in self.calls()), 1)
                self.data[key] = original


if __name__ == "__main__":
    unittest.main()
