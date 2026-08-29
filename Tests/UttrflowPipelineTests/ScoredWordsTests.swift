import UttrflowCore
import Testing

@testable import UttrflowPipeline

/// Turning what the recogniser scored into what the correction engine can judge.
///
/// The whole feature rests on this being right: correction only touches a word the
/// recogniser was unsure about, so a wrong score here either shields a bad word or
/// exposes a good one.
@Suite("What the recogniser was sure of")
struct ScoredWordsTests {
    private func transcription(_ text: String, words: [TranscribedWord]) -> Transcription {
        Transcription(
            text: text,
            segments: [
                TranscriptionSegment(text: text, start: .zero, end: .seconds(1), words: words)
            ])
    }

    @Test("scores each spoken word from what the recogniser reported")
    func scoresWords() {
        let scored = transcription(
            "send it to Nikhil",
            words: [
                TranscribedWord(text: "send", confidence: 0.99),
                TranscribedWord(text: "it", confidence: 0.98),
                TranscribedWord(text: "to", confidence: 0.97),
                TranscribedWord(text: "Nikhil", confidence: 0.41),
            ]
        ).scoredWords

        #expect(scored?.map(\.text) == ["send", "it", "to", "Nikhil"])
        #expect(scored?.last?.confidence == 0.41)
    }

    /// `nil` means nobody measured, and it must never be read as "everything is certain".
    /// Apple's recogniser reports no per-word figure, so a build using it lands here.
    @Test("declines to judge when nothing was scored")
    func nothingScored() {
        #expect(transcription("send it to Nikhil", words: []).scoredWords == nil)
        #expect(transcription("", words: []).scoredWords == nil)
    }

    /// A word the recogniser never scored is left alone rather than guessed at. One is
    /// "no reason to doubt it", which keeps it out of reach of the first condition.
    @Test("leaves an unscored word beyond suspicion rather than guessing")
    func unscoredWord() {
        let scored = transcription(
            "send it onwards",
            words: [TranscribedWord(text: "send", confidence: 0.4)]
        ).scoredWords

        #expect(scored?.first?.confidence == 0.4)
        #expect(scored?.last?.confidence == 1)
    }

    /// The doubtful reading is the one worth acting on. Taking the confident one would
    /// hide exactly the word correction exists to catch.
    @Test("takes the lowest score when a word is heard more than once")
    func repeatedWord() {
        let scored = transcription(
            "Nikhil and Nikhil",
            words: [
                TranscribedWord(text: "Nikhil", confidence: 0.95),
                TranscribedWord(text: "and", confidence: 0.99),
                TranscribedWord(text: "Nikhil", confidence: 0.32),
            ]
        ).scoredWords

        #expect(scored?.first?.confidence == 0.32)
        #expect(scored?.last?.confidence == 0.32)
    }

    /// The tidier has not run yet, but a recogniser punctuates too — and a word wearing
    /// a comma must still find its own score.
    @Test("matches a word through the punctuation attached to it")
    func punctuation() {
        let scored = transcription(
            "Thanks, Nikhil.",
            words: [
                TranscribedWord(text: "Thanks", confidence: 0.99),
                TranscribedWord(text: "Nikhil", confidence: 0.38),
            ]
        ).scoredWords

        #expect(scored?.count == 2)
        #expect(scored?.last?.confidence == 0.38, "the full stop must not hide the score")
    }

    /// Case is the recogniser's guess, not the speaker's, so it cannot decide whether a
    /// word gets its own score.
    @Test("matches regardless of how the recogniser capitalised it")
    func caseInsensitive() {
        let scored = transcription(
            "Send it",
            words: [
                TranscribedWord(text: "send", confidence: 0.44),
                TranscribedWord(text: "IT", confidence: 0.5),
            ]
        ).scoredWords

        #expect(scored?.map(\.confidence) == [0.44, 0.5])
    }

    /// One entry per spoken word, in order — that is what a correction's range indexes,
    /// and a mismatch would put the replacement on the wrong word.
    @Test("returns one score per spoken word, in order")
    func onePerWord() {
        let text = "one two three four five"
        let scored = transcription(
            text, words: [TranscribedWord(text: "three", confidence: 0.2)]
        ).scoredWords

        #expect(scored?.count == text.split(separator: " ").count)
        #expect(scored?[2].confidence == 0.2)
    }
}
