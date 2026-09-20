# Main window: sizing and the clipboard demonstration

## Window sizing

`MainWindowController.makeWindow()` sets `hosting.sizingOptions = []`. `NSHostingView` reports
SwiftUI's ideal size as its `intrinsicContentSize` by default and AppKit resizes the window to
match, so the window grew and shrank as the user moved between pages. Measured before the
change: 1084 points tall on Home, 4458 on Account and 5461 on Insights. On Account the content
sat at the top of a window four times the height of the screen with everything below it blank.
The pages already scroll.

Default size is 1180 × 780 (900 × 620 is cramped once the rail carries four figures); minimum
760 × 500. The icon rail is 76 points (a 44pt target with room either side), the expanded
sidebar 204 (eleven rows of 13-point text, the longest "Diagnostics", plus the badge) and the
figures rail 186. The two rails once shared a width, and at 76 points "Words per minute"
wrapped one word to a line and "2.7K" truncated to "2....".

The sidebar's expanded state is remembered in `UserDefaults` directly, not the settings store:
it is the window's own memory of how it was left, like the quick panel's position.

## The clipboard demonstration

`ClipboardDemonstration` is drawn rather than recorded. A GIF is a few hundred kilobytes that
has to be re-recorded every time the panel's design moves, is wrong the moment somebody changes
their shortcut (this reads the real one), is soft on a Retina display, and cannot follow the
light or dark appearance.

It shows the whole gesture, ending with the words arriving in the document. A version that
stopped when the panel closed demonstrated a mechanism and left out the payoff.

- Loop: 8 seconds. Long enough to read the pasted line before it resets.
- Document width: 400 points. The finished sentence is 373 points at the footnote size plus
  ten points of padding a side; a line that wrapped would read as a paragraph appearing.
- Layout: side by side while the document can hold its line, stacked otherwise. The card is
  offered a width, `onGeometryChange` records it, and
  `ClipboardDemonstrationMetrics.arrangement(forOfferedWidth:)` answers from it: side by side
  once 17 points of padding a side, 22 of gap, the document's 400 and 360 for the words all
  fit — 816 points — with the words widening to 460 and no further. At the 760-point minimum
  window, reserving 400 for the document leaves 56 for the words beside it, which is why the
  stacked form exists.
- `ViewThatFits` used to make that choice and does not any more. It asks every candidate how
  big it would like to be, and it was inside the clock's closure, so both arrangements were
  measured on every display frame — the subject of `Docs/performance.md`. The decision is
  width in, arrangement out, and the clock only draws.
- The animation is a pure function of the clock, so the page can redraw underneath it (on
  every keystroke in a search field) without the loop stuttering.
- Moves only while its window is key in the active app and some of the card itself is inside the
  scroll view's bounds and on a display, per `WindowAttention`, and only while
  `MotionBudget` finds no Reduce Motion, Low Power Mode or serious thermal pressure; otherwise
  it rests on the panel open with the address row chosen. Its clock wakes only when the drawing
  changes, and at most 30 times a second while the panel moves (`ClipboardDemonstrationMoments`).
  See `Docs/performance.md`.

## Colours

`Sources/Uttrflow/Brand/BrandPalette.swift` is the only place a colour is defined. It groups
every value by role — brand teal, brand purple, surfaces, lines, text tones and semantic
colours — each as a dark and light pair where the appearance changes it. Views name a palette
member, through aliases such as `Color.panelAccent` or `Color.mainBackground`; none writes a hex.
Where two views draw the same value they point at the same member, so the dock's live accent
and the quick panel's accent cannot drift apart. `NSColor.orbit(_:)` in `OrbitPalette.swift`
resolves a pair per appearance. `BrandPaletteTests` pins the primary teal and secondary purple.

Text that carries a status is drawn in an ink, never in a fill. The semantic fills — `warning`,
`success`, `recording` and the teal `deep` — are bright single values that sit near 2:1 on a
light card, which is fine for a dot, an icon or a filled button and unreadable as words. The inks
`Semantic.warningInk`, `successInk`, `criticalInk` and `Teal.ink` are pairs that clear WCAG AA's
4.5:1 on a card, on the ground and on their own 16% pill wash in both appearances, reached as
`Color.warningInk`, `successInk`, `criticalInk` and `accentInk` and through `MainTone.foreground`.
`SemanticInkContrastTests` computes those ratios, so a palette edit that drops one below 4.5:1
fails.
