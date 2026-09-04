# Accepting a suggestion

What happens between the user pressing a key and the completion appearing in their
document. The deciding is `KeyRouting` in `UttrflowPredict`, which is pure; the tap is
`KeyInterceptor` in `UttrflowInput`, which is not and is excluded from the coverage gate
for it.

## Which key accepts

Tab by default. The right arrow in terminals, because Tab there is the shell's own
completion and taking it would break the thing the user is actually trying to do.
Option-Tab in editors, because Tab there is indentation and the language server's
completion is already bound to it. The user can override any application, and the
override wins over the kind.

`AcceptKeys` recognises terminals and editors from a bundle-identifier prefix.
`AppKind` in `UttrflowAI` recognises overlapping sets for a different purpose — the one
line of prompt text that describes the screen — and the two tables are deliberately not
shared, because `UttrflowPredict` depends on nothing and `UttrflowAI` depends on Core and
the dictionary. If a third caller ever needs the classification, the table moves into
Core and both read it; two is not enough to pay for that.

## Return is the dangerous key

A suggestion on screen does **not** entitle us to Return. Stealing it runs a command in a
terminal and sends a half-written message in a chat box, and both are unrecoverable in a
way that a missed completion is not. So Return passes through untouched until the user has
pressed Down at least once — the moment they are demonstrably navigating our list rather
than finishing their own line. `SuggestionSelection.hasMoved` is that fact and nothing
else.

The same reasoning applies to Up, which is shell history before it is anything of ours: it
is claimed only once the list is being walked. A single suggestion is not a list at all,
so neither arrow nor Return is ever claimed for one — Tab is the only way to take it.

## The escape ladder

| Keystroke | Effect |
|---|---|
| ⎋ | The suggestion goes; the dot stays |
| ⎋⎋ | This field offers nothing more |
| ⌥⎋ | Suggestions stop everywhere until turned back on |

⎋ with nothing drawn is not ours: it closes the application's own dialog, and a tap that
swallows it is a tap the user has to quit the app to escape from.

## Why the tap swallows from a bitmask

The tap's callback runs inside the window server's event path for **every keypress in the
system**, ours or not, and macOS disables a tap that takes too long over one. So the
callback allocates nothing, takes no lock, and asks one question: is the bit for this
keystroke set in one atomic `UInt32`?

`ArmedKeys` is that word — one bit per keystroke the feature can ever claim — and
`KeyRouting.arming` computes it *from `KeyRouting.decision` itself*, over every slot. The
mask and the rules therefore cannot disagree about what is taken, which matters because a
key swallowed with no rule behind it is a keystroke the user silently loses. There is a
test that asserts the agreement directly.

A swallowed keystroke is written into a fixed ring buffer of 64 entries and a dispatch
source is signalled; the decision runs on that source's queue. The ring is what keeps two
quick presses of Down from coalescing into one, which a source's own OR-ed data would do.

The tap gets its own thread with its own run loop. A tap serviced by the main run loop is
a tap that stalls behind whatever the app is drawing, and the system's answer to a stalled
tap is to switch it off.

## Being switched off

macOS disables an event tap that misses its deadline (`.tapDisabledByTimeout`) and when
the user's own input demands it (`.tapDisabledByUserInput`). The callback turns it back on
once. On a second disable it stops re-arming and reports `.disabledTwice` instead: a tap
that has to be revived repeatedly is one that is costing the user keystrokes, and a
feature that quietly fights the system forever is worse than one that says it has stopped.

## The clipboard is not on the insertion route

Dictation's route ends in the clipboard, because §19 says a user must never lose words
they spoke. A completion is the opposite case: the user did not produce this text, they
merely declined to type it, and losing it costs them one keypress.

Meanwhile putting it on the clipboard costs them their actual clipboard **and** files a
phantom entry in their own clip history — from a feature they experience as autocomplete.
So `TextInsertion.completion` is Accessibility first and synthesised keystrokes second,
with nothing beneath, and a completion that lands nowhere is simply not accepted.

## What accepting inserts, and what it takes back

`Acceptance.edit(accepting:after:)` answers with an `Edit`: the already-typed characters
immediately before the caret that go, and the text that replaces them. An append is that
edit with nothing replaced, so the common case stays trivial and destroys nothing.

