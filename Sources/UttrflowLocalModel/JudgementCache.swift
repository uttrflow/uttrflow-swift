// Compact per-token log-softmax scores, kept so the model is not re-run for every keystroke.

import Foundation
import UttrflowCore

/// The candidate log-probabilities and cut-prefix masses the scorer needs for every span.
struct JudgedLine: Sendable, Equatable {
    /// The candidate's tokens with `leadIn` already prepended.
    let tokens: [Int]
    /// The log-probability of `tokens[i]` at position i, as read from the model's log-softmax.
    let tokenLogProbabilities: [Float]
    /// The one requested log mass, stored at its token position; all other positions are nil.
    let prefixLogMasses: [Float?]
    /// The one position whose prefix mass was requested for this judgement.
    let prefixMassIndex: Int?
    /// `texts[i]` is the decoded text of `tokens[i]`, so a span reads the same surface the forward pass did.
    let texts: [String]

    init(
        tokens: [Int], tokenLogProbabilities: [Float], prefixLogMasses: [Float?],
        prefixMassIndex: Int? = nil, texts: [String]
    ) {
        self.tokens = tokens
        self.tokenLogProbabilities = tokenLogProbabilities
        self.prefixLogMasses = prefixLogMasses
        self.prefixMassIndex = prefixMassIndex
        self.texts = texts
    }

    var isEmpty: Bool { tokens.isEmpty }

    /// The per-token log-probability the model gave the candidate at each position past its typed opening, with the cut case conditioned by `span`.
    static func judged(
        from line: JudgedLine, typedTokens: [Int], vocabulary: TokenHealing.Vocabulary
    ) -> [JudgedToken] {
        let bytes = vocabulary.bytes
        guard !line.tokens.isEmpty,
            let span = ScoredSpan(whole: line.tokens, typed: typedTokens, bytes: bytes),
            span.start < line.tokens.count
        else { return [] }
        let start = span.start
        var taken: [Float] = []
        taken.reserveCapacity(line.tokens.count - start)
        for i in start..<line.tokens.count {
            taken.append(line.tokenLogProbabilities[i - 1])
        }
        let continuing = ScoredSpan.continuing(span.owed, in: vocabulary)
        let mass =
            line.prefixMassIndex == start && continuing.contains(line.tokens[start])
            ? line.prefixLogMasses[start] : nil
        let scores = ScoredSpan.conditioned(taken, onMass: mass)
        return zip(line.texts[start...], scores).map {
            text, logProbability in JudgedToken(text: text, logProbability: logProbability)
        }
    }
}

/// Reads one candidate's token scores and cut-prefix masses in a single batch.
enum JudgementReadback {
    static func read<Value>(
        tokenScores: [Value], prefixMasses: [Value?],
        readBatch: ([Value]) -> [Float]
    ) -> (tokenScores: [Float], prefixMasses: [Float?]) {
        let values = readBatch(tokenScores + prefixMasses.compactMap { $0 })
        var nextMass = tokenScores.count
        let masses = prefixMasses.map { mass -> Float? in
            guard mass != nil else { return nil }
            defer { nextMass += 1 }
            return values[nextMass]
        }
        return (Array(values.prefix(tokenScores.count)), masses)
    }
}

/// A bounded LRU of the lines the model has already scored, so a keystroke only re-averages from the new `start`.
struct JudgementCache: Sendable {
    /// How many lines are kept, since a session sees a few candidates and forgets the rest.
    static let capacity = 16

    /// Each line against the candidate the model was asked to score, least recently used dropped first.
    private var held = BoundedCache<String, JudgedLine>(capacity: capacity)

    /// A cache holding nothing.
    init() {}

    /// The line for this candidate, nil when none is remembered.
    mutating func recall(candidate: String) -> JudgedLine? {
        held.value(for: candidate)
    }

    /// Remembers a freshly-scored line, dropping the least recently used to stay within capacity.
    mutating func remember(_ line: JudgedLine, for candidate: String) {
        held.store(line, for: candidate)
    }

    /// Drops every remembered line when leaving a field, forgetting suggestions, or releasing the model.
    mutating func forgetEverything() {
        held.forgetEverything()
    }

    /// How many lines are remembered, for the diagnostics page.
    var count: Int { held.count }
}
