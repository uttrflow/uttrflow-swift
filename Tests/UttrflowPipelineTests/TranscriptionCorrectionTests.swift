import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

/// Corrected words become settled, keeping the heard score, while untouched words keep theirs.
@Suite("Transcription corrections keep word confidences")
struct TranscriptionCorrectionTests {
    @Test("sorts reversed corrections and preserves every untouched confidence")
    func reversedCorrectionsKeepConfidences() {
        let heard = Self.transcription("alpha beta gamma delta epsilon zeta eta theta")
        let corrected = CorrectedTranscript(
            text: "alpha BetaName gamma delta epsilon ZetaName eta theta",
            corrections: [
                Self.correction("zeta", wrote: "ZetaName", over: 5..<6),
                Self.correction("beta", wrote: "BetaName", over: 1..<2),
            ])

        let result = heard.saying(corrected)
        let draft = Draft(transcription: result)

        #expect(result.text == corrected.text)
        #expect(draft.confidencesAreReal)
        #expect(
            draft.words.map(\.text) == [
                "alpha", "BetaName", "gamma", "delta", "epsilon", "ZetaName", "eta", "theta",
            ])
        #expect(draft.words.map(\.confidence) == [0.91, 0.2, 0.86, 0.31, 0.77, 0.2, 0.68, 0.21])
        #expect(draft.words.map(\.settled) == [false, true, false, false, false, true, false, false])
    }

    @Test("an override is never written as confidence 1, whatever it replaced", .bug(id: 4519))
    func overrideNeverBecomesCertain() {
        let heard = Self.transcription("alpha beta gamma")
        let corrected = CorrectedTranscript(
            text: "alpha Beta Name gamma",
            corrections: [Self.correction("beta", wrote: "Beta Name", over: 1..<2)])

        let words = heard.saying(corrected).segments.flatMap(\.words)

        #expect(words.filter(\.settled).map(\.text) == ["Beta", "Name"])
        #expect(words.filter(\.settled).allSatisfy { $0.confidence == 0.2 })
        #expect(!words.contains { $0.confidence == 1 })
    }

    @Test("falls back to plain text when correction ranges overlap")
    func overlappingRangesUsePlainTextFallback() {
        let heard = Self.transcription("one two three four")
        let corrected = CorrectedTranscript(
            text: "one TWO THREE four",
            corrections: [
                Self.correction("two three", wrote: "TWO THREE", over: 1..<3),
                Self.correction("three", wrote: "THREE", over: 2..<3),
            ])

        #expect(heard.saying(corrected) == heard.saying(corrected.text))
    }

    @Test("falls back to plain text when a correction range runs past the words")
    func outOfBoundsRangeUsesPlainTextFallback() {
        let heard = Self.transcription("one two three four")
        let corrected = CorrectedTranscript(
            text: "one TWO three four",
            corrections: [Self.correction("two", wrote: "TWO", over: 1..<5)])

        #expect(heard.saying(corrected) == heard.saying(corrected.text))
    }

    @Test("falls back to plain text when corrected text does not match the rebuilt words")
    func mismatchedSpellingUsesPlainTextFallback() {
        let heard = Self.transcription("one two three four")
        let corrected = CorrectedTranscript(
            text: "one TWO something four",
            corrections: [Self.correction("two", wrote: "TWO", over: 1..<2)])

        #expect(heard.saying(corrected) == heard.saying(corrected.text))
    }

    private static func transcription(_ text: String) -> Transcription {
        let scores = [0.91, 0.42, 0.86, 0.31, 0.77, 0.54, 0.68, 0.21]
        let words = text.split(whereSeparator: \.isWhitespace).enumerated().map { index, word in
            TranscribedWord(text: String(word), confidence: scores[index])
        }
        return Transcription(
            text: text,
            segments: [TranscriptionSegment(text: text, start: .zero, end: .seconds(1), words: words)],
            audioDuration: .seconds(1))
    }

    private static func correction(
        _ heard: String, wrote: String, over range: Range<Int>
    ) -> DictationCorrection {
        DictationCorrection(
            heard: heard, wrote: wrote, wordRange: range, entryID: UUID(), reason: .unknown("test"),
            heardConfidence: 0.2)
    }
}
