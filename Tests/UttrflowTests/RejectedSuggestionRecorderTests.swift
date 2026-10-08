import Testing
import UttrflowContext
import UttrflowPredict

@testable import Uttrflow

private enum RejectionWriteError: Error {
    case unavailable
}

private actor ThrowingRejectedStore: RejectedSuggestionStore {
    private(set) var attempts = 0
    private(set) var successes = 0
    private var failuresRemaining: Int

    init(failuresBeforeSuccess: Int = .max) {
        failuresRemaining = failuresBeforeSuccess
    }

    func recordRejected(_ text: String, in surface: Surface) async throws {
        attempts += 1
        guard failuresRemaining > 0 else {
            successes += 1
            return
        }
        failuresRemaining -= 1
        throw RejectionWriteError.unavailable
    }
}

@Suite("Rejected suggestion persistence")
struct RejectedSuggestionRecorderTests {
    @Test("A rejected line stays suppressed while its counter write fails and retries.")
    @MainActor
    func retriesFailedRejectionAndKeepsLineSuppressed() async {
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let store = ThrowingRejectedStore()
        let recorder = RejectedSuggestionRecorder(store: store)

        await recorder.record("wrong completion", in: surface)
        #expect(await store.attempts == 1)
        #expect(recorder.suppresses("wrong completion", in: surface))
        #expect(recorder.suppresses("WRONG COMPLETION", in: surface))
        #expect(
            !recorder.suppresses(
                "wrong completion", in: Surface(bundleIdentifier: "com.example.other", role: "AXTextArea")))

        await recorder.retry()
        #expect(await store.attempts == 2)
        #expect(await store.successes == 0)
        #expect(recorder.suppresses("wrong completion", in: surface))
    }

    @Test("A rejected Unicode line suppresses case-folded and canonical equivalents")
    @MainActor
    func unicodeRejectionMemory() async {
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let recorder = RejectedSuggestionRecorder(store: ThrowingRejectedStore())

        await recorder.record("Straße café", in: surface)

        #expect(recorder.suppresses("STRASSE CAFE\u{301}", in: surface))
        #expect(!recorder.suppresses("STRASSE cafe", in: surface))
    }

    @Test("A rejected-line counter write succeeds on retry after one failure.")
    @MainActor
    func rejectionRetryRecovers() async {
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let store = ThrowingRejectedStore(failuresBeforeSuccess: 1)
        let recorder = RejectedSuggestionRecorder(store: store)

        await recorder.record("wrong completion", in: surface)
        await recorder.retry()
        await recorder.retry()

        #expect(await store.attempts == 2)
        #expect(await store.successes == 1)
        #expect(!recorder.suppresses("wrong completion", in: surface))
    }

    @Test("Forgetting drops held rejection writes so a later retry writes nothing back")
    @MainActor
    func forgetDropsHeldRejections() async {
        let editor = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let other = Surface(bundleIdentifier: "com.example.other", role: "AXTextArea")
        let store = ThrowingRejectedStore(failuresBeforeSuccess: 2)
        let recorder = RejectedSuggestionRecorder(store: store)

        await recorder.record("wrong completion", in: editor)
        await recorder.record("other completion", in: other)
        recorder.forget(bundleIdentifier: "com.example.editor")
        #expect(!recorder.suppresses("wrong completion", in: editor))
        #expect(recorder.suppresses("other completion", in: other))

        recorder.forget()
        await recorder.retry()

        #expect(await store.attempts == 2)
        #expect(await store.successes == 0)
        #expect(!recorder.suppresses("other completion", in: other))
    }

    @Test("suppression stays bounded with the retry queue")
    @MainActor
    func droppedRejectionsStopBeingSuppressed() async {
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let recorder = RejectedSuggestionRecorder(store: ThrowingRejectedStore())

        for index in 0..<40 {
            await recorder.record("completion \(index)", in: surface)
        }

        let suppressedCount = (0..<40).filter {
            recorder.suppresses("completion \($0)", in: surface)
        }.count
        #expect(suppressedCount == 32)
        #expect(!recorder.suppresses("completion 0", in: surface))
        #expect(recorder.suppresses("completion 39", in: surface))
    }
}
