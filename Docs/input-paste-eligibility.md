# When the paste strategy volunteers

`PasteboardTextInsertionEngine` (`Sources/UttrflowInput/PasteboardTextInsertionEngine.swift`)
puts text on the clipboard and posts ⌘V. It is the second strategy on the clip routes — a clip
pasted from the panel, or inserted from the menu bar or main window — and is not on the dictation
or completion routes ([insertion.md](insertion.md), "Which route each insertion takes").
`canInsert()` declines for one case only: Uttrflow itself being the frontmost application.
Everything else is worth attempting.

Per-application results are in [compatibility.md](compatibility.md), whose `Paste` column this
page feeds.

## It does not ask Accessibility first

"Can the Accessibility API see a focused element" is the wrong precondition twice over.
Editors built on a bundled browser engine can expose no focused element at all and still accept a
⌘V, so the check would refuse exactly the applications the paste strategy serves. The same shape
appears in web views and anything that draws its own text: a focused element that will not report
its selection, which the Accessibility strategy cannot write into either.
[insertion.md](insertion.md), "The Accessibility write that changes nothing", has the other half of
the trap: a field that accepts an Accessibility write, answers `.success`, and changes nothing.

## Trying and failing costs nothing

The paste never restores the previous clipboard. If it is cancelled before ⌘V, it discards its own
unchanged write; after posting, arrival may be uncertain and the words stay on the clipboard. The
rules for cancellation and ownership are in [insertion.md](insertion.md). Declining costs the user
their insertion, so the engine volunteers and the coordinator finds out by trying.

## Never into Uttrflow itself

Uttrflow's own windows are where the user chooses a shortcut or reads clip history, and a ⌘V
posted while one is in front lands in the app's own text rather than the document the words were
for.

## Checked again at the write

`canInsert()` and `insert()` are two separate `await`s, so real time passes between them, long
enough for the user to switch to Uttrflow. `insert()` therefore asks again
(`PasteboardPasteAction.requireExternal`) before it writes the clipboard, and once more immediately
before it posts ⌘V (`postIfExternal`). If Uttrflow is frontmost it throws `.noFocusedTextField`
without touching the clipboard, and the coordinator moves to the next strategy. When the insertion
names a destination application, the same two points also require that application to still be
frontmost (`requireTarget`), and throw `.insertionTargetChanged` otherwise, which stops the route.

Pastes are serialised: a second paste waits for the first to finish (`PasteboardInsertionGate`), so
two clip insertions cannot interleave their clipboard writes and keystrokes. After writing, the
engine reads the clipboard back and compares change counts; a different count means another
writer owns the clipboard now, and the engine throws `.clipboardChanged` rather than paste their
contents.

The Accessibility and typed strategies make the same Uttrflow-frontmost check at their writes; see
[insertion.md](insertion.md), "Never into Uttrflow itself".
