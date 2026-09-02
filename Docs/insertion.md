# Putting the words on screen, and the traps in doing it

Three strategies in order — write into the focused element, paste, leave it on the
clipboard — and each of the first two has a failure that reports success.

## The Accessibility write that changes nothing

Electron applications (Claude's own desktop app among them) publish a focused text
field, accept a write to its selected text, answer `.success`, and do nothing at all.

Believing the return value meant the coordinator stopped there, so the words never
reached the paste below and never reached the clipboard either — the user saw the
dictation happen and had nothing to paste. The write is therefore **read back and
verified**; a field that does not answer the read is trusted, since that is a
verification rather than a precondition.

## The paste that is posted and never arrives

`.hidSystemState` with `.cghidEventTap` is the pair that reaches another application.
A combined-session source posted to `.cgAnnotatedSessionEventTap` creates a perfectly
valid event the target never sees, and **nothing reports an error** — `post` returns no
status. The paste then "succeeded", the borrowed clipboard was put back over the
dictation 250 ms later, and the words were in the document, the clipboard, and nowhere
else. Exactly what a user calls "it just does not work".

## `clearContents()` sends your words to your iPhone

The default pasteboard behaviour offers everything written to it to every Apple device
signed into the same account. A product whose entire claim is that your words do not
leave this Mac was, on the paste path, sending finished transcripts to the user's phone.
`.currentHostOnly` is the one line that stops it, and the paste path is not an edge case
— it is how a large share of dictations reach the caret, because the Accessibility route
cannot write into most Electron and web apps.

## Finding the focused element takes two questions

`AXUIElementCreateSystemWide()` is the canonical answer and works across the widest
range of applications, but returns nothing when the caller has no application context —
which is why a command-line probe reports "nothing focused" whatever is on screen. That
measurement is misleading, and chasing it once left only the per-application query, which
is the weaker of the two: several applications answer `kAXFocusedUIElementAttribute` on
the system-wide element and not on their own. Both are asked, system-wide first; the
fallback costs one extra round trip in a case that was already failing.

## Accessibility calls must be bounded

They are synchronous and run on the pipeline's own thread, so a focused app that has
quit, beachballed or gone to sleep holds the pipeline in `.tidying` for the system
default — `isBusy` the whole time, so no further dictation can start either. The budget
here is generous next to the context engine's 100 ms, because this read *is* the
dictation rather than a nicety alongside it.

## Announcing Uttrflow's own writes

Pasting a clip puts it on the clipboard and never takes it back, so the clipboard
watcher would see a change it cannot attribute and file the clip a second time, moving
it to the top of the panel every time it is used.

`PasteboardWatcher.ignoreNextWrite(of:)` is called **immediately before** the write, and
before `clearContents()` — clearing is itself what moves the change count, so an
announcement made after it describes a change that has already happened.

The announcement **names the text it is about to write**. Matching on the count alone
meant any later change was claimed: a user copying something within the same 200 ms tick
as an Uttrflow paste had their copy silently swallowed, which is the one thing a
clipboard manager may not do. An announcement whose own write has not arrived is kept
rather than spent, and lapses after two seconds so a paste that threw cannot sit armed.
