import Foundation
import UttrflowDictionary
import Testing

@testable import UttrflowAI

/// What a proposal has to carry, and the promise that it can always be taken back.
@Suite("WordCorrection")
struct CorrectionProposalTests {
    private let engine = WordCorrectionEngine()

    /// The Corrections page reads these, so they are part of the product rather than
    /// debugging text. Each must say something a person could check for themselves.
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

    /// A reason survives a round trip through the dictation record, which is where the
    /// Corrections page reads it from a day later.
    @Test("a reason keeps its meaning through storage", arguments: CorrectionReason.allCases)
    func reasonsRoundTripThroughStorage(reason: CorrectionReason) throws {
        let encoded = try JSONEncoder().encode(reason)
        #expect(try JSONDecoder().decode(CorrectionReason.self, from: encoded) == reason)
    }

    // MARK: Undo

    /// The promise, on a real proposal from the real engine: apply it, then take it back,
    /// and be exactly where you started.
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

    /// Several corrections at once, one shrinking the sentence and one growing it, because
    /// the undo has to find where each replacement actually landed rather than where it
    /// was proposed.
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

    /// Corrections handed over out of order must still land in the right places — the
    /// engine sorts them, but nothing in the type stops a caller from not doing.
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

    /// Every proposal names the entry behind it, which is what lets an undo be counted
    /// against the word that caused it rather than merely discarded.
    @Test("a proposal names the entry that has to answer for it")
    func proposalsNameTheirEntry() throws {
        let utterance = CorrectionFixtures.spoken(
            "we should run the ?s ?q ?l migration tonight before the release goes out to everyone")
        let proposals = engine.proposals(for: utterance, against: CorrectionFixtures.index)
        let entry = try #require(
            CorrectionFixtures.entries.first { $0.word == "SQL" })
        #expect(proposals.map(\.entryID) == [entry.id])
    }

    private static func correction(
        heard: String, replacement: String, over range: Range<Int>
    ) -> WordCorrection {
        WordCorrection(
            heard: heard, replacement: replacement, wordRange: range, entryID: UUID(),
            reason: .heardAsStrayLetters, heardConfidence: 0.2)
    }
}
