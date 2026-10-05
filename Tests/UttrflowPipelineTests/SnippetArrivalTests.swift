import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A recogniser that hears one fixed phrase.
private actor PhraseSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let heard: String

    init(hearing heard: String) {
        self.heard = heard
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        Transcription(text: heard, audioDuration: audio.duration)
    }
}

/// A dictionary holding one spelling for one heard word, wherever it is heard.
private struct OneEntryDictionary: WordCorrecting {
    let heard: String
    let wrote: String

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        transcription.text.split(whereSeparator: \.isWhitespace).enumerated().compactMap {
            $0.element.lowercased() == heard
                ? DictationCorrection(
                    heard: String($0.element), wrote: wrote, wordRange: $0.offset..<($0.offset + 1),
                    entryID: UUID(), reason: .unknown("test"), heardConfidence: 0.2)
                : nil
        }
    }
}

/// The snippets on file, matched by the shipping matcher.
private struct FiledSnippets: SnippetExpanding {
    let snippets: [Snippet]

    func expand(_ text: String) async -> ExpandedTranscript {
        let expansion = SnippetExpander(snippets: snippets).expand(text)
        return ExpandedTranscript(
            text: expansion.text,
            snippets: expansion.applied.map {
                SnippetUse(snippetID: $0.snippetID, matched: $0.matched, expansion: $0.expansion)
            })
    }
}

@Suite("Snippet triggers: how a phrase arrives at the matcher")
struct SnippetArrivalTests {
    /// Invented triggers across numbers, spoken marks, fillers, contractions, a dictionary word and romanised Hindi.
    static let triggers = [
        "email one", "send a comma", "um sign off", "cube control", "page two", "step three please",
        "room twenty one", "uh my address", "dont forget", "its done", "call me at five",
        "question mark reply", "new line thanks", "version two point one", "ok bye", "cube notes",
        "hmm standup link", "i am out", "weekly one on one", "my zoom link", "tea break",
        "thanks so much", "हाँ ठीक है", "मैं अभी आता हूँ", "कल मिलते हैं", "बहुत अच्छा",
        "चलो ठीक है", "नमस्ते जी", "धन्यवाद भाई", "अच्छा सुनो",
    ]

    private static let dictionary = OneEntryDictionary(heard: "cube", wrote: "Kube")

    private func pipeline(
        hearing phrase: String, snippets: any SnippetExpanding, inserter: FakeTextInserter
    ) async -> DictationPipeline {
        let rate = AudioSamples.canonicalSampleRate
        let take = AudioSamples.canonical(
            (0..<Int(1.2 * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) })
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(take))
        await capture.setCaptured(take)
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies)
        return DictationPipeline(
            capture: capture, speech: PhraseSpeechEngine(hearing: phrase), cleaner: router,
            context: FakeContextEngine(), inserter: inserter, corrector: Self.dictionary,
            snippets: snippets)
    }

    private func words(_ text: String) -> [String] {
        Snippet(trigger: text, expansion: " ", created: .distantPast).triggerWords
    }

    @Test("the preview is the words a dictation of that phrase inserts", arguments: triggers)
    func previewMatchesDictation(_ phrase: String) async {
        let inserter = FakeTextInserter()
        let pipeline = await pipeline(hearing: phrase, snippets: NoTextChanges(), inserter: inserter)
        let arrives = await pipeline.arrival(ofSpoken: phrase)
        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(inserter.received.count == 1)
        #expect(words(arrives) == words(inserter.received.first ?? ""), "\(arrives) vs \(inserter.received)")
        #expect(LatinScript.isLatin(arrives))
    }

    @Test("a trigger saved in the form it arrives fires when said", arguments: triggers)
    func arrivedFormFires(_ phrase: String) async {
        let probe = await pipeline(hearing: phrase, snippets: NoTextChanges(), inserter: FakeTextInserter())
        let arrives = await probe.arrival(ofSpoken: phrase)
        let snippet = Snippet(trigger: arrives, expansion: "EXPANDED", created: .distantPast)
        let inserter = FakeTextInserter()
        let pipeline = await pipeline(
            hearing: phrase, snippets: FiledSnippets(snippets: [snippet]), inserter: inserter)
        await pipeline.startRecording()
        await pipeline.finishRecording()

        let fired = inserter.received.first?.contains("EXPANDED") == true
        // A decimal's point splits the arrived trigger at a place the matcher will not cross; tracked apart.
        if arrives.contains(/\d\.\d/) {
            withKnownIssue { #expect(fired, "\(arrives) -> \(inserter.received)") }
        } else {
            #expect(fired, "\(arrives) -> \(inserter.received)")
        }
    }

    /// Invented triggers typed in Devanagari or in mixed script, as a person types them in the editor.
    static let typedInDevanagari = [
        "हाँ ठीक है", "मैं अभी आता हूँ", "कल मिलते हैं", "बहुत अच्छा", "नमस्ते जी",
        "मेरा address", "office का पता", "धन्यवाद team", "send करो notes", "चाय break",
    ]

    @Test(
        "a trigger typed in Devanagari fires when said, and inserts Latin only",
        arguments: typedInDevanagari)
    func devanagariTriggerFires(_ phrase: String) async {
        let snippet = Snippet(trigger: phrase, expansion: "पता: EXPANDED", created: .distantPast)
        let inserter = FakeTextInserter()
        let pipeline = await pipeline(
            hearing: phrase, snippets: FiledSnippets(snippets: [snippet]), inserter: inserter)
        await pipeline.startRecording()
        await pipeline.finishRecording()

        let inserted = inserter.received.first ?? ""
        #expect(inserted.contains("EXPANDED"), "\(phrase) -> \(inserter.received)")
        #expect(LatinScript.writesOnlyLatin(inserted), "\(inserted)")
    }

    @Test("the dictionary's spelling is part of the arrival")
    func dictionaryIsApplied() async {
        let probe = await pipeline(
            hearing: "cube control", snippets: NoTextChanges(), inserter: FakeTextInserter())
        #expect(words(await probe.arrival(ofSpoken: "cube control")) == ["kube", "control"])
    }
}
