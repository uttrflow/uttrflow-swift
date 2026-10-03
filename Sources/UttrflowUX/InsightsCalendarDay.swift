public import Foundation

/// One day's tile on the calendar.
public struct InsightsCalendarDay: Sendable, Equatable, Identifiable {
    /// The start of the day.
    public let date: Date
    /// The day of the month drawn on the tile: "26".
    public let number: String
    /// Words dictated that day.
    public let words: Int
    /// Of the busiest day in the range, 0…1, so the view scales nothing itself.
    public let fraction: Double
    /// Whether this tile is today's.
    public let isToday: Bool
    /// "1,284 words · 26 Sept", shown on hover and read aloud.
    public let detail: String

    /// The start of this calendar day, unique across a multi-month range even when day numbers repeat.
    public var id: Date { date }
    /// A day with nothing said, drawn as a bare tile.
    public var isSilent: Bool { words == 0 }
    /// The teal's opacity, from a floor to full, stepping over the band where no number ink reaches 4.5:1.
    public var shade: Double {
        if isSilent { return 0 }
        let smooth = 0.15 + 0.85 * fraction
        guard smooth > Self.inkCeiling, smooth < Self.deepInkFloor else { return smooth }
        return smooth < (Self.inkCeiling + Self.deepInkFloor) / 2 ? Self.inkCeiling : Self.deepInkFloor
    }
    /// Whether the number is drawn in the deep ink, which is on every tile at or past ``deepInkFloor``.
    public var usesDeepInk: Bool { shade >= Self.deepInkFloor }

    /// The deepest shade the page's ink still clears 4.5:1 on in dark. See `Docs/redesign-tokens.md`.
    public static let inkCeiling = 0.5
    /// The palest shade the deep ink clears 4.5:1 on in dark.
    public static let deepInkFloor = 0.72

    /// Builds a tile; the fraction is clamped to 0…1.
    public init(
        date: Date, number: String, words: Int, fraction: Double, isToday: Bool, detail: String
    ) {
        self.date = date
        self.number = number
        self.words = words
        self.fraction = min(max(fraction, 0), 1)
        self.isToday = isToday
        self.detail = detail
    }
}
