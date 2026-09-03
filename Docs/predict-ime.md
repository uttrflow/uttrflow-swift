# Detecting a composing input method

`Docs/predict-probe.md` left this open: nothing in the Accessibility API obviously reports
that a Hindi, Chinese or Japanese input method is mid-composition in another application,
and tab-to-complete must draw nothing and swallow nothing while one is. This is what was
measured, what works, and what it costs where it does not.

Re-run any of it with `uttrflow-dev probe ime`.

**Summary.** A real state signal exists and is public — `AXTextInputMarkedRange` — but it
only reaches AppKit multi-line text views. Everywhere else the answer is a capability
guess from the selected input source, which is a stopgap and is stated as one below.

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

`WKWebView` is unmeasured rather than negative, and two attempts failed to reach it: the
focused Accessibility element would not resolve for a web view, and walking the web view's
subtree from the application element found no text element at all. WebKit's Accessibility
appears not to come up for an unbundled harness. So WebKit — and therefore Safari — is not
settled either way, and Chromium's result does not speak for it.

## What does not work, checked rather than assumed

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

## The fallback, which is a stopgap

Where the field will not answer, all that is left is whether the selected input source
*could* be composing. `TISCopyCurrentKeyboardInputSource` with
`kTISPropertyInputSourceType` gives four keyboard types: `TISTypeKeyboardLayout`, a static
key map that cannot compose, against `TISTypeKeyboardInputMethodWithoutModes`,
`TISTypeKeyboardInputMethodModeEnabled` and `TISTypeKeyboardInputMode`, which can. Of the
311 keyboard input sources installed on this Mac, 251 are layouts and 59 are input methods
or their modes.

**Use the source's type, not whether it is Roman.** The obvious stopgap — suppress when
the current input source is not Roman — is not merely blunt, it is wrong in both
directions, and Hindi is the case that shows it:

- `com.apple.keylayout.Devanagari` and `com.apple.keylayout.Devanagari-QWERTY` are plain
  layouts. They are not ASCII-capable and they never compose. The Roman test turns the
  feature off for a Hindi typist who is typing perfectly ordinary Devanagari; the type
  test leaves it on.
- `com.apple.inputmethod.Kotoeri.RomajiTyping` and all four `com.apple.inputmethod.VietnameseIM`
  modes report `kTISPropertyInputSourceIsASCIICapable` as true and **do** compose —
  Vietnamese Telex builds its diacritics through marked text. The Roman test lets them
  through, and a ghost would be drawn over live marked text.

So the shipped fallback is: the current source is not a plain keyboard layout, therefore
assume composition. It is right where the Roman test is wrong in both of the cases above.

**It is still a stopgap, and here is the bill.** It is a capability, not a state: it says
composition is *possible*, never that it is *happening*.

- A user of any Chinese, Japanese, Korean, Vietnamese or Hindi-transliteration input
  method gets no suggestions at all in any field that does not publish a marked range —
  which, per the table above, is Chrome, every Electron application, Terminal, and every
  single-line field. That is most of the surface the feature exists for.
- `com.apple.inputmethod.Kotoeri.RomajiTyping.Roman` — the ASCII mode a Japanese user
  switches to in order to type English — is an input *mode*, so it is suppressed even
  though it can never compose. Refining with `kTISPropertyInputSourceIsASCIICapable` would
  rescue exactly that case and would re-break Vietnamese Telex and Kotoeri's parent mode,
  both ASCII-capable and both composing. Drawing nothing is the safe side of that trade
  and is the side taken.

The field's own answer always wins where there is one, so an AppKit text view under a
Japanese input method that is *not* composing still gets its suggestion. That is the whole
reason the state signal is worth having despite its reach.

## Text Input Sources must be called on the main queue, so it is not called on the read path

`TISCopyCurrentKeyboardInputSource` and `TSMGetInputSourceProperty` go through HIToolbox's
`islGetInputSourceListWithAdditions`, which calls `dispatch_assert_queue` on the main queue.
Called from anywhere else the process is killed outright with `EXC_BREAKPOINT` —
reproduced three times, on the first keystroke after tab-to-complete was armed, because
`FocusedFieldReader` deliberately reads on a private queue so an Accessibility read can
never block the keystroke path.

Hopping to the main queue and waiting would put exactly that block back, on exactly the
path the private queue exists to keep clear. So the input source is not read on the read
path at all. It is read once on the main queue when the loop starts, re-read on the main
queue whenever `kTISNotifySelectedKeyboardInputSourceChanged` arrives through
`DistributedNotificationCenter`, and kept in a `Mutex` that any thread may read with no
system call in it. The input source changes when a person presses a key combination to
change it, which is many orders of magnitude rarer than a keystroke, so a cache is both
correct and cheaper than the call it replaces.

Until the first read lands the cache holds `.unknown`, and `.unknown` may compose — so the
window before start-up completes suppresses suggestions rather than drawing one over live
marked text. That is the same side of the trade taken everywhere else on this page.

`NSScreen` is main-thread-only for the same reason and was being read on the same private
queue, for the primary screen's top edge that flips Accessibility coordinates into AppKit
ones. It is cached the same way, refreshed on `NSApplication.didChangeScreenParametersNotification`.
`NSWorkspace.shared.frontmostApplication` is also read there and is left alone: it vends
`NSRunningApplication`, which Apple documents as safe from any thread.

## Residual risk

1. **WebKit is unmeasured.** Safari is the single most valuable unknown in the table.
2. **Dead keys compose on a plain layout.** `com.apple.keylayout.USExtended` holds marked
   text for one keystroke after `⌥e`, and `.layout` claims that cannot happen. Where the
   field answers, the field is right and this costs nothing; where it does not, there is a
   one-keystroke window in which a ghost could sit over a dead-key accent.
3. **A third-party input method could classify itself as a layout.** Not observed among
   the 311 installed sources, but nothing enforces the classification.
4. **Presence was measured per application, not per field.** An application could publish
   the attribute on one field and not another. The application sweep in
   `Docs/predict-probe.md` is what would settle it.
5. **Composition was driven in-process rather than by a live input method.** No non-Roman
   input source is enabled on this Mac, and enabling one changes the operator's system
   settings. `setMarkedText` is the same call an input method makes through the same
   AppKit path, so the field's state is genuinely identical — but it has not been watched
   with a real Japanese IME in front of it, and item 4 above cannot be closed until it has.

## An aside that unblocks the pending sweeps

`Docs/predict-probe.md` records the application sweep and the event-tap probe as blocked
because "Accessibility is granted per binary, and `uttrflow-dev` does not have it". That
is not true when the binary is launched from a terminal that already has the grant: every
cross-process Accessibility read in this document was made from an unsigned scratch binary
run that way, and `AXIsProcessTrusted()` returned true. Accessibility is attributed to the
responsible process, which is the terminal. The sweeps still need somebody to click into a
text field in each application, but they no longer need a password.
