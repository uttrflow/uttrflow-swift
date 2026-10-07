# The dictation history file, and the shape of the store around it

`DictationHistoryStore` in `Sources/UttrflowHistory/DictationHistoryStore.swift` holds
everything the user has dictated, on this Mac, between launches: one `DictationRecord` per
finished dictation (`Sources/UttrflowHistory/DictationRecord.swift`), with the corrections and
snippet firings recorded against it. It is an actor over one file. The History, Corrections,
Home and Insights pages read it; a finished dictation appends to it.

The file holds transcripts and nothing else: no audio, and no path to any
([recordings.md](recordings.md)). In the app it is sealed with the local-store key
([local-store-encryption.md](local-store-encryption.md)), written owner-only and excluded from
backups through `PrivateFile` ([local-store-permissions.md](local-store-permissions.md)).

| Constant | Value | Meaning |
|---|---|---|
| file name (`DictationHistoryStore.defaultFile(in:)`) | `history.v1.json` | Under `~/Library/Application Support/Uttrflow/` for the shipped build (`LocalStore.file`). |
| `DictationHistoryStore.defaultCapacity` | 1,000 | Most records kept under a finite retention period. |
| `RetentionWindow.keepAlwaysDays` | 36,500 | The stored value for "Always": no window and no cap. |
| `Settings.defaultTranscriptRetentionDays` | `keepAlwaysDays` | Transcripts are kept until the user deletes them unless a shorter period is chosen. |
| `SettingsRetention.finiteOfferedDays` | 1, 3, 7, 14, 30, 90 | The finite periods Settings offers beside "Always". |

## Why it has its own file

The history grows with use, ages out on a clock, and is the one store whose contents are the
user's own words rather than their preferences. It lives in its own file rather than as a key
beside the settings, so nothing else reads it and nothing else pays for its size. The name is
versioned so a shape too different to read field by field can be introduced beside this one
rather than on top of it.

## Why an actor, not a lock

`SampleAccumulator` takes a lock because its writer is the audio capture thread, which runs in
real time and must never wait. Nothing here is real-time: the writer is a dictation that has
already finished, and the readers are windows and a menu. A lock would have to be held across a
file read and a whole-file rewrite, blocking whichever thread asked, and the thread that asks
most often is the main one. An actor turns that waiting into a suspension, so the caller's
thread is free. `SnippetStore` is the same shape for the same reasons
([ai-snippet-store.md](ai-snippet-store.md)).

## How reads stay in step with the disk

The file is the single source of truth. The store keeps its decoded contents in a
`CachedStoredList` (`Sources/UttrflowCore/Support/CachedStoredList.swift`) stamped with the
file's inode, size and modification time (`FileStamp`), and decodes the file again only when
that stamp differs. A file deleted or replaced in the Finder is therefore noticed on the next
read, with no invalidation code that has to see it happen. Every write replaces the held value
with what it wrote; a write that fails drops it, so the next read goes to the disk.

## Retention: "Always" keeps everything, a finite period has a cap

Every call takes a `Retention` (`Sources/UttrflowHistory/Retention.swift`): the user's period in
days and the moment to measure from, passed in so the store never reads a clock.

- "Always" keeps every record until the user deletes it. It skips the count cap on reads and on
  every write, including flagging, undoing a correction and deleting another record. Settings
  and the store share `RetentionWindow.keepAlwaysDays`, so the storage rule agrees with the
  choice. An Always history can grow past a thousand records, and reading and rewriting it then
  costs more; a storage optimisation must keep those records rather than impose a deletion
  policy the user did not choose.
- A finite period keeps the newest `defaultCapacity` records within its window. The cap bounds
  the whole-file rewrite on every dictation once the user has chosen automatic deletion. A
  capacity passed to `init` is clamped to zero or more, since a negative one would trap in
  `prefix`. Choosing a finite period applies its window and cap to the existing history on the
  next read or write.

Order is arrival order: a new record is prepended, never sorted in, so a machine whose clock
moved cannot reshuffle what the user is shown. The retention filter runs first and the cap
second, as a plain `prefix`, because the list is newest-first throughout.

## Retention is applied on read as well as on write

