import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("The guard accepts the written form of a spoken address in an Email field", .bug(id: 8365))
struct MeaningGuardEmailReferenceTests {
    private func verdict(_ spoken: String, _ written: String) async -> GuardVerdict {
        let app = AppContext(
            applicationName: "Mail", accessibilityRole: "AXTextField", isMultiline: false, fieldLabel: "Email"
        )
        let request = TransformationRequest(
            transcription: Transcription(text: spoken), context: app,
            situation: Situation(app: app, insertion: app.insertionPoint, destination: .email))
        return await MeaningPreservationGuard().verdict(onReference: written, for: request)
    }

    @Test(
        "the correct address is accepted",
        arguments: [
            ("ops dash team at example dot org", "ops-team@example.org"),
            ("info at example dot com", "info@example.com"),
            ("sam dot lee at example dot net", "sam.lee@example.net"),
        ])
    func accepted(spoken: String, written: String) async {
        let result = await verdict(spoken, written)
        #expect(result.isAccepted, "\(spoken) -> \(written): \(result)")
    }

    @Test("a changed local part or domain is still refused")
    func refused() async {
        #expect(await !verdict("info at example dot com", "help@example.com").isAccepted)
        #expect(await !verdict("info at example dot com", "info@example.org").isAccepted)
    }
}
