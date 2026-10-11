// The hub client every model download goes through, and the two things it refuses to do.

import Foundation
import HuggingFace
import Synchronization
import UttrflowCore

/// The client model downloads use: nobody's token, and huggingface.co whatever the environment says. See `Docs/predict-llm.md`.
enum AnonymousHub {
    /// A client that sends no `Authorization` header and reads no `HF_ENDPOINT`.
    static func client() -> HubClient {
        // Both named rather than defaulted: `HubClient()` resolves a token and follows HF_ENDPOINT.
        HubClient(
            session: session(),
            host: HubClient.defaultHost,
            tokenProvider: .none)
    }

    static func session(
        ledger: NetworkActivityLedger = .shared,
        configuration: URLSessionConfiguration = .ephemeral
    ) -> URLSession {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(
            configuration: configuration,
            delegate: ModelRequestCounter(ledger: ledger),
            delegateQueue: nil)
    }
}

/// Immutable state lets Foundation deliver task callbacks on its delegate queue.
private final class ModelRequestCounter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let ledger: NetworkActivityLedger

    init(ledger: NetworkActivityLedger) {
        self.ledger = ledger
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        ledger.record(.modelDownload)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        ledger.record(.modelDownload)
        completionHandler(request)
    }
}
