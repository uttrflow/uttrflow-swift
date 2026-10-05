# Detecting a composing input method

AI suggestions (tab-to-complete) must not draw a ghost over an input method's marked text: while a
Hindi, Chinese, Japanese or Vietnamese input method is mid-composition, the line, Escape and the
arrow keys belong to it. This page is how Uttrflow tells, from another process, that a field is
composing. The field read is `Sources/UttrflowContext/CompositionProbe+System.swift`, the decision
`Sources/UttrflowPredict/Composition.swift`, and the gate `Quieting.reason`
([predict.md](predict.md)). Re-run the measurements with `uttrflow-dev probe ime`.

Which application publishes what is collected in [compatibility.md](compatibility.md); this page
feeds its `Marked text` column, and the table under "How far it travels" stays here because the
reach of one attribute is this page's whole subject.

**Summary.** A real state signal exists and is public — `AXTextInputMarkedRange` — but it
only reaches AppKit multi-line text views. Everywhere else the only answer is a capability
guess from the selected input source, and that guess does not gate.

**What the signal does: the field's own answer gates, and the guess does not.**
`Composition.isComposing` combines the field's marked range with the input source's kind,
`FocusedFieldReader` writes the answer into `FocusedFieldSnapshot.isComposing`, and the
coordinator copies it into `PredictionContext.isComposing`, where nothing gates on it. The
field's own answer travels beside it as `FocusedFieldSnapshot.markedText` and
`PredictionContext.markedText`, and `Quieting.reason` returns `composing` when that is
`present`: nothing is drawn and no key is claimed, so Escape and the arrow keys reach the
input method, which uses them to cancel a conversion and walk its candidates. `absent` and
`unanswered` gate nothing, so the fallback below withholds nothing — the bill below is what a
gate on the fallback costs, and it is why that gate is off.

**A Return while composing confirms a conversion, not the line.** A Japanese or Chinese
input method uses Return to confirm the current conversion mid-sentence. When the last
field read reported `present`, the coordinator hands that Return to capture as a
keystroke (`SuggestionCoordinator.endsLine`), so the half-typed line is neither learned
nor reset; the Return that sends the line, with no marked text before it, commits as usual.

**The dictation read leaves the marked run out of the caret sides.** `MacContextEngine` reads
the same attribute through `CompositionProbe.markedRange`, widens the selection to cover the
marked run before `CaretText.around` cuts the value, and reports `FocusedWindow.isComposing`. So
text that is still provisional never pads or cases a dictation. Nothing waits on that flag yet.

## What works: `AXTextInputMarkedRange`

The attribute is `NSAccessibilityTextInputMarkedRangeAttribute`, declared in AppKit's
`NSAccessibilityConstants.h` and available since macOS 10.6. It is public, not private;
its header comment says "range of visible text", which is wrong, and the measurements
below are what it actually holds. Read cross-process it is the string
`"AXTextInputMarkedRange"` on the focused element.

Measured by driving `setMarkedText(_:selectedRange:replacementRange:)` on a real
`NSTextView` — the same call an input method makes, through the same AppKit path — and
reading the result back through `AXUIElementCopyAttributeValue`:

| Moment | `AXError` | Value |
|---|---|---|
| Idle, caret after `hello ` | `success` | `loc:6 len:0` |
| Composing `にほんご` | `success` | `loc:6 len:4` |
| Composition shortened to `にほ` | `success` | `loc:6 len:2` |
| Committed (`unmarkText`) | `success` | `loc:8 len:0` |
| Cancelled (empty marked text) | `success` | `loc:8 len:0` |
| The same reads on an `NSTextField` | `attributeUnsupported` | — |

Three things follow.

**The tri-state is clean.** `success` with a positive length is composing; `success` with
zero length is not composing and settles the question; `attributeUnsupported` means the
field has said nothing. That maps exactly onto `MarkedText`.

**Length tracks the composition, not just its start.** It shrank from 4 to 2 when the
composition did, and returned to 0 on both commit and cancel. There is no stuck state to
recover from.

**Whether a field answers is a property of the field, not of the moment.** The text view
advertised the attribute in its list of 24 attribute names while idle as well as while
composing. So one read answers both "will this field tell me" and "is it composing", and
a field that is silent is silent all the time rather than only at the interesting moment.

