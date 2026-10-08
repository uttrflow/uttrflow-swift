# The key events this app posts, and what the system does with them

Uttrflow posts keyboard events in two places, both in `Sources/UttrflowInput/SystemInput.swift`:
`CGEventKeystrokeSender` presses ⌘V for the paste strategy, and `CGEventTypist` types characters
for dictation and accepted suggestions and presses Delete when a suggestion replaces text. The
events enter the same stream the user's own keyboard feeds, through `postTaggedKeyPair`. An event
can carry both a Unicode string and a physical key code, and the receiving application decides
which it reads. [insertion.md](insertion.md) covers which route posts them; this page covers what
is in them.

There are no per-application results here: a posted event carries the same thing wherever it
lands. This page feeds the `Completion` column of [compatibility.md](compatibility.md) and the undo
note beside it.

## Every posted event is stamped as ours

Three readers see this app's own synthetic keys upstream of the target application: the dictation
shortcut's tap in `SystemKeyboard`, the suggestion tap in `KeyInterceptor`, and the `NSEvent`
monitor in `SuggestionCoordinator`. Untagged, accepting a completion with Tab would type a Tab that
the tap then read as another accept.

`SyntheticEvent.tag(_:)` writes `SyntheticEvent.sentinel` into `.eventSourceUserData` before the
event is posted, and all three readers drop anything for which `SyntheticEvent.isOurs(_:)` is true.
The sentinel is not zero: an event that never had the field set reads as zero, so zero would make
every ordinary keystroke look like ours.

## Typed text uses one mapped key per character

`CGEventTypist.type(_:)` posts one key-down and key-up per grapheme cluster. Each event carries that
cluster as its Unicode string and the current layout's physical key code for the same character,
with Shift, Option or both set when the layout needs them (`LayoutKeyCode.stroke(for:in:)`). A
field that reads the Unicode string gets the character, and a field that reads physical keys gets
a matching key and modifiers instead of key code 0.

For one `type(_:)` or `deleteBackwards(_:)` call, the typist constructs and tags every key pair
before posting the first pair. Event-construction failure therefore posts none of that call's
characters or Delete presses; an error from a later chunk cannot leave part of that chunk posted.

A cluster with no single key on the selected layout — a character above U+FFFF, one reached only
through a dead key (é on a US layout), a cluster of several scalars (a ZWJ emoji, a flag, a letter
with combining marks, a Devanagari conjunct), or any Latin letter while a Devanagari, Cyrillic,
Arabic, Hebrew or Greek layout is selected — is posted as its own key pair with key code 0, no
modifiers and all of the cluster's UTF-16 units as the Unicode string
(`LayoutKeyCode.keypresses(for:stroke:)`). A field that renders per event therefore never shows
a cluster cut in two; the chunks of `TypedTextInsertionEngine` are counted in clusters too.
One unmapped character therefore never refuses the rest of the text; it falls back to the plain
Unicode-string event the typed route used before layout keys were added.

The event format alone does not establish which representation a particular application uses.
The `Completion` column in [compatibility.md](compatibility.md) records observed results by
application without separating the two; terminal emulators, cross-platform editors, remote
desktops, virtual machines and games need measurements that do.

### Control characters are never typed as keys

A layout maps U+000D to Return and U+0009 to Tab, so looking up a key for them would send a chat
message, run a shell line or move focus to the next field mid-text. `LayoutKeyCode.controlPolicy(for:)`
gives every scalar in U+0000 to U+001F and U+007F one policy, applied before any key lookup:

| Scalars | Policy |
|---|---|
| LF, CR, CR LF, VT, FF | one line break, posted as the Unicode string U+2028 with key code 0 |
| Tab | a space |
| every other control, and DEL | the whole text is refused before any key is posted |

What each target class renders for a posted U+2028 is not yet measured.

### Option-only characters

A character the layout reaches only with Option held is posted with `.maskAlternate` set. On US
QWERTY that is ¬, √, ∑, © and π, among others (`LayoutKeyCode` tests pin the strokes). A target
may read an Option-flagged key as a command or a dead key instead of reading the Unicode string.
What each target class does with these events is not yet measured:

| Target class | Result for Option-flagged typed symbols |
|---|---|
| Terminal emulator | not measured |
| Code editor | not measured |

## Flags are set on every event

A modifier the user is still holding when the paste or the typing goes out would otherwise be
applied to it: the shortcut is held while a dictation ends, so ⌥ on a typed `t` becomes `†`, and a
Delete with ⌥ held deletes a whole word. Every posted event sets `flags` explicitly rather than
inheriting the current state: `.maskCommand` for ⌘V, the layout's own modifiers for a typed
character, and none for Delete.

## One Delete per character

No bulk delete is reachable from a synthetic keyboard, so taking back what a completion replaces
costs one key pair per character (`deleteBackwards(_:)`, key code 51, which is positional and so
the same on every layout). That is why the target's undo sees several edits on the typed route and
one on the Accessibility route; [predict-accept.md](predict-accept.md) has what ⌘Z costs on each.

## The key code for ⌘V is resolved, not fixed

A key code is a key's position, but an application matches a ⌘ shortcut against the character the
current layout gives that position. On US QWERTY, key code 9 types V; on Dvorak the same position
types `k`, so posting key code 9 fires ⌘K.

`PasteKeyLayout` reads the selected layout's table with `UCKeyTranslate`, with ⌘ held so a layout
with a separate ⌘ table (Dvorak – QWERTY ⌘) is read from that table, and caches the key code that
produces `v`. When the selected layout has no Latin letters it reads the system's ASCII-capable
layout instead, and when neither can be read it posts key code 9. The cache fills on
`startObserving()` and follows `kTISNotifySelectedKeyboardInputSourceChanged`, refreshed on the
main queue because Text Input Sources asserts it, the way `CompositionProbe` reads input sources.
The same cached table supplies the typed route's key codes. `LayoutKeyCode.code(for:in:modifiers:)`
is the pure lookup, and `Tests/UttrflowInputTests/LayoutKeyCodeTests.swift` checks it against real
layout tables: US QWERTY, AZERTY, Dvorak, Dvorak – QWERTY ⌘, and Russian.
