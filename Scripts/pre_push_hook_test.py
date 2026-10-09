#!/usr/bin/env python3
"""Proves the pre-push hook resolves its companion disclosure audit by the hook's location.

`core.hooksPath` is a single absolute path for the whole repository, so every worktree
runs the same hook, and the script the hook shells out to — `Scripts/disclosure_audit.py`
— is on a relative path that, written as the obvious thing, resolves inside the worktree
the push is coming from. The hook and the script are therefore two halves of one gate that
travel on different commits whenever the main checkout is not on the worktree's commit.

That was the bug: a worktree with a cleaner / differently-shaped script could disagree
with the main checkout's, and the hook saw only the worktree's. The reporter hit it on a
push that argparse refused with "unrecognized arguments", which the hook then printed as
"A commit message or an added line carries text that must not be published" — for text
that was clean. The fix is to find the script beside the hook, not beside the push.
"""

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(HERE)
HOOK = os.path.join(REPO_ROOT, ".githooks", "pre-push")


SCRIPT_THAT_RUNS = """#!/usr/bin/env python3
import os, sys
log = os.environ.get("UTTRFLOW_AUDIT_INVOCATION_LOG")
if log:
    with open(log, "a") as f:
        f.write("MAIN " + sys.argv[0] + "\\n")
sys.exit(0)
"""

SCRIPT_THAT_LIES = """#!/usr/bin/env python3
import os, sys
log = os.environ.get("UTTRFLOW_AUDIT_INVOCATION_LOG")
if log:
    with open(log, "a") as f:
        f.write("WORKTREE " + sys.argv[0] + "\\n")
sys.exit(0)
"""


