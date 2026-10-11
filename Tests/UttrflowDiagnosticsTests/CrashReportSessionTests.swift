import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowDiagnostics

private final class CrashEnvelopeProtocol: URLProtocol, @unchecked Sendable {
    private static let requests = Mutex(0)

    static var requestCount: Int { requests.withLock { $0 } }

    static func reset() { requests.withLock { $0 = 0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.withLock { $0 += 1 }
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if url.path == "/failure" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        guard
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([1]))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Crash report transport accounting")
struct CrashReportSessionTests {
    @Test("counts each envelope task once, including a failed request")
    func countsCreatedTasksAndFailures() async throws {
        CrashEnvelopeProtocol.reset()
        let ledger = NetworkActivityLedger(file: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CrashEnvelopeProtocol.self]
        let session = CrashReportSession.make(ledger: ledger, configuration: configuration)
        defer { session.invalidateAndCancel() }

        let success = try #require(URL(string: "https://sentry.invalid/envelope"))
        _ = try await session.data(from: success)
        let failure = try #require(URL(string: "https://sentry.invalid/failure"))
        do {
            _ = try await session.data(from: failure)
            Issue.record("the mock failed request unexpectedly succeeded")
        } catch {}

        let tally = ledger.activity().tallies(at: Date())[.crashReport]
        #expect(CrashEnvelopeProtocol.requestCount == 2)
        #expect(tally?.count == 2)
    }
}
