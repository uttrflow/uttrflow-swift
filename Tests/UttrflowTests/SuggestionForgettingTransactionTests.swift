import Foundation
import Testing
import UttrflowCore
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowTestSupport

@testable import Uttrflow
@testable import UttrflowPredictStore

private enum ForgetContext {
    @TaskLocal static var marker = 0
}

private enum ForgetScope: CaseIterable, Sendable { case application, everything }

private enum ForgetFixtureError: Error { case rejected }

private actor UnavailableRejectionStore: RejectedSuggestionStore {
    func recordRejected(_ text: String, in surface: Surface) throws {
        throw ForgetFixtureError.rejected
    }
}

private actor ForgetScorer: CandidateScoring {
    private(set) var observed: [(Int, Bool)] = []
    var isReady: Bool { true }
    func logLikelihood(of candidate: String, following context: String) async -> Double? { nil }
    func confidence(ofGenerated line: String) async -> Double? { nil }
    func forgetEverything() {
        observed.append((ForgetContext.marker, Task.isCancelled))
    }
}

private struct ForgetMachine: EnvironmentReading {
    func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) async -> [String]? {
        []
    }
}

@MainActor
private final class ForgetFixture {
    let folder = FileManager.default.temporaryDirectory.appending(path: "forget-owner-\(UUID().uuidString)")
    let app = Surface(bundleIdentifier: "com.example.forget-a", role: "AXTextArea")
    let other = Surface(bundleIdentifier: "com.example.forget-b", role: "AXTextArea")
    let queue = AcceptanceQueue()
    let rejected = RejectedSuggestionRecorder(store: UnavailableRejectionStore())
    let scorer = ForgetScorer()
    let store: PredictStore
    let capture: CaptureSession
    let verifier: Verifier
    let database: Database

    init() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = PredictStore.defaultFile(in: folder).path(percentEncoded: false)
        store = try PredictStore(path: path)
        database = try Database(path: path)
        capture = CaptureSession(
            sink: EditHearingSink(store: store, heard: { _ in }),
            preferencesFile: CapturePreferencesFile(
                path: CapturePreferencesFile.defaultFile(in: folder).path(percentEncoded: false)))
        verifier = Verifier(
            index: EnvironmentIndex(reader: ForgetMachine()), scoring: scorer, supersession: store)
        for surface in [app, other] {
            try await capture.record(.allowed, for: surface.bundleIdentifier)
            try await store.record("held line", in: surface, at: Date(timeIntervalSince1970: 1_800_000_000))
            await rejected.record("held rejection", in: surface)
        }
    }

    func clear(_ scope: ForgetScope, completed: () -> Void) async throws {
        let owner = SuggestionForgetting(
            capture: capture, store: store, rejectedSuggestionRecorder: rejected,
            acceptances: queue, verifier: verifier)
        switch scope {
        case .everything:
            try await owner.forgetEverySuggestion(completed: completed)
        case .application:
            try await owner.forgetSuggestions(from: app.bundleIdentifier, completed: completed)
        }
    }

    func admitWrite() -> Bool { queue.enqueue({}) }

    func blockWrite() async throws -> AsyncStream<Void>.Continuation {
        let started = Signal()
        let (release, continuation) = AsyncStream<Void>.makeStream()
        let admitted = queue.enqueue {
            started.fire()
            for await _ in release { break }
        }
        #expect(admitted)
        try await arrival(of: started.fired)
        return continuation
    }

    func waitForClosedAdmission() async throws {
        try await eventually {
            !rejected.suppresses("held rejection", in: app)
                && !rejected.suppresses("held rejection", in: other)
        }
        #expect(!admitWrite())
        #expect(try await store.entryCount() == 2)
        var expected = CapturePreferences()
        for surface in [app, other] { expected.record(.allowed, for: surface.bundleIdentifier) }
        #expect(await capture.decisions() == expected)
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }
}

@MainActor
@Suite("Running-loop forgetting transaction", .timeLimit(.minutes(1)))
struct SuggestionForgettingTransactionTests {
    @Test(
        "the complete route clears its scope before reset and reopens admission afterward",
        arguments: ForgetScope.allCases)
    fileprivate func successfulScope(scope: ForgetScope) async throws {
        let fixture = try await ForgetFixture()
        defer { fixture.remove() }
        let answers = await fixture.capture.decisions()
        var completed = 0
        try await fixture.clear(scope) {
            completed += 1
            #expect(!fixture.admitWrite())
        }
        #expect(completed == 1)
        #expect(
            try await fixture.store.entryCountsByApplication()
                == (scope == .everything ? [:] : [fixture.other.bundleIdentifier: 1]))
        #expect(await fixture.capture.decisions() == (scope == .everything ? CapturePreferences() : answers))
        #expect(!fixture.rejected.suppresses("held rejection", in: fixture.app))
        #expect(fixture.rejected.suppresses("held rejection", in: fixture.other) == (scope == .application))
        #expect(fixture.admitWrite())
        await fixture.queue.drained()
    }

    @Test(
        "an actual clear error skips reset, preserves answers and reopens admission",
        arguments: ForgetScope.allCases)
    fileprivate func failureScope(scope: ForgetScope) async throws {
        let fixture = try await ForgetFixture()
        defer { fixture.remove() }
        let answers = await fixture.capture.decisions()
        try fixture.database.execute(
            "CREATE TRIGGER refuse_forget BEFORE DELETE ON surface BEGIN SELECT RAISE(ABORT, 'fixture refusal'); END"
        )
        var completed = 0
        do {
            try await fixture.clear(scope) { completed += 1 }
            Issue.record("the fixture's real SQLite DELETE must fail")
        } catch {
            #expect(error is PredictStoreError)
        }
        #expect(completed == 0)
        #expect(try await fixture.store.entryCount() == 2)
        #expect(await fixture.capture.decisions() == answers)
        #expect(!fixture.rejected.suppresses("held rejection", in: fixture.app))
        #expect(fixture.rejected.suppresses("held rejection", in: fixture.other) == (scope == .application))
        #expect(fixture.admitWrite())
        await fixture.queue.drained()
        try fixture.database.execute("DROP TRIGGER refuse_forget")
        try await fixture.clear(scope) { completed += 1 }
        #expect(completed == 1)
        #expect(try await fixture.store.entryCount() == (scope == .everything ? 0 : 1))
    }

    @Test("the existing barriers drain even when their caller is cancelled, preserving task context")
    func cancelledCallerDrains() async throws {
        let fixture = try await ForgetFixture()
        defer { fixture.remove() }
        let releaseSignal = try await fixture.blockWrite()
        var completed = false
        let caller = Task {
            try await ForgetContext.$marker.withValue(73) {
                try await fixture.clear(.everything) {
                    #expect(ForgetContext.marker == 73)
                    #expect(Task.isCancelled)
                    #expect(!fixture.admitWrite())
                    completed = true
                }
            }
        }
        defer {
            caller.cancel()
            releaseSignal.yield()
        }
        try await fixture.waitForClosedAdmission()
        #expect(!completed)
        caller.cancel()
        releaseSignal.yield()
        try await caller.value
        #expect(completed)
        #expect(try await fixture.store.entryCount() == 0)
        #expect(await fixture.capture.decisions() == CapturePreferences())
        let observed = await fixture.scorer.observed
        #expect(observed.count == 1)
        #expect(observed.first?.0 == 73)
        #expect(observed.first?.1 == true)
        #expect(fixture.admitWrite())
        await fixture.queue.drained()
    }
}
