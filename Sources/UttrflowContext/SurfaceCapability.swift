import Foundation

/// Where a suggestion can be drawn for one text field, best first.
public enum SuggestionPlacement: String, Sendable, CaseIterable, Comparable {
    /// Grey text at the caret, on the user's own line, with any alternatives listed below it.
    case inlineGhost
    /// The old bottom-edge strip, kept only for the phase-0 probe's tally; nothing is ever drawn here now.
    case windowStrip

    /// Orders the ladder so the best placement is the smallest.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        guard let l = allCases.firstIndex(of: lhs), let r = allCases.firstIndex(of: rhs)
        else { return false }
        return l < r
    }
}

/// What one text field was willing to tell Accessibility about itself.
public struct SurfaceCapability: Sendable, Equatable {
    /// The application the field belongs to, named as the user knows it.
    public let application: String
    /// The field's Accessibility role, or `nil` when it publishes no focused element.
    public let role: String?
    /// What tells this field from another of the same role in the same application.
    public let locator: String?
    /// Whether the text already typed can be read, without which nothing can be predicted.
    public let reportsValue: Bool
    /// Whether the insertion point's screen rectangle can be read.
    public let reportsCaretRect: Bool
    /// Whether the font and colour at the insertion point can be read.
    public let reportsTextStyle: Bool
    /// Whether the field hides what is typed into it, as a password field does.
    public let isSecure: Bool
    /// How long the whole reading took, in microseconds.
    public let readMicroseconds: Int

    public init(
        application: String,
        role: String?,
        locator: String? = nil,
        reportsValue: Bool,
        reportsCaretRect: Bool,
        reportsTextStyle: Bool,
        isSecure: Bool,
        readMicroseconds: Int
    ) {
        self.application = application
        self.role = role
        self.locator = locator
        self.reportsValue = reportsValue
        self.reportsCaretRect = reportsCaretRect
        self.reportsTextStyle = reportsTextStyle
        self.isSecure = isSecure
        self.readMicroseconds = readMicroseconds
    }

    /// The inline ghost when the caret can be placed, or `nil` where nothing may be drawn off the line.
    public var placement: SuggestionPlacement? {
        guard !isSecure, reportsValue, reportsCaretRect else { return nil }
        return .inlineGhost
    }

    /// Identifies the field across readings, so a second visit refines rather than duplicates.
    var identity: String { "\(application)\u{0}\(role ?? "-")\u{0}\(locator ?? "-")" }

    /// Whether this reading saw strictly more than another of the same field.
    func supersedes(_ other: Self) -> Bool {
        (score, -readMicroseconds) > (other.score, -other.readMicroseconds)
    }

    /// Orders readings by application, then role, then field, leaving no pair unordered.
    var sortKey: String { "\(application.lowercased())\u{0}\(role ?? "")\u{0}\(locator ?? "")" }

    /// Ranks a reading by how much the field was willing to answer.
    private var score: Int {
        (reportsValue ? 4 : 0) + (reportsCaretRect ? 2 : 0) + (reportsTextStyle ? 1 : 0)
    }
}

/// The readings from one probe run, and the decision they add up to.
public struct CapabilitySweep: Sendable, Equatable {
    /// Below this share of fields reaching the inline ghost, the feature is not worth leading with.
    public static let inlineThreshold = 0.30

    private var byIdentity: [String: SurfaceCapability] = [:]

    public init(_ readings: [SurfaceCapability] = []) {
        for reading in readings { record(reading) }
    }

    /// Adds a reading, keeping whichever visit to that field saw the most.
    public mutating func record(_ reading: SurfaceCapability) {
        guard let existing = byIdentity[reading.identity] else {
            byIdentity[reading.identity] = reading
            return
        }
        if reading.supersedes(existing) { byIdentity[reading.identity] = reading }
    }

    /// Every field seen, in a total order so two runs of the probe read alike.
    public var readings: [SurfaceCapability] {
        byIdentity.values.sorted { $0.sortKey < $1.sortKey }
    }

    public var isEmpty: Bool { byIdentity.isEmpty }

    /// How many fields each placement would be drawn in.
    public func count(of placement: SuggestionPlacement?) -> Int {
        readings.filter { $0.placement == placement }.count
    }

    /// The share of fields that could take a suggestion at all.
    public var eligibleShare: Double {
        share { $0.placement != nil }
    }

    /// The share of fields that could take the inline ghost, which is what phase 0 decides.
    public var inlineShare: Double {
        share { $0.placement == .inlineGhost }
    }

    /// Whether the inline ghost reaches enough fields to be worth leading with, since it is the only surface.
    public var inlineIsWorthBuilding: Bool {
        !isEmpty && inlineShare >= Self.inlineThreshold
    }

    private func share(_ matches: (SurfaceCapability) -> Bool) -> Double {
        guard !isEmpty else { return 0 }
        return Double(readings.filter(matches).count) / Double(readings.count)
    }
}
