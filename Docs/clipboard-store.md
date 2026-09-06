# The clipboard store

`ClipboardStore` is everything the user has copied, held on this Mac between launches. It is the
sibling of `DictationHistoryStore` and differs from it in exactly one way that matters: this one
keeps its list in memory as well as on disk.

## Why this one caches and the history store does not

The history store treats the file as the single source of truth, because a copy beside it can
disagree with a user who deleted it in the Finder. That reasoning holds for a list read when a
window is drawn, which happens rarely. This list is read on ⇧⌘V, which is the whole product: the
panel is opened dozens of times a day and the user is looking at the screen waiting for it.
Decoding five hundred records from JSON on that path buys certainty nobody asked for at a cost
everybody sees.

So the files are read once, lazily, and every read after that is a filter over an array already in
memory — no I/O, and no `await` that can block on a disk. Writes go to memory and to disk together,
so the two never drift while the app is running.

An actor rather than a lock, for the same reason the history store gives: nothing here is
real-time, a write is a whole-file rewrite, and the thread that asks most often is the main one.
An actor turns waiting into suspension.

## Two files, not one

`clipboard.v1.json` holds the history. `saved.v1.json` holds the clips the user named, filed or
pinned. Two files rather than one flag inside one file, because "saved" is a promise about
surviving and a shared file is shared fate.

Everything that can happen to the history — a truncated write, a half-finished sync, a hand edit,
a build that wrote a shape this one cannot read — happened to the aliases and pins too while they
shared a file, and reading answers an unreadable file with an empty list, so the loss became
permanent on the next ordinary ⌘C. Measured before the split: one damaged byte took a clip aliased
`/pgprod` with it, and the next copy wrote the emptiness down.

The saved file's path is derived from the history's rather than injected, so the pair travels
together: move or copy the folder and the clipboard arrives whole.

Answering an unreadable file with an empty list is itself why the two are separate. It is the
right answer for a history nobody promised to keep and the wrong one for a clip somebody named,
and one file cannot give two answers. Salvaging clip by clip is not attempted: our own writes are
atomic, so the realistic corruption is a whole file somebody mangled, and half a clipboard
restored is harder to explain than none.

### Migration from the single file

A clipboard written before the split has its saved clips inside the history file. They are
partitioned on the first read and written to their own file by the next ordinary write. Nothing
above the store can tell the difference, and a read that writes is a surprise nobody at the call
site would expect.

This is why `persistedSaved` exists. It records what the saved file is known to hold, as opposed
to what is in memory, and the two differ exactly once: after that first read, memory already holds
the saved clips and the saved file does not exist. Comparing the write against memory would decide
there was nothing to write, and the migration would never reach the disk.

## Which clips are the same clip

Two clips are the same thing when they carry the same thing: for text that is the text, for a
picture it is the bytes, compared by digest. A repeat moves the existing clip to the top rather
than adding a second row — without it, holding ⌘C over the same value while switching windows
fills the panel with one value and the panel stops being scannable.

Pictures were once exempt, because the only comparison was `text` and every picture's text is
empty, so matching on it made every screenshot the same clip as the last: the second replaced the
first, its file was orphaned, and the surviving row pointed at neither. Comparing the digest is
the fix. A picture with no digest — one stored before digests existed — never merges.

Matching happens only within one list. A sentence dictated and the same sentence copied out of a
document are two clips, not one thing that happened twice: merging them would move a row from one
tab to the other and add to a count that is supposed to mean "you reach for this often".

What survives a merge is everything the user did deliberately — the alias, the collection, the pin
— plus the identifier. The timestamp, the kind, the source, the language and the rich text come
from the new copy, because it genuinely was copied again, just now, from somewhere. Dropping the
language and the rich text is what once quietly hollowed out a clip: a Swift snippet lost its
language chip on the second copy and a formatted note lost its formatting, while the row looked
identical.

## Rebuilding a clip

`Clip.text` is `let` on purpose — a clip is what was on the clipboard — so editing one builds a
replacement carrying the same identity. Every field has to be named. Leaving one out returns it to
its default, which is how tidying a clip once reset `timesCopied` to one and made a clip the user
had reached for thirty times the cheapest thing in the history to evict. One helper does the
rebuild so there is one place for that obligation.

## Clearing versus resetting

"Clear clipboard" is a tidy-up and spares what somebody named, filed and pinned — those are the
clips a user would be most upset to lose and the ones they were least expecting that button to
touch. It once took them, because `save([])` wrote an empty list and an empty list is empty of
everything.

"Reset personalisation" says it puts Uttrflow back to a fresh install, and a fresh install has no
clips of any kind, so it is the one call that takes them. The two are separate calls so that
neither promise can be made by accident from the other's button. It matters more than it looks:
every finished dictation is written here as a second copy of the transcript, so a reset that
spared this file left every word the user had ever spoken on the disk after telling them it was
gone.

## Eviction

