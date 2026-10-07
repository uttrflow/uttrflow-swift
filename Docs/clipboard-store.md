# The clipboard store

`ClipboardStore` in `Sources/UttrflowClipboard/ClipboardStore.swift` is everything the user has
copied, held on this Mac between launches: two JSON files and an `Images` folder under
Application Support. It is the sibling of `DictationHistoryStore` and differs from it in exactly
one way that matters: this one keeps its list in memory as well as on disk. What it may cost is
in [`clipboard-budget.md`](clipboard-budget.md); when a clip ages out is in
[`retention-clock.md`](retention-clock.md).

| File | Holds |
| --- | --- |
| `clipboard.v1.json` | the history: every clip nobody named, filed or pinned |
| `saved.v1.json` | the clips the user named, filed or pinned; its path is derived from the history's |
| `Images/` | picture bytes, beside the history file |
| `<name>.unreadable-<seconds since 1970>` | a file that could not be read, set aside |

Each index payload is a versioned object, `{"version":2,"clips":[...]}`. The released bare
`[Clip]` array is decoded as version 1 and upgraded after both indexes have been inspected, so a
future-format sibling cannot be overwritten during migration. A payload newer than this build
stays at its original path and makes clipboard changes read-only; the app explains that an update
is needed. An encrypted-file envelope version newer than this build is also left untouched and makes
clipboard changes read-only; because the payload cannot be opened, its clips cannot be displayed
until the app is updated. Neither unsupported version is set aside or rewritten. A supported-version
payload with an unrecognised JSON key is also refused for writing, so a newer field cannot be lost
when this build rewrites an index.

These are local working memory, not backup material. The folder and every file written through
`PrivateFile` are marked `isExcludedFromBackup`, so backup tools that honour Finder's exclusion
flag skip clipboard text, saved clips and copied pictures. JSON indexes and picture bytes are
encrypted with the shared device-only Keychain key (`EncryptedStore`); picture file names remain
visible. A plaintext file from an older build is sealed in place when it is read
(`migrateLegacyImagesOnce` for pictures). The first list read schedules the picture pass in the
background; it reads only the envelope header of each regular PNG and opens the full file only for
an unsealed legacy picture that needs migration. This pass can also migrate pictures beside an
unreadable index, so index recovery does not control whether old picture bytes are protected.

## Why this one caches and the history store does not

The history store treats the file as the single source of truth, because a copy beside it can
disagree with a user who deleted it in the Finder. That reasoning holds for a list read when a
window is drawn, which happens rarely. This list is read on ⇧⌘V: the panel is opened dozens of
times a day and the user is looking at the screen waiting for it. Decoding five hundred records
from JSON on that path buys certainty nobody asked for at a cost everybody sees.

So the indexes are read once, lazily, and every list read after that is a filter over an array
already in memory. `clips(keeping:)`, the read ⇧⌘V waits on, does no picture-folder scan or full
picture read; the first load schedules the bounded-header migration separately. Writes go to
memory and to disk together, so the two never drift while the app is running.

An actor rather than a lock, for the same reason the history store gives: nothing here is
real-time, a write is a whole-file rewrite, and the thread that asks most often is the main one.
An actor turns waiting into suspension.

## Two files, not one

Two files rather than one flag inside one file, because "saved" is a promise about surviving and
a shared file is shared fate. Everything that can happen to the history (a truncated write, a
half-finished sync, a hand edit, a build that wrote a shape this one cannot read) would happen to
the aliases and pins too, and reading answers an unreadable file with an empty list, so one
damaged byte would take every named clip with it and the next ordinary ⌘C would write the
emptiness down. An empty answer is right for a history nobody promised to keep and wrong for a
clip somebody named, and one file cannot give two answers.

The saved file's path is derived from the history's rather than injected, so the pair travels
together: move or copy the folder and the clipboard arrives whole.

