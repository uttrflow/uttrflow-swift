// Tests how corrections are spliced, reported and scored.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

// MARK: - Building blocks

private let entry = UUID()

private func correction(
    heard: String, wrote: String, at range: Range<Int>, entry: UUID = entry,
    confidence: Double = 0.2
) -> DictationCorrection {
    DictationCorrection(
        heard: heard, wrote: wrote, wordRange: range, entryID: entry,
        reason: "heardAsSeveralWords", heardConfidence: confidence)
}

// MARK: - Tests

@Suite("Applying corrections to a transcript")
struct ApplyingCorrectionsTests {
    @Test("Replaces the words the range names, and only those")
    func replacesTheNamedWords() {
        let result = DictationCorrection.applying(
            [correction(heard: "payment sheet", wrote: "PaymentSheet", at: 2..<4)],
            to: "open the payment sheet again")

        #expect(result.text == "open the PaymentSheet again")
        #expect(result.corrections.count == 1)
    }

    /// Splicing by character range is what keeps a dictated code block off one line.
    @Test("Keeps every newline, indent and double space exactly where it was")
    func keepsTheWhitespace() {
        let spoken = "func  main() {\n    print s q l\n}"
        let result = DictationCorrection.applying(
            [correction(heard: "s q l", wrote: "SQL", at: 4..<7)], to: spoken)

        #expect(result.text == "func  main() {\n    print SQL\n}")
    }

    @Test("Applies several changes at once, in any order they arrive")
    func appliesSeveralAtOnce() {
        let result = DictationCorrection.applying(
            [
                correction(heard: "clawed", wrote: "Claude", at: 3..<4),
                correction(heard: "utterflow", wrote: "Uttrflow", at: 0..<1),
            ],
            to: "utterflow asked clawed clawed")

        #expect(result.text == "Uttrflow asked clawed Claude")
        #expect(result.corrections.map(\.wrote) == ["Uttrflow", "Claude"])
    }

    /// A replacement can differ in word count, so the whole set applies against the original ranges.
    @Test("Survives a replacement that is a different length to what it replaced")
    func survivesALengthChange() {
        let result = DictationCorrection.applying(
            [
                correction(heard: "s q l", wrote: "SQL", at: 1..<4),
                correction(heard: "cube control", wrote: "kubectl", at: 5..<7),
            ],
            to: "run s q l with cube control now")

        #expect(result.text == "run SQL with kubectl now")
    }

    @Test("Leaves the transcript alone when there is nothing to change")
    func leavesItAloneWhenEmpty() {
        let result = DictationCorrection.applying([], to: "nothing to do here")

        #expect(result.text == "nothing to do here")
        #expect(result.corrections.isEmpty)
    }

    /// A bad range reaches this through a protocol and must cost a correction rather than a dictation.
    @Test(
        "Drops a range the transcript does not have",
        arguments: [4..<6, 9..<10, -1..<1, 2..<2])
    func dropsAnImpossibleRange(range: Range<Int>) {
        let result = DictationCorrection.applying(
            [correction(heard: "whatever", wrote: "ruined", at: range)],
            to: "one two three four")

        #expect(result.text == "one two three four")
        #expect(result.corrections.isEmpty)
    }

    /// Two changes wanting the same word: the first wins and the second is dropped, never written over it.
    @Test("Drops a change that overlaps one already taken")
    func dropsAnOverlap() {
        let result = DictationCorrection.applying(
            [
                correction(heard: "s q l", wrote: "SQL", at: 1..<4),
                correction(heard: "q l", wrote: "QL", at: 2..<4),
            ],
            to: "run s q l now")

        #expect(result.text == "run SQL now")
        #expect(result.corrections.count == 1)
    }

    /// The recogniser hangs a comma on the word before it, and the sentence still needs that comma.
    @Test("Keeps the punctuation the replaced word was wearing")
    func keepsTheWordsPunctuation() {
        let result = DictationCorrection.applying(
            [correction(heard: "tarvock,", wrote: "Tarvok", at: 2..<3)],
            to: "Open the tarvock, then check tarvock.")

        #expect(result.text == "Open the Tarvok, then check tarvock.")
    }

    /// A word behind a quote or a bracket keeps both sides, since neither was the word.
    @Test("Keeps punctuation on both sides of the replaced word")
    func keepsPunctuationOnBothSides() {
        let result = DictationCorrection.applying(
            [correction(heard: "(tarvock).", wrote: "Tarvok", at: 1..<2)], to: "ask (tarvock). again")

        #expect(result.text == "ask (Tarvok). again")
    }

    /// A run is replaced whole, so only what sits outside the run survives it.
    @Test("Keeps the punctuation outside a run of several words, not the punctuation within it")
    func keepsPunctuationAroundARun() {
        let result = DictationCorrection.applying(
            [correction(heard: "payment, sheet.", wrote: "PaymentSheet", at: 2..<4)],
            to: "open the payment, sheet. again")

        #expect(result.text == "open the PaymentSheet. again")
    }

    /// Undo splices back what a correction says it wrote, so that has to be what reached the transcript.
    @Test("Reports what it wrote including the punctuation it kept")
    func reportsWhatItWrote() {
        let result = DictationCorrection.applying(
            [correction(heard: "tarvock,", wrote: "Tarvok", at: 2..<3)], to: "open the tarvock, then")

        #expect(result.corrections.map(\.wrote) == ["Tarvok,"])
        #expect(result.corrections.map(\.heard) == ["tarvock,"], "what was heard is not rewritten")
    }