## How far it travels, which is not far

Presence was checked two ways: a cross-process Accessibility walk of the running
applications' window trees, and `strings` over the shipped binaries of the toolkits.
The `strings` method was validated by checking two control attributes in the same
binaries — `AXSelectedTextRange` and `AXInsertionPointLineNumber` are present in every
one of them, so an absent `AXTextInputMarkedRange` is a real absence and not a failed
grep.

| Target | Publishes the marked range |
|---|---|
| `NSTextView` — Notes, Mail, TextEdit, AppKit editors | **yes** |
| `NSTextField` — search boxes, single-line fields everywhere | no |
| Terminal (its own `AXTextArea`) | no |
| Google Chrome | absent from the binary |
| Electron — Cursor, VS Code, Slack | absent from the binary |
| WhatsApp | no |
| System Settings | no |

So the signal covers AppKit multi-line text views and nothing else. It notably does **not**
cover single-line fields, which is where a completion is worth most, nor any browser, nor
any Electron application.

`WKWebView` is unmeasured rather than negative: from an unbundled harness the focused
Accessibility element does not resolve for a web view, and walking its subtree from the
application element finds no text element. So WebKit — and therefore Safari — is not settled
either way, and Chromium's result does not speak for it.

## What does not work

**Nine other attribute names return nothing.** Probed by hand on a text view holding live
marked text: `AXMarkedTextRange`, `AXMarkedRange`, `AXHasMarkedText`, `AXTextMarkedRange`,
`AXSelectedTextMarkerRange`, `AXIsComposing`, `AXTextMarkerRange`,
`AXInputMethodComposing`, `AXMarkedTextValue`. Exactly one of the ten names tried
resolved, and it is the one above.

`kAXSelectedTextMarkerRange` is worth naming separately because it looks like the answer
and is not. It is WebKit's text-*marker* API — opaque tokens for positions in web content
— and has nothing to do with an input method's *marked* text.

**The selection does not change shape during composition.** `AXSelectedTextRange` was a
zero-length caret both idle and composing, and `AXSelectedText` was empty in both. There
is no "marked text shows up as a selection with particular characteristics" to detect.

**The attributed string carries no marker.** Marked text is drawn underlined, and
`AXUnderline` is an attribute Accessibility can carry, so this looked promising. It is
not: the runs returned by `AXAttributedStringForRange` over composing text were
`AXATextAlignmentValue, AXFont, AXForegroundColor` — identical to the runs over committed
text. Neither the underline nor `NSMarkedClauseSegment` survives into Accessibility.

**`AXValue` contains the uncommitted text** but offers no way to tell it from committed
text, so it cannot be used to infer composition.

**`NSTextInputClient` is not reachable.** It is implemented by the application being typed
into. Uttrflow is not that application, so the protocol is out of reach by construction.

## The fallback: the input source's kind

Where the field will not answer, all that is left is whether the selected input source
*could* be composing (`InputSourceKind`). `TISCopyCurrentKeyboardInputSource` with
`kTISPropertyInputSourceType` gives four keyboard types: `TISTypeKeyboardLayout`, a static
key map that cannot compose, against `TISTypeKeyboardInputMethodWithoutModes`,
`TISTypeKeyboardInputMethodModeEnabled` and `TISTypeKeyboardInputMode`, which can. Of the
311 keyboard input sources installed on the measuring Mac, 251 are layouts and 59 are input
methods or their modes.

**The source's type is used, not whether it is Roman.** Suppressing when the current input
source is not Roman is wrong in both directions, and Hindi is the case that shows it:

- `com.apple.keylayout.Devanagari` and `com.apple.keylayout.Devanagari-QWERTY` are plain
  layouts. They are not ASCII-capable and they never compose. The Roman test turns the
  feature off for a Hindi typist who is typing perfectly ordinary Devanagari; the type
  test leaves it on.
- `com.apple.inputmethod.Kotoeri.RomajiTyping` and all four `com.apple.inputmethod.VietnameseIM`
  modes report `kTISPropertyInputSourceIsASCIICapable` as true and **do** compose —
  Vietnamese Telex builds its diacritics through marked text. The Roman test lets them
  through, and a ghost would be drawn over live marked text.

