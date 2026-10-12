"""Checks Swift nested comments without creating product wakeup sites."""

from types import SimpleNamespace
import unittest
from unittest.mock import patch

import perf_budget_audit as audit


class NestedPerfCommentTests(unittest.TestCase):
    timer = "Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in }"

    def test_nested_comment_timer_is_not_a_site(self):
        for depth in (2, 3, 6):
            with self.subTest(depth=depth):
                source = "/* " * depth + " */" * (depth - 1) + self.timer + "*/"
                self.assertEqual(list(audit.repeating_sites(audit.blanked(source))), [])

    def test_real_timer_after_comment_retains_exact_offset(self):
        source = "/* outer /* inner */ " + self.timer + " */\n" + self.timer
        self.assertEqual(list(audit.repeating_sites(audit.blanked(source))),
                         [(source.rindex(self.timer), "repeating timer", "0.1")])

    def test_mask_preserves_length_and_newlines(self):
        source = "/* outer\n/* inner */\n" + self.timer + "\n*/\nlet value = 1"
        masked = audit.blanked(source)
        self.assertEqual(len(masked), len(source))
        self.assertEqual([i for i, c in enumerate(masked) if c == "\n"],
                         [i for i, c in enumerate(source) if c == "\n"])
        self.assertEqual(masked[:source.index("let")].strip(), "")
        self.assertEqual(masked[source.index("let"):], "let value = 1")

    def test_strings_and_line_comments_do_not_open_block_comments(self):
        source = 'let a = "/* */"\nlet b = """/* outer /* inner */"""\n// /*\n' + self.timer
        self.assertEqual(list(audit.repeating_sites(audit.blanked(source))),
                         [(source.index("Timer"), "repeating timer", "0.1")])

    def test_unclosed_outer_comment_hides_remaining_source(self):
        source = "/* outer /* inner */\n" + self.timer
        self.assertEqual(list(audit.repeating_sites(audit.blanked(source))), [])

    def test_wakeup_gate_ignores_decoy_and_still_rejects_real_timer(self):
        decoy = "/* outer /* inner */ " + self.timer + " */"
        for source, expected_count in ((decoy, 0), (decoy + "\n" + self.timer, 1)):
            with self.subTest(expected_count=expected_count):
                tree = SimpleNamespace(files={"Sources/Synthetic/Timer.swift": audit.blanked(source)},
                                       constants={}, defaults={})
                findings = audit.Findings()
                with patch.dict(audit.WAKEUPS_ALLOWED, {}, clear=True), \
                        patch.dict(audit.WAKEUPS_BOUND_BY, {}, clear=True):
                    audit.check_wakeups(tree, findings, [])
                self.assertEqual(len(findings.failures), expected_count)
                if expected_count:
                    self.assertIn("repeating timer every 0.1 s, under 0.5 s", findings.failures[0])


if __name__ == "__main__":
    unittest.main()
