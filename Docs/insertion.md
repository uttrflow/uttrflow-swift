# Putting the words on screen, and the traps in doing it

Insertion puts finished text into whatever field another application has focused. The code is
in `Sources/UttrflowInput/`: `TextInsertion.swift` is the one place that names each route,
`TextInsertionCoordinator` tries a route's strategies in order, and the strategies are
`AccessibilityTextInsertionEngine`, `PasteboardTextInsertionEngine`, `TypedTextInsertionEngine`,
`ClipboardTextInsertionEngine` and `PasteboardImageInsertionEngine`. The platform adapters —
`SystemPasteboard`, `CGEventKeystrokeSender`, `CGEventTypist` and `AXAccessibilityFocus` — are in
`SystemInput.swift`. **Dictation never writes the clipboard**: it tries an Accessibility write,
then typed keystrokes, and if both refuse the transcript stays in History with
an explicit Copy.

Per-application results are collected in [compatibility.md](compatibility.md); this page feeds
its `AX write`, `Paste`, `Confirmed` and `Full route` columns and the secure-field row.

## Which route each insertion takes

| What is inserted | Built by | Strategies, in order | Clipboard |
|---|---|---|---|
| A dictation | `TextInsertion.dictation()` | Accessibility, typed | Never written. When both refuse, the failure is `insertionNeedsCopy` and the recovery is Copy |
| An accepted suggestion | `TextInsertion.completion()` (`CompletionRoute`) | Accessibility, typed | Never written; see [predict-accept.md](predict-accept.md) |
| A clip pasted from the clipboard panel | `TextInsertion.coordinator(…, confirmsArrival: false, clipboardFallback: false)` | Accessibility, paste, typed | Written by the paste and left there; arrival is not checked |
| A clip or recent dictation inserted from the menu bar or main window | `TextInsertion.coordinator(…)` | Accessibility, paste, clipboard | Written by the paste, or by the clipboard floor when everything else refuses; a paste's arrival is checked |
| The Paste last transcript shortcut | `TextInsertion.dictation()` | Accessibility, typed | Never written; if both strategies refuse, the transcript stays available for explicit Copy |
| A secret clip | either clip route over `ConcealingPasteboard` | as above | Every text write carries `org.nspasteboard.ConcealedType` |
| A picture clip | `PasteboardImageInsertionEngine` | paste | The picture stays on the clipboard, since a paste whose arrival is not confirmed cannot be safely undone |
| A retry of a kept recording | `ClipboardTextInsertionEngine` alone | clipboard | Written; see [recordings.md](recordings.md) |

A clip with a formatted (HTML) flavour skips the Accessibility strategy, which would write the
plain text and drop the formatting. The typed strategy refuses the whole text when any character
has no single key on the current layout; see
[input-synthetic-keystrokes.md](input-synthetic-keystrokes.md).

Every strategy that sends words makes the same two checks immediately before it does:
`TextInsertion.requireLive()` refuses once the waiting stage has given up, and
`TextInsertion.requireTarget(_:focus:)` refuses with `insertionTargetChanged` when the captured
destination is no longer the frontmost application. The typed strategy makes both, so a switch to
an app with no readable field is refused rather than typed into.

The typed strategy also refuses, with `noFocusedTextField`, when a focused element is published
and its role is not a text-entry role (`FocusedElementKind.control`): in a page body, a list or a
file browser, letters are commands. It still types when the application publishes no focused
element at all (`FocusedElementKind.unpublished`), which is how a bundled-browser composer takes
dictation. The check is made in `canInsert()`, before the first chunk and before every later one.

The typed strategy posts its text `TypedTextInsertionEngine.chunkLength` characters at a time,
yields between chunks and makes the same checks again before each chunk after the first, against
the captured destination or, without one, the application in front at the first chunk. A check
or typist failure after the first chunk throws `insertionInterrupted(typed:total:)`, since the
posted characters cannot be taken back.

A strategy that throws `insertionUnconfirmed`, `insertionTargetChanged`, `insertionInterrupted` or
`clipboardChanged` stops the route (`TextInsertionError.stopsFallback`): the words may already be in the field, or the
clipboard now belongs to somebody else, and another strategy could duplicate or overwrite them.

