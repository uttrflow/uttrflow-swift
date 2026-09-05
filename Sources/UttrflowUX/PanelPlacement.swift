// Where the quick panel sits on screen: the default corner, a remembered spot, and clamping.
public import Foundation

/// Where the quick panel sits on screen, in AppKit coordinates. See Docs/ux-panel-geometry.md.
public enum PanelPlacement {
    /// The gap between the panel and the usable screen's edges; small, so the panel reads as attached.
    public static let margin: CGFloat = 12

    /// The top-right corner, out of the way of running text and where macOS puts uninvited things.
    public static func defaultOrigin(size: CGSize, in visible: CGRect) -> CGPoint {
        clamped(
            CGPoint(
                x: visible.maxX - size.width - margin,
                y: visible.maxY - size.height - margin),
            size: size, in: visible)
    }

    /// Where the panel opens: where the user left it, clamped rather than trusted, or the default corner.
    public static func origin(
        remembered: CGPoint?, size: CGSize, in visible: CGRect
    ) -> CGPoint {
        guard let remembered else { return defaultOrigin(size: size, in: visible) }
        return clamped(remembered, size: size, in: visible)
    }

    /// Pulls a rectangle back inside the visible frame; a too-large panel is pinned bottom-left.
    public static func clamped(
        _ origin: CGPoint, size: CGSize, in visible: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visible.minX), max(visible.maxX - size.width, visible.minX)),
            y: min(max(origin.y, visible.minY), max(visible.maxY - size.height, visible.minY)))
    }
}
