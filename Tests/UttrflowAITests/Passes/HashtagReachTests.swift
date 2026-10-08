import Testing
import UttrflowCore

@testable import UttrflowAI

/// A transcription timed at 100 ms between words, with a gap of `gap` after each position in `pausedAfter`.
private func timed(_ text: String, pausedAfter: [Int], gap: Duration = .milliseconds(400)) -> Transcription {
    var clock = Duration.zero
    let words = text.split(separator: " ").enumerated().map { index, word in
        let start = clock
        clock += .milliseconds(250)
        let end = clock
        clock += pausedAfter.contains(index) ? gap : .milliseconds(100)
        return TranscribedWord(text: String(word), confidence: 1, start: start, end: end)
    }
    return Transcription(
        text: text, segments: [TranscriptionSegment(text: text, start: .zero, end: clock, words: words)])
}

private func tagged(_ text: String, pausedAfter: [Int], to destination: Destination = .messaging) -> String {
    SpokenCasingPass(destination: destination)
        .apply(Draft(transcription: timed(text, pausedAfter: pausedAfter))).text
}

@Suite("A spoken hashtag joins the words up to the next pause, clause mark or end of the piece")
struct HashtagReachTests {
    @Test(
        "joins one to four words, ended by what the speaker did",
        arguments: [
            ("we are live hashtag launch day and thanks", [5], "we are live #launchday and thanks"),
            (
                "we are live hashtag spring launch and a big thank you", [5],
                "we are live #springlaunch and a big thank you"
            ),
            ("so proud hashtag teamwork", [], "so proud #teamwork"),
            ("so proud hashtag team work", [], "so proud #teamwork"),
            ("hashtag new music friday out now", [3], "#newmusicfriday out now"),
            ("hashtag throw back to the summer", [2], "#throwback to the summer"),
            ("loved it hashtag best day ever", [], "loved it #bestdayever"),
            ("loved it hashtag best day ever see you soon", [5], "loved it #bestdayever see you soon"),
            ("hashtag one hashtag two", [1], "#one #two"),
            ("ran it hashtag half marathon hashtag first race", [4], "ran it #halfmarathon #firstrace"),
            ("join us hashtag open source summit next week", [5], "join us #opensourcesummit next week"),
            ("big news hashtag launch, more soon", [], "big news #launch, more soon"),
            ("big news hashtag Spring Launch", [], "big news #springlaunch"),
            ("hashtag a b c d", [], "#abcd"),
        ])
    func joins(text: String, pausedAfter: [Int], expected: String) {
        #expect(tagged(text, pausedAfter: pausedAfter) == expected)
    }

    @Test("ends a tag at a small word when the words carry no timings")
    func untimedTagEndsAtASmallWord() {
        let draft = Draft(text: "we are live hashtag spring launch and thanks to the team")
        #expect(
            SpokenCasingPass(destination: .messaging).apply(draft).text
                == "we are live #springlaunch and thanks to the team")
    }

    @Test(
        "leaves the word alone where it names a tag or covers nothing",
        arguments: [
            ("the hashtag was trending", [Int]()),
            ("a hashtag for the event", []),
            ("their hashtag is clever", []),
            ("which hashtag did you use", []),
            ("I posted it with no hashtag", []),
            ("the hashtag", []),
            ("ends with hashtag", []),
        ])
    func abstains(text: String, pausedAfter: [Int]) {
        #expect(tagged(text, pausedAfter: pausedAfter) == text)
    }

    @Test("a pause shorter than the tag pause does not end the tag")
    func shortPause() {
        let draft = Draft(
            transcription: timed("hashtag spring launch now", pausedAfter: [1], gap: .milliseconds(250)))
        #expect(SpokenCasingPass(destination: .messaging).apply(draft).text == "#springlaunchnow")
    }

    @Test("a pause after the word hashtag itself does not end an empty tag")
    func pauseAfterCue() {
        #expect(tagged("hashtag spring launch now", pausedAfter: [0, 2]) == "#springlaunch now")
    }

    @Test("a code editor keeps the word, since a hash there is code")
    func codeEditor() {
        #expect(tagged("hashtag spring", pausedAfter: [], to: .codeEditor) == "hashtag spring")
    }
}
