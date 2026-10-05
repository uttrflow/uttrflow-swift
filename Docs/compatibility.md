# What each kind of application actually does with the words

Dictation, clip insertion and tab-to-complete all depend on things no part of this codebase
controls: whether another application publishes its focused field through Accessibility, whether
it takes a synthetic ⌘V or typed keys, and whether it says where the caret is. Each is a property
of the receiving application, so the only way to know is to put words into that application and
look. This page collects those readings, one table per class of application. The measuring tools
are the `uttrflow-dev` subcommands in `Sources/uttrflow-dev/` (`insert`, `probe surface`,
`probe ime`, `doctor`); each row links the page that holds the reasoning behind it.

**Nothing here is inferred from the code.** A cell is a measurement or it is blank. Blank means
nobody has run that check on that application, not that the answer is no; `unknown` is written
where a page says something was tried and did not settle. Every defect these pages record is a
case where the code's own belief about an application was wrong, so reading a capability off the
source would defeat the page.

## The columns

| Column | Values | How it is measured |
|---|---|---|
| App | name, version, macOS version | the application's About window |
| Field | single-line, multi-line, rich editor, spreadsheet cell, secure, chat composer, address bar, shell | by inspection |
| Published | yes / no / only after `AXManualAccessibility` or `AXEnhancedUserInterface` | `uttrflow-dev probe surface` |
| AX write | lands / refused / reports success, changes nothing / lands late | `uttrflow-dev insert --via accessibility` |
| Paste | lands / ignored / other shortcut fires / forwarded elsewhere | `uttrflow-dev insert --via paste` |
| Confirmed | landed / not reported / gave up | the same run's printout, with the caveat below |
| Full route | once / twice / nowhere | `uttrflow-dev insert`, no `--via` |
| Caret | right / wrong place / none | `uttrflow-dev probe surface`, plus looking at the screen |
| Value | yes / value only / no | `uttrflow-dev probe surface` |
| Marked text | yes / no | `uttrflow-dev probe ime` |
| Completion | correct / wrong characters / nothing | accept a suggestion in the application |
| Undo | one step / several / undoes nothing / undoes more than the dictation, plus whether a replaced selection came back | `uttrflow-dev insert --via <route> --then-undo`, once at a bare caret and once over a selection |
| Notes | line breaks, undo, right-to-left, anything surprising | |

`Full route` is the route `uttrflow-dev insert` takes with no `--via`: `TextInsertion.coordinator`,
which is Accessibility, then paste, then the clipboard floor — the route a clip inserted from the
menu bar or main window takes. Dictation and an accepted suggestion take Accessibility then typed
keys ([insertion.md](insertion.md), "Which route each insertion takes"); `--via typed` forces
the typed strategy those two fall back to.

### Typed substitutions

Typed keys reach a text view's own substitutions, which an Accessibility write bypasses. Run each
string with `uttrflow-dev insert --via typed "<string>"` in a field with the system's defaults and
compare the `read back:` line with the input; `changed by the field: true` names a substitution.

| String | What it reaches |
|---|---|
| `"quoted" and 'single'` | smart quotes |
| `one -- two` | smart dashes |
| `omw` | text replacement, with the system's default entry present |
| `first. second` | automatic capitalisation |
| `Uttrflow teh` | automatic spelling correction |

The read-back takes as many characters before the caret as were typed, so a substitution that
changes the length shows a shifted window rather than the whole string.

### Reading an `Undo` run

`--then-undo` reads the focused field through Accessibility, inserts, waits half a second, reads
it again, posts one ⌘Z, waits, and reads it a third time. `UndoProbe.classify` compares the three
values exactly: back to the first reading is `one step`; unchanged from the second is `undoes
nothing`; part of the insertion gone with the text on both sides of it intact is `several`; any
other change is `undoes more than the dictation`. With a selection in the first reading it also
prints whether the selection came back. A field that will not report its value prints
`unreadable`, and the cell is filled by looking at the screen instead. Where a cell is `several`,
press ⌘Z again until the field is restored and write the count in Notes.

### Reading a `--via` run

Every `--via` run is built by `TextInsertion.coordinator(only:)`, the factory the app uses, so a
forced strategy still asks the focused field whether it is secure, reads the destination and
reports how long a paste took to land. Each run prints `destination:` and `secure:` under the
`Inserted via …` line.

`uttrflow-dev doctor` reports the three things that look identical from outside: whether
Accessibility is granted, whether anything is focused, and whether the focused field reports its
selection. Run from a terminal, the grant it reads is the terminal's.

