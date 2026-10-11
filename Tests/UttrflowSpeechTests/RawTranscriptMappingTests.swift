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

    @Test("keeps the decoder's judgement of each segment, and leaves an unjudged one unjudged")
    func carriesSegmentReliability() {
        let hot = SegmentReliability(
            temperature: 1, averageLogProbability: -0.93, noSpeechProbability: 0, compressionRatio: 0.95)
        let raw = RawTranscript(
            text: "painful hello",
            segments: [
                RawSegment(text: "painful", start: 0, end: 1, reliability: hot),
                RawSegment(text: "hello", start: 1, end: 2),
            ])
        let mapped = raw.transcription(audioDuration: .seconds(2))

        #expect(mapped.segments.map(\.reliability) == [hot, nil])
    }

    /// Whisper emits these routinely on quiet recordings, and typing them would be worse than nothing.
    @Test(
        "strips the markers recognisers emit for things that are not speech",
        arguments: [
            ("[BLANK_AUDIO]", ""),
            ("(silence)", ""),
            ("[ Music ]", ""),
            ("[Music]", ""),
            ("(applause)", ""),
            ("[SOUND]", ""),
            ("[BLANK_AUDIO] hello there", "hello there"),
            ("hello [inaudible] there", "hello there"),
            ("(upbeat music) let's begin", "let's begin"),
            ("*pain*", ""),
            ("*thud*", ""),
            ("*", "*"),
            ("**", "**"),
            ("a * b", "a * b"),
            ("*,", "*,"),
            ("*music*", ""),
            ("before *music* after", "before after"),
            ("*painful sound*", ""),
            ("review the ******* Kubernetes", "review the Kubernetes"),
            ("I really mean *really* this time", "I really mean *really* this time"),
            ("[door slams]", ""),
            ("(phone ringing)", ""),
            ("[clears throat]", ""),
            ("(sneezes)", ""),
            ("[inaudible 00:02]", ""),
            ("(speaking in foreign language)", ""),
            ("[ Background Conversations ]", ""),
            ("♪♪", ""),
            ("♪ la la la ♪", ""),
            ("[♪♪♪]", ""),
            (">> Hello there.", "Hello there."),
        ]
    )
    func stripsNonSpeechMarkers(input: String, expected: String) {
        #expect(RawTranscript(text: input).transcription(audioDuration: .zero).text == expected)
    }

    @Test("maps asterisks safely in the recogniser word list")
    func mapsAsterisksInWords() {
        let cases: [(String, String, [String])] = [
            ("*", "*", ["*"]),
            ("**", "**", ["**"]),
            ("a * b", "a * b", ["a", "*", "b"]),
            ("*,", "*,", ["*,"]),
            ("*music*", "", []),
            ("before *music* after", "before after", ["before", "after"]),
        ]

        for (text, expectedText, expectedWords) in cases {
            let words = text.split(separator: " ").map {
                RawWord(text: String($0), start: 0, end: 0.1, probability: 0.9)
            }
            let mapped = RawTranscript(
                text: text,
                segments: [RawSegment(text: text, start: 0, end: 0.1, words: words)]
            ).transcription(audioDuration: .milliseconds(100))

            #expect(mapped.text == expectedText)
            #expect(mapped.segments.first?.words.map(\.text) == expectedWords)
        }
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
            "(see the attached file)",
            "[TODO]",
            "[whirring]",
            "[door music]",
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

    @Test("maps marker-only non-speech descriptions to blank text")
    func markersOnlyIsBlank() {
        #expect(RawTranscript(text: "[BLANK_AUDIO]").transcription(audioDuration: .zero).isBlank)
        #expect(RawTranscript(text: "*pain*").transcription(audioDuration: .zero).isBlank)
    }

    @Test("removes issue 2372 caption, speaker, and music markers from the word list")
    func stripsCaptionMarkersFromWords() {
        let raw = RawTranscript(
            text: ">> ♪ la la la ♪ hello [phone ringing]",
            segments: [
                RawSegment(
                    text: ">> ♪ la la la ♪ hello [phone ringing]", start: 0, end: 2,
                    words: [
                        RawWord(text: " >>", start: 0, end: 0.1, probability: 0.99),
                        RawWord(text: " ♪", start: 0.1, end: 0.2, probability: 0.99),
                        RawWord(text: " la", start: 0.2, end: 0.3, probability: 0.99),
                        RawWord(text: " la", start: 0.3, end: 0.4, probability: 0.99),
                        RawWord(text: " la", start: 0.4, end: 0.5, probability: 0.99),
                        RawWord(text: " ♪", start: 0.5, end: 0.6, probability: 0.99),
                        RawWord(text: " hello", start: 0.6, end: 1, probability: 0.5),
                        RawWord(text: " [phone", start: 1, end: 1.1, probability: 0.99),
                        RawWord(text: " ringing]", start: 1.1, end: 1.2, probability: 0.99),
                    ])
            ])

        let segment = raw.transcription(audioDuration: .seconds(2)).segments[0]

        #expect(segment.text == "hello")
        let hello = TranscribedWord(text: "hello", confidence: 0.5, start: .seconds(0.6), end: .seconds(1))
        #expect(segment.words == [hello])
    }
}

