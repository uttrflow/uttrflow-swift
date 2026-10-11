// Who should own the question mark: the recogniser's choice of mark, the question-shape rules, or both.
private import Foundation

/// One spoken sentence with its true closing mark and what each candidate owner said about it.
public struct QuestionMarkCase: Sendable, Equatable {
    /// Whether the sentence is a question, from the clip's ground truth.
    public let isQuestion: Bool
    /// Whether the recogniser closed the sentence with "?".
    public let decoderAsks: Bool
    /// The recogniser's probability of "?" against "." at the closing position, when both were among its leaders.
    public let decoderQuestionProbability: Double?
    /// Whether `QuestionShape` reads the words, marks taken off, as a question.
    public let rulesAsk: Bool

    /// A scored sentence.
    public init(isQuestion: Bool, decoderAsks: Bool, decoderQuestionProbability: Double?, rulesAsk: Bool) {
        self.isQuestion = isQuestion
        self.decoderAsks = decoderAsks
        self.decoderQuestionProbability = decoderQuestionProbability
        self.rulesAsk = rulesAsk
    }
}

/// A proportion with its Wilson score interval at 95%.
public struct Proportion: Sendable, Equatable {
    /// The count that met the condition.
    public let hits: Int
    /// The count it is a share of.
    public let total: Int

    /// A share of `total`.
    public init(hits: Int, of total: Int) {
        self.hits = hits
        self.total = total
    }

    /// The share, or `nil` with nothing to share.
    public var value: Double? { total == 0 ? nil : Double(hits) / Double(total) }

    /// The Wilson interval, which stays inside 0...1 at small counts where the normal one does not.
    public var interval: ClosedRange<Double>? {
        guard total > 0 else { return nil }
        let z = 1.959_963_984_540_054
        let n = Double(total)
        let p = Double(hits) / n
        let centre = (p + z * z / (2 * n)) / (1 + z * z / n)
        let half = z / (1 + z * z / n) * (p * (1 - p) / n + z * z / (4 * n * n)).squareRoot()
        return max(0, centre - half)...min(1, centre + half)
    }
}

/// Precision, recall and false-question rate of one owner over a set of sentences.
public struct QuestionMarkScore: Sendable, Equatable {
    /// Of the sentences it marked "?", how many were questions.
    public let precision: Proportion
    /// Of the questions, how many it marked "?".
    public let recall: Proportion
    /// Of the statements, how many it marked "?".
    public let falseQuestionRate: Proportion

    /// Scores `asks` against each case's truth.
    public init(_ cases: [QuestionMarkCase], asks: (QuestionMarkCase) -> Bool) {
        let asked = cases.filter(asks)
        let questions = cases.filter(\.isQuestion)
        let statements = cases.filter { !$0.isQuestion }
        precision = Proportion(hits: asked.filter(\.isQuestion).count, of: asked.count)
        recall = Proportion(hits: questions.filter(asks).count, of: questions.count)
        falseQuestionRate = Proportion(hits: statements.filter(asks).count, of: statements.count)
    }
}

/// The probe's answer: each owner's score, the two combined, and how often they agree.
public struct QuestionMarkOwnership: Sendable, Equatable {
    /// The recogniser's own mark.
    public let decoder: QuestionMarkScore
    /// `QuestionShape` on the words alone.
    public let rules: QuestionMarkScore
    /// "?" only where both say so: the one combined feature the existing override gate could take.
    public let both: QuestionMarkScore
    /// How often the two owners make the same call.
    public let agreement: Proportion

    /// Scores every owner over the same sentences.
    public init(_ cases: [QuestionMarkCase]) {
        decoder = QuestionMarkScore(cases) { $0.decoderAsks }
        rules = QuestionMarkScore(cases) { $0.rulesAsk }
        both = QuestionMarkScore(cases) { $0.decoderAsks && $0.rulesAsk }
        agreement = Proportion(hits: cases.filter { $0.decoderAsks == $0.rulesAsk }.count, of: cases.count)
    }

    /// The table the pull request carries, one row per owner.
    public var table: String {
        func cell(_ share: Proportion) -> String {
            guard let value = share.value, let interval = share.interval else { return "n/a" }
            return String(
                format: "%.2f (%.2f-%.2f, %d/%d)", value, interval.lowerBound, interval.upperBound,
                share.hits,
                share.total)
        }
        let rows = [("decoder", decoder), ("rules", rules), ("both", both)].map { name, score in
            "| \(name) | \(cell(score.precision)) | \(cell(score.recall)) | \(cell(score.falseQuestionRate)) |"
        }
        return
            (["| Owner | Precision | Recall | False-question rate |", "|---|---|---|---|"] + rows
            + ["", "Agreement: \(cell(agreement))"]).joined(separator: "\n")
    }
}
