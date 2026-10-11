# Decoding a stored history: one unreadable change costs one change

The dictation history is decoded from one file as a whole: `DictationHistoryStore`
(`Sources/UttrflowHistory/DictationHistoryStore.swift`) treats a file it cannot decode as
unreadable and keeps none of it (see [history-store-file.md](history-store-file.md)). So a
single field that throws inside `DictationRecord`, `RecordedChanges`, `RecordedCorrection` or
`RecordedSnippet` would cost the user every dictation on disk, on nothing worse than running an
older build after a newer one. The decoders in `Sources/UttrflowHistory/DictationRecord.swift`
and `Sources/UttrflowHistory/Corrections.swift` are written so that cannot happen.

## Which fields may be missing

A field added to any of these types is read with `decodeIfPresent` and given an honest
default, or it is not added. Only fields with an honest default get one.

| Field | When absent | Why |
|---|---|---|
| `DictationRecord.isFlagged` | `false` | A file without the key and a dictation nobody flagged are the same fact. |
| `DictationRecord.changes` | `nil` | Absent means unmeasured, not "nothing changed"; see [core-history-accuracy.md](core-history-accuracy.md). |
| `DictationRecord.guardRefusals` | `nil` | Unrecorded; a kind this build lacks is left out of the list, never a discarded file. |
| `DictationRecord.notation` | `nil` | No notation recorded; a destination this build lacks or a count not above zero reads as none, never a discarded file. It holds a kind of place and a count, no word. |
| `DictationRecord.applicationName`, `applicationIdentifier`, `spokenFor` | `nil` | Unknown is their honest value. |
| `RecordedCorrection.isUndone` | `false` | A file without the key and a change nobody undid are the same fact. |
| `RecordedCorrection.writtenWordIndex` | `nil` | Unknown; undo falls back to the heard-space range ([core-history-undo.md](core-history-undo.md)). |
| `RecordedChanges.corrections`, `snippets` | empty | Lists that were never written hold nothing. |
| `RecordedChanges.spokenWords` | `nil` | Also `nil` when negative, so a damaged count retires the accuracy figure instead of trapping. |

Two fields stay required:

- `RecordedCorrection.heardConfidence` has no honest default. A missing score read as zero
  would claim the recogniser was certain about words it never scored, so a stored change
  without it is dropped.
- `RecordedCorrection.reason` stays required, but a spelling this build cannot name decodes to
  `CorrectionReason.unknown`, shown as "Other" and written back verbatim. A reason added in a
  newer build is therefore kept, shown and undoable on an older one, never renamed.

## How one bad change is contained

`RecordedChanges.init(from:)` reads both lists entry by entry through `Salvaged`, a private
`Decodable` wrapper whose `init(from:)` uses `try?` and never throws. An entry this build cannot
read is left out of the list rather than failing the record, the record list, and the file. The
`try?` is deliberate: the changes a user cannot see are the ones they cannot undo, and a build
that cannot read a change has nothing true to say about it.

The write path carries the reason as the one `UttrflowCore.CorrectionReason` from the engine to
the store, so no string conversion can lose a correction between them.

## Why the decoders are hand-written

Swift's synthesised `init(from:)` throws on any absent non-optional key and ignores the
property's default value. Adding `isFlagged` to `DictationRecord` with a synthesised decoder
would make every file already on disk unreadable. The hand-written decoders keep the
synthesised behaviour for every other field.

## Tests

`DictationRecordTests.decodesTheShapeBeforeChanges()`
(`Tests/UttrflowHistoryTests/DictationRecordTests.swift`) decodes a JSON literal of the shape an
older build writes, rather than re-encoding today's shape: a test that encodes before it decodes
cannot fail the way an upgrade does. `RecordedChangesDecodingTests` in
`Tests/UttrflowHistoryTests/CorrectionsTests.swift` covers an unreadable change inside an
otherwise readable record.
