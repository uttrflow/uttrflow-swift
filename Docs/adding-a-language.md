# Adding a language

Uttrflow transcribes English and Hindi. No other language is planned here; this page lists
what a later one has to touch, so the product's rules — Latin letters only, nothing
translated, nothing rewritten — stay true for it instead of silently becoming false.

## The rule that comes first

**A language with no romaniser may not be added to `LanguageCode.transcribed`.** A language
written in a script other than Latin needs a romaniser in `Romaniser`, a translation check in
`MeaningPreservationGuard.scriptVerdict` and a script check before it can be listed. Without
them its speech reaches the screen through ICU's generic transliteration, which nobody has
measured, and the translation guard never runs. See [latin-output.md](latin-output.md).

## Every place a language is keyed

Places are named by symbol rather than line, because lines move.

| File | Symbol | What it must hold for a new language |
|---|---|---|
| `Sources/UttrflowCore/Models/LanguageCode.swift` | `LanguageCode.transcribed` | The code. This is the list detection is held to. |
| `Sources/UttrflowUX/SettingsChoices.swift` | `SettingsLanguage.offered` | The same code, its English name and its endonym. |
| `Sources/UttrflowCore/Models/ListeningLanguages.swift` | `ListeningLanguages.init(profile:)` | Today it branches on Hindi alone; a third language needs a rule for which spoken sets pin one language. |
| `Sources/UttrflowSpeech/LanguageHeldDecoder.swift` | `compressionRatioThresholds` | A decision: a measured threshold, or `nil` to keep Whisper's 2.4. |
| `Sources/UttrflowEval/TextNormaliser.swift` | `Script` | Only `latin` and `devanagari`; another script needs a case and its normalising rules. |
| `Sources/UttrflowEval/TranscriptionCase.swift` | `TranscriptionCase.Language` | A case, and the hint it gives the recogniser. |
| `Sources/UttrflowEval/CorpusSample.swift` | `spokenLanguage` | Any code that is not `hi` is read as English today. |
| `Sources/UttrflowCore/Script/Romaniser.swift` | `Romaniser` | Devanagari only; a non-Latin script needs its own romaniser. |
| `Sources/UttrflowCore/Script/LatinScript.swift` | `LatinScript.transliterated` | The ICU fallback every other script falls through to today. |
| `Sources/UttrflowAI/ScriptGuard.swift` | `MeaningPreservationGuard.scriptVerdict` | Checks translation only for a Devanagari draft. |
| `Sources/UttrflowCore/Cleaning/FunctionWords.swift` | `FunctionWords` | English (and Hindi) closed word lists; a new language needs its own. |
| `Sources/UttrflowCore/Cleaning/NumberWords.swift` | `NumberWords` | The language's number words, or numerals are not written for it. |
| `Sources/UttrflowCore/Cleaning/QuestionShape.swift` | `QuestionShape` | The words that open a question in that language. |
| `Sources/UttrflowAI/Passes/FirstWordPass.swift` | abbreviation checks | The language's dotted abbreviations. |

A Latin-script language also needs its accents preserved through every pass, its own
punctuation conventions, and its own closed word lists behind any lookup that asks where a
word comes from.

## Punctuation conventions

"Latin letters only" is a rule about script, not about marks. Which marks each language is
written with is decided here, per language the product transcribes:

| Language | Marks written | Decision | Measured today |
|---|---|---|---|
| English | English: `? ! : ;` closed up to the word, straight quotes | Keep | 6 English passages in `TranscriptionCorpus`; `SpacingPass` closes a spaced clause mark up to its word |
| Hindi and Hinglish | English marks; the danda and double danda become a full stop (`Romaniser`) | Keep: romanised Hindi is typed with English marks | 6 Hindi and 6 Hinglish passages in `TranscriptionCorpus` |
| Spanish, French and every other Latin-script language | none | Not transcribed: `LanguageCode.transcribed` is `[en, hi]`, `SettingsLanguage.offered` lists only those two, and `LanguageHeldDecoder` holds detection to them | 0 passages in `TranscriptionCorpus`; 0 `¿`, `¡`, `«` or `»` written by any pass |

So no language-specific mark rules exist and none are built. Adding a Latin-script language
decides its row here before it is added to `LanguageCode.transcribed`, with:

- a corpus class for it, showing how the recogniser writes its marks (`¿ ¡`, a space before
  `: ; ? !`, guillemets);
- the passes that would rewrite a mark the recogniser wrote correctly for it, changed so they
  do not: `SpacingPass` closes up a space before `: ; ? !`, and `QuestionShape` and
  `FirstWordPass` read English words only;
- one formatter for marks, keyed by language; never a second one beside the English path.

## Measurements that must exist first

1. **Language identification confusion by length**: how often a short piece is detected as
   the wrong language, against English and Hindi.
2. **A corpus class** for the language in the evaluation corpus, scored by `make bakeoff`.
3. **A held-out set** the change was not tuned on.
4. **A prompt-frame probe**: what the vocabulary prompt does to recognition in that language.
5. **Its tokens-per-word cost**: the Devanagari cost in [speech-engines.md](speech-engines.md)
   is the template, since it decides how much audio fits one decode.

## What fails when the lists drift

- `SettingsPresenterTests.offersOnlyTranscribedLanguages`: `SettingsLanguage.offered` codes
  equal `LanguageCode.transcribed`.
- `LanguageHeldDecoderTests.everyTranscribedLanguageHasACompressionDecision`: the keys of
  `compressionRatioThresholds` equal `LanguageCode.transcribed`.

The rest of the table is judgement: the reviewer of a language change checks every row.
