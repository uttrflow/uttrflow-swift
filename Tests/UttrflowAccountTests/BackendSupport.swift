// Test doubles for the backend: a scripted transport, canned responses, and stub loopback listeners.

import Foundation
import Synchronization
import UttrflowCore

@testable import UttrflowAccount

/// A backend that answers from a closure and remembers what it is asked.
final class StubTransport: BackendTransport {
    /// Answers a request, given the count before it; `nil` means no network, which is never a refusal.
    typealias Handler = @Sendable (_ request: BackendRequest, _ attempt: Int) -> BackendResponse?

    /// The script every request is answered from.
    private let handler: Handler
    /// Every request performed, in order.
    private let seen = Mutex<[BackendRequest]>([])

    /// Wraps `handler`.
    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [BackendRequest] { seen.withLock { $0 } }

    /// Every request that went to a path ending in `suffix`, in order.
    func requests(to suffix: String) -> [BackendRequest] {
        requests.filter { $0.url.path().hasSuffix(suffix) }
    }

    /// Records the request and answers it from the script, throwing when the script answers `nil`.
    func perform(_ request: BackendRequest) async throws(BackendUnreachable) -> BackendResponse {
        let attempt = seen.withLock { seen -> Int in
            seen.append(request)
            return seen.count - 1
        }
        guard let response = handler(request, attempt) else {
            throw BackendUnreachable(url: request.url, reason: "no network in this test")
        }
        return response
    }
}

/// Canned responses in the shapes the backend sends.
enum Stub {
    /// The API root, a file URL so nothing reaches a network by accident.
    static let baseURL = URL(fileURLWithPath: "/").appending(path: "x")

    /// A JSON response, as the backend would send one.
    static func json(_ value: some Encodable, status: Int = 200, etag: String? = nil) -> BackendResponse {
        var headers = ["Content-Type": "application/json"]
        // Not "ETag": a proxy re-cases header names, so the service must not depend on the spelling.
        if let etag { headers["etag"] = etag }
        return BackendResponse(
            status: status, headers: headers,
            body: (try? JSONEncoder().encode(value)) ?? Data())
    }

    /// A refusal in the backend's own error shape.
    static func problem(_ status: Int, message: String) -> BackendResponse {
        BackendResponse(
            status: status, headers: [:],
            body: Data(#"{"error":"nope","message":"\#(message)"}"#.utf8))
    }

    /// What `/v1/auth/{provider}/start` sends back.
    struct StartedSignIn: Encodable {
        var authorisationUrl = "https://accounts.google.example/authorise?state=abc"
        var state = "the-state"
        var claimToken = "the-claim-token"
        var usesFormPost = false
        var isDevelopmentStub = false
    }

    /// What `/v1/auth/device/code` sends back, in RFC 8628's own names.
    struct StartedDevice: Encodable {
        var deviceCode = "the-device-code"
        var userCode = "BCDF-GHJK"
        var verificationURI = "https://api.uttrflow.test/v1/auth/device"
        var verificationURIComplete = "https://api.uttrflow.test/v1/auth/device?user_code=BCDF-GHJK"
        var expiresIn = 900
        var interval = 5

        // The RFC's snake_case names on the wire, so the properties can keep the lint rule's spelling.
        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case verificationURIComplete = "verification_uri_complete"
            case expiresIn = "expires_in"
            case interval
        }
    }

    /// A refusal in the OAuth shape, where the code is the thing a client reads.
    static func oauthProblem(_ code: String, _ description: String) -> BackendResponse {
        BackendResponse(
            status: 400, headers: [:],
            body: Data(#"{"error":"\#(code)","error_description":"\#(description)"}"#.utf8))
    }

    /// What `/v1/auth/token` and `/v1/auth/refresh` send back.
    struct IssuedSession: Encodable {
        var accessToken = "access.token.one"
        var accessTokenExpiresAt = "2099-01-01T00:00:00.000Z"
        var refreshToken = "refresh-token-one"
        var refreshTokenExpiresAt = "2099-01-01T00:00:00.000Z"
        var tokenType = "Bearer"
    }
}

extension BackendRequest {
    /// The body as the JSON object it is, for a test that wants to look inside it.
    var jsonBody: [String: Any] {
        guard let body,
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return [:] }
        return object
    }
}

/// A loopback listener that never binds a socket, the one part of sign-in a test cannot exercise.
final class StubLoopbackListener: LoopbackListening {
    /// What the browser brings back, or `nil` to never answer.
    private let callback: LoopbackCallback?
    /// What `bind()` throws, or `nil` to bind successfully.
    private let bindFailure: AccountError?
    /// How far the flow has got: bound, closed, and how often awaited.
    private let state = Mutex(Progress())

    /// The listener's progress through one sign-in.
    private struct Progress {
        /// Whether `bind()` ran.
        var bound = false
        /// Whether `close()` ran.
        var closed = false
        /// How many times `awaitCallback()` ran.
        var awaited = 0
    }

    /// A listener answering `callback`, or failing to bind with `bindFailure`.
    init(returning callback: LoopbackCallback?, failingToBind bindFailure: AccountError? = nil) {
        self.callback = callback
        self.bindFailure = bindFailure
    }

    var wasBound: Bool { state.withLock { $0.bound } }
    var wasClosed: Bool { state.withLock { $0.closed } }
    var timesAwaited: Int { state.withLock { $0.awaited } }

    /// A fixed port: the test only cares that whatever binds is what the backend is told.
    static let redirectURI = safeURL("http://127.0.0.1:49152/callback")

    /// Throws `bindFailure` if set, else records the bind and returns the fixed address.
    func bind() async throws(AccountError) -> URL {
        if let bindFailure { throw bindFailure }
        state.withLock { $0.bound = true }
        return Self.redirectURI
    }

    /// Returns the scripted callback, or refuses when there is none.
    func awaitCallback() async throws(AccountError) -> LoopbackCallback {
        state.withLock { $0.awaited += 1 }
        guard let callback else {
            throw .providerRefused(description: "that sign-in did not come back")
        }
        return callback
    }

    /// Records the close.
    func close() async {
        state.withLock { $0.closed = true }
    }
}

/// A listener that cannot bind, standing in for a Mac whose security software refuses to let an app listen.
final class UnbindableListener: LoopbackListening {
    /// Always throws.
    func bind() async throws(AccountError) -> URL { throw .serverUnreachable }

    /// Always throws.
    func awaitCallback() async throws(AccountError) -> LoopbackCallback {
        throw .serverUnreachable
    }

    /// Nothing to close.
    func close() async {}
}
