#!/usr/bin/env python3
"""Checks the mutation probe finds each mutation it claims and refuses the main checkout."""

import os
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import mutation_probe


class MutantTests(unittest.TestCase):
    def kinds(self, source):
        return [(item[0], item[3], item[4]) for item in mutation_probe.mutants([source])]

    def test_flips_a_spaced_comparison_but_not_a_generic_or_arrow(self):
        found = self.kinds("func f<T>(x: Int) -> Bool { x >= 2 }\n")
        self.assertIn(("comparison", ">=", "<"), found)
        self.assertEqual([item for item in found if item[0] == "comparison"], [("comparison", ">=", "<")])

    def test_swaps_logical_operators(self):
        self.assertIn(("logical", "&&", "||"), self.kinds("if a && b {}\n"))

    def test_shifts_a_literal_both_ways_and_never_below_zero(self):
        found = self.kinds("let limit = 0\nlet growth = 2.0\n")
        self.assertIn(("literal", "0", "1"), found)
        self.assertNotIn(("literal", "0", "-1"), found)

    def test_leaves_a_closure_parameter_alone(self):
        found = self.kinds("let n = xs.filter { $0 > 0 }.count\n")
        self.assertEqual(found, [("comparison", ">", "<="), ("literal", "0", "1")])

    def test_ignores_strings_and_comments(self):
        self.assertEqual(self.kinds('let text = "a < b && 3" // x == 4\n'), [])

    def test_rejection_becomes_acceptance_and_keeps_the_closing_brace(self):
        lines = ["    else { return .rejected(reason: reason, kind: kind) }\n"]
        mutant = next(item for item in mutation_probe.mutants(lines) if item[0] == "rejection")
        self.assertEqual(mutation_probe.apply(lines, mutant), ["    else { return .accepted }\n"])

    def test_a_rejection_spread_over_lines_is_not_applied(self):
        lines = ["return .rejected(\n", "    reason: reason, kind: kind)\n"]
        mutant = next(item for item in mutation_probe.mutants(lines) if item[0] == "rejection")
        self.assertIsNone(mutation_probe.apply(lines, mutant))


class WorktreeTests(unittest.TestCase):
    def test_refuses_a_directory_that_is_not_a_linked_worktree(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(SystemExit):
                mutation_probe.refuse_outside_worktree(directory)


class PoolProbeTests(unittest.TestCase):
    def arguments(self):
        return SimpleNamespace(file="Guard.swift", filter="GuardTests", ref="HEAD", limit=0,
                               timeout=30, report=None, build_runner="/tools/pool-build")

    def test_the_report_cannot_overwrite_the_source(self):
        with tempfile.TemporaryDirectory() as directory:
            arguments = self.arguments()
            arguments.report = os.path.join(directory, "Guard.swift")
            with patch("mutation_probe.os.getcwd", return_value=directory), \
                 patch("mutation_probe.refuse_outside_worktree"), \
                 patch("mutation_probe.require_runner"), patch("mutation_probe.run") as run:
                with self.assertRaises(SystemExit):
                    mutation_probe.probe(arguments)
            run.assert_not_called()

    def test_restores_source_after_an_interrupted_test(self):
        with tempfile.TemporaryDirectory() as directory:
            target = os.path.join(directory, "Guard.swift")
            original = "let limit = 2\n"
            with open(target, "w") as file:
                file.write(original)
            with patch("mutation_probe.os.getcwd", return_value=directory), \
                 patch("mutation_probe.refuse_outside_worktree"), \
                 patch("mutation_probe.require_clean_target"), \
                 patch("mutation_probe.require_runner"), \
                 patch("mutation_probe.run", side_effect=[0, 0, 0, KeyboardInterrupt]):
                with self.assertRaises(KeyboardInterrupt):
                    mutation_probe.probe(self.arguments())
            with open(target) as file:
                self.assertEqual(file.read(), original)

    def test_routes_builds_and_tests_through_the_runner_in_the_owned_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, "Guard.swift"), "w") as file:
                file.write("let limit = 0\n")
            with patch("mutation_probe.os.getcwd", return_value=directory), \
                 patch("mutation_probe.refuse_outside_worktree"), \
                 patch("mutation_probe.require_clean_target"), \
                 patch("mutation_probe.require_runner"), \
                 patch("mutation_probe.run", return_value=0) as run:
                outcomes = mutation_probe.probe(self.arguments())
            self.assertEqual(len(outcomes), 1)
            self.assertTrue(all(call.args[1] == directory for call in run.call_args_list))
            self.assertEqual(run.call_args_list[0].args[0],
                             ["/tools/pool-build", "build", "--jobs", "4", "--build-tests",
                              "--enable-code-coverage"])
            self.assertEqual(run.call_args_list[1].args[0],
                             ["/tools/pool-build", "test", "--jobs", "4", "--skip-build",
                              "--enable-code-coverage",
                              "--filter", "GuardTests"])

    def test_a_timeout_cannot_be_reported_as_a_killed_mutant(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, "Guard.swift"), "w") as file:
                file.write("let limit = 0\n")
            with patch("mutation_probe.os.getcwd", return_value=directory), \
                 patch("mutation_probe.refuse_outside_worktree"), \
                 patch("mutation_probe.require_clean_target", create=True), \
                 patch("mutation_probe.require_runner", create=True), \
                 patch("mutation_probe.tempfile.mkdtemp", return_value=directory), \
                 patch("mutation_probe.tempfile.gettempdir", return_value=directory), \
                 patch("mutation_probe.subprocess.run"), \
                 patch("mutation_probe.shutil.rmtree"), \
                 patch("mutation_probe.run", side_effect=[0, 0, 0, None]):
                with self.assertRaises(SystemExit):
                    mutation_probe.probe(self.arguments())


