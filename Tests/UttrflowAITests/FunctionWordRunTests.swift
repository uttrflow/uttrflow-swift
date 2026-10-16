import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// Runs of small words the recogniser doubted, against entries they merely sound like. See Docs/ai-correction-thresholds.md.
@Suite("Function-word runs")
struct FunctionWordRunTests {
    /// The engine under test.
    private let engine = WordCorrectionEngine()

    /// An index over these words, each added by the user.
    private static func index(_ words: [String]) -> PhoneticIndex {
        PhoneticIndex(
            entries: words.map {
                DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
            })
    }

    /// A sentence, the entry that sounds like a run of it, and what the screen shows.
    struct Row: Sendable, CustomTestStringConvertible {
        let sentence: String
        let entry: String
        let screen: String?
        var testDescription: String { "\(sentence) / \(entry)" }
    }

    static let rows = [
        Row(sentence: "I said I'd go.", entry: "Ada", screen: nil),
        Row(sentence: "It is a good idea.", entry: "iOS", screen: "notes about iOS"),
        Row(sentence: "I wanted to buy a record as a present.", entry: "iOS", screen: "notes about iOS"),
        Row(sentence: "That is it.", entry: "Istio", screen: "notes about Istio"),
        Row(sentence: "I finished the report and sent it to Maria.", entry: "Ada", screen: "Ada notes"),
    ]

    @Test("keeps a run of function words as spoken, however badly it was heard", arguments: rows)
    func keepsFunctionWords(row: Row) {
        let context = row.screen.map(CorrectionFixtures.showing) ?? .unknown
        let proposals = engine.proposals(
            for: CorrectionFixtures.doubting(row.sentence), against: Self.index([row.entry]),
            seeing: context)
        #expect(proposals.isEmpty, "\(row.sentence) → \(proposals.map(\.replacement))")
    }

    @Test("tells a run of function words from letters spelled out and from a half-heard name")
    func theRunIsOnlyFunctionWords() {
        #expect(WordCorrectionEngine.isOnlyFunctionWords("is a"))
        #expect(WordCorrectionEngine.isOnlyFunctionWords("is it."))
        #expect(WordCorrectionEngine.isOnlyFunctionWords("I'd"))
        #expect(!WordCorrectionEngine.isOnlyFunctionWords("a i"))
        #expect(!WordCorrectionEngine.isOnlyFunctionWords("pry a"))
        #expect(!WordCorrectionEngine.isOnlyFunctionWords(""))
    }

    @Test("still corrects a run that holds a word of its own")
    func stillCorrectsAHalfHeardName() throws {
        let utterance = CorrectionFixtures.doubting("ask pry a about the report")
        let proposals = engine.proposals(
            for: utterance, against: Self.index(["Priya"]),
            seeing: CorrectionFixtures.showing("Priya notes"))
        #expect(try #require(proposals.first).replacement == "Priya")
    }
}
