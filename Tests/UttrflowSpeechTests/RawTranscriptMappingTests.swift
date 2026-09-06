// Tests mapping raw recogniser output into a Transcription.
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

@Suite("Raw transcript mapping")
struct RawTranscriptMappingTests {
    @Test("carries the recognised text and the audio's length")
    func basicMapping() {
        let raw = RawTranscript(text: "hello there")
        let mapped = raw.transcription(audioDuration: .seconds(3))

        #expect(mapped.text == "hello there")
        #expect(mapped.audioDuration == .seconds(3))
    }

    /// Whisper emits these routinely on quiet recordings, and typing them would be worse than nothing.
    @Test(
        "strips the markers recognisers emit for things that are not speech",
        arguments: [
            ("[BLANK_AUDIO]", ""),
            ("(silence)", ""),
            ("[ Music ]", ""),
            ("[BLANK_AUDIO] hello there", "hello there"),
            ("hello [inaudible] there", "hello there"),
            ("(upbeat music) let's begin", "let's begin"),
        ]
    )
    func stripsNonSpeechMarkers(input: String, expected: String) {
        #expect(RawTranscript(text: input).transcription(audioDuration: .zero).text == expected)
    }

    /// A bracket the user actually dictated must survive; only whole markers go.
    @Test(
        "keeps brackets that are part of what was said",
        arguments: [
            "call get_user(id) first",  // attached to a word
            "the array is [1, 2, 3]",  // not only letters
            "see figure (2) above",  // not only letters
            "handler(request)",  // attached, at the end
            "(this is a longer spoken aside)",  // more than three words
            "def main(argv):",  // attached, followed by punctuation
        ]
    )
    func keepsMeaningfulBrackets(input: String) {
        #expect(RawTranscript(text: input).transcription(audioDuration: .zero).text == input)
    }

    @Test("strips a marker that ends the sentence, keeping the punctuation after it")
    func markerBeforePunctuation() {
        #expect(
            RawTranscript(text: "that is all [inaudible].")
                .transcription(audioDuration: .zero).text == "that is all ."
        )
    }

    @Test("leaves an unclosed bracket alone rather than eating the rest of the line")
    func unclosedBracket() {
        let text = "hello [there and onwards"
        #expect(RawTranscript(text: text).transcription(audioDuration: .zero).text == text)
    }

    @Test("collapses the whitespace that stripping leaves behind")
    func tidiesWhitespace() {
        let raw = RawTranscript(text: "  hello   [noise]   there  ")
        #expect(raw.transcription(audioDuration: .zero).text == "hello there")
    }

    @Test("normalises whatever the recogniser calls the language")
    func normalisesLanguage() {
        let raw = RawTranscript(text: "hi", languageIdentifier: "en-US", languageProbability: 0.9)
        let language = raw.transcription(audioDuration: .zero).detectedLanguage

        #expect(language?.code == .english)
        #expect(language?.confidence == 0.9)
    }

    /// Encoding "did not report" as zero would read as "certainly wrong" to a router.
    @Test("reports no confidence when the recogniser gives none")
    func absentConfidence() {
        let raw = RawTranscript(text: "hi", languageIdentifier: "hi")
        #expect(raw.transcription(audioDuration: .zero).detectedLanguage?.confidence == nil)
    }

    @Test("reports no language when the recogniser names none, or names nonsense")
    func missingLanguage() {
        #expect(RawTranscript(text: "hi").transcription(audioDuration: .zero).detectedLanguage == nil)
        #expect(
            RawTranscript(text: "hi", languageIdentifier: "123")
                .transcription(audioDuration: .zero).detectedLanguage == nil
        )
    }

    @Test("maps segments, cleaning each one the same way")
    func mapsSegments() {
        let raw = RawTranscript(
            text: "hello there",
            segments: [
                RawSegment(text: "hello", start: 0, end: 1.5),
                RawSegment(text: "[noise] there", start: 1.5, end: 2),
            ]
        )
        let segments = raw.transcription(audioDuration: .seconds(2)).segments

        #expect(segments.count == 2)
        #expect(segments[0] == TranscriptionSegment(text: "hello", start: .zero, end: .milliseconds(1_500)))
        #expect(segments[1].text == "there")
    }

    @Test("reports a transcript of nothing but markers as blank")
    func markersOnlyIsBlank() {
        #expect(RawTranscript(text: "[BLANK_AUDIO]").transcription(audioDuration: .zero).isBlank)
    }
}
