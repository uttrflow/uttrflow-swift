// How complete a finished dictation is, and the one wording every surface uses when it is not.

/// How complete the inserted text is, decided once where the fallback ladder is known.
public enum OutcomeQuality: Sendable, Equatable, Codable {
    /// Everything said is there and the clean-up the person asked for ran, or none was asked for.
    case complete
    /// The rules tidied the words because the language model could not.
    case tidiedByRules(RulesReason)
    /// No clean-up ran, so the words went in as heard.
    case untidied(UntidiedReason)
    /// Part of what was said decoded to no words and is missing.
    case partial

    /// Why the language model did not tidy the words.
    public enum RulesReason: Sendable, Equatable, CaseIterable {
        case modelUnavailable, modelFailed, answerRefused
    }

    /// Why no clean-up ran.
    public enum UntidiedReason: Sendable, Equatable, CaseIterable {
        case timedOut, failed
    }

    /// Every value that is not complete, so a test can walk each rung and reason.
    static let incomplete: [OutcomeQuality] =
        RulesReason.allCases.map(OutcomeQuality.tidiedByRules)
        + UntidiedReason.allCases.map(OutcomeQuality.untidied) + [.partial]

    /// The stable text a kept record stores; never shown, and never renamed, since older files hold it.
    var storedName: String {
        switch self {
        case .complete: "complete"
        case .partial: "partial"
        case .tidiedByRules(let reason): "tidiedByRules.\(reason)"
        case .untidied(let reason): "untidied.\(reason)"
        }
    }

    /// Reads a stored name back; a name a newer build adds is `nil`, never a failure.
    init?(storedName: String) {
        guard
            let match = ([OutcomeQuality.complete] + Self.incomplete).first(where: {
                $0.storedName == storedName
            })
        else { return nil }
        self = match
    }

    /// Stored as its name, so a rung a newer build adds can be left out instead of discarding the file.
    public init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let known = OutcomeQuality(storedName: name) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown quality"))
        }
        self = known
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storedName)
    }

    /// Reads the quality off the engine that tidied the words, the dictation's cleaning account and the missed pieces.
    public init(producedBy: TransformerKind, account: CleaningRecord, missedPieces: Int) {
        if MissedSpeech.isMissing(missedPieces) {
            self = .partial
            return
        }
        let tidyTimedOut = account.skippedStages.contains { $0.stage == .tidy && $0.reason == .timeout }
        let engineTimedOut = account.engineFailures.contains { $0.failureClass == .timedOut }
        let tidyFailed =
            account.skippedStages.contains { $0.stage == .tidy && $0.reason == .error }
            || !account.engineFailures.isEmpty || !account.unavailableEngines.isEmpty
        switch producedBy {
        case .untidied:
            // Without a cause the clean-up was switched off, which the person chose, so nothing is degraded.
            if tidyTimedOut || engineTimedOut {
                self = .untidied(.timedOut)
            } else {
                self = tidyFailed ? .untidied(.failed) : .complete
            }
        case .rules:
            if !account.refusals.isEmpty {
                self = .tidiedByRules(.answerRefused)
            } else if !account.engineFailures.isEmpty {
                self = .tidiedByRules(.modelFailed)
            } else if !account.unavailableEngines.isEmpty {
                self = .tidiedByRules(.modelUnavailable)
            } else {
                self = .complete
            }
        case .foundationModels, .localModel, .cloud:
            self = .complete
        }
    }

    /// The glyph for a result tidied less than asked, which differs from the one for missing speech.
    public static let degradedSymbol = "exclamationmark.bubble"

    /// What every surface says about this quality; `nil` when nothing needs saying.
    public var presentation: Presentation? {
        switch self {
        case .complete:
            nil
        case .partial:
            Presentation(
                symbolName: "exclamationmark.circle", line: MissedSpeech.line, detail: MissedSpeech.detail,
                sentence: MissedSpeech.sentence)
        case .tidiedByRules(let reason):
            Self.presentation(rules: reason)
        case .untidied(let reason):
            Self.presentation(untidied: reason)
        }
    }

    private static func presentation(rules reason: RulesReason) -> Presentation {
        let because: String
        switch reason {
        case .modelUnavailable: because = "the language model was not available"
        case .modelFailed: because = "the language model did not finish"
        case .answerRefused: because = "the language model's answer was set aside"
        }
        return Presentation(
            symbolName: Self.degradedSymbol, line: "Inserted — basic clean-up",
            detail: "Only basic clean-up tidied this",
            sentence: "Only basic clean-up ran, because \(because).")
    }

    private static func presentation(untidied reason: UntidiedReason) -> Presentation {
        let because = reason == .timedOut ? "clean-up ran out of time" : "clean-up did not finish"
        return Presentation(
            symbolName: Self.degradedSymbol, line: "Inserted — not tidied",
            detail: "Your words went in as heard",
            sentence: "Your words went in exactly as heard, because \(because).")
    }

    /// The words and glyph for one degraded quality, sized for the dock, the menu bar and VoiceOver.
    public struct Presentation: Sendable, Equatable {
        public let symbolName: String
        /// The short headline for the dock and the menu bar status line.
        public let line: String
        /// The second line under the headline.
        public let detail: String
        /// The full sentence read aloud, which never abbreviates.
        public let sentence: String
    }
}