/// #179: a marker removed from the text but not from the words costs the piece its confidences.
@Suite("A marker and the word list")
struct MarkerWordListTests {
    @Test("a non-speech-only transcript is blank in its text and word list")
    func nonSpeechOnlyIsBlank() {
        let raw = RawTranscript(
            text: "*thud*",
            segments: [
                RawSegment(
                    text: "*thud*", start: 0, end: 1,
                    words: [RawWord(text: " *thud*", start: 0, end: 0.5, probability: 0.1)])
            ])

        let transcription = raw.transcription(audioDuration: .seconds(1))

        #expect(transcription.isBlank)
        #expect(transcription.segments.first?.text == "")
        #expect(transcription.segments.first?.words.isEmpty == true)
    }

    @Test("removes a long asterisk span and keeps its surrounding words aligned")
    func removesAsteriskMarkerFromWordList() {
        let raw = RawTranscript(
            text: "review the ******* Kubernetes",
            segments: [
                RawSegment(
                    text: "review the ******* Kubernetes", start: 0, end: 2,
                    words: [
                        RawWord(text: " review", start: 0, end: 0.2, probability: 0.99),
                        RawWord(text: " the", start: 0.2, end: 0.4, probability: 0.99),
                        RawWord(text: " *******", start: 0.4, end: 0.6, probability: 0.1),
                        RawWord(text: " Kubernetes", start: 0.6, end: 1, probability: 0.99),
                    ])
            ])

        let transcription = raw.transcription(audioDuration: .seconds(2))
        let draft = Draft(transcription: transcription)

        #expect(transcription.text == "review the Kubernetes")
        #expect(transcription.segments.first?.text == "review the Kubernetes")
        #expect(transcription.segments.first?.words.map(\.text) == ["review", "the", "Kubernetes"])
        #expect(draft.confidencesAreReal)
    }

    @Test("removes bounded Whisper descriptions from text and words")
    func removesWhisperDescriptionsFromWords() {
        for marker in ["pain", "thud"] {
            let raw = RawTranscript(
                text: "before *\(marker)* after",
                segments: [
                    RawSegment(
                        text: "before *\(marker)* after", start: 0, end: 2,
                        words: [
                            RawWord(text: " before", start: 0, end: 0.3, probability: 0.9),
                            RawWord(text: " *\(marker)*", start: 0.3, end: 0.6, probability: 0.1),
                            RawWord(text: " after", start: 0.6, end: 1, probability: 0.9),
                        ])
                ])

            let transcription = raw.transcription(audioDuration: .seconds(2))

            #expect(transcription.text == "before after")
            #expect(transcription.segments.first?.text == "before after")
            #expect(transcription.segments.first?.words.map(\.text) == ["before", "after"])
        }
    }

