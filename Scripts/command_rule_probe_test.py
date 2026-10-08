#!/usr/bin/env python3
"""Checks the command-rule probe counts the corpus the way Docs/commands.md reports it."""

import unittest

import command_rule_probe as probe


class CommandRuleProbeTests(unittest.TestCase):
    def setUp(self):
        self.cases = probe.build_corpus()
        self.result = probe.measure(self.cases)

    def test_corpus_has_three_hundred_cases(self):
        self.assertEqual(300, len(self.cases))

    def test_whole_utterance_fires_on_content_said_alone(self):
        case = {"intent": "content", "kind": "content-alone", "mode": "hold", "command": "delete that", "pieces": ["delete that"]}
        self.assertTrue(probe.fires(case, "whole-utterance"))

    def test_whole_utterance_misses_a_second_piece_of_one_hold(self):
        case = {"intent": "command", "kind": "x", "mode": "hold", "command": "scratch that", "pieces": [probe.LEAD, "scratch that"]}
        self.assertFalse(probe.fires(case, "whole-utterance"))
        self.assertTrue(probe.fires(case, "whole-piece"))

    def test_prefix_ignores_the_phrase_inside_prose(self):
        case = {"intent": "content", "kind": "embedded", "mode": "hold", "command": "delete that", "pieces": ["i told him to delete that file"]}
        self.assertFalse(probe.fires(case, "prefix"))

    def test_reported_counts(self):
        counts = {rule: (r["false"], r["missed"]) for rule, r in self.result.items()}
        self.assertEqual({"whole-utterance": (18, 30), "whole-piece": (24, 12), "key": (0, 0), "prefix": (0, 12)}, counts)


if __name__ == "__main__":
    unittest.main()
