public import UttrflowCore
internal import UttrflowDictionary
private import struct Foundation.Date

/// Shipped technical terms that sound like a doubtful run, so "Oath" in "add Oath login" can be offered "OAuth".
public struct TechnicalCandidates: CandidateSource {
    /// Fewer than a span's whole budget, so the screen and the user's dictionary keep their places on the line.
    public static let maximumOffered = 2

    /// The lexicon filed by sound once, by the same index and lookup the user's dictionary uses.
    static let index = PhoneticIndex(
        entries: TechnicalLexicon.terms.filter(isSaidAsAWord).map {
            DictionaryEntry(word: $0.id, origin: .shipped, firstSeen: Date(timeIntervalSince1970: 0))
        })

    public init() {}

    /// Terms that apply where the words are going and pass `ReadingRestraint`, since a shipped term is no evidence the user says it.
    public func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading] {
        let applicable = Set(
            TechnicalLexicon.terms.filter { $0.applies(in: situation.destination) }.map(\.id))
        return Array(
            WordCorrectionEngine.spellings(of: word.text, in: Self.index)
                .filter { applicable.contains($0.entry.word) }
                .map(\.word)
                .filter { ReadingRestraint.isWorthOffering($0, for: word.text) }
                .prefix(Self.maximumOffered)
                .map { Reading($0) })
    }

    /// Whether a shipped term is spelt as the word was heard, so "SwiftUI" is never doubted for its sentence.
    public func vouches(for heard: String, in situation: Situation) async -> Bool {
        let spelling = ReadingRestraint.closedUp(heard)
        return TechnicalLexicon.terms.contains { ReadingRestraint.closedUp($0.id) == spelling }
    }

    /// A term only ever spelt out letter by letter, such as API, sounds like no single word, so it is never filed by sound, nor is a joined form such as Q&A.
    static func isSaidAsAWord(_ term: TechnicalTerm) -> Bool {
        term.category != .joined
            && term.spoken.contains { form in form.split(separator: " ").contains { $0.count > 1 } }
    }
}
