# Deciding whether the panel can paste

`PanelInsertion.decided(isAccessibilityGranted:isSelfFrontmost:)` in
`Sources/UttrflowUX/PanelInsertion.swift` settles, when the panel opens, whether choosing
a clip will place it at the caret or only copy it. It lives in `UttrflowUX` because it is
a decision, and `AppDelegate` is the one file the coverage gate cannot see.

## Two questions, and not a third

Two facts decide it: whether macOS lets this process type into other applications, and
whether Uttrflow's own window is in front (in which case a ⌘V would land in the panel
rather than in the document behind it). The permission wins when both are false, because
it is the one the user can act on.

**It must not ask whether anything is focused.** That question is the Accessibility
engine's precondition, not the paste engine's: pasting needs only that some *other*
application is in front to receive the ⌘V. Cursor, VS Code and Claude's desktop app expose
no focused element and take a paste perfectly well. The same precondition was once in the
insertion engine and sent every one of Cursor's dictations to the clipboard; a copy of it
in the panel's pre-flight did the identical damage from one step further back, announcing
"Copied — press ⌘V" without ever calling the engine that would have worked.
`PanelInsertionDecisionTests.onlyTwoQuestions` enumerates the whole input space so a third
question has to be justified against this.

## What the user is told

Each obstacle has its own sentence, because the way out of each differs: grant a
permission, put a caret somewhere, or click out of Uttrflow's own window first. None of
them says "failed"; the words are on the clipboard in every case, so the paste became a
manual one, which is a smaller thing than the word suggests.

A write the disk refused (`PanelNotice.writeFailed`) is said rather than swallowed: a
sheet that closes and changes nothing looks exactly like success.
