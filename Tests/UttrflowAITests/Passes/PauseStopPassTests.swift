import Testing
import UttrflowCore

@testable import UttrflowAI

/// A transcription whose words are timed, with a one-second silence after each position in `pausedAfter`.
private func timed(_ text: String, pausedAfter: [Int]) -> Transcription {
    var clock = Duration.zero
    let words = text.split(separator: " ").enumerated().map { index, word in
        let start = clock
        clock += .milliseconds(300)
        let end = clock
        clock += pausedAfter.contains(index) ? .seconds(1) : .milliseconds(100)
        return TranscribedWord(text: String(word), confidence: 1, start: start, end: end)
    }
    return Transcription(
        text: text, segments: [TranscriptionSegment(text: text, start: .zero, end: clock, words: words)])
}

private func stopped(_ text: String, pausedAfter: [Int], to destination: Destination = .plain) -> String {
    PauseStopPass(destination: destination).apply(Draft(transcription: timed(text, pausedAfter: pausedAfter)))
        .text
}

@Suite("PauseStopPass")
struct PauseStopPassTests {
    @Test(
        "ends a sentence at a sentence-length pause",
        arguments: [
            (
                "the kettle boiled the tea is ready come and get it", [2, 6],
                "the kettle boiled. the tea is ready. come and get it"
            ),
            (
                "the meeting moved to thursday please update your calendar", [4],
                "the meeting moved to thursday. please update your calendar"
            ),
        ])
    func endsAtPause(text: String, pausedAfter: [Int], expected: String) {
        #expect(stopped(text, pausedAfter: pausedAfter) == expected)
    }

    @Test(
        "keeps the sentence going where the words show it carries on",
        arguments: [
            ("we need to finish the report by friday", [4]),
            ("i stayed home because it was raining", [2]),
            ("she put the keys on the shelf by the door", [5]),
        ])
    func runsOn(text: String, pausedAfter: [Int]) {
        #expect(stopped(text, pausedAfter: pausedAfter) == text)
    }

    @Test("leaves a pause shorter than a piece boundary alone")
    func shortPause() {
        let text = "the kettle boiled the tea is ready"
        let draft = Draft(transcription: timed(text, pausedAfter: []))
        #expect(PauseStopPass().apply(draft).text == text)
    }

    @Test("leaves untimed words alone")
    func untimed() {
        #expect(
            cleaned("the kettle boiled the tea is ready", by: PauseStopPass())
                == "the kettle boiled the tea is ready")
    }

    @Test("leaves a word that already carries a mark alone")
    func alreadyMarked() {
        #expect(
            stopped("the kettle boiled, the tea is ready", pausedAfter: [2])
                == "the kettle boiled, the tea is ready")
    }

    @Test(
        "writes no stop into code", arguments: [Destination.codeEditor, .terminal, .sqlEditor, .spreadsheet])
    func notInCode(destination: Destination) {
        let text = "the kettle boiled the tea is ready"
        #expect(stopped(text, pausedAfter: [2], to: destination) == text)
    }

    @Test("reads the pause across a filler the pipeline took out")
    func acrossRemovedFiller() {
        let transcription = timed("the kettle boiled um the tea is ready", pausedAfter: [3])
        #expect(
            CleaningPipeline.standard.run(Draft(transcription: transcription)).text
                == "The kettle boiled. The tea is ready.")
    }
}
