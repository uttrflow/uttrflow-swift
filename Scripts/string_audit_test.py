#!/usr/bin/env python3
"""Checks the string audit counts a fixed literal in a view and passes a localised one."""

import os
import tempfile
import unittest

import string_audit


class StringAuditTests(unittest.TestCase):
    def found(self, source):
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        with open(os.path.join(root.name, "View.swift"), "w") as handle:
            handle.write(source)
        return string_audit.violations(root.name)

    def test_counts_a_literal_in_each_view(self):
        for call in ('Text("Hi")', 'Button("Go") {}', 'Label("Go", systemImage: "x")', 'x.help("Hi")',
                     'x.accessibilityLabel("Hi")', 'Text(#"Hi"#)', 'Text( "Hi")'):
            with self.subTest(call=call):
                self.assertEqual(len(self.found(call + "\n")), 1)

    def test_passes_a_localised_string(self):
        self.assertEqual(self.found('Text(String(localized: "Hi", comment: "Greeting"))\n'), [])

    def test_ignores_comments_variables_and_lookalike_names(self):
        source = '// Text("Hi")\nText(title)\nRichText("Hi")\nText(verbatim: "1.0")\n'
        self.assertEqual(self.found(source), [])

    def test_counts_every_literal_on_one_line(self):
        self.assertEqual(len(self.found('HStack { Text("A"); Text("B") }\n')), 2)


if __name__ == "__main__":
    unittest.main()
