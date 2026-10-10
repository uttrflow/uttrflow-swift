# The personal dictionary store

`PersonalDictionaryStore` (`Sources/UttrflowDictionary/PersonalDictionaryStore.swift`) holds the
words this user says that a general model would not expect. `Docs/app-dictionary.md` covers the
phonetics and the learning thresholds; this page covers the store itself — where it lives, what
it caches, and what each reset promises.

## Its own file, and an actor

The dictionary is its own file under Application Support, `dictionary.v1.json`, beside the
history rather than inside it: the two age differently, are reset by different buttons, and a user
who clears their history must not thereby forget how to spell their colleagues' names. The name is
versioned so a shape too different to read field by field can be introduced beside it rather than
on top of it. The app writes it through `EncryptedStore`, as it does the history and the snippets
(`Docs/local-store-encryption.md`).

An actor, for the reason the history store gives: the writers are dictations that have already
finished and the readers are windows, so waiting should be a suspension and not a blocked main
thread.

## What it caches

The store is read on the hot path — once before every dictation and again after it — and
rebuilding a phonetic index from disk each time would put the whole dictionary back into a cost
the index exists to remove. Two caches answer that. `CachedStoredList` holds the decoded entries
and reads the file again only when its stamp — inode, size and modification time — differs from
the one it was read at, so an edit made to the file outside the app is seen on the next read.
`index()` keeps the `PhoneticIndex` built from those entries and rebuilds it only when the list's
`generation` has moved. A successful write hands the cache what it wrote; a failed one makes it
forget, so the next read goes back to the disk. `index(in:)` answers for one application: the whole
index while no entry is confined, otherwise one built from the entries `DictionaryEntry.applies(in:)`
admits, kept for the application last asked about.

An entry may list the applications it is offered in (`DictionaryEntry.applications`), chosen in the
editor; empty, and every entry from before the list existed, means everywhere. Correction reads
`index(in:)` for the dictation's application and the recogniser's word list (`WorkingSet.words`)
leaves out entries confined elsewhere. `index()` stays whole, so the clean-up's guard still
protects a confined word's spelling wherever it appears.

Reads answer with nothing when there is nothing readable there. Absent, unreadable, truncated,
hand-edited, or written by a build that knew a different shape all mean the same thing to a user,
which is that the app should still open: a dictionary that has forgotten everything makes dictation
slightly worse, and one that refuses to load makes it impossible. The unreadable file is renamed
aside first, as the history store describes (`Docs/history-store-file.md`), and a write is refused
while the store holds an unreadable read, so the next word added cannot write over the only copy.

A structurally valid entry can still carry a counter outside the domain the rest of the type
assumes: negative, or absurdly large from a hand edit. `DictionaryEntry`'s decoder clamps
`timesUsed` and `timesReverted` into zero through `DictionaryEntry.maximumCount` on the way in, so
ranking, the phonetic index and both counters' own arithmetic can never overflow; everything else
about the entry decodes untouched.

## Sightings are written down only as keyed hashes

Terms noticed on screen and said aloud, but seen on too few days to keep, are written to the
encrypted evidence ledger (`Docs/learned-state.md`) as `sighting` rows: a keyed hash of the
lowercased term and the day number, never the term. The hash is an HMAC under a key derived from
this installation's store key (`EncryptedStore.digest(of:for:)`), so the file cannot be matched
against a word list without the key, and the term is known again only when it is next spoken and
seen. Rows live under History's retention and go with every reset: learning, removing a pending
term, refusing it and `removeLearned()` each append rows that cancel its days. Without the key a
term is not counted at all rather than counted in the clear.

## Adding

`add(_:)` replaces any entry with the same identifier and any *other* entry spelling the same word.
Spelling identity ignores case and spaces but retains `+`, `#`, `&`, `.`, `/` and `-`, so "Open AI"
and "OpenAI" are one entry while "C++", "C#" and "C" remain distinct. The newcomer's spelling
wins, since it is the one they just asked for.

`add(word:pronunciation:at:)` is where the editor's input is turned into an entry, so the trimming,
the empty-pronunciation rule and the origin are decided once. A blank pronunciation is stored as
absent rather than as an empty string: `soundsLike` falls back to the spelling when it is `nil`,
and an empty string would index the word under no sound at all — never found, with nothing to say
why.

## An address for every entry

`WordSound` reads nothing but Latin letters, so a spelling written in
Devanagari, CJK, Cyrillic or digits alone has no sound key — and an entry with no key is never
looked up, offered or learnt from, with nothing to say why.

`PronunciationCoder` is what the index keys on. It asks `WordSound` first, and where that
is silent it keys the spelling itself, folded for case and accents with marks dropped. So such a
word is matched *exactly* rather than not at all, which is the honest ceiling for a script the coder
cannot speak: the recogniser has to produce the same spelling. A pronunciation still beats both, and
the editor says so — where a spelling has no English letters and the pronunciation is blank, the
hint tells the user what it costs instead of advising them to leave it blank.

`PhoneticIndex.unaddressable` keeps whatever it could not file at all, which is now only a spelling
with no letter and no digit anywhere in it. The list exists so that the next gap in a coder is
visible rather than silent, and a test asserts every entry is found by its own spelling across seven
scripts.

