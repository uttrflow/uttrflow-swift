import Foundation
import Testing
import UttrflowContext
import UttrflowCore
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore

@testable import Uttrflow

private actor BlockingCaptureSink: CaptureSink {
    private let gate: AsyncStream<Void>
    private let gateContinuation: AsyncStream<Void>.Continuation
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation

    init() {
        (gate, gateContinuation) = AsyncStream.makeStream(of: Void.self)
        (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func waitUntilBlocked() async {
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() { gateContinuation.yield() }

    func record(
        _ text: String, in surface: Surface, after previous: String?, selfSourced: Bool, at moment: Date
    ) async throws {
        startedContinuation.yield()
        for await _ in gate { break }
    }

    func supersede(_ text: String, with replacement: String, in surface: Surface) async throws {}
}

private struct FixedGhostGenerator: CandidateGenerating {
    var isReady: Bool { get async { true } }

    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        ["hello world"]
    }
}

private struct FixedGhostScorer: CandidateScoring {
    var isReady: Bool { get async { true } }

    func logLikelihood(of candidate: String, following context: String) async -> Double? { 0 }
    func confidence(ofGenerated line: String) async -> Double? { 1 }
}

@MainActor
@Suite("Suggestion capture routing")
struct SuggestionCaptureRoutingTests {
    @Test(
        "a real turn reaches its generated suggestion while a corpus write is blocked",
        .timeLimit(.minutes(1)))
    func blockedCaptureWriteDoesNotDelayTurn() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-capture-blocked-draw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let application = "com.example.editor"
        // A caret on no screen, so the turn reaches its answer without putting a panel up beside other suites.
        let snapshot = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            value: "hello ", selection: NSRange(location: 6, length: 0),
            caret: CGRect(x: -100_000, y: -100_000, width: 0, height: 17))

        let sink = BlockingCaptureSink()
        let panel = SuggestionPanelController()
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            scoring: FixedGhostScorer(), generating: FixedGhostGenerator(), captureSink: sink,
            focusedFieldReader: { snapshot },
            frontmostBundleIdentifier: { application }, panel: panel)
        defer {
            coordinator.stop()
            panel.hide()
        }
        let moment = Date()
        let reading = SuggestionMoment.reading(of: snapshot)
        try await coordinator.capture.record(.allowed, for: application)
        coordinator.session.keystrokeArrived()
        _ = try await coordinator.capture.handle(.keystroke("hello", at: moment), in: reading)

        guard case .free(let turn) = coordinator.turns.begin(at: moment.addingTimeInterval(1)) else {
            Issue.record("the test turn should be admitted")
            return
        }
        // The Return this turn hands capture is a corpus write the sink holds until released.
        await coordinator.turn(turn, because: .returnPressed)
        await sink.waitUntilBlocked()

        #expect(coordinator.session.suggestion == .certain("hello world"))

        await sink.release()
        await coordinator.finishWrites()
    }

    @Test("pending capture typing stays bounded and overflow discards its contents")
    func pendingCaptureTypingIsBounded() {
        let pending = CaptureTypingRouter()
        for _ in 0...CaptureTypingRouter.maximumKeys {
            pending.append("x")
        }

        #expect(pending.keys.count <= CaptureTypingRouter.maximumKeys)
        let batch = pending.drain()
        #expect(batch.keys.isEmpty)
        #expect(batch.overflowed)
        #expect(pending.keys.isEmpty)
        #expect(!pending.overflowed)

        pending.append(String(repeating: "x", count: CaptureTypingRouter.maximumCharacters + 1))
        #expect(pending.keys.isEmpty)
        #expect(pending.overflowed)
    }

    @Test("discarding pending capture typing removes every buffered key")
    func discardingPendingCaptureTyping() {
        let pending = CaptureTypingRouter()
        pending.append("private")
        pending.discard()

        #expect(pending.keys.isEmpty)
        #expect(!pending.overflowed)
    }

    @Test("A same-app field switch completes the old line and leaves the new field empty")
    func sameApplicationFieldSwitchRoutesPendingSuffixToPreviousField() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-capture-routing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let coordinator = try await SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true))
        defer { coordinator.stop() }
        let application = "com.example.editor"
        let first = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "first", value: "hello wor", selection: NSRange(location: 9, length: 0))
        let second = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "second", value: "", selection: NSRange(location: 0, length: 0))
        let firstReading = SuggestionMoment.reading(of: first)
        let secondReading = SuggestionMoment.reading(of: second)
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        try await coordinator.capture.record(.allowed, for: application)

        await coordinator.captureFeed.rememberAfterReadsDrained(
            first, as: firstReading, because: .keystroke, at: moment, leaving: nil, typed: [])
        await coordinator.captureFeed.rememberAfterReadsDrained(
            second, as: secondReading, because: .tick, at: moment.addingTimeInterval(1),
            leaving: firstReading, typed: ["l", "d"])
        await coordinator.finishWrites()

        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        #expect(try await store.recent(in: try #require(firstReading.surface), limit: 10) == ["hello world"])
        #expect(try await store.recent(in: try #require(secondReading.surface), limit: 10).isEmpty)
    }

    @Test("A secure field discards queued typing without committing the incomplete previous line")
    func secureFieldDoesNotCommitPreviousLineAfterDiscardingTyping() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-capture-secure-switch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let disabledApplication = "com.example.disabled"
        let coordinator = try await SuggestionCoordinator(
            container: container,
            preferences: SuggestionPreferences(
                isEnabled: true, turnedOff: [disabledApplication]))
        defer { coordinator.stop() }
        let application = "com.example.editor"
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        try await coordinator.capture.record(.allowed, for: application)

        let first = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "first", value: "hello wor", selection: NSRange(location: 9, length: 0))
        let firstReading = SuggestionMoment.reading(of: first)
        await coordinator.captureFeed.rememberAfterReadsDrained(
            first, as: firstReading, because: .keystroke, at: moment, leaving: nil, typed: [])
        coordinator.captureFeed.lastReading = firstReading
        coordinator.queueCaptureTyping("l", from: application, at: moment.addingTimeInterval(1))
        coordinator.queueCaptureTyping("d", from: application, at: moment.addingTimeInterval(1))

        let password = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXSecureTextField",
            identifier: "password", selection: NSRange(location: 0, length: 0), isSecure: true)
        let passwordReading = SuggestionMoment.reading(of: password)
        await coordinator.captureFeed.finishBeforeSecureRead(
            passwordReading, at: moment.addingTimeInterval(2))

        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        #expect(try await store.recent(in: try #require(firstReading.surface), limit: 10).isEmpty)
        #expect(try await store.recent(in: try #require(passwordReading.surface), limit: 10).isEmpty)
    }

    @Test("A secure field does not commit a line while an insertion is pending")
    func secureFieldDoesNotCommitAfterPendingInsertion() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-capture-secure-insertion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let application = "com.example.editor"
        let coordinator = try await SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true))
        defer { coordinator.stop() }
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        try await coordinator.capture.record(.allowed, for: application)

        let first = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "first", value: "hello wor", selection: NSRange(location: 9, length: 0))
        let firstReading = SuggestionMoment.reading(of: first)
        await coordinator.captureFeed.rememberAfterReadsDrained(
            first, as: firstReading, because: .keystroke, at: moment, leaving: nil, typed: [])
        coordinator.captureFeed.lastReading = firstReading
        coordinator.captureFeed.noteInsertion()

        let password = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXSecureTextField",
            identifier: "password", selection: NSRange(location: 0, length: 0), isSecure: true)
        await coordinator.captureFeed.finishBeforeSecureRead(
            SuggestionMoment.reading(of: password), at: moment.addingTimeInterval(1))

        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        #expect(try await store.recent(in: try #require(firstReading.surface), limit: 10).isEmpty)
    }

    @Test("deactivating an application commits the last handed line")
    func applicationDeactivationCommitsLastHandedLine() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-capture-deactivation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let coordinator = try await SuggestionCoordinator(
            container: container,
            preferences: SuggestionPreferences(isEnabled: true, turnedOff: ["com.example.disabled"]))
        defer { coordinator.stop() }
        let application = "com.example.editor"
        let snapshot = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "first", value: "hello world", selection: NSRange(location: 11, length: 0))
        let reading = SuggestionMoment.reading(of: snapshot)
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        try await coordinator.capture.record(.allowed, for: application)
        await coordinator.captureFeed.rememberAfterReadsDrained(
            snapshot, as: reading, because: .keystroke, at: moment, leaving: nil, typed: [])
        coordinator.captureFeed.lastReading = reading
        coordinator.applicationChanged(front: "com.example.disabled")
        let disabledApp = "com.example.disabled"
        for _ in 0..<300 {
            coordinator.queueCaptureTyping("x", from: disabledApp, at: moment)
        }
        let returned = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "first", value: "hello world!", selection: NSRange(location: 12, length: 0))
        let returnedReading = SuggestionMoment.reading(of: returned)
        coordinator.queueCaptureTyping("!", from: application, at: moment.addingTimeInterval(2))
        await coordinator.captureFeed.remember(
            returned, as: returnedReading, because: .keystroke, at: moment.addingTimeInterval(2))
        coordinator.captureFeed.lastReading = returnedReading
        coordinator.applicationChanged(front: disabledApp)
        await coordinator.captureFeed.waitForPreviousField()

        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        let recent = try await store.recent(in: try #require(reading.surface), limit: 10)
        #expect(recent.contains("hello world!"))
        #expect(recent.allSatisfy { !$0.contains("x") })
    }

    @Test("overflowing keys for a leaving field do not suppress the newly read field")
    func overflowingOldFieldKeysDoNotSuppressNewField() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-capture-overflow-switch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let disabledApp = "com.example.disabled"
        let coordinator = try await SuggestionCoordinator(
            container: container,
            preferences: SuggestionPreferences(isEnabled: true, turnedOff: [disabledApp]))
        defer { coordinator.stop() }
        let application = "com.example.editor"
        let first = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "first", value: "old field line", selection: NSRange(location: 14, length: 0))
        let firstReading = SuggestionMoment.reading(of: first)
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        try await coordinator.capture.record(.allowed, for: application)
        await coordinator.captureFeed.rememberAfterReadsDrained(
            first, as: firstReading, because: .keystroke, at: moment, leaving: nil, typed: [])
        coordinator.captureFeed.lastReading = firstReading

        for _ in 0...CaptureTypingRouter.maximumKeys {
            coordinator.queueCaptureTyping("x", from: application, at: moment.addingTimeInterval(1))
        }

        let second = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "second", value: "new field line", selection: NSRange(location: 14, length: 0))
        let secondReading = SuggestionMoment.reading(of: second)
        await coordinator.captureFeed.remember(
            second, as: secondReading, because: .keystroke, at: moment.addingTimeInterval(2))
        coordinator.captureFeed.lastReading = secondReading
        coordinator.applicationChanged(front: disabledApp)
        await coordinator.captureFeed.waitForPreviousField()

        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        #expect(try await store.recent(in: try #require(firstReading.surface), limit: 10).isEmpty)
        #expect(
            try await store.recent(in: try #require(secondReading.surface), limit: 10)
                .contains("new field line"))
    }

    @Test("an insertion in the newly read field does not hold back the leaving field")
    func insertedNewFieldDoesNotSuppressPreviousField() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-capture-insertion-switch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let disabledApp = "com.example.disabled"
        let coordinator = try await SuggestionCoordinator(
            container: container,
            preferences: SuggestionPreferences(isEnabled: true, turnedOff: [disabledApp]))
        defer { coordinator.stop() }
        let application = "com.example.editor"
        let first = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "first", value: "old field line", selection: NSRange(location: 14, length: 0))
        let firstReading = SuggestionMoment.reading(of: first)
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        try await coordinator.capture.record(.allowed, for: application)
        await coordinator.captureFeed.rememberAfterReadsDrained(
            first, as: firstReading, because: .keystroke, at: moment, leaving: nil, typed: [])
        coordinator.captureFeed.lastReading = firstReading
        coordinator.captureFeed.noteInsertion()

        let second = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "second", value: "pasted new field line", selection: NSRange(location: 21, length: 0))
        let secondReading = SuggestionMoment.reading(of: second)
        await coordinator.captureFeed.remember(
            second, as: secondReading, because: .keystroke, at: moment.addingTimeInterval(1))
        coordinator.captureFeed.lastReading = secondReading
        coordinator.applicationChanged(front: disabledApp)
        await coordinator.captureFeed.waitForPreviousField()

        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        #expect(
            try await store.recent(in: try #require(firstReading.surface), limit: 10)
                .contains("old field line"))
        #expect(try await store.recent(in: try #require(secondReading.surface), limit: 10).isEmpty)
    }
}
