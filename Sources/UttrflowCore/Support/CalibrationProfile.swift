// What the guided read at setup leaves behind: a handful of aggregates as evidence rows, never audio or text. See `Docs/learned-state.md`.

/// The aggregates measured from one guided reading, and their round trip through the evidence ledger.
public struct CalibrationProfile: Sendable, Equatable {
    /// Words spoken per minute; nil when the reading timed fewer than two words.
    public let wordsPerMinute: Double?
    /// The median gap between two words of one sentence, in seconds.
    public let medianPause: Double?
    /// The 90th-percentile gap between two words of one sentence, in seconds.
    public let longPause: Double?
    /// The median recogniser confidence, from 0 to 1.
    public let medianConfidence: Double?
    /// How many technical-lexicon terms the passage asked for.
    public let targets: Int
    /// The terms that did not come out as read, one entry per miss.
    public let missedTargets: [String]

    /// A profile from measured values.
    public init(
        wordsPerMinute: Double?, medianPause: Double?, longPause: Double?, medianConfidence: Double?,
        targets: Int, missedTargets: [String]
    ) {
        self.wordsPerMinute = wordsPerMinute
        self.medianPause = medianPause
        self.longPause = longPause
        self.medianConfidence = medianConfidence
        self.targets = targets
        self.missedTargets = missedTargets
    }

    /// The pause setting whose sentence pause the long mid-sentence gap stays under; nil when no gap was timed.
    public var pauses: PauseLength? {
        guard let longPause else { return nil }
        return PauseLength.allCases.first {
            longPause < SpeechWindowing.standard.adjusted(for: $0).sentencePause
        }
            ?? .veryLong
    }

    /// The subjects of the `calibration` rows; a missed term is `missed:` and the term.
    private enum Subject {
        static let rate = "wordsPerMinute"
        static let medianPause = "medianPauseMilliseconds"
        static let longPause = "longPauseMilliseconds"
        static let confidence = "medianConfidencePercent"
        static let targets = "targets"
        static let missedPrefix = "missed:"
    }

    /// The rows that record this profile on `day`; a measure that was not taken writes no row.
    public func rows(day: Int) -> [EvidenceRow] {
        func row(_ subject: String, _ value: Int) -> EvidenceRow {
            EvidenceRow(kind: .calibration, subject: subject, weight: value, day: day, provenance: .user)
        }
        var rows: [EvidenceRow] = []
        if let wordsPerMinute { rows.append(row(Subject.rate, Int(wordsPerMinute.rounded()))) }
        if let medianPause { rows.append(row(Subject.medianPause, Int((medianPause * 1000).rounded()))) }
        if let longPause { rows.append(row(Subject.longPause, Int((longPause * 1000).rounded()))) }
        if let medianConfidence {
            rows.append(row(Subject.confidence, Int((medianConfidence * 100).rounded())))
        }
        rows.append(row(Subject.targets, targets))
        for term in missedTargets { rows.append(row(Subject.missedPrefix + term, 1)) }
        return rows
    }

    /// The profile the `calibration` rows describe, or nil when there are none; other kinds are ignored.
    public static func project(_ rows: [EvidenceRow]) -> CalibrationProfile? {
        var values: [String: Int] = [:]
        var missed: [String: Int] = [:]
        var found = false
        for row in rows where row.kind == .calibration {
            found = true
            if row.subject.hasPrefix(Subject.missedPrefix) {
                missed[String(row.subject.dropFirst(Subject.missedPrefix.count)), default: 0] += row.weight
            } else {
                values[row.subject, default: 0] += row.weight
            }
        }
        guard found else { return nil }
        return CalibrationProfile(
            wordsPerMinute: values[Subject.rate].map(Double.init),
            medianPause: values[Subject.medianPause].map { Double($0) / 1000 },
            longPause: values[Subject.longPause].map { Double($0) / 1000 },
            medianConfidence: values[Subject.confidence].map { Double($0) / 100 },
            targets: values[Subject.targets] ?? 0,
            missedTargets: missed.sorted { $0.key < $1.key }.flatMap {
                Array(repeating: $0.key, count: max(0, $0.value))
            })
    }
}

extension EvidenceLedgerStore {
    /// Records a reading in place of any earlier one, so running it twice leaves one profile.
    func replaceCalibration(
        with profile: CalibrationProfile, day: Int, keeping window: RetentionWindow
    ) throws {
        try replace(kinds: [.calibration], with: profile.rows(day: day), keeping: window)
    }

    /// Deletes the recorded reading, which is how the person clears it.
    func clearCalibration() throws {
        try forget(kinds: [.calibration])
    }
}
