// Where the floating button sits on a screen for each anchor.

import CoreGraphics
import UttrflowCore

/// Turns an anchor into a place on the screen; pure geometry in AppKit's coordinate space.
enum DockPlacement {
    /// The gap between the button and the edges it is parked against.
    static let margin: CGFloat = 16

    /// The point the anchor names, independent of the button's size; what a drag snaps towards.
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

    /// The panel's bottom-left corner for an anchor and a size; the button grows inwards from its edge.
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

    /// Pulls a panel that would hang over an edge back inside the visible frame, lower bound last.
    private static func clamping(
        _ origin: CGPoint, panelSize: CGSize, in visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - panelSize.width)),
            y: max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - panelSize.height)))
    }
}