## Dictating over a selection

A dictation started with text selected replaces that text, on every route: the Accessibility
route writes over `kAXSelectedTextAttribute`, and the typed and paste routes send only the words,
so the field's own typing or paste replaces the selection. No route collapses or moves the
selection first. This is the platform convention, and the same replacement is what re-dictating
over a selection relies on; the replaced text is taken back by the field's own undo, measured per
application in [compatibility.md](compatibility.md). Collapsing to the end of the selection and
appending is not built. `DictationOverSelectionTests` asserts the behaviour per route.

## What every insertion may contain

`OutputSafety` in `Sources/UttrflowCore/Adapters/` checks the finished text once, in the
pipeline, before any route writes it, so no destination relies on its own layout flag for this:

1. No control character except tab and line feed; any other becomes a space.
2. No trailing line break, which a shell or chat field would read as Return.
3. No escape sequence; an ANSI sequence is removed whole.

Whether a line break inside the text may reach a destination whose Return sends or runs it is
decided per route by the line-break probe, and is not yet part of this check.

## The Accessibility write that changes nothing

Some applications built on a bundled browser engine publish a focused text field, accept a write
to its selected text, answer `.success`, and change nothing. `SelectionWriter.replaceSelection(with:)`
therefore reads the selection back after every write and requires it to be a collapsed caret at
the old start plus the text's UTF-16 length. A missing or different selection throws
`insertionUnconfirmed`, which stops the route and asks the user to check the field before
retrying. A write that moves the caret but leaves the surrounding text unchanged throws
`insertionRejected` ("the field accepted the text and did not change"), and the next strategy runs.
A selection that already held the same text is the exception: replacing it changes nothing by
definition, so the moved caret alone confirms the write and no fallback writes the words again.

## A web field's own state

The caret check proves the field's visible text and caret moved. A page whose field is
driven by script keeps its own copy of the text and updates it from `input` and
`beforeinput` events, so a write that changes the screen without raising one would leave
the page holding the old text: Send posts what the page holds, and the next keystroke
re-renders the old text over the dictation. Whether an Accessibility write can do that is
measured, not assumed, by `Scripts/web_field_probe/probe.sh`.

The fixture is three fields that start as `start `: a single-line input re-rendered from
state that `input` events set; a `contenteditable` whose state `input` events set; and a
`contenteditable` that cancels `beforeinput`, applies it to its model and re-renders from
the model, the shape of a structured rich-text editor. Each is written with `one two three`
through one attribute, then sent one key press `x`; the page reports what it shows and what
it holds after each. Windows open in the background and every write goes to that process
only. Google Chrome 154.0.8037.97 and WebKit through `WKWebView` (the engine Safari 26.5
ships), macOS 26.5.1:

| Attribute | Engine | Field | Shown after the write | Page state | Caret check | After `x` |
|---|---|---|---|---|---|---|
| `AXSelectedText` | both | all three | unchanged | unchanged | unconfirmed | `start x` |
| `AXValue` | Chrome | input | written | written, one `input` event | confirmed | appended |
| `AXValue` | Chrome | contenteditable | written | **old**, no event | unconfirmed (caret at 0) | `xstart one two three` |
| `AXValue` | Chrome | model editor | written | **old**, no event | unconfirmed (caret at 0) | **`start x`: the write is undone** |
| `AXValue` | WebKit | input, contenteditable | written | written, `deleteContent` then `insertText` | confirmed | appended |
| `AXValue` | WebKit | model editor | `start start one two three` | the same | unconfirmed | appended |

**The attribute dictation writes cannot produce a visible but uncommitted field.** Both
engines answer an `AXSelectedText` write with `.success` and change nothing at all, shown
or held, and `SelectionWriter`'s caret check reports it. The Chrome input, re-run with its
window in front, behaved the same. That unconfirmed answer stops the dictation before the
typed route runs, although nothing landed.

**`AXValue` is not a fix to reach for.** It is the write that produces exactly that defect:
in a Chrome `contenteditable` the text appears, the page never hears of it, and a model
editor's next keystroke puts the old text back. WebKit replaces the value as delete-all
then insert-all, which a model editor applies on top of what it already holds. A whole-value
write also replaces the field rather than the selection.