If a clipboard index cannot be read, the store first tries its previous sealed generation. A
valid backup is restored durably and the app tells the user once; otherwise the unreadable file
is renamed aside before a new empty file can be written. The app tells the user once where that
preserved copy is. A file that cannot be moved aside is left where it is, and every write to it
is refused. `LocalStore.read(_:from:)` distinguishes a missing file from one that is present but
cannot be read: permission denied, truncated, or empty. A valid payload from a newer schema is
handled separately: it stays at its original path, is not set aside, and blocks writes to either
index until a compatible build opens it. Readable clip rows are shown when the newer payload has
the known `clips` field.

### Moving a clip between the files

Pinning, filing or naming a clip moves it into the saved file; taking the last of those off moves
it back. Each move writes the clip's destination before the file it is leaving, so a disk that
refuses either write leaves at least one durable copy. Unpinning therefore writes the history
first, while the saved file still holds the old copy, and only then rewrites the saved file.

A move refused between its two writes leaves the clip in both files. Reading keeps the saved
file's copy and drops the history's, so reopening finds exactly one clip, and the next write that
succeeds removes the stale copy from the history.

A history file that still holds saved clips is partitioned on the first read, and the saved clips
are written to their own file by the next ordinary write. `savedOnDisk` records what the saved
file is known to hold, as opposed to what is in memory; comparing the write against memory would
decide there was nothing to write, and the saved clips would never reach the disk.

## Which clips are the same clip

Two clips are the same thing when they carry the same thing: for text that is the text, for a
picture it is the bytes, compared by digest. A repeat moves the existing clip to the top rather
than adding a second row; without it, holding ⌘C over the same value while switching windows
fills the panel with one value and the panel stops being scannable. A picture with no digest
never merges.

Matching happens only within one list. A sentence dictated and the same sentence copied out of a
document are two clips, not one thing that happened twice: merging them would move a row from one
tab to the other and add to a count that is supposed to mean "you reach for this often".

What survives a merge is everything the user did deliberately (the alias, the collection, the
pin) plus the identifier. The timestamp, the kind, the source, the language and the rich text come
from the new copy, because it genuinely was copied again, just now, from somewhere; dropping the
language or the rich text would hollow out a clip while its row looked identical.

One exception to the kind: a kept clip (pinned, named or filed) that is on disk keeps its kind and
language when the same text arrives again classified as a secret. A secret is never written to
disk, so taking the arrival's kind would delete the one clip the store promises never to age out,
and the text was already on disk and shown in the panel under the user's own decision to keep it.
A clip that is not kept still becomes a secret and leaves the disk.

The rich text comes from the new copy only when the new copy carries some. A plain copy of the
same text keeps the clip's rich text, because that may be a note the user wrote or promoted in the
panel, checklist state included, and a plain copy has nothing to replace it with.

## Rebuilding a clip

`Clip.text` is `let` on purpose (a clip is what was on the clipboard), so editing one builds a
replacement carrying the same identity. Every field has to be named; leaving one out returns it to
its default, and a `timesCopied` reset to one would make a clip the user had reached for thirty
times the cheapest thing in the history to evict. One helper does the rebuild so there is one place
for that obligation.

## Undoing a delete

Undo restores a clip's alias only when no current clip holds it. If another clip took that alias
while the deleted clip was absent, the newer holder keeps it and the restored clip returns unnamed.
`restoreReportingAliasConflict` returns that conflict with the settled list so the panel can tell
the user after the store write succeeds; `restore` keeps returning only the settled list.

Deleting a collection and its clips uses the same eight-second undo offer as deleting one clip. The
offer restores all clips removed with that collection together, including their saved pins and
collection name. Each alias follows the conflict rule above.

A restored clip also comes back to the place it held: its persisted order is untouched, so the
list sorts it back where it was.

## Forgetting

