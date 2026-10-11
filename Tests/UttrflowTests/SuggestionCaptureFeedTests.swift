import Foundation
import Testing
import UttrflowContext
import UttrflowCore
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore

@testable import Uttrflow

@MainActor
@Suite("Suggestion capture feed")
struct SuggestionCaptureFeedTests {
    private static let application = "com.example.editor"
    private static let moment = Date(timeIntervalSince1970: 1_800_000_000)

    /// A feed over a real corpus in a fresh folder, with learning allowed in the test application.
    private struct Fixture {
        let container: URL
        let store: PredictStore
        let feed: SuggestionCaptureFeed

        @MainActor
        init() async throws {
            container = FileManager.default.temporaryDirectory
                .appending(path: "suggestion-capture-feed-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            store = try PredictStore(
                path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
            let capture = CaptureSession(
                sink: EditHearingSink(store: store, heard: { _ in }),
                preferencesFile: CapturePreferencesFile(
                    path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false)),
                policy: .whereReturnSends)
            try await capture.record(.allowed, for: SuggestionCaptureFeedTests.application)
            feed = SuggestionCaptureFeed(capture: capture, acceptances: AcceptanceQueue())
        }

        func learned(in reading: FieldReading) async throws -> [String] {
            await feed.waitForPreviousField()
            return try await store.recent(in: try #require(reading.surface), limit: 10)
        }

        func remove() { try? FileManager.default.removeItem(at: container) }
    }

    private static func field(_ identifier: String, value: String) -> FocusedFieldSnapshot {
        FocusedFieldSnapshot(
            bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
            identifier: identifier, value: value,
            selection: NSRange(location: value.utf16.count, length: 0))
    }

    /// Reads `snapshot` as a turn would, keeping the reading the next turn leaves from.
    private static func read(
        _ snapshot: FocusedFieldSnapshot, into feed: SuggestionCaptureFeed,
        because reason: SuggestionReason, after seconds: TimeInterval
    ) async -> FieldReading {
        let reading = SuggestionMoment.reading(of: snapshot)
        await feed.remember(snapshot, as: reading, because: reason, at: moment.addingTimeInterval(seconds))
        feed.lastReading = reading
        return reading
    }

    @Test("a slow field's late echo of typed keys is learned, and awaited until the field shows it")
    func lateEchoIsAwaitedAndLearned() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }

        _ = await Self.read(
            Self.field("shell", value: "kubectl get po"), into: fixture.feed, because: .keystroke, after: 0)
        fixture.feed.queue("d")
        fixture.feed.queue("s")
        _ = await Self.read(
            Self.field("shell", value: "kubectl get po"), into: fixture.feed, because: .keystroke, after: 0.1)
        #expect(fixture.feed.awaitsTypedEcho)
        _ = await Self.read(
            Self.field("shell", value: "kubectl get pod"), into: fixture.feed, because: .keystroke,
            after: 0.3)
        #expect(fixture.feed.awaitsTypedEcho)
        _ = await Self.read(
            Self.field("shell", value: "kubectl get pods"), into: fixture.feed, because: .keystroke,
            after: 0.5)
        #expect(!fixture.feed.awaitsTypedEcho)
        let reading = await Self.read(
            Self.field("shell", value: "kubectl get pods"), into: fixture.feed, because: .returnPressed,
            after: 1)

