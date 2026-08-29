public import Foundation

/// Which part of the panel's border the pointer is on.
///
/// Eight, because a corner is not two edges taking turns: dragging one has to move both
/// dimensions at once, and a corner that resolved to whichever edge was nearer would
/// swap under the pointer mid-drag.
public enum PanelEdge: Sendable, Equatable, CaseIterable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    /// Whether dragging this edge moves the window's origin as well as its size.
    ///
    /// AppKit's origin is the bottom-left, so growing rightwards or upwards leaves it
    /// alone and growing left or down has to move it — which is the whole reason this
    /// arithmetic is written down somewhere a test can reach rather than inline in a
    /// mouse handler.
    var movesOrigin: (x: Bool, y: Bool) {
        switch self {
        case .left: (true, false)
        case .right: (false, false)
        case .top: (false, false)
        case .bottom: (false, true)
        case .topLeft: (true, false)
        case .topRight: (false, false)
        case .bottomLeft: (true, true)
        case .bottomRight: (false, true)
        }
    }

    var changesWidth: Bool {
        switch self {
        case .top, .bottom: false
        default: true
        }
    }

    var changesHeight: Bool {
        switch self {
        case .left, .right: false
        default: true
        }
    }

    /// Which way the width grows when the pointer moves in +x, and the height in +y.
    var sign: (width: CGFloat, height: CGFloat) {
        switch self {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .top: (0, 1)
        case .bottom: (0, -1)
        case .topLeft: (-1, 1)
        case .topRight: (1, 1)
        case .bottomLeft: (-1, -1)
        case .bottomRight: (1, -1)
        }
    }
}

/// How big the quick panel is, while the user is dragging its edge.
///
/// Geometry rather than AppKit, for the reason ``PanelPlacement`` gives about position:
/// the controller owns the window and this owns the arithmetic, which is the part with
/// the corners in it. Coordinates are AppKit's — origin bottom-left, `y` growing upwards
/// — and getting that backwards makes a panel that shrinks when it should grow, which is
/// invisible in a diff and obvious in the hand.
///
/// Nothing here is remembered. A resize lasts as long as the panel is on screen and the
/// next open is the default size again, so there is no stored rectangle to migrate, no
/// size restored from a build that measured the design differently, and no way for a
/// panel dragged to something unusable to still be unusable tomorrow.
public enum PanelResize {
    /// How far inside the border counts as being on it.
    ///
    /// Six points, and the number is set by the two failures either side of it. Narrower
    /// and the band is a thing you hunt for with the pointer, on a window whose corners
    /// are rounded so the visual edge is not where the geometric one is. Wider and it
    /// eats the padding around the search field, which is one of the few places
    /// `isMovableByWindowBackground` still lets the user drag the panel — so the panel
    /// would resize when they meant to move it.
    public static let grip: CGFloat = 6

    /// The smallest the panel may be dragged.
    ///
    /// Not a preference. The width is set by the sheet card, which is 364 points wide and
    /// would be clipped by anything narrower; the height by the parts that are always
    /// drawn — the search field, the chips, the hint and the five-button bar — plus room
    /// for two rows, because a list that can show one row is a list nothing can be
    /// scanned in and the whole product is scanning a list.
    public static let minimum = CGSize(width: 380, height: 300)

    /// Which edge, if any, a point in the panel's own coordinates is on.
    ///
    /// - Parameters:
    ///   - point: In the view's own coordinates, whichever way up they are.
    ///   - size: The panel's current size.
    ///   - grip: How far inside the border still counts.
    ///   - isFlipped: Whether `point` arrived from a view whose origin is the top-left.
    ///     SwiftUI's is, so `NSHostingView.isFlipped` is `true` and every `y` handed to
    ///     this from the panel's content view is measured downwards. Taken as a parameter
    ///     rather than assumed either way, because the two callers that ask this question
    ///     — the hit test and the cursor rects — must answer it identically, and a flip
    ///     applied in one of them is a bug that shows up in only one axis.
    /// - Returns: The edge under the pointer, or `nil` for the whole middle of the panel,
    ///   which belongs to the list and must keep every one of its clicks.
    public static func edge(
        at point: CGPoint, in size: CGSize, grip: CGFloat = grip, isFlipped: Bool = false
    ) -> PanelEdge? {
        // Outside the panel entirely is not an edge. A point beyond the border belongs to
        // whatever is behind the panel, and claiming it would let a click aimed at another
        // application resize this one.
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else {
            return nil
        }
        // Everything below this line is in AppKit's coordinates, so the flip is undone
        // once, here, rather than being remembered by each comparison.
        let y = isFlipped ? size.height - point.y : point.y
        let left = point.x <= grip
        let right = point.x >= size.width - grip
        let bottom = y <= grip
        let top = y >= size.height - grip

        switch (left, right, top, bottom) {
        // A panel narrower than two grips would report both sides at once. Left wins, so
        // the answer is at least stable rather than depending on rounding.
        case (true, _, true, _): return .topLeft
        case (true, _, _, true): return .bottomLeft
        case (_, true, true, _): return .topRight
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return nil
        }
    }

