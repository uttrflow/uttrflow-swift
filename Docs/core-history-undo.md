# Undoing a correction: how the words are found and when they are left alone

`DictationRecord.undoing(_:)` returns a copy of the record with one change put back and
the dictionary entry to charge, or `nil` when the record has no such change or has already
put it back (so a second undo cannot count a second revert against the entry).

## The entry is the point

`PersonalDictionaryStore.recordRevert(of:)` counts reverts against the entry that caused
them, and a word the user keeps rejecting retires itself on that count. An undo that only
crossed out a row would leave the bad word in the dictionary to be applied again tomorrow.

## Where the words sit is computed, not searched

A correction's `wordRange` indexes the words as spoken. Every change applied before it may
have changed the word count on the way past ("s q l" becomes "SQL"), so each earlier
change shifts this one along by what it added or removed; a change already undone occupies
the words it was heard as, not the ones it was written as. The position is read against
the flags as they stand *before* this change is marked. Searching the finished text for
the written word instead finds the wrong one the first time a word appears twice.

Words are split on whitespace, the way the pipeline counts an utterance; splitting on
letters would put "don't" at two indices and shift every later correction onto the wrong
word. The split is stated in `CorrectionUndo.swift` rather than shared, because
`UttrflowHistory` sees nothing but `UttrflowCore`.

## The splice is by character range

The text between the words — newlines, indentation, the space before a full stop that is
not there — is copied across untouched. Rejoining words with spaces flattens a dictated
code block onto one line.

## Where the words landed after tidying

Tidying and snippet expansion both run after the dictionary, so the stored text is not the
text the heard-space ranges index: a filler dropped before the word, the discarded half of
a self-correction, "twenty five" written as "25", or a snippet expanded into several words
all move it. So the pipeline, which still holds both texts, aligns the corrected transcript
against the inserted text with `WordErrorRate.measure` and records each correction's
`writtenWordIndex`: where its written words begin among the stored text's whitespace
words. Words are compared by their letters, lower-cased and without the punctuation
hanging on them, since tidying capitalises and punctuates without changing the word. A
correction is located only when every one of its written words came through as a match and
they still sit side by side; anything the tidier rewrote is left unlocated.

At undo, the position is `writtenWordIndex` moved by each earlier change already undone,
by the words it gave back. A record where any correction lacks the index — one written
before the index was kept, or where the tidier rewrote the word — falls back to the
heard-space range shifted by the other corrections, as above.

## When the words do not line up

When the words at the computed position are not the ones that were written, the text is
left exactly as it is rather than overwritten with a guess — but the change is still marked
undone and the entry still answers for it, because the user's judgement of the change holds
whether or not the sentence can be repaired. A range that does not fit the text is refused
the same way. With the index recorded this happens only when the tidier changed the word
itself (its spelling, or punctuation attached to it), or on the fallback path.

## The result is a copy, not a rebuild

The record comes back as `self` with two fields changed in place. A constructor call
lists what its author remembered and takes the memberwise default for everything else,
and nothing warns about the difference — the shape of bug that drops `isFlagged`, the one
judgement in the record the user made. A copy has nothing to forget, and
`CorrectionUndoTests.changesOnlyWhatItSays()` compares whole values so a field added
tomorrow is covered without anybody remembering to add it to a checklist.
