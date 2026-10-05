# Personal dictionary: phonetics and learning

The personal dictionary holds the names and terms a user says that a general recogniser
would not spell right. This page is its phonetic index and what it learns on its own:
`Sources/UttrflowDictionary/DoubleMetaphone.swift`, `PronunciationCoder.swift`,
`PhoneticIndex.swift`, `LearnableWords.swift`, `GeneralVocabulary.swift` and `Utterance.swift`.
How entries are stored and reset is `Docs/app-dictionary-store.md`; how they correct a
dictation is `Docs/ai-correction-thresholds.md`.

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

## Scripts an entry matches in

A Latin entry and a Devanagari spelling of the same word meet: `PronunciationCoder.keys`
also codes a Devanagari spelling's romanisation, so "Raghunath" is found whichever script
recognition wrote it in. Devanagari spelling variants — chandrabindu against anusvara, a
nukta letter against its base consonant — are folded to one key before that romanisation, so
पहुँच and पहुंच meet the same entry. A correction learnt across scripts is stored under its
Latin spelling, since dictation output is romanised (`Docs/latin-output.md`). Two spellings
that romanise to different Latin text (transliteration, not the writer's own spelling choice)
key apart.

## Learning: the default is to learn nothing

A mis-heard name reinforced three times is worse than one never learnt, so every rule refuses
and a word gets in only by defeating all of them. Every learnt word is thrown away by
`PersonalDictionaryStore.removeLearned()`, which is the promise the feature is sold under.

### Seen and said

- A term must be both in the window or document title and spoken — judged by sound **and by
  opening letters**, through `ReadingRestraint`, so two words that merely share a sound key do
  not meet — in **three** separate dictations (`sightingsBeforeLearning`). One sighting is a coincidence;
  two is usually the same task seeing the same title; three is the same number
  `DictionaryEntry.isTrustworthy` already calls "enough to stop being an accident". Five would
  end a fortnight's project before its vocabulary is learnt. The restraint binds what may be
  *learnt* here, never what a learnt word may later be offered for: a spelling the user taught is
  evidence in its own right, and `DictionaryCandidates` asks no restraint of it — see the
  doubtful-words row of `Docs/cleanup.md`.
- Only a term worth learning: at least three characters (`shortestWorthLearning`), not a word
  `GeneralVocabulary` knows, not spelt the same as what was heard, holding no digit, and not an
  all-capitals abbreviation of two to five letters. A trailing version number is cut off a title
  word first, so numbered files share one spelling. At most `WorkingSet.maximumWordsOnScreen`
  (64) title words are read.
- Never from the application name, which is on screen for every dictation in that app.
- Never from the selected text: both insertion routes write over the selection, so every word
  in it is a word the user is deleting.

### Corrected by the user

`LearnableWords.corrected(over:wrote:)` learns the replacement when: both sides are at most
`PhoneticIndex.maximumWordsPerEntry` (three) words; they are spelt differently, capitals
alone not counting; the whole phrases sound the same and open alike (`ReadingRestraint`),
read through their romanisation when either side is Devanagari; and every word of the
replacement is one `GeneralVocabulary` would not know (otherwise re-dictating "there" as
"their" would index a homophone of an ordinary word). The one exception is a spelling
preference: when each replacement word and the word it replaces are both listed romanised Hindi
and share `Romaniser.soundKey` ("thik" to "theek"), the user's spelling is learnt. The entry is stored without a
pronunciation, because the two spellings already sound identical.

"A word a general model already knows" is `GeneralVocabulary`: a fixed list of common
English and of romanised Hindi and Hinglish, not `NSSpellChecker`. The system checker is
main-actor UI framework, answers differently with what is installed, and has no view on
Hinglish, so every Hinglish word would read as new and the dictionary would fill with
`nahi` and `matlab`.

### The sighting ledger

`SightingLedger` holds the pending tally in memory only. The words in it came off the user's
screen and most never become entries; writing them to disk would keep a record of what
somebody had open in a file no page shows and no button clears. Bounded at 128 pending terms
(`maximumPending`), pruned best-corroborated first then alphabetically so two machines learn
the same words in the same order.

A word the user deletes is refused: it and anything that sounds like it stop being counted.
The refusals are words the user already had and removed, not terms read off the screen, so
the store writes them down and a relaunch still refuses them; at most 512 are kept
(`maximumRefused`), the oldest lapsing first. Removing learnt words clears the pending tally
and keeps the refusals; removing everything clears both (`Docs/app-dictionary-store.md`).

## Which source yields vocabulary

`VocabularySourceProbeTests` runs three sources through the existing rules on two invented
personas over fourteen invented days: window titles and typed lines through `seenAndSaid` and
the three-sighting `SightingLedger`, selections through `corrected(over:wrote:)`. Typed lines
are the committed lines of one day, read as the screen the speech is matched against; the
probe prints only counts. No store is touched. Run with
`swift test --filter VocabularySourceProbeTests` (Apple M5 Pro).

| Persona | Source | Proposed | Correct | Truth | Not in `GeneralVocabulary` | Median day learnt |
|---|---|---|---|---|---|---|
| engineer | title | 2 | 2 | 6 | 2 | 3 |
| engineer | selection | 1 | 1 | 6 | 1 | 5 |
| engineer | typed | 5 | 5 | 6 | 5 | 3 |
| administrator | title | 0 | 0 | 5 | 0 | - |
| administrator | selection | 1 | 1 | 5 | 1 | 4 |
| administrator | typed | 2 | 2 | 5 | 2 | 3 |

Precision is 1.0 for every source: a term must be spoken as well as seen, so typed decoys and
typos that are never said are never proposed. Recall is where they differ: typed lines 0.83 and
0.40, titles 0.33 and 0.00, selections 0.17 and 0.20.

**Threshold.** Aggregating typed lines into the evidence ledger is worth building when, on every
persona, typed recall beats title recall by at least 0.20 at a precision of at least 0.90. Both
invented personas pass. The fixtures are written by hand, so this decides the follow-up, not the
size of the gain on real use.

## Candidate budget

The candidates offered for a dictation are a function of the `Utterance` alone: at most
`maximumLength × words.count` spans, ordered least confident first so the budget is spent on
the words that needed it. A run's confidence is its minimum, so longer runs sort ahead of the
single words inside them.

## Related pages

- `Docs/app-dictionary-store.md` — the file, the caches and the three resets.
- `Docs/ai-correction-thresholds.md` — when an entry may replace a heard word.
- `Docs/cleanup.md` — the doubtful-words line, where entries are offered to the model.