`add(word:pronunciation:at:)` re-checks for an empty spelling and for a word already known even
though the editor refuses both before its button goes live. The editor judges from the list it last
drew, and that list can go stale while the editor is open, because a dictation finishing in another
app can teach the dictionary a word. Only the store's answer is current. An entry of more than
`PhoneticIndex.maximumWordsPerEntry` (three) words is refused.

## Removing, and the three resets

**One word.** Removing an identifier that is not there is not an error: the caller asked for it to
be gone, and it is. Removing any word also refuses it in the sighting ledger. It is still in the
window title and still being said, so clearing the tally alone would count it back up to the
threshold — three dictations later the deleted word reappears, which is the app arguing with the
person using it. That holds for a word the user typed in as much as one Uttrflow inferred: the
sighting path does not care how a word first arrived, only whether it is on disk and refused. The
refusal binds only inference — typing the word in again adds it as before.

The refusals are written to `dictionary.v1.refused.json` beside the dictionary, oldest first
and capped at the ledger's 512 (`SightingLedger.maximumRefused`), so a relaunch still refuses a word
deleted before it. They are words the user already had in the dictionary and chose to remove, not
terms read off the screen. `removeEverything()` deletes the record; `removeLearned()` keeps it. The
personal data archive carries the record to another Mac, where `importRefusals(_:)` adds it after
that Mac's own refusals (`Docs/personal-data-archive.md`).

**Not learning.** The record is not hidden: `refusedWords()` lists it newest first, in the
user's own spelling, and the Dictionary page shows it under a "Not learning" disclosure with
Allow again on each row. `allowAgain(_:)` is the inverse of a deletion: it lifts the refusal from
the ledger and rewrites the record, after which three days of sightings teach the word as before.

**Several words.** `remove(_:)` also takes a set of identifiers and is the one removal path: one
word is a set of one. Every word in the set is refused, and the refusals and the dictionary are
each written once. Past the 512 cap the oldest refusals lapse first, so a batch larger than the cap
keeps the newest 512 refused. On the Dictionary page each row has a checkbox; Delete selected sends
the ticked rows still listed to `remove(_:)` in one call, and Restore selected sends the ticked
retired ones to `restore(_:)`. A ticked row that the search or a filter hides is left alone.

**Everything.** `removeEverything()` is the blunt instrument and takes the user's own words too.
It also removes the seed record and the refusals, so the next launch offers the shipped words as
on a fresh install. If either record cannot be removed, the reset reports a write failure.
`removeLearned()` keeps the seed record and individual deletions in force.

**Everything inferred.** `removeLearned()` is the operation the rest of the design is insured by. A
dictionary that learns is a dictionary that can learn the wrong thing — a mis-heard name accepted
once and reinforced, a colleague's surname bound to a typo — and the honest answer to a poisoned
dictionary is to throw the inferences away. Throwing away the user's own words at the same time
would make the fix cost more than the fault, and they would stop using it.

Both `learned` and `observed` go, through the same `remove(_:)`, so every one of them is refused
and the same sightings do not bring it back. Both go because both are the app's inference and the user cannot be
expected to know which of the two mechanisms guessed wrong. `added` survives, and so does
`shipped`: a word this build was born knowing was inferred from nothing on this Mac, so there is
nothing about it to forget. Deleting it one row at a time is still the user's to do, and it stays
deleted — see the section below. The half-counted
sightings go with the entries, cancelled in the evidence ledger: a word that appeared one day after the user asked Uttrflow to
forget what it had worked out would make a liar of the button.

Only the inferred entries are capped. At most `maximumInferredEntries` (256) `learned` and
`observed` entries are kept on every write, the strongest first — most uses
net of undos, then the most recently first seen, then alphabetical. Words the user added and words
the build shipped are never trimmed: a silent trim there would delete words a user deliberately
taught the app.

## The words the build ships knowing

An empty dictionary cannot help with the word most likely to be dictated while somebody writes
*about* this product — its own name. `ShippedWords` holds the list (one word, "Uttrflow"),
`PersonalDictionaryStore.seedShippedWords(at:)` writes it, and `AppDelegate` calls that once per
launch, off the launch's own path.

Matching is by sound, so one entry covers a family: "Uttrflow", "utter flow", "utterflow",
"otter flow" and "udder flow" all carry one sound key (a vowel, then T, R, F, L), so any of them resolves
to the shipped spelling. That is also the limit of what seeding buys — a mishearing that codes to
something else is not reached by it, and the fix for those is a different mechanism, not a longer
list.

The seeding is recorded in `dictionary.v1.seeded.json` beside the dictionary, holding the
version of the list last applied and every shipped spelling ever offered. Two things follow, and
both are deliberate: a word the user deletes does not reappear on the next launch, and a later build
that adds a word seeds only that word, because each earlier spelling is already listed as offered
and stays deleted if the user deleted it. A record that names only a version, from before spellings
were listed, counts as having offered the version 1 list.
The record is named after the dictionary file, so two dictionaries in one directory never share it.
If the record is present but unreadable, seeding stops without changing the dictionary or replacing
the record. Launch logs the failure so the damaged marker can be diagnosed; only an absent record
is treated as a new dictionary.

