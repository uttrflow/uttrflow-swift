#!/usr/bin/env python3
"""Checks the mutation probe finds each mutation it claims and refuses the main checkout."""

import os
import sys
import tempfile
import unittest

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


class ScoreTests(unittest.TestCase):
    def test_unviable_mutants_do_not_count(self):
        outcomes = [{"verdict": "killed"}, {"verdict": "survived"}, {"verdict": "unviable"}]
        self.assertEqual(mutation_probe.score(outcomes), (1, 1, 0.5))


if __name__ == "__main__":
    unittest.main()
