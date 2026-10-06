import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

private let written =
    "Dear Asha, thanks for the notes. The draft is on the shared drive. I moved the review to"

/// A tidier that hands the words back as heard.
private struct UntouchedCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: .rules)
    }
}

/// Dictates once into a field showing `context` and returns the options every decode was given.
private func optionsDecoded(seeing context: AppContext) async -> [TranscriptionOptions] {
    let speech = FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "Thursday")))
    let pipeline = DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: speech,
        cleaner: UntouchedCleaner(),
        context: FakeContextEngine(context: context),
        inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard))),
        clock: ManualClock())
    await pipeline.startRecording()
    await pipeline.finishRecording()
    return await speech.transcribeCalls.events.map(\.options)
}

@Suite("Recognition reads the sentences before the caret")
struct DictationRecognitionContextTests {
    @Test("every decode is given the last two sentences before the caret")
    func ordinaryFieldConditionsRecognition() async {
        let options = await optionsDecoded(
            seeing: AppContext(applicationName: "Mail", precedingText: written))

        #expect(!options.isEmpty)
        #expect(
            options.allSatisfy {
                $0.precedingText == "The draft is on the shared drive. I moved the review to"
            })
    }

    @Test("a secure field gives recognition no text")
    func secureFieldGivesNothing() async {
        let options = await optionsDecoded(
            seeing: AppContext(applicationName: "Mail", precedingText: written, isSecure: true))

        #expect(!options.isEmpty)
        #expect(options.allSatisfy { $0.precedingText == nil })
    }

    @Test("an empty or unreadable field gives recognition no text")
    func emptyFieldGivesNothing() async {
        for preceding in ["", "  \n ", nil] as [String?] {
            let options = await optionsDecoded(
                seeing: AppContext(applicationName: "Mail", precedingText: preceding))

            #expect(!options.isEmpty)
            #expect(options.allSatisfy { $0.precedingText == nil })
        }
    }
}
