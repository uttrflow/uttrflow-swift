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

    /// A bracket holding words no recogniser writes for non-speech is the speaker's own aside, whatever its shape.
    @Test(
        "keeps a bracketed aside the speaker dictated",
        arguments: [
            "the API (version two) is ready",
            "we shipped it (finally) last night",
            "call the office (not the mobile) tomorrow",
            "the release (v3) is out",
        ])
    func keepsSpokenParentheticals(text: String) {
        #expect(RawTranscript(text: text).transcription(audioDuration: .zero).text == text)
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

/// #179: a marker removed from the text but not from the words costs the piece its confidences.
@Suite("A marker and the word list")
struct MarkerWordListTests {
    @Test("leaves the recogniser's confidences usable when a marker was removed")
    func confidencesSurviveAMarker() {
        let raw = RawTranscript(
            text: "[BLANK_AUDIO] the crash is in payment sheet",
            segments: [
                RawSegment(
                    text: "[BLANK_AUDIO] the crash is in payment sheet", start: 0, end: 2,
                    words: [
                        RawWord(text: " [BLANK_AUDIO]", start: 0.0, end: 0.2, probability: 0.9),
                        RawWord(text: " the", start: 0.2, end: 0.4, probability: 0.99),
                        RawWord(text: " crash", start: 0.4, end: 0.6000000000000001, probability: 0.99),
                        RawWord(text: " is", start: 0.6000000000000001, end: 0.8, probability: 0.99),
                        RawWord(text: " in", start: 0.8, end: 1.0, probability: 0.99),
                        RawWord(text: " payment", start: 1.0, end: 1.2, probability: 0.3),
                        RawWord(text: " sheet", start: 1.2, end: 1.4, probability: 0.3),
                    ])
            ])

        let draft = Draft(transcription: raw.transcription(audioDuration: .seconds(2)))

        #expect(draft.confidencesAreReal)
        #expect(draft.text == "the crash is in payment sheet")
    }

    /// "not reported" and "reported nothing" are different facts: see Transcription.swift's own warning.
    @Test("does not read an absent word list as full confidence")
    func absentWordsAreNotConfidence() {
        let raw = RawTranscript(
            text: "the crash is in payment sheet",
            segments: [
                RawSegment(text: "the crash is in payment sheet", start: 0, end: 2, words: nil)
            ])

        let draft = Draft(transcription: raw.transcription(audioDuration: .seconds(2)))

        #expect(!draft.confidencesAreReal)
        #expect(draft.text == "the crash is in payment sheet")
    }

    /// The other half of the rule: a bracket the speaker dictated has to survive in both representations.
    @Test("keeps a dictated aside in the words as well as the text")
    func keepsADictatedAside() {
        let raw = RawTranscript(
            text: "the API (version two) is ready",
            segments: [
                RawSegment(
                    text: "the API (version two) is ready", start: 0, end: 2,
                    words: [
                        RawWord(text: " the", start: 0, end: 0.2, probability: 0.99),
                        RawWord(text: " API", start: 0.2, end: 0.4, probability: 0.99),
                        RawWord(text: " (version", start: 0.4, end: 0.6, probability: 0.9),
                        RawWord(text: " two)", start: 0.6, end: 0.8, probability: 0.9),
                        RawWord(text: " is", start: 0.8, end: 1.0, probability: 0.99),
                        RawWord(text: " ready", start: 1.0, end: 1.2, probability: 0.99),
                    ])
            ])

        let draft = Draft(transcription: raw.transcription(audioDuration: .seconds(2)))

        #expect(draft.confidencesAreReal)
        #expect(draft.text == "the API (version two) is ready")
    }
}
