import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A recogniser that hears the same words every time, so the app's mode is the only variable.
private struct HeardSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    let heard: String

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        Transcription(text: heard, audioDuration: audio.duration)
    }
}

/// An app's formatting mode reaches the dictation path: "Work it out" writes notation, "Plain prose" does not.
@Suite("Dictation: the per-app formatting mode", .bug(id: 3898))
struct DictationAdapterModeTests {
    private static let audio = AudioSamples.canonical(
        (0..<24_000).map { 0.3 * Float(sin(Double($0) * 0.07)) })
    private static let xcode = DestinationRules.xcode

    private let editor = AppContext.fixture(
        applicationName: "Xcode", bundleIdentifier: DestinationRules.xcode,
        documentName: "Parser.swift", precedingText: "let value = ")

    private func inserted(
        saying heard: String, overrides: DestinationOverrides, in context: AppContext
    ) async -> String? {
        let inserter = FakeTextInserter()
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies)
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Self.audio)),
            speech: HeardSpeechEngine(heard: heard), cleaner: router,
            context: FakeContextEngine(context: context), inserter: inserter,
            speechWords: { _ in [] }, destinationOverrides: overrides)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        return inserter.received.last
    }

    @Test("work it out writes spoken symbols in code; plain prose leaves the words as said")
    func modeDecidesNotation() async {
        let spoken = "limit equals twelve"
        let auto = await inserted(saying: spoken, overrides: .none, in: editor)
        let prose = await inserted(
            saying: spoken,
            overrides: DestinationOverrides.none.setting(
                mode: .prose, for: Self.xcode, named: "Xcode", fallback: .codeEditor),
            in: editor)
        #expect(auto?.contains("limit = 12") == true, "\(auto ?? "nil")")
        #expect(prose?.contains("=") == false, "\(prose ?? "nil")")
        #expect(prose?.lowercased().contains("limit equals") == true, "\(prose ?? "nil")")
    }

    @Test("the mode belongs to one app: another app and a forced adapter still write notation")
    func modeIsPerApp() async {
        let spoken = "limit equals twelve"
        let other = DestinationOverrides.none.setting(
            mode: .prose, for: "com.example.Other", named: "Other", fallback: .codeEditor)
        let forced = DestinationOverrides.none.setting(
            mode: .forced(AdapterID(rawValue: "source.swift")), for: Self.xcode, named: "Xcode",
            fallback: .codeEditor)
        #expect(await inserted(saying: spoken, overrides: other, in: editor)?.contains("limit = 12") == true)
        #expect(await inserted(saying: spoken, overrides: forced, in: editor)?.contains("limit = 12") == true)
    }
}
