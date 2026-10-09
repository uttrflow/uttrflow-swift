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

    def test_an_interpolated_id_is_read_whole_and_its_removal_can_be_ledgered(self):
        template = '    .init(id: "b-\\(kind.rawValue)-\\(id)", category: .everyday, spoken: s, expected: e),\n'
        base = BASE.replace("]\n", template + "]\n")
        self.assertIn("b-\\(kind.rawValue)-\\(id)", corpus_edit_audit.cases_in(base))
        removed = corpus_edit_audit.findings(
            corpus_edit_audit.cases_in(base), corpus_edit_audit.cases_in(BASE), set())
        self.assertEqual(["removed: b-\\(kind.rawValue)-\\(id)"], removed)
        ledgered = corpus_edit_audit.findings(
            corpus_edit_audit.cases_in(base), corpus_edit_audit.cases_in(BASE),
            corpus_edit_audit.ledger_ids("b-\\(kind.rawValue)-\\(id) moved to a data file\n"))
        self.assertEqual([], ledgered)

    def test_ledger_reads_first_word_and_skips_comments(self):
        self.assertEqual({"a1"}, corpus_edit_audit.ledger_ids("# header\na1 the old expectation dropped a word\n\n"))

    def test_a_second_ledger_line_for_an_id_counts_and_an_old_line_does_not(self):
        base = "# header\na1 an earlier edit\n"
        self.assertEqual({"a1"}, corpus_edit_audit.newly_ledgered_ids(base, base + "a1 a later edit\n"))
        self.assertEqual(set(), corpus_edit_audit.newly_ledgered_ids(base, base))

    def test_data_file_edit_fails_and_its_note_or_layout_passes(self):
        base = corpus_edit_audit.data_cases_in('[{"id": "d1", "spoken": "hi", "expected": "Hi."}]')
        edited = corpus_edit_audit.data_cases_in('[{"id": "d1", "spoken": "hi", "expected": "Hi!"}]')
        noted = corpus_edit_audit.data_cases_in(
            '[\n  {"expected": "Hi.", "note": "Why.", "spoken": "hi", "id": "d1"}\n]')
        self.assertEqual(["changed: d1"], corpus_edit_audit.findings(base, edited, set()))
        self.assertEqual([], corpus_edit_audit.findings(base, noted, set()))
        self.assertEqual(["removed: d1"], corpus_edit_audit.findings(base, {}, set()))

    def test_data_files_are_corpus_paths(self):
        paths = [
            "Sources/UttrflowEval/EvaluationCorpus.swift",
            "Sources/UttrflowEval/Resources/Corpus/everyday.json",
            "Sources/UttrflowEval/Resources/Other/table.json",
        ]
        self.assertEqual(paths[:2], corpus_edit_audit.corpus_paths(lambda: paths))

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


    def test_a_shallow_checkout_fetches_the_first_parent_by_id_and_retries(self):
        calls = []
        fetches = iter([1, 0])

        def run(*args, check=True):
            calls.append(args)
            if args == ("cat-file", "-p", "HEAD"):
                return types.SimpleNamespace(returncode=0, stdout="tree t\nparent base\nparent pr\n\nMerge\n")
            if args[0] == "fetch":
                return types.SimpleNamespace(returncode=next(fetches), stdout="", stderr="reset")
            return types.SimpleNamespace(returncode=1, stdout="")

        self.assertEqual("base", corpus_edit_audit.fetched_first_parent(run, pause=lambda _: None))
        self.assertIn(("fetch", "--quiet", "--no-tags", "--depth=1", "origin", "base"), calls)
        self.assertEqual(2, sum(1 for call in calls if call[0] == "fetch"))

    def test_a_commit_with_no_parent_has_no_base(self):
        def run(*args, check=True):
            return types.SimpleNamespace(returncode=0, stdout="tree t\n\nRoot\n")

        self.assertIsNone(corpus_edit_audit.fetched_first_parent(run))


if __name__ == "__main__":
    unittest.main()
