# Quick panel: measurements and platform traps

What `Sources/Uttrflow/Panel/QuickPanelView.swift` relies on that the code alone does not show.
`Docs/panel.md` describes the panel's behaviour; this file holds the numbers and the AppKit
and SwiftUI traps the view is written around.

## Focus between the search field and a sheet

Two `@FocusState` bindings that both ask for focus are not a contest the newer one wins. The
search field is the panel's first responder from the moment it opens and keeps focus until
something releases it, so `isSheetFocused = true` on its own sets a flag that never becomes
focus: the sheet shows its placeholder while every keystroke filters the list behind it.
Measured three seconds after a sheet opened, by typing nine characters and finding all nine in
the search field.

Releasing the search from the panel's own `.task` does not fix it either, because that release
lands *after* the sheet field appears and takes the field's focus down with it; the keystrokes
then go nowhere at all. The working order is both writes in the sheet field's `onAppear`, with
the release first and the claim last — and the claim on the *next* turn (`Task { … }`), since a
focus request made while SwiftUI is still assembling the update that puts the field on screen
is applied against a responder chain the field is not yet in and is dropped silently.

The panel's `.task(id: presentation.sheet == nil)` does the reverse: when the sheet closes it
releases the sheet's focus and hands the search field back its caret.

## Hover while another application is frontmost

`.onHover` only reports while Uttrflow is the active application, and the quick panel never
activates it — the insertion path declines while Uttrflow is frontmost, so a panel that
activated could not paste anywhere. The symptom is rows that never light up under the pointer
and one row that keeps its hover for ever because the matching exit never arrived.

`PointerWatch` wraps an `NSTrackingArea` with `.activeAlways`, which tracks regardless of
activation, and `.inVisibleRect`, which keeps the tracked rectangle in step with a scrolling
row. Its `hitTest` answers `nil` so the row behind it still takes the click.

## Right-click without an `NSMenu`

`.contextMenu` hands the menu to AppKit, which draws it in the system's grey and metrics with no
icons; every other pixel of the panel is drawn by the view. `RightClickWatch` catches the click
instead and the panel opens its own menu. Two details matter:

- It is an **overlay, not a background**. The row is a `Button`, the button's own view is in
  front, and hit testing stops at the first view that claims the point — behind the row the
  catcher is never asked, and the right-click reaches the button, which latches into its pressed
  shade and stays there.
- `hitTest` claims only `.rightMouse*` events and a left click carrying ⌃ (macOS does not
  translate ctrl-click for you). Everything else answers `nil` and falls through to the row, so
  the left click that pastes a clip is untouched.

## Row identity across grouping

The list is one `ForEach` over sections whether browsing (one unnamed run) or searching (one run
per heading). A row's `.id` is keyed by section as well as by clip: an explicit id is a promise
to SwiftUI that this is the same view as before, and a row that kept its id while moving from
the flat list into a heading kept its old rendering too — unringed and unfilled while the
presentation said it was selected.

## Menu placement

The ⋯ menu is anchored to the panel's trailing edge below the chips, not to the row whose ⋯
was pressed. A menu pinned to a row inside a scroll view is clipped near the bottom of the list
and would have to measure the remaining room and flip; the menu's header names the clip
instead, so there is never a question of which row it means.

## Sizes

| Value | Points | Why |
| --- | --- | --- |
| Panel | 420 × 560 | The approved design; the view fills the window rather than pinning this |
| Corner radius | 16 | |
| Control height | 34 | Search field and microphone button |
| Row height | 34 | Every row the same height, so arrow-key counting stays right |
| Chip padding | 9 | Eight chips fit one row of a 420-point panel |
| Thumbnail | 34 × 24 | |
| Menu width | 200 | |
| Sheet width | panel − 56 | A cap, so the sheet shrinks with a narrower panel |

## Palette contrast