    @Test("keeps punctuation attached to a removed Whisper description in the word list")
    func keepsPunctuationAfterWhisperDescription() {
        let raw = RawTranscript(
            text: "before *pain*. after",
            segments: [
                RawSegment(
                    text: "before *pain*. after", start: 0, end: 2,
                    words: [
                        RawWord(text: " before", start: 0, end: 0.3, probability: 0.9),
                        RawWord(text: " *pain*.", start: 0.3, end: 0.6, probability: 0.1),
                        RawWord(text: " after", start: 0.6, end: 1, probability: 0.9),
                    ])
            ])

        let segment = raw.transcription(audioDuration: .seconds(2)).segments.first

        #expect(segment?.text == "before . after")
        #expect(segment?.words.map(\.text) == ["before", ".", "after"])
    }

    @Test("refuses insertion when the mapped transcript contains only Whisper markers")
    func whisperMarkerOnlyIsBlank() {
        for marker in ["pain", "thud"] {
            let raw = RawTranscript(
                text: "*\(marker)*",
                segments: [
                    RawSegment(
                        text: "*\(marker)*", start: 0, end: 1,
                        words: [RawWord(text: " *\(marker)*", start: 0, end: 1, probability: 0.1)])
                ])

            let transcription = raw.transcription(audioDuration: .seconds(1))

            #expect(transcription.isBlank)
            #expect(transcription.segments.first?.text == "")
            #expect(transcription.segments.first?.words.isEmpty == true)
        }
    }

    @Test("keeps dictated asterisk emphasis in both text and words")
    func keepsAsteriskEmphasis() {
        let raw = RawTranscript(
            text: "I really mean *really* this time",
            segments: [
                RawSegment(
                    text: "I really mean *really* this time", start: 0, end: 2,
                    words: [
                        RawWord(text: " I", start: 0, end: 0.2, probability: 0.99),
                        RawWord(text: " really", start: 0.2, end: 0.4, probability: 0.99),
                        RawWord(text: " mean", start: 0.4, end: 0.6, probability: 0.99),
                        RawWord(text: " *really*", start: 0.6, end: 0.8, probability: 0.99),
                        RawWord(text: " this", start: 0.8, end: 1, probability: 0.99),
                        RawWord(text: " time", start: 1, end: 1.2, probability: 0.99),
                    ])
            ])

        let segment = raw.transcription(audioDuration: .seconds(2)).segments.first

        #expect(segment?.text == "I really mean *really* this time")
        #expect(segment?.words.map(\.text) == ["I", "really", "mean", "*really*", "this", "time"])
    }

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

    /// An empty word list reports nothing, so the segment keeps its own text as an absent one does.
    @Test("keeps a segment's text when its word list is empty")
    func emptyWordsKeepTheSegmentText() {
        let raw = RawTranscript(
            text: "hello there",
            segments: [RawSegment(text: "hello there", start: 0, end: 1, words: [])])

        let segment = raw.transcription(audioDuration: .seconds(1)).segments.first

        #expect(segment?.text == "hello there")
        #expect(segment?.words.isEmpty == true)
    }

    /// A segment that reports no words beside timed ones leaves the timed confidences in use.
    @Test("keeps real confidences when a marker segment reports an empty word list")
    func emptyMarkerSegmentKeepsConfidences() {
        let raw = RawTranscript(
            text: "hello there [BLANK_AUDIO]",
            segments: [
                RawSegment(
                    text: "hello there", start: 0, end: 1,
                    words: [
                        RawWord(text: " hello", start: 0, end: 0.5, probability: 0.9),
                        RawWord(text: " there", start: 0.5, end: 1, probability: 0.4),
                    ]),
                RawSegment(text: "[BLANK_AUDIO]", start: 1, end: 2, words: []),
            ])

        let transcription = raw.transcription(audioDuration: .seconds(2))
        let draft = Draft(transcription: transcription)

        #expect(transcription.segments.map(\.text) == ["hello there", ""])
        #expect(draft.confidencesAreReal)
        #expect(draft.text == "hello there")
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
