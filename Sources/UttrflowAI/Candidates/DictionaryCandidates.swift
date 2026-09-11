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

    /// The entries the engine would consider, less the ones that only collide on a sound key.
    public func candidates(for word: Draft.Word, in situation: Situation) async -> [String] {
        let heard = word.text
        return Array(
            WordCorrectionEngine.spellings(of: heard, in: await index())
                .map(\.word)
                .filter {
                    DoubtfulSpan.closedUp($0) == DoubtfulSpan.closedUp(heard)
                        || ReadingRestraint.opensAlike($0, heard: heard)
                }
                .prefix(Self.maximumOffered))
    }
}
