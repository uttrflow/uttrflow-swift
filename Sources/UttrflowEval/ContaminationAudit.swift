// Whether any text a change is tuned on carries a corpus passage. See `Docs/eval-methodology.md`.

/// One audit for every tuned-on asset: prompt text, rule text and bundled data alike.
public struct ContaminationAudit: Sendable {
    /// A corpus passage found inside an asset, named so the copy can be found and removed.
    public struct Finding: Sendable, Equatable, CustomStringConvertible {
        public let caseID: String
        public let asset: String
        public let words: String

        public var description: String { "\(caseID) in \(asset): \(words)" }
    }

    /// A run this long is shared by copying; shorter runs of function words are shared by any two English texts.
    public static let sharedRunWords = 8
    /// A short phrase counts only when the whole of it sits in a passage, and only from this many words.
    public static let wholePhraseWords = 4

    private let shortestPhrase: Int
    private let runs: [Int: [String: Set<String>]]

    /// Indexes every passage as `(caseID, text)`; `shortestPhrase` below the default is for stricter callers.
    public init(passages: [(caseID: String, text: String)], shortestPhrase: Int = wholePhraseWords) {
        self.shortestPhrase = shortestPhrase
        var runs: [Int: [String: Set<String>]] = [:]
        for passage in passages {
            let words = Scorer.tokens(passage.text)
            for length in shortestPhrase...Self.sharedRunWords where words.count >= length {
                for start in 0...(words.count - length) {
                    let run = words[start..<(start + length)].joined(separator: " ")
                    runs[length, default: [:]][run, default: []].insert(passage.caseID)
                }
            }
        }
        self.runs = runs
    }

    /// Every clean-up case's spoken and expected text and every transcription passage.
    public static var corpusPassages: [(caseID: String, text: String)] {
        EvaluationCorpus.all.flatMap { [($0.id, $0.spoken), ($0.id, $0.expected)] }
            + TranscriptionCorpus.all.flatMap { passage in passage.forms.map { (passage.id, $0) } }
    }

    /// The audit over the whole corpus as it stands.
    public static var corpus: ContaminationAudit { ContaminationAudit(passages: corpusPassages) }

    /// Passages that `fragment` copies whole, or shares a run of ``sharedRunWords`` words with.
    public func findings(in fragment: String, asset: String) -> [Finding] {
        let words = Scorer.tokens(fragment)
        guard words.count >= shortestPhrase else { return [] }
        let length = min(words.count, Self.sharedRunWords)
        let index = runs[length] ?? [:]
        var found: [Finding] = []
        var seen: Set<String> = []
        for start in 0...(words.count - length) {
            let run = words[start..<(start + length)].joined(separator: " ")
            for caseID in (index[run] ?? []).sorted() where seen.insert(caseID + run).inserted {
                found.append(Finding(caseID: caseID, asset: asset, words: run))
            }
        }
        return found
    }

    /// Findings across many fragments of one asset, such as the lines of a data file.
    public func findings(in fragments: [String], asset: String) -> [Finding] {
        fragments.flatMap { findings(in: $0, asset: asset) }
    }
}
