/// How far back the calendar reaches.
public enum InsightsRange: String, Sendable, CaseIterable, Identifiable {
    case week = "7"
    case month = "30"
    case quarter = "90"

    /// The identifier the page reports back when this range is picked.
    public var id: String { rawValue }

    /// The days the range covers, today included.
    public var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    /// "30 days".
    public var title: String { "\(days) days" }
}

/// One segment of the range switch.
public struct InsightsRangeOption: Sendable, Equatable, Identifiable {
    /// The range this segment picks.
    public let range: InsightsRange
    /// Whether this is the range the calendar shows.
    public let isSelected: Bool
    /// Why the range cannot be picked; absent when it can.
    public let unavailableReason: String?

    /// The range's identifier.
    public var id: String { range.id }
    /// "30 days".
    public var title: String { range.title }
    /// Whether the range reaches no further back than history is kept.
    public var isAvailable: Bool { unavailableReason == nil }

    /// Builds a segment.
    public init(range: InsightsRange, isSelected: Bool, unavailableReason: String? = nil) {
        self.range = range
        self.isSelected = isSelected
        self.unavailableReason = unavailableReason
    }
}
