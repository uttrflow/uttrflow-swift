# Quick panel geometry: resizing and placement

`PanelResize` and `PanelPlacement` in `Sources/UttrflowUX` own the arithmetic; the
controller owns the window. Coordinates are AppKit's — origin bottom-left, `y` growing
upwards — and getting that backwards makes a panel that shrinks when it should grow,
which is invisible in a diff and obvious in the hand.

## The grip: 6 points

`PanelResize.grip` is how far inside the border still counts as being on it. Narrower
and the band is something you hunt for with the pointer, on a window whose corners are
rounded so the visual edge is not where the geometric one is. Wider and it eats the
padding around the search field, which is one of the few places
`isMovableByWindowBackground` still lets the user drag the panel, so the panel would
resize when they meant to move it.

## The minimum: 380 × 300

Not a preference. The width is set by the sheet card, which is 364 points wide and would
be clipped by anything narrower. The height is the parts that are always drawn — the
search field, the chips, the hint and the five-button bar — plus room for two rows,
because a list that can show one row is a list nothing can be scanned in.

A screen smaller than the minimum loses: the panel overflows rather than being shrunk
below the size at which it can be read. `PanelPlacement.clamped` makes the same choice.

## Nothing is remembered

A resize lasts as long as the panel is on screen; the next open is the default size
again. There is no stored rectangle to migrate, no size restored from a build that
measured the design differently, and no way for a panel dragged to something unusable to
still be unusable tomorrow.

## The flip trap

The panel's content view is an `NSHostingView`, whose origin is the top-left
(`isFlipped == true`). A point at the visual top of the panel arrives with a small `y`,
which upright arithmetic reads as the bottom. `x` is unaffected by a flip, which is why
dragging the sides can work perfectly while dragging the top and bottom is backwards.

Both callers that ask which edge a point is on — the hit test and the cursor rects — must
answer identically, so `edge(at:in:grip:isFlipped:)` and `borders(in:grip:isFlipped:)`
both take the flip as a parameter and undo it once. A flip applied in only one of them is
a bug that shows up in only one axis: the pointer over the bottom border promises a
resize that the click there does not perform.

## Holding the frame on screen

A borderless panel gets none of AppKit's protection. An edge dragged past the menu bar
takes the search field with it for the rest of the session, since there is no handle
left to drag it back by. `PanelResize.held` pulls back only the edges being dragged; the
opposite border is the thing that stays put.

Inside `held`, the anchors (`maxX`, `maxY`) are read before anything changes. Shrinking
the width moves `maxX` with it because the origin is the bottom-left, so a line that read
`frame.maxX` after writing `frame.size` would be clamping the rectangle it had just made
rather than the one being held, and the panel flies off the screen it was supposed to
stay on.

Drags are measured from where the drag started, not from the last frame, so a gesture
that hits the minimum and comes back out returns to where the pointer is rather than
trailing it by however much was clamped away.
