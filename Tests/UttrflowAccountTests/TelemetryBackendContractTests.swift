import Foundation
import Testing

@testable import UttrflowAccount

/// Checks the app against the running backend rather than against our idea of it.
///
/// The sibling suite `BackendContractTests` exists because the two sides once disagreed in
/// silence, each checking its own idea of the contract against itself. The same trap is set
/// here: `telemetryReportSchema` is `.strict()`, so a key the app invents is a 400 and a key
/// it forgets is a default — and unit tests on either side would pass throughout.
///
/// So this posts real bytes. It is skipped when nothing is listening, exactly as the
/// fixture-based suite is skipped when the backend is not checked out, which keeps the
/// suite green on a machine with no server and honest on one that has it. Point it
/// somewhere else with `UTTRFLOW_BACKEND_URL`.
@Suite(
    "The contract with uttrflow-backend's telemetry ingest",
    .enabled(if: LiveBackend.isConfigured, LiveBackend.absenceReason))
struct TelemetryBackendContractTests {
    /// Where telemetry is posted.
    ///
    /// This used to default to `http://127.0.0.1:8787` when the variable was unset, and
    /// that default is what made the suite dishonest: with nothing listening there the
    /// requests simply failed, both tests returned early, and both reported a pass. There
    /// is no default now — ``LiveBackend`` requires the variable, and `.enabled(if:)` above
    /// turns its absence into a reported skip.
    private static var endpoint: URL? {
        LiveBackend.url?.appending(path: "v1/telemetry")
    }

    /// - Returns: The status code, or `nil` when nothing answered.
    private func post(_ body: Data) async -> (status: Int, body: Data)? {
        guard let endpoint = Self.endpoint else { return nil }
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse
        else { return nil }
        return (http.statusCode, data)
    }

    /// The bytes the app would really send, judged by the server that really receives them.
    @Test("a report the app builds is accepted by the running backend")
    func theServerAcceptsWhatTheAppSends() async throws {
        let collector = Telemetry.collector()
        collector.recordDictation(
            .completed, language: .english, audio: .seconds(6), processing: .milliseconds(420),
            charactersInserted: 137)
        collector.recordDictation(.cancelled, language: .hindi, audio: .seconds(2))
        collector.recordDictation(.failed, language: .tamil, audio: .seconds(1))
        collector.record(.init(stage: .transcription, duration: .milliseconds(300), succeeded: true))
        collector.record(.init(stage: .insertion, duration: .milliseconds(9), succeeded: false))

        let report = try #require(collector.takeReport(endedAt: Telemetry.anHourLater))
        let body = try #require(report.encodedForIngest())
        let answer = try #require(
            await post(body),
            "UTTRFLOW_BACKEND_URL is set but nothing answered at \(Self.endpoint?.absoluteString ?? "it")")

        #expect(
            answer.status == 202,
            "backend refused a report the app built: \(String(decoding: answer.body, as: UTF8.self))")
    }

    /// The other half of the contract, and the reason the strictness is worth having: had
    /// the app put a transcript in the payload, it would be refused rather than stored.
    /// This is what makes the privacy line enforced on both sides instead of trusted on one.
    @Test("the backend refuses a payload with a field the schema does not know")
    func theServerRefusesAnythingExtra() async throws {
        let report = try #require(Telemetry.report(languages: [.english: 1]))
        let encoded = try #require(report.encodedForIngest())
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return }
        object["transcript"] = "the words somebody actually said"

        let body = try JSONSerialization.data(withJSONObject: object)
        let answer = try #require(
            await post(body),
            "UTTRFLOW_BACKEND_URL is set but nothing answered at \(Self.endpoint?.absoluteString ?? "it")")

        #expect(answer.status == 400)
        #expect(String(decoding: answer.body, as: UTF8.self).contains("unrecognized_keys"))
    }
}