| Store call | What it removes | Used by |
| --- | --- | --- |
| `deleteEverything(keeping:)` | the history and its set-aside copies; spares every named, filed and pinned clip and the saved file's set-aside copies | the store's API for clearing the history |
| `forgetEverything()` | every clip, pinned ones included, and both files' set-aside copies | "Reset personalisation" (`SettingsReset.everything`, target `.clipboard`) |

Clearing is a tidy-up and spares what somebody named, filed and pinned, the clips a user would be
most upset to lose. "Reset personalisation" says it puts Uttrflow back to a fresh install, and a
fresh install has no clips of any kind, so it is the one call that takes them. The two are
separate calls so that neither promise can be made by accident from the other's button. It
matters more than it looks: a dictation kept as a clip is a second copy of the transcript in this
file, so a reset that spared it would leave the user's words on disk after telling them they were
gone.

Dictations remain in History unless the user chooses **Keep as clip** on a History row; dictating
alone does not add a clipboard item.

## Eviction

Anything kept survives unconditionally: it is exempt from the window and is not counted against
the cap. Not as a special case checked in three places, but absent from the candidate list
entirely: the `kept` pool has no tier, so there is no rule for it to be an exception to.

The window is `RetentionWindow`, shared with the history and the recordings, and it is asked two
questions rather than one: whether a clip may still be shown, and whether this clock may be
believed to delete it. They differ only for a clip the window has passed on a clock too far ahead
of it to be believed, which is hidden but left on the disk; see
[`retention-clock.md`](retention-clock.md).

The history gets the window, then the per-pool count cap, then the memory quota, then the picture
disk budget. The cap is per pool for the reason the panel's two tabs exist: a morning of dictating
must not push out yesterday's ⌘C, and neither may push out a picture. The two halves are
recombined by filtering the original list rather than by concatenating them, which keeps arrival
order in one pass and without a sort.

**Least recently used, not fewest copies.** "Fewest copies, then oldest" is not used because its
weakness is the common case: a value copied twenty times last month would outrank one pasted twice
this morning, so the clip somebody leaned on all week would be the first thrown away.
`Clip.lastUsedOrder` ranks eviction, while `Clip.lastUsedAt` records when the use happened.
`markUsed` moves the clip to the top of its history or saved pool by that order, even when the wall
clock moves backward.

**Memory and disk are weighed separately.** `weight(of:)` counts a clip's words and deliberately
not its picture: `image.bytes` is the size of a file on disk the process has not read, so adding it
would mix two units and make the memory quota measure the wrong thing by a factor of a thousand. A
thousand screenshots is a gigabyte on disk and nothing at all in RAM until somebody scrolls past
them, so the disk is asked about separately (`withinDisk`).

