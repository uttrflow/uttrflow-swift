import UttrflowCore
import UttrflowDictionary
import Testing

@testable import UttrflowAI

/// Condition three on its own, away from the engine, because it is the piece that decides
/// whether this feature is a help or a vandal.
@Suite("CorrectionEvidence")
struct CorrectionEvidenceTests {
    private func evidence(
        heard: String = "", seeing screen: String = ""
    ) -> CorrectionEvidence {
        CorrectionEvidence(
            utterance: CorrectionFixtures.spoken(heard),
            seeing: AppContext(selectedText: screen),
            certainAt: WordCorrectionEngine.certaintyThreshold)
    }

    // MARK: The margin

    @Test("nothing at all in favour of either reading is a tie, and a tie changes nothing")
    func noEvidenceIsNoReason() {
        #expect(evidence().decisiveReason(preferring: "Claude", over: "clawed") == nil)
    }

    /// The case the margin exists for: one signal, and two readings of the same shape.
    @Test("one signal does not beat a word of the same shape")
    func oneSignalIsNotDecisive() {
        #expect(
            evidence(seeing: "Claude notes").decisiveReason(preferring: "Claude", over: "clawed")
                == nil)
    }

    @Test("two signals decide it, and the strongest is the one reported")
    func twoSignalsAreDecisive() {
        let sut = evidence(heard: "Claude answered again", seeing: "Claude notes")
        #expect(sut.decisiveReason(preferring: "Claude", over: "clawed") == .seenOnScreen)
    }

    /// A run collapsing into one written word is a signal in its own right, so a word on
    /// screen only needs that one companion.
    @Test("a split word on the screen needs no other help")
    func aSplitWordOnScreenIsEnough() {
        #expect(
            evidence(seeing: "PaymentSheet.swift")
                .decisiveReason(preferring: "PaymentSheet", over: "payment sheet") == .seenOnScreen)
    }

    /// Stray letters are worth two on their own — the heard reading has neither the
    /// whole-words signal nor the shorter-reading one.
    @Test("stray letters are decisive without any context at all")
    func strayLettersAreDecisiveAlone() {
        #expect(
            evidence().decisiveReason(preferring: "SQL", over: "s q l") == .heardAsStrayLetters)
    }

    /// The evidence must be able to run *against* the dictionary word too, or it is not
    /// comparing anything.
    @Test("evidence for what was heard cancels evidence for the candidate")
    func theHeardReadingCanWin() {
        let sut = evidence(heard: "clawed at it again", seeing: "clawed marks on the bark")
        #expect(sut.decisiveReason(preferring: "Claude", over: "clawed") == nil)
    }

    // MARK: Individual signals

    @Test("a word below the certainty line cannot vouch for itself")
    func anUncertainWordIsNotCorroboration() {
        let sut = CorrectionEvidence(
            utterance: CorrectionFixtures.spoken("?Uttrflow and ?utter ?flow"),
            seeing: .unknown,
            certainAt: WordCorrectionEngine.certaintyThreshold)
        #expect(sut.decisiveReason(preferring: "Uttrflow", over: "utter flow") == nil)
    }

    @Test("the screen is read from the app, the document and the selection alike")
    func everyPartOfTheScreenCounts() {
        let context = AppContext(
            applicationName: "Grafana", documentName: "Terraform plan", selectedText: "asyncpg pool")
        let sut = CorrectionEvidence(
            utterance: CorrectionFixtures.spoken(""), seeing: context,
            certainAt: WordCorrectionEngine.certaintyThreshold)
        #expect(sut.decisiveReason(preferring: "Grafana", over: "graf an a") == .seenOnScreen)
        #expect(sut.decisiveReason(preferring: "Terraform", over: "terra form") == .seenOnScreen)
        #expect(sut.decisiveReason(preferring: "asyncpg", over: "a sink pee gee") == .seenOnScreen)
    }

    /// A run of words has to appear on screen *in order* to count, or "sheet payment" would
    /// be as corroborated as "payment sheet".
    @Test("a run only counts when the screen shows it in that order")
    func runsMustMatchInOrder() {
        let sut = evidence(seeing: "the sheet and the payment are separate things")
        #expect(sut.decisiveReason(preferring: "payment sheet", over: "PaymentSheet") == nil)
    }

    @Test("a run longer than everything on screen is not on screen")
    func aRunLongerThanTheScreenIsNotFound() {
        let sut = evidence(seeing: "payment")
        #expect(sut.decisiveReason(preferring: "payment sheet", over: "PaymentSheet") == nil)
    }

    /// A selection can be a whole document, so the read is capped. Past the cap the screen
    /// stops corroborating, which is the safe direction to fail in.
    @Test("only the first few hundred words on screen are read")
    func theScreenReadIsBounded() {
        let padding = String(repeating: "filler ", count: CorrectionEvidence.maximumWordsOnScreen)
        let inside = evidence(heard: "SQL again later", seeing: "SQL " + padding)
        let outside = evidence(heard: "SQL again later", seeing: padding + "SQL")
        #expect(inside.decisiveReason(preferring: "SQL", over: "sequel") == .seenOnScreen)
        #expect(outside.decisiveReason(preferring: "SQL", over: "sequel") == nil)
    }

    // MARK: Reading the text

    @Test(
        "a lone letter is a recogniser giving up, and a lone word is not",
        arguments: [
            ("SQL", true), ("s q l", false), ("a young tree", true), ("I said so", true),
            ("3 tickets", true), ("payment sheet", true), ("x m l", false), ("", true),
        ])
    func wholeWordsAreRecognised(text: String, expected: Bool) {
        #expect(CorrectionEvidence.readsAsWholeWords(text) == expected)
    }

    /// Text with nothing in it must not be corroborated by every screen there is.
    @Test("a reading with no words in it is never on screen")
    func punctuationIsNeverCorroborated() {
        #expect(evidence(seeing: "anything at all").decisiveReason(preferring: "—", over: "…") == nil)
    }
}

/// The ordering of the runs the engine considers, which has to be total or the same
/// utterance could produce different corrections on different runs.
@Suite("UncertainSpan")
struct CorrectionSpanTests {
    @Test("the least confident run is considered first")
    func confidenceComesFirst() {
        let spans = UncertainSpan.spans(
            in: Utterance(words: [
                SpokenWord(text: "one", confidence: 0.4),
                SpokenWord(text: "two", confidence: 0.1),
            ]),
            below: 0.5)
        #expect(spans.first?.text == "one two")
        #expect(spans.first?.confidence == 0.1)
    }

    @Test("equally doubtful runs are ordered earliest first, then longest")
    func tiesAreBrokenByPositionThenLength() {
        let spans = UncertainSpan.spans(in: CorrectionFixtures.doubting("one two three"), below: 0.5)
        #expect(spans.map(\.text) == ["one two three", "one two", "one", "two three", "two", "three"])
    }

    /// No run reaches across "three", which the recogniser was sure of — the three-word run
    /// starting at "one" is never even considered.
    @Test("runs stop at the first word the recogniser was sure of")
    func confidentWordsEndTheRun() {
        let spans = UncertainSpan.spans(
            in: CorrectionFixtures.spoken("?one ?two three ?four"), below: 0.5)
        #expect(spans.map(\.text) == ["one two", "one", "two", "four"])
    }

    @Test("an utterance with nothing doubtful in it has no runs")
    func certainUtterancesHaveNoRuns() {
        #expect(UncertainSpan.spans(in: CorrectionFixtures.spoken("all quite clear"), below: 0.5).isEmpty)
    }
}
