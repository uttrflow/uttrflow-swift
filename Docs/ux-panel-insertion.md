# Deciding whether the panel can paste

When the quick panel opens, `PanelInsertion.decided(isAccessibilityGranted:isSelfFrontmost:)` in
`Sources/UttrflowUX/PanelInsertion.swift` settles whether choosing a clip will place it at the
caret (`.atCaret`) or only copy it (`.clipboardOnly(obstacle)`). It lives in `UttrflowUX` because
it is a decision, and `AppDelegate`, which asks it in `placement()`, is outside the coverage gate.

## Two questions, and not a third

Two facts decide it: whether macOS lets this process type into other applications, and whether
Uttrflow's own window is in front (in which case a ⌘V would land in Uttrflow rather than in the
document behind it). When neither holds, the missing permission is the one reported, because it
is the one the user can act on.

**It does not ask whether anything is focused.** That question is the Accessibility insertion
engine's precondition, not the paste engine's: pasting needs only that some *other* application
is in front to receive the ⌘V. Some editors built on web views expose no focused element and
take a paste perfectly well, so a focus check here would announce "Copied — press ⌘V" without
ever calling the engine that would have worked. `PanelInsertionDecisionTests.onlyTwoQuestions`
enumerates the whole input space, so a third question has to be justified against this.

## What the user is told

Each obstacle (`PanelInsertionObstacle`) has its own sentence, because the way out of each
differs:

| Obstacle | Notice |
| --- | --- |
| `accessibilityNotGranted` | "Turn on Accessibility and Uttrflow can paste for you.", with **Open Accessibility settings** |
| `uttrflowInFront` | "Copied — click where you want it, then press ⌘V" |
| `nothingFocused` | "Copied — press ⌘V where you want it" |

`decided` never answers `nothingFocused`; that sentence is for a key pressed after the application
that owned the caret has quit behind the panel (`PanelSnapshot.applying(_:caretOwnerHasQuit:)`). None of them says "failed": the words are on the clipboard in every case,
so the paste became a manual one, which is a smaller thing than the word suggests. The
Accessibility notice is shown as the panel opens rather than after Return, when there is nowhere
left to say it; once Return has copied the clip, it is prefixed with "Copied — press ⌘V."
(`PanelInsertionObstacle.copiedNotice`).

A write the disk refused (`PanelNotice.writeFailed`) is said rather than swallowed: a sheet that
closes and changes nothing looks exactly like success.

What is said after the panel has closed and a paste did not arrive is
[`app-quick-panel.md`](app-quick-panel.md#after-the-panel-has-closed).
