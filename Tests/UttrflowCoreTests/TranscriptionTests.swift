import Testing

@testable import UttrflowCore

@Suite("Transcription")
struct TranscriptionTests {
    @Test("defaults to no language, no segments and no duration")
    func minimalInitialiser() {
        let transcription = Transcription(text: "hello")

        #expect(transcription.text == "hello")
        #expect(transcription.detectedLanguage == nil)
        #expect(transcription.segments.isEmpty)
        #expect(transcription.audioDuration == .zero)
    }

    @Test(
        "treats whitespace-only recognition as blank so silence is not inserted",
        arguments: ["", " ", "\n", "\t  \n"]
    )
    func blankDetection(text: String) {
        #expect(Transcription(text: text).isBlank)
    }

    @Test("treats any real word as not blank")
    func nonBlankDetection() {
        #expect(!Transcription(text: " hello ").isBlank)
    }

    @Test("carries timed segments when the engine supplies them")
    func segments() {
        let segment = TranscriptionSegment(text: "hello", start: .zero, end: .seconds(1))
        let transcription = Transcription(text: "hello", segments: [segment])

        #expect(transcription.segments == [segment])
        #expect(segment.start == .zero)
        #expect(segment.end == .seconds(1))
    }

    @Test("compares equal only when every field matches")
    func equatable() {
        let base = Transcription(text: "hi", audioDuration: .seconds(1))

        #expect(base == Transcription(text: "hi", audioDuration: .seconds(1)))
        #expect(base != Transcription(text: "hi", audioDuration: .seconds(2)))
        #expect(base != Transcription(text: "bye", audioDuration: .seconds(1)))
    }
}
