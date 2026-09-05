public import UttrflowCore
public import UttrflowDictionary

/// The user's own spellings for a doubtful run, found by the same phonetic lookup the correction engine uses.
public struct DictionaryCandidates: CandidateSource {
    private let index: @Sendable () async -> PhoneticIndex

    /// Reads the index per dictation rather than holding one, because the store rewrites it on every write.
    public init(index: @escaping @Sendable () async -> PhoneticIndex) {
        self.index = index
    }

    public func candidates(for word: Draft.Word, in situation: Situation) async -> [String] {
        WordCorrectionEngine.spellings(of: word.text, in: await index()).map(\.word)
    }
}
