// Tests that the engine hands the recogniser one call at a time, however many callers arrive.
import Synchronization
import Testing
import UttrflowTestSupport

@testable import UttrflowCore
@testable import UttrflowSpeech

/// A recogniser that holds every call until released and ignores cancellation, the way a decode inside one model call does.
private final class HeldBackend: TranscriptionBackend {
    private struct State {
        var inside = 0
        var mostInside = 0
        var loads = 0
        var transcriptions = 0
        var isOpen = false
        var held: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    func load() async throws(SpeechEngineError) {
        await hold { $0.loads += 1 }
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        await hold { $0.transcriptions += 1 }
        return RawTranscript(text: "hello there")
    }

    /// Counts the call as inside, parks it unless the backend is open, and counts it out once released.
    private func hold(_ count: @Sendable @escaping (inout State) -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let passes = state.withLock { state -> Bool in
                count(&state)
                state.inside += 1
                state.mostInside = max(state.mostInside, state.inside)
                if !state.isOpen { state.held.append(continuation) }
                return state.isOpen
            }
            if passes { continuation.resume() }
        }
        state.withLock { $0.inside -= 1 }
    }

    /// Lets the oldest held call finish.
    func releaseOne() {
        let first = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.held.isEmpty ? nil : state.held.removeFirst()
        }
        first?.resume()
    }

    /// Releases every held call and lets every later one straight through, so no test can hang on a held call.
    func open() {
        let all = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            defer { state.held = [] }
            return state.held
        }
        for continuation in all { continuation.resume() }
    }

    var held: Int { state.withLock(\.held.count) }
    var mostInside: Int { state.withLock(\.mostInside) }
    var loads: Int { state.withLock(\.loads) }
    var transcriptions: Int { state.withLock(\.transcriptions) }
}

@Suite("BackedSpeechEngine: one call into the recogniser at a time", .timeLimit(.minutes(1)))
struct BackedSpeechEngineTurnTests {
    private let speech = AudioSamples.canonical(
        Array(repeating: 0.1, count: AudioSamples.canonicalSampleRate))

    /// Yields until `condition` holds or the attempts run out, for what must not happen.
    private func briefly(_ condition: () -> Bool) async {
        for _ in 0..<20_000 where !condition() { await Task.yield() }
    }

    /// An engine whose recogniser has already loaded, with the backend holding calls again.
    private func loadedEngine(_ backend: HeldBackend) async throws -> BackedSpeechEngine {
        let engine = BackedSpeechEngine(kind: .whisperKit, backend: backend)
        let loading = Task { try await engine.prepare() }
        try await eventually { backend.held == 1 }
        backend.releaseOne()
        try await loading.value
        return engine
    }

    @Test("a second transcription waits for the first to leave the recogniser")
    func transcriptionsDoNotOverlap() async throws {
        let backend = HeldBackend()
        let engine = try await loadedEngine(backend)

        let first = Task { try await engine.transcribe(speech, options: .automatic) }
        try await eventually { backend.held == 1 }
        let second = Task { try await engine.transcribe(speech, options: .automatic) }
        await briefly { backend.transcriptions == 2 }

        #expect(backend.transcriptions == 1, "the second call must not reach the recogniser yet")
        backend.releaseOne()
        try await eventually { backend.transcriptions == 2 }
        backend.open()
        _ = try await first.value
        _ = try await second.value

        #expect(backend.transcriptions == 2)
        #expect(backend.mostInside == 1)
    }

    @Test("a transcription abandoned while it waits never reaches the recogniser")
    func abandonedWaitDoesNotDecode() async throws {
        let backend = HeldBackend()
        let engine = try await loadedEngine(backend)

        let first = Task { try await engine.transcribe(speech, options: .automatic) }
        try await eventually { backend.held == 1 }
        let abandoned = Task { try await engine.transcribe(speech, options: .automatic) }
        await briefly { backend.transcriptions == 2 }
        abandoned.cancel()
        let outcome = Task { await abandoned.result }
        for _ in 0..<2_000 { await Task.yield() }
        backend.open()

        guard case .failure = await outcome.value else {
            Issue.record("an abandoned wait must end in an error, not a transcript")
            return
        }
        _ = try await first.value
        #expect(backend.transcriptions == 1, "only the first call decodes")
        #expect(backend.mostInside == 1)
    }

    @Test("a transcription already cancelled does not decode")
    func cancelledBeforeWaitingDoesNotDecode() async throws {
        let backend = HeldBackend()
        let engine = try await loadedEngine(backend)
        backend.open()

        let started = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.transcribe(speech, options: .automatic)
        }

        await #expect(throws: SpeechEngineError.self) { try await started.value }
        #expect(backend.transcriptions == 0)
    }

    @Test("a transcription that arrives during the load does not load the recogniser a second time")
    func loadIsNotRepeatedByAnOverlappingCall() async throws {
        let backend = HeldBackend()
        let engine = BackedSpeechEngine(kind: .whisperKit, backend: backend)

        let loading = Task { try await engine.prepare() }
        try await eventually { backend.held == 1 }
        let transcribing = Task { try await engine.transcribe(speech, options: .automatic) }
        await briefly { backend.loads == 2 }

        #expect(backend.loads == 1, "the overlapping call must wait for the load in flight")
        backend.open()
        try await loading.value
        _ = try await transcribing.value

        #expect(backend.loads == 1)
        #expect(backend.mostInside == 1)
    }

    @Test("a prepare that waits behind a load finds the recogniser loaded")
    func waitingPrepareDoesNotLoadAgain() async throws {
        let backend = HeldBackend()
        let engine = BackedSpeechEngine(kind: .whisperKit, backend: backend)

        let first = Task { try await engine.prepare() }
        try await eventually { backend.held == 1 }
        let second = Task { try await engine.prepare() }
        await briefly { backend.loads == 2 }
        backend.open()
        try await first.value
        try await second.value

        #expect(backend.loads == 1)
    }
}
