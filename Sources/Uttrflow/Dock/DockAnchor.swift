import CoreGraphics
import UttrflowCore

extension DockAnchor {
    /// Whether the button stands on its end rather than lying along the bottom.
    ///
    /// On the right edge a wide recorder would run off the screen, so the button turns
    /// vertical there and grows leftwards instead.
    var isVertical: Bool { self == .rightEdge }
}

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
        let unclamped: CGPoint =
            switch anchor {
            case .bottomLeft:
                CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin)
            case .bottomCentre:
                CGPoint(
                    x: visibleFrame.midX - panelSize.width / 2, y: visibleFrame.minY + margin)
            case .bottomRight:
                CGPoint(
                    x: visibleFrame.maxX - margin - panelSize.width,
                    y: visibleFrame.minY + margin)
            case .rightEdge:
                CGPoint(
                    x: visibleFrame.maxX - margin - panelSize.width,
                    y: visibleFrame.midY - panelSize.height / 2)
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

    /// The anchor a dropped button should snap to.
    static func nearestAnchor(
        to point: CGPoint, in visibleFrame: CGRect, margin: CGFloat = margin
    ) -> DockAnchor {
        var nearest = DockAnchor.bottomRight
        var shortest = CGFloat.infinity
        // Strictly-nearer wins, so declaration order settles a tie. A point exactly
        // between two anchors then always resolves the same way instead of flickering
        // as the pointer jitters over it.
        for anchor in DockAnchor.allCases {
            let candidate = anchorPoint(for: anchor, in: visibleFrame, margin: margin)
            let distance = squaredDistance(from: point, to: candidate)
            if distance < shortest {
                shortest = distance
                nearest = anchor
            }
        }
        return nearest
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

    /// Compared squared, because only the ordering matters and a square root would add
    /// rounding without changing the answer.
    private static func squaredDistance(from point: CGPoint, to other: CGPoint) -> CGFloat {
        let dx = point.x - other.x
        let dy = point.y - other.y
        return dx * dx + dy * dy
    }
}
