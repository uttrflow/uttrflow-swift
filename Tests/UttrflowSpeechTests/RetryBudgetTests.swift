// Tests that a piece's retry chain stops once it has spent its time budget.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

/// A recogniser that returns its scripted results in order and moves a test clock forward by each decode's seconds.
private final class TimedBackend: TranscriptionBackend, Sendable {
    let minimumDuration: Duration = .zero
    private let state: Mutex<State>
    private struct State {
        var clock: Duration = .zero
        var decodeSeconds: [Double]
        var calls = 0
    }
    private let result: @Sendable (Int, [Float]) -> RawTranscript

    init(decodeSeconds: [Double], result: @escaping @Sendable (Int, [Float]) -> RawTranscript) {
        state = Mutex(State(decodeSeconds: decodeSeconds))
        self.result = result
    }

    var now: @Sendable () -> Duration { { [self] in state.withLock(\.clock) } }
    var calls: Int { state.withLock(\.calls) }

    func load() async throws(SpeechEngineError) {}

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await transcribe(samples, languageHint: languageHint, biasedTowards: [])
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws(SpeechEngineError) -> RawTranscript {
        let call = state.withLock { state -> Int in
            let seconds = state.decodeSeconds.isEmpty ? 1 : state.decodeSeconds.removeFirst()
            state.clock += .seconds(seconds)
            state.calls += 1
            return state.calls
        }
        return result(call, samples)
    }
}

/// A decode that always stops at the cap with its last normal word at one second.
private func cappedResult(_: Int, _: [Float]) -> RawTranscript {
    RawTranscript(
        text: "capped",
        segments: [
            RawSegment(
                text: "capped", start: 0, end: 1,
                words: [RawWord(text: " capped", start: 0, end: 1, probability: 0.9)])
        ],
        tokensUsed: CappedDecodeRetry.tokenCapThreshold)
}

@Suite("The time budget on a piece's retry chain")
struct RetryBudgetTests {
    @Test("a decode that stays capped stops when the retries use twice the first decode")
    func cappedChainStopsAtBudget() async throws {
        let backend = TimedBackend(decodeSeconds: [2, 2, 2, 2, 2, 2], result: cappedResult)
        let samples = Array(repeating: Float(0.1), count: 60 * 16_000)

        let raw = try await CappedDecodeRetry.transcribe(
            samples: samples, languageHint: .hindi, vocabulary: [], using: backend, now: backend.now)

        // A first decode of 2 s gives a 4 s budget; two retries use it, so three decodes, not ten.
        #expect(backend.calls == 3)
        #expect(raw.effort.retryBudgetSpent)
        #expect(raw.effort.capUnresolved)
        #expect(raw.text == "capped capped capped")
    }

    @Test("a chain that finishes inside the budget is not marked as over budget")
    func chainInsideBudgetIsNotMarked() async throws {
        let backend = TimedBackend(decodeSeconds: [2, 1]) { call, samples in
            call == 1
                ? cappedResult(call, samples)
                : RawTranscript(
                    text: "rest", segments: [RawSegment(text: "rest", start: 0, end: 0.5)], tokensUsed: 10)
        }
        let samples = Array(repeating: Float(0.1), count: 2 * 16_000)

        let raw = try await CappedDecodeRetry.transcribe(
            samples: samples, languageHint: .hindi, vocabulary: [], using: backend, now: backend.now)

        #expect(backend.calls == 2)
        #expect(!raw.effort.retryBudgetSpent)
        #expect(!raw.effort.capUnresolved)
    }

    @Test("the unprompted retry of an empty result is skipped once the tail retries use the budget")
    func emptyPromptRetrySharesBudget() async throws {
        let backend = TimedBackend(decodeSeconds: [1, 3]) { call, _ in
            call == 1
                ? RawTranscript(
                    text: "", segments: [RawSegment(text: "", start: 0, end: 1)],
                    tokensUsed: CappedDecodeRetry.tokenCapThreshold)
                : RawTranscript(text: "", tokensUsed: 5)
        }
        let samples = Array(repeating: Float(0.1), count: 10 * 16_000)

        let raw = try await CappedDecodeRetry.transcribeRecoveringEmptyPrompt(
            samples: samples, languageHint: .english, vocabulary: ["Uttrflow"], using: backend,
            now: backend.now)

        #expect(backend.calls == 2)
        #expect(raw.effort.retryBudgetSpent)
        #expect(!raw.effort.retriedWithoutPrompt)
    }

    @Test("every decode after the first is timed as a retry, less the fallback seconds it reports")
    func retriesAreTimed() async throws {
        let backend = TimedBackend(decodeSeconds: [2, 1.5, 1]) { call, samples in
            switch call {
            case 1:
                return cappedResult(call, samples)
            case 2:
                let capped = cappedResult(call, samples)
                return RawTranscript(
                    text: capped.text, segments: capped.segments,
                    effort: DecodeEffort(fallbacks: 1, fallbackSeconds: 0.5), tokensUsed: capped.tokensUsed)
            default:
                return RawTranscript(
                    text: "rest", segments: [RawSegment(text: "rest", start: 0, end: 0.5)], tokensUsed: 10)
            }
        }
        let samples = Array(repeating: Float(0.1), count: 4 * 16_000)

        let raw = try await CappedDecodeRetry.transcribe(
            samples: samples, languageHint: .hindi, vocabulary: [], using: backend, now: backend.now)

        #expect(backend.calls == 3)
        #expect(raw.effort.retrySeconds == 2)
        #expect(raw.effort.fallbackSeconds == 0.5)
    }

    @Test("a single decode that is not capped spends nothing on retries")
    func plainDecodeHasNoRetryTime() async throws {
        let backend = TimedBackend(decodeSeconds: [3]) { _, _ in
            RawTranscript(
                text: "done", segments: [RawSegment(text: "done", start: 0, end: 1)], tokensUsed: 10)
        }

        let raw = try await CappedDecodeRetry.transcribe(
            samples: Array(repeating: Float(0.1), count: 16_000), languageHint: .english, vocabulary: [],
            using: backend, now: backend.now)

        #expect(raw.effort.retrySeconds == 0)
        #expect(raw.effort.isPlain)
    }

    @Test("the unprompted retry of an empty result is timed as a retry")
    func emptyPromptRetryIsTimed() async throws {
        let backend = TimedBackend(decodeSeconds: [1, 2]) { call, _ in
            call == 1
                ? RawTranscript(text: "", tokensUsed: 5)
                : RawTranscript(
                    text: "heard", segments: [RawSegment(text: "heard", start: 0, end: 1)], tokensUsed: 5)
        }

        let raw = try await CappedDecodeRetry.transcribeRecoveringEmptyPrompt(
            samples: Array(repeating: Float(0.1), count: 16_000), languageHint: .english,
            vocabulary: ["Uttrflow"], using: backend, now: backend.now)

        #expect(raw.text == "heard")
        #expect(raw.effort.retrySeconds == 2)
    }

    @Test("the worst-case chain is bounded by the budget multiple, not the retry count")
    func worstCaseIsBounded() {
        #expect(RetryBudget.firstDecodeMultiple == 2)
        var budget = RetryBudget(now: { .seconds(3) })
        budget.recordDecode(startedAt: .seconds(1))
        #expect(budget.deadline == .seconds(7))
        #expect(!budget.isSpent)
        var fast = RetryBudget(now: { .seconds(1) })
        fast.recordDecode(startedAt: .seconds(1))
        #expect(fast.deadline == .seconds(1) + RetryBudget.minimumBudget)
    }
}
