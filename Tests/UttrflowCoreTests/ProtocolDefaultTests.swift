// Tests for the default implementations Core's protocols supply.

import Testing

@testable import UttrflowCore

/// The least an engine can be, to show what the protocols supply on their own.
private struct BareCapture: AudioCaptureEngine {
    var state: AudioCaptureState { .idle }
    func start() async throws(AudioCaptureError) {}
    func stop() async throws(AudioCaptureError) -> AudioSamples { .empty }
    func cancel() async {}
}

private struct BareCleaner: TranscriptCleaning {
    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: .rules)
    }
}

private struct BareTransformer: TextTransformationEngine {
    let kind = TransformerKind.rules
    func availability(for request: TransformationRequest) async -> TransformerAvailability { .available }
    func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: kind)
    }
}

@Suite("Protocol defaults")
struct ProtocolDefaultTests {
    @Test("a capture engine that cannot share audio early answers nothing")
    func captureAnswersNothingEarly() async {
        #expect(await BareCapture().capturedSoFar() == .empty)
        #expect(await BareCapture().capturedSoFar(from: 5) == .empty)
    }

    @Test("cleaners and transformers with nothing to prepare can still be warmed")
    func warmingIsHarmless() async {
        await BareCleaner().warm(for: nil)
        await BareTransformer().warm(for: .unknown)
    }

    @Test("a cleaner with no message stage hands a joined message back as it was")
    func messageStageIsIdentity() async {
        let request = TransformationRequest(transcription: Transcription(text: "on my way"))
        #expect(
            await BareCleaner().finishMessage("on my way. be there", for: request) == "on my way. be there")
    }

    @Test("a request is the whole message unless it says it is a piece")
    func requestScopeDefaultsToMessage() {
        let transcription = Transcription(text: "on my way")
        #expect(TransformationRequest(transcription: transcription).scope == .message)
        #expect(TransformationRequest(transcription: transcription, scope: .piece).scope == .piece)
    }
}
