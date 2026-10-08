import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A recogniser that hears the same words in every piece.
private actor HearingSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let heard: String
    private(set) var calls = 0

    init(hearing heard: String) {
        self.heard = heard
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        calls += 1
        return Transcription(
            text: heard, detectedLanguage: DetectedLanguage(code: .hindi, confidence: 1),
            audioDuration: audio.duration)
    }
}

@Suite("Dictation pipeline: Latin letters only")
struct DictationPipelineLatinOutputTests {
    /// One short take, heard as `heard`, tidied by `cleaner`, and what was inserted.
    private func dictate(_ heard: String, cleaner: any TranscriptCleaning) async -> [String] {
        await dictate(heard, cleaner: cleaner, snippets: NoTextChanges())
    }

    /// One short take with the supplied snippet expander and what the inserter receives.
    private func dictate(
        _ heard: String, cleaner: any TranscriptCleaning, snippets: any SnippetExpanding
    ) async -> [String] {
        await dictate(speech: HearingSpeechEngine(hearing: heard), cleaner: cleaner, snippets: snippets)
            .inserted
    }

    /// One short take heard by `speech`, what was inserted and the state it ended in.
    private func dictate(
        speech: HearingSpeechEngine,
        cleaner: any TranscriptCleaning = FakeTranscriptCleaner(producedBy: .foundationModels),
        snippets: any SnippetExpanding = NoTextChanges()
    ) async -> (inserted: [String], state: DictationState) {
        let rate = AudioSamples.canonicalSampleRate
        let take = AudioSamples.canonical(
            (0..<Int(1.2 * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) })
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(take))
        await capture.setCaptured(take)
        let inserter = FakeTextInserter()
        let pipeline = DictationPipeline(
            capture: capture, speech: speech, cleaner: cleaner,
            context: FakeContextEngine(context: .fixture()), inserter: inserter, snippets: snippets)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        return (inserter.received, await pipeline.currentState)
    }

    @Test("writes a listed word in the spelling the user prefers, after romanising it")
    func writesPreferredSpelling() async {
        let rate = AudioSamples.canonicalSampleRate
        let take = AudioSamples.canonical(
            (0..<Int(1.2 * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) })
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(take))
        await capture.setCaptured(take)
        let inserter = FakeTextInserter()
        let pipeline = DictationPipeline(
            capture: capture, speech: HearingSpeechEngine(hearing: "हाँ ठीक है।"),
            cleaner: FakeTranscriptCleaner(producedBy: .foundationModels),
            context: FakeContextEngine(context: .fixture()), inserter: inserter,
            spellings: { ["thik": "theek"] })
        await pipeline.startRecording()
        await pipeline.finishRecording()
        #expect(inserter.received.first?.hasPrefix("Haan theek hai") == true, "\(inserter.received)")
    }

    @Test("romanises Devanagari that no tidier romanised, whether the tidy failed or handed the words back")
    func romanisesUntidiedDevanagari() async {
        for cleaner: any TranscriptCleaning in [
            FakeTranscriptCleaner(answering: ScriptedSequence(.failure(.noCapableTransformer))),
            FakeTranscriptCleaner(producedBy: .foundationModels),
        ] {
            let inserted = await dictate("हाँ ठीक है।", cleaner: cleaner)
            #expect(inserted.count == 1)
            #expect(inserted.allSatisfy { !Romaniser.containsDevanagari($0) && LatinScript.isLatin($0) })
            #expect(inserted.first?.hasPrefix("Haan thik hai") == true, "\(inserted)")
        }
    }

    @Test("romanises Devanagari from a snippet before insertion")
    func romanisesSnippetExpansion() async {
        let snippet = Snippet(
            trigger: "greeting", expansion: "हाँ ठीक है", created: Date(timeIntervalSince1970: 0))
        let inserted = await dictate(
            "greeting", cleaner: FakeTranscriptCleaner(producedBy: .foundationModels),
            snippets: StoredSnippetExpander(snippet: snippet))

        #expect(inserted == ["Haan thik hai"])
        #expect(inserted.allSatisfy { !Romaniser.containsDevanagari($0) && LatinScript.isLatin($0) })
    }

    @Test("inserts romanised Hinglish on the shipping floor when the model is not there")
    func rulesFloorRomanises() async {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.foundationModels, .rules],
            rulesAlone: .shortReplies)
        let inserted = await dictate("मैं अभी आता हूँ", cleaner: router)
        #expect(inserted.count == 1)
        #expect(inserted.first?.hasPrefix("Main abhi aata hoon") == true, "\(inserted)")
    }

    @Test(
        "a piece heard mostly in a script neither language is written in inserts nothing and fails as untranscribed",
        arguments: ["Привет, как дела", "你好，谢谢观看", "شكرا جزيلا", "สวัสดีครับ"])
    func untranscribedScriptIsARecognitionFailure(heard: String) async {
        let speech = HearingSpeechEngine(hearing: heard)
        let (inserted, state) = await dictate(speech: speech)
        #expect(inserted.isEmpty)
        #expect(state == .failed(DictationFailure(SpeechEngineError.speechWithoutWords)))
        #expect(await speech.calls == 2)
    }

    @Test("writes a single word of another script inside an English sentence in Latin letters")
    func transliteratesOneForeignWord() async {
        let inserted = await dictate(
            "Let us meet at the Привет cafe tomorrow",
            cleaner: FakeTranscriptCleaner(producedBy: .foundationModels))
        #expect(inserted.count == 1)
        #expect(inserted.allSatisfy { LatinScript.isLatin($0) && $0.hasPrefix("Let us meet at the ") })
    }

    @Test(
        "inserts English exactly as the tidier wrote it",
        arguments: ["Okay, see you at 5 p.m. 👍", "Café “naïve” — résumé…", "x² ≤ ½, ₹1,50,000 and 3.5%"])
    func leavesEnglishAlone(text: String) async {
        #expect(await dictate(text, cleaner: FakeTranscriptCleaner(producedBy: .foundationModels)) == [text])
    }

    @Test(
        "every written word is heard or counted as a script conversion on the outcome",
        arguments: [
            ("हाँ ठीक है।", 3, 0), ("मुझे report भेजो", 2, 0), ("मैं अभी आता हूँ", 4, 0),
            ("send the report today", 0, 0), ("Let us meet at the Привет cafe tomorrow", 0, 1),
        ])
    func writtenWordsAreAccounted(heard: String, romanised: Int, transliterated: Int) async {
        let (inserted, state) = await dictate(speech: HearingSpeechEngine(hearing: heard))
        guard case .inserted(let outcome) = state else {
            Issue.record("not inserted: \(state)")
            return
        }
        let conversions = outcome.changes.scriptConversions
        #expect(
            conversions == ScriptConversions(wordsRomanised: romanised, wordsTransliterated: transliterated))
        let heardWords = Set(Self.words(heard))
        let novel = inserted.flatMap(Self.words).filter { !heardWords.contains($0) }.count
        let unaccounted = max(0, novel - conversions.words)
        print("romanised \(conversions.wordsRomanised), transliterated \(conversions.wordsTransliterated)")
        #expect(unaccounted == 0, "\(inserted) has \(unaccounted) words with no named origin")
    }

    /// Lower-cased words with their punctuation dropped, the form two texts are compared in.
    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
            .filter { !$0.isEmpty }
    }
}

/// Runs the production snippet matcher and adapts its result to the pipeline seam.
private struct StoredSnippetExpander: SnippetExpanding {
    let snippet: Snippet

    func expand(_ text: String) async -> ExpandedTranscript {
        let expansion = SnippetExpander(snippets: [snippet]).expand(text)
        return ExpandedTranscript(
            text: expansion.text,
            snippets: expansion.applied.map {
                SnippetUse(snippetID: $0.snippetID, matched: $0.matched, expansion: $0.expansion)
            })
    }
}
