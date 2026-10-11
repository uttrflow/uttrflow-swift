import Foundation
import Testing
import UttrflowAI
import UttrflowAccount
import UttrflowCore
import UttrflowPipeline

@testable import Uttrflow

/// Ordinary words marked secret exercise the boundary independently of credential-shape detection.
@MainActor
@Suite("Secret snippet telemetry and failure messages")
struct SecretSnippetTelemetryTests {
    private let secret = "Cobalt meadow"
    private let trigger = "my passphrase"

    private func expanded() -> String {
        let snippet = Snippet(
            trigger: trigger, expansion: secret, created: .distantPast, isSecret: true)
        let result = SnippetExpander(snippets: [snippet], in: nil).expand(trigger)
        #expect(result.text == secret)
        #expect(result.usedSnippetIDs == [snippet.id])
        return result.text
    }

    @Test("successful insertion sends counts without the expanded words or trigger")
    func successfulInsertion() async throws {
        let text = expanded()
        let sender = RecordingTelemetrySender()
        let usage = UsageTelemetry(isEnabled: true, sender: sender, version: "26.1011.0")
        usage.observe(
            .inserted(DictationOutcome(text: text, method: .accessibility, cleanedBy: .rules)),
            language: LanguageCode("en"))
        await usage.flushBeforeQuitting()

        let report = try #require(sender.reports.first)
        #expect(sender.reports.count == 1)
        #expect(report.dictationCount == 1)
        #expect(report.failureCount == 0)
        #expect(report.charactersInserted == text.count)
        try expectNoWords(in: report)
    }

    @Test("every insertion failure keeps salvaged words out of messages and ingest bytes")
    func failedInsertion() async throws {
        let text = expanded()
        let errors: [TextInsertionError] = [
            .noFocusedTextField, .accessibilityDenied, .clipboardUnavailable, .clipboardChanged,
            .insertionTimedOut, .insertionRejected(description: text), .insertionCancelled,
            .insertionUnconfirmed, .insertionTargetChanged, .insertionFieldClosed,
            .insertionNeedsCopy(description: text), .insertionInterrupted(typed: 2, total: text.count),
        ]
        for error in errors { try await expectFailedReport(for: error, text: text) }
        // An unforeseen backend failure can carry words in its localized description, too.
        try await expectFailedReport(
            for: NSError(
                domain: "synthetic.insertion", code: 1,
                userInfo: [NSLocalizedDescriptionKey: text]), text: text)
    }

    private func expectFailedReport(for error: any Error, text: String) async throws {
        let notice = DictationFailure(error, transcript: text)
        #expect(notice.transcript == text)
        #expect(!notice.message.contains(secret))
        #expect(!notice.cause.contains(secret))
        #expect(!notice.offeringRetry(of: UUID()).message.contains(secret))
        #expect(!ErrorLog.failure(error).contains(secret))
        let sender = RecordingTelemetrySender()
        let usage = UsageTelemetry(isEnabled: true, sender: sender, version: "26.1011.0")
        usage.observe(.failed(notice), language: LanguageCode("en"))
        await usage.flushBeforeQuitting()

        let report = try #require(sender.reports.first)
        #expect(sender.reports.count == 1)
        #expect(report.dictationCount == 1)
        #expect(report.failureCount == 1)
        #expect(report.charactersInserted == 0)
        try expectNoWords(in: report)
    }

    private func expectNoWords(in report: TelemetryReport) throws {
        // This is the exact serializer HTTPTelemetrySender uses, rather than a test-only encoding.
        let bytes = try #require(report.encodedForIngest())
        let json = try #require(String(data: bytes, encoding: .utf8))
        #expect(!json.contains(secret))
        #expect(!json.contains(trigger))
    }
}
