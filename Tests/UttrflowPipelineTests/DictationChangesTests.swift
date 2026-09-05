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
        try await learner.recordUse(ofEntry: UUID())
        try await learner.recordUse(ofSnippets: [UUID()])
    }
}