    /// The eight bands of border, in the coordinates of a view of this size.
    ///
    /// Here rather than in the view because the cursor rects and ``edge(at:in:grip:isFlipped:)``
    /// have to describe the same eight rectangles. They did not: the hit test was given the
    /// flip and the cursor rects were written out by hand in AppKit's coordinates, so the
    /// pointer over the bottom border promised a resize that the click there did not
    /// perform — and the band that did resize was the one at the top.
    ///
    /// Corners last, so a caller adding them in order lets them win the overlap: a corner
    /// drag moves both dimensions, and the very corner is where the pointer is most
    /// obviously asking for both.
    ///
    /// - Returns: Each band and the edge it drags, in the view's own coordinates.
    public static func borders(
        in size: CGSize, grip: CGFloat = grip, isFlipped: Bool = false
    ) -> [(rect: CGRect, edge: PanelEdge)] {
        let (width, height) = (size.width, size.height)
        let upright: [(CGRect, PanelEdge)] = [
            (CGRect(x: 0, y: grip, width: grip, height: height - 2 * grip), .left),
            (CGRect(x: width - grip, y: grip, width: grip, height: height - 2 * grip), .right),
            (CGRect(x: grip, y: 0, width: width - 2 * grip, height: grip), .bottom),
            (CGRect(x: grip, y: height - grip, width: width - 2 * grip, height: grip), .top),
            (CGRect(x: 0, y: 0, width: grip, height: grip), .bottomLeft),
            (CGRect(x: width - grip, y: 0, width: grip, height: grip), .bottomRight),
            (CGRect(x: 0, y: height - grip, width: grip, height: grip), .topLeft),
            (CGRect(x: width - grip, y: height - grip, width: grip, height: grip), .topRight),
        ]
        guard isFlipped else { return upright.map { (rect: $0.0, edge: $0.1) } }
        return upright.map {
            (
                rect: CGRect(
                    x: $0.0.minX, y: height - $0.0.maxY, width: $0.0.width, height: $0.0.height),
                edge: $0.1
            )
        }
    }

    /// The frame a drag has arrived at.
    ///
    /// Measured from where the drag *started* rather than from the last frame, so a
    /// gesture that hits the minimum and comes back out returns to where the pointer is
    /// rather than trailing it by however much was clamped away.
    ///
    /// - Parameters:
    ///   - frame: The panel's frame when the drag began.
    ///   - edge: The edge being dragged.
    ///   - delta: How far the pointer has moved since the drag began.
    ///   - minimum: The smallest the panel may become.
    ///   - visible: The usable screen, when there is one. The frame is held inside it for
    ///     the reason a drag is: a borderless panel gets none of AppKit's protection, and
    ///     an edge dragged past the menu bar takes the search field with it — for the rest
    ///     of the session, since there is no handle left to drag it back by.
    /// - Returns: The frame the panel should now have.
    public static func resized(
        _ frame: CGRect, dragging edge: PanelEdge, by delta: CGSize,
        minimum: CGSize = minimum, within visible: CGRect? = nil
    ) -> CGRect {
        let sign = edge.sign
        let width =
            edge.changesWidth
            ? max(frame.width + sign.width * delta.width, minimum.width) : frame.width
        let height =
            edge.changesHeight
            ? max(frame.height + sign.height * delta.height, minimum.height) : frame.height

        // The edge opposite the one being dragged does not move, which is what makes a
        // resize feel like pulling the border rather than pushing the window.
        let moves = edge.movesOrigin
        let origin = CGPoint(
            x: moves.x ? frame.maxX - width : frame.minX,
            y: moves.y ? frame.maxY - height : frame.minY)

        return held(
            CGRect(origin: origin, size: CGSize(width: width, height: height)),
            dragging: edge, minimum: minimum, within: visible)
    }

    /// Keeps a resized frame on the usable screen.
    ///
    /// Only the edges being dragged are pulled back. Moving the others would drag the
    /// panel under the pointer — the user is holding one border and the opposite one is
    /// supposed to be the thing that stays put.
    ///
    /// A screen smaller than ``minimum`` loses: the panel overflows rather than being
    /// shrunk below the size at which it can be read, which is the same choice
    /// ``PanelPlacement/clamped(_:size:in:)`` makes when the panel will not fit.
    private static func held(
        _ frame: CGRect, dragging edge: PanelEdge, minimum: CGSize, within visible: CGRect?
    ) -> CGRect {
        guard let visible else { return frame }
        // The anchors are read before anything is changed. Shrinking the width moves
        // `maxX` with it — the origin is the bottom-left — so a second line that asked
        // for `frame.maxX` after the first had written to `frame.size` would be asking
        // about the rectangle it had just made rather than the one being clamped, and the
        // panel flew off the screen it was supposed to be held on.
        let (right, top) = (frame.maxX, frame.maxY)
        var frame = frame

        if edge.movesOrigin.x, frame.minX < visible.minX {
            frame.size.width = max(right - visible.minX, minimum.width)
            frame.origin.x = right - frame.width
        }
        if !edge.movesOrigin.x, edge.changesWidth, right > visible.maxX {
            frame.size.width = max(visible.maxX - frame.minX, minimum.width)
        }
        if edge.movesOrigin.y, frame.minY < visible.minY {
            frame.size.height = max(top - visible.minY, minimum.height)
            frame.origin.y = top - frame.height
        }
        if !edge.movesOrigin.y, edge.changesHeight, top > visible.maxY {
            frame.size.height = max(visible.maxY - frame.minY, minimum.height)
        }
        return frame
    }
}
