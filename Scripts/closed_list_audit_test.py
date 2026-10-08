#!/usr/bin/env python3
"""Checks the closed-list audit recognises a word list and passes what is not one."""

import os
import tempfile
import unittest

import closed_list_audit


class ClosedListShapeTests(unittest.TestCase):
    def findings(self, source):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".swift", delete=False) as file:
            file.write(source)
            path = file.name
        self.addCleanup(lambda: os.unlink(path))
        return list(closed_list_audit.findings_in(path))

    def test_four_word_set_is_counted(self):
        found = self.findings('static let cues: Set<String> = ["git", "npm", "yarn", "pnpm"]\n')
        self.assertEqual([(1, 4)], [(line, size) for line, size, _ in found])

    def test_list_across_lines_is_counted_at_its_opening_line(self):
        source = 'let a = 1\nlet pairs = [\n    "could", "finish",\n    "pick up", "look",\n]\n'
        found = self.findings(source)
        self.assertEqual([(2, 4)], [(line, size) for line, size, _ in found])

    def test_three_words_are_a_marker_not_a_list(self):
        self.assertEqual([], self.findings('let marks = ["and", "but", "so"]\n'))

    def test_list_with_a_non_word_is_not_counted(self):
        self.assertEqual([], self.findings('let parts = ["a", "b", "c", "-"]\n'))

    def test_list_with_a_non_literal_is_not_counted(self):
        self.assertEqual([], self.findings('let parts = ["a", "b", "c", name]\n'))

    def test_list_in_a_comment_is_not_counted(self):
        source = '// ["git", "npm", "yarn", "pnpm"]\n/* ["git", "npm", "yarn", "pnpm"] */\n'
        self.assertEqual([], self.findings(source))

    def test_comment_marker_inside_a_string_does_not_hide_the_next_list(self):
        source = 'let url = "https://example.com"\nlet cues = ["git", "npm", "yarn", "pnpm"]\n'
        self.assertEqual([2], [line for line, _, _ in self.findings(source)])


if __name__ == "__main__":
    unittest.main()
