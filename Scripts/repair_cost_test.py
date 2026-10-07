#!/usr/bin/env python3
"""Checks the repair-cost model's orderings that Docs/repair-cost.md decides routes on."""

import unittest

import repair_cost as model


class RepairCostTests(unittest.TestCase):
    def setUp(self):
        self.priced = model.table()

    def test_every_route_prices_every_class(self):
        self.assertGreaterEqual(len(self.priced), 5)
        for row in self.priced.values():
            self.assertEqual(set(model.CLASSES), set(row))

    def test_redictating_everything_is_slower_than_retyping_every_class(self):
        for route in ("app undo, redictate (IN.11)", "undo last, redictate (UX.10)", "History Undo, redictate"):
            for name in model.CLASSES:
                self.assertGreater(self.priced[route][name], self.priced["retype by hand"][name])

    def test_a_spoken_fix_beats_retyping_a_lost_piece(self):
        self.assertLess(
            self.priced["replace X with Y (CM.9)"]["lost piece"], self.priced["retype by hand"]["lost piece"])

    def test_fewer_errors_is_faster(self):
        slow = model.net_words_per_minute(0.05, model.LONG_WAIT, 5.0)[0]
        fast = model.net_words_per_minute(0.01, model.LONG_WAIT, 5.0)[0]
        self.assertGreater(fast, slow)


if __name__ == "__main__":
    unittest.main()
