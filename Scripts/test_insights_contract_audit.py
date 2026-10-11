"""Checks current empty-state parsing and rejects missing wording or artwork drift."""

from pathlib import Path
import unittest

import insights_contract_audit as audit


class InsightsContractTests(unittest.TestCase):
    def setUp(self):
        self.swift = Path(audit.INSIGHTS_PRESENTER_SOURCE).read_text()
        self.ranges = Path(audit.INSIGHTS_RANGE_SOURCE).read_text()
        self.days = Path(audit.INSIGHTS_DAY_SOURCE).read_text()
        self.generator = Path(audit.GEN_APP_SOURCE).read_text()

    def contract(self, swift=None):
        return audit.presenter_contract(
            self.swift if swift is None else swift, self.ranges, self.days)

    def valid_section(self):
        section = audit.insights_section(self.generator)
        section = section.replace('EMPTY_TITLE = "Not enough to chart yet"',
                                  'EMPTY_TITLE = "Nothing to chart yet"')
        section = section[:section.index("insights_empty =")]
        section = "\n".join(line for line in section.splitlines()
                            if not line.startswith(("EMPTY_MESSAGE =", "EMPTY_RETENTION_", "EMPTY_KEPT ="))) + "\n"
        return section + '''EMPTY_MESSAGE = "Charts appear after your first dictation. {kept}"
EMPTY_RETENTION_ALWAYS = "Insights count the dictations kept on this Mac."
EMPTY_RETENTION_LIMITED = "Insights count the dictations kept on this Mac, and history is kept for {retention}."
EMPTY_KEPT = EMPTY_RETENTION_ALWAYS
insights_empty = f"""<h3>{EMPTY_TITLE}</h3>
<p>{EMPTY_MESSAGE.format(kept=EMPTY_KEPT)}</p>{suggestion_insights}"""
'''

    def test_current_empty_state_has_both_retention_explanations(self):
        contract = self.contract()
        self.assertEqual(contract["empty_title"], "Nothing to chart yet")
        self.assertEqual(contract["empty_message"],
                         "Charts appear after your first dictation. {kept}")
        self.assertEqual(contract["empty_retention_always"],
                         "Insights count the dictations kept on this Mac.")
        self.assertEqual(contract["empty_retention_limited"],
                         "Insights count the dictations kept on this Mac, and history is kept for {retention}.")

    def test_missing_empty_state_values_are_rejected(self):
        for present in ('title: "Nothing to chart yet",',
                        'message: "Charts appear after your first dictation. \\(kept)",',
                        'SettingsRetention.isAlways(days: retention)'):
            with self.subTest(present=present), self.assertRaises(SystemExit):
                self.contract("".join(self.swift.rsplit(present, 1)))

    def test_unknown_interpolation_is_rejected(self):
        with self.assertRaises(SystemExit):
            self.contract('\\(other)'.join(self.swift.rsplit('\\(kept)', 1)))

    def test_matching_fixture_and_all_empty_wording_mutations(self):
        section = self.valid_section()
        screens = audit.screens_rows(self.generator)
        self.assertEqual(audit.audit_failures(section, screens, self.contract()), [])
        for old, new in (
            ('EMPTY_TITLE = "Nothing to chart yet"', 'EMPTY_TITLE = "Changed"'),
            ('Charts appear after your first dictation.', 'Charts appear after seven days.'),
            ('Insights count the dictations kept on this Mac.', 'History explanation removed.'),
            ('history is kept for {retention}.', 'history is kept forever.'),
            ('{EMPTY_MESSAGE.format(kept=EMPTY_KEPT)}', '{EMPTY_TITLE}'),
        ):
            with self.subTest(old=old):
                self.assertTrue(audit.audit_failures(
                    section.replace(old, new, 1), screens, self.contract()))

    def test_retired_waiting_period_is_rejected(self):
        section = self.valid_section() + '\nSPOKEN_SO_FAR = 2\n'
        self.assertIn("the empty state still draws the retired multi-day waiting period",
                      audit.audit_failures(section, audit.screens_rows(self.generator), self.contract()))

    def test_stale_artwork_mismatch_remains_visible(self):
        section = self.valid_section().replace('EMPTY_TITLE = "Nothing to chart yet"',
                                               'EMPTY_TITLE = "Not enough to chart yet"')
        section = section[:section.index("EMPTY_MESSAGE =")] + "insights_empty = 'Dictate on seven days {suggestion_insights}'\nSPOKEN_SO_FAR = 2"
        failures = audit.audit_failures(section, audit.screens_rows(self.generator), self.contract())
        self.assertEqual(len(failures), 6)
        self.assertIn("the empty state does not say 'Nothing to chart yet'", failures)


if __name__ == "__main__":
    unittest.main()
