public import Foundation

/// Where the quick panel sits on screen.
///
/// Geometry rather than AppKit, so the rules are decided somewhere a test can reach.
/// The controller owns the window; this owns the arithmetic, which is the part that has
/// corners — a remembered position on a display that has since been unplugged, a panel
/// taller than the screen it is asked to sit on.
///
/// Coordinates are AppKit's: the origin is bottom-left and `y` grows upwards, so the top
/// of the screen is the *larger* `y`. Getting that backwards puts the panel off the
/// bottom of the display, which is the one mistake here that is invisible in a diff.
public enum PanelPlacement {
    /// The gap left between the panel and the edges of the usable screen.
    ///
    /// Small on purpose. The panel is meant to read as attached to the corner rather
    /// than floating near it, and the menu bar and Dock are already excluded from the
    /// visible frame this measures against.
    public static let margin: CGFloat = 12

    /// The top-right corner, which is where the panel goes before anybody has moved it.
    ///
    /// Not centred. The panel opens over whatever the user was typing into, and the
    /// middle of the screen is the likeliest place for that to be the very thing they
    /// were reading. The top-right is out of the way of running text in almost every
    /// window, and it is the corner macOS itself uses for things that arrive uninvited.
    public static func defaultOrigin(size: CGSize, in visible: CGRect) -> CGPoint {
        clamped(
            CGPoint(
                x: visible.maxX - size.width - margin,
                y: visible.maxY - size.height - margin),
            size: size, in: visible)
    }

    /// Where the panel should open: where it was left, or the default corner.
    ///
    /// A remembered position is clamped rather than trusted. Displays are unplugged,
    /// resolutions change, and a panel restored onto a screen that no longer extends
    /// that far would open somewhere the user cannot see or reach — with no way back,
    /// because moving it needs it to be visible first.
    public static func origin(
        remembered: CGPoint?, size: CGSize, in visible: CGRect
    ) -> CGPoint {
        guard let remembered else { return defaultOrigin(size: size, in: visible) }
        return clamped(remembered, size: size, in: visible)
    }

    /// Pulls a rectangle back inside the visible frame.
    ///
    /// When the panel is larger than the screen it is pinned to the bottom-left rather
    /// than centred on the overflow: the alternative is a negative range, and the
    /// corner at least keeps the search field and the first rows reachable.
    public static func clamped(
        _ origin: CGPoint, size: CGSize, in visible: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visible.minX), max(visible.maxX - size.width, visible.minX)),
            y: min(max(origin.y, visible.minY), max(visible.maxY - size.height, visible.minY)))
    }
}