## Which application the record names

The user may switch windows while a dictation is transcribed, and the words land wherever the
caret is by then. `TextInsertionCoordinator` takes the destination from the strategy
(`destinationAtLanding()`, which the paste strategy reads as it posts ⌘V) or reads it right after
the write, and reports it on the `InsertionAttempt`; the pipeline files the dictation under that.

The destination is the process that owns the focused element, not the frontmost application. A
launcher, a password-manager quick panel or a floating note can take keyboard focus as a
non-activating panel while the application underneath stays frontmost; the words land in the
panel, so the panel's owner is what the context names, what the target-changed check compares
and what the record files. `FocusedElementPreference.destination` is the one statement of that
rule: the owner of the element `choose` keeps, and the frontmost application only when
Accessibility names no owner. `AccessibilityFocus.focusedApplication()` and `MacContextEngine`'s
focus-owner read both go through it. The probe is in [compatibility.md](compatibility.md). Reading the destination can never refuse or delay
an insertion: it happens after the words are written. [early-transcription.md](early-transcription.md)
covers the layout decisions made against the screen as it was when each piece was cut.

## The paste that is posted and never arrives

`.hidSystemState` with `.cghidEventTap` is the source-and-tap pair that reaches another
application, and every posted event uses it (`postTaggedKeyPair`). A combined-session source
posted to `.cgAnnotatedSessionEventTap` creates a valid event the target never sees, and
`CGEvent.post` returns no status, so nothing reports the failure.

## The paste that is posted and never confirmed

Posting ⌘V proves nothing about arrival, so on the routes that check, `PasteConfirmation` reads
the text behind the caret until the end of what was pasted appears there.

| Constant | Value | Meaning |
|---|---|---|
| `PasteConfirmation.budget` | 1,600 ms | Longest wait, measured by the clock from entry |
| `PasteConfirmation.interval` | 40 ms | Sleep between reads |
| `PasteConfirmation.tailLength` | 24 characters | End of the pasted text that must sit behind the caret, whitespace collapsed |
| `PasteConfirmation.readLength` | 96 characters | Text read behind the caret on each poll |

Whitespace is collapsed because an application may rewrap what it is given; only the tail is
compared because the caret sits at its end. The tail is read once before the paste is posted, so a
caret that already ended in the same text does not count as a landing until it has changed. The
budget is elapsed time rather than a count of sleeps because each read — a focused-element lookup
plus a range read — can cost more than the 40 ms it follows; only the read already in flight when
the deadline passes can overshoot it.

The wait has four answers, and only the first is a fact:

- **Landed** — the words are behind the caret, and the elapsed time is reported with it.
- **Not reported** — the field will not say what it holds. Nothing is waited for, since a field
  that will not answer now will not answer in a second.
- **Gave up** — the budget was spent with no sign of the words.
- **Cancelled** — the waiting task was cancelled, as a stage timeout does. It stops at once,
  without reading the field again, and is reported as unconfirmed, never as landed.

`InsertionArrival(_:)` maps these to `.confirmed`, `.notReported` and `.unconfirmed`. Arrival is
part of what every strategy returns from `TextInsertionEngine/insert(_:)`, carried on the
`InsertionAttempt` and the `DictationOutcome`, so the floating button draws "Inserted — not
confirmed" against a plain "Inserted". The `reporting:` closure only observes an answer that is
reached whether or not anyone is listening; `uttrflow-dev insert` uses it to print the timing.

**A doubtful paste is not a failed one.** An application that rewrites quotes, dashes or
capitalisation as it takes a paste never matches the tail, and treating that as a failure would
demote a large class of successful pastes. The words are on the clipboard either way, so
"not confirmed" is said and nothing retries or re-pastes. A strategy that cannot check answers
**not reported**, which draws the plain tick: the Accessibility write verifies itself inside the
field, and typing reads nothing back.

If cancellation arrives before the paste key is posted, the engine discards its clipboard
generation only if it still owns that generation. It never restores the previous clipboard or
clears a newer copy. Once the key is posted, arrival can be uncertain, so the clipboard stays as
written.