Anything kept survives unconditionally: it is exempt from the window and is not counted against
the cap. Not as a special case checked in three places, but absent from the candidate list
entirely — the `kept` pool has no tier, so there is no rule for it to be an exception to.

The history gets the window, then the per-pool count cap, then the memory quota, then the picture
disk budget. The cap is per pool for the reason the panel's two tabs exist: a morning of dictating
must not push out yesterday's ⌘C, and neither may push out a picture.

The two halves are recombined by filtering the original list rather than by concatenating them,
which keeps arrival order in one pass and without a sort.

**Least recently used, not fewest copies.** The rule this replaced was "fewest copies, then
oldest", and its known weakness turned out to be the common case rather than a corner: a value
copied twenty times last month outranked one pasted twice this morning, so the clip somebody had
leaned on all week was the first thing thrown away. `Clip.lastUsedAt` exists to make LRU possible,
and `markUsed` is what keeps it honest — without it, `lastUsedAt` would only ever be the arrival
time and the policy would be least-recently-*copied* wearing an LRU name.

**Memory and disk are weighed separately.** `weight(of:)` counts a clip's words and deliberately
not its picture. It once added `image.bytes`, which is the size of a file on disk the process has
never read, so the figure mixed two units and the memory quota it fed measured the wrong thing by
a factor of a thousand. A thousand screenshots is a gigabyte on disk and nothing at all in RAM
until somebody scrolls past them, so the disk is asked about separately.

The largest-clip bound is the one that actually stops the list growing; see
`Docs/clipboard-budget.md`. It is refused rather than truncated: half a log file is not a clip
anybody wants, and a history entry that silently differs from what was copied is worse than no
entry. What is lost is the row; the text is still on the system clipboard and still pastes.

## Pictures

The bytes live in an `Images` folder beside the clipboard file — beside rather than inside,
because the clipboard is one JSON document rewritten whole on every copy and a picture must never
be part of that write. The record in the clip carries only what a row needs to draw it.

A picture is hashed before it is written, so a screenshot copied twice costs a counter rather than
another file: about a megabyte saved every time somebody presses ⌘C twice on a Retina screenshot.
The digest is SHA-256 from CryptoKit, truncated to sixteen bytes because it is a cache key rather
than a signature — the file it names is beside it on the same disk, and a full digest doubles the
size of every picture row in a file rewritten on every copy.

The picture is written before the clip is recorded. A file with no clip is swept up later; a clip
with no file is a broken row for ever. That is also why writing a picture throws rather than
failing quietly, where nearly every other write here is best-effort.

A picture can vanish underneath the app — the folder is on disk and disks are shared with the user
— so reading one answers `nil`, which is the row's cue to say so rather than draw a blank.

### Orphans

`save(_:)` catches a file the moment it stops being referenced, which handles everything from the
point that check was written. It cannot handle what is already there: a build that leaked pictures
leaked them permanently, because no future write drops a name that was already absent from the
list. `sweepOnce(against:)` reconciles the folder once per launch to cover that.

It is skipped when the list is empty, and that is the whole safety of it. Reading answers with
nothing for a file that is missing, truncated or written by another build — so an empty list is
not evidence that the user has no pictures, and sweeping on one would delete every picture they
have over a bad read.

The sweep in `save(_:)` runs only when a file stops being referenced, so an ordinary text copy —
which is nearly every write — never pays for a directory scan. Earlier the sweep documented itself
as running after the retention pass and was in fact called from nowhere, so every picture whose
clip was deleted or aged out stayed on disk for ever; four had accumulated in a morning's testing.

## Ordering

The store answers in arrival order, newest first, and the panel decides where pinned rows are
shown — that is a presentation question and two answers to it would disagree. A new clip is
prepended rather than sorted in, because the clock belongs to the caller and a machine whose clock
moved must not be able to shuffle what the user is shown.

Merging the two files uses a two-way merge rather than a sort, and that is not a
micro-optimisation: each list is already in arrival order, and a merge keeps both of those orders
intact where a sort is free to reorder equal timestamps differently on each call. The panel counts
rows, so two draws of an unchanged clipboard disagreeing about which one is third is the one thing
this cannot do.

## What fails quietly and what does not

Memory is updated first and unconditionally, so a disk that refuses does not also cost the user
the pin they just set for as long as the app stays open. The error still reaches them: what they
lose is the change surviving a quit, not the change.

`markUsed` is the one write allowed to fail silently — it is bookkeeping for a future eviction,
and refusing somebody's paste because the note about it could not be filed would trade the thing
they asked for against the record of it. Dropping aged-out clips on the read path is best-effort
for the same reason: refusing to open the panel over a disk that would not accept a tidy-up would
punish the user for something they cannot fix, and nothing they were told is gone comes back on
screen either way.

Writes are atomic, so a crash or a full disk cannot leave behind a truncated file that the next
read would have to throw away. An empty list removes the file rather than writing `[]`, so an
emptied clipboard leaves nothing of the user's on disk at all.
