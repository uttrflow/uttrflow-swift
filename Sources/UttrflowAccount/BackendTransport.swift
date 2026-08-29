public import struct Foundation.Data
public import struct Foundation.URL

/// One request to the backend, as a value.
///
/// Describing a request rather than making one is what keeps every decision worth getting
/// wrong — which path, which header, what body — in code a test can read, and leaves the
/// network layer with nothing to do but put bytes on a wire. It is the same bargain
/// ``UttrflowEval``'s `HTTPTransport` makes, and a near-twin of it for the same reason
/// ``SessionStorage`` is a near-twin of `KeyValueStore`: this module cannot import that
/// one. The honest home for both is ``UttrflowCore``.
public struct BackendRequest: Sendable, Equatable {
    public enum Method: String, Sendable, Equatable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    public let method: Method
    public let url: URL
    /// Written in canonical form here and never assembled from anything a user typed.
    public let headers: [String: String]
    public let body: Data?

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct BackendResponse: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }

    /// A header, found without caring how the server capitalised it.
    public func header(_ name: String) -> String? {
        let wanted = name.lowercased()
        return headers.first { $0.key.lowercased() == wanted }?.value
    }
}

/// The only way this module reaches the network.
///
/// A protocol, so that the whole of sign-in — the polling, the rotation, the four ways a
/// server can say no — is driven from tests with no server anywhere near them. The
/// conformance that opens a socket is ``URLSessionTransport``, which is small enough that
/// reading it is a sufficient review.
public protocol BackendTransport: Sendable {
    /// Non-throwing on the status: a `404` and a `502` are answers with different meanings
    /// and the caller has something different to say about each. Only a connection that
    /// could not be made at all throws — which is the one failure that must never be
    /// mistaken for "the server said no", because the app carries on offline and does not
    /// carry on when it has been refused.
    func perform(_ request: BackendRequest) async throws(BackendUnreachable) -> BackendResponse
}

/// The request did not happen. Anything the server said is a ``BackendResponse``.
public struct BackendUnreachable: Error, Sendable, Equatable, CustomStringConvertible {
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }

    public var description: String { "could not reach \(url.absoluteString): \(reason)" }
}
