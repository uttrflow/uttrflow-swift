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
    /// Below this much room after the caret nothing is drawn, since a ghost cut to a letter or two says nothing.
    public static let minimumWidth: CGFloat = 24

    /// The frame at the caret, never wider than the room to the field's or screen's right edge and never off the screen.
    public static func anchor(
        for placement: SuggestionPlacement,
        caret: CGRect?,
        window: CGRect?,
        field: CGRect? = nil,
        screen: CGRect,
        size: CGSize
    ) -> SuggestionAnchor? {
        guard placement == .inlineGhost, let caret = usable(caret, on: screen),
            let room = availableWidth(caret: caret, field: field, screen: screen),
            size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
            room >= min(size.width, minimumWidth)
        else { return nil }
        let width = min(size.width, room)
        let height = min(size.height, screen.height)
        let top = min(max(caret.maxY, screen.minY + height), screen.maxY)
        return SuggestionAnchor(
            placement: .inlineGhost,
            frame: CGRect(x: caret.maxX, y: top - height, width: width, height: height))
    }

    /// How far the ghost may run from the caret before it meets the field's right edge or the screen's, or nothing when the caret is past both.
    public static func availableWidth(caret: CGRect, field: CGRect?, screen: CGRect) -> CGFloat? {
        let start = caret.maxX
        guard start.isFinite, start >= screen.minX, start < screen.maxX else { return nil }
        let edge = min(screen.maxX, fieldEdge(field, holding: start) ?? screen.maxX)
        return edge > start ? edge - start : nil
    }

    /// Turns an Accessibility rectangle, whose `y` grows downwards, into AppKit's space.
    public static func fromAccessibility(_ rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX, y: primaryScreenMaxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The field's right edge, trusted only when the field is wider than a caret and actually holds the caret.
    private static func fieldEdge(_ field: CGRect?, holding start: CGFloat) -> CGFloat? {
        guard let field, !field.isNull, !field.isInfinite, field.width > minimumWidth,
            field.minX <= start, start <= field.maxX
        else { return nil }
        return field.maxX
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
}
