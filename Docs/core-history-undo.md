# Undoing a correction: how the words are found and when they are left alone

When the user undoes a dictionary correction on the Corrections page,
`DictationHistoryStore.undoCorrection(_:keeping:)` finds the record that holds it and calls
`DictationRecord.undoing(_:)` (`Sources/UttrflowHistory/CorrectionUndo.swift`). That returns a
copy of the record with the heard words put back into its text and the change marked undone,
together with the dictionary entry to charge; or `nil` when no record holds the change or it is
already undone, so a second undo cannot count a second revert against the entry. Where the
written words landed is recorded by the pipeline in
`DictationCorrection.locating(_:from:in:)` (`Sources/UttrflowPipeline/DictationChanges.swift`).

## Why undo charges a dictionary entry

`AppDelegate` passes the returned entry to `PersonalDictionaryStore.recordRevert(of:)`, which
counts reverts against the entry that caused them; a word the user keeps rejecting retires
itself on that count ([app-dictionary-store.md](app-dictionary-store.md)). An undo that only
crossed out a row would leave the bad word in the dictionary to be applied again.

## Where the written words landed after tidying

Tidying and snippet expansion run after the dictionary, so the stored text is not the text a
correction's `wordRange` (an index into the words as spoken) points into: a filler dropped
before the word, the discarded half of a self-correction, "twenty five" written as "25", or a
snippet expanded into several words all move it.

So the pipeline, which still holds both texts, aligns the corrected transcript against the
inserted text with `WordErrorRate.measure` and records each correction's `writtenWordIndex`:
where its written words begin among the stored text's whitespace-separated words. Words are
compared by their core, lower-cased and without the punctuation hanging on them
(`SpokenToken.scoreKey`), since tidying capitalises and punctuates without changing the word.
A correction is located only when every one of its written words came through as a match and
they still sit side by side; anything the tidier rewrote is left with `writtenWordIndex == nil`.

## How the position is computed at undo

When every correction in the record has a `writtenWordIndex`, the position is that index moved
by each earlier correction already undone, by the number of words it gave back
(`located`).

When any correction lacks it (a record written without the index, or one where the tidier
rewrote the word) the position falls back to the heard-space `wordRange`, shifted by every
earlier correction's change in word count (`counted`). The "s q l" to "SQL" correction, for
example, takes three heard words to one. A correction already undone occupies the words it was
heard as, not the ones it was written as, and the position is read against the flags as they
stand *before* this change is marked.

The finished text is never searched for the written word: a search finds the wrong one the
first time a word appears twice.

Words are split on whitespace, the way the pipeline counts an utterance; splitting on letters
would put "don't" at two indices and shift every later correction onto the wrong word. The
split is stated privately in `CorrectionUndo.swift` rather than shared with the pipeline,
because `UttrflowHistory` depends only on `UttrflowCore`.

## When the words do not line up

At the computed position, the word cores must match the written words, with only the first
letter's case allowed to differ. When they do not, or the range does not fit the text, the text
is left exactly as it is rather than overwritten with a guess. The change is still marked undone
and the entry still answers for it, because the user's judgement of the change holds whether or
not the sentence can be repaired. With the index recorded, this happens when the tidier changed
the word itself, or on the fallback path.

## How the words are spliced back

The replacement is by character range. Everything outside the replaced words (newlines,
indentation, text before and after) is copied across untouched; rejoining words with spaces
would flatten a dictated code block onto one line.

Inside the range, punctuation the stored text carries is kept:

| Heard form has | Result |
|---|---|
| The same number of words as the written form | Each word's core is replaced; each stored word's leading and trailing punctuation and the spacing between them are kept. |
| A different number of words | The heard words are written out; the first keeps the stored first word's leading punctuation and the last keeps the stored last word's trailing punctuation. |

## The result is a copy, not a rebuild

The record comes back as a copy of `self` with `text` and one correction's `isUndone` changed.
A memberwise constructor call lists what its author remembered and takes the default for
everything else, and nothing warns about the difference: that is how a rebuild drops
`isFlagged`, the one judgement in the record the user made. A copy has nothing to forget.

`CorrectionUndoTests.changesOnlyWhatItSays()` in
`Tests/UttrflowHistoryTests/CorrectionsTests.swift` compares whole values, so a field added to
`DictationRecord` is covered without anybody adding it to a checklist.
`UndoingAMovedCorrectionTests` in the same file covers fillers, self-corrections, numerals and
snippets that move the word before undo.

## The change ledger from the draft's edit chains

Every `Draft.Word` keeps the chain of edits the passes made to it, so where each change landed is
already known on the rules path and needs no alignment. `Draft.changeLedger`
(`Sources/UttrflowCore/Cleaning/ChangeLedger.swift`) reduces the chains to one `ChangeLedgerEntry`
per edit: the written word index (present words that are not layout marks, in draft order; for a
removal, the word that now follows the gap), the pass and the kind. An entry holds no heard or
written word, so it can be kept with a History row and pruned with it; `ChangeLedgerTests` checks
the encoded form for the fixture's words. Alignment stays only for the model path, which has no chain
(`RewriteAlignment`). The ledger is not yet stored on `DictationRecord`.