The record is written after the words, never before. If the dictionary write fails, nothing is
recorded and the next launch seeds again; if the record write fails after the words landed, the
next launch finds them already there and only writes the record. A word the user deletes in that
one window, before any launch has managed to write the record, comes back once — the price of
never marking a seed done that did not happen.

**Be conservative about adding to this list.** A shipped dictionary that is too eager rewrites
words the user meant, which is worse than not knowing them: every entry here is applied by sound to
every user, and none of them asked for it. The product's own name earns its place because the
product is what its users write about.

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

## Provisional words

A word learned from a selection dictation came from text Uttrflow wrote, so nothing yet says the
user wanted it. It is provisional until `DictionaryEntry.promotionUses` later uses land without an
undo. While provisional it ranks below every settled entry in the prompt, so it is never the word
the recogniser is pointed at first, and a single undo removes it through `remove(_:)`, which also
refuses the spelling so the same lesson is not learned again. Added, observed and shipped words are
never provisional, and their retirement is the ratio below.

A provisional word the user replaces by hand is vetoed the same way. `EditAway.editedAway` compares
what a dictation inserted with what the field reads later, and names each applied word that is gone
while the words on both sides of it are still there; a cleared or rewritten field names nothing. The
caller sends each one through `recordRevert(of:)`, the one undo path. In the app, `EditAwayWatch` is that caller:
after a dictation that wrote a provisional word lands, it reads the focused field through
`FocusedFieldReader`, reads it again `EditAwayWatch.window` (10 seconds) later, and judges only when
both reads name the same field; any other field, or a field it cannot read, vetoes nothing.

The count is fitted on the learning simulator ([learning-simulator.md](learning-simulator.md)),
`swift test --filter LearningDynamicsSimulatorTests`, across all four edit models. Recency is the
other constant: `WorkingSet.recencyHalfLifeInDays`, 30 days.

| Promotion uses | Harmful entries still provisional at their first undo | Real terms promoted by week 8 |
|---|---|---|
| 1 | 0/0 | 27/27 |
| 3 (chosen) | 0/0 | 27/27 |
| 6 | 0/0 | 27/27 |

No harmful entry is applied in the replay, so harm does not separate the counts; every real term
survives 8 clean uses, so any count up to 8 promotes all of them. Three matches `isTrustworthy`'s use
floor and leaves a misspelt word one undo or one edit from removal through its first three uses. The
test fails if a harmful entry is first undone after promotion or a kept term never reaches the count.

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

A dictation's uses go through the same path as one batch: `recordUse(of:)` given a list changes
every entry in it that is still there and writes the file once, and writes nothing at all when
none of them is. The counts are on disk before the call returns, so nothing is held in memory for
a crash or a quit to lose; a write the disk refuses counts none of the batch.

An entry is applied two ways, and both report into that batch. The correction engine writes a
spelling itself and names its entry on the `DictationCorrection`; the doubtful-word line offers the
spelling to the model, which may or may not write it. `DictionaryCandidates` keeps the entry on the
`Reading` it offers, `MeaningPreservationGuard.readingsTaken` reads off the same alignment the
verdict used which reading was written where the run stood, and the pipeline counts those entries
beside the corrections' — once per dictation whichever path used an entry, or both. A reading that
differs from the heard words only in its capitals is not counted: "Claude" for "claude" is what a
sentence does to its first word whatever the dictionary holds, so the capital is no evidence the
model chose the entry. Such an entry is still counted when the correction engine applies it.

A third way leaves no rewrite at all: the vocabulary prompt makes the recogniser spell the entry
right, so nothing corrects it. `timesUsed` therefore means "appeared in a landed dictation", not
"was rewritten into one". After the words land, the pipeline hands the counter the text it wrote,
and `DictionaryAppearances.used` adds every entry whose spelling stands in that text as whole words,
by the same boundary test the guard uses (`MeaningPreservationGuard.isWritten`), never a prefix or
substring: "Orvanta" inside "Orvantasoft" is not counted. Each entry still counts once per
dictation, whichever routes used it. Without this, a word the prompt helps most is counted least,
leaves the working set once its unused lifetime passes, and comes back only after the recogniser
misspells it again. Words sent to a secure field, or shaped like a credential, count nothing. Undo is unchanged: an
undone dictation is one appearance and one revert, so the ratio retires a word the user keeps
undoing exactly as before.

Undo does not charge a taken reading. A taken reading is not a `DictationCorrection` — it has no
word range in what was heard, because the model rewrote the sentence around it — so History has
nothing to put back, and `timesReverted` only moves for corrections. An entry used only through the
doubtful-word line therefore cannot retire itself, and the recourse is the one above: delete the
row, or remove learnt words.

## Related pages

- `Docs/app-dictionary.md` — the phonetic index and the learning rules.
- `Docs/personal-data-archive.md` — exporting and importing the dictionary.
- `Docs/history-store-file.md` — the shared file-handling rules this store follows.
