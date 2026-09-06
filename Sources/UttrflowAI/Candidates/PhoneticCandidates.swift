public import UttrflowCore
private import UttrflowDictionary

/// Ordinary words that sound like a doubtful run, so a mishearing can be offered a real word to be.
public struct PhoneticCandidates: CandidateSource {
    /// Fewer than a span's whole budget, so the screen and the dictionary keep their places on the line.
    public static let maximumOffered = 2

    public init() {}

    public func candidates(for word: Draft.Word, in situation: Situation) async -> [String] {
        Array(GeneralVocabulary.wordsSounding(like: word.text).prefix(Self.maximumOffered))
    }
}
