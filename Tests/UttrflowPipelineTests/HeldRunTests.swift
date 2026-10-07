import Foundation
import Synchronization
import Testing
import UttrflowAI
import UttrflowDictionary

@testable import UttrflowCore
@testable import UttrflowPipeline

/// A run the correction gate weighed and kept reaches the model settled as heard, with no reading offered for it.
@Suite("Held runs stay as heard")
struct HeldRunTests {
    private static let entry = DictionaryEntry(
        word: "PaymentSheet", origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
    private static let index = PhoneticIndex(entries: [entry])
    private static let corrector = DictionaryCorrections { index }

    /// Nothing on screen names the entry, so the gate has a reading but no evidence for it.
    private static let context = AppContext(
        applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", documentName: "Notes.swift")

    private static let heard: Transcription = {
        let spoken = "the crash is in payment sheet"
        let words = spoken.split(separator: " ").map {
            TranscribedWord(text: String($0), confidence: $0 == "payment" || $0 == "sheet" ? 0.3 : 0.95)
        }
        return Transcription(
            text: spoken, detectedLanguage: DetectedLanguage(code: .english),
            segments: [TranscriptionSegment(text: spoken, start: .zero, end: .zero, words: words)])
    }()

    private static func request(_ transcription: Transcription) -> TransformationRequest {
        TransformationRequest(
            transcription: transcription, context: context,
            situation: Situation(app: context, insertion: .unknown, destination: .codeEditor))
    }

    @Test("the gate holds the run it had a reading for and declined")
    func gateHoldsTheDeclinedRun() async {
        let weighed = await Self.corrector.weigh(Self.heard, seeing: Self.context)

        #expect(weighed.corrections.isEmpty)
        #expect(weighed.held == [4..<6])
    }

    @Test("a held run is certain in the transcription the model is given, and every other score is kept")
    func heldRunBecomesCertain() {
        let corrected = CorrectedTranscript.unchanged(Self.heard.text).holding([4..<6])

        let draft = Draft(transcription: Self.heard.saying(corrected))

        #expect(draft.confidencesAreReal)
        #expect(draft.words.map(\.confidence) == [0.95, 0.95, 0.95, 0.95, 1, 1])
    }

    @Test("a held run that a correction changed is not held")
    func correctedRunIsNotHeld() {
        let correction = DictationCorrection(
            heard: "payment sheet", wrote: "PaymentSheet", wordRange: 4..<6, entryID: Self.entry.id,
            reason: .unknown("test"), heardConfidence: 0.3)

        let corrected = DictationCorrection.applying([correction], to: Self.heard.text).holding([4..<6])

        #expect(corrected.held.isEmpty)
    }

    @Test("the model is offered the dictionary's reading only while the gate has not declined it")
    func promptOmitsTheHeldRunsReadings() async throws {
        let weighed = await Self.corrector.weigh(Self.heard, seeing: Self.context)
        let held = Self.heard.saying(CorrectedTranscript.unchanged(Self.heard.text).holding(weighed.held))

        let before = try await Self.prompt(for: Self.heard)
        let after = try await Self.prompt(for: held)

        #expect(before.contains("PaymentSheet"))
        #expect(!after.contains(PromptBuilder.doubtfulLabel))
        #expect(!after.contains("PaymentSheet"))
    }

    /// What the model was asked, the dictionary asked first as the app builds the transformer.
    private static func prompt(for transcription: Transcription) async throws -> String {
        let model = PromptRecordingModel()
        _ = try await GenerativeTextTransformer(
            kind: .foundationModels, model: model, doubtful: .including(dictionary: { index })
        ).transform(request(transcription))
        return model.prompts.joined(separator: "\n")
    }
}

/// A model that keeps every prompt and answers with the words as heard.
private final class PromptRecordingModel: CleanupModel {
    private let asked = Mutex<[String]>([])

    var prompts: [String] { asked.withLock { $0 } }

    func availability(for language: LanguageCode?) async -> TransformerAvailability { .available }

    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        asked.withLock { $0.append(text) }
        return "The crash is in payment sheet."
    }
}
