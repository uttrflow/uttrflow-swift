public import UttrflowCore
private import UttrflowDictionary

/// The words the pronunciation lexicon lists as said exactly like this one, so a confidently wrong hearing can be reconsidered.
public struct HomophoneCandidates: CandidateSource {
    /// The most partners offered, ordinary words first, so a crowded sound cannot fill the span's line.
    public static let maximumOffered = 2

    public init() {}

    public func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading] {
        GeneralVocabulary.homophones(of: word.text)
            .prefix(Self.maximumOffered)
            .map { Reading($0) }
    }
}
