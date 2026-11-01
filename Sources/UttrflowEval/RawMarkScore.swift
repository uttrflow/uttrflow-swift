// The recogniser's own marks and case scored per mark and per class, with an interval over passages.
import UttrflowCore

/// One passage's raw recogniser text scored against its marked reference.
public struct RawMarkScore: Sendable, Equatable {
    public let passageID: String
    public let marks: PunctuationTally
    public let capitalisation: CapitalisationTally
    /// What an output that wrote the reference words in lower case with no mark would score on case.
    public let lowerCaseBaseline: CapitalisationTally

    public init(passageID: String, raw output: String, reference: String) {
        let wanted = ClassifiedWord.words(of: reference)
        self.passageID = passageID
        marks = PunctuationTally.measure(output, against: reference)
        capitalisation = CapitalisationTally.measure(Scorer.surfaceWords(output), against: wanted)
        lowerCaseBaseline = CapitalisationTally.measure(
            Scorer.surfaceWords(reference.lowercased()), against: wanted)
    }
}

/// A set of passages' raw scores pooled, each figure with a bootstrap interval that resamples passages.
public struct RawMarkReport: Sendable, Equatable {
    public let scores: [RawMarkScore]
    public let resamples: Int
    public let confidence: Double
    public let seed: UInt64

    public init(
        _ scores: [RawMarkScore], resamples: Int = 2_000, confidence: Double = 0.95, seed: UInt64 = 0x5EED
    ) {
        self.scores = scores
        self.resamples = resamples
        self.confidence = confidence
        self.seed = seed
    }

    public var marks: PunctuationTally { scores.map(\.marks).reduce(.init(), +) }
    public var capitalisation: CapitalisationTally { scores.map(\.capitalisation).reduce(.init(), +) }
    public var lowerCaseBaseline: CapitalisationTally { scores.map(\.lowerCaseBaseline).reduce(.init(), +) }

    /// The pooled F1 of `mark` and the interval over resampled passages; `nil` when no passage wants or has it.
    public func f1(of mark: MarkClass) -> (value: Double, interval: ClosedRange<Double>)? {
        guard let value = marks.f1(of: mark) else { return nil }
        let bounds = interval { drawn in drawn.map(\.marks).reduce(.init(), +).f1(of: mark) }
        return (value, bounds ?? value...value)
    }

    /// The pooled accuracy of `wordClass` and the interval over resampled passages; `nil` when none matched.
    public func accuracy(of wordClass: CapitalisationClass) -> (value: Double, interval: ClosedRange<Double>)?
    {
        guard let value = capitalisation.accuracy(of: wordClass) else { return nil }
        let bounds = interval { drawn in
            drawn.map(\.capitalisation).reduce(.init(), +).accuracy(of: wordClass)
        }
        return (value, bounds ?? value...value)
    }

    private func interval(_ statistic: ([RawMarkScore]) -> Double?) -> ClosedRange<Double>? {
        guard scores.count > 1 else { return nil }
        var generator = SplitMix(state: seed)
        var draws: [Double] = []
        for _ in 0..<resamples {
            let drawn = (0..<scores.count).map { _ in scores[Int(generator.next() % UInt64(scores.count))] }
            if let value = statistic(drawn) { draws.append(value) }
        }
        guard !draws.isEmpty else { return nil }
        draws.sort()
        let tail = (1 - confidence) / 2
        return PairedBootstrap.quantile(draws, tail)...PairedBootstrap.quantile(draws, 1 - tail)
    }
}
