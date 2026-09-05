public import UttrflowPredict

/// What the engine would have drawn at one keystroke, held until the committed value settles it.
public struct ShadowObservation: Sendable, Equatable {
    /// The text Tab would have inserted, or nothing when the answer was to stay quiet.
    public let offered: String?
    /// Whether the leader was far enough ahead to be shown alone, which is the confident case.
    public let wasCertain: Bool

    public init(offered: String?, wasCertain: Bool) {
        self.offered = offered
        self.wasCertain = wasCertain
    }

    /// Reads one observation off a suggestion, which is the only thing shadow mode does with it.
    public init(_ suggestion: Suggestion) {
        offered = suggestion.accepting
        wasCertain = if case .certain = suggestion { true } else { false }
    }
}

/// What shadow mode counted in one application, from which its three rates are read.
public struct ShadowTally: Sendable, Equatable {
    /// How many keystrokes the engine was asked about.
    public var keystrokes = 0
    /// How many of those would have put something on screen.
    public var shown = 0
    /// How many of those matched the value the user went on to commit.
    public var matched = 0
    /// How many were shown alone, at full separation, and were wrong.
    public var confidentlyWrong = 0

    public init(keystrokes: Int = 0, shown: Int = 0, matched: Int = 0, confidentlyWrong: Int = 0) {
        self.keystrokes = keystrokes
        self.shown = shown
        self.matched = matched
        self.confidentlyWrong = confidentlyWrong
    }

    /// How often anything would have been drawn at all, which is how intrusive the feature is.
    public var shownRate: Double { keystrokes > 0 ? Double(shown) / Double(keystrokes) : 0 }

    /// How often what was drawn was right, which is the number the whole phase exists to get.
    public var precisionAtOne: Double { shown > 0 ? Double(matched) / Double(shown) : 0 }

    /// How often the feature would have been confidently wrong, which is the one unforgivable failure.
    public var confidentlyWrongRate: Double {
        shown > 0 ? Double(confidentlyWrong) / Double(shown) : 0
    }

    /// Adds one tally to another, so a run's counts fold into an application's.
    public static func + (left: Self, right: Self) -> Self {
        Self(
            keystrokes: left.keystrokes + right.keystrokes, shown: left.shown + right.shown,
            matched: left.matched + right.matched,
            confidentlyWrong: left.confidentlyWrong + right.confidentlyWrong)
    }
}

/// One field's worth of observations, kept until the user finishes and reveals what was right.
public struct ShadowRun: Sendable, Equatable {
    private var observations: [ShadowObservation] = []

    public init() {}

    /// Notes what the engine would have drawn at this keystroke, and draws nothing.
    public mutating func observe(_ suggestion: Suggestion) {
        observations.append(ShadowObservation(suggestion))
    }

    /// Scores every observation against what was actually entered, and starts again.
    public mutating func resolve(against committed: String) -> ShadowTally {
        var tally = ShadowTally(keystrokes: observations.count)
        for observation in observations {
            guard let offered = observation.offered else { continue }
            tally.shown += 1
            if offered == committed {
                tally.matched += 1
            } else if observation.wasCertain {
                tally.confidentlyWrong += 1
            }
        }
        observations.removeAll()
        return tally
    }

    /// Throws the run away unscored, for a field the user left without finishing anything.
    public mutating func discard() {
        observations.removeAll()
    }

    /// Whether nothing has been observed yet, which is what an untouched field looks like.
    public var isEmpty: Bool { observations.isEmpty }
}
