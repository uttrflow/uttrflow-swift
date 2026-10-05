// Which transcription passages a fitted layer may learn from, tune a threshold on, or be judged by.

/// The side of the transcription corpus a passage sits on; assigned per passage, never per recording. See `Docs/eval-methodology.md`.
public enum TranscriptionSplit: String, Sendable, Equatable, CaseIterable, Codable {
    /// Passages a fitted layer may learn from.
    case fit
    /// Passages a threshold or other setting is chosen on, kept apart so the choice is not scored on itself.
    case calibration
    /// Passages read only to judge a release; nothing is fitted or tuned on them.
    case test

    /// The committed assignment by passage id, so a new passage cannot move an old one across.
    public static let assignment: [String: TranscriptionSplit] = [
        "en-standup": .fit, "en-terms": .fit,
        "en-restarts": .calibration, "en-message": .calibration,
        "en-people": .test, "en-versions": .test,
        "hi-everyday": .fit, "hi-long": .fit,
        "hi-request": .calibration, "hi-restarts": .calibration,
        "hi-people": .test, "hi-numbers": .test,
        "hinglish-standup": .fit, "hinglish-terms": .fit,
        "hinglish-restarts": .calibration, "hinglish-message": .calibration,
        "hinglish-people": .test, "hinglish-numbers": .test,
    ]

    /// Fewest test passages a language may have, since one passage is one speaker's one reading of one text.
    public static let minimumTestPassages = 2
}

extension TranscriptionCase {
    /// The side this passage is on, or `nil` when the assignment does not name it.
    public var split: TranscriptionSplit? { TranscriptionSplit.assignment[id] }
}

/// Fails when a transcription passage is unassigned, or shares a passage-length run with a passage on another side.
public struct SplitLeakAudit: Sendable {
    /// One reason the split cannot be trusted, worded so it names what to move.
    public enum Finding: Sendable, Equatable, CustomStringConvertible {
        case unassigned(passageID: String)
        case staleAssignment(passageID: String)
        case sharedRun(passageID: String, side: TranscriptionSplit, testPassageID: String, words: String)
        case tooFewTestPassages(language: TranscriptionCase.Language, count: Int)

        public var description: String {
            switch self {
            case .unassigned(let id): "\(id) has no side in TranscriptionSplit.assignment"
            case .staleAssignment(let id): "\(id) is assigned a side but is not in the corpus"
            case .sharedRun(let id, let side, let other, let words):
                "\(id) (\(side.rawValue)) shares with \(other): \(words)"
            case .tooFewTestPassages(let language, let count):
                "\(language.rawValue) has \(count) test passages; at least \(TranscriptionSplit.minimumTestPassages) are needed"
            }
        }
    }

    public let passages: [TranscriptionCase]
    public let assignment: [String: TranscriptionSplit]

    public init(
        passages: [TranscriptionCase] = TranscriptionCorpus.all,
        assignment: [String: TranscriptionSplit] = TranscriptionSplit.assignment
    ) {
        self.passages = passages
        self.assignment = assignment
    }

    /// Passage count per side for one language, the numbers a reader needs to judge the split.
    public func counts(in language: TranscriptionCase.Language) -> [TranscriptionSplit: Int] {
        passages.filter { $0.language == language }.reduce(into: [:]) { counts, passage in
            if let side = assignment[passage.id] { counts[side, default: 0] += 1 }
        }
    }

    /// Every reason the split leaks or is too thin, empty when it is sound.
    public var findings: [Finding] {
        let ids = Set(passages.map(\.id))
        var found = passages.filter { assignment[$0.id] == nil }.map { Finding.unassigned(passageID: $0.id) }
        found += assignment.keys.filter { !ids.contains($0) }.sorted().map {
            Finding.staleAssignment(passageID: $0)
        }
        let test = passages.filter { assignment[$0.id] == .test }
        let audit = ContaminationAudit(
            passages: test.flatMap { passage in passage.forms.map { (passage.id, $0) } },
            shortestPhrase: ContaminationAudit.sharedRunWords)
        for passage in passages {
            guard let side = assignment[passage.id], side != .test else { continue }
            let shared = passage.forms.flatMap { audit.findings(in: $0, asset: passage.id) }
            found += shared.map {
                .sharedRun(passageID: passage.id, side: side, testPassageID: $0.caseID, words: $0.words)
            }
        }
        for language in TranscriptionCase.Language.allCases {
            let count = counts(in: language)[.test] ?? 0
            if count < TranscriptionSplit.minimumTestPassages {
                found.append(.tooFewTestPassages(language: language, count: count))
            }
        }
        return found
    }
}
