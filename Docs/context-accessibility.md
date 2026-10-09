# What applications actually answer

`MacContextEngine` (`Sources/UttrflowContext/MacContextEngine.swift`, with the system reads in
`MacContextEngine+System.swift`) describes what the user is looking at when they dictate: the
application, its window title, the selection and the text around the caret. It gathers that from
two sources with very different costs, and the split between them is what makes its guarantee —
never make the user wait — real rather than hoped for. `uttrflow-dev context` prints one reading
of the frontmost application and how long it took. A command-line tool is not a representative
test bed for the Accessibility API, and a well-behaved application never exercises the broken
path, so the readings below are of real applications on the desktop.

The tables here also feed the `Value` column of [compatibility.md](compatibility.md). The budget
and its numbers are in [context-budget.md](context-budget.md).

## Identity is free; the window is not

| Source | Cost | Permission | Can hang |
| --- | --- | --- | --- |
| `NSWorkspace`: name and bundle identifier | free | none | no |
| Accessibility: window title, selection, caret text | a message to another app | required | yes |

Without an Accessibility grant, `uttrflow-dev context` still reads the application's name and
bundle identifier from `NSWorkspace`, while every Accessibility call returns `kAXErrorAPIDisabled`
and the window title and selection stay empty.

So the two are gathered in that order and recorded as they arrive: identity first, banked the
moment it lands, then the window read, which is the part allowed to hang. The window read banks
each answer as it arrives: the title first, then the role, label and selection once the secure
check has finished, then the caret text. Whatever the budget interrupts, the application name and
every answer already banked are kept; a field whose secure check did not finish gives no text.

## Applications answer the halves separately

`FocusedWindow`'s title, selection and caret text are separately optional because applications
answer them separately:

| Application | Window title | Selection |
| --- | --- | --- |
| Google Chrome | yes | refused (`kAXErrorNoValue`) |
| Terminal | yes | yes |
| Slack | no | no |

The reads are issued separately and each is kept on its own: an application that names its window
but hides its selection still yields the half it was willing to give. Between reads,
`read(_:while:)` checks whether its caller is still waiting and stops sending messages once it is
not.

Two answers end the read early. A focused field that is secure (`FieldNames.isSecure`, from its
role, subrole and names, or a value of mask characters alone) yields only the window title and
`isSecure`, so none of its text can reach a prompt. Dictation and suggestions ask the names with
`SurfaceProbe.names(of:)` and the value with `SurfaceProbe.text(of:names:at:)`, so the secure order
and the bounded value window (`ValueWindow`) are one implementation. A field with several separate
selections yields only the title, since no one selection is the caret.

## Why a read carries no text

A field the read never reached and a field that is truly empty must not look alike, so
`AppContext.unavailable` names why the caret text is missing; it is `nil` when the read reached
the text, an empty field included (`precedingText` is then `""`, not `nil`). The reason is derived
where the read ends, from the `FieldAnswer` kinds the tree already tells apart, with no second
classification:

| Reason | Where the read ends |
| --- | --- |
| `notTrusted` | any message answers `kAXErrorAPIDisabled`, which `FieldAnswer` keeps as `.notTrusted`; the window read is not gated on `AXIsProcessTrusted`, so the first batch says it |
| `noFocusedElement` | the application answers no focused element |
| `refused` | a message cannot complete, the field names no role, its value gives no caret text, or it holds several selections |
| `timedOut` | a message times out, `MacContextEngine.budget` expires before the read ends, or the dictation's screen-read limit is spent |
| `secure` | the field declares itself secure or its value is mask characters alone |

Formatting does not read the reason; every formatter keeps its default for a missing side.
`uttrflow-dev context` prints it beside the read rung. `ContextUnavailableReasonTests` drives each
reason through the fake tree.

## macOS will not say what is behind the front window

`MacContextEngine` remembers the last application in front that was not Uttrflow, because there is
no way to ask: `runningApplications` comes back in launch order, not activation order. Watching the
front change is the only source, so the engine subscribes to
`NSWorkspace.didActivateApplicationNotification` for as long as it exists, independently of
whether a read is in flight.

