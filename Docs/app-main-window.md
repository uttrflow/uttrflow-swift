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
- Layout: side by side while the document can hold its line, stacked otherwise, via
  `ViewThatFits`. The explanation column has an *ideal* width (360, max 460), not
  `maxWidth: .infinity`: `ViewThatFits` asks each candidate how big it would like to be, and a
  greedy column asks for everything, so the side-by-side arrangement never fitted. At the
  760-point minimum window, reserving 400 for the document leaves 56 for the words beside it,
  which is why the stacked form exists.
- The animation is a pure function of the clock, so the page can redraw underneath it (on
  every keystroke in a search field) without the loop stuttering.
- Paused when the window is not visible, which is where this card spends most of its life.