| Colour | Hex | Contrast on `panelSurface` |
| --- | --- | --- |
| `panelLabel` | `F4F4F6` | |
| `panelLabelSoft` | `8B90A0` | 7.4:1 |
| `panelLabelDim` | `565B68` | the dimmest grey in the design |
| `panelGhost` | `3A3F4A` | below the design's floor; never the only signal on a row |
| `panelAccentBright` | `5FE0D3` | 12.2:1 as a foreground |
| `panelAccentText` | `04332F` | ink on a teal fill, where white measures 2.1:1 |

The selection ring is `panelAccent` at 0.38 over a 0.08 wash; at 1.5 points and full strength
the ring was brighter than the clip it pointed at. The active chip is a 0.16 wash with a 0.35
border for the same reason. The palette has four values; a fifth for Delete was tried and
reverted, so Delete takes `dockWarning` only under the pointer.

## The window: key, never main

`QuickPanel` is a `.nonactivatingPanel` with `canBecomeKey` true and `canBecomeMain` false.
The mask is what makes keyboard input possible without activation; key lets the search field
hold the caret; main is what drags application activation along behind it, and activation is
the thing that must not happen. The paste path refuses to insert while Uttrflow is frontmost
(`PasteboardTextInsertionEngine.canInsert()` is `!focus.isSelfFrontmost()`, which compares
`NSWorkspace.shared.frontmostApplication` to this process). Activating to get keys would not
throw or warn; Return would simply do nothing and the clip would stay on the clipboard.

Measured with the panel open over TextEdit and answering ↓ ↑ Return: frontmost stayed
`com.apple.TextEdit` for the whole session. `NSApp.isActive` reads `true` in that state; it is
AppKit's own bookkeeping, not the system's idea of frontmost, so anything that needs to know
whether pasting will work must ask `NSWorkspace`.

The controller shows the panel with `orderFrontRegardless` then `makeKey`, never
`makeKeyAndOrderFront` or any form of `activate`; it hides with `orderOut` and activates
nothing on the way out either, because the application underneath never stopped being
frontmost.

Every line of `configurePanel()` follows from the same rule: `becomesKeyOnlyIfNeeded` false
(the search field must be typeable at once), `hidesOnDeactivate` false (the app is never
active), level `.statusBar` with `.canJoinAllSpaces` and `.fullScreenAuxiliary`,
`animationBehavior` `.none` (three keystrokes cannot feel instant from behind a fade), and no
`.resizable` in the style mask, so the hosting view is the border's one owner.

## Dismissal

`windowDidResignKey` is deliberately empty. Losing key is not the user going somewhere: a
notification banner, a Bluetooth prompt, a permission sheet or a screenshot all take key for a
moment, and closing on it made the panel vanish mid-use with the next keystrokes landing in
whatever was behind. The panel closes instead on a global mouse-down outside its frame or on
another application activating (`NSWorkspace.didActivateApplicationNotification`, ignoring
Uttrflow itself, which is the main window opening from the panel). Global mouse monitors need
no permission, so this works before Accessibility is granted.

## Position

The panel opens where the user last dragged it, else the top-right corner of the screen the
pointer is on (`NSScreen.main` belongs to another application's key window here). Only the
origin is remembered, as two `UserDefaults` keys, read with `object(forKey:)` because
`double(forKey:)` answers 0 for a key never written and 0,0 is a real corner. The size is the
design's on every open; a drag-resize lasts only while the panel is on screen.

`windowDidMove` compares the frame origin to `placedOrigin`, the origin `show(_:)` last set,
rather than using a flag: AppKit delivers the notification on a later pass of the run loop, by
which time a flag has been cleared and the panel's own placement is indistinguishable from a
drag. A resize from the left or bottom border moves the origin too and sets `placedOrigin`
through `onResize`, so a resize is remembered as exactly nothing. While dragging, the origin is
clamped to the visible frame, because a borderless panel gets none of AppKit's protection and
goes clean under the menu bar.