So the fallback computes: the current source is not a plain keyboard layout, therefore
composition is possible. It is right where the Roman test is wrong in both of the cases
above.

**Why the fallback does not gate.** It is a capability, not a state: it says composition is
*possible*, never that it is *happening*. Used as a gate it costs this:

- A user of any Chinese, Japanese, Korean, Vietnamese or Hindi-transliteration input
  method gets no suggestions at all in any field that does not publish a marked range —
  which, per the table above, is Chrome, every Electron application, Terminal, and every
  single-line field. That is most of the surface the feature exists for.
- `com.apple.inputmethod.Kotoeri.RomajiTyping.Roman` — the ASCII mode a Japanese user
  switches to in order to type English — is an input *mode*, so it is suppressed even
  though it can never compose. Refining with `kTISPropertyInputSourceIsASCIICapable` would
  rescue exactly that case and re-break Vietnamese Telex and Kotoeri's parent mode, both
  ASCII-capable and both composing.

The field's own answer always wins in the computed value where there is one, so an AppKit
text view under a Japanese input method that is *not* composing reads as not composing.
That is why the state signal is gated on despite its reach: a `present` answer is a
measured state, not a guess, and fields that never answer keep their suggestions.

## Text Input Sources must be called on the main queue, so it is not called on the read path

`TISCopyCurrentKeyboardInputSource` and `TSMGetInputSourceProperty` go through HIToolbox's
`islGetInputSourceListWithAdditions`, which calls `dispatch_assert_queue` on the main queue.
Called from anywhere else the process is killed outright with `EXC_BREAKPOINT`, and
`FocusedFieldReader` reads on a private queue so an Accessibility read can never block the
keystroke path.

Hopping to the main queue and waiting would put exactly that block back, on exactly the
path the private queue exists to keep clear. So the input source is not read on the read
path at all. `CompositionProbe.startObservingInputSource` reads it once on the main queue when
the loop starts, re-reads it on the main
queue whenever `kTISNotifySelectedKeyboardInputSourceChanged` arrives through
`DistributedNotificationCenter`, and kept in a `Mutex` that any thread may read with no
system call in it. The input source changes when a person presses a key combination to
change it, which is many orders of magnitude rarer than a keystroke, so a cache is both
correct and cheaper than the call it replaces.

Until the first read lands the cache holds `.unknown`, and `.unknown` may compose — so in
the window before start-up completes the computed value reads as composing. With the gate
off nothing is withheld by it; were the gate on, that window would be silent rather than
risk a ghost over live marked text.

`NSScreen` is main-thread-only too, and the read path needs the primary screen's top edge to
flip Accessibility coordinates into AppKit ones (`SuggestionGeometry.fromAccessibility`). It is
read on the main actor and cached the same way.

The frontmost application's identity is read on the main actor first. `FocusedFieldReader.read`
and `.surroundings` both call `frontmostApp()`, a `@MainActor` function that asks
`NSWorkspace.shared.frontmostApplication` for the process identifier, bundle identifier
and name, and hand that `FrontmostApp` value to the private queue; the blocking read on
the queue never touches `NSWorkspace`. The name is stripped of control and direction marks
on the way, since some applications pad theirs and the model would otherwise read them
verbatim.

## Limits

1. **WebKit is unmeasured.** Safari is the most valuable unknown in the table.
2. **Dead keys compose on a plain layout.** `com.apple.keylayout.USExtended` holds marked
   text for one keystroke after `⌥e`, and `.layout` claims that cannot happen. Where the
   field answers, the field is right and this costs nothing; where it does not, there is a
   one-keystroke window in which a ghost could sit over a dead-key accent.
3. **A third-party input method could classify itself as a layout.** Not observed among
   the 311 installed sources, but nothing enforces the classification.
4. **Presence was measured per application, not per field.** An application could publish
   the attribute on one field and not another.
5. **Composition was driven in-process rather than by a live input method.** `setMarkedText`
   is the same call an input method makes through the same AppKit path, so the field's state
   is identical, but the table has not been checked with a real Japanese input method in front
   of it.

Every cross-process read on this page was made from an unsigned binary launched from a terminal
that holds the Accessibility grant, which the binary inherits ([predict-probe.md](predict-probe.md)).
