# Decoding a stored history: one unreadable change costs one change

`DictationHistoryStore` reads its file all-or-nothing and discards a file it cannot
decode; the next write puts the survivors — none — over it. So a single throwing field in
`RecordedCorrection` or `RecordedSnippet` would cost the user every dictation on disk, on
nothing worse than running an older build after a newer one.

## The rule

- Anything added to `RecordedCorrection`, `RecordedSnippet` or `DictationRecord` is read
  with `decodeIfPresent` and given an honest default, or it is not added.
- Only fields with an honest default get one. `isUndone` and `isFlagged` default to
  `false`: a file without the key and a change nobody undid are the same fact.
  `heardConfidence` has no honest default — a missing score read as zero would claim the
  recogniser was certain about words it never scored — so it stays required, and a file
  missing it costs that one change.
- `reason` stays required: a change this build cannot name must not be drawn under a name
  somebody guessed for it. A fifth `CorrectionReason` creates exactly that case for every
  user who runs an older build again, and it is contained one level up rather than
  defaulted away.
- `RecordedChanges.init(from:)` reads both lists entry by entry through `Salvaged`, a
  `Decodable` wrapper that never throws, so an entry this build cannot read is left out
  rather than thrown. The `try?` there is the point, not a swallowed error: the changes a
  user cannot see are the ones they cannot undo, and a build that cannot read a change has
  nothing true to say about it.
- The write path gives the same answer: `AppDelegate` builds each `RecordedCorrection`
  through the failable initialiser and `compactMap`s away any reason it cannot name.

## Why the decoders are hand-written

Swift's synthesised `init(from:)` throws on any absent non-optional key and ignores the
property's default, so adding `isFlagged` to `DictationRecord` without a hand-written
decoder would make every file already on disk unreadable. The hand-written decoders keep
the synthesised behaviour for every other field.

`DictationRecordTests.decodesTheShapeBeforeChanges()` holds a literal of the shape an
older build writes, rather than re-encoding today's shape: a test that encodes before it
decodes cannot fail the way an upgrade does.
