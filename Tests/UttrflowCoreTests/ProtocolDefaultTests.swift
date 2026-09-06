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
    }

    @Test("cleaners and transformers with nothing to prepare can still be warmed")
    func warmingIsHarmless() async {
        await BareCleaner().warm()
        await BareTransformer().warm()
    }
}
