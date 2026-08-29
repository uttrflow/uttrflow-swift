import Foundation
import Synchronization
import UttrflowCore

@testable import UttrflowAccount

/// A backend that answers from a closure, and remembers what it was asked.
///
/// The whole of ``HTTPAuthenticationService`` is four HTTP calls and the rules it keeps
/// between them, so a transport that a test can script is the difference between testing
/// those rules and testing a server.
final class StubTransport: BackendTransport, @unchecked Sendable {
    /// - Parameters:
    ///   - request: What was asked.
    ///   - attempt: How many requests have already been made, so a test can answer the
    ///     first `claim` with `404` and the third with a session.
    /// - Returns: The answer, or `nil` for a request that never happened at all — which is
    ///   how a missing network is spelled, and is never the same thing as a refusal.
    typealias Handler = @Sendable (_ request: BackendRequest, _ attempt: Int) -> BackendResponse?

    private let handler: Handler
    private let seen = Mutex<[BackendRequest]>([])

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [BackendRequest] { seen.withLock { $0 } }

    /// Every request that went to a path ending in `suffix`, in order.
    func requests(to suffix: String) -> [BackendRequest] {
        requests.filter { $0.url.path().hasSuffix(suffix) }
    }

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

enum Stub {
    static let baseURL = URL(fileURLWithPath: "/").appending(path: "x")

    /// A JSON response, as the backend would send one.
    static func json(_ value: some Encodable, status: Int = 200, etag: String? = nil) -> BackendResponse {
        var headers = ["Content-Type": "application/json"]
        // Deliberately not "ETag": HTTP header names are case-insensitive and a real proxy
        // will change them, so the tests use a spelling the service must not depend on.
        if let etag { headers["etag"] = etag }
        return BackendResponse(
            status: status, headers: headers,
            body: (try? JSONEncoder().encode(value)) ?? Data())
    }

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

        // The names on the wire are the RFC's, and snake_cased. Spelling them here rather
        // than in the property names keeps the lint rule and the specification both happy.
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

/// A loopback listener that never binds a socket.
///
/// Binding a port is the one part of sign-in a test cannot exercise, and it is deliberately
/// the only part behind this protocol: everything a test wants to say about the flow — what
/// went in the URL, what came back, what was refused — is on the other side of it.
final class StubLoopbackListener: LoopbackListening, @unchecked Sendable {
    /// What the browser will bring back, or `nil` to never answer.
    private let callback: LoopbackCallback?
    private let bindFailure: AccountError?
    private let state = Mutex(Progress())

    private struct Progress {
        var bound = false
        var closed = false
        var awaited = 0
    }

    init(returning callback: LoopbackCallback?, failingToBind bindFailure: AccountError? = nil) {
        self.callback = callback
        self.bindFailure = bindFailure
    }

    var wasBound: Bool { state.withLock { $0.bound } }
    var wasClosed: Bool { state.withLock { $0.closed } }
    var timesAwaited: Int { state.withLock { $0.awaited } }

    /// A fixed port, because the number is the operating system's business and the test's
    /// interest is only that whatever was bound is what the backend is told.
    static let redirectURI = safeURL("http://127.0.0.1:49152/callback")

    func bind() async throws(AccountError) -> URL {
        if let bindFailure { throw bindFailure }
        state.withLock { $0.bound = true }
        return Self.redirectURI
    }

    func awaitCallback() async throws(AccountError) -> LoopbackCallback {
        state.withLock { $0.awaited += 1 }
        guard let callback else {
            throw .providerRefused(description: "that sign-in did not come back")
        }
        return callback
    }

    func close() async {
        state.withLock { $0.closed = true }
    }
}

/// A listener that cannot bind, which is the situation the device grant exists for.
///
/// A Mac whose security software refuses to let an application listen cannot be arranged in
/// a test, so this stands in for one — and it is the only part of the end-to-end device
/// test that is not real.
final class UnbindableListener: LoopbackListening {
    func bind() async throws(AccountError) -> URL { throw .serverUnreachable }

    func awaitCallback() async throws(AccountError) -> LoopbackCallback {
        throw .serverUnreachable
    }

    func close() async {}
}
