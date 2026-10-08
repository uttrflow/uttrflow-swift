# What counts as an ordinary word

`GeneralVocabulary.isOrdinary` decides which words a general recogniser already spells, so the
dictionary does not learn them, the ordinary-word veto refuses them and sound-alike readings come
from them. This page scores three definitions of that set against a labelled fixture, and records
the one that ships.

## The fixture

`Tests/Fixtures/ordinary-words/labelled.tsv`: 300 words, each labelled `ordinary` or `personal`,
in four groups: everyday English (103), programmer vocabulary (56), romanised Hindi (49) and
invented personal terms (92). It holds words only, and every personal term is invented.

## The definitions

1. The English hand list `GeneralVocabulary.swift` held before this decision (deleted; its row
   below is the measurement taken while it shipped).
2. The recogniser tokenizer's cost: the number of byte-level BPE tokens for the word with a
   leading space, read from the `tokenizer.json` the speech model already installs.
3. The system word list at `/usr/share/dict/words` (Webster's Second International, public
   domain), standing in for a published list that needs no download.

## Results

```bash
python3 Scripts/ordinary_word_probe.py --tokenizer <model folder>/tokenizer.json
```

Measured with the large-v3 turbo tokenizer:

| definition | precision | recall | english correct | hindi correct | personal correct | programmer correct |
|---|---|---|---|---|---|---|
| hand list | 1.000 | 0.269 | 14/103 | 41/49 | 92/92 | 1/56 |
| tokenizer, 1 token | 1.000 | 0.721 | 103/103 | 5/49 | 92/92 | 42/56 |
| tokenizer, at most 2 tokens | 0.892 | 0.913 | 103/103 | 36/49 | 69/92 | 51/56 |
| system word list | 0.993 | 0.721 | 100/103 | 8/49 | 91/92 | 42/56 |
| tokenizer, 1 token, or the Hinglish list | 1.000 | 0.899 | 103/103 | 42/49 | 92/92 | 42/56 |

## Verdict

The tokenizer's cost wins: one token keeps precision at 1.000 (no invented term is called
ordinary) and lifts recall from 0.269 to 0.721, with every everyday English word and 42 of 56
programmer words. Two tokens buys recall at the cost of 23 invented terms, so one token is the
line. The system word list matches the tokenizer's recall with lower precision and adds a file
the app does not ship, so it loses.

The tokenizer is English-centred and splits romanised Hindi, so the Hinglish list stays: it is
also what `isHindiSpellingPreference` reads. One token or the Hinglish list scores 1.000
precision and 0.899 recall. The English hand list is the losing definition.

Limits: the fixture is 300 words labelled by one reader; programmer words the tokenizer splits
(`rebase`, `webhook`, `refactor`) still need the dictionary or a context hint.

## What ships

`GeneralVocabulary.isOrdinary(_:)` is the one test, and every reader asks it: the learner
(`isWorthLearning`), the ordinary-word veto (`ReadingRestraint`), the sound-alike readings
(`wordsSounding`), the casing pass's guard, the lexicon check and the pronunciation note. A word
is ordinary when its lowercase form is a row of `recogniser-words.json` or a word of the
romanised Hindi list. The word is lowercased and nothing more, so a phrase or a form with marks
(`s l a`, `.js`, `C++`) is never ordinary.

`recogniser-words.json` is derived, never edited:

```bash
python3 Scripts/derive_recogniser_words.py --tokenizer <model folder>/tokenizer.json
```

It refuses any tokenizer but the one `SpeechModel` pins, keeps every lowercase word of letters
whose leading-space spelling is one token, and drops a word the disclosure audit refuses in a
tracked file. The probe's last row scores the shipped table and matches the tokenizer row above.

What the change moves, against the hand list:

| Reader | Before | After |
|---|---|---|
| Ordinary words | 423 English + 179 Hindi | 20,477 + 179 |
| Weekday names | ordinary | not ordinary: the tokenizer spells them as one token only capitalised |
| Screen readings, both words ordinary | refused unless neither word was listed | refused unless the pair is in `Homophones`, the same rule the ordinary-words source keeps, so `Cache.swift` still offers "Cache" for "cash" and `mad` is no longer offered for "made" |
| Casing an ordinary word written on screen in capitals | never | only beside the neighbour the screen writes it with: "select id from orders" over `SELECT id FROM orders` |
| Lexicon rows with an ordinary form, each limited to destinations | 8 | 39: the new languages, tools and concepts apply in code and the terminal; the new commands everywhere but spreadsheets and SQL editors, so their spoken options still read in prose; `SQL` loses the spoken form "sequel" and stays everywhere |
| An acronym spelt out letter by letter whose letters spell an ordinary word (`https`, `ai`) | not ordinary | claims no ordinary word unless it spells a function word, so the casing pass still writes "HTTPS" and the lexicon check does not limit it |
| Loanword probe, ordinary Hindi words wrongly restored | 7 of 122 | 12 of 122 ([latin-output.md](latin-output.md)) |