class SafetyTests(unittest.TestCase):
    def test_refuses_a_runner_that_is_not_an_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(SystemExit):
                mutation_probe.require_runner(os.path.join(directory, "missing-wrapper"))

    def test_refuses_a_target_outside_the_worktree(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(SystemExit):
                mutation_probe.require_clean_target(
                    directory, os.path.join(directory, "..", "Guard.swift"), "HEAD")

    def test_refuses_a_symlink_before_running_git(self):
        with tempfile.TemporaryDirectory() as directory:
            target = os.path.join(directory, "Guard.swift")
            os.symlink("elsewhere.swift", target)
            with self.assertRaises(SystemExit):
                mutation_probe.require_clean_target(directory, target, "HEAD")

    def test_refuses_a_modified_tracked_source(self):
        with tempfile.TemporaryDirectory() as directory:
            target = os.path.join(directory, "Guard.swift")
            with open(target, "w") as file:
                file.write("let limit = 0\n")
            answers = [SimpleNamespace(stdout=" M Guard.swift\n"),
                       SimpleNamespace(stdout=b"let limit = 0\n")]
            with patch("mutation_probe.subprocess.run", side_effect=answers):
                with self.assertRaises(SystemExit):
                    mutation_probe.require_clean_target(directory, target, "HEAD")

    def test_only_a_failed_swift_testing_run_proves_a_kill(self):
        with tempfile.NamedTemporaryFile(mode="w+", suffix=".log") as file:
            file.write("$ old command\nTest run with 2 tests failed\n$ latest command\nerror: fatalError\n")
            file.flush()
            self.assertFalse(mutation_probe.assertion_failure(file.name))
            file.write("Test run with 4 tests failed after 0.1 seconds with 1 issue.\n")
            file.flush()
            self.assertTrue(mutation_probe.assertion_failure(file.name))


class PartialRunTests(unittest.TestCase):
    def test_a_partial_run_cannot_record_a_floor(self):
        arguments = ["mutation_probe.py", "Guard.swift", "--filter", "GuardTests", "--limit", "1",
                     "--update-baseline", "--build-runner", "/tools/build-wrapper"]
        with patch("mutation_probe.sys.argv", arguments), patch("mutation_probe.probe") as probe:
            with self.assertRaises(SystemExit) as failure:
                mutation_probe.main()
        self.assertEqual(failure.exception.code, 2)
        probe.assert_not_called()


class ScoreTests(unittest.TestCase):
    def test_unviable_mutants_do_not_count(self):
        outcomes = [{"verdict": "killed"}, {"verdict": "survived"}, {"verdict": "unviable"}]
        self.assertEqual(mutation_probe.score(outcomes), (1, 1, 0.5))


if __name__ == "__main__":
    unittest.main()
