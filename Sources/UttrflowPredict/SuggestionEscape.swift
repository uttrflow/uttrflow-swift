public import struct Foundation.Date

/// What one more press of Escape means, ordered so that climbing the ladder is adding one.
public enum SuggestionEscape: Int, Sendable, Equatable, CaseIterable, Comparable, Codable {
    /// Take this suggestion off the screen and leave everything else alone.
    case dismissSuggestion
    /// Say nothing more in this field until the caret leaves it and comes back.
    case silenceField
    /// Switch this application off, and keep it off across launches.
    case turnOffApplication
    /// Stop everywhere for half an hour, after which it comes back on its own.
    case pauseEverywhere
    /// Switch the whole feature off, which only the Settings screen turns back on.
    case offEverywhere

    public static func < (lhs: SuggestionEscape, rhs: SuggestionEscape) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether reaching this rung changes something that outlives the field it was pressed in.
    public var outlivesTheField: Bool {
        self >= .turnOffApplication
    }
}

/// How far Escape has climbed in the field the caret is in, since the surface only sends events.
public struct SuggestionEscapeLadder: Sendable, Equatable {
    /// The rung the last press reached, or nothing while nothing has been refused here.
    public private(set) var reached: SuggestionEscape?

    /// Whether this field is silent until the caret leaves it and comes back.
    public private(set) var isFieldSilenced: Bool

    public init(reached: SuggestionEscape? = nil, isFieldSilenced: Bool = false) {
        self.reached = reached
        self.isFieldSilenced = isFieldSilenced
    }

    /// Takes one press of Escape and answers the rung it earned, stopping at the top.
    @discardableResult
    public mutating func escape() -> SuggestionEscape {
        let next: SuggestionEscape =
            if let reached {
                SuggestionEscape(rawValue: reached.rawValue + 1) ?? .offEverywhere
            } else {
                .dismissSuggestion
            }
        reached = next
        if next >= .silenceField { isFieldSilenced = true }
        return next
    }

    /// The caret went somewhere else, which is what earns a field its voice back.
    public mutating func focusChanged() {
        reached = nil
        isFieldSilenced = false
    }

    /// A suggestion was taken, so the climb starts again from the bottom in this field.
    public mutating func accepted() {
        reached = nil
    }

    /// What a rung means for the preferences, which is nothing at all for the first two.
    public static func carriedOut(
        _ rung: SuggestionEscape,
        in bundleIdentifier: String,
        to preferences: SuggestionPreferences,
        at moment: Date
    ) -> SuggestionPreferences {
        var updated = preferences
        switch rung {
        case .dismissSuggestion, .silenceField:
            break
        case .turnOffApplication:
            updated.set(bundleIdentifier, isOn: false)
        case .pauseEverywhere:
            updated.setPaused(true, at: moment)
        case .offEverywhere:
            updated.isEnabled = false
        }
        return updated
    }
}