The largest-clip bound is the one that stops the list growing; see
[`clipboard-budget.md`](clipboard-budget.md#the-largest-clip). It is refused rather than truncated:
half a log file is not a clip anybody wants, and a history entry that silently differs from what
was copied is worse than no entry. What is lost is the row; the text is still on the system
clipboard and still pastes.

## Pictures

The bytes live in the `Images` folder beside the clipboard file, beside rather than inside,
because the clipboard is one JSON document rewritten whole on every copy and a picture must never
be part of that write. The record in the clip carries only what a row needs to draw it.

A picture is hashed before it is written, so a screenshot copied twice costs a counter rather than
another file. The digest is SHA-256 from CryptoKit, truncated to sixteen bytes because it is a
cache key rather than a signature: the file it names is beside it on the same disk, and a full
digest doubles the size of every picture row in a file rewritten on every copy.

The picture is written before the clip is recorded. A file with no clip is swept up later; a clip
with no file is a broken row for ever. That is also why writing a picture throws rather than
failing quietly, where nearly every other write here is best-effort.

A picture can vanish underneath the app (the folder is on disk and disks are shared with the
user), so reading one answers `nil`, which is the row's cue to say so rather than draw a blank.

### Who owns the file

`save(_:)` owns a picture's lifetime. It takes the difference between the names the previous list
held and the names the new one holds, which catches a file the moment it stops being referenced (a
delete, the retention window, a reset) but cannot see a file that was referenced by neither. A
picture is written before its clip is recorded, so a clip dropped on arrival, such as a new
screenshot the disk budget evicts at once, leaves a file that appears in no list at all.
`keep(_:forClip:width:height:sha:)` therefore records what it has put on disk, and the next write
accounts for it: kept when the list names it, deleted when the list does not, whether or not the
index write itself lands. One rule covers every path that can drop a clip, because the difference
and the file just written are reconciled in the same place.

A refused index write is the one case where the file stays: the clip is in memory whatever the
disk said, the panel can still draw its row, and a picture deleted under a visible row is the
broken row this whole ordering exists to prevent. Nothing on disk names it, so the next launch
sweeps it.

### Orphans

`save(_:)` cannot reach a file no list has ever named, and never runs a directory scan.
`sweepOnce()` reconciles the folder once per launch, when the store first loads.

A picture is an orphan only when every file that can name one was read. So the sweep is skipped
when either file was unreadable at this launch, and on every later launch while a set-aside file
sits beside it. It is not skipped merely because the list is empty: with only the saved file
damaged the history still holds clips, so emptiness is not the test of a bad read, and a store
whose every clip had been evicted could otherwise never reconcile at all. Skipping leaks at worst;
sweeping on a bad read destroys. Once the set-aside file is restored or removed, the next launch
sweeps again.

## Ordering

The store answers in most-recently-used order, and the panel decides where pinned rows are shown;
that is a presentation question and two answers to it would disagree. A new clip is prepended, and
using a clip moves it to the top of its history or saved pool. The persisted `lastUsedOrder` is
monotonic, so a machine whose clock moved cannot shuffle what the user is shown.

Merging the two files uses a two-way merge rather than a sort: each pool is already in use order,
and a merge keeps those orders intact. Equal use orders retain their copied-time order, so two
draws of an unchanged clipboard agree about which row is third.

## What fails quietly and what does not

Memory is updated first and unconditionally, so a disk that refuses does not also cost the user
the pin they just set for as long as the app stays open. The error still reaches them: what they
lose is the change surviving a quit, not the change.

`markUsed` does not write at all. It moves the clip in memory and the next real write (a copy, a
pin, a delete) carries it to disk; with no other write, `flushUse` writes it after `useFlushDelay`
(30 seconds), and quitting writes it before the process exits. A paste therefore costs no rewrite
of the history file. If the app is killed before any of those, the uses since the last write are
lost, and all that costs is an eviction order that many seconds stale: no clip, pin or name is
ever held back this way. A collection is renamed, emptied or deleted by one store call
(`moveCategory`, `deleteCategory`), which is one write per file however many clips it holds.

A held use is the one write allowed to fail silently: it is bookkeeping for a future eviction, and
refusing somebody's paste because the note about it could not be filed would trade the thing they
asked for against the record of it. Dropping aged-out clips on the read path is best-effort for the
same reason: refusing to open the panel over a disk that would not accept a tidy-up would punish
the user for something they cannot fix, and nothing they were told is gone comes back on screen
either way.

Index writes flush the temporary file and containing folder around their atomic replacement.
Each successful encrypted write also keeps the previous sealed generation as `.bak`; an empty
list removes both files rather than writing `[]`, so an emptied clipboard leaves no recoverable
index behind. If the live index is missing, an orphan backup is ignored and removed before the
first new generation is written. Reset removes and flushes the backup before removing the live
index, so an interrupted reset cannot restore an older generation over the current one.

The legacy-array test data is synthetic and representative, not an authentic user's clipboard file.
The released `v26.0926.0` writer persisted arrays with `JSONEncoder().encode(clips)`; a test
constructs a synthetic clip and runs that encoder call to prove the released payload shape migrates.
Real clipboard files are excluded from fixtures to avoid committing user content.
