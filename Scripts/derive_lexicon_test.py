#!/usr/bin/env python3
"""Proves the lexicon derivation keeps frequent words, their same-sound and distance-1 neighbours, and every alternative."""

import unittest

import derive_lexicon

SAMPLE = """affect AH0 F EH1 K T
effect IH0 F EH1 K T
effect(2) IY1 F EH0 K T
effect(3) AH0 F EH1 K T
cat K AE1 T
cad K AE1 D
cut K AH1 T
dog D AO1 G
zebra Z IY1 B R AH0
"""


class DeriveLexiconTests(unittest.TestCase):
    def setUp(self):
        self.lexicon = derive_lexicon.parse_lexicon(SAMPLE)

    def test_alternatives_merge_under_the_word(self):
        self.assertEqual(len(self.lexicon["effect"]), 3)

    def test_same_sound_through_an_alternative_is_kept(self):
        _, kept = derive_lexicon.derive(self.lexicon, {"affect": 50}, 20)
        self.assertIn("effect", kept)
        self.assertEqual(derive_lexicon.render(self.lexicon, kept).count("effect"), 3)

    def test_distance_one_neighbours_are_kept_and_others_are_not(self):
        frequent, kept = derive_lexicon.derive(self.lexicon, {"cat": 20}, 20)
        self.assertEqual(frequent, {"cat"})
        self.assertEqual(kept, {"cat", "cad", "cut"})

    def test_rare_words_alone_keep_nothing(self):
        self.assertEqual(derive_lexicon.derive(self.lexicon, {"zebra": 19}, 20), (set(), set()))

    def test_weighted_distance(self):
        self.assertEqual(derive_lexicon.distance(("K", "AE", "T"), ("K", "AH", "D")), 1.0)
        self.assertGreater(derive_lexicon.distance(("K", "AE", "T"), ("D", "AO", "G")), 1.0)


if __name__ == "__main__":
    unittest.main()