    /// A change offered for undo that never happened would be as dishonest as one made and never shown.
    @Test("Reports only the changes that actually landed")
    func reportsOnlyWhatLanded() {
        let result = DictationCorrection.applying(
            [
                correction(heard: "utterflow", wrote: "Uttrflow", at: 0..<1),
                correction(heard: "nowhere", wrote: "lost", at: 8..<9),
            ],
            to: "utterflow is the name")

        #expect(result.text == "Uttrflow is the name")
        #expect(result.corrections.map(\.wrote) == ["Uttrflow"])
    }
}

@Suite("What a dictation changed")
struct AppliedChangesTests {
    @Test("A dictation that came out as it was said has nothing to show")
    func noneIsEmpty() {
        #expect(AppliedChanges.none.isEmpty)
        #expect(AppliedChanges.none.corrections.isEmpty)
        #expect(AppliedChanges.none.snippets.isEmpty)
    }

    @Test("A single correction is enough to have something to show")
    func aCorrectionIsNotEmpty() {
        let changes = AppliedChanges(
            corrections: [correction(heard: "utterflow", wrote: "Uttrflow", at: 0..<1)])

        #expect(!changes.isEmpty)
    }

    @Test("A single expansion is enough on its own")
    func aSnippetIsNotEmpty() {
        let changes = AppliedChanges(
            snippets: [SnippetUse(snippetID: UUID(), matched: "my address", expansion: "12 Some St")])

        #expect(!changes.isEmpty)
    }

    @Test("An unchanged transcript carries no changes")
    func unchangedCarriesNothing() {
        #expect(CorrectedTranscript.unchanged("as said").corrections.isEmpty)
        #expect(CorrectedTranscript.unchanged("as said").text == "as said")
        #expect(ExpandedTranscript.unchanged("as said").snippets.isEmpty)
        #expect(ExpandedTranscript.unchanged("as said").text == "as said")
    }
}

@Suite("What the recogniser is willing to score")
struct ScoredWordTests {
    /// `Transcription` carries no confidence, so no word is eligible for correction and none is invented.
    @Test("No transcription this app can produce carries a per-word score")
    func nothingIsScoredToday() {
        #expect(Transcription.fixture().scoredWords == nil)
        #expect(Transcription(text: "").scoredWords == nil)
    }

    @Test("A score is carried as given")
    func aScoreIsCarried() {
        #expect(ScoredWord(text: "utterflow", confidence: 0.2).confidence == 0.2)
    }
}

@Suite("A pipeline wired to nothing")
struct NoTextChangesTests {
    /// Exercised through the existentials the pipeline holds, the only shape this type is used in.
    @Test("Proposes nothing, expands nothing and counts nothing")
    func changesNothing() async throws {
        let corrector: any WordCorrecting = NoTextChanges()
        let expander: any SnippetExpanding = NoTextChanges()
        let learner: any DictationLearning = NoTextChanges()

        #expect(try await corrector.corrections(for: .fixture(), seeing: .fixture()).isEmpty)

        let expanded = try await expander.expand("the words as spoken")
        #expect(expanded.text == "the words as spoken")
        #expect(expanded.snippets.isEmpty)

        // Neither throws, which is the whole of what a caller needs from them.
        try await learner.recordUse(ofEntries: [UUID()])
        try await learner.recordUse(ofSnippets: [UUID()])
    }
}

/// Where each correction's written words land in the text that is inserted, after tidying and snippets.
@Suite("Locating corrections in the inserted text")
struct LocatingCorrectionsTests {
    /// Finds `wrote` at `range` in `corrected` and returns the index it landed at in `finished`.
    private func landing(
        _ wrote: String, at range: Range<Int>, from corrected: String, in finished: String
    ) -> Int? {
        DictationCorrection.locating(
            [correction(heard: "tarvock", wrote: wrote, at: range)], from: corrected, in: finished
        ).first?.writtenWordIndex
    }

    @Test("A filler removed before the word moves it one word earlier")
    func fillerBefore() {
        #expect(landing("Tarvok", at: 4..<5, from: "um send it to Tarvok", in: "Send it to Tarvok") == 3)
    }

    @Test("The discarded half of a self-correction moves it back by what was dropped")
    func selfCorrectionBefore() {
        #expect(
            landing(
                "Tarvok", at: 6..<7, from: "send it to Bob no to Tarvok", in: "Send it to Tarvok.")
                == 3)
    }

    @Test("A spoken number written as a numeral moves it back by the words merged")
    func numeralBefore() {
        #expect(
            landing("Tarvok", at: 3..<4, from: "twenty five for Tarvok", in: "25 for Tarvok") == 2)
    }

    @Test("A snippet expanded into several words moves it forward")
    func snippetBefore() {
        #expect(
            landing(
                "Tarvok", at: 2..<3, from: "my sign Tarvok", in: "Kind regards, Sam Tarvok")
                == 3)
    }

    @Test("Several written words are found together, and a later change is shifted past an earlier one")
    func severalWords() {
        let located = DictationCorrection.locating(
            [
                correction(heard: "pay sheet", wrote: "PaymentSheet", at: 1..<3),
                correction(heard: "tarvock", wrote: "Tar Vok", at: 5..<6),
            ],
            from: "uh PaymentSheet for the Tar Vok", in: "PaymentSheet for the Tar Vok")
        #expect(located.map(\.writtenWordIndex) == [0, 3])
    }

    @Test("A word the tidier rewrote is not located")
    func rewrittenWord() {
        #expect(landing("Tarvok", at: 3..<4, from: "send it to Tarvok", in: "Send it to Travok") == nil)
    }
}
