# Latin letters only

**Uttrflow writes English/Latin script only. Hindi and Hinglish speech is romanised the way
people type it, never written in Devanagari and never translated.**

"हाँ ठीक है" is written "Haan thik hai", not "हाँ ठीक है" and not "Yes, okay". Uttrflow is not
a translator. This holds for every piece of text dictation inserts, whichever engine tidied
the words, and when no engine tidied them at all.

Three places make it true, from the most specific to the last resort.

| Where | What it does |
|---|---|
| `RuleBasedTransformer` | romanises the transcript with `Romaniser` before the passes run, so the floor beneath every model writes Latin letters |
| `MeaningPreservationGuard.scriptVerdict` | refuses a model's rewrite that is in another script, translates a Devanagari draft, or repeats a worked example, so the router falls back to the rules |
| `DictationPipeline` | runs `LatinScript.enforced` over the finished message before snippets and insertion, so an untidied or unexpected answer is romanised too |

Snippet expansions are the user's own text and run after that last step, so a snippet the
user wrote in Devanagari is inserted as written.

## The romaniser

`Sources/UttrflowCore/Script/Romaniser.swift` writes Devanagari the way Hinglish is typed in a
chat, not the way a scholar transliterates it. It has no diacritics and never produces
"karanā"; it produces "karna".

- **Common spellings first.** A table of 167 frequent words holds the
  spelling people actually use: है hai, हाँ haan, ठीक thik, नहीं nahi, मैं main, में mein, क्या
  kya, क्यों kyun, हूँ hoon, and loanwords people write in English (ऑफिस office, मिनट minute).
  Chandrabindu and anusvara key the same entry, so हाँ and हां meet.
- **Syllables otherwise.** A word is split into consonant clusters and their vowels.
- **The unwritten vowel is dropped** at the end of a word (कल kal) and between a vowel and a
  consonant that carries its own vowel (करना karna, समझना samajhna), scanning from the right.
  A conjunct after it keeps it: अनन्या is "ananya", not "annya".
- **Long vowels are doubled only where people double them.** आ is "aa" in a first or closed
  syllable (आज aaj, किताब kitaab) and "a" at the end of a word or before another vowel
  (करना karna, जाएगा jayega). ई and ऊ are "ee" and "oo" in a closed syllable or a first
  syllable before "a" (चीज़ cheez, पूरा poora), otherwise "i" and "u" (लीजिए lijiye, दूँगा dunga).
- **A final cluster drops its vowel too** (अगस्त agast, दोस्त dost) unless it ends in य, र or व
  (मित्र mitra).
- **Nasalisation is "n"**, "ein" for a final ें (में mein), and nothing before न or म (मैंने maine).
- **An unwritten vowel before a closing ह is "e"**: पहले pehle, कह keh.
- **Clusters people write as one sound**: च्छ cch (अच्छा accha), क्ष ksh, ज्ञ gy. व is "w" except
  before "i" or "e" (वाला wala, विक्रम vikram). Nukta letters take their borrowed sound: ज़ z, फ़ f.
- **Devanagari digits and stops** become Western digits and a full stop; a danda the recogniser
  followed with a Latin stop is written once.

Nothing in the Devanagari block survives it: every scalar of the block, alone or after a
consonant, is covered by a test.

### Measured

Against the twelve Hindi and Hinglish passages of `TranscriptionCorpus`, whose Devanagari and
romanised forms are word-for-word parallel (385 words), normalised as every transcription score
is (`TextNormaliser.standard`):

| | words | characters |
|---|---|---|
| ICU letter by letter, stripped of diacritics | 42.7% | 84.5% |
| `Romaniser`, syllable rules alone (no table) | 91.9% | 98.3% |
| `Romaniser` | **97.9%** | **99.4%** |

The rules and the table were written with these passages in view, so these are upper bounds:
there is no held-out Hindi set yet. The clean-up corpus's six Hinglish cases were in view too;
against their expected text, which also has fillers removed and commas added, the romaniser
alone matches 92.9% of words and 97.4% of characters. `RomaniserCorpusTests` holds the floor.

The remaining misses are mostly two spellings of one word, where neither is wrong: the
references write "theek" and "hun" where the table writes "thik" and "hoon", "Are" where it
writes "arre", "zaroorat" where the rules write "zarurat", "raghunath" for "raghunaath".

On the rules path, the six Hinglish cases of the clean-up corpus went from 0 passing (mean
similarity 24%) to 5 passing (92%). The sixth, `hinglish-negation-kept`, expects "yah" and
"theek" where the table writes "yeh" and "thik". English is unchanged byte for byte: every
English case of the clean-up corpus gets the answer the passes gave before romanising existed,
and `LatinScript.enforced` returns every English passage and expectation exactly as written.

## The script guard

A model can answer Devanagari with a translation, with the prompt's own worked example, or in
another script, and before this check the guard accepted all three (issue 700): its tokeniser
reads no Devanagari, so it compared nothing.

`scriptVerdict` reads the draft the only way it needs to: romanised by `Romaniser`.

- **Another script.** A rewrite holding any letter outside Latin is refused.
- **A translation.** When the draft holds Devanagari, each word of the rewrite is looked for
  among the romanised draft's words by `Romaniser.soundKey`, which folds the usual spelling
  variants together ("theek" and "thik", "woh" and "wo", "hoon" and "hun"). Digits are left to
  the number checks. More than half the rewrite's words with no counterpart is a translation.
  Measured on the answers issue 700 recorded: "Meeting is at four o'clock, no no, five o'clock."
  has 8 of 9 words with none and is refused; "Woh kya hai na, yaani mujhe thoda time chahiye."
  has 1 of 9 and is accepted.
- **A worked example.** A rewrite of three or more words, at least 80% of them one example's
  words in order, is refused when the draft holds fewer than half of that example's words.
  This reads any script, so an English example given back for English that did not say it is
  refused too, while a dictation that really says "add milk and eggs to the shopping list" is
  not.

A refusal is not a failure. The router moves on, the rules romanise the draft, and the words
arrive in Latin letters.

## The last resort

`LatinScript.enforced` runs over the finished message. Devanagari is romanised, with a capital
where a romanised word opens a sentence. Any other script is written in Latin letters through
ICU with its diacritics stripped, and a letter ICU cannot write is dropped rather than inserted.
Another script's decimal digits become Western ones.

What counts as Latin is deliberately wide, because English text is full of it: accented Latin
letters, combining diacritics, curly quotes and dashes, currency, superscripts, letter-like
symbols, ligatures, fullwidth Latin, and emoji with their variation selectors, skin tones and
keycaps are all left exactly as they were. Only letters and marks of another script change.
