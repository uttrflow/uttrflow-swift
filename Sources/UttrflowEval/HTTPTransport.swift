public import Foundation

/// One request as a value, so everything worth getting wrong is decided in code a test can read.
public struct HTTPRequest: Sendable, Equatable {
    public enum Method: String, Sendable, Equatable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }

    public let method: Method
    public let url: URL
    /// Headers in canonical case, since HTTP compares names case-insensitively and `Dictionary` does not.
    public let headers: [String: String]
    public let body: Data?

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }

    /// The body as a person reads it in a terminal, trimmed so a proxy's HTML error page does not fill it.
    public var text: String {
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count <= 400 ? text : String(text.prefix(400)) + "…"
    }
}

/// The only way this module reaches the network; the socket-opening conformance lives in `uttrflow-eval`.
public protocol HTTPTransport: Sendable {
    /// Throws only when no connection can be made; a 404 or 501 is an answer the caller reads.
    func perform(_ request: HTTPRequest) async throws(HTTPTransportError) -> HTTPResponse
}

/// The connection did not happen. Anything the server said is an ``HTTPResponse``.
public struct HTTPTransportError: Error, Sendable, Equatable, CustomStringConvertible {
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }

    public var description: String { "could not reach \(url.absoluteString): \(reason)" }
}
