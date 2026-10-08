#!/usr/bin/env python3
"""Checks the word-split audit counts a hand-written split and passes what is not one."""

import os
import tempfile
import unittest

import word_split_audit


class WordSplitShapeTests(unittest.TestCase):
    def findings(self, source):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".swift", delete=False) as file:
            file.write(source)
            path = file.name
        self.addCleanup(lambda: os.unlink(path))
        return [line for line, _ in word_split_audit.findings_in(path)]

    def test_labelled_separator_is_counted(self):
        self.assertEqual([1], self.findings("let w = text.split(whereSeparator: \\.isWhitespace)\n"))

    def test_trailing_closure_is_counted(self):
        self.assertEqual([2], self.findings("let a = 1\nlet w = text.split { $0 == \" \" }\n"))

    def test_fixed_separator_is_not_counted(self):
        self.assertEqual([], self.findings("let parts = line.split(separator: \",\")\n"))

    def test_split_in_a_comment_is_not_counted(self):
        self.assertEqual([], self.findings("// text.split(whereSeparator: \\.isWhitespace)\n"))

    def test_the_seam_is_not_surveyed(self):
        self.assertEqual("WordTokens.swift", word_split_audit.SEAM)


if __name__ == "__main__":
    unittest.main()
