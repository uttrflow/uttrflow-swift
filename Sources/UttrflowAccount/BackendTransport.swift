// The request and response values, and the protocol that carries them to the backend.
public import struct Foundation.Data
public import struct Foundation.URL

/// One request as a value, so every decision worth getting wrong is in code a test can read.
public struct BackendRequest: Sendable, Equatable {
    /// The HTTP method.
    public enum Method: String, Sendable, Equatable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    /// The HTTP method.
    public let method: Method
    /// Where it goes.
    public let url: URL
    /// Written in canonical form here and never assembled from anything a user typed.
    public let headers: [String: String]
    /// The body, if any.
    public let body: Data?

    /// A request with no headers and no body unless given.
    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// What the server answered, whatever the status.
public struct BackendResponse: Sendable, Equatable {
    /// The HTTP status.
    public let status: Int
    /// The response headers as the server sent them.
    public let headers: [String: String]
    /// The body, possibly empty.
    public let body: Data

    /// A response with no headers and an empty body unless given.
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// Whether the status is 2xx.
    public var isSuccess: Bool { (200..<300).contains(status) }

    /// A header, found without caring how the server capitalised it.
    public func header(_ name: String) -> String? {
        let wanted = name.lowercased()
        return headers.first { $0.key.lowercased() == wanted }?.value
    }
}

/// The only way this module reaches the network; a protocol, so sign-in is tested without a server.
public protocol BackendTransport: Sendable {
    /// Throws only when no connection could be made; every status, `404` and `502` included, is an answer.
    func perform(_ request: BackendRequest) async throws(BackendUnreachable) -> BackendResponse
}

/// The request did not happen. Anything the server said is a ``BackendResponse``.
public struct BackendUnreachable: Error, Sendable, Equatable, CustomStringConvertible {
    /// The address that could not be reached.
    public let url: URL
    /// What the system said.
    public let reason: String

    /// Names the address and the system's reason.
    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }

    public var description: String { "could not reach \(url.absoluteString): \(reason)" }
}
