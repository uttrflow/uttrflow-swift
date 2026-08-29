import Foundation
import Testing

@testable import UttrflowAccount

/// The whole sign-in, with nothing substituted: a real socket, a real HTTP client, and a
/// real backend on the other end.
///
/// Everything else in this suite replaces one half of the flow to make the other half
/// testable. This replaces neither, which is why it is the only test that can catch the
/// class of bug those cannot — a port that binds but is never reached, a redirect the
/// server refuses, a request the app builds one way and the backend parses another.
///
/// Skipped unless `UTTRFLOW_BACKEND_URL` names a running service, because it needs one:
///
/// ```bash
/// cd ../uttrflow-backend && make run     # or PORT=8788 with a seeded database
/// UTTRFLOW_BACKEND_URL=http://127.0.0.1:8788 swift test --filter "against a real backend"
/// ```
@Suite(
    "Signing in against a real backend",
    .enabled(if: LiveBackend.isConfigured, LiveBackend.absenceReason))
struct EndToEndTests {
    /// The service under test. Non-optional: the suite does not run without one, and
    /// `.enabled(if:)` above is what makes that a reported skip rather than three tests
    /// returning early and calling themselves passed.
    private var backendURL: URL {
        get throws { try #require(LiveBackend.url, "UTTRFLOW_BACKEND_URL is not a URL") }
    }

    /// The key the running service publishes, so this build verifies what that deployment
    /// actually signs rather than what it was compiled to expect.
    private func liveVerifier(_ backend: URL) async throws -> Ed25519EntitlementVerifier {
        let (data, _) = try await URLSession.shared.data(from: backend.appending(path: "v1/health"))
        struct Health: Decodable { let entitlementPublicKey: String }
        let health = try JSONDecoder().decode(Health.self, from: data)
        let key = try #require(Data(base64Encoded: health.entitlementPublicKey))
        return Ed25519EntitlementVerifier(publicKeyBytes: key)
    }

    @Test("binds a port, opens the page, and comes back with a signed profile")
    func theWholeThing() async throws {
        let backend = try backendURL

        let tokens = InMemoryTokenStore()
        let service = HTTPAuthenticationService(
            baseURL: backend,
            transport: URLSessionTransport(),
            tokens: tokens,
            device: MacDeviceIdentity(
                storage: MemoryStorage(), name: { "An End-to-End Mac" }, appVersion: "0.1.0",
                makeInstallIdentifier: { "install-end-to-end-0001" }),
            verifier: try await liveVerifier(backend))

        let challenge = try await service.beginSignIn(with: .google)

        // The port really is bound, and the address really is loopback.
        let query = URLComponents(url: challenge.authorisationURL, resolvingAgainstBaseURL: false)?
            .queryItems
        let redirect = try #require(query?.first { $0.name == "redirect_uri" }?.value)
        #expect(redirect.hasPrefix("http://127.0.0.1:"))
        #expect(redirect.hasSuffix("/callback"))

        // Stand in for the browser: follow the redirects, which ends at the port the app
        // is listening on. In development the provider redirects straight back, so this is
        // the same two hops a person's browser would take.
        async let browsing: Void = {
            _ = try? await URLSession.shared.data(from: challenge.authorisationURL)
        }()

        let profile = try await service.completeSignIn(challenge)
        await browsing

        #expect(profile.account.emailAddress != nil)
        #expect(profile.entitlement.plan == .free)
        #expect(profile.validator != nil, "the server issued no cache validator")
        #expect(profile.isInternallyConsistent)
        #expect(tokens.refreshToken() != nil, "no refresh token was kept")

        // And the machine this test claims to be is in the list, marked as the one asking.
        let current = try #require(profile.currentDevice)
        #expect(current.name == "An End-to-End Mac")
        #expect(current.platform == .macOS)
    }

    /// The path a locked-down machine takes, against the real service.
    ///
    /// The listener is made to fail on purpose, which is the only part of this that is not
    /// real — a Mac where security software refuses to let an application listen cannot be
    /// arranged in a test. Everything after that is: the backend really mints a code, this
    /// really polls, and the approval really goes through the activation page and a
    /// provider.
    @Test("signs in by code when no port can be bound")
    func theDeviceGrant() async throws {
        let backend = try backendURL

        let tokens = InMemoryTokenStore()
        let service = HTTPAuthenticationService(
            baseURL: backend,
            transport: URLSessionTransport(),
            tokens: tokens,
            verifier: try await liveVerifier(backend),
            makeListener: { UnbindableListener() })

        let challenge = try await service.beginSignIn(with: .google)
        guard case .code(let userCode, let verificationURL) = challenge.method else {
            Issue.record("the sign-in did not fall back to a code: \(challenge.method)")
            return
        }
        #expect(userCode.count == 9, "a code somebody has to type is \(userCode)")
        #expect(verificationURL.absoluteString.contains("/v1/auth/device"))

        // Stand in for the person at a browser: submit the activation form, then follow
        // the provider's redirect back. Exactly the two steps they would take.
        async let approving: Void = approve(userCode, at: backend)

        let profile = try await service.completeSignIn(challenge)
        await approving

        #expect(profile.account.emailAddress != nil)
        #expect(profile.isInternallyConsistent)
        #expect(tokens.refreshToken() != nil)
    }

    /// Submits the activation form and follows where it goes, as a browser would.
    private func approve(_ userCode: String, at backend: URL) async {
        var form = URLRequest(url: backend.appending(path: "v1/auth/device"))
        form.httpMethod = "POST"
        form.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        form.httpBody = Data("user_code=\(userCode)&provider=google".utf8)
        // URLSession follows the redirect chain, which ends at the page saying it worked.
        _ = try? await URLSession.shared.data(for: form)
    }

    /// The second launch: no browser, no sign-in, just the cached copy being re-read.
    @Test("re-reads the profile afterwards, and is told when nothing changed")
    func rereadingAfterwards() async throws {
        let backend = try backendURL

        let tokens = InMemoryTokenStore()
        let service = HTTPAuthenticationService(
            baseURL: backend, transport: URLSessionTransport(), tokens: tokens,
            verifier: try await liveVerifier(backend))

        let challenge = try await service.beginSignIn(with: .gitHub)
        async let browsing: Void = {
            _ = try? await URLSession.shared.data(from: challenge.authorisationURL)
        }()
        let signedIn = try await service.completeSignIn(challenge)
        await browsing

        // Sending the validator back is what makes re-reading the truth affordable.
        let unchanged = try await service.currentProfile(ifChangedFrom: signedIn)
        #expect(unchanged == .unchanged)

        // And without it, a fresh document.
        let refreshed = try await service.currentProfile(ifChangedFrom: nil)
        #expect(refreshed.updatedProfile != nil)
    }
}
