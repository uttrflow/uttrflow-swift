import Testing
import UttrflowCore

@testable import UttrflowAI

/// A transcription whose words are timed, with the given silence after each position in `pauses`.
private func timed(_ text: String, pauses: [Int: Duration]) -> Transcription {
    var clock = Duration.zero
    let words = text.split(separator: " ").enumerated().map { index, word in
        let start = clock
        clock += .milliseconds(300)
        let end = clock
        clock += pauses[index] ?? .milliseconds(100)
        return TranscribedWord(text: String(word), confidence: 1, start: start, end: end)
    }
    return Transcription(
        text: text, segments: [TranscriptionSegment(text: text, start: .zero, end: clock, words: words)])
}

private func ms(_ value: Int) -> Duration { .milliseconds(value) }

private func punctuated(_ text: String, pauses: [Int: Duration]) -> String {
    PauseStopPass().apply(Draft(transcription: timed(text, pauses: pauses))).text
}

@Suite("PauseStopPass commas")
struct PauseCommaTests {
    @Test(
        "puts a comma after sorry, thanks or done where the speaker paused",
        arguments: [
            (
                "rollback done error rate is back to normal", [1: ms(450)],
                "rollback done, error rate is back to normal"
            ),
            ("sorry was busy will call in a bit", [0: ms(400)], "sorry, was busy will call in a bit"),
            ("thanks marcy i'll pick up the keys", [0: ms(350)], "thanks, marcy i'll pick up the keys"),
        ])
    func commaAtPause(text: String, pauses: [Int: Duration], expected: String) {
        #expect(punctuated(text, pauses: pauses) == expected)
    }

    @Test("a comma head and a sentence pause give the comma, then the stop where the clause ends")
    func headThenStop() {
        #expect(
            punctuated(
                "sorry was busy will call in a bit",
                pauses: [0: .milliseconds(400), 2: .seconds(1)])
                == "sorry, was busy. will call in a bit")
    }

    @Test(
        "leaves the words alone without a pause long enough",
        arguments: [
            ("rollback done error rate is back to normal", [Int: Duration]()),
            ("rollback done error rate is back to normal", [1: Duration.milliseconds(150)]),
            ("sorry was busy will call in a bit", [Int: Duration]()),
        ])
    func noPauseNoComma(text: String, pauses: [Int: Duration]) {
        #expect(punctuated(text, pauses: pauses) == text)
    }

    @Test("a pause after any other word places no comma")
    func otherWordsKeepTheirPause() {
        let text = "yesterday i finished the login screen refactor"
        #expect(punctuated(text, pauses: [0: .milliseconds(450), 3: .milliseconds(450)]) == text)
    }

    @Test("a head that carries on into its phrase takes no comma")
    func headCarriesOn() {
        #expect(
            punctuated("thanks for the lift", pauses: [0: .milliseconds(450)]) == "thanks for the lift")
        #expect(
            punctuated("i am done with the report", pauses: [2: .milliseconds(450)])
                == "i am done with the report")
    }

    @Test("a head already carrying a mark, or ending the text, is left alone")
    func markedOrLast() {
        #expect(
            punctuated("sorry, was busy", pauses: [0: .milliseconds(450)]) == "sorry, was busy")
        #expect(punctuated("all done", pauses: [1: .milliseconds(450)]) == "all done")
    }

    @Test("a head in code takes no comma")
    func notInCode() {
        let draft = Draft(
            transcription: timed("sorry was busy", pauses: [0: .milliseconds(450)]))
        #expect(PauseStopPass(destination: .codeEditor).apply(draft).text == "sorry was busy")
    }
}
