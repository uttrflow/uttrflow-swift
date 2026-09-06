# The key events this app posts, and what the system does with them

`CGEventKeystrokeSender` presses ⌘V and `CGEventTypist` types characters and presses
Delete. Both post events into the same stream the user's own keyboard feeds, which is
what makes them work everywhere and what makes each of the rules below necessary.
`Docs/insertion.md` covers where the events are posted; this page covers what is in them.

## Every posted event is stamped as ours

The feature reads the keyboard from two places — the `CGEventTap` in `KeyInterceptor` and
the `NSEvent` monitor in `SuggestionCoordinator` — and both see this app's own synthetic
keys upstream of the target application. Untagged, accepting a completion by pressing Tab
would type a Tab that the tap then read as another accept.

`SyntheticEvent` writes a sentinel into `.eventSourceUserData` before the event is posted,
and both readers drop anything carrying it. The value is deliberately not zero: an event
that never had the field set reads as zero, so zero would make every ordinary keystroke
look like ours.

## Sixteen UTF-16 units per event

`keyboardSetUnicodeString` takes a longer string without complaint and the window server
delivers a truncated one — no error, no short return, just missing characters at the end
of a dictation. `CGEventTypist` therefore chunks the text at 16 units and posts a pair of
events per chunk. Chunking is in UTF-16 units rather than characters because that is what
the API counts.

## Flags are cleared on every event

A modifier the user is still holding when the paste or the typing goes out is applied to
it: the shortcut is held down while dictation ends, so ⌥ on a typed `t` becomes `†`, and
a Delete with ⌥ held deletes a whole word instead of one character. Every posted event
sets `flags` explicitly rather than inheriting the current state — `.maskCommand` for the
⌘V, empty for everything else.

## One Delete per character

There is no bulk delete a synthetic keyboard can reach for, so taking back what a
completion replaces costs one key-down/key-up pair per character. That is also why the
target application's undo sees several edits on this route and one on the Accessibility
route; `Docs/predict-accept.md` has what ⌘Z costs on each.
