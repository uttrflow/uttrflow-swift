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

/// Remembers where the user left the panel on each display, so a spot on one never places it on another.
public struct PanelSpots: Sendable, Equatable {
    /// Holds the origin last dragged to on each display, keyed by the display's number.
    public private(set) var origins: [UInt32: CGPoint]

    public init(origins: [UInt32: CGPoint] = [:]) {
        self.origins = origins
    }

    /// Reads back what `propertyList` wrote, skipping anything malformed rather than guessing at it.
    public init(propertyList: Any?) {
        var origins: [UInt32: CGPoint] = [:]
        for (key, value) in propertyList as? [String: Any] ?? [:] {
            guard let display = UInt32(key), let pair = value as? [Double], pair.count == 2 else {
                continue
            }
            origins[display] = CGPoint(x: pair[0], y: pair[1])
        }
        self.origins = origins
    }

    /// Gives the form kept in user defaults: each display's number as a string, and its origin as `[x, y]`.
    public var propertyList: [String: [Double]] {
        Dictionary(
            uniqueKeysWithValues: origins.map { display, origin in
                (String(display), [Double(origin.x), Double(origin.y)])
            })
    }

    /// Places the panel on this display at its own remembered spot, clamped, or else the default corner.
    public func origin(on display: UInt32?, size: CGSize, in visible: CGRect) -> CGPoint {
        PanelPlacement.origin(remembered: display.flatMap { origins[$0] }, size: size, in: visible)
    }

    /// Records where the user left the panel on this display, leaving every other display's spot alone.
    public mutating func remember(_ origin: CGPoint, on display: UInt32) {
        origins[display] = origin
    }
}
