// Tests for where HTTPAuthenticationService.avatar(at:) sends its request and its bearer token.

import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowAccount

/// Fetches avatars against scripted backends at several API roots and checks every address used.
@Suite("Fetching the avatar")
struct AvatarAddressTests {
    /// The bytes every scripted avatar answers with.
    private static let picture = Data([0x89, 0x50, 0x4E, 0x47])

    /// A backend that issues a fresh access token per refresh and answers any avatar path with a picture.
    private func backend(rejectingFirstAvatar: Bool = false) -> StubTransport {
        let refreshes = Mutex(0)
        let avatars = Mutex(0)
        return StubTransport { request, _ in
            if request.url.path().hasSuffix("/v1/auth/refresh") {
                let count = refreshes.withLock { count -> Int in
                    count += 1
                    return count
                }
                return Stub.json(Stub.IssuedSession(accessToken: "access.token.\(count)"))
            }
            let count = avatars.withLock { count -> Int in
                count += 1
                return count
            }
            if rejectingFirstAvatar, count == 1 { return Stub.problem(401, message: "expired") }
            return BackendResponse(status: 200, headers: [:], body: Self.picture)
        }
    }

    /// A signed-in service against `root`.
    private func service(_ root: String, transport: StubTransport) throws -> HTTPAuthenticationService {
        HTTPAuthenticationService(
            baseURL: try #require(URL(string: root)), transport: transport,
            tokens: InMemoryTokenStore(refreshToken: "refresh-token-one"),
            verifier: Fixture.verifier, now: { Fixture.noon })
    }

    /// Whether `url` has the scheme, host and port of `root`.
    private func sameOrigin(_ url: URL, as root: String) -> Bool {
        guard let root = URL(string: root) else { return false }
        return url.scheme == root.scheme && url.host() == root.host() && url.port == root.port
    }

    @Test(
        "builds the address below the API root, with or without its trailing slash",
        arguments: [
            ("https://api.example.com", "/v1/me/avatar", "https://api.example.com/v1/me/avatar"),
            ("https://api.example.com/", "/v1/me/avatar", "https://api.example.com/v1/me/avatar"),
            (
                "https://api.example.com:8443/base", "/v1/me/avatar",
                "https://api.example.com:8443/base/v1/me/avatar"
            ),
            (
                "https://api.example.com/base/", "/v1/me/avatar?v=2",
                "https://api.example.com/base/v1/me/avatar?v=2"
            ),
        ])
    func aNormalPath(root: String, path: String, expected: String) async throws {
        let transport = backend()
        let bytes = try await service(root, transport: transport).avatar(at: path)

        #expect(bytes == Self.picture)
        let fetched = transport.requests.filter { $0.method == .get }
        #expect(fetched.map(\.url.absoluteString) == [expected])
        #expect(fetched.first?.headers["Authorization"] == "Bearer access.token.1")
    }

    @Test(
        "never sends a request, or the token, to any other origin",
        arguments: [
            "/.other.example/x", "/@other.example/x", "/:1@other.example/x", "//other.example/x",
            "https://other.example/x", "///other.example/x", "/%2e%2e/x", "/../x", "/./x", "/x#part",
            "v1/me/avatar", "", "/\\other.example/x",
        ])
    func aPathLeavingTheOrigin(path: String) async throws {
        for root in [
            "https://api.example.com", "https://api.example.com/", "https://api.example.com:8443/base",
        ] {
            let transport = backend(rejectingFirstAvatar: true)
            _ = try await service(root, transport: transport).avatar(at: path)

            for request in transport.requests {
                #expect(sameOrigin(request.url, as: root), "\(path) against \(root) reached \(request.url)")
            }
            let authorised = transport.requests.filter { $0.headers["Authorization"] != nil }
            #expect(authorised.allSatisfy { sameOrigin($0.url, as: root) })
        }
    }

    @Test("retries once after a 401 with the renewed token, at the same address on the same origin")
    func theRetryAfterA401() async throws {
        let transport = backend(rejectingFirstAvatar: true)
        let bytes = try await service("https://api.example.com", transport: transport).avatar(
            at: "/v1/me/avatar")

        #expect(bytes == Self.picture)
        let fetched = transport.requests.filter { $0.method == .get }
        #expect(
            fetched.map(\.url.absoluteString)
                == Array(repeating: "https://api.example.com/v1/me/avatar", count: 2))
        #expect(
            fetched.map { $0.headers["Authorization"] } == ["Bearer access.token.1", "Bearer access.token.2"])
        #expect(transport.requests.allSatisfy { sameOrigin($0.url, as: "https://api.example.com") })
    }

    @Test(
        "refuses a path that is not a plain absolute path, before asking for anything",
        arguments: [
            "//other.example/x", "https://other.example/x", "///other.example/x", "/%2e%2e/x", "/../x",
            "/./x",
            "/x#part", "v1/me/avatar", "",
        ])
    func aRefusedPathSendsNothing(path: String) async throws {
        for root in [
            "https://api.example.com", "https://api.example.com/", "https://api.example.com:8443/base",
        ] {
            let transport = backend()
            let bytes = try await service(root, transport: transport).avatar(at: path)

            #expect(bytes == nil, "\(path) against \(root)")
            #expect(
                transport.requests.isEmpty, "\(path) against \(root) sent \(transport.requests.map(\.url))")
        }
    }
}
