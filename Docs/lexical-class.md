# Reading a word's class

Every seam decision that asks what kind of word a word is reads it from one place:
`LexicalClass` in `Sources/UttrflowCore/Cleaning/LexicalClass.swift`, a thin wrapper over
Apple's on-device `NaturalLanguage` lexical-class tagger. `WordSlot`, `MentionGuard` and
`LayoutWordsPass` call it; nothing else builds its own tagger.

This is the lexical-class layer of the clause analyser. Its clause-boundary layer is
`ClauseSegmenter` in `Sources/UttrflowCore/Cleaning/ClauseSegmenter.swift`, which reads only
these classes and, when word timings are known, the pause before each word. It reports where a
clause starts and why; which of those starts get a comma is decided by the rules that call it.

## Clause starts

| Evidence | Read as |
|---|---|
| `afterOpener` | the first word is an interjection, or an adverb followed by a subject and verb |
| `coordinatedClause` | a conjunction with a subject and verb before it, and a subject then a verb after it |
| `pause` | no word evidence, and at least `pauseThreshold` (0.35 s) of silence before the word |

A conjunction that joins nouns ("eggs milk and bread") or shares one subject ("went home and
slept") starts no clause.

## How far the tagger holds on bare recogniser text

The question is whether the tagger still gives the same classes when the text arrives
lowercase and without marks, as bare recogniser output does.

**Method.** Each English reference in `EvaluationCorpus` that is plain ASCII is tagged as
written. It is then lowercased, with `. , ? ! ; : " ( )` replaced by spaces, and tagged again.
Cases whose word count changes are left out. The written tagging is the reference, so this
measures how stable the tagger is, not whether it is right.

| Measure | Words | Same class | Agreement |
|---|---|---|---|
| Lowercase, no marks, every word | 2215 | 2145 | 96.8% |
| Lowercase, no marks, word that closes a sentence | 294 | 275 | 93.5% |
| Cased, no marks, every word | 2215 | 2178 | 98.3% |

341 of 359 references aligned. The most common change is noun read as verb (18 words), then
noun read as other word or interjection (6 each).

Measured on an Apple M5 Pro running macOS 26.5.1, with a standalone `swiftc` probe. The same
numbers are checked by `Tests/UttrflowEvalTests/LexicalClassProbeTests.swift`, which fails
below 95% word agreement.

**Sentence completeness reads the tagger.** `MarkLegality.sentenceCompleteness` reads a closed
sentence from the last word's state and a verb in the tagger's classes. The 93.5% agreement on
sentence-closing words is taken as enough. It is scoped to the rules-side sentence splitter, its only planned reader.
A rule table held as data replaces it only if that splitter measures worse than the rules
without it.

## Held whole

`ClauseSegmenter` starts no clause inside a quote or bracket, at a number, or at the word that
joins two numbers, whatever the pause. `ClauseSegmenterEnclosureTests` checks this.
