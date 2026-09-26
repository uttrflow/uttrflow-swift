// Tests that a recogniser chosen in Settings transcribes the next dictation, never the one under way.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// Holds a recogniser's load open until the test lets it end.
private actor HeldLoad {
    private var held: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    let reached = Signal()

    func pass() async {
        reached.fire()
        guard !isOpen else { return }
        await withCheckedContinuation { held.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in held { continuation.resume() }
        held.removeAll()
    }
}

/// A recogniser whose load waits on the test and then fails.
private final class HeldFailingSpeechEngine: SpeechEngine, Sendable {
    let kind: SpeechEngineKind = .whisperKit
    let load = HeldLoad()

    func prepare() async throws(SpeechEngineError) {
        await load.pass()
        throw .modelLoadFailed(description: "fixture")
    }

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        .fixture(text: "never heard")
    }
}

/// A tidier that hands the words back as they came.
private struct PassThroughCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        TransformationResult(text: request.transcription.text, producedBy: .rules)
    }
}

/// A place for the words to land that never refuses.
private struct LandingInserter: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        InsertionAttempt(.accessibility)
    }
}

// MARK: - Fixtures

private let spoken: AudioSamples = {
    let count = Int(AudioSamples.canonicalSampleRate)
    let tone: [Float] = (0..<count).map { index in 0.3 * Float(sin(Double(index) * 0.07)) }
    return AudioSamples.canonical(tone)
}()

private func accurate() -> FakeSpeechEngine {
    FakeSpeechEngine(kind: .whisperKit, transcribeOutcome: .success(.fixture(text: "most accurate")))
}

private func faster() -> FakeSpeechEngine {
    FakeSpeechEngine(kind: .appleSpeech, transcribeOutcome: .success(.fixture(text: "faster")))
}

private func makePipeline(speech: any SpeechEngine) -> DictationPipeline {
    DictationPipeline(
        capture: FakeAudioCaptureEngine(stopOutcome: .success(spoken)), speech: speech,
        cleaner: PassThroughCleaner(), context: FakeContextEngine(context: .fixture()),
        inserter: LandingInserter(), earlyPoll: .seconds(60))
}

extension DictationState {
    fileprivate var words: String? {
        if case .inserted(let outcome) = self { outcome.text } else { nil }
    }
}

// MARK: - Tests

@Suite("Dictation pipeline: switching the recogniser", .timeLimit(.minutes(1)))
struct DictationPipelineSpeechSwitchTests {
    @Test("the recogniser chosen between dictations loads and transcribes the next one")
    func nextDictationUsesTheNewRecogniser() async {
        let before = accurate()
        let after = faster()
        let pipeline = makePipeline(speech: before)
        await pipeline.prepare()

        await pipeline.adopt(speech: after)

        #expect(await after.prepareCalls.count == 1, "the new recogniser is loaded when it is chosen")
        #expect(await pipeline.isReady)
        #expect(await pipeline.speechKind == .appleSpeech)
        await pipeline.startRecording()
        await pipeline.finishRecording()
        #expect(await pipeline.currentState.words == "faster")
        #expect(await before.transcribeCalls.isEmpty, "the recogniser it replaced is not asked again")
    }

    @Test("a recogniser chosen while the user speaks waits for that dictation to end")
    func dictationUnderWayKeepsItsRecogniser() async throws {
        let before = accurate()
        let after = faster()
        let pipeline = makePipeline(speech: before)

        await pipeline.startRecording()
        let switching = Task { await pipeline.adopt(speech: after) }
        try await eventually { await pipeline.speechChangesWaiting == 1 }
        #expect(await after.prepareCalls.isEmpty, "nothing is loaded beside the recogniser in use")
        #expect(await pipeline.speechKind == .whisperKit)
        await pipeline.finishRecording()
        await switching.value

        #expect(await after.transcribeCalls.isEmpty, "the dictation under way is not swapped")
        #expect(await pipeline.speechKind == .appleSpeech)
        await pipeline.acknowledge()
        await pipeline.startRecording()
        await pipeline.finishRecording()
        #expect(await pipeline.currentState.words == "faster", "the dictation after it is")
    }

    @Test("a recogniser replaced by a later choice before it was taken up is never loaded")
    func laterChoiceWins() async throws {
        let first = faster()
        let second = accurate()
        let pipeline = makePipeline(speech: FakeSpeechEngine())

        await pipeline.startRecording()
        let one = Task { await pipeline.adopt(speech: first) }
        try await eventually { await pipeline.speechChangesWaiting == 1 }
        let two = Task { await pipeline.adopt(speech: second) }
        try await eventually { await pipeline.speechChangesWaiting == 2 }
        await pipeline.cancel()
        await one.value
        await two.value

        #expect(await first.prepareCalls.isEmpty)
        #expect(await second.prepareCalls.count == 1)
        #expect(await pipeline.speechKind == .whisperKit)
    }

    @Test("a load of a recogniser since replaced says nothing about the one in use")
    func replacedLoadIsIgnored() async throws {
        let stale = HeldFailingSpeechEngine()
        let pipeline = makePipeline(speech: stale)
        let loading = Task { await pipeline.prepare() }
        try await arrival(of: stale.load.reached.fired)

        await pipeline.adopt(speech: faster())
        #expect(await pipeline.isLoading, "the replaced load is still running")
        await stale.load.open()
        await loading.value

        #expect(await pipeline.isReady, "the failed load of the old recogniser does not unready the new one")
        #expect(await !pipeline.isLoading)
        #expect(await pipeline.currentState == .idle)
    }

    @Test("a recogniser taken up without loading is not called ready")
    func adoptWithoutLoading() async {
        let after = faster()
        let pipeline = makePipeline(speech: accurate())
        await pipeline.prepare()

        await pipeline.adopt(speech: after, loading: false)

        #expect(await after.prepareCalls.isEmpty)
        #expect(await !pipeline.isReady)
        #expect(await pipeline.speechKind == .appleSpeech)
    }
}