A larger set offers more sound-alike readings for a word the recogniser split: its sound key
now reaches word pieces the tokenizer keeps as tokens ("pra" for "Priya"). The ranked phoneme
distance in [pronunciation-lexicon.md](pronunciation-lexicon.md) is the measure that replaces the
sound key for these readings.

## Ordinary is not the same as English

`LexicalClass.isKnownEnglishWord` asks a second question: whether the on-device English model
has a dictionary form for the word, so whether English has it in any inflection. `isOrdinary`
asks whether the recogniser writes the word unaided. The probe scores the English-word test as a
definition of ordinary, through `uttrflow-eval english-words`:

| definition | precision | recall | english correct | hindi correct | personal correct | programmer correct |
|---|---|---|---|---|---|---|
| English-word test | 0.994 | 0.760 | 102/103 | 6/49 | 91/92 | 50/56 |

As a definition of ordinary it loses to the shipped one: it calls the invented "calloway" a word,
misses 43 romanised Hindi words and the spelling "neighbour". So no reader that asks "would the
recogniser write this" reads it. The two sets differ both ways, and that difference is why the
English-word test stays for the readers that ask about the language:

- ordinary and not English: a word piece the tokenizer keeps whole ("trov") and romanised Hindi
  ("kar");
- English and not ordinary: an inflection or rarer word the tokenizer splits ("clawed",
  "readies", "docker", "rebase").

| Reader | Test | Why |
|---|---|---|
| the learner, the veto, sound-alike readings, the lexicon check, the casing pass's lexicon keys | `isOrdinary` | the question is what the recogniser writes |
| the non-word test (`WordCorrectionEngine`) | both: a word either test knows is kept | "trov" is ordinary and spells no word; "readies" is English and not ordinary |
| whether a sentence speaks Hindi (`WordCorrectionEngine`) | English | every listed Hindi word is ordinary; "kar" is not English and "main" is |
| a stray capital lowered (`FirstWordPass`) | English, with `isNameInDictionary` from the same model | ordinary would lower "Trov" and keep "Clawed" |
| a title term heard spelt as written (`LearnableWords`) | English, after `isWorthLearning` refused ordinary words | with no spelling difference only the language marks a term as the user's: "pgvector" is learnt, and "rebase", "refactor", "rollback" and "timeout", which the fixture labels ordinary, are not |
| a capitalised screen word in prose (`AcronymCasingPass`) | either | a heading word in capitals is a word if either test says so |
| a heard word recased to an entry (`WordCorrectionEngine`, the only path) | `isEveryday`: ordinary and English, or listed romanised Hindi | a speaker may mean "mark" or "kar" in lower case, so those need the screen; "docker" (English, split) and "trov" (ordinary, no word) are the user's term |

A heard word written in the case of a dictionary entry with the same letters has one path, the
correction engine's recasing, for every recogniser: a transcript without word scores gets the
recasing and nothing else. `AcronymCasingPass` leaves a one-word entry as it arrives, so a
lexicon or screen casing never overrides it. Each fixture word as a capitalised entry, heard in
lower case mid-sentence with no screen, counting the words written in the entry's case:

| group | English test (engine before) | `isOrdinary` (pass before) | `isEveryday` (now) |
|---|---|---|---|
| english (103) | 1 | 0 | 1 |
| hindi (49) | 43 | 7 | 7 |
| personal (92) | 91 | 92 | 92 |
| programmer (56) | 6 | 14 | 14 |

Before, the engine capitalised 43 romanised Hindi words ("bhai", "kaam") for an entry spelt so,
and the pass never asked the screen. With the entry on screen beside a heard
neighbour, all 300 take the entry's case. "neighbour" is ordinary and not English to the model,
so an entry "Neighbour" takes its case without the screen.
