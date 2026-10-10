// Every reading the sources offered for one doubtful span, with what each source said about it, ranked by one scorer.

/// What the sources said about one reading, which is what a scorer weighs.
public struct HypothesisFeatures: Sendable, Equatable {
    /// The position, counted from 0, of the first source asked that offered the reading.
    public let firstSource: Int
    /// How many sources offered the reading.
    public let agreement: Int
}

/// One other reading of a doubtful span and what the sources said about it.
public struct Hypothesis: Sendable, Equatable {
    /// The reading as the first source to offer it wrote it, still carrying its dictionary entry.
    public let reading: Reading
    /// The features a scorer weighs.
    public let features: HypothesisFeatures
}

/// The readings of one doubtful span, each once, in the order the sources were asked, never the span as heard.
public struct HypothesisSet: Sendable, Equatable {
    /// The span as the recogniser wrote it.
    public let heard: String
    /// The lowest score the recogniser gave the span.
    public let confidence: Double
    /// Every reading, the first source to offer a spelling keeping it, so a taught word keeps its entry.
    public let hypotheses: [Hypothesis]
    /// The said words just before the span, nearest last, which a context scorer reads.
    let before: [String]
    /// The said words just after the span, nearest first.
    let after: [String]

    /// Gathers each source's answer, given in the order the sources were asked; spellings are matched ignoring case.
    public init(
        heard: String, confidence: Double, answers: [[Reading]], before: [String] = [], after: [String] = []
    ) {
        self.heard = heard
        self.confidence = confidence
        self.before = before
        self.after = after
        var order: [String] = []
        var found: [String: (reading: Reading, first: Int, sources: Set<Int>)] = [:]
        for (source, answer) in answers.enumerated() {
            for reading in answer where reading.spelling != heard && !reading.spelling.isEmpty {
                let key = reading.spelling.lowercased()
                if found[key] == nil {
                    order.append(key)
                    found[key] = (reading, source, [])
                }
                found[key]?.sources.insert(source)
            }
        }
        hypotheses = order.compactMap { key in
            found[key].map {
                Hypothesis(
                    reading: $0.reading,
                    features: HypothesisFeatures(firstSource: $0.first, agreement: $0.sources.count))
            }
        }
    }

    /// The readings best first by `scorer`, ties and a scorer that does not answer for every reading keeping the sources' order.
    public func ranked(by scorer: any SpanScorer) -> [Reading] {
        let scores = scorer.scores(for: self)
        guard scores.count == hypotheses.count else { return hypotheses.map(\.reading) }
        return hypotheses.indices
            .sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
            .map { hypotheses[$0].reading }
    }
}

/// What a scorer spends per span, so a caller can tell a table lookup from a scorer that needs the audio again.
public enum SpanScorerCost: Sendable, Equatable {
    /// A lookup in memory, within the single-digit milliseconds a source is held to.
    case lookup
    /// Another pass of the recogniser over the span's audio.
    case recogniserPass
}

/// The one place the readings of a doubtful span are weighed against each other.
public protocol SpanScorer: Sendable {
    /// What scoring one span costs.
    var cost: SpanScorerCost { get }

    /// One score per hypothesis, in the set's order; higher is better.
    func scores(for set: HypothesisSet) -> [Double]
}

/// Ranks readings in the order the sources were asked, so the user's own words come before the screen's.
public struct SourceOrderScorer: SpanScorer {
    public let cost = SpanScorerCost.lookup

    public init() {}

    public func scores(for set: HypothesisSet) -> [Double] { set.hypotheses.indices.map { -Double($0) } }
}
