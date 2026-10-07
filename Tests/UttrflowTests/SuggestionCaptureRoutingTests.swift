import Foundation
import Testing
import UttrflowContext
import UttrflowCore
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore

@testable import Uttrflow

@MainActor
@Suite("Suggestion capture routing")
struct SuggestionCaptureRoutingTests {
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

        let coordinator = try SuggestionCoordinator(
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

        await coordinator.rememberAfterReadsDrained(
            first, as: firstReading, because: .keystroke, at: moment, leaving: nil, typed: [])
        await coordinator.rememberAfterReadsDrained(
            second, as: secondReading, because: .tick, at: moment.addingTimeInterval(1),
            leaving: firstReading, typed: ["l", "d"])

        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        #expect(try await store.recent(in: try #require(firstReading.surface), limit: 10) == ["hello world"])
        #expect(try await store.recent(in: try #require(secondReading.surface), limit: 10).isEmpty)
    }

    @Test("deactivating an application commits the last handed line")
    func applicationDeactivationCommitsLastHandedLine() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-capture-deactivation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let coordinator = try SuggestionCoordinator(
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
        await coordinator.rememberAfterReadsDrained(
            snapshot, as: reading, because: .keystroke, at: moment, leaving: nil, typed: [])
        coordinator.lastReading = reading
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
        await coordinator.remember(
            returned, as: returnedReading, because: .keystroke, at: moment.addingTimeInterval(2))
        coordinator.lastReading = returnedReading
        coordinator.applicationChanged(front: disabledApp)
        await coordinator.waitForPendingCaptureEnd()

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
        let coordinator = try SuggestionCoordinator(
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
        await coordinator.rememberAfterReadsDrained(
            first, as: firstReading, because: .keystroke, at: moment, leaving: nil, typed: [])
        coordinator.lastReading = firstReading

        for _ in 0...CaptureTypingRouter.maximumKeys {
            coordinator.queueCaptureTyping("x", from: application, at: moment.addingTimeInterval(1))
        }

        let second = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "second", value: "new field line", selection: NSRange(location: 14, length: 0))
        let secondReading = SuggestionMoment.reading(of: second)
        await coordinator.remember(
            second, as: secondReading, because: .keystroke, at: moment.addingTimeInterval(2))
        coordinator.lastReading = secondReading
        coordinator.applicationChanged(front: disabledApp)
        await coordinator.waitForPendingCaptureEnd()

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
        let coordinator = try SuggestionCoordinator(
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
        await coordinator.rememberAfterReadsDrained(
            first, as: firstReading, because: .keystroke, at: moment, leaving: nil, typed: [])
        coordinator.lastReading = firstReading
        coordinator.noteCaptureInsertion()

        let second = FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: "second", value: "pasted new field line", selection: NSRange(location: 21, length: 0))
        let secondReading = SuggestionMoment.reading(of: second)
        await coordinator.remember(
            second, as: secondReading, because: .keystroke, at: moment.addingTimeInterval(1))
        coordinator.lastReading = secondReading
        coordinator.applicationChanged(front: disabledApp)
        await coordinator.waitForPendingCaptureEnd()

        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        #expect(
            try await store.recent(in: try #require(firstReading.surface), limit: 10)
                .contains("old field line"))
        #expect(try await store.recent(in: try #require(secondReading.surface), limit: 10).isEmpty)
    }
}
