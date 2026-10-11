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

    /// The frame at the caret's text baseline, never wider than the room after it or off the screen or window.
    public static func anchor(
        for placement: SuggestionPlacement,
        caret: CGRect?,
        window: CGRect?,
        field: CGRect? = nil,
        screen: CGRect,
        size: CGSize,
        direction: WritingDirection = .leftToRight,
        fontAscent: CGFloat? = nil,
        fontDescent: CGFloat? = nil
    ) -> SuggestionAnchor? {
        guard placement == .inlineGhost, let caret = usable(caret, on: screen),
            isVerticallyVisible(caret, in: window, field: field),
            let room = availableWidth(
                caret: caret, field: field, window: window, screen: screen, direction: direction),
            size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
            room >= min(size.width, minimumWidth)
        else { return nil }
        let width = min(size.width, room)
        let lowerY = max(screen.minY, window?.minY ?? screen.minY)
        let upperY = min(screen.maxY, window?.maxY ?? screen.maxY)
        let baselineTop = firstLineTop(caret: caret, ascent: fontAscent, descent: fontDescent)
        let top = min(max(baselineTop, lowerY), upperY)
        let height = min(size.height, max(top - lowerY, 0))
        guard height > 0 else { return nil }
        return SuggestionAnchor(
            placement: .inlineGhost,
            frame: CGRect(
                x: direction == .leftToRight ? caret.maxX : caret.minX - width,
                y: top - height, width: width, height: height))
    }

    /// The first line's top follows the field baseline when its font metrics are available.
    private static func firstLineTop(caret: CGRect, ascent: CGFloat?, descent: CGFloat?) -> CGFloat {
        guard let ascent, let descent, ascent.isFinite, descent.isFinite,
            ascent >= 0, descent >= 0
        else { return caret.maxY }
        return caret.minY + descent + ascent
    }

    /// A caret outside its visible container cannot anchor an inline ghost.
    private static func isVerticallyVisible(_ caret: CGRect, in window: CGRect?, field: CGRect?) -> Bool {
        if let window, !window.isNull, !window.isInfinite,
            (caret.minY < window.minY || caret.maxY > window.maxY)
        {
            return false
        }
        if let field, !field.isNull, !field.isInfinite, field.width > minimumWidth,
            field.minX <= caret.midX, caret.midX <= field.maxX,
            (caret.minY < field.minY || caret.maxY > field.maxY)
        {
            return false
        }
        return true
    }

    /// How far the ghost may run from the caret before it meets the containing edge in its writing direction.
    public static func availableWidth(
        caret: CGRect, field: CGRect?, window: CGRect?, screen: CGRect,
        direction: WritingDirection = .leftToRight
    ) -> CGFloat? {
        let start = direction == .leftToRight ? caret.maxX : caret.minX
        guard start.isFinite, start >= screen.minX, start <= screen.maxX else { return nil }
        let edge =
            direction == .leftToRight
            ? min(
                screen.maxX,
                fieldEdge(field, holding: start) ?? windowEdge(window, holding: start) ?? screen.maxX)
            : max(
                screen.minX,
                fieldLeadingEdge(field, holding: start) ?? windowLeadingEdge(window, holding: start)
                    ?? screen.minX)
        let room = direction == .leftToRight ? edge - start : start - edge
        return room > 0 ? room : nil
    }

    /// Whether a ghost this wide is drawn whole in this much room, since a cut ghost would hide what Tab inserts.
    public static func fits(_ width: CGFloat, in room: CGFloat) -> Bool {
        width.isFinite && room.isFinite && width <= room
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

    /// The window's right edge, the rung between a stale field rect and the screen.
    private static func windowEdge(_ window: CGRect?, holding start: CGFloat) -> CGFloat? {
        guard let window, !window.isNull, !window.isInfinite,
            window.minX <= start, start <= window.maxX
        else { return nil }
        return window.maxX
    }

    private static func fieldLeadingEdge(_ field: CGRect?, holding start: CGFloat) -> CGFloat? {
        guard let field, !field.isNull, !field.isInfinite, field.width > minimumWidth,
            field.minX <= start, start <= field.maxX
        else { return nil }
        return field.minX
    }

    private static func windowLeadingEdge(_ window: CGRect?, holding start: CGFloat) -> CGFloat? {
        guard let window, !window.isNull, !window.isInfinite,
            window.minX <= start, start <= window.maxX
        else { return nil }
        return window.minX
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
