public import Foundation

/// One request, as a value.
///
/// The whole point of describing a request rather than making one: everything worth
/// getting wrong — which path, which query, which header, what body — is decided here,
/// in code a test can read, and the only thing left for the network layer is to put the
/// bytes on the wire. That is what keeps ``BackendCorpusClient`` testable with no
/// backend, and what keeps the single `URLSession` in this project down to a file small
/// enough to review by eye.
public struct HTTPRequest: Sendable, Equatable {
    public enum Method: String, Sendable, Equatable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }

    public let method: Method
    public let url: URL
    /// Header names are compared case-insensitively by HTTP but not by `Dictionary`, so
    /// they are written in canonical form here and never assembled from user input.
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

    /// The body as a person would read it in a terminal, trimmed so a stray HTML error
    /// page from a proxy does not fill the screen.
    public var text: String {
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count <= 400 ? text : String(text.prefix(400)) + "…"
    }
}

/// The only way anything in this module reaches the network.
///
/// A protocol rather than a `URLSession` because the corpus is roughly a thousand
/// recordings in a private bucket: a test that needed either the bucket or the backend
/// would be a test nobody could run, and a harness whose own tests need the thing it is
/// measuring is not a harness anybody trusts. The conformance that actually opens a
/// socket lives in the `uttrflow-eval` executable, which nothing else links.
public protocol HTTPTransport: Sendable {
    /// Non-throwing on the HTTP status: a 404 or a 501 is an answer, not an error, and
    /// the caller has different things to say about each. Only a connection that could
    /// not be made at all throws.
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
