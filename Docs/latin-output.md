# Latin letters only

**Uttrflow writes English/Latin script only. Hindi and Hinglish speech is romanised the way
people type it, never written in Devanagari and never translated.**

"हाँ ठीक है" is written "Haan thik hai", not "हाँ ठीक है" and not "Yes, okay". Uttrflow is not
a translator. This holds for every piece of text dictation inserts, whichever engine tidied
the words, and when no engine tidied them at all.

The romaniser and the last-resort check live in `Sources/UttrflowCore/Script/` (`Romaniser.swift`,
`LatinScript.swift`); the script guard is `Sources/UttrflowAI/ScriptGuard.swift`. Three places make
it true, from the most specific to the last resort.

| Where | What it does |
|---|---|
| `RuleBasedTransformer` | romanises the transcript with `Romaniser` before the passes run, so the floor beneath every model writes Latin letters |
| `MeaningPreservationGuard.scriptVerdict` | refuses a model's rewrite that is in another script, translates a Devanagari draft, or repeats a worked example, so the router falls back to the rules |
| `DictationPipeline` | runs `LatinScript.enforced` over the finished message and again after snippets, immediately before insertion, so untidied text and user-authored expansions are romanised too |

Snippet expansions stay stored exactly as the user wrote them. The final script check runs
after expansion, so a snippet written in Devanagari is inserted romanised in Latin letters.
A trigger stays stored as typed and is matched in the form dictation writes it: `Snippet.triggerWords`
reads it through `LatinScript.enforced`, so a trigger typed in Devanagari or mixed script fires when
said, and two triggers that romanise alike are one trigger to the store's duplicate check.

Recognition still answers in Devanagari, and what that costs in decoder steps — with the options
for decoding straight to Latin, and why none of them is taken — is measured in
`Docs/speech-engines.md`.

## What a model is told

Every prompt that states the rule quotes one constant, `LatinOnlyInstruction.text` in
`Sources/UttrflowCore/Script/LatinOnlyInstruction.swift`: the tidy contract (`PromptContract`) for
every destination, and the suggestion prompt (`CompletionPromptBuilder`) whenever its context holds
another script. `LatinOnlyInstructionTests` checks the constant against this quote:

> Write only English in the Latin alphabet, or romanised Hinglish where the person writes Hindi in Latin letters. Never write Devanagari or any other script, and never translate.

What a prompt says is a request; the romaniser, the script guard and the last resort below are
what hold whatever a model writes.

## The romaniser

`Sources/UttrflowCore/Script/Romaniser.swift` writes Devanagari the way Hinglish is typed in a
chat, not the way a scholar transliterates it. It has no diacritics and never produces
"karanā"; it produces "karna".

- **Common spellings first.** A table of <!-- count:Romaniser.commonSpellingList -->204 frequent words (`commonSpellings`) holds the
  spelling people actually use: है hai, हाँ haan, ठीक thik, नहीं nahi, मैं main, में mein, क्या
  kya, क्यों kyun, हूँ hoon, and loanwords people write in English (ऑफिस office, मिनट minute).
  Chandrabindu and anusvara key the same entry, so हाँ and हां meet.
- **Syllables otherwise.** A word is split into consonant clusters and their vowels.
- **The unwritten vowel is dropped** at the end of a word (कल kal) and between a vowel and a
  consonant that carries its own vowel (करना karna, समझना samajhna), scanning from the right.
  A nasal syllable before it keeps it too (ज़िंदगी zindagi). A conjunct after it keeps it:
  अनन्या is "ananya", not "annya". So does a lone ह after it, whose "h" would otherwise join
  the consonant before into a digraph: दोपहर is "dopahar", not "dophar" (read "dofar").
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
is (`TextNormaliser.standard`), by the harness in `RomaniserCorpusTests`:

