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
    /// The frame at the caret, or `nil` when there is no on-screen caret and so nothing is drawn.
    public static func anchor(
        for placement: SuggestionPlacement,
        caret: CGRect?,
        window: CGRect?,
        screen: CGRect,
        size: CGSize
    ) -> SuggestionAnchor? {
        guard placement == .inlineGhost, let caret = usable(caret, on: screen) else { return nil }
        return SuggestionAnchor(
            placement: .inlineGhost,
            frame: CGRect(
                origin: clamped(caretAnchored(caret: caret, size: size), size: size, in: screen),
                size: size))
    }

    /// Turns an Accessibility rectangle, whose `y` grows downwards, into AppKit's space.
    public static func fromAccessibility(_ rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX, y: primaryScreenMaxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The panel's top-left, hung from the caret's top edge so the leader sits on the line and rows fall below.
    private static func caretAnchored(caret: CGRect, size: CGSize) -> CGPoint {
        CGPoint(x: caret.maxX, y: caret.maxY - size.height)
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
