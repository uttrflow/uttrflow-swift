import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowLocalModel

private final class ModelFileProtocol: URLProtocol, @unchecked Sendable {
    private static let requests = Mutex(0)

    static var requestCount: Int { requests.withLock { $0 } }

    static func reset() { requests.withLock { $0 = 0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.withLock { $0 += 1 }
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([1]))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Anonymous Hub request accounting")
struct AnonymousHubTests {
    @Test("counts each file request in a multi-file model download")
    func countsEveryFileTask() async throws {
        ModelFileProtocol.reset()
        let ledger = NetworkActivityLedger(file: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelFileProtocol.self]
        let session = AnonymousHub.session(ledger: ledger, configuration: configuration)

        for file in ["config.json", "weights.safetensors"] {
            let url = try #require(URL(string: "https://huggingface.co/model/\(file)"))
            _ = try await session.data(from: url)
        }
        session.invalidateAndCancel()

        let tally = ledger.activity().tallies(at: Date())[.modelDownload]
        #expect(ModelFileProtocol.requestCount == 2)
        #expect(tally?.count == 2)
    }
}

@Suite("Anonymous Hub client and delegate")
struct AnonymousHubDelegateTests {
    @Test("the client is built without reading a token or the environment")
    func clientIsBuilt() {
        _ = AnonymousHub.client()
    }

    @Test("a created task and a redirect are each recorded as a model download")
    func delegateRecordsTasksAndRedirects() async throws {
        let ledger = NetworkActivityLedger(file: nil)
        let session = AnonymousHub.session(ledger: ledger)
        let delegate = try #require(session.delegate as? (any URLSessionTaskDelegate))
        let url = try #require(URL(string: "https://huggingface.co/model/config.json"))
        let task = session.dataTask(with: url)
        delegate.urlSession?(session, didCreateTask: task)
        let response = try #require(
            HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil))
        let followed = await withCheckedContinuation { continuation in
            delegate.urlSession?(
                session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: url)
            ) { continuation.resume(returning: $0) }
        }
        session.invalidateAndCancel()
        #expect(followed?.url == url)
        #expect(ledger.activity().tallies(at: Date())[.modelDownload]?.count == 3)
    }
}