def _write_executable(path, body):
    """Writes `body` to `path` and marks it executable, the same shape `make hooks` leaves."""
    with open(path, "w") as handle:
        handle.write(body)
    current = os.stat(path).st_mode
    os.chmod(path, current | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


class HookPairsWithItsOwnAuditTests(unittest.TestCase):
    """The hook and the script it calls have to travel as a pair."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="uttrflow-hook-pair-")

        self.main = os.path.join(self.root, "main")
        os.makedirs(os.path.join(self.main, ".githooks"))
        os.makedirs(os.path.join(self.main, "Scripts"))
        shutil.copy(HOOK, os.path.join(self.main, ".githooks", "pre-push"))
        _write_executable(
            os.path.join(self.main, "Scripts", "disclosure_audit.py"), SCRIPT_THAT_RUNS
        )

        self.worktree = os.path.join(self.root, "worktree")
        os.makedirs(os.path.join(self.worktree, "Scripts"))
        _write_executable(
            os.path.join(self.worktree, "Scripts", "disclosure_audit.py"), SCRIPT_THAT_LIES
        )

        self._git("init", "--quiet", "--initial-branch=main")
        self._git("config", "user.email", "hook-pair@example.invalid")
        self._git("config", "user.name", "Hook Pair Test")
        with open(os.path.join(self.worktree, "README.md"), "w") as handle:
            handle.write("hello\n")
        self._git("add", "README.md")
        self._git("commit", "--quiet", "-m", "init")
        self.sha = self._head()

        # The whole point: core.hooksPath points at the main checkout's hook dir.
        self._git("config", "core.hooksPath", os.path.join(self.main, ".githooks"))

        self.invocation_log = os.path.join(self.root, "invocations.txt")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def _git(self, *args):
        subprocess.run(
            ["git", *args], cwd=self.worktree, check=True, capture_output=True, text=True
        )

    def _head(self):
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=self.worktree, capture_output=True, text=True
        ).stdout.strip()

    def _run_hook(self):
        zero = "0" * 40
        # Pushing a *new* feature branch, not main, so the hook runs the disclosure gate but
        # does not go on to a `make verify` that would need the whole toolchain to fake.
        stdin = f"refs/heads/feature {self.sha} refs/heads/feature {zero}\n"
        env = os.environ.copy()
        env["UTTRFLOW_AUDIT_INVOCATION_LOG"] = self.invocation_log
        return subprocess.run(
            [os.path.join(self.main, ".githooks", "pre-push")],
            cwd=self.worktree,
            input=stdin,
            capture_output=True,
            text=True,
            env=env,
        )

    def _read_invocations(self):
        try:
            with open(self.invocation_log) as handle:
                return [line.strip() for line in handle if line.strip()]
        except FileNotFoundError:
            return []

    def test_hook_invokes_the_script_paired_with_the_hook(self):
        result = self._run_hook()
        invocations = self._read_invocations()
        self.assertEqual(
            result.returncode,
            0,
            msg=(
                f"hook exited {result.returncode}\n"
                f"--- stdout ---\n{result.stdout}\n"
                f"--- stderr ---\n{result.stderr}"
            ),
        )
        self.assertTrue(
            any(line.startswith("MAIN ") for line in invocations),
            msg=(
                "main audit was not invoked; the hook resolved Scripts/ relative to cwd\n"
                f"--- stdout ---\n{result.stdout}\n"
                f"--- stderr ---\n{result.stderr}\n"
                f"--- invocations ---\n{invocations}"
            ),
        )
        self.assertFalse(
            any(line.startswith("WORKTREE ") for line in invocations),
            msg=(
                "worktree audit was invoked; hook resolved Scripts/ relative to cwd\n"
                f"--- stdout ---\n{result.stdout}\n"
                f"--- stderr ---\n{result.stderr}\n"
                f"--- invocations ---\n{invocations}"
            ),
        )

    def test_hook_does_not_publish_disclosure_refusal_for_an_invocation_error(self):
        """A gate that cannot run is not a gate that found something.

        Both audits print a usage error and exit 2. After the paired-script fix, the hook
        sees the failure from the main checkout's script, not the worktree's; the message
        it prints to the user must say the script could not be run, not that the branch
        carried text that must not be published.
        """
        failing = (
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "print('usage: disclosure_audit.py [--range RANGE]', file=sys.stderr)\n"
            "print('disclosure_audit.py: error: unrecognized arguments', file=sys.stderr)\n"
            "sys.exit(2)\n"
        )
        _write_executable(
            os.path.join(self.main, "Scripts", "disclosure_audit.py"), failing
        )
        _write_executable(
            os.path.join(self.worktree, "Scripts", "disclosure_audit.py"), failing
        )

        result = self._run_hook()
        self.assertNotEqual(
            result.returncode,
            0,
            msg="hook accepted a script that returned 2; expected a hard failure",
        )
        # The misleading line is word-wrapped: "must not be\n  published". Collapse
        # any whitespace between words so it still matches across the wrap.
        import re
        flattened = re.sub(r"\s+", " ", result.stdout + result.stderr)
        self.assertNotIn(
            "must not be published",
            flattened,
            msg=(
                "hook printed the disclosure refusal for an invocation error\n"
                f"--- stdout ---\n{result.stdout}\n"
                f"--- stderr ---\n{result.stderr}"
            ),
        )


class HookScansOnlyUnpublishedCommitsTests(unittest.TestCase):
    """A branch that merges main must not be refused for commits main already published."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="uttrflow-hook-range-")
        self.remote = os.path.join(self.root, "remote.git")
        self.clone = os.path.join(self.root, "clone")
        os.makedirs(os.path.join(self.root, "hooks", ".githooks"))
        os.makedirs(os.path.join(self.root, "hooks", "Scripts"))
        self.hook = os.path.join(self.root, "hooks", ".githooks", "pre-push")
        shutil.copy(HOOK, self.hook)
        # A stand-in audit that refuses any commit whose message says REFUSED.
        _write_executable(
            os.path.join(self.root, "hooks", "Scripts", "disclosure_audit.py"),
            "#!/usr/bin/env python3\n"
            "import shlex, subprocess, sys\n"
            "revs = shlex.split(sys.argv[sys.argv.index('--range') + 1])\n"
            "out = subprocess.run(['git', 'log', '--format=%B', *revs],"
            " capture_output=True, text=True, check=True).stdout\n"
            "sys.exit(1 if 'REFUSED' in out else 0)\n",
        )
        subprocess.run(["git", "init", "--quiet", "--bare", self.remote], check=True)
        subprocess.run(["git", "clone", "--quiet", self.remote, self.clone], check=True,
                       capture_output=True)
        self._git("config", "user.email", "hook-range@example.invalid")
        self._git("config", "user.name", "Hook Range Test")
        self._git("checkout", "--quiet", "-b", "main")
        self._commit("init")
        self._git("push", "--quiet", "origin", "main")
        self._git("checkout", "--quiet", "-b", "feature")
        self._commit("feature work")
        self._git("push", "--quiet", "origin", "feature")
        self.feature_remote_sha = self._sha("HEAD")
        # main gains a commit the stand-in audit refuses, and it is published.
        self._git("checkout", "--quiet", "main")
        self._commit("REFUSED but already on main")
        self._git("push", "--quiet", "origin", "main")
        self._git("checkout", "--quiet", "feature")
        self._git("merge", "--quiet", "--no-edit", "origin/main")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def _git(self, *args):
        subprocess.run(["git", *args], cwd=self.clone, check=True, capture_output=True)

    def _sha(self, rev):
        return subprocess.run(["git", "rev-parse", rev], cwd=self.clone, check=True,
                              capture_output=True, text=True).stdout.strip()

    def _commit(self, message):
        self._git("commit", "--quiet", "--allow-empty", "-m", message)

    def _run_hook(self):
        stdin = (f"refs/heads/feature {self._sha('HEAD')} refs/heads/feature "
                 f"{self.feature_remote_sha}\n")
        return subprocess.run([self.hook, "origin"], cwd=self.clone, input=stdin,
                              capture_output=True, text=True)

    def test_merge_of_main_is_not_refused_for_main_commits(self):
        result = self._run_hook()
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def test_new_commit_on_the_branch_is_still_refused(self):
        self._commit("REFUSED and new on the branch")
        result = self._run_hook()
        self.assertNotEqual(result.returncode, 0, msg=result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=1)
