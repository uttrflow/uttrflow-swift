#!/usr/bin/env python3
"""Proves the snapshot fixture audit refuses each kind of personal data and passes invented text."""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import snapshot_fixture_audit as audit

# Joined at runtime, so the tree-wide personal-data audit does not read this invented address as one.
OFF_DOMAIN = "@".join(["ana", "shop.zz"])


class FindingsTests(unittest.TestCase):
    def kinds(self, text):
        return [kind for kind, _ in audit.findings(text)]

    def test_an_address_on_a_real_domain_is_refused(self):
        self.assertEqual(self.kinds(f"write to {OFF_DOMAIN}"), ["email address"])

    def test_an_address_on_a_reserved_domain_passes(self):
        self.assertEqual(self.kinds("ana.lima@example.com and sample@remote.example.com"), [])

    def test_a_real_host_in_a_link_is_refused(self):
        self.assertEqual(self.kinds("https://mail.shop.zz/inbox"), ["host"])

    def test_a_reserved_host_or_a_file_link_passes(self):
        self.assertEqual(self.kinds("https://example.com/compose file:///Users/sample/demo/ http://box.local"), [])

    def test_a_bare_web_host_is_refused(self):
        self.assertEqual(self.kinds("see www.shop.zz today"), ["host"])

    def test_a_long_number_is_refused_with_or_without_separators(self):
        self.assertEqual(self.kinds("call 98450 12345"), ["long number"])
        self.assertEqual(self.kinds("card 4111-1111-1111-1111"), ["long number"])

    def test_a_short_number_passes(self):
        self.assertEqual(self.kinds("invoice 4417, 80×24, 2026-10-10"), [])

    def test_a_postal_address_is_refused(self):
        self.assertEqual(self.kinds("Flat 9, 12 Sample Road"), ["postal address"])

    def test_invented_text_passes(self):
        self.assertEqual(self.kinds("Untitled.txt Lorem ipsum dolor"), [])


class AuditTests(unittest.TestCase):
    def write(self, directory, name, value):
        with open(os.path.join(directory, name), "w", encoding="utf-8") as handle:
            json.dump(value, handle)

    def test_every_string_of_every_fixture_is_read(self):
        with tempfile.TemporaryDirectory() as directory:
            self.write(directory, "a.json", {"focused": {"attributes": {"AXValue": {"text": OFF_DOMAIN}}}})
            self.write(directory, "b.json", {"windowTitle": "Untitled.txt"})
            results, count = audit.audit(directory)
        self.assertEqual(count, 2)
        self.assertEqual(results, [("a.json", "email address", OFF_DOMAIN)])

    def test_the_tree_s_own_fixtures_pass(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        results, count = audit.audit(os.path.join(root, audit.FIXTURES))
        self.assertGreater(count, 0)
        self.assertEqual(results, [])


if __name__ == "__main__":
    unittest.main()