| | words | characters |
|---|---|---|
| ICU letter by letter, stripped of diacritics | 42.7% | 84.5% |
| `Romaniser`, syllable rules alone (no table) | 91.9% | 98.3% |
| `Romaniser` | **97.9%** | **99.4%** |

These are in-sample figures: the rules and the table were written with these passages in view,
so they are upper bounds. `RomaniserCorpusTests` holds the floor at 96% of words and 99% of
characters, and checks that `LatinScript.enforced` returns every English passage and
expectation exactly as written.

The remaining misses are mostly two spellings of one word, where neither is wrong: the
references write "theek" and "hun" where the table writes "thik" and "hoon", "Are" where it
writes "arre", "zaroorat" where the rules write "zarurat", "raghunath" for "raghunaath".

### Held out

`HeldOutHindi` holds 30 invented Devanagari sentences (everyday vocabulary, the sound classes
below, no real people or places) that no rule, table entry or tuning passage was written against.
`HeldOutHindiTests` fails if a table entry is added for one of their words or a sentence appears
in `TranscriptionCorpus`. Each sentence takes Latin references written independently by people
who have not seen the table, and `RomanisationScore` scores against the closest of them. No
reference is written yet, so no held-out figure exists.

### Audited by sound class

`RomaniserSoundClassTests` checks the romaniser by the structure of the script rather than by
reported word: every consonant with every vowel sign in a closed first syllable (30 × 11 = 330
cases), independent vowels, common conjuncts (क्ष, त्र, ज्ञ, श्र and doubled stops), final
halant, anusvara before each consonant class, chandrabindu, nukta letters, visarga and digits,
and, separately, unwritten-vowel cases, which need a rule rather than a table. Each case is
compared with the form people type; the expected forms are compiled for this audit, not copied
from any external list.

A case written wrongly today is listed in `knownGaps` and recorded as a known issue, so a fix
shows up as an unexpected pass and the list must shrink with it. Measured by that test:

| Class | Cases | Wrong | Written today |
|---|---|---|---|
| consonant × vowel sign | 330 | 0 | |
| independent vowel, conjunct, final halant, nukta, digit | 40 | 0 | |
| anusvara before velar, palatal, retroflex, dental, sibilant | 15 | 0 | |
| anusvara before a labial | 6 | 6 | मुंबई munbai, नंबर nanbar, संपर्क sanpark |
| chandrabindu | 6 | 3 | माँ man, गाँव gaanw |
| visarga after an unwritten vowel | 4 | 3 | अतः ath, नमः namh |
| unwritten vowel | 15 | 1 | हँसना hansana |

Each wrong row is a class, not a word: anusvara is always "n" though it is said "m" before
प फ ब भ म; a nasal "aa" that is the whole word is shortened as if it ended a longer word; a
visarga after the unwritten vowel drops the vowel it follows; and the unwritten-vowel rule
drops the vowel after a nasal syllable that people drop in हँसना. The months जनवरी and
फ़रवरी, whose dropped vowel is the one the right-to-left scan keeps, and चाय "chai" are in
`commonSpellings`.

### Properties over generated words

`RomaniserPropertyTests` generates 5,000 Devanagari words from the romaniser's own tables
(consonants, nukta letters, conjuncts, vowel signs, virama, independent vowels, anusvara and
chandrabindu, visarga) with fixed seeds, and checks what must hold for every word: the output is
non-empty lower-case ASCII letters; `LatinScript.enforced` is Latin and a second pass changes
nothing; precomposed and decomposed nukta, chandrabindu and anusvara, and inserted joiners give
one output and one `soundKey`; and a run of words is written word for word with its spacing
kept. `UTTRFLOW_SEED` replays one seed. None is broken on the tree this landed on.

### English loanwords outside the table