The promise is about elapsed time, and time passes while the app sits idle. So
`records(keeping:)` tidies the *disk* too: if the window has passed some records, it rewrites
the file without them. That rewrite is best-effort (`try?`): refusing to answer because the disk
refused the tidying would punish the reader for something it cannot fix, and either way nothing
the user was told is gone comes back on screen.

What a read may show (`retained(_:keeping:)`) and what may stay on the disk
(`keptOnDisk(_:keeping:)`) are two lists. They differ for one kind of record only: one the
window has passed on a clock too far ahead of it to be believed. That record is hidden either
way, and stays on the disk until a clock that has been put right sweeps it. Every write goes
through the disk list too. [retention-clock.md](retention-clock.md) explains why, and why a
dictation stamped ahead of the clock is treated as due rather than as young.

`changes(in:keeping:)`, which feeds the Corrections page, goes through `records(keeping:)` and
builds a `CorrectionHistory` from that one read, so a correction belonging to a dictation the
user was told is gone cannot outlive it.

## Writing

| Call | What it does |
|---|---|
| `append(_:keeping:)` | Prepends a finished dictation and answers with the history as it now stands. |
| `delete(_:keeping:)` | Forgets one dictation; an absent identifier is not an error. |
| `toggleFlag(_:keeping:)` | Flips the user's "this came out wrong" flag; `nil` when no record matches. |
| `undoCorrection(_:keeping:)` | Puts one correction back and answers with the dictionary entry to charge, or `nil` ([core-history-undo.md](core-history-undo.md)). |
| `deleteEverything()` | Removes the file and every set-aside copy; called by "Reset personalisation". |

`undoCorrection` returning `nil` means no dictation holds that change or it is already undone.
Neither is an error and neither writes anything, so undoing twice cannot count twice against a
dictionary entry. The caller passes a returned entry to
`PersonalDictionaryStore.recordRevert(of:)`.

Writes flush the temporary file and containing folder around their atomic replacement, so a
crash or a full disk cannot leave a truncated history file behind. Dictation history does not
keep a previous-generation backup; unreadable bytes from outside this write path follow the
set-aside behavior below. An empty list removes the file rather than writing `[]`, so an emptied
history leaves nothing of the user's on disk.

## When the file cannot be read

Whether the file is truncated, hand-edited, written by a build that knew a different shape, or
cannot be opened, the app must still open. The store never treats such a file as empty:

| What the read found | What happens to the file | What the store does |
|---|---|---|
| No file | — | Reads as an empty history. |
| A plaintext file that does not decode (`LocalStore.read`) | Renamed aside to `history.v1.json.unreadable-<seconds since 1970>` (with `-1`, `-2`… on a collision) | Reads as empty; the next write starts a fresh file instead of writing over the only copy. |
| An encrypted file that fails authentication, or whose key is definitely missing | Renamed aside the same way | As above. |
| A legacy plaintext file that does not decode, a key that is temporarily unavailable, or a file that could not be renamed | Left in place | Reads as empty and refuses every write (`HistoryStoreError.couldNotWrite`), so the original bytes cannot be replaced. |

Encrypted clipboard-index writes use a durable temporary file and atomic replacement, retaining
the prior authenticated generation so opted-in clipboard reads can recover after an interrupted
or corrupt whole-file replacement. Other stored lists are decoded entry by entry
(`LocalStore.decodeKeepingReadable`): an entry this build cannot decode, such as one carrying a
case a newer build added, costs only itself. Readable entries load, and the original bytes are
copied aside for every partial decode, even when an older copy already exists. Copies use the same
timestamped names with increasing collision suffixes, so repeated reads in one second keep the
newest originals under the store's count limit. Copies are also bounded by the store's set-aside
lifetime. A file that is not a list at all is still set aside whole. Inside a readable record, an
individual change that cannot be decoded costs only that change
([core-history-decoding.md](core-history-decoding.md)).

A set-aside copy holds transcripts, so it lives no longer than they would have. Every
`records(keeping:)` deletes copies whose stamp the retention window has passed
(`LocalStore.removeSetAside(_:stamped:)` with `RetentionWindow.sweepable`), and a period of
zero days deletes every copy. `deleteEverything()` deletes every copy whatever its age, since
nothing in the app can show one and nothing can tell it apart from the transcripts the user
asked to be forgotten.
