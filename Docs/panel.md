# The clipboard panel

`PanelPresenter` is pure and is the only place that decides what the panel says. The
view draws exactly that, so the highlight, the mask over a secret and the words under the
list cannot tell three different stories about the same moment.

## Chips, and the way out of a collection

The kind filters and the collections share one row, and that row already begins with an
**All** meaning every *kind*. So there is **no second All for collections** — two chips a
few points apart both reading "All" and meaning different things reads as a bug rather
than a choice. Drawing one only while a collection was chosen just moved the confusion to
the moment somebody was looking at it.

The way out of a collection is **the collection itself, pressed again**
(`PanelCategoryChip.chosen` answers 1 — everything — when the chip is already active).
⌘1 means everything and clears the kind as well, or "show me everything" would leave a
filter on.

**A shortcut and a position are different numbers.** The shortcut is what is *printed*
and stops at the ninth, because there is no ⌘10 and printing a shortcut that does not
work is worse than printing none. The position is what pressing the chip *means*, and
does not stop. Reusing one for the other made every collection past the ninth send 0,
which the snapshot rejects — so the tenth chip drew like the others, said nothing about
being different, and did nothing when clicked.

**While there is a query, the active chip is All** — unless a kind chip (Text, Links, Code,
Images) is on. That is the one narrowing a search keeps: the kind chip stays lit, and an empty
search says "Nothing under Code mentions …" and points at All, rather than claiming the whole
clipboard was searched (#899). A search otherwise spans every collection and every tab, so drawing the open tab as chosen would tell the user their search had been
narrowed when it had not, and the rows from elsewhere would read as a bug. The snapshot
keeps its collection regardless — this is only what is *shown*, and emptying the field
brings it back.

## Masking

The mask is **twelve bullets, not one per character**. The length of a token is worth
something to whoever is looking over the user's shoulder, and a mask that leaks it only
pretends to work.

A masked row also loses its excerpt, its language chip and its tooltip:

- the **excerpt** would print the part of the secret the user searched for;
- the **language chip** is one more thing on a row whose whole point is to say as little
  as possible until asked;
- the **tooltip** exists to give back what a row had to cut, and a masked row cut nothing
  the pointer is entitled to. A panel of bullets appearing under the cursor reads as the
  mask being lifted.

The checklist count is withheld too: how much of a hidden thing is done is still something
about it, and the masking rule is to say as little as possible until it is revealed.

Search does not read a masked secret's text either. A row that appeared under "Contents"
for a typed fragment would confirm the fragment is inside the hidden value, so until it is
revealed a secret is found only by its alias or its collection.

## Empty states, and being specific and wrong

There are four different nothings, and the sentence is **assembled from the narrowings
that are actually on** rather than picked from the first one that matches.

Picking the first is how the panel came to say *"Nothing in db — nothing you have copied
is filed here"* while the Code filter was also on: there were clips in db, and the
sentence said there were not. **An empty state that names one of two reasons is worse
than a vague one, because it is specific and wrong.** This file has been corrected for
that class of error three times, on three different axes.

The related trap: *"Nothing copied yet"* over a full clipboard. Pinning and filing both
take a clip out of the arrivals tabs, so somebody who keeps a tidy clipboard reaches an
empty History with fifty clips in the panel. And since a search now spans what Uttrflow
made as well, *"nothing you have copied"* told a user with nothing but dictations that
their search had looked somewhere it had not.

The third nothing on the same axis: **a list that has not been read yet**. The window is shown
and made key before the store is asked for anything (see `Docs/app-quick-panel.md`), so for the
moment in between the panel holds no clips and has no idea whether there are any. Saying
*"Nothing copied yet"* there would be the same specific-and-wrong error, this time against a
clipboard nobody has looked at. `PanelSnapshot.isAwaitingList` marks that moment, and the
presenter says nothing about emptiness and offers nothing to keep until the list arrives: an
unread list is an unknown, not a nothing.

## The line under the list

Precedence: the sheet's keys, then the undo offer, then the empty state's reason, then
the gesture.

A sheet wins whenever one is open, because its keys are what the focused field actually
obeys: teaching **⌘Z** over a field where Return saves and `esc` backs out would be the
wrong key, and the undo offer being merely hidden costs nothing — the clip is not gone,
only the sentence that says so.

Outside a sheet, the undo wins while it is live because it expires in seconds. Press
**⌘Z** while the offer is visible to restore the deleted clip. It is **offered, not merely
available** — F7 trades the confirmation dialog away *for* that undo, so an undo nobody is
told about turns the trade into a loss: the clip is gone with neither a question beforehand
nor a way back.

While a sheet is up, `esc` backs out of it and Return commits it. Saying so is the
difference between one press of esc and two by reflex, the second of which loses the list.

## What a picture row says

The **application**, not the pixel dimensions: the question a row has to answer is "which
screenshot is this", and 922 × 1362 does not answer it. A file name would be better and
never exists — a screenshot copied with the keyboard puts raw PNG on the pasteboard with
no URL and no name, and an image file copied in Finder arrives as a path, which becomes a
file clip whose row already shows it. Dimensions are the fallback for clips old enough to
predate the source being recorded.

When the file has gone, the reason **replaces** the numbers rather than joining them: the
size of a file that is not there is not the useful half. The row itself stays, because
the clip is still a real record of something copied and removing it would look like the
app had lost it.

## Things that must not be decided in the view

Everything the panel says is decided in the presenter, and the reason is a specific
failure: the bottom line once claimed the history was *"synced across devices"*, under a
tick — a sentence copied from the reference design of a product that does sync,
describing one that does not. It lived in the view, where the copy tests cannot see it,
which is exactly how it survived.

The same applies to `isDestructive` and `isMonospaced` on a row: a view guessing from the
trash symbol or the last position would be right about Delete today by coincidence, and
silently wrong about the next action added.

## Moving, and why the list does not wrap

↓ and ↑ **stop at the ends**. This is a list somebody is stabbing at, and wrapping means
holding ↓ one beat too long teleports the highlight from the bottom to the top — the next
Return inserts the newest clip instead of the oldest one being aimed at, a wrong paste
into somebody else's document with no travel on screen to warn of it. Stopping is
self-correcting.

A change to *what is listed* puts the selection back at the top; a change to *the world*
— something copied while the panel is open — leaves it where it was, because the
selection is held by identity.

## Six rows of each kind of match

While searching, each group (name, collection, contents) draws at most six rows and counts the
rest as "N more · keep typing to narrow it". Browsing is never capped. Two cases would make that
advice impossible to follow, so the cap bends for them (#898): a clip whose whole text is the
query leads its group, since nothing more can be typed to reach it, and a collection named
exactly lists every clip in it, since a picture has no text to narrow by.

## The keys an input method owns

With an input method that composes — Japanese Kana or Romaji, Chinese Pinyin, Korean 2-Set,
Hindi Transliteration — the word being typed is *marked text* in the field editor, and four
keys belong to the input method while it is there: Return commits the candidate, ↑ and ↓ walk
the candidate list, and Escape cancels the word. SwiftUI runs `onKeyPress` **before** the field
editor sees the key, so a handler that answers `.handled` takes the key away from the input
method and it never arrives.

`PanelComposition.panelMayTake(_:whileComposing:)` holds the rule, and `send` is the one place
that asks it, so the search field and the sheet's field are covered by the same guard. Marked
text is also not reported through the `text:` binding, so the query still holds only what was
committed — which is why taking Return pasted the top row of the *unfiltered* list.

Whether a composition is open is the one part a key handler cannot read from the key: the view
asks the field editor, `(NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText()`.
That read is in `QuickPanelView`, which is excluded from coverage (#630), so it is checked by
hand:

1. Add Japanese – Romaji in System Settings › Keyboard › Text Input.
2. Copy two pieces of text, one containing 日本.
3. In a text editor press ⇧⌘V, switch to Japanese, type `nihon`, press Space to convert.
4. Return commits 日本 into the search field and the list filters; it does not paste.
5. During composition, ↓ walks the candidate list, and Escape cancels the word rather than
   closing the panel.
6. With no composition open, Return, ↑, ↓ and Escape work on the first press as always.
