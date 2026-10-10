# The clipboard panel

The clipboard panel is the floating list opened with ⇧⌘V: everything copied, searchable,
pasted back with Return. What it says is decided in `Sources/UttrflowUX/` (`PanelPresenter`,
`PanelSnapshot`, `PanelPresentation`, `PanelAlias`, `PanelComposition`,
`PanelPasteReport`); the window and view are in `Sources/Uttrflow/Panel/`. `PanelPresenter` is
pure and is the only place that decides what the panel says. The view draws exactly that, so
the highlight, the mask over a secret and the words under the list cannot tell three different
stories about the same moment. Window, focus and AppKit traps are in
[`app-quick-panel.md`](app-quick-panel.md).

## What a clip is

A clip has one of seven kinds, detected rather than declared: text, link, code, secret, colour,
image and file path (`ClipKind` in `Sources/UttrflowClipboard/Clip.swift`). The kind picks the
glyph, the tint and what the row offers. A colour with a resolved sRGB value shows that value as
the row mark; a detected perceptual colour without an sRGB conversion keeps the palette glyph.
Word-shaped hashes and issue-like short numbers need a colour declaration to disambiguate
them. An exact standalone CSS named colour gets a swatch; a colour name within prose stays text.

One search field matches text and aliases. An alias is reduced the same way when it is saved
and when it is matched, in `PanelAlias.handle` (no leading slash, no whitespace, case, accents
and width folded), so two spellings of one name cannot drift apart.

A clip can also carry tags (`Clip.tags`), and search finds a clip by one of them. A tag is
compared in `PanelTags.match` after the same reduction as an alias, with a leading `#` dropped
instead of a slash, so `Prod`, `prod` and `próD` are one tag. A query finds a tag only when it is
the whole tag or its beginning: never from inside a tag, never across two tags, never with a
space, and never when it is shorter than two characters, which would begin too many tags. The
clip's text is still searched as before, so a word that only appears in the middle of a tag
finds the clip by its text or not at all. Tag matches are listed after the names you gave and
before collections and contents; a whole tag leads a tag the query only begins.

Content search bounds a clip containing a grapheme longer than 32 Unicode scalars to its first
1,000 Unicode scalars. This keeps a single combining-mark cluster from making each keystroke
work over an unbounded grapheme.

## Chips, and the way out of a collection

The kind filters (`PanelFilter`: All, Text, Links, Code, Images) and the collections share one
row, and that row already begins with an **All** meaning every *kind*. So there is **no second
All for collections**: two chips a few points apart both reading "All" and meaning different
things reads as a bug rather than a choice.

The way out of a collection is **the collection itself, pressed again**
(`PanelCategoryChip.chosen` answers 1, everything, when the chip is already active). ⌘1 means
everything and clears the kind as well, or "show me everything" would leave a filter on.

**A shortcut and a position are different numbers.** `shortcut` is what is *printed* and stops
at `PanelSnapshot.shortcutLimit` (9), because there is no ⌘10 and printing a shortcut that does
not work is worse than printing none. `position` is what pressing the chip *means*, counts from
2, and does not stop, so the tenth collection and later still work when clicked.

**A collection name fits one chip.** `PanelSnapshot.collectionRefusal` is the one rule for a new
name, whether a clip is filed under it or a collection is renamed to it. A name is at most
`PanelCollectionName.maximumLength` (40) characters as a person counts them, holds no line break,
tab, or character `ClipTextSafety` calls a display hazard, and is not a kind filter's title in any
case, since that would be a second chip in the row reading the same. A name already held files the clip there, so a collection made before these rules keeps working.
The chip draws one line at most 160 points wide, cut at the end, with the full name as its tooltip.

A collection exists only while a clip carries its name. When a refreshed list no longer has the
open collection, for example because its last clip moved out, the panel returns to every clip.

Each collection chip offers **Rename collection** and **Delete collection** as VoiceOver actions.
With a chip focused, ⌘⇧R renames that collection. The context menu offers both actions with
⌘⇧R and ⌘⇧Delete.

**While there is a query, the active chip is All**, unless a kind chip is on. That is the one
narrowing a search keeps: the kind chip stays lit, and an empty search says "Nothing under Code
mentions …" and points at All, rather than claiming the whole clipboard was searched. A search
otherwise spans every collection and every tab, so drawing the open tab as chosen would tell the
user their search had been narrowed when it had not. The snapshot keeps its collection
regardless; this is only what is *shown*, and emptying the field brings it back.