**"Reports success, changes nothing" does not print as success.**
`SelectionWriter.replaceSelection(with:)` checks that the selection collapses to the expected
caret after the write. A field that accepts the write and leaves the selection where it was, or
reports no selection afterwards, fails with "The app hasn't confirmed whether the text was
inserted"; a field whose caret moves while its text does not fails as refused. Record the column
from that message, not from the screen.

## Browsers

The engine matters here, not the brand: the rows below differ on the one column that decides
whether anything can be drawn at all.

| App | Field | Published | AX write | Paste | Confirmed | Full route | Caret | Value | Marked text | Completion | Undo | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Google Chrome | address bar | | | | | | | value only | no | | | Window title answered; the selection is refused with `kAXErrorNoValue`, so half the context read comes back ([context-accessibility.md](context-accessibility.md)). `AXTextInputMarkedRange` is absent from the binary, checked against two control attributes that are present ([predict-ime.md](predict-ime.md)) |
| Google Chrome 153, macOS 26.5.1 | single-line | only after `AXEnhancedUserInterface` | | | | | right | yes | | | | With the full tree off, value and selection answer and every caret bound is a zero-size rectangle, so there is no placement. Chrome refuses `AXManualAccessibility` and applies `AXEnhancedUserInterface` while answering the write as not implemented; the suggestion loop turns it on for a caretless field once per process and off when suggestions stop. The caret was right about two seconds after the switch ([predict-reliability.md](predict-reliability.md)) |
| Google Chrome 153, macOS 26.5.1 | multi-line | only after `AXEnhancedUserInterface` | | | | | right | yes | | | | As the single-line row. The text-marker selection (`AXSelectedTextMarkerRange` measured with `AXLengthForTextMarkerRange` from the field's start) agreed with `AXSelectedTextRange` across a line break, and is what the reader uses where the range is refused ([predict-reliability.md](predict-reliability.md)) |
| Google Chrome 153, macOS 26.5.1 | rich editor in a page | yes | | | | | right | yes | | | | A code editor that renders its own text keeps an empty one-pixel textarea focused at the caret, so the field has neither a line nor a caret. The reader takes the line from the rendered row the textarea sits on, split at the textarea's position, and that row's height for the caret; measured on a SQL-mode editor with `SELECT id, name FROM users WHERE` typed: line read whole, caret at the line's end, `inlineGhost`, about 8 ms a read ([predict-reliability.md](predict-reliability.md)) |
| Safari 26.5, macOS 26.5.1 | code editor in a page | yes | | | | | right | yes | | | | WebKit widens the hidden textarea such an editor keeps at the caret to about 1 000 × 14 pt, so an empty text area one bare line tall (18 pt at most) is taken as the parked input too. WebKit lays each highlighted run of a line straight into the editor rather than into a line element, so such runs share a row by their parent and their line band. Measured on a SQL-mode editor with `SELECT id, name FROM users WHERE` typed: line read whole, caret at the line's end, `inlineGhost`, about 8 ms a read warm ([predict-reliability.md](predict-reliability.md)) |
| Google Chrome 154.0.8037.97, macOS 26.5.1 | script-controlled input and contenteditable in a page | | reports success, changes nothing | | | | | yes | | | | Neither the text shown nor the page's own state changes, for an input and for two kinds of `contenteditable`; the caret check reports it unconfirmed. An `AXValue` write instead shows the text in a `contenteditable` without telling the page, and a model-driven editor's next keystroke reverts it ([insertion.md](insertion.md), "A web field's own state") |
| WebKit `WKWebView` (Safari 26.5's engine), macOS 26.5.1 | script-controlled input and contenteditable in a page | | reports success, changes nothing | | | | | yes | | | | As the Chrome row for `AXSelectedText`. An `AXValue` write reaches the page as delete-all then insert-all events ([insertion.md](insertion.md), "A web field's own state") |
| Safari | address bar | | | | | | | | unknown | | | The marked-range walk could not resolve a focused element for a `WKWebView`, and walking the web view's subtree found no text element, so WebKit's answer is unmeasured; Chromium's result does not speak for it ([predict-ime.md](predict-ime.md)) |

## Applications built on a bundled browser engine

Every failure in this class has the same shape: the application answers, and the answer is not
true.

| App | Field | Published | AX write | Paste | Confirmed | Full route | Caret | Value | Marked text | Completion | Undo | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Claude desktop | chat composer | yes | reports success, changes nothing | | | | right | | no | | | The write is accepted, answers `.success`, and changes nothing, so every write is read back ([insertion.md](insertion.md)). Every Chromium field answers the caret's glyph bounds with a zero-size rectangle at a false position; the selection's text-marker range has real bounds, and the caret is read from it ([predict-reliability.md](predict-reliability.md)) |
| Cursor | rich editor | no | | lands | | | | | no | | | Exposes no focused element at all and takes a ⌘V. Typed delivery, the dictation route here, is not measured ([input-paste-eligibility.md](input-paste-eligibility.md), [input-synthetic-keystrokes.md](input-synthetic-keystrokes.md)) |
| Slack | — | | | | | | | no | no | | | The reading is of the window, not of a focused field, so `Published` stays blank. Neither a window title nor a selection ([context-accessibility.md](context-accessibility.md)); `AXTextInputMarkedRange` absent from the binary ([predict-ime.md](predict-ime.md)) |
| Visual Studio Code | | | | | | | | | no | | | Marked range absent from the binary. Nothing else measured ([predict-ime.md](predict-ime.md)) |
| WhatsApp | chat composer | | | | | | | no | no | | | Messages are published as static texts with an empty value and the text in the description, date headings are nested, and the recipient appears only as a group label, so the collector reads the description as a text fallback. Every bubble's label glues its timestamp on ("3Septemberat6:41 PM"), which a model then imitates, so stamps are stripped from every label read ([predict-reliability.md](predict-reliability.md)). The marked range is not published ([predict-ime.md](predict-ime.md)) |

## Native AppKit

| App | Field | Published | AX write | Paste | Confirmed | Full route | Caret | Value | Marked text | Completion | Undo | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Notes | multi-line | | | | | | | | yes | | | An `NSTextView`: publishes `AXTextInputMarkedRange`, and it tracks a composition faithfully — `loc:6 len:4` while composing `にほんご`, `len:2` when the composition is shortened, back to length zero on commit or cancel ([predict-ime.md](predict-ime.md)) |
| Mail | multi-line | | | | | | | | yes | | | The same `NSTextView` reading ([predict-ime.md](predict-ime.md)) |
| TextEdit | multi-line | yes | | | | once | right | | yes | correct | | `Published` and `Caret` follow from the harness drawing an inline ghost here, which needs both. One of the four surfaces the live end-to-end harness runs in, so the drawn ghost, the accepted key and the read-back are exercised here every cycle ([predict-reliability.md](predict-reliability.md)) |
| Messages | chat composer | | | | | | | | no | | | A single-line `NSTextField` does not publish the marked range ([predict-ime.md](predict-ime.md)). The person's own recent lines from this conversation are offered before lines from other conversations ([predict-reliability.md](predict-reliability.md)) |
| Finder | search field | yes | | | | once | right | | no | correct | | `Published` and `Caret` as for TextEdit. The second live-harness surface ([predict-reliability.md](predict-reliability.md)) |
| System Settings | search field | | | | | | | | no | | | ([predict-ime.md](predict-ime.md)) |
| MacVim | editor buffer | | | | | | | | | | | Not yet measured in normal or insert mode. In normal mode every typed letter is a command, so its `DestinationRules` row sets `keysMayBeCommands`: the typed route refuses before posting a key, and a dictation keeps its words for an explicit copy with the usual notice. A modal editor running inside a terminal is read as the terminal, so this flag does not reach it |
| — | any single-line `NSTextField` | | | | | | | | no | | | The marked range reaches AppKit multi-line text views and nothing else, so it misses single-line fields, where a completion is worth most ([predict-ime.md](predict-ime.md)) |
| — | any secure field | | | | | | | no | | A password or PIN field takes the words like any other field and nothing else does: the outcome is marked `intoSecureField` and the words reach no store — no history row, not even a length, no clip, no dictionary lesson — and the floating button neither draws nor reads them. A clipboard write carries `org.nspasteboard.ConcealedType` ([insertion.md](insertion.md)) | |

## Terminals

| App | Field | Published | AX write | Paste | Confirmed | Full route | Caret | Value | Marked text | Completion | Undo | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Terminal | shell | yes | refused | | | once | right | yes | no | correct | | Window title and selection both answered ([context-accessibility.md](context-accessibility.md)). Terminal takes a widened selection and refuses the text, so on the completion path, the only one that widens a selection, the caret is put back before the next strategy runs; a dictation writes at the caret and has nothing to restore ([predict-reliability.md](predict-reliability.md)). The marked range is not published even on Terminal's own `AXTextArea` ([predict-ime.md](predict-ime.md)). The third live-harness surface |

An address bar, the fourth live-harness surface, is measured under Browsers.

## Cross-platform toolkits

| App | Field | Published | AX write | Paste | Confirmed | Full route | Caret | Value | Marked text | Completion | Undo | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DBeaver (Java/SWT) | rich editor | no | | | | | none | no | | nothing | | The focused element is an `SWTComposite` or an outline and most reads fail outright; from the background the application reports no focused element at all, so nothing on the reading side can recover the line ([predict-reliability.md](predict-reliability.md)) |

## Office, spreadsheets, remote desktops and VMs, games

Nothing measured. No page in this repository records a reading from a spreadsheet cell, a remote
desktop, a VM window or a game, so there are no rows.

## Panels that take focus without activating

A non-activating `NSPanel` holding an `NSTextField` as first responder, shown by an accessory
process on macOS 26.5.1 while another application stayed frontmost:

| Read | Answer |
|---|---|
| `NSWorkspace.shared.frontmostApplication` | the other application |
| system-wide `kAXFocusedUIElementAttribute`, owner by `AXUIElementGetPid` | the panel's process, role `AXTextField` |
| the frontmost application's own `kAXFocusedUIElementAttribute` | its own editor, or no value |
| the panel process's own `kAXFocusedUIElementAttribute` | the panel's `AXTextField` |

The two owners differ, so the destination is the focused element's owner
([insertion.md](insertion.md), "Which application the record names"). A probe of a shipping
launcher's panel has not been run; this row is the synthetic panel only.

## How to add a row

One application, one field. Accessibility must be granted to the **terminal** you run from, not to
the binary: Accessibility is attributed to the responsible process, so an unsigned `swift build`
product inherits the terminal's grant ([predict-ime.md](predict-ime.md)).

1. Write down the application's version, from its About window, and the macOS version. A row
   without versions can only be re-measured, never re-confirmed.
2. `swift run uttrflow-dev doctor` with the field focused, to rule out a missing grant or an
   unfocused field.
3. `swift run uttrflow-dev probe surface --seconds 60`, then click into the field. Fills
   `Published`, `Caret`, `Value`.
4. `swift run uttrflow-dev insert --via accessibility "one two three"` and watch the screen.
   "Inserted via accessibility" is *lands*; "The text couldn't be inserted here" is *refused* (or
   *reports success, changes nothing* when the screen did not change); "The app hasn't confirmed
   whether the text was inserted" is the unconfirmed case in the caveat above, worth saying so in
   Notes.
5. `swift run uttrflow-dev insert --via paste "four five six"`. Fills `Paste` and `Confirmed`.
6. `swift run uttrflow-dev insert "seven eight nine"`, no `--via`, for `Full route` and the
   confirmation timing. *Twice* means two strategies both landed, which is a defect.
7. `swift run uttrflow-dev probe ime` for `Marked text`.
8. Accept a suggestion by hand for `Completion`, and dictate into the field for typed delivery
   (Notes).
9. `swift run uttrflow-dev insert --via typed --then-undo "ten eleven"` at a bare caret, then
   again with a word selected, and the same with `--via accessibility`. Fills `Undo` for each
   route; name the route in the cell when they differ.

Add the row under the right class heading, with a link in Notes to the page that holds the
reasoning. **Leave every cell you did not measure blank**: an empty cell tells the next person
what to measure, and a plausible one tells them not to bother. Use the field's own vocabulary in
`Field` rather than the application's name for it, so a chat composer sorts beside every other
chat composer.

## The pages this draws on

Each page owns its subject and feeds named columns here; none keeps a per-application table of its
own except where the table is the subject.

| Page | Feeds |
|---|---|
| [insertion.md](insertion.md) | `AX write`, `Paste`, `Confirmed`, `Full route`, and the secure-field row |
| [input-paste-eligibility.md](input-paste-eligibility.md) | `Paste`: when the route volunteers at all |
| [context-accessibility.md](context-accessibility.md) | `Value`: the window title and the selection, answered separately |
| [predict-ime.md](predict-ime.md) | `Marked text` |
| [predict-reliability.md](predict-reliability.md) | `Caret`, `Value`, `Completion`, and most of the Notes |
| [predict-probe.md](predict-probe.md) | `Published`, `Caret`, `Value` |
| [input-synthetic-keystrokes.md](input-synthetic-keystrokes.md) | `Completion` and the undo note. A posted event carries the same thing wherever it lands, so it has no per-application rows: one key pair per character with flags set explicitly, and one Delete per character replaced, which is why the target's undo sees several edits on the typed route and one on the Accessibility route |
