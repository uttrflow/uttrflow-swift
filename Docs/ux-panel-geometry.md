# Quick panel geometry: resizing and placement

Where the quick panel opens and how its border resizes it. `PanelResize`, `PanelPlacement` and
`PanelSpots` in `Sources/UttrflowUX/PanelResize.swift` and `Sources/UttrflowUX/PanelPlacement.swift`
own the arithmetic; `QuickPanelController` in `Sources/Uttrflow/Panel/` owns the window.
Coordinates are AppKit's (origin bottom-left, `y` growing upwards), and getting that backwards
makes a panel that shrinks when it should grow, which is invisible in a diff and obvious in the
hand.

| Value | Constant | Why |
| --- | --- | --- |
| 6 pt | `PanelResize.grip` | how far inside the border still counts as being on it |
| 380 × 300 pt | `PanelResize.minimum` | the smallest a drag may make the panel |
| 12 pt | `PanelPlacement.margin` | the gap to the visible frame's edges in the default corner |
| 8 displays | `PanelSpots.limit` | how many displays keep a remembered spot |

## The grip

Narrower than 6 points and the band is something you hunt for with the pointer, on a window
whose corners are rounded so the visual edge is not where the geometric one is. Wider and it eats
the padding around the search field, which is one of the few places
`isMovableByWindowBackground` still lets the user drag the panel, so the panel would resize when
they meant to move it.

## The minimum

The width is set by the sheet card, which is at most 364 points (`QuickPanelMetrics.width - 56`)
and would be clipped by a narrower panel. The height is the parts that are always drawn (the
search field, the chips, the hint and the bottom bar) plus room for two rows, because a list that
can show one row is a list nothing can be scanned in.

The minimum binds a drag when the visible frame can contain it. Opening is different: on a display
whose visible frame is smaller than the design size, `PanelPlacement.fitted` shrinks the panel to
fit. Resizing also keeps the result inside that visible frame, even when this makes it smaller than
the minimum, so its top never runs off the screen.

## A size is not remembered

A resize lasts as long as the panel is on screen; the next open is the design size again. There
is no stored rectangle to migrate, and no way for a panel dragged to something unusable to still
be unusable tomorrow.

## The flip trap

The panel's content view is an `NSHostingView`, whose origin is the top-left
(`isFlipped == true`). A point at the visual top of the panel arrives with a small `y`, which
upright arithmetic reads as the bottom. `x` is unaffected by a flip, which is why dragging the
sides can work perfectly while dragging the top and bottom is backwards.

Both callers that ask which edge a point is on, the hit test and the cursor rects, must answer
identically, so `edge(at:in:grip:isFlipped:)` and `borders(in:grip:isFlipped:)` both take the
flip as a parameter and undo it once. A flip applied in only one of them is a bug that shows up
in only one axis: the pointer over the bottom border promises a resize that the click there does
not perform.

## Holding the frame on screen while resizing

A borderless panel gets none of AppKit's protection. An edge dragged past the menu bar would take
the search field with it for the rest of the session, since there is no handle left to drag it
back by. `PanelResize.held` fits the resized rectangle inside the visible frame after applying the
minimum. It keeps the opposite border in place when it can; if that border is already outside the
visible frame, it brings the rectangle back on screen. When the minimum is larger than the available
space, the visible frame sets the size.

Inside `held`, the opposite-edge anchors are read before fitting the size. Shrinking from the left
or bottom keeps the right or top edge in place when it is visible; shrinking from the right or top
keeps the left or bottom edge in place when it is visible.

Drags are measured from where the drag started, not from the last frame, so a gesture that hits
the minimum and comes back out returns to where the pointer is rather than trailing it by however
much was clamped away.

## Placement

The default position is the top-right corner of the visible frame, inset by the 12-point margin
(`PanelPlacement.defaultOrigin`), not the centre. The margin is small so the panel reads as
attached to the corner rather than floating near it; the menu bar and Dock are already excluded
from the visible frame it measures against. The panel opens over whatever the user was typing
into, and the middle of the screen is the likeliest place for that to be the very thing they
were reading; the top-right is out of the way of running text in almost every window, and it is
the corner macOS itself uses for things that arrive uninvited.

A remembered position belongs to one display. Global coordinates from one display mean nothing on
another: clamped into it, a spot near one display's far corner lands flush against the other's
near edge. So `PanelSpots` keeps one origin per display, for the most recently used
`PanelSpots.limit` displays, and a display with none opens in its default corner.

A remembered position is clamped rather than trusted (`PanelPlacement.origin(remembered:size:in:)`).
Displays are unplugged and resolutions change, and a panel restored onto a screen that no longer
extends that far would open somewhere the user cannot see or reach, with no way back, because
moving it needs it to be visible first. Before either the default corner or a remembered spot is
computed, `fitted` shrinks the design size to the display's visible frame, and `clamped` then pins
whatever is left inside it, to the bottom-left if anything still overflows rather than centring
on the overflow. Clamping is idempotent, because the panel is placed on every open.

## Related

- [`app-quick-panel.md`](app-quick-panel.md#position): how the controller remembers a drag.
- [`panel.md`](panel.md): what the panel says.