Only the loanwords in `commonSpellings` come out in English spelling; every other English word
the recogniser writes in Devanagari is spelt by the syllable rules ("मैनेजर" mainejar).
`LoanwordRestorationProbeTests` measures whether the guard's own acceptance test
(`isRespelling`: a shared Double Metaphone key of at least two sounds, not an ordinary
collision) could restore the English spelling, taking candidates from
`GeneralVocabulary.wordsSounding(like:)` and restoring only when exactly one qualifies. Measured
on 100 invented loanwords and 122 ordinary Hindi words, on an Apple M5 Pro:

| Loanwords | Count | Examples |
|---|---|---|
| already spelt in English | 9 | report, link, student |
| restorable by the match | 13 | draapht draft, teem team, histri history |
| same sound, but not in the vocabulary | 63 | mainejar manager, tikat ticket, kainsal cancel |
| sounds differ by the guard's test | 15 | kanpani company, nanbar number, sarwar server |

| Hindi words | Count | Wrongly restored |
|---|---|---|
| ordinary Hindi | 122 | 8: naam name, baccha back, daal daily, sona soon, paani pani, khaana khana, jaan jaana, kaan kaun |

So the match cannot be the restoration step as it stands: it reaches 13 of the 91 misspelt
loanwords, because the vocabulary holds almost none of them, and it rewrites 8 of 122 Hindi
words (6.6%), four of them into English, against a bar of none. Excluding listed Hindi words
removes neither "baccha" nor "sona", which the vocabulary does not list. Restoring loanwords
needs a list of English words that is a deliberate product choice, and a Hindi lexicon broad
enough to veto every collision; neither exists today.

## The script guard

A model can answer Devanagari with a translation, with the prompt's own worked example, or in
another script. The guard's word tokeniser reads no Devanagari, so the other checks compare
nothing there; `scriptVerdict` reads the draft the only way it needs to: romanised by
`Romaniser`.

- **Another script.** A rewrite holding any letter outside Latin is refused.
- **A translation.** When the draft holds Devanagari, each word of the rewrite is looked for
  among the romanised draft's words by `Romaniser.soundKey`, which folds the usual spelling
  variants together ("theek" and "thik", "woh" and "wo", "hoon" and "hun", a final "ay" and
  "ai" as in "chaay" and "chai"). A dropped medial "a" is not folded: "karna" and "karana"
  are two verbs. Digits are left to
  the number checks. More than half the rewrite's words with no counterpart
  (`mostStrangerWords`, 0.5) is a translation: "Meeting is at four o'clock, no no, five
  o'clock." has 8 of 9 words with none and is refused; "Woh kya hai na, yaani mujhe thoda time
  chahiye." has 1 of 9 and is accepted.
- **A changed word.** Below that, the rewrite's content words are aligned with the romanised
  draft's, in order, by `WordErrorRate.measure` over the same sound keys, with number words read
  as their digits, fillers dropped and a word said twice in a row kept once. Grammar words (Hindi auxiliaries, postpositions and particles, and English
  `FunctionWords`) are left out of both sides; a negation, a number and a Hindi pronoun never
  are. A dropped or added content word refuses the rewrite, and so does a substituted one unless
  it is:
  - the same word in another form, by `WordForms.sameRomanisedForm`: an English
    inflection by `sameForm`, a Hindi verb or noun and its ending ("aa" and "aata", "log" and
    "logon"), or two cases of one demonstrative ("yah" and "is");
  - an English loanword the rules romanised, written in its English spelling: the two share a
    Double Metaphone key of at least two sounds and are not two ordinary English words
    (`ReadingRestraint.isOrdinaryCollision`). "ticket" for "tikat", "cancel" for "kainsal",
    "office" for "ophis" and "sorry" for "sauri" are accepted.

  "Maine khana khila." for "मैंने खाना खा लिया" changes the verb and drops "liya", and "Hum doh
  baje" for "हम धाई बजे" changes the time: "dhai" and "doh" share only a lone T, which says too
  little to call them one word. Both are refused and the rules' romanisation goes in. What this
  cannot see: a change of tense on a verb whose stem is kept ("aata" for "aa raha") is accepted,
  and a changed Hindi word that happens to share a two-sound key with the draft's is too.
