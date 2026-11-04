import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// Records what the vocabulary ranking was shown.
private final class Seen: Sendable {
    private let contexts = Mutex<[AppContext]>([])
    func record(_ context: AppContext) { contexts.withLock { $0.append(context) } }
    var all: [AppContext] { contexts.withLock { $0 } }
}

private func dictate(
    into context: AppContext, names: [String]
) async throws -> (seen: [AppContext], asked: Int) {
    let seen = Seen()
    let engine = FakeContextEngine(context: context, onScreenNames: names)
    let pipeline = DictationPipeline(
        capture: FakeAudioCaptureEngine(),
        speech: FakeSpeechEngine(transcribeOutcome: .success(.fixture(text: "tell Mira"))),
        cleaner: FakeTranscriptCleaner(producedBy: .rules), context: engine,
        inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard))),
        speechWords: {
            seen.record($0); return []
        }, clock: ManualClock())
    await pipeline.startRecording()
    // The names are read while recording, so the release waits for that read rather than racing it.
    try await eventually { await pipeline.earlyReadsSettled == 1 }
    await pipeline.finishRecording()
    return (seen.all, await engine.nameCalls.events.count)
}

@Suite("Dictation takes the names visible in the conversation")
struct DictationOnScreenNamesTests {
    @Test("the vocabulary ranking sees the names read while recording")
    func rankingSeesNames() async throws {
        let result = try await dictate(into: AppContext(applicationName: "Messages"), names: ["Meera"])
        #expect(result.asked >= 1)
        #expect(!result.seen.isEmpty)
        #expect(result.seen.allSatisfy { $0.onScreenNames == ["Meera"] })
    }

    @Test("a secure field is given no names")
    func secureFieldGetsNone() async throws {
        let result = try await dictate(
            into: AppContext(applicationName: "Login", isSecure: true), names: ["Meera"])
        #expect(result.seen.allSatisfy { $0.onScreenNames.isEmpty })
    }
}