## Masking

The mask is **twelve bullets, not one per character** (`PanelPresenter.mask`). The length
of a token is worth something to whoever is looking over the user's shoulder, and a mask that
leaks it only pretends to work.

A masked row also loses its excerpt, its language chip and its tooltip:

- the **excerpt** would print the part of the secret the user searched for;
- the **language chip** is one more thing on a row whose whole point is to say as little
  as possible until asked;
- the **tooltip** exists to give back what a row had to cut, and a masked row cut nothing
  the pointer is entitled to. A panel of bullets appearing under the cursor reads as the
  mask being lifted.

Search does not read a masked secret's text either. A row that appeared under "Contents" for a
typed fragment would confirm the fragment is inside the hidden value, so until it is revealed a
secret is found only by its alias, its tags or its collection. What counts as a secret:
[`clipboard-secrets.md`](clipboard-secrets.md).

A reveal lasts only for the open panel. Screen lock, display sleep, system sleep and switching
user sessions close the panel; its resume point does not retain revealed clip identifiers, so
the next opening masks those clips again.

## Checklists in notes

The panel counts a note's checkboxes and never ticks them. The row's `checklist` field, which
VoiceOver reads as "1 of 2", counts exactly the boxes the plain form writes: `NoteChecklist` takes
them from `RichTextPlainForm`, so a paste and its row never disagree on which items are boxes. An
item in a list labelled as a checklist is a box even when it does not mark itself; see
[`clipboard-plain-form.md`](clipboard-plain-form.md#checklists). A row is built on every
keystroke, so `ChecklistProgresses` reads each note once until its formatted content changes.

## Editing a clip's text

Edit (⌘E) opens the clip's whole text in the sheet's field, which grows to eight lines and then
scrolls; ⏎ saves and ⌥⏎ starts a new line. Save sends the text to `ClipboardStore.setText`, which
keeps the clip's identity, name, tags, collection and pin, asks the detector again on the path a
copy takes, so the user's own answer about a text still outranks it, and clears the formatted
form. The app then marks the clip used, so it moves to the top. Save does nothing while the text
is unchanged, blank, or over the largest clip the store keeps
([`clipboard-budget.md`](clipboard-budget.md#the-largest-clip)), so what was typed stays on screen.

Edit is offered on every clip that is text, and not on:

- a picture, which has no text;
- a masked secret, until it is revealed, because the field would show what the mask hides;
- a clip with a formatted form, a note included: plain editing would discard the formatting and a
  note's checklist state, and a written note and a formatted copy are the same field to the store.

A kept clip whose new text the detector takes for a secret would be held in memory only and gone
after the next launch ([`clipboard-secrets.md`](clipboard-secrets.md)). The first Save says so and
saves nothing; a second Save of the same text saves it. Typing anything in between asks again.

## Empty states: never specific and wrong

`PanelPresenter.emptyState(for:)` tells the nothings apart, because what to do about each one
differs, and the sentence for a narrowed list is **assembled from every narrowing that is
actually on** (`narrowedEmptyState`) rather than picked from the first one that matches. An
empty state that names one of two reasons is worse than a vague one, because it is specific and
wrong: "Nothing in db" while the Code filter is also on says there are no clips in db when there
are.

| The nothing | What is said |
| --- | --- |
| No clips at all | "Nothing copied yet" |
| The arrivals tab is empty because everything is pinned or filed | "Nothing loose", with "Everything you have copied is pinned or filed." (or "…Uttrflow made…") |
| A search with a kind chip on | "Nothing under Code mentions “…”. Choose All to search everything." |
| A search with no kind chip | "Nothing on your clipboard mentions “…”." |
| A filter or collection with no query | assembled from the scope, collection and kind that are on |

Pinning and filing both take a clip out of the arrivals tabs, so somebody who keeps a tidy
clipboard reaches an empty History with fifty clips in the panel; "Nothing copied yet" there
would be false. A search spans what Uttrflow made as well as what was copied, so it says "your
clipboard", not "what you have copied".

**A list that has not been read yet is an unknown, not a nothing.** The window is shown and made
key before the store is asked for anything (see
[`app-quick-panel.md`](app-quick-panel.md#what-the-open-waits-for-nothing)), so for that moment
the panel holds no clips and has no idea whether there are any. `PanelSnapshot.isAwaitingList`
marks it, and the presenter says nothing about emptiness and offers nothing to keep until the
list arrives.

A refresh keeps a selection or open sheet only while its referenced clip or collection remains in the
list. A vanished sheet closes with a notice. Reveals belong to the current clip list, so a deleted
and later restored secret is masked again.

## The line under the list

Precedence: the sheet's keys, then the undo offer, then the empty state's reason, then the
gesture.

A sheet wins whenever one is open, because its keys are what the focused field actually obeys:
teaching **⌘Z** over a field where Return saves and `esc` backs out would be the wrong key, and
the undo offer being merely hidden costs nothing; the clip is not gone, only the sentence that
says so.

Outside a sheet, the undo offer wins while it is live, because it expires: `AppDelegate.undoWindow`
is 8 seconds. Press **⌘Z** while the offer is visible to restore the deleted clip. Delete asks no
confirmation, and the undo is what pays for that, so the undo is **offered, not merely
available**: an undo nobody is told about leaves the clip gone with neither a question
beforehand nor a way back.

If another clip took the deleted clip's alias during that window, undo restores the clip without
that alias, keeps the newer clip's name, and announces the conflict in the panel.

The panel window takes ⌘Z ahead of Edit › Undo, which would otherwise swallow it, in this order:
while the offer shows, ⌘Z restores the clip; otherwise, if the search field has typing to take
back, ⌘Z undoes that typing; otherwise it goes to the panel. ⇧⌘Z stays Redo.
Typing a different search query hides the offer, so ⌘Z after typing undoes the typing rather
than bringing back a clip the person is no longer looking at; with no typing left to undo, ⌘Z
still restores the clip until the offer expires.

While a sheet is up, `esc` backs out of it and Return commits it. Saying so is the difference
between one press of esc and two by reflex, the second of which loses the list.

When a search has no results, **Clear search · Esc** appears below the message; Escape clears the
query before it closes the panel. **?** while search is empty, or **⌘/**, opens the one-screen
keyboard guide, whose entries use the same row-action chord table as the panel. List footer states
point to the guide; sheet footers keep only the keys available in their focused editor. If an undo
is available during a search, the footer also keeps its ⌘Z hint while teaching Escape to clear the
query.

## What a picture row says

The **application**, not the pixel dimensions: the question a row has to answer is "which
screenshot is this", and 922 × 1362 does not answer it. A file name would be better and never
exists: a screenshot copied with the keyboard puts raw PNG on the pasteboard with no URL and no
name, and an image file copied in Finder arrives as a path, which becomes a file clip whose row
already shows it. Dimensions are the fallback for clips recorded without a source.

When the file has gone, the reason **replaces** the numbers rather than joining them: the size
of a file that is not there is not the useful half. The row itself stays, because the clip is
still a real record of something copied and removing it would look like the app had lost it.

## What must not be decided in the view

Everything the panel says, including the footer, is decided in the presenter, where the copy
tests can see it; a sentence written in the view is invisible to them. The panel makes no claim
about syncing, because nothing is synced.

The same applies to `isDestructive` and `isMonospaced` on a row: a view guessing from the trash
symbol or the last position would be right about Delete today by coincidence, and silently wrong
about the next action added.

## Moving, and why the list does not wrap

↓ and ↑ **stop at the ends**. This is a list somebody is stabbing at, and wrapping means holding
↓ one beat too long teleports the highlight from the bottom to the top: the next Return inserts
the newest clip instead of the oldest one being aimed at, a wrong paste into somebody else's
document with no travel on screen to warn of it. Stopping is self-correcting.

A change to *what is listed* puts the selection back at the top; a change to *the world*
(something copied while the panel is open) leaves it where it was, because the selection is held
by identity.

## Six rows of each kind of match

While searching, each group (name, collection, contents) draws at most
`PanelPresenter.rowsPerGroup` (6) rows and counts the rest as "N more · keep typing to narrow it".
Browsing is never capped. The cap bends in the two cases where that advice is impossible to
follow: a clip whose whole text is the query leads its group, since nothing more can be typed to
reach it, and a collection named exactly lists every clip in it, since a picture has no text to
narrow by.

## The keys an input method owns

With an input method that composes (Japanese Kana or Romaji, Chinese Pinyin, Korean 2-Set,
Hindi Transliteration) the word being typed is *marked text* in the field editor. Return commits
the candidate, ↑ and ↓ walk the candidate list, Escape cancels the word, Page Up/Down and
Home/End move within the input method, and command chords remain available to it. SwiftUI runs `onKeyPress` **before** the field
editor sees the key, so a handler that answers `.handled` takes the key away from the input
method and it never arrives.

`PanelComposition.panelMayTake(_:whileComposing:)` holds the rule for both panel keys and
resolved key decisions, including command chord intents. `send` in `QuickPanelView` applies it to
relayed keys, and the chord handler applies it before performing an intent, so the search field
and the sheet's field share one ownership policy. Marked text is also not reported through the `text:` binding, so the
query holds only what was committed; a panel that took Return during composition would paste the
top row of the *unfiltered* list.

Whether a composition is open is the one part a key handler cannot read from the key: the view
asks the field editor, `(NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText()`. That
read is in `QuickPanelView`, which is excluded from coverage, so it is checked by hand:

1. Add Japanese – Romaji in System Settings › Keyboard › Text Input.
2. Copy two pieces of text, one containing 日本.
3. In a text editor press ⇧⌘V, switch to Japanese, type `nihon`, press Space to convert.
4. Return commits 日本 into the search field and the list filters; it does not paste.
5. During composition, ↓ walks the candidate list, and Escape cancels the word rather than
   closing the panel.
6. With no composition open, Return, ↑, ↓ and Escape work on the first press as always.

## Multiline clips

A row stays one line, and a multiline clip labels how many additional lines will be pasted.
Hovering its summary or line count shows the full text, capped at 10,000 characters with an
explicit truncation marker. The preview is bounded because stored clips may be much larger;
the clipboard itself is unchanged and a user can still inspect the source before pasting.
Unrevealed secrets expose neither the line count nor their preview. A first line made only of
whitespace says so and includes the clip's character count, instead of becoming an empty row.

## Names and Unicode confusables

Two names are one name when they are equal under the search comparison, after whitespace and the leading slash are dropped, or when their Unicode confusable skeletons are equal. The search comparison folds case, accents and width, so a Devanagari nukta is ignored and an Arabic hamza is kept. The skeleton keeps every mark: normalize to NFD, replace each code point with its Unicode confusable prototype, and normalize to NFD again. The skeleton is only a comparison key and is never shown or stored. The packaged Unicode 18.0.0 confusables, Scripts, ScriptExtensions and PropertyValueAliases data make the result consistent across macOS ICU versions. If any table is missing or unreadable, saving a name is disabled and the sheet says why.

The script check intersects each alphabetic character's Script_Extensions set, falling back to Script when no extension set is listed. Common and inherited letters do not constrain the set. An empty intersection means the name mixes scripts, except that Japanese names may combine Han with Hiragana or Katakana, and Korean names may combine Han with Hangul. Other mixed-script combinations remain refused. Unicode data is distributed under the [Unicode terms of use](https://www.unicode.org/terms_of_use.html); the source tables identify their version and copyright.

## Invisible and control characters in clips

The panel identifies default-ignorable, format and control scalars in a clip, except tabs and line endings. Rows show a `Hidden chars` badge, and previews replace each such scalar with its `U+` value and Unicode name in brackets; unnamed controls are labelled `CONTROL CHARACTER`. Search removes non-whitespace hazards from both the clip text and the query; whitespace controls keep the existing search-as-space behavior. A query made only of removed scalars acts like a blank search. The stored clip and ordinary Insert or Copy actions keep the original text. `Paste cleaned` is an explicit row action that removes those scalars from the text sent to the destination; it never edits the stored clip, and a secret remains marked concealed.

## Related

- [`app-quick-panel.md`](app-quick-panel.md): the window, focus, measurements and AppKit traps.
- [`ux-panel-geometry.md`](ux-panel-geometry.md): where the panel opens.
- [`ux-panel-insertion.md`](ux-panel-insertion.md): what Return does.
- [`clipboard-budget.md`](clipboard-budget.md) and [`clipboard-store.md`](clipboard-store.md):
  what is kept and where.
