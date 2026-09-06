# The dictation history file, and the shape of the store around it

`DictationHistoryStore` in `Sources/UttrflowHistory/DictationHistoryStore.swift` holds
everything the user has dictated, on this Mac, between launches.

## Its own file, not a key beside the settings

The history grows without bound, ages out on a clock, and is the one store whose contents
are the user's own words rather than their preferences. It lives at
`history.v1.json` under Application Support — versioned in the name so a shape too different
to read field by field can one day be introduced beside this one rather than on top of it.
Nothing else reads that file, so nothing else can be surprised by its size.

## An actor, not a `Mutex`-guarded box

`SampleAccumulator` takes a lock because its writer is CoreAudio's real-time thread, which
must never wait. Nothing here is real-time: the writer is a dictation that has already
finished, and the readers are a window and a menu. A lock would have to be held across a
file read and a whole-file rewrite, blocking whichever thread asked — and the thread that
asks most often is the main one. An actor turns that same waiting into a suspension, so the
caller's thread is free.

## Nothing is cached

The file is the single source of truth, and a copy beside it would be a second one: it would
disagree with a user who deleted the file in the Finder, and would have to be invalidated by
code that cannot see them do it. A read happens when a window is drawn, not per keystroke,
so re-reading is cheap enough to be worth the certainty.

`SnippetStore` is the same shape for the same reasons — see `Docs/ai-snippet-store.md`.

## The cap: a thousand records

The whole file is rewritten on every dictation, so the cap is really a bound on that write:
at a few hundred bytes a record, a thousand is a couple of hundred kilobytes — one cheap
atomic write — where an uncapped file eventually is not. It sits well above what the default
retention window holds, so in ordinary use the retention promise does the deleting and the
cap never has to. Because the cap only ever removes *more*, it cannot keep anything longer
than the user was told.

A capacity passed in is clamped to zero at the bottom, for the reason `RecentDictations`
gives about its own: a negative capacity would trap in `prefix`, and a history that keeps
nothing is a far better outcome than a crash.

## Retention is applied on read as well as on write

The promise is about elapsed time, and time passes while the app sits idle. A user who
dictated once a fortnight ago and never again was still told the words would be deleted, so
`records(keeping:)` tidies the *disk* too. That rewrite is best-effort: refusing to answer
because the disk refused the tidying would punish the reader for something the reader cannot
fix, and either way nothing the user was told is gone comes back on screen.

`changes(in:keeping:)` goes through the same call, so a correction belonging to a dictation
the user was told is gone cannot outlive it on the Corrections page. It answers with the
list and its completeness together because the two are read together, and two separate reads
could answer from two different files.

Order is arrival order — a new record is prepended, never sorted in. The clock belongs to
the caller, so a machine whose clock moved must not be able to shuffle what the user is
shown. The retention filter runs first and the cap second, and the cap is a plain `prefix`
only because the list is newest-first throughout.

## Undo answers with a dictionary entry

`undoCorrection(_:keeping:)` returns the entry to blame for the change it put back. The
caller passes it to `PersonalDictionaryStore.recordRevert(of:)`, which is how a word the user
keeps rejecting retires itself; an undo that stopped at the history would cross out a row and
leave the bad word to be applied again tomorrow. `nil` means no dictation holds that change
or it is already undone — neither is an error, and neither writes anything, so undoing twice
cannot count twice against an entry.

## Reading and writing the file

Absent, unreadable, truncated, hand-edited, or written by a build that knew a different
shape — to a user those all mean the same thing, which is that the app should still open, so
`load()` answers with nothing. Salvaging record by record is not attempted: the store's own
writes are atomic, so the realistic corruption is a whole file somebody mangled, and half a
history restored is harder to explain than none.

Writes are atomic, so a crash or a full disk cannot leave behind the truncated file `load()`
would then have to throw away. An empty list removes the file rather than writing `[]`, so an
emptied history leaves nothing of the user's on disk at all — which is what "Clear History"
says on the tin.
