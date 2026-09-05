# The accuracy figure: where its denominator comes from

`DictationPresenter.accuracy(of:snapshot:)` draws "how much of what I said came out as I
said it" from `RecordedChanges.spokenWords` and `RecordedChanges.correctedWords`. Both are
shaped to keep that figure honest.

## `spokenWords` is kept because it cannot be recovered

`DictationRecord.text` is what was *written*. Three passes stand between the utterance
and it: the dictionary can write one word over three, a snippet twelve over two, and the
tidier drops fillers from what is left. Counting the finished text and calling it the
utterance is the mistake that reports 0% to a user whose dictionary is working perfectly.
So the count lives on `RecordedChanges`, beside the ranges that index into it, and is read
together with them or not at all.

## Absent is not empty

- `DictationRecord.changes` present and empty means "this dictation came out exactly as
  spoken". Absent means nobody was keeping a record — a file from a build without changes,
  or a dictation whose insertion failed and never reported what was applied. Collapsing
  the two lets an unmeasured dictation count as a perfect one.
- `spokenWords == nil` retires the figure for that dictation, the same way absent
  `changes` does. `correctedWords` answers zero in that case, and the value is never read.
- `DictationHistoryStore.changes(keeping:)` lists a dictation with no record as
  contributing nothing, without stopping the ones beside it being read.

## `correctedWords` counts positions, not ranges

It is the number of distinct in-range positions in the utterance covered by a standing
correction.

- Distinct positions rather than summed range lengths, and out-of-range positions dropped,
  so the answer is at most `spokenWords` by construction and the accuracy figure is a plain
  subtraction with no `max(_:0)` absorbing a disagreement. The pipeline refuses overlapping
  and oversized ranges (`DictationCorrection.applying(_:to:)`); a hand-edited file can carry
  them, and the figure is then merely wrong about one dictation rather than negative.
- Undone changes do not count: the user put those words back, so they read as said.
- Snippets do not count: a snippet fires because the user said its trigger and meant it,
  so charging an expansion against the recogniser would charge the user's own shorthand.
