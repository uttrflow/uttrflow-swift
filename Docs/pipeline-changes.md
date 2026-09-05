# What the pipeline changes about a dictation, and how it stays honest

`UttrflowPipeline` may rewrite what the recogniser heard: a personal-dictionary correction, a
snippet expansion, the tidier. Every one of those is reported back with the outcome so it can be
shown, undone and learnt from. This page holds the design rules behind `TranscriptChanging.swift`
and `DictationChanges.swift`. `Docs/pipeline.md` has the stage order.

## The seams

- `WordCorrecting`, `SnippetExpanding`, `DictationLearning` and `VocabularyLearning` are the
  pipeline's own protocols rather than the engines behind them, so the whole speak-to-inserted
  sequence tests with no dictionary, no snippet store and no model anywhere near it.
  `DictationCorrection` restates `UttrflowAI.WordCorrection` field for field for the same reason:
  the pipeline sees nothing but `UttrflowCore`.
- The one error type, `DictationChangeError`, has one case because there is one cause and one
  consequence: a store on disk refuses, and the dictation carries on exactly as though the
  feature were switched off (§19). It is not a `UttrflowFailure`, since the pipeline swallows it
  by design and no user can ever be shown its message.
- `NoTextChanges` wires all four seams to nothing. It is one type rather than four no-ops because
  "leave the words alone and remember nothing" is one behaviour. `VocabularyLearning` has no
  default implementation on the protocol on purpose: a seam that silently does nothing when a
  conformer forgets it is how a feature compiles and never fires. Opting out is passing
  `NoTextChanges`, in writing, at the call site.
- Learning is a separate seam from correcting because it happens at a different time: a word
  earns its place by surviving a dictation, so nothing is counted until the words have landed.
  It has two methods shaped after the two stores (the dictionary counts one entry at a time, the
  snippets in a batch), so the decision about how much failure is survivable stays in the
  pipeline where it is tested.

## Proposals, not rewrites

- A correcting engine proposes and never applies. Handing back a rewritten string would take
  the decision away from the only layer that knows whether the dictation is still wanted, and
  would leave nothing to show or undo.
- `AppliedChanges.applying` splices corrections by character range rather than rebuilding the
  sentence from its words. Rejoining words with single spaces is exactly the whitespace collapse
  that flattens a dictated code block onto one line; everything between the words (newlines,
  indentation) is copied across untouched. All corrections are applied at once, because a
  replacement can be a different number of words from what it replaces ("s q l" becomes "SQL")
  and applying them one at a time would invalidate the ranges not yet done.
- A correction naming words the transcript does not have, or overlapping one already taken, is
  dropped and left out of what comes back. The engine cannot produce either, but it reaches the
  pipeline through a protocol, and a bad range must cost a correction rather than a dictation.
  Reporting only what landed is the other half of "nothing is applied silently".
- Word ranges index the whitespace-separated words of the transcript, because that is how an
  utterance is counted into words. Splitting on runs of letters would put "don't" at two indices
  and shift every later correction onto the wrong word.
- `spokenWords` is kept on the outcome rather than counted later, because the dictionary, the
  snippet expander and the tidier each rewrite the word count. Substituting the finished count is
  how the accuracy figure came to subtract heard words from written ones and report 0%.

## Scored words

- `RawTranscript.scoredWords` is `nil` when nobody measured, never "everything is certain". A
  single score standing in for every word makes correction's first condition either vacuous (a
  restrained engine rewrites every dictation) or unsatisfiable (it never fires). Declining to
  judge is the third answer, asked once here with its reason rather than ad hoc by each caller.
- Segment words are matched against the whitespace split of the text rather than trusted to
  align with it: a recogniser is free to break words differently from the text it also gave, and
  a misalignment would score the wrong word. Where a word repeats, the lowest confidence wins,
  since the doubtful reading is the one worth acting on. An unscored word gets 1.
- See `Docs/speech-engines.md` for where the probabilities come from and what they cost.