- **A worked example.** A rewrite of three or more words, at least 80% of them one example's
  words in order (`exampleCopied`), is refused when the draft holds fewer than half of that example's words.
  This reads any script, so an English example given back for English that did not say it is
  refused too, while a dictation that really says "add milk and eggs to the shopping list" is
  not.

A refusal is not a failure. The router moves on, the rules romanise the draft, and the words
arrive in Latin letters.

### How well the sound key judges one word

`Romaniser.soundKey` is measured against two tables in `Tests/UttrflowEvalTests/Golden/`:
`romanised-variants.json`, 169 Hindi words each with the other spellings people type for it
(297 variant pairs), and `romanised-distinct-words.json`, 54 pairs of different words a
spelling fold could merge. `RomanisedVariantProbeTests` pins the figures.

| Measure | Result |
|---|---|
| Variant pairs given one key (recall) | 133 of 297 (44.8%) |
| Variant sets whose every spelling meets | 58 of 169 |
| Distinct pairs given one key (false merges) | 29 of 54 |

Misses are spellings the six rules do not cover: "kyun" and "kyon", "zyada" and "jyada",
"bahut" and "bohot", "mein" and "main", "nahi" and "nahin", "hai" and "he". Nearly every false
merge comes from collapsing a doubled letter, which folds a long vowel into a short one:
"kam" and "kaam", "din" and "deen", "pata" and "patta", "jal" and "jaal".

## The last resort

`LatinScript.enforced` runs over the finished message. Devanagari is romanised, with a capital
where a romanised word opens a sentence. Any other script is written in Latin letters through
ICU with its diacritics stripped, and a letter ICU cannot write is dropped rather than inserted.
Another script's decimal digits become Western ones.

What counts as Latin is wide on purpose, because English text is full of it: accented Latin
letters, combining diacritics, curly quotes and dashes, currency, superscripts, letter-like
symbols, ligatures, fullwidth Latin, and emoji with their variation selectors, skin tones and
keycaps are all left exactly as they were. Only letters and marks of another script change.

## Related pages

- `Docs/cleanup.md` — the catalogue of cleanings, of which this is the one that is never optional.
- `Docs/ai-model-output.md` — the guard's other checks and what it cannot read in Devanagari.
- `Docs/speech-engines.md` — why recognition still answers in Devanagari.

## A Latin sentence in a right-to-left paragraph

A full stop is a neutral character: the bidirectional algorithm gives it the direction of the
paragraph when nothing strong follows it. So "Hello world." inserted at the end of an Arabic,
Hebrew or Urdu paragraph shows its stop on the left of "Hello", not after "world".

### Measured

Host: Apple M5 Pro, macOS 26. An offscreen `NSTextView` with `baseWritingDirection =
.rightToLeft` holds one right-to-left word and a space; "Hello world." is inserted at the end by
`insertText(_:replacementRange:)` (the typed route), `readSelection(from:type:)` (the pasteboard
route) and `NSTextStorage.replaceCharacters(in:with:)` (the selected-text write route). The layout
manager gives each glyph's horizontal centre.

| Paragraph | Text inserted | Every route |
|---|---|---|
| Arabic, Hebrew, Urdu | `Hello world.` | stop 3–4 pt left of "H": wrong side |
| Arabic, Hebrew, Urdu | `Hello world.` + U+200E | stop 6–7 pt right of "d": correct |

The route makes no difference: all three leave the same characters in the field, and the field
lays them out.

### Decision

Append a left-to-right mark (U+200E) after the final stop, and only when the dictated piece ends
in a stop and the focused paragraph is right-to-left. The mark is invisible, keeps every spoken
word, and is the smallest change that puts the stop on the right side. It is a formatting
character, so the meaning guard does not count it as a word and the history text stores the
dictation without it. It waits on the dictation read carrying the paragraph direction, which
the one focused-field reader (CX.1.a) provides.
