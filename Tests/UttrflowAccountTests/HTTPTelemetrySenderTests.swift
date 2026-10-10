// Tests for HTTPTelemetrySender: what it posts, where, and how each answer is read.

import Foundation
import Synchronization
import Testing

@testable import UttrflowAccount

/// Drives the sender through a scripted transport, so no report reaches a network.
@Suite("Posting telemetry to the backend")
struct HTTPTelemetrySenderTests {
    /// A report with a dictation in it.
    private func aReport() throws -> TelemetryReport {
        try #require(Telemetry.report(dictationCount: 3, languages: [.english: 3]))
    }

    /// A transport that answers every request with `status`.
    private func answering(_ status: Int) -> StubTransport {
        StubTransport { _, _ in BackendResponse(status: status) }
    }

    @Test("posts the ingest encoding to v1/telemetry as JSON")
    func postsTheIngestEncoding() async throws {
        let transport = answering(202)
        let report = try aReport()
        try await HTTPTelemetrySender(baseURL: Stub.baseURL, transport: transport).send(report)

        let request = try #require(transport.requests.first)
        #expect(transport.requests.count == 1)
        #expect(request.method == .post)
        #expect(request.url == Stub.baseURL.appending(path: "v1/telemetry"))
        #expect(request.headers["Content-Type"] == "application/json")
        // Compared as objects, since JSONEncoder does not promise key order between two encodes.
        #expect(
            NSDictionary(dictionary: request.jsonBody)
                == NSDictionary(dictionary: Telemetry.encodedObject(report)))
    }

    @Test("sends anonymously when there is no token, and signed in when there is one")
    func carriesTheTokenWhenThereIsOne() async throws {
        let anonymous = answering(202)
        try await HTTPTelemetrySender(baseURL: Stub.baseURL, transport: anonymous).send(aReport())
        #expect(anonymous.requests.first?.headers["Authorization"] == nil)

        let signedIn = answering(202)
        let sender = HTTPTelemetrySender(
            baseURL: Stub.baseURL, transport: signedIn, bearer: { "the-token" })
        try await sender.send(aReport())
        #expect(signedIn.requests.first?.headers["Authorization"] == "Bearer the-token")
    }

    @Test("a refusal carries the server's status", arguments: [400, 401, 500])
    func aRefusalCarriesTheStatus(status: Int) async throws {
        let sender = HTTPTelemetrySender(baseURL: Stub.baseURL, transport: answering(status))
        let report = try aReport()
        await #expect(throws: TelemetryError.refused(status: status)) { try await sender.send(report) }
    }

    @Test("no answer at all is unreachable, never a refusal")
    func noAnswerIsUnreachable() async throws {
        let sender = HTTPTelemetrySender(
            baseURL: Stub.baseURL, transport: StubTransport { _, _ in nil })
        let report = try aReport()
        await #expect(throws: TelemetryError.unreachable) { try await sender.send(report) }
    }

    @Test("a service flushing through it leaves the report queued while offline and sends it after")
    func flushesThroughTheService() async throws {
        let online = Mutex(false)
        let transport = StubTransport { _, _ in
            online.withLock { $0 } ? BackendResponse(status: 202) : nil
        }
        let service = TelemetryService(
            collector: Telemetry.collector(),
            sender: HTTPTelemetrySender(baseURL: Stub.baseURL, transport: transport))
        service.recorder.recordDictation(.completed, language: .english, processing: .milliseconds(300))

        await service.flush(at: Telemetry.anHourLater)
        #expect(service.pendingReports.count == 1)

        online.withLock { $0 = true }
        await service.flush(at: Telemetry.anHourLater.addingTimeInterval(1))
        #expect(service.pendingReports.isEmpty)
        #expect(service.sentReports.count == 1)
    }

    @Test("cancellation while resolving the bearer does not send or acknowledge a report")
    func cancellationDuringBearerResolutionKeepsReportQueued() async throws {
        let (bearerStarted, signalBearerStarted) = AsyncStream<Void>.makeStream()
        let (bearerGate, releaseBearer) = AsyncStream<String?>.makeStream()
        let transport = answering(202)
        let sender = HTTPTelemetrySender(
            baseURL: Stub.baseURL, transport: transport,
            bearer: {
                signalBearerStarted.yield(())
                for await token in bearerGate { return token }
                return nil
            })
        let service = TelemetryService(collector: Telemetry.collector(), sender: sender)
        service.recorder.recordDictation(.completed, language: .english, charactersInserted: 5)
        let flush = Task { await service.flush(at: Telemetry.anHourLater) }

        for await _ in bearerStarted { break }
        flush.cancel()
        releaseBearer.yield("old-account-token")
        await flush.value

        #expect(transport.requests.isEmpty)
        #expect(service.pendingReports.count == 1)
        #expect(service.sentReports.isEmpty)
    }

    @Test("the account service hands over its access token only while signed in")
    func theAccessTokenFollowsTheSession() async {
        let transport = StubTransport { _, _ in Stub.json(Stub.IssuedSession()) }
        let signedOut = HTTPAuthenticationService(
            baseURL: Stub.baseURL, transport: transport, tokens: InMemoryTokenStore())
        #expect(await signedOut.accessTokenIfSignedIn() == nil)

        let signedIn = HTTPAuthenticationService(
            baseURL: Stub.baseURL, transport: transport,
            tokens: InMemoryTokenStore(refreshToken: "refresh-token-one"))
        #expect(await signedIn.accessTokenIfSignedIn() == "access.token.one")
    }
}
