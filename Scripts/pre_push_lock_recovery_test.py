#!/usr/bin/env python3
"""Proves the verify-worktree lock recovers from an owner that never wrote its pid.

`mkdir` claims the lock and the pid is written on the next line, so a process killed in
that gap leaves a lock directory with no `pid` file. The recovery check only ever read
`holder` from that file, so an empty holder never matched "gone" and every later push to
main waited the full 30 minutes. These tests exercise the lock directly rather than the
whole hook, at a fast poll interval, so the grace period does not cost real minutes.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(HERE)
HOOK = os.path.join(REPO_ROOT, ".githooks", "pre-push")

# Isolates just the locking loop from the hook so a test does not need a real `make
# verify`. It mirrors the hook's lock variables and exits 0 once it holds the lock.
LOCK_RUNNER = """#!/usr/bin/env bash
set -uo pipefail
lock="$1"
git_dir="$(dirname "$lock")"
"""


def _extract_lock_loop():
    """Pulls the lock-acquisition block out of the real hook, so the test runs the
    exact code the hook runs rather than a reimplementation that could drift from it."""
    with open(HOOK) as handle:
        text = handle.read()
    start = text.index('lock="$git_dir/verify-worktree.lock"')
    end = text.index('trap \'rm -rf "$lock"\' EXIT') + len('trap \'rm -rf "$lock"\' EXIT')
    return text[start:end]


LOCK_LOOP = _extract_lock_loop()


class VerifyLockRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="uttrflow-lock-")
        self.git_dir = os.path.join(self.root, "gitdir")
        os.makedirs(self.git_dir)
        self.lock = os.path.join(self.git_dir, "verify-worktree.lock")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def _run(self, env_extra=None, timeout=15):
        script = f'git_dir={self.git_dir!r}\n' + LOCK_LOOP + '\necho "acquired pid=$$"\n'
        env = os.environ.copy()
        env["UTTRFLOW_LOCK_POLL_SECONDS"] = "0.2"
        if env_extra:
            env.update(env_extra)
        return subprocess.run(
            ["bash", "-c", script],
            cwd=self.root,
            capture_output=True,
            text=True,
            env=env,
            timeout=timeout,
        )

    def test_lock_without_pid_file_is_recovered_quickly(self):
        os.makedirs(self.lock)
        started = time.monotonic()
        result = self._run()
        elapsed = time.monotonic() - started
        self.assertEqual(
            result.returncode, 0, msg=f"stdout={result.stdout}\nstderr={result.stderr}"
        )
        self.assertIn("acquired pid=", result.stdout)
        self.assertLess(
            elapsed, 5, msg="waited far longer than the grace period for an empty lock"
        )

    def test_lock_with_dead_owner_pid_is_recovered(self):
        os.makedirs(self.lock)
        dead = subprocess.run(["bash", "-c", "echo $$"], capture_output=True, text=True)
        # The process this pid names has already exited by the time we read it back.
        with open(os.path.join(self.lock, "pid"), "w") as handle:
            handle.write(dead.stdout.strip())
        result = self._run()
        self.assertEqual(
            result.returncode, 0, msg=f"stdout={result.stdout}\nstderr={result.stderr}"
        )
        self.assertIn("clearing a lock left behind by pid", result.stdout)

    def test_lock_with_live_owner_is_not_recovered(self):
        os.makedirs(self.lock)
        holder = subprocess.Popen(["sleep", "5"])
        try:
            with open(os.path.join(self.lock, "pid"), "w") as handle:
                handle.write(str(holder.pid))
            with self.assertRaises(subprocess.TimeoutExpired):
                self._run(timeout=2)
            # The lock must still belong to the live holder: recovery did not touch it.
            self.assertTrue(os.path.isdir(self.lock))
            with open(os.path.join(self.lock, "pid")) as handle:
                self.assertEqual(handle.read(), str(holder.pid))
        finally:
            holder.kill()
            holder.wait()


if __name__ == "__main__":
    unittest.main(verbosity=1)