Uttrflow is never the right answer for a context. Its own window comes forward for settings,
onboarding and permission prompts, and "you are dictating into Uttrflow" is both useless and false:
the words are on their way somewhere else. The application that was in front before is the answer;
when there has not been one, there is none. With Uttrflow's own window in front the focused window
is Uttrflow's, so it is not read at all: filing its title under the application behind it would be
wrong.

Uttrflow is recognised two ways because either can be missing. The process identifier always
holds; the bundle identifier is absent when Uttrflow runs unbundled from the command line. Bundle
identifiers are compared only once ours is known, so an application that reports none never matches
an Uttrflow that has none either.

## Text an application does not publish is not read

Canvas editors, remote windows and some web editors publish no text through Accessibility. Their
context is empty, and that is the answer. Three ways of getting the text anyway are rejected:

| Route | Why it is rejected |
| --- | --- |
| Post select-all and copy, then read the clipboard | Overwrites the user's clipboard, moves their selection, and costs a round trip through another app's event loop. |
| Capture the screen | Needs the Screen Recording permission, which the product does not ask for. |
| Recognise text in a capture | All of the above, plus a recognition pass of 100 ms or more, and it reads text the person never typed: menus, other windows, other people's messages. |

`Scripts/context_reach_audit.py` (`make context-reach-audit`, run by `make verify`) fails when a
context module names the clipboard, posts a key event, or uses screen capture or text recognition.

## What a field calls itself

A mail subject, a recipient list, a search box and an address bar are all one-line fields; only
their names tell them apart. The focused-field read asks `AXTitle` in the same batched message as
the names the secure check already reads (`AXRole`, `AXSubrole`, `AXIdentifier`,
`AXPlaceholderValue`, `AXDescription`), so the label adds no message. `AppContext.fieldLabel`
is the title, else the placeholder, else the description, as one line with control characters removed
and cut to `AppContext.fieldLabelLimit` characters. A secure field carries no label. A field label is
untrusted; when a suggestion prompt uses it as a locator, the prompt builder scrubs controls and
format marks, caps it, and puts it in a fenced data block with an instruction not to follow its contents.
Secure `FieldReading`s also have no locator or corpus surface. `FieldRole` rejects secure subroles,
then gives search, multiline and one-line field structure precedence over labels; only when structure
does not identify a field does it match an exact known label. Longer labels such as “Message to Alice”
cannot turn an ordinary text field into a recipient field, and exact labels such as “To” or “Subject”
cannot override a reported text-field role. The prediction register does not use
labels to choose search or address history gates: search requires the structural `AXSearchField`
role, and address behavior comes from the typed text or the person's recent address-shaped lines.

The label of an `AXTitleUIElement` link is not read: following it costs a second element and a
second message. Which of these attributes each application fills for each field, and whether the
link is needed, is not yet measured on this page.

## Core Foundation casts

Every element and value that comes back from Accessibility is checked by type ID and then
`unsafeDowncast`. A conditional cast cannot express this: Swift treats `as?` on a Core Foundation
type as always succeeding, so it would silently accept a non-element.

## Why the `+System` files are excluded from coverage

`Scripts/coverage_report.py` excludes `MacContextEngine+System.swift`, `SurfaceProbe+System.swift`,
`FocusedFieldReader+System.swift`, `FocusedFieldReader+AXElementTree.swift` and
`CompositionProbe+System.swift` with a stated reason each: every line reaches into another running
application or asks the window server about one. What they must never do — wait — is decided in
`MacContextEngine` and `withDeadline` (`Sources/UttrflowCore/Support/StageTimeout.swift`) and
tested there. All five are under the 400-line limit `make exclusion-audit` sets for an excluded
file.

What the focused-field read decides from its answers is not in them. It is
`FocusedFieldReader.snapshot(of:in:from:while:)` (`FocusedFieldReader+Snapshot.swift`), with the
selection and marked-text reads in `FocusedFieldRead`, all written over `ElementTree`.
`FocusedFieldReader.AXElementTree` sends the messages and `FieldAnswer` keeps a value, no value,
unsupported, cannot complete and timed out apart, so `FocusedFieldSnapshotReadTests` drives each
refusal through a fake tree and asserts the fallback the read takes.

Related: [accessibility-private-api.md](accessibility-private-api.md) for the one private symbol
`FocusedFieldReader+System.swift` calls.
