// Disfluency removal scored by the words deleted, so a word removed in error never hides inside overlap.
public import UttrflowCore

/// The kind of disfluency a case is about, or a fluent control that should lose no word at all.
public enum DisfluencyClass: String, Sendable, Equatable, CaseIterable, Codable {
    /// A hesitation sound: "um", "uh".
    case filledPause = "filled-pause"
    /// A word or run said twice in a row.
    case repetition
    /// A start the speaker abandoned and began again.
    case restart
    /// A word the speaker replaced with another, announced by a one-word trigger.
    case selfRepair = "self-repair"
    /// A correction announced by a phrase of its own, which goes with the half it takes back.
    case editingPhrase = "editing-phrase"
    /// A discourse marker the clean-up keeps by policy, so nothing is deletable.
    case discourseMarker = "discourse-marker"
    /// Fluent speech with doubled words said on purpose, so nothing is deletable.
    case fluentControl = "fluent-control"
}

/// One case's deletions: the reference's, the output's and the words both removed, as word counts.
public struct DeletionScore: Sendable, Equatable {
    public let caseID: String
    public let disfluency: DisfluencyClass
    /// Spoken words the reference leaves out, which are the words deletable here.
    public let goldDeleted: [String]
    /// Spoken words the output leaves out.
    public let deleted: [String]
    /// Deleted words the reference also leaves out.
    public let correct: Int
    /// How many spoken words the reference keeps.
    public let fluentWords: Int
    /// Words removed by each pass, where the engine kept a record of its steps.
    public let removedBy: [PassID: Int]

    /// Words the reference keeps and the output deleted.
    public var overDeleted: Int { deleted.count - correct }
    /// Deletable words the output kept.
    public var missed: Int { goldDeleted.count - correct }

    /// Scores `output` for `testCase`, aligning each against the spoken words so a rewritten word is not a deleted one.
    public init(
        output: String, for testCase: EvaluationCase, disfluency: DisfluencyClass,
        record: CleaningRecord? = nil
    ) {
        let spoken = Scorer.tokens(testCase.spoken)
        let goldDeleted = Self.deletions(from: spoken, to: Scorer.tokens(testCase.expected))
        let deleted = Self.deletions(from: spoken, to: Scorer.tokens(output))
        var remaining = Dictionary(goldDeleted.map { ($0, 1) }, uniquingKeysWith: +)
        var correct = 0
        for word in deleted where remaining[word, default: 0] > 0 {
            remaining[word, default: 0] -= 1
            correct += 1
        }
        self.caseID = testCase.id
        self.disfluency = disfluency
        self.goldDeleted = goldDeleted
        self.deleted = deleted
        self.correct = correct
        self.fluentWords = spoken.count - goldDeleted.count
        self.removedBy = Dictionary(
            (record?.changes ?? []).filter { $0.removedCount > 0 }.map { ($0.step, $0.removedCount) },
            uniquingKeysWith: +)
    }

    /// The spoken words an aligned reading of `written` has no word for.
    static func deletions(from spoken: [String], to written: [String]) -> [String] {
        WordErrorRate.measure(reference: spoken, hypothesis: written).alignment.compactMap {
            if case .deletion(let word) = $0 { word } else { nil }
        }
    }
}

/// Deletion precision, recall and over-deletion over a group of cases, summed as word counts.
public struct DeletionRates: Sendable, Equatable {
    public let cases: Int
    public let goldDeleted: Int
    public let deleted: Int
    public let correct: Int
    public let fluentWords: Int
    public let removedBy: [PassID: Int]

    public init(_ scores: [DeletionScore]) {
        cases = scores.count
        goldDeleted = scores.reduce(0) { $0 + $1.goldDeleted.count }
        deleted = scores.reduce(0) { $0 + $1.deleted.count }
        correct = scores.reduce(0) { $0 + $1.correct }
        fluentWords = scores.reduce(0) { $0 + $1.fluentWords }
        removedBy = scores.reduce(into: [:]) { sum, score in sum.merge(score.removedBy, uniquingKeysWith: +) }
    }

    /// Share of deletions that were deletable; `nil` with no deletion, since nothing was claimed.
    public var precision: Double? { deleted == 0 ? nil : Double(correct) / Double(deleted) }
    /// Share of deletable words deleted; `nil` with nothing deletable.
    public var recall: Double? { goldDeleted == 0 ? nil : Double(correct) / Double(goldDeleted) }

    public var f1: Double? {
        guard let precision, let recall, precision + recall > 0 else { return nil }
        return 2 * precision * recall / (precision + recall)
    }

    /// Share of the words the reference keeps that the output deleted, the number that protects a speaker.
    public var overDeletion: Double { fluentWords == 0 ? 0 : Double(deleted - correct) / Double(fluentWords) }
}

/// One engine's deletion scores, read per disfluency class.
public struct DeletionReport: Sendable, Equatable {
    public let scores: [DeletionScore]

    public init(scores: [DeletionScore]) {
        self.scores = scores
    }

    /// Each class's rates, in declaration order, leaving out a class with no case.
    public var byClass: [(disfluency: DisfluencyClass, rates: DeletionRates)] {
        DisfluencyClass.allCases.compactMap { disfluency in
            let scores = scores.filter { $0.disfluency == disfluency }
            return scores.isEmpty ? nil : (disfluency, DeletionRates(scores))
        }
    }

    public var overall: DeletionRates { DeletionRates(scores) }

    /// Each class's rates as one line of counts and rates, keyed by class, as the committed baseline holds them.
    public var baseline: [String: String] {
        var lines = Dictionary(uniqueKeysWithValues: byClass.map { ($0.disfluency.rawValue, Self.line($0.rates)) })
        lines["all"] = Self.line(overall)
        return lines
    }

    /// The report as a table, one row per class, with the passes that made the deletions.
    public var table: String {
        let rows = byClass.map { ($0.disfluency.rawValue, $0.rates) } + [("all", overall)]
        return rows.map { label, rates in "\(label.padding(toLength: 18, withPad: " ", startingAt: 0)) \(Self.line(rates))" }
            .joined(separator: "\n")
    }

    static func line(_ rates: DeletionRates) -> String {
        let passes = rates.removedBy.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: ",")
        return [
            "cases=\(rates.cases)", "deletable=\(rates.goldDeleted)", "deleted=\(rates.deleted)",
            "correct=\(rates.correct)", "fluent=\(rates.fluentWords)",
            "precision=\(percent(rates.precision))", "recall=\(percent(rates.recall))",
            "f1=\(percent(rates.f1))", "over-deletion=\(percent(rates.overDeletion))",
            "by=\(passes.isEmpty ? "-" : passes)",
        ].joined(separator: " ")
    }

    private static func percent(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f%%", value * 100)
    }
}
