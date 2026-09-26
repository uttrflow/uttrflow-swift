/// What the model has already said about the line, and whether it should be asked again.
public struct ModelPass: Sendable {
    /// What the model does on this turn for a line.
    public enum Plan: Sendable, Equatable {
        /// An earlier answer still begun by the line is drawn without a pass.
        case reuse([String])
        /// The model's last word on this exact line was nothing, so no pass is run.
        case skip
        /// A fresh pass is run.
        case ask
    }

    /// Where the alternatives behind a single drawn line come from.
    public enum AlternativesSource: Sendable, Equatable {
        /// The machine's other values, with no pass spent on them.
        case values([String])
        /// A second model pass.
        case model
    }

    /// The last answer that stood, with the field and line it was asked on.
    public private(set) var lastGenerated: (surface: Surface, typed: String, completions: [String])?
    /// The last line whose pass came back empty or failed.
    public private(set) var lastEmpty: (surface: Surface, typed: String)?

    /// Nothing remembered.
    public init() {}

    /// Whether the model is asked at all, given what the corpus and gates settled on.
    public static func shouldAsk(after update: SuggestionUpdate, hasGenerator: Bool, isReady: Bool) -> Bool {
        update.suggestion.accepting == nil && update.silence != .overBudget && hasGenerator && isReady
    }

    /// Whether an answer that took a while is still fresh enough to draw against the field read now.
    public static func isFresh(
        keystrokesBefore: Int, keystrokesNow: Int, isCurrent: Bool, sameReading: Bool, sameLine: Bool
    ) -> Bool {
        keystrokesBefore == keystrokesNow && isCurrent && sameReading && sameLine
    }

    /// Where the alternatives come from: the machine's values when it listed any, otherwise the model.
    public static func alternativesSource(
        typed: String, choices: [String], leader: String
    ) -> AlternativesSource {
        guard !choices.isEmpty else { return .model }
        return .values(Verification.completed(typed, with: choices).filter { $0 != leader })
    }

    /// Forgets both memories on a new field or an emptied line.
    public mutating func freshStart(surfaceChanged: Bool, lineIsEmpty: Bool) {
        guard surfaceChanged || lineIsEmpty else { return }
        lastGenerated = nil
        lastEmpty = nil
    }

    /// What to do for this query: reuse an answer the line still begins, skip a line known empty, or ask.
    public func plan(for query: SuggestionQuery) -> Plan {
        let lowered = query.typed.lowercased()
        let kept =
            (lastGenerated?.surface == query.surface ? lastGenerated?.completions : nil)?
            .filter { $0.lowercased().hasPrefix(lowered) && $0 != query.typed } ?? []
        if !kept.isEmpty { return .reuse(kept) }
        if let lastEmpty, lastEmpty.surface == query.surface, lastEmpty.typed == query.typed { return .skip }
        return .ask
    }

    /// Remembers that this exact line came back empty or failed, so a tick does not repeat it.
    public mutating func rememberEmpty(_ query: SuggestionQuery) {
        lastEmpty = (query.surface, query.typed)
    }

    /// Remembers what stood of an answer, or the line as empty when nothing did.
    public mutating func remember(_ standing: [String], for query: SuggestionQuery) {
        if standing.isEmpty {
            rememberEmpty(query)
        } else {
            lastGenerated = (query.surface, query.typed, standing)
        }
    }
}
