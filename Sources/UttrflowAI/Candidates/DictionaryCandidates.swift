public import UttrflowCore
public import UttrflowDictionary

/// The user's own spellings for a doubtful run, found by the same phonetic lookup the correction engine uses.
public struct DictionaryCandidates: CandidateSource {
    /// Fewer than a span's whole budget, so one crowded sound cannot spend the whole line.
    public static let maximumOffered = 2

    private let index: @Sendable () async -> PhoneticIndex

    /// Reads the index per dictation rather than holding one, because the store rewrites it on every write.
    public init(index: @escaping @Sendable () async -> PhoneticIndex) {
        self.index = index
    }

    /// What the correction engine's lookup recalls, capped; `ReadingRestraint` is not asked, because a taught word is evidence.
    public func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading] {
        let candidates = WordCorrectionEngine.spellings(of: word.text, in: await index())
        let visible = Self.visibleWords(in: situation)
        return Array(
            candidates.filter { candidate in
                let entry = candidate.entry
                guard entry.origin == .learned || entry.origin == .observed,
                    GeneralVocabulary.isOrdinary(word.text)
                else { return true }
                return visible.contains(ReadingRestraint.closedUp(entry.word))
            }.map { Reading($0.word, entryID: $0.entry.id) }.prefix(Self.maximumOffered))
    }

    /// Screen text can corroborate an inferred word; the selected correction source is included too.
    private static func visibleWords(in situation: Situation) -> Set<String> {
        [
            situation.app.documentName, situation.app.selectedText,
            situation.insertion.precedingText, situation.insertion.followingText,
        ]
        .compactMap { $0 }
        .flatMap { WordTokens.words($0, .comparison) }
        .map { ReadingRestraint.closedUp($0) }
        .filter { !$0.isEmpty }
        .reduce(into: Set<String>()) { $0.insert($1) }
    }
}
