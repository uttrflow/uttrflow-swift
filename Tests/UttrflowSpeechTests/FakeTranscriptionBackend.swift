// Fake recognisers for the speech tests.
import Synchronization

@testable import UttrflowCore
@testable import UttrflowSpeech

/// A recogniser that returns whatever a test scripts.
final class FakeTranscriptionBackend: TranscriptionBackend {
    struct Call: Sendable, Equatable {
        let sampleCount: Int
        let languageHint: LanguageCode?
        let vocabulary: [String]
    }

    private struct State {
        var loadCount = 0
        var calls: [Call] = []
        var loadError: SpeechEngineError?
        var transcribeError: SpeechEngineError?
        var result = RawTranscript(text: "hello there")
    }

    private let state = Mutex(State())

    init(result: RawTranscript = RawTranscript(text: "hello there")) {
        state.withLock { $0.result = result }
    }

    func load() async throws(SpeechEngineError) {
        let error = state.withLock { state -> SpeechEngineError? in
            state.loadCount += 1
            return state.loadError
        }
        if let error { throw error }
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await transcribe(samples, languageHint: languageHint, biasedTowards: [])
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws(SpeechEngineError) -> RawTranscript {
        let outcome = state.withLock { state -> Result<RawTranscript, SpeechEngineError> in
            state.calls.append(
                Call(
                    sampleCount: samples.count, languageHint: languageHint, vocabulary: vocabulary))
            if let error = state.transcribeError { return .failure(error) }
            return .success(state.result)
        }
        switch outcome {
        case .success(let raw): return raw
        case .failure(let error): throw error
        }
    }

    // MARK: Scripting and inspection

    func failLoad(with error: SpeechEngineError) { state.withLock { $0.loadError = error } }
    func failTranscribe(with error: SpeechEngineError) { state.withLock { $0.transcribeError = error } }

    var loadCount: Int { state.withLock(\.loadCount) }
    var calls: [Call] { state.withLock(\.calls) }
}

/// A recogniser with no way to bias its decoder, the shape ``AppleSpeechBackend`` has.
final class UnbiasableBackend: TranscriptionBackend {
    private let heard = Mutex(0)

    func load() async throws(SpeechEngineError) {}

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        heard.withLock { $0 += 1 }
        return RawTranscript(text: "hello there")
    }

    var transcriptions: Int { heard.withLock { $0 } }
}
