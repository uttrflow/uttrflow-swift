import Foundation
import Testing

@testable import UttrflowAccount

/// Posts real bytes to a running backend; unit tests on either side cannot see a key the other refuses.
@Suite(
    "The contract with uttrflow-backend's telemetry ingest",
    .enabled(if: LiveBackend.isConfigured, LiveBackend.absenceReason))
struct TelemetryBackendContractTests {
    /// Where telemetry is posted; no default, so `.enabled(if:)` reports an absent backend as a skip.
    private static var endpoint: URL? {
        LiveBackend.url?.appending(path: "v1/telemetry")
    }

    /// Posts `body` and answers the status and body, or `nil` when nothing answers.
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

    /// The strictness refuses a transcript rather than storing it, so the privacy line holds on both sides.
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
