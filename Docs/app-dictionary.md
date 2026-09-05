# Personal dictionary: phonetics and learning

The numbers and reasons behind `Sources/UttrflowDictionary/DoubleMetaphone.swift`,
`LearnableWords.swift` and `Utterance.swift`.

## Why Double Metaphone and not Soundex

- Soundex copies the opening letter through untouched, so "Claude" keys as `C…` and "Klaude"
  as `K…` and the two never meet. The whole point of the index is that a recogniser which
  heard a name wrong still finds the entry. Double Metaphone codes the sound of the opening.
- Soundex truncates to four characters, which suits census surnames and collapses
  `setUserPrefs` and `PaymentSheet` into a handful of buckets. A bucket of a hundred entries
  is a scan, not a candidate list.
- Double Metaphone produces an alternate code. "Gemma" and "Gerald", "Chianti" and "chair" open
  with the same letter and not the same sound; filing under both codes and looking up under
  both costs one extra hash probe and removes the guess.

Only the English rule set is implemented. The published algorithm also carries
Slavo-Germanic, Spanish, Italian and Greek special cases keyed off guesses about a word's
origin; they change a small number of census surnames from one code to two. Leaving them out
only ever merges two keys into one, the safe direction for an index whose output is a
shortlist.

Digits, punctuation, spaces and accented letters make no sound, so `"payment sheet"` and
`"PaymentSheet"` share a code; that is what lets a spoken phrase find a camel-cased entry.

## Learning: the default is to learn nothing

A mis-heard name reinforced three times is worse than one never learnt, so every rule refuses
and a word gets in only by defeating all of them. Every learnt word is thrown away by
`PersonalDictionaryStore.removeLearned()`, which is the promise the feature is sold under.

### Seen and said

- A term must be both in the window or document title and spoken (judged by sound) in
  **three** separate dictations (`sightingsBeforeLearning`). One sighting is a coincidence;
  two is usually the same task seeing the same title; three is the same number
  `DictionaryEntry.isTrustworthy` already calls "enough to stop being an accident". Five would
  end a fortnight's project before its vocabulary is learnt.
- Never from the application name, which is on screen for every dictation in that app.
- Never from the selected text: both insertion routes write over the selection, so every word
  in it is a word the user is deleting.

### Corrected by the user

`LearnableWords.corrected(over:wrote:)` learns the replacement when: both sides are at most
`PhoneticIndex.maximumWordsPerEntry` (three) words; they are spelt differently, spaces
included, capitals alone not counting; the whole phrases sound the same; and every word of the
replacement is one `GeneralVocabulary` would not know (otherwise re-dictating "there" as
"their" would index a homophone of an ordinary word). The entry is stored without a
pronunciation, because the two spellings already sound identical.

### The sighting ledger

Held in memory only. The words in it came off the user's screen and most never become
entries; writing them to disk would keep a record of what somebody had open in a file no page
shows and no button clears. Bounded at 128 pending terms, pruned best-corroborated first then
alphabetically so two machines learn the same words in the same order. A deleted word is
refused for the rest of the run; whether a deletion should outlive a quit is an open product
decision. A reset clears both the tally and the refusals.

## Candidate budget

The candidates offered for a dictation are a function of the `Utterance` alone: at most
`maximumLength × words.count` spans, ordered least confident first so the budget is spent on
the words that needed it. A run's confidence is its minimum, so longer runs sort ahead of the
single words inside them.