        #expect(try await fixture.learned(in: reading) == ["kubectl get pods"])
    }

    @Test("a read that is not the typed keys' echo stops awaiting one")
    func unrelatedReadStopsAwaitingEcho() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }

        _ = await Self.read(
            Self.field("shell", value: "git sta"), into: fixture.feed, because: .keystroke, after: 0)
        fixture.feed.queue("t")
        _ = await Self.read(
            Self.field("shell", value: "git stash pop"), into: fixture.feed, because: .keystroke, after: 0.3)

        #expect(!fixture.feed.awaitsTypedEcho)
        #expect(SuggestionCaptureFeed.unechoed(after: "git sta", typed: "tus", read: "git stat") == "us")
        #expect(SuggestionCaptureFeed.unechoed(after: "git sta", typed: "tus", read: "git sta") == "tus")
        #expect(SuggestionCaptureFeed.unechoed(after: "git sta", typed: "tus", read: "git stash pop") == nil)
        #expect(SuggestionCaptureFeed.unechoed(after: "git sta", typed: "tus", read: "git st") == nil)
    }

    @Test("a Return learns the read line and lets go of the line the last keystroke handed")
    func returnLearnsTheLineAndClearsTheHandedLine() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }

        _ = await Self.read(
            Self.field("first", value: "hello wor"), into: fixture.feed, because: .keystroke, after: 0)
        #expect(fixture.feed.handed?.line == "hello wor")
        let reading = await Self.read(
            Self.field("first", value: "hello world"), into: fixture.feed, because: .returnPressed,
            after: 1)

        #expect(fixture.feed.handed == nil)
        #expect(try await fixture.learned(in: reading) == ["hello world"])
    }

    @Test("a Return in another field than the handed line's learns only what that field reads")
    func returnIgnoresALineHandedInAnotherField() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let other = SuggestionMoment.reading(of: Self.field("other", value: "elsewhere"))
        fixture.feed.handed = ("elsewhere", other)

        let reading = await Self.read(
            Self.field("first", value: "sent"), into: fixture.feed, because: .returnPressed, after: 0)

        #expect(fixture.feed.handed == nil)
        #expect(try await fixture.learned(in: reading) == ["sent"])
    }

    @Test("leaving an application with no field read forgets the handed line and finishes nothing")
    func leavingWithoutAReadClearsTheHandedLine() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let reading = SuggestionMoment.reading(of: Self.field("first", value: "draft"))
        fixture.feed.handed = ("draft", reading)
        fixture.feed.queue("s")

        fixture.feed.leaveApplication(at: Self.moment)
        await fixture.feed.waitForPreviousField()

        #expect(fixture.feed.handed == nil)
        #expect(fixture.feed.lastReading == nil)
        #expect(try await fixture.learned(in: reading).isEmpty)
    }

    @Test("discarding drops the queued keys and the pending insertion before the next field is read")
    func discardDropsKeysAndInsertion() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = await Self.read(
            Self.field("first", value: "old field line"), into: fixture.feed, because: .keystroke, after: 0)
        fixture.feed.queue("x")
        fixture.feed.noteInsertion()

        fixture.feed.discard()
        _ = await Self.read(
            Self.field("second", value: ""), into: fixture.feed, because: .keystroke, after: 1)

        #expect(try await fixture.learned(in: first) == ["old field line"])
    }

    @Test("a pending insertion read on a keystroke keeps the field's line from being learned")
    func insertionOnAKeystrokeIsNotLearned() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        _ = await Self.read(
            Self.field("first", value: "typed"), into: fixture.feed, because: .keystroke, after: 0)
        fixture.feed.noteInsertion()
        let first = await Self.read(
            Self.field("first", value: "typed and pasted"), into: fixture.feed, because: .keystroke,
            after: 1)

        _ = await Self.read(
            Self.field("second", value: ""), into: fixture.feed, because: .keystroke, after: 2)

        #expect(try await fixture.learned(in: first).isEmpty)
    }

    @Test("a tick holds a pending insertion for the next keystroke read rather than spending it")
    func tickKeepsThePendingInsertion() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        _ = await Self.read(
            Self.field("first", value: "typed"), into: fixture.feed, because: .keystroke, after: 0)
        fixture.feed.noteInsertion()
        _ = await Self.read(
            Self.field("first", value: "typed and pasted"), into: fixture.feed, because: .tick, after: 1)
        let first = await Self.read(
            Self.field("first", value: "typed and pasted"), into: fixture.feed, because: .keystroke,
            after: 2)

        _ = await Self.read(
            Self.field("second", value: ""), into: fixture.feed, because: .keystroke, after: 3)

        #expect(try await fixture.learned(in: first).isEmpty)
    }

    @Test("keys that overflowed in the same field mark its line inserted on a tick")
    func overflowOnATickMarksTheLineInserted() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        _ = await Self.read(
            Self.field("first", value: "typed"), into: fixture.feed, because: .keystroke, after: 0)
        for _ in 0...CaptureTypingRouter.maximumKeys { fixture.feed.queue("x") }
        let first = await Self.read(
            Self.field("first", value: "typed then much more"), into: fixture.feed, because: .tick, after: 1)

        _ = await Self.read(
            Self.field("second", value: ""), into: fixture.feed, because: .keystroke, after: 2)

        #expect(try await fixture.learned(in: first).isEmpty)
    }

    @Test("keys that overflowed alongside a pending insertion keep a keystroke's line from being learned")
    func overflowWithAnInsertionOnAKeystrokeIsNotLearned() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        _ = await Self.read(
            Self.field("first", value: "typed"), into: fixture.feed, because: .keystroke, after: 0)
        fixture.feed.noteInsertion()
        for _ in 0...CaptureTypingRouter.maximumKeys { fixture.feed.queue("x") }
        let first = await Self.read(
            Self.field("first", value: "typed then pasted"), into: fixture.feed, because: .keystroke,
            after: 1)

        _ = await Self.read(
            Self.field("second", value: ""), into: fixture.feed, because: .keystroke, after: 2)

        #expect(try await fixture.learned(in: first).isEmpty)
    }

    @Test("a password field read in the field already read finishes nothing and forgets the reading")
    func secureReadInTheSameFieldFinishesNothing() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = await Self.read(
            Self.field("first", value: "hello world"), into: fixture.feed, because: .keystroke, after: 0)

        await fixture.feed.finishBeforeSecureRead(first, at: Self.moment.addingTimeInterval(1))

        #expect(fixture.feed.lastReading == nil)
        #expect(fixture.feed.handed == nil)
        #expect(try await fixture.learned(in: first).isEmpty)
    }
}
