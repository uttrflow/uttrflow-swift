#!/usr/bin/env python3
"""Checks the corpus edit audit fails a planted edit or removal and passes an added case."""

import types
import unittest

import corpus_edit_audit

BASE = """
static let everyday: [EvaluationCase] = [
    .init(
        id: "a1", category: .everyday,
        spoken: "send it (today)",
        expected: "Send it today."
    ),
    .init(id: "a2", category: .everyday, spoken: "hi", expected: "Hi."),
]
"""


class CorpusEditAuditTests(unittest.TestCase):
    def run_audit(self, head, ledgered=frozenset()):
        return corpus_edit_audit.findings(
            corpus_edit_audit.cases_in(BASE), corpus_edit_audit.cases_in(head), set(ledgered)
        )

    def test_both_cases_are_read(self):
        self.assertEqual({"a1", "a2"}, set(corpus_edit_audit.cases_in(BASE)))

    def test_unchanged_corpus_passes(self):
        self.assertEqual([], self.run_audit(BASE))

    def test_added_case_passes(self):
        head = BASE.replace("]\n", '    .init(id: "a3", category: .everyday, spoken: "ok", expected: "OK."),\n]\n')
        self.assertEqual([], self.run_audit(head))

    def test_planted_expectation_edit_fails(self):
        self.assertEqual(["changed: a1"], self.run_audit(BASE.replace("Send it today.", "Send it today!")))

    def test_planted_input_edit_fails(self):
        self.assertEqual(["changed: a2"], self.run_audit(BASE.replace('spoken: "hi"', 'spoken: "hey"')))

    def test_removal_fails(self):
        head = BASE.replace('    .init(id: "a2", category: .everyday, spoken: "hi", expected: "Hi."),\n', "")
        self.assertEqual(["removed: a2"], self.run_audit(head))

    def test_ledgered_edit_passes(self):
        self.assertEqual([], self.run_audit(BASE.replace("Hi.", "Hi!"), {"a2"}))

    def test_comment_and_layout_changes_pass(self):
        head = BASE.replace("    .init(\n        id", "    // Contested.\n    .init(\n            id")
        self.assertEqual([], self.run_audit(head))

    def test_ledger_reads_first_word_and_skips_comments(self):
        self.assertEqual({"a1"}, corpus_edit_audit.ledger_ids("# header\na1 the old expectation dropped a word\n\n"))

    def test_head_on_origin_main_ignores_a_stale_local_main(self):
        answers = {
            ("rev-parse", "HEAD"): "head",
            ("merge-base", "HEAD", "origin/main"): "head",
            ("merge-base", "HEAD", "main"): "stale",
            ("rev-parse", "--verify", "--quiet", "HEAD^1"): "parent",
        }

        def run(*args, check=True):
            return types.SimpleNamespace(returncode=0, stdout=answers.get(args, ""))

        self.assertEqual("parent", corpus_edit_audit.resolve_base(run))


if __name__ == "__main__":
    unittest.main()
