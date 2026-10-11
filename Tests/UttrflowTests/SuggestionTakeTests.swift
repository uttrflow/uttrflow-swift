import Foundation
import Testing
import UttrflowContext
import UttrflowCore
import UttrflowInput
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore

@testable import Uttrflow

@MainActor
@Suite("Taking an accepted suggestion into the field")
struct SuggestionTakeTests {
    private static let application = "com.example.editor"

    /// The lines capture was told to keep.
    private actor Lines: CaptureSink {
        private(set) var texts: [String] = []
        private(set) var accepted: [String] = []

        func record(
            _ text: String, in surface: Surface, after previous: String?, as origin: LineOrigin, at moment: Date
        ) {
            texts.append(text)
        }

        func supersede(_ text: String, with replacement: String, in surface: Surface) {}

        func recordAccepted(_ text: String, in surface: Surface) { accepted.append(text) }
    }

    /// What the fake insertion was asked to do, and what it answers.
    private final class Insertion {
        var calls: [(suggestion: Suggestion, typed: String, window: UInt32)] = []
        var failure: TextInsertionError?
        var trustLosses = 0
    }

    @MainActor
    private struct Fixture {
        let container: URL
        let lines = Lines()
        let acceptances = AcceptanceQueue()
        let insertion = Insertion()
        let take: SuggestionTake

        init() async throws {
            container = FileManager.default.temporaryDirectory
                .appending(path: "suggestion-take-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            let capture = CaptureSession(
                sink: lines,
                preferencesFile: CapturePreferencesFile(
                    path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false)),
                policy: .whereReturnSends)
            try await capture.record(.allowed, for: SuggestionTakeTests.application)
            let insertion = insertion
            take = SuggestionTake(
                insert: { suggestion, typed, window throws(TextInsertionError) in
                    insertion.calls.append((suggestion, typed, window))
                    if let failure = insertion.failure { throw failure }
                    return .accessibility
                },
                acceptances: acceptances, capture: capture,
                trustLost: { insertion.trustLosses += 1 })
        }

        func remove() { try? FileManager.default.removeItem(at: container) }
    }

    private static func reading(window: UInt32?) -> FieldReading {
        SuggestionMoment.reading(
            of: FocusedFieldSnapshot(
                bundleIdentifier: application, applicationName: "Editor", role: "AXTextField",
                identifier: "body", value: "git c", selection: NSRange(location: 5, length: 0),
                windowNumber: window))
    }

    @Test("a field with no identifiable window is refused before anything is written")
    func unidentifiedWindowIsRefused() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }

        let outcome = await fixture.take.take(
            "ommit", after: "git c", in: Self.reading(window: nil), closingPunctuation: "")
        let withoutReading = await fixture.take.take(
            "ommit", after: "git c", in: nil, closingPunctuation: "")

        #expect(outcome == .refused)
        #expect(withoutReading == .refused)
        #expect(fixture.insertion.calls.isEmpty)
    }

    @Test("an insertion goes to the drawn field's window and its line is queued for capture")
    func insertionIsQueuedForCapture() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let reading = Self.reading(window: 42)

        let outcome = await fixture.take.take(
            "git commit", after: "git c", in: reading, closingPunctuation: "")
        await fixture.acceptances.drained()

        #expect(outcome == .inserted)
        #expect(fixture.insertion.calls.count == 1)
        #expect(fixture.insertion.calls.first?.typed == "git c")
        #expect(fixture.insertion.calls.first?.window == 42)
        #expect(fixture.insertion.trustLosses == 0)
        #expect(await fixture.lines.texts == ["git commit"])
        #expect(await fixture.lines.accepted == ["git commit"])
    }

    @Test("a refusal for lost accessibility trust tells the activation monitor and learns nothing")
    func lostTrustIsReported() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        fixture.insertion.failure = .accessibilityDenied
        let reading = Self.reading(window: 42)

        let outcome = await fixture.take.take(
            "git commit", after: "git c", in: reading, closingPunctuation: "")
        await fixture.acceptances.drained()

        #expect(outcome == .refused)
        #expect(fixture.insertion.trustLosses == 1)
        #expect(await fixture.lines.texts.isEmpty)
    }

    @Test("an unconfirmed write may have landed, so it is reported as uncertain and learns nothing")
    func unconfirmedWriteIsUncertain() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        fixture.insertion.failure = .insertionUnconfirmed
        let reading = Self.reading(window: 42)

        let outcome = await fixture.take.take(
            "git commit", after: "git c", in: reading, closingPunctuation: "")
        await fixture.acceptances.drained()

        #expect(outcome == .mayHaveWritten)
        #expect(fixture.insertion.trustLosses == 0)
        #expect(await fixture.lines.texts.isEmpty)
    }
}