The panel's paste route skips the wait (`confirmsArrival: false`) because the panel shows no
arrival notice. If the insertion stage itself times out (`StageTimeout.quick`, 15 s), the failure
is `insertionTimedOut` and points to the transcript in History, never to a manual paste that
could insert an older clipboard item.

## Every clipboard write stays on this Mac

The default pasteboard offers everything written to it to every Apple device signed into the same
account. `SystemPasteboard` calls `prepareForNewContents(with: .currentHostOnly)` before every
write (`clearForThisMacOnly()`), which keeps clipboard writes off Universal Clipboard.

Each write also carries the marker a clipboard history needs to treat it properly:

| Write | Marker |
|---|---|
| A paste (`writeTransientText`) | `org.nspasteboard.TransientType` |
| The clipboard floor (`writeAutoGeneratedText`) | `org.nspasteboard.AutoGeneratedType` |
| The clipboard floor for a transcript the clipboard panel's secret classifier recognises | `org.nspasteboard.ConcealedType` |
| Anything into a secure field, or a secret clip (`writeConcealedText`) | `org.nspasteboard.ConcealedType` |
| An explicit Copy (`writeText`) | none: it is an ordinary user copy |

The text and HTML flavours stay on the same item; only the marker type is added.

## Finding the focused element takes two questions

`AXUIElementCreateSystemWide()` works across the widest range of applications but returns nothing
when the caller has no application context, which is why a command-line probe can report "nothing
focused" whatever is on screen. Several applications also answer `kAXFocusedUIElementAttribute` on
the system-wide element and not on their own application element. Both are asked, system-wide
first; the fallback costs one extra round trip in a case that was already failing.

Answering is not the same as answering with the right element. While a browser's own editor is
typed into, the system-wide element can name the word under the caret rather than the editor.
`FocusedElementPreference.choose` keeps the system-wide answer if its role is one text is entered
into, else the application's if that is, else whichever answered at all. Insertion
(`AXAccessibilityFocus`) and the context and suggestion readers (`SurfaceProbe`) all call it rather
than keeping their own copy.

A field is offered to the Accessibility strategy only when its role is a text-entry role, its
selected text is readable and settable, and it reports a single selection: a field with several
carets is refused rather than written at one of them.

## Reading a field by range, not whole

Every question insertion asks about the focused field — what is before the caret, whether it is
masked, whether a write changed anything — prefers a bounded read with
`kAXStringForRangeParameterizedAttribute`. `kAXValueAttribute` returns the whole document and is
built on the target application's main thread.

| Constant | Value | Meaning |
|---|---|---|
| `CaretWindow.unitsPerCharacter` | 4 | UTF-16 units requested per character wanted |
| `CaretWindow.slack` | 16 | Extra units requested; the first character of a window that does not start at the field's start is dropped, since the range may have cut it in half |
| `CaretWindow.maskPrefixUnits` | 64 | Units read to decide whether a field shows only mask characters |
| `AXAccessibilityFocus.smallValueFallbackLimit` | 1,024 | Largest field, in UTF-16 units, whose whole value is read when it cannot answer by range |

A range read that fails falls back to the whole value only under that limit; a range read that
returns malformed or short text stays unreadable. A confirmation poll therefore copies
96 × 4 + 16 = 400 units however long the document is, where a whole-value read would copy all of
it on each of up to 41 polls.

## Accessibility calls are bounded

They are synchronous and block the sending thread until the target answers, so a focused
application that has quit, hung or gone to sleep would otherwise hold a dictation in progress for
the system default, and `isBusy` with it.

| Constant | Value | Applies to |
|---|---|---|
| `AXAccessibilityFocus.messagingTimeout` | 2 s | Every message to the focused element and its application, for insertion and paste confirmation |
| `AXAccessibilityFocus.acceptanceMessagingTimeout` | 0.1 s | Reading the caret when a suggestion is accepted, well inside `KeyHold`'s one-second limit |

