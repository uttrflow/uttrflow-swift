#!/usr/bin/env python3
"""Checks the duplicate-table audit finds a planted copy, passes distinct tables, and refuses a new copy."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

import duplicate_table_audit

HERE = os.path.dirname(os.path.abspath(__file__))
DIGITS = '["one", "two", "three", "four", "five", "six", "seven"]'


class DuplicateTableTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="uttrflow-duplicate-")
        self.addCleanup(shutil.rmtree, self.root, True)
        os.makedirs(os.path.join(self.root, "Scripts"))
        os.makedirs(os.path.join(self.root, "Sources", "Example"))
        for name in ("duplicate_table_audit.py", "closed_list_audit.py", "ratchet.py"):
            shutil.copy(os.path.join(HERE, name), os.path.join(self.root, "Scripts", name))

    def write(self, name, text):
        path = os.path.join(self.root, "Sources", "Example", name)
        with open(path, "w") as handle:
            handle.write(text)
        return path

    def pairs(self, *paths):
        return duplicate_table_audit.survey(list(paths))[1]

    def run_audit(self, *arguments):
        return subprocess.run(
            [sys.executable, os.path.join("Scripts", "duplicate_table_audit.py"), *arguments],
            cwd=self.root,
            capture_output=True,
            text=True,
        )

    def test_planted_copy_in_another_file_is_a_pair(self):
        first = self.write("A.swift", f"let words: Set<String> = {DIGITS}\n")
        second = self.write("B.swift", 'let numbers = ["one", "two", "three", "four", "five", "nine"]\n')
        self.assertEqual(1, len(self.pairs(first, second)))

    def test_dictionary_keys_are_compared(self):
        first = self.write("A.swift", f"let words = {DIGITS}\n")
        second = self.write("B.swift", 'let values = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6]\n')
        third = self.write("C.swift", 'let values = ["one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6"]\n')
        self.assertEqual(1, len(self.pairs(first, second)))
        self.assertEqual(1, len(self.pairs(first, third)))

    def test_distinct_tables_are_not_a_pair(self):
        first = self.write("A.swift", f"let words = {DIGITS}\n")
        second = self.write("B.swift", 'let days = ["monday", "tuesday", "wednesday", "thursday", "one", "two"]\n')
        self.assertEqual([], self.pairs(first, second))

    def test_narrow_tables_are_not_compared(self):
        first = self.write("A.swift", 'let a = ["one", "two", "three", "four", "five"]\n')
        second = self.write("B.swift", 'let b = ["one", "two", "three", "four", "five"]\n')
        self.assertEqual([], self.pairs(first, second))

    def test_copies_in_one_file_are_not_a_pair(self):
        only = self.write("A.swift", f"let a = {DIGITS}\nlet b = {DIGITS}\n")
        self.assertEqual([], self.pairs(only))

    def test_member_holding_a_comma_is_read(self):
        first = self.write("A.swift", 'let marks = [".", ",", "!", "?", ":", ";"]\n')
        second = self.write("B.swift", 'let stops = [".", ",", "!", "?", ":", ";", "-"]\n')
        self.assertEqual(1, len(self.pairs(first, second)))

    def test_new_copy_fails_and_names_the_home(self):
        self.write("A.swift", f"let words = {DIGITS}\n")
        self.assertEqual(0, self.run_audit("--update").returncode)
        self.write("B.swift", f"let copy = {DIGITS}\n")
        result = self.run_audit()
        self.assertEqual(1, result.returncode)
        self.assertIn("Sources/Example/A.swift:1", result.stdout)
        self.assertEqual(1, self.run_audit("--update").returncode)

    def test_a_fall_is_recorded(self):
        self.write("A.swift", f"let words = {DIGITS}\n")
        self.write("B.swift", f"let copy = {DIGITS}\n")
        self.assertEqual(0, self.run_audit("--update").returncode)
        os.unlink(os.path.join(self.root, "Sources", "Example", "B.swift"))
        self.assertEqual(0, self.run_audit().returncode)
        self.assertEqual(0, self.run_audit("--update").returncode)
        with open(os.path.join(self.root, "Scripts", "duplicate_table_baseline.json")) as handle:
            self.assertEqual({}, json.load(handle)["files"])


if __name__ == "__main__":
    unittest.main()
