// Protects the load-bearing settings on URLSessionTransport's default session. See Docs/account-transport.md.
import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowAccount

/// Answers a scripted status for every request it sees, so a 304 can be produced without a socket.
final class ScriptedStatusProtocol: URLProtocol, @unchecked Sendable {
    /// The status the next request still gets; each request consumes one and repeats the last once empty.
    static let statuses = Mutex<[Int]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let status = Self.statuses.withLock { queue in
            queue.isEmpty ? 200 : queue.removeFirst()
        }
        guard
            let response = HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"), statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: [:])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The settings `Docs/account-transport.md` calls load-bearing, checked without a live backend.
@Suite("URLSessionTransport's default session")
struct URLSessionTransportTests {
    private var configuration: URLSessionConfiguration {
        URLSessionTransport.defaultSession().configuration
    }

    @Test("keeps no cache, so a 304 cannot be answered from a stored copy")
    func hasNoCache() {
        #expect(configuration.urlCache == nil)
    }

    @Test("ignores any local cache data that is still there")
    func ignoresLocalCache() {
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("times out a request after 20 seconds")
    func hasATwentySecondTimeout() {
        #expect(configuration.timeoutIntervalForRequest == 20)
    }

    @Test("fails fast on a dead network instead of waiting for connectivity")
    func doesNotWaitForConnectivity() {
        #expect(configuration.waitsForConnectivity == false)
    }

    /// The session under test carries the same cache settings `defaultSession()` does, plus the stub protocol.
    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.protocolClasses = [ScriptedStatusProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("passes a 304 the server sent straight through, not a synthesised 200")
    func passesA304Through() async throws {
        ScriptedStatusProtocol.statuses.withLock { $0 = [304] }
        let ledger = NetworkActivityLedger(file: nil)
        let transport = URLSessionTransport(session: stubbedSession(), ledger: ledger)

        let response = try await transport.perform(
            BackendRequest(method: .get, url: URL(fileURLWithPath: "/v1/profile"), purpose: .account))

        #expect(response == BackendResponse(status: 304))
        #expect(ledger.activity().tallies(at: Date())[.account]?.count == 1)
    }
}
