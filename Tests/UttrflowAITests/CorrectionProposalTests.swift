import Foundation
import UttrflowDictionary
import Testing

@testable import UttrflowAI

/// What a proposal has to carry, and the promise that it can always be taken back.
@Suite("WordCorrection")
struct CorrectionProposalTests {
    /// The engine under test.
    private let engine = WordCorrectionEngine()

    /// The Corrections page shows these, so each must say something a person can check.
    @Test("every reason has a label a user could act on", arguments: CorrectionReason.allCases)
    func reasonsAreLegible(reason: CorrectionReason) {
        #expect(!reason.summary.isEmpty)
        #expect(reason.summary.first?.isUppercase == true)
    }

    @Test("the labels are the ones the Corrections page shows")
    func reasonLabels() {
        #expect(CorrectionReason.seenOnScreen.summary == "Seen on screen")
        #expect(CorrectionReason.saidClearlyElsewhere.summary == "You said it clearly elsewhere")
        #expect(CorrectionReason.heardAsStrayLetters.summary == "Heard as stray letters")
        #expect(CorrectionReason.heardAsSeveralWords.summary == "Heard as several words")
    }

    /// A reason survives the dictation record, where the Corrections page reads it a day later.
    @Test("a reason keeps its meaning through storage", arguments: CorrectionReason.allCases)
    func reasonsRoundTripThroughStorage(reason: CorrectionReason) throws {
        let encoded = try JSONEncoder().encode(reason)
        #expect(try JSONDecoder().decode(CorrectionReason.self, from: encoded) == reason)
    }

    // MARK: Undo

    /// Apply a real proposal, take it back, and be exactly where you started.
    @Test("a correction can always be undone")
    func correctionsRoundTrip() {
        let utterance = CorrectionFixtures.spoken(
            "we should run the ?s ?q ?l migration tonight before the release goes out to everyone")
        let heard = utterance.words.map(\.text)
        let proposals = engine.proposals(for: utterance, against: CorrectionFixtures.index)
        let corrected = WordCorrection.applying(proposals, to: heard)

        #expect(
            corrected.joined(separator: " ")
                == "we should run the SQL migration tonight before the release goes out to everyone")
        #expect(WordCorrection.reverting(proposals, from: corrected) == heard)
    }

    /// One correction shrinks the sentence and one grows it, so undo must find where each landed.
    @Test("several corrections of different lengths all come back")
    func severalCorrectionsRoundTrip() {
        let heard = ["open", "the", "s", "q", "l", "file", "and", "the", "paymentsheet", "view"]
        let corrections = [
            Self.correction(heard: "s q l", replacement: "SQL", over: 2..<5),
            Self.correction(heard: "paymentsheet", replacement: "Payment Sheet", over: 8..<9),
        ]
        let corrected = WordCorrection.applying(corrections, to: heard)

        #expect(corrected == ["open", "the", "SQL", "file", "and", "the", "Payment", "Sheet", "view"])
        #expect(WordCorrection.reverting(corrections, from: corrected) == heard)
    }

    /// The engine sorts corrections, but nothing in the type stops a caller passing them unsorted.
    @Test("the order corrections arrive in does not matter")
    func orderOfApplicationDoesNotMatter() {
        let heard = ["the", "s", "q", "l", "and", "x", "m", "l", "notes"]
        let corrections = [
            Self.correction(heard: "x m l", replacement: "XML", over: 5..<8),
            Self.correction(heard: "s q l", replacement: "SQL", over: 1..<4),
        ]
        let corrected = WordCorrection.applying(corrections, to: heard)

        #expect(corrected == ["the", "SQL", "and", "XML", "notes"])
        #expect(WordCorrection.reverting(corrections, from: corrected) == heard)
    }

    @Test("correcting nothing leaves the words untouched")
    func applyingNothingChangesNothing() {
        let heard = ["nothing", "to", "see"]
        #expect(WordCorrection.applying([], to: heard) == heard)
        #expect(WordCorrection.reverting([], from: heard) == heard)
    }

    /// The entry is named so an undo can be counted against the word that caused it.
    @Test("a proposal names the entry that has to answer for it")
    func proposalsNameTheirEntry() throws {
        let utterance = CorrectionFixtures.spoken(
            "we should run the ?s ?q ?l migration tonight before the release goes out to everyone")
        let proposals = engine.proposals(for: utterance, against: CorrectionFixtures.index)
        let entry = try #require(
            CorrectionFixtures.entries.first { $0.word == "SQL" })
        #expect(proposals.map(\.entryID) == [entry.id])
    }

    /// A stray-letters correction over `range`.
    private static func correction(
        heard: String, replacement: String, over range: Range<Int>
    ) -> WordCorrection {
        WordCorrection(
            heard: heard, replacement: replacement, wordRange: range, entryID: UUID(),
            reason: .heardAsStrayLetters, heardConfidence: 0.2)
    }
}