The edit is the difference from the longest opening the two strings share. `git com` →
`git commit` shares all seven typed characters, so nothing is replaced and `mit` is typed.
`gti c` → `git commit -m` shares only `g`, so four characters go and `it commit -m`
arrives. Two features produce exactly that second shape and both used to draw a suggestion
and then do nothing when Tab was pressed: the store's fuzzy fallback, and verification's
correction of what was typed.

What is replaced is always a suffix of what the user typed — it is cut from that string
and no other — so the count cannot exceed what they have entered, and the edit can never
reach text they did not type at this caret. `Quieting` has already refused the moment
before this if the caret is not at the end or anything is selected.

The route takes it two ways. Accessibility widens the field's own selection back over
those characters and then writes once, which is why it is tried first. Where the field
will not report or set its selection, `TypedTextInsertionEngine` presses Delete once per
character and then types — which works everywhere and costs what the next section says.

## What ⌘Z does afterwards

**One press, on the Accessibility route.** Setting `kAXSelectedText` on an AppKit field
goes through `insertText:replacementRange:`, which registers one undo action; moving the
selection first registers none, because a selection change is not an edit.

**Several, on the keystroke route, and this cannot be fixed from outside the
application.** Each synthesised Delete is a separate `deleteBackward:` in the target, and
no undo manager coalesces a run of deletions with the typing that follows it — the kinds
differ, so the group is broken between them. AppKit therefore charges roughly one press
per character replaced plus one for the typing; Chromium and Electron coalesce
same-kind edits within a time window and so charge about two. Undo grouping belongs to the
target's own undo manager and there is no cross-process API that opens a group in it, so
this is a property of the route rather than a defect to be fixed later.

This is the whole argument for preferring Accessibility, and it is why a field that
refuses to select backwards falls through to keystrokes rather than the replacement being
dropped: a completion the user has to press ⌘Z five times to undo is still better than a
Tab that does nothing.

## What the surface draws, and why it is the same answer

`SuggestionPresentation` is built from the `Suggestion` **and what is typed**, and each of
its rows holds the `Acceptance.Edit` for that candidate — the very value
`SuggestionAcceptor.accept` applies. The ghost is `edit.inserted` and nothing else, so
`git com` draws `mit` at `caret.maxX` and the line reads `git commit` rather than
`git comgit commit`. A row that has nothing left to offer is dropped, so a suggestion the
user has finished typing takes the surface away instead of drawing an empty one.

`Edit.applied(to:)` is what makes the agreement checkable: what is drawn on top of what is
typed equals the candidate, and a test asserts it over both shapes.

**A replacement is drawn as its cost.** `edit.replaced` — the typed characters Tab
destroys — is drawn struck through immediately before the inserted text, so `gti c` shows
~~ti c~~`it commit -m` and the four characters about to go are visible before the keypress.
It carries no colour or opacity of its own: the strike is the whole signal, and it
inherits whatever the enclosing style is, which is how it stays legible when Increase
Contrast or Reduce Transparency drops the ghost's transparency to full strength. VoiceOver
hears the same fact as "Tab to accept, replacing 4 characters".

The struck-through text sits inside the panel rather than over the user's own characters,
because the panel is anchored at the caret and shifting it left far enough to overlay them
would mean measuring the field's own font from outside the application. It is an echo of
what goes, not a mark on it.

**The ghost line carries no key glyph.** Grey text after the caret is already understood
as a completion; a symbol beside it is clutter. Where a key is named — the `take` entry of
the list's footer and the VoiceOver label — it is built from the field's `AcceptKey`, so a
terminal reads `→` and an editor `⌥⇥`. A `⇥` once drawn in a terminal sent the user to
press the shell's own completion key and conclude accepting was broken.

**A choice is one line until Down is pressed.** A `.choice` draws only the leader's
continuation on the caret's line, exactly like a `.certain`. The first ↓ opens the list
under the line — every candidate as `↳ text`, the highlighted one at ghost strength and
the rest dimmer, then `take · next · dismiss` — and the list stays open while the highlight
walks round, collapsing again only when the suggestion changes.

## Not settled here

- **Whether the strike should overlay the user's own characters rather than echo them.**
  That needs the field's text metrics, which `SuggestionGeometry` does not have.