The timeout is set on the focused element and the application element, never on the system-wide
element: a timeout set there is process-wide and read when each message is sent, so a suggestion
read setting 0.1 s on another queue would cut an insertion's write short. The system-wide focus
query itself runs under the system default. The context read has its own, shorter budget; see
[context-budget.md](context-budget.md).

Swift's cooperative pool has about one thread per core, so a blocking call made from `async` code
would hold a pool thread for up to 2 s per message. Insertion, paste confirmation, suggestion
acceptance and the typed route's checks send their messages through `AccessibilityThread`, a
concurrent dispatch queue of their own, and the awaiting task resumes when the answer comes back.
A task cancelled before its message leaves the queue sends nothing and takes a safe fallback —
"secure" for the concealment question, "unreadable" for a caret read. A message already sent
cannot be recalled; the timeout bounds the wait, not the write. A target that answers late can
still apply the write after the timeout, so `SelectionWriter.writeFailure(_:after:)` maps a
cannot-complete answer at or past `SelectionWriter.messagingTimeout` to `insertionUnconfirmed`,
which stops the route; any other failed write is `insertionRejected`, and the next strategy runs.

## Never into Uttrflow itself

Uttrflow's own windows are where the user chooses a shortcut or reads clip history, so no strategy
writes while Uttrflow is frontmost. Every strategy that writes into the focused field asks
`isSelfFrontmost()` in `canInsert()` and again immediately before the write, because the two are
separate `await`s and the user can switch to Uttrflow between them. A strategy that finds Uttrflow
in front throws `noFocusedTextField` before touching the clipboard or the field. See
[input-paste-eligibility.md](input-paste-eligibility.md) for why that is the paste strategy's only
refusal.

The History page's rows therefore offer **Copy** and **Copy to Paste Elsewhere**, both
`.copy(text)`, and the page shows "Copied — click where you want it, then press ⌘V" through
`MainNotice` and VoiceOver. An insert action from the main window could only ever reach
Uttrflow's own window. Re-activating the original application and inserting into it is not done,
because when to switch belongs to the user, not the page.

## Announcing Uttrflow's own writes

A pasted clip stays on the clipboard, so the clipboard watcher would otherwise see a change it
cannot attribute and file the clip again, moving it to the top of the panel every time it is used.
`SystemPasteboard` reserves an announcement through `PasteboardWatcher.ignoreNextWrite(of:)` with
the text, or `ignoreNextPicture(_:)` with the PNG bytes, **immediately before** clearing the
pasteboard, because clearing is itself what moves the change count. After a successful write it
reports the exact resulting change count from `writeText` or `setImage`.

The watcher matches the announced contents at that exact generation. A newer observed generation
retires an older announcement, so a same-text copy made by the user remains visible and a delayed
poll cannot turn Uttrflow's own write into a history row. If a write is refused or its text cannot
be read back, its reservation is withdrawn. If the watcher gives up on a bounded clipboard read,
it withdraws announcements that could have named that unread change.

## Dictating into a field that hides what is typed

A password or PIN field gets the words like any other field, and nothing else does. `SecureField`
decides from the field's role, subrole, identifier, placeholder and description, and reads the
first `CaretWindow.maskPrefixUnits` of the value only when none of those says secure, to catch a
field that shows mask characters without declaring itself. The question is asked by the context
read at the start of the dictation, which then carries none of the field's text, and by
`TextInsertionCoordinator` before the route starts and again after the winning strategy has
written, so a switch into a secure field during the route still counts.

Either answer marks the outcome `intoSecureField`, and its `wordsToKeep` is `nil`. The words reach
no store: no history row (not even a length), no Uttrflow clip, no last transcript, no dictionary
lesson and no clean-up record, and the floating button neither draws nor reads them aloud. A paste
or clipboard write into a secure field carries `org.nspasteboard.ConcealedType`, so a clipboard
history that honours the convention leaves it out. If the words are lost before insertion, the
audio is not kept for a retry.

## One writer, one reader, and a gate that says so

