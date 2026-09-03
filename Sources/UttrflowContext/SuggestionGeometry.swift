public import CoreGraphics

/// Where the suggestion surface is drawn, and which rung of the ladder it settled for.
public struct SuggestionAnchor: Sendable, Equatable {
    /// The placement that was actually reachable, at or below the one asked for.
    public let placement: SuggestionPlacement
    /// The panel's frame, in AppKit screen coordinates.
    public let frame: CGRect

    public init(placement: SuggestionPlacement, frame: CGRect) {
        self.placement = placement
        self.frame = frame
    }
}

/// Turns a placement, a caret and a window into a rectangle, in AppKit's space where `y` grows up.
public enum SuggestionGeometry {
    /// The gap between the surface and the caret it hangs off.
    public static let gap: CGFloat = 4

    /// The gap between the surface and the edge it is parked against.
    public static let margin: CGFloat = 8

    /// The frame to occupy inside the screen, one row an inline ghost and more a list below the caret.
    public static func anchor(
        for placement: SuggestionPlacement,
        caret: CGRect?,
        window: CGRect?,
        screen: CGRect,
        size: CGSize,
        rows: Int = 1
    ) -> SuggestionAnchor {
        let (reached, origin): (SuggestionPlacement, CGPoint) =
            switch (placement, usable(caret, on: screen)) {
            case (.inlineGhost, .some(let caret)):
                (.inlineGhost, caretAnchored(caret: caret, size: size, rows: rows))
            default:
                (.windowStrip, strip(along: usable(window, on: screen) ?? screen, size: size))
            }
        return SuggestionAnchor(
            placement: reached,
            frame: CGRect(origin: clamped(origin, size: size, in: screen), size: size))
    }

    /// Turns an Accessibility rectangle, whose `y` grows downwards, into AppKit's space.
    public static func fromAccessibility(_ rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX, y: primaryScreenMaxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Where a lone inline ghost begins: at the caret, continuing the user's own line.
    static func inlineOrigin(caret: CGRect) -> CGPoint {
        CGPoint(x: caret.maxX, y: caret.minY)
    }

    /// The top-left of the list drawn below the caret, left-aligned to the caret's own x.
    static func belowCaretOrigin(caret: CGRect, size: CGSize) -> CGPoint {
        CGPoint(x: caret.minX, y: caret.maxY - size.height)
    }

    /// A lone ghost sits on the caret's line; a list hangs from the caret's top so its rows fall below.
    private static func caretAnchored(caret: CGRect, size: CGSize, rows: Int) -> CGPoint {
        rows > 1 ? belowCaretOrigin(caret: caret, size: size) : inlineOrigin(caret: caret)
    }

    /// The strip stands on the bottom edge of whatever it was given, centred on it.
    private static func strip(along frame: CGRect, size: CGSize) -> CGPoint {
        CGPoint(x: frame.midX - size.width / 2, y: frame.minY + margin)
    }

    /// A rectangle from another display, or from a window since closed, is no rectangle.
    private static func usable(_ rect: CGRect?, on screen: CGRect) -> CGRect? {
        guard let rect, !rect.isNull, !rect.isInfinite else { return nil }
        // A thin insertion caret has zero width, so it never "intersects" a screen; ask whether its point is on one.
        if rect.isEmpty {
            return screen.contains(CGPoint(x: rect.minX, y: rect.midY)) ? rect : nil
        }
        return rect.intersects(screen) ? rect : nil
    }

    /// Pulls a surface that would hang over an edge back inside the screen, the lower bound winning.
    private static func clamped(_ origin: CGPoint, size: CGSize, in screen: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, screen.minX), max(screen.maxX - size.width, screen.minX)),
            y: min(max(origin.y, screen.minY), max(screen.maxY - size.height, screen.minY)))
    }
}
