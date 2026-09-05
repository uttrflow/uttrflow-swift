import CoreGraphics
import UttrflowCore

/// Turns an anchor into a place on the screen.
///
/// Pure geometry, deliberately free of any window: placement is the part that can be
/// got wrong invisibly — a second display sitting to the left of the main one has
/// negative coordinates, and an origin computed as though every screen started at zero
/// puts the button somewhere nobody can see it.
///
/// Everything here works in AppKit's coordinate space: y grows upwards, and the
/// visible frame already excludes the menu bar and the Dock.
enum DockPlacement {
    /// The gap between the button and the edges it is parked against.
    static let margin: CGFloat = 16

    /// The point on the screen the anchor names, independent of how big the button is.
    ///
    /// This is what a drag snaps towards, so it is the anchor's own position rather
    /// than any corner of the panel.
    static func anchorPoint(
        for anchor: DockAnchor, in visibleFrame: CGRect, margin: CGFloat = margin
    ) -> CGPoint {
        switch anchor {
        case .bottomLeft:
            CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin)
        case .bottomCentre:
            CGPoint(x: visibleFrame.midX, y: visibleFrame.minY + margin)
        case .bottomRight:
            CGPoint(x: visibleFrame.maxX - margin, y: visibleFrame.minY + margin)
        case .rightEdge:
            CGPoint(x: visibleFrame.maxX - margin, y: visibleFrame.midY)
        }
    }

    /// The panel's bottom-left corner for an anchor and a size.
    ///
    /// The button grows inwards from the edge it is parked on, which falls out of
    /// recomputing this on every resize: an anchor pinned to the right subtracts the
    /// new width, so the right-hand edge stays put and the panel extends leftwards.
    static func origin(
        for anchor: DockAnchor, panelSize: CGSize, in visibleFrame: CGRect,
        margin: CGFloat = margin
    ) -> CGPoint {
        let point = anchorPoint(for: anchor, in: visibleFrame, margin: margin)
        let unclamped: CGPoint =
            switch anchor {
            case .bottomLeft: point
            case .bottomCentre: CGPoint(x: point.x - panelSize.width / 2, y: point.y)
            case .bottomRight: CGPoint(x: point.x - panelSize.width, y: point.y)
            case .rightEdge:
                CGPoint(x: point.x - panelSize.width, y: point.y - panelSize.height / 2)
            }
        return clamping(unclamped, panelSize: panelSize, in: visibleFrame)
    }

    /// The whole rectangle to hand a window.
    static func frame(
        for anchor: DockAnchor, panelSize: CGSize, in visibleFrame: CGRect,
        margin: CGFloat = margin
    ) -> CGRect {
        CGRect(
            origin: origin(
                for: anchor, panelSize: panelSize, in: visibleFrame, margin: margin),
            size: panelSize)
    }

    /// Pulls a panel that would hang over an edge back inside the visible frame.
    ///
    /// The lower bound is applied last on purpose: a panel wider or taller than the
    /// screen cannot satisfy both bounds, and pinning it to the bottom-left of the
    /// visible frame at least leaves it reachable.
    private static func clamping(
        _ origin: CGPoint, panelSize: CGSize, in visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - panelSize.width)),
            y: max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - panelSize.height)))
    }
}
