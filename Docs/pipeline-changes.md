# What the pipeline changes about a dictation, and how it stays honest

`UttrflowPipeline` may rewrite what the recogniser heard: a personal-dictionary correction, a
snippet expansion, the tidier. Every one of those is reported back with the outcome so it can be
shown, undone and learnt from. The seams are in `Sources/UttrflowPipeline/TranscriptChanging.swift`
and the record of what changed is in `Sources/UttrflowPipeline/DictationChanges.swift`; this page
holds the design rules behind both. [pipeline.md](pipeline.md) has the stage order.

## The seams

- `WordCorrecting`, `SnippetExpanding`, `DictationLearning` and `VocabularyLearning` are the
  pipeline's own protocols rather than the engines behind them, so the whole speak-to-inserted
  sequence tests with no dictionary, no snippet store and no model. `DictationCorrection` restates
  `UttrflowAI.WordCorrection` field for field for the same reason: the pipeline sees nothing but
  `UttrflowCore`.
- The one error type, `DictationChangeError`, has one case, `storeRefused`, because there is one
  cause and one consequence: a store on disk refuses, and the dictation carries on exactly as
  though the feature were switched off. It is not a `UttrflowFailure`, since the pipeline swallows
  it by design and no user is ever shown its message.
- `NoTextChanges` wires all four seams to nothing. It is one type rather than four no-ops because
  "leave the words alone and remember nothing" is one behaviour. `VocabularyLearning` has no
  default implementation on the protocol: a seam that silently does nothing when a conformer
  forgets it is how a feature compiles and never fires. Opting out is passing `NoTextChanges`, in
  writing, at the call site.
- Learning is a separate seam from correcting because it happens at a different time: a word
  earns its place by surviving a dictation, so nothing is counted until the words have landed, and
  nothing is counted from an insertion whose arrival is `.unconfirmed`. `DictationLearning` has
  two methods, one per store, and each takes the whole dictation as a batch so each store rewrites
  its file once per dictation. The dictionary is handed each entry once, because it counts
  dictations; the snippets are handed every firing. Keeping the two apart leaves the decision about
  how much failure is survivable in the pipeline, where it is tested: a refused dictionary write
  does not stop the snippets being counted.
- Neither `DictationLearning` nor `VocabularyLearning` is offered a dictation into a secure field
  or a credential-shaped one (the `KeptWords` gate that also decides `wordsToKeep`), so no
  dictionary word or snippet it used is counted. `VocabularyLearning` is also not offered one
  whose words landed in a different application from the one the screen was read from.

## Proposals, not rewrites

- A correcting engine proposes and never applies. Handing back a rewritten string would take the
  decision away from the only layer that knows whether the dictation is still wanted, and would
  leave nothing to show or undo.
- `DictationCorrection.applying(_:to:)` splices corrections by character range rather than
  rebuilding the sentence from its words. Rejoining words with single spaces is the whitespace
  collapse that flattens a dictated code block onto one line; everything between the words
  (newlines, indentation) is copied across untouched, and punctuation the recogniser attached to a
  word is kept around the replacement. All corrections are applied in one pass, because a
  replacement can be a different number of words from what it replaces ("s q l" becomes "SQL")
  and applying them one at a time would invalidate the ranges not yet done.
- A correction naming words the transcript does not have, or overlapping one already taken, is
  dropped and left out of what comes back (`CorrectedTranscript`). The engine cannot produce
  either, but it reaches the pipeline through a protocol, and a bad range must cost a correction
  rather than a dictation. Reporting only what landed is the other half of "nothing is applied
  silently".
- Word ranges index the whitespace-separated words of the transcript (`spokenWordRanges()`),
  because that is how an utterance is counted into words. Splitting on runs of letters would put
  "don't" at two indices and shift every later correction onto the wrong word.
- `AppliedChanges.spokenWords` is taken from the transcript before any rewrite rather than counted
  later, because the dictionary, the snippet expander and the tidier each change the word count,
  and an accuracy figure that subtracts heard words from written ones is meaningless.

## Scored words

- `Transcription.scoredWords` is `nil` when nobody measured, never "everything is certain". A
  single score standing in for every word makes correction's first condition either vacuous (a
  restrained engine rewrites every dictation) or unsatisfiable (it never fires). Declining to judge
  is the third answer, asked once here rather than by each caller.
- Segment words are matched to the transcript's words by their reduced form (`SpokenToken.scoreKey`)
  rather than by position: a recogniser is free to break words differently from the text it also
  gave, and a misalignment would score the wrong word. Where a word repeats, the lowest confidence
  wins, since the doubtful reading is the one worth acting on. An unscored word gets 1.
- See [speech-engines.md](speech-engines.md) for where the probabilities come from and what they
  cost.
