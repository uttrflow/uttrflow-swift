"""Checks nested Swift comments cannot hide a real corpus edit or removal."""
import unittest

import corpus_edit_audit as audit


class NestedCorpusCommentTests(unittest.TestCase):
    case = '.init(id: "a1", category: .everyday, spoken: "hello", expected: "Hello.")'

    def decoy(self, depth):
        return "/* " * depth + "*/ " * (depth - 1) + self.case + " */"

    def test_nested_decoy_cannot_hide_an_edit(self):
        for depth in [2, 3, 6]:
            with self.subTest(depth=depth):
                head = self.decoy(depth) + self.case.replace("Hello.", "Changed.")
                self.assertEqual(audit.findings(audit.cases_in(self.case),
                                               audit.cases_in(head), set()), ["changed: a1"])

    def test_nested_decoy_cannot_hide_a_removal(self):
        self.assertEqual(audit.findings(audit.cases_in(self.case),
                                       audit.cases_in(self.decoy(3)), set()), ["removed: a1"])

    def test_nested_comments_do_not_create_cases_or_change_real_ones(self):
        for depth in [1, 2, 4]:
            with self.subTest(depth=depth):
                self.assertEqual(audit.cases_in(self.decoy(depth)), {})
                self.assertEqual(audit.cases_in(self.decoy(depth) + self.case),
                                 audit.cases_in(self.case))

    def test_comment_delimiters_inside_strings_stay_literal(self):
        for spoken in ['/* outer /* inner */ end */', '// literal', '"""/* nested */"""']:
            with self.subTest(spoken=spoken):
                text = spoken if spoken.startswith('"""') else '"' + spoken + '"'
                source = '.init(id: "a1", spoken: ' + text + ', expected: "Hello.")'
                self.assertEqual(audit.strip_comments(source), source)
                self.assertIn("a1", audit.cases_in(source))

    def test_unclosed_nested_comment_keeps_the_existing_end_of_file_behavior(self):
        source = self.case + "/* outer /* inner */ " + self.case.replace("a1", "hidden")
        self.assertEqual(audit.cases_in(source), audit.cases_in(self.case))


if __name__ == "__main__":
    unittest.main()
