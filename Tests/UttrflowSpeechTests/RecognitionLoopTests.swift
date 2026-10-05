// Tests that a piece the recogniser looped is written once, and a sentence really said twice is kept twice.
import Testing

import UttrflowEval
@testable import UttrflowCore
@testable import UttrflowSpeech

@Suite("A piece the recogniser looped")
struct RecognitionLoopTests {
    private let sentence = "Kal meeting hai, please slides ready rakhna."

    private func heard(_ text: String, seconds: Double) -> Transcription {
        Transcription(
            text: text,
            segments: [
                TranscriptionSegment(
                    text: text, start: .zero, end: .seconds(seconds),
                    words: text.split(separator: " ").map {
                        TranscribedWord(text: String($0), confidence: 0.9)
                    })
            ],
            audioDuration: .seconds(seconds))
    }

    @Test("a quoted sentence written twice in under three seconds is written once, without the quotes")
    func quotedLoopIsWrittenOnce() {
        let looped = "\"\(sentence)\" \"\(sentence)\""

        let undone = RecognitionLoop.undone(heard(looped, seconds: 2.76), speechDuration: .seconds(2.76))

        #expect(undone.text == sentence)
        #expect(undone.segments.map(\.text) == [sentence])
        #expect(undone.segments.first?.words.map(\.text) == sentence.split(separator: " ").map(String.init))
    }

    @Test("a loop whose second copy was heard slightly differently is still written once")
    func nearCopyIsWrittenOnce() {
        let looped =
            "KAL MEETING HAI PLEASE SLIDES READY RAKHNA KAL MEETING HAYE PLEASE SLIDES READY RAKHNA"

        let undone = RecognitionLoop.undone(heard(looped, seconds: 2.76), speechDuration: .seconds(2.76))

        #expect(undone.text == "KAL MEETING HAI PLEASE SLIDES READY RAKHNA")
    }

    @Test("three near-identical copies are written once")
    func threeCopiesAreWrittenOnce() {
        let looped =
            "Please send the report today. Please send the report today. Please send that report today."

        let undone = RecognitionLoop.undone(heard(looped, seconds: 1.5), speechDuration: .seconds(1.5))

        #expect(undone.text == "Please send the report today.")
    }

    @Test("four copies at a fast rate are written once")
    func fourFastCopiesAreWrittenOnce() {
        let looped = String(repeating: "Send the report. ", count: 4).trimmingCharacters(in: .whitespaces)

        let undone = RecognitionLoop.undone(heard(looped, seconds: 2), speechDuration: .seconds(2))

        #expect(undone.text == "Send the report.")
    }

    @Test("six copies of a phrase are written once")
    func sixCopiesAreWrittenOnce() {
        let looped = String(repeating: "Send the report. ", count: 6).trimmingCharacters(in: .whitespaces)

        let undone = RecognitionLoop.undone(heard(looped, seconds: 3), speechDuration: .seconds(3))

        #expect(undone.text == "Send the report.")
    }

    @Test("a trailing partial copy is dropped after three copies are proven")
    func trailingPartialCopyIsDropped() {
        let looped = "Send the report. Send the report. Send the report. Send the"

        let undone = RecognitionLoop.undone(heard(looped, seconds: 1.5), speechDuration: .seconds(1.5))

        #expect(undone.text == "Send the report.")
    }

    @Test("quotes around a repeated run are removed after it is collapsed")
    func wrappingQuotesAroundRunAreRemoved() {
        let looped = "\"Send the report. Send the report. Send the report.\""

        let undone = RecognitionLoop.undone(heard(looped, seconds: 1.5), speechDuration: .seconds(1.5))

        #expect(undone.text == "Send the report.")
    }

    @Test("unrelated words after three copies are kept")
    func unrelatedTrailingWordsAreKept() {
        let looped = "Send the report. Send the report. Send the report. Call me"

        let undone = RecognitionLoop.undone(heard(looped, seconds: 1.5), speechDuration: .seconds(1.5))

        #expect(undone.text == "Send the report. Call me")
    }

    @Test("four copies below the speech-rate threshold are kept")
    func slowFourCopiesAreKept() {
        let looped = "Send the report. Send the report. Send the report. Send the report."

        let undone = RecognitionLoop.undone(heard(looped, seconds: 3), speechDuration: .seconds(3))

        #expect(undone.text == looped)
    }

    @Test("six repetitions of a two-word phrase are kept")
    func sixShortCopiesAreKept() {
        let looped = String(repeating: "and then ", count: 6).trimmingCharacters(in: .whitespaces)

        let undone = RecognitionLoop.undone(heard(looped, seconds: 1.5), speechDuration: .seconds(1.5))

        #expect(undone.text == looped)
    }

    @Test("corpus passages at the recorded natural rate are not shortened")
    func corpusPassagesAreNotShortenedAtNaturalRate() {
        for passage in TranscriptionCorpus.all {
            for form in passage.forms {
                let wordCount = form.split(whereSeparator: \.isWhitespace).count
                let duration = Duration.seconds(Double(wordCount) / 2.5)
                let transcription = Transcription(text: form)

                let undone = RecognitionLoop.undone(transcription, speechDuration: duration)

                #expect(undone.text == form, "\(passage.id) was shortened")
            }
        }
    }

    @Test("a sentence said twice in a piece long enough to hold both is kept twice")
    func realRepeatIsKept() {
        let twice = "I will send the file today. I will send the file today."

        let undone = RecognitionLoop.undone(heard(twice, seconds: 6), speechDuration: .seconds(6))

        #expect(undone.text == twice)
    }

    @Test("two different sentences spoken fast are left alone")
    func differentHalvesAreKept() {
        let fast = "send the file today and call me back tonight"

        let undone = RecognitionLoop.undone(heard(fast, seconds: 1.5), speechDuration: .seconds(1.5))

        #expect(undone.text == fast)
    }

    @Test("a partial decode already looping past what the window holds stops decoding")
    func partialLoopStops() {
        let partial = "send the file. send the file. send the file. send"

        #expect(RecognitionLoop.isLooping(partial, within: .seconds(2)))
    }

    @Test("a phrase said three times in a window long enough to hold it keeps decoding")
    func spokenRepeatKeepsDecoding() {
        let partial = "send the file. send the file. send the file."

        #expect(!RecognitionLoop.isLooping(partial, within: .seconds(30)))
    }

    @Test("a partial decode of different words keeps decoding however fast")
    func differentWordsKeepDecoding() {
        #expect(!RecognitionLoop.isLooping("send the file today and call me back", within: .seconds(1)))
    }

    @Test("a short word said twice quickly is ordinary speech")
    func shortRepeatIsKept() {
        let undone = RecognitionLoop.undone(heard("no no", seconds: 0.3), speechDuration: .seconds(0.3))

        #expect(undone.text == "no no")
    }

    @Test(
        "quotes are taken off only when they wrap the whole piece and no other quote is there",
        arguments: [
            ("\"Ship it today.\"", "Ship it today."),
            ("\u{201C}Ship it today.\u{201D}", "Ship it today."),
            ("\"Ship it\" today.", "\"Ship it\" today."),
            ("He said \"ship it\" and \"test it\".", "He said \"ship it\" and \"test it\"."),
        ])
    func wrappingQuotesOnly(text: String, expected: String) {
        let undone = RecognitionLoop.undone(heard(text, seconds: 3), speechDuration: .seconds(3))

        #expect(undone.text == expected)
    }
}
