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

    /// The frame to occupy, inside the screen, on the best rung these inputs support.
    public static func anchor(
        for placement: SuggestionPlacement,
        caret: CGRect?,
        window: CGRect?,
        screen: CGRect,
        size: CGSize
    ) -> SuggestionAnchor {
        let (reached, origin): (SuggestionPlacement, CGPoint) =
            switch (placement, usable(caret, on: screen)) {
            case (.inlineGhost, .some(let caret)):
                (.inlineGhost, inline(after: caret))
            case (.caretChip, .some(let caret)):
                (.caretChip, chip(under: caret, screen: screen, size: size))
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

    /// The ghost continues the user's own line, so it starts where the caret is.
    private static func inline(after caret: CGRect) -> CGPoint {
        CGPoint(x: caret.maxX, y: caret.minY)
    }

    /// The chip hangs under the caret, and flips above it rather than off the screen.
    private static func chip(under caret: CGRect, screen: CGRect, size: CGSize) -> CGPoint {
        let below = caret.minY - gap - size.height
        let y = below >= screen.minY + margin ? below : caret.maxY + gap
        return CGPoint(x: caret.midX - size.width / 2, y: y)
    }

    /// The strip stands on the bottom edge of whatever it was given, centred on it.
    private static func strip(along frame: CGRect, size: CGSize) -> CGPoint {
        CGPoint(x: frame.midX - size.width / 2, y: frame.minY + margin)
    }

    /// A rectangle from another display, or from a window since closed, is no rectangle.
    private static func usable(_ rect: CGRect?, on screen: CGRect) -> CGRect? {
        guard let rect, !rect.isNull, rect.intersects(screen) else { return nil }
        return rect
    }

    /// Pulls a surface that would hang over an edge back inside the screen, the lower bound winning.
    private static func clamped(_ origin: CGPoint, size: CGSize, in screen: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, screen.minX), max(screen.maxX - size.width, screen.minX)),
            y: min(max(origin.y, screen.minY), max(screen.maxY - size.height, screen.minY)))
    }
}
