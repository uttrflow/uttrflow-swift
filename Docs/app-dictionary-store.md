# The personal dictionary store

`PersonalDictionaryStore` holds the words this user says that a general model would not expect.
`Docs/app-dictionary.md` covers the phonetics and the learning thresholds; this page covers the
store itself — where it lives, what it caches, and what each reset promises.

## Its own file, and an actor

The dictionary is its own file under Application Support, beside the history rather than inside
it: the two age differently, are reset by different buttons, and a user who clears their history
must not thereby forget how to spell their colleagues' names. The name is versioned so a shape too
different to read field by field can one day be introduced beside it rather than on top of it.

An actor, for the reason the history store gives: the writers are dictations that have already
finished and the readers are windows, so waiting should be a suspension and not a blocked main
thread.

## Why this store caches and the history store does not

The history is read when a window is drawn, so re-reading the file is cheap enough to buy the
certainty that the file is the only truth. This one is read on the hot path — once before every
dictation and again after it — and rebuilding a phonetic index from disk each time would put the
whole dictionary back into a cost the index exists to remove.

So the index is built once and thrown away by every write. The cache is the `PhoneticIndex` and
not the raw entries, because the index is what the hot path wants and caching the list would leave
the expensive half to be redone anyway. The price is that a user who edits the file in the Finder
while the app is running is not seen until the next write — a trade the history store could not
make and this one can.

The cache is dropped before a write is attempted rather than after it succeeds. A failed write
leaves the disk holding the old list, and an index rebuilt from that is right either way; dropping
it only on success would be one more state to be wrong about.

Reads answer with nothing when there is nothing readable there. Absent, unreadable, truncated,
hand-edited, or written by a build that knew a different shape all mean the same thing to a user,
which is that the app should still open: a dictionary that has forgotten everything makes dictation
slightly worse, and one that refuses to load makes it impossible.

## Sightings are never written down

Terms noticed on screen and said aloud, but not yet seen often enough to keep, live in memory and
never reach the file. Two reasons. The first is privacy: these words came off the user's screen and
most will never become entries, so a file of them would be a record of what they had open that no
page shows and no button clears. The second is the reset — this is the app's inference like any
other, and holding it inside the actor that owns `removeLearned()` is what makes it impossible to
forget to throw away.

## Adding

`add(_:)` replaces any entry with the same identifier and any *other* entry spelling the same word,
case-insensitively: "Kubectl" and "kubectl" are one word to the user and two rows in a settings
list is a bug they can see. The newcomer's spelling wins, since it is the one they just asked for.

`add(word:pronunciation:at:)` is where the editor's input is turned into an entry, so the trimming,
the empty-pronunciation rule and the origin are decided once. A blank pronunciation is stored as
absent rather than as an empty string: `soundsLike` falls back to the spelling when it is `nil`,
and an empty string would index the word under no sound at all — never found, with nothing to say
why.

It re-checks for an empty spelling and for a word already known even though the editor refuses both
before its button goes live. The editor judges from the list it last drew, and that list can go
stale while the editor is open now that a dictation finishing in another app can teach the
dictionary a word. Only the store's answer is current.

## Removing, and the three resets

**One word.** Removing an identifier that is not there is not an error: the caller asked for it to
be gone, and it is. Removing a word Uttrflow inferred also refuses it in the sighting ledger. It is
still in the window title and still being said, so clearing the tally alone would count it back up
to the threshold — three dictations later the deleted word reappears, which is the app arguing with
the person using it. Only inferred words are refused: a word the user typed in and then deleted is
theirs to change their mind about, and nothing would re-learn it anyway.

**Everything.** `removeEverything()` is the blunt instrument and takes the user's own words too.
`removeLearned()` is almost always the one they wanted.

**Everything inferred.** `removeLearned()` is the operation the rest of the design is insured by. A
dictionary that learns is a dictionary that can learn the wrong thing — a mis-heard name accepted
once and reinforced, a colleague's surname bound to a typo — and the honest answer to a poisoned
dictionary is to throw the inferences away. Throwing away the user's own words at the same time
would make the fix cost more than the fault, and they would stop using it.

Both `learned` and `observed` go, because both are the app's inference and the user cannot be
expected to know which of the two mechanisms guessed wrong. Only `added` survives. The half-counted
sightings go with the entries: a word that appeared one dictation after the user asked Uttrflow to
forget what it had worked out would make a liar of the button.

This is also why the dictionary is not capped in size the way the history is. The history trims
itself silently because nobody chose those records; here a silent trim would delete words a user
deliberately taught the app. The reset is the answer instead, and it is one they ask for and can
predict.

## Learning from a dictation

`learn(heard:wrote:seeing:at:)` is the part of the two automatic paths that needs a disk and a
memory of previous dictations, and it is deliberately the only part; the thresholds and their
reasons are in `LearnableWords` and `Docs/app-dictionary.md`.

`heard` is exactly what the recogniser produced, before anything rewrote it. The raw transcript and
not the finished text, because the question this path asks is what the user *said*, and by the end
of the pipeline the tidier and the snippets have both had a turn at changing it.

It is called after the words are on the user's screen and never before. A word earns its place by
surviving a dictation, and a dictation that failed to insert taught nobody anything.

Nothing is written when nothing is learnt, which is nearly every dictation. That guard is what
keeps the feature off the disk rather than merely off the hot path.

Words already in the dictionary are filtered out before the tally rather than after it, so a word
the user already has stops being counted at all rather than being counted forever and discarded at
the end. It also keeps either path from reaching `add(_:)`, which replaces an entry of the same
spelling and would reset the counters of a word the user typed in themselves.

A write that fails throws, and the caller drops it: the dictation is already over, and a lesson is
worth less than a notice about one.

## Retirement and restoring

Entries that have retired themselves are excluded from the lookup, so they can do no more harm, but
they are still listed. A user who is told a word has stopped being used and cannot then see it has
been told nothing useful.

`restore(_:)` clears the undo count rather than nudging it back below the threshold, because the
counters are evidence and evidence the user has overruled is not evidence any more. Leaving one
undo behind would retire the word again after a single further mistake, which is not what "Restore"
says on the button.

`timesUsed` deliberately survives. How often a word has been applied is a fact about the past the
user has not disputed, and it gives the restored word a longer leash rather than a shorter one:
`isTrustworthy` is a ratio, so a word restored at twenty uses can be undone nine times before it
retires again, where one reset to zero would be back inside the three-use grace period and could
retire on its fourth mistake.

Both counters go through one find-change-write path so they cannot drift into two different ideas
of what a missing entry means. Each answers with the entry as it now stands, so a caller sees the
moment a word retires itself rather than discovering it from a lookup that has quietly stopped
returning it; `nil` is what a caller holding a stale list should be told.