Every rule above — announce first, keep it on this Mac, mark the write — lives in
`SystemPasteboard`, and a call site that reaches `NSPasteboard` itself gets none of them. Every
write in the app, including the main window's and the menu's Copy (`AppDelegate.putOnClipboard`)
and pictures (`Pasteboard.setImage`), goes through the `Pasteboard` port. `make pasteboard-audit`
(`Scripts/pasteboard_audit.sh`, part of `make verify`) fails when any file other than the writer
(`Sources/UttrflowInput/SystemInput.swift`) and the reader
(`Sources/UttrflowClipboard/ClipboardSource+System.swift`) names `NSPasteboard`.
[offline.md](offline.md) makes the same argument for one module owning the network.

## Remembering where the last dictation landed

A spoken edit command acts on text written earlier into another app, so something has to know
where it went. `InsertionLedger` holds that, in memory only: it is never persisted and never
sent. `TextInsertionCoordinator` writes it after every insertion, reading the field and caret
through `AccessibilityFocus.focusedFieldPlace` once the words are written.

Only an Accessibility write whose arrival is `confirmed` is recorded, because only that route
reads the words back. An unconfirmed write, a paste, a typed write, a clipboard hand-off, a
failure, a secure field or a field that cannot be placed empties the ledger instead: a command
must never act on a span nobody saw arrive. A field is identified by its process, its window and
the element itself, so asking from any other field empties it as well. It keeps
`InsertionLedger.capacity` entries and refuses one longer than `InsertionLedger.textLimit`.

Offsets go stale the moment the user types, so a record is never trusted on its own:
`InsertionRecord.stillThere` reads the field now and answers whether exactly those words still
end where they were written, through `BackwardSelection.confirms`.

How much of that text an edit command covers is one value, `CommandScope`: `word`, `clause`,
`sentence`, `piece` or `dictation`, with `dictation` for a bare "delete that". `range(in:)`
divides the newest insertion, finding sentences through `Abbreviations.endsSentence` (so "3.5"
and "e.g." never split) and clauses through written clause marks and `ClauseSegmenter`.
`span(in:)` turns that into the one record an `EditTarget` takes; a dictation is the newest
insertion and each earlier one that ends where the next begins. An empty ledger or a blank insertion returns nil, and nil makes no edit.

An edit returns an `EditUndo`: the span its own text now occupies, the text it took out, and up
to `EditUndo.contextUnits` UTF-16 units either side. `EditHistory` keeps the last
`EditHistory.depth` of them for `EditHistory.window`, in memory only. An undo is itself an edit
of that span back to the removed text, so it refuses unless the span, both neighbours and the
caret are as the edit left them, and a second undo re-applies the first edit. A refused undo,
or asking from another field, forgets every entry. `EditUndo` never describes the removed text.

## The insertion fixture

`uttrflow-insertion-fixture` is a test-only window with a text field, a multi-line view and a
secure field, each of which takes its edits through one fault mode named on its command line.
`Scripts/e2e_insertion.sh` launches it once per mode, runs `uttrflow-dev insert` into the focused
field, and asserts the exit status, the line `insert` prints and what the field holds after. It
waits until nobody has touched the Mac for 30 s, and needs Accessibility granted to the shell.
`Scripts/bundle.sh` fails a bundle that contains any of it.

| Mode | Field, route | What the field does | Expected |
|---|---|---|---|
| `faithful` | text, Accessibility | takes every edit | written, field holds the words |
| `changes-nothing` | text, Accessibility | answers the write with success and changes nothing | `insertionUnconfirmed`, field empty |
| `drops-keys` | text, paste | never receives posted keys | pasted, unconfirmed, field empty |
| `substitutes` | multi-line, paste | curls quotes and turns `--` into an em dash | pasted, unconfirmed, field holds the rewritten words |
| `caps-length` | text, Accessibility | keeps 16 characters | `insertionUnconfirmed`, field holds the first 16 |
| `late-write` | text, Accessibility | answers the write with success and applies it 150 ms later | `insertionUnconfirmed`, field holds the words once the write lands |
| `steals-focus` | text, paste | moves focus to the multi-line view the first time its selection is read | pasted, and the words land in the multi-line view, not the text field |
| `closes-window` | text, paste | closes its window the first time its selection is read | pasted, field empty |
| `marks-text` | text, Accessibility | opens with an input method composition, `ni`, in progress at the caret | written, the composition is committed and the words follow it |
