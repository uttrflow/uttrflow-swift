import Foundation
import Testing

@testable import UttrflowAccount

/// The whole sign-in against a live backend named by `UTTRFLOW_BACKEND_URL`, with nothing substituted.
@Suite(
    "Signing in against a real backend",
    .enabled(if: LiveBackend.isConfigured, LiveBackend.absenceReason))
struct EndToEndTests {
    /// The backend's address; `.enabled(if:)` above turns its absence into a reported skip, not a pass.
    private var backendURL: URL {
        get throws { try #require(LiveBackend.url, "UTTRFLOW_BACKEND_URL is not a URL") }
    }

    /// The key the running service publishes, so this build verifies what that deployment signs.
    private func liveVerifier(_ backend: URL) async throws -> Ed25519EntitlementVerifier {
        let (data, _) = try await URLSession.shared.data(from: backend.appending(path: "v1/health"))
        /// The one field of `/v1/health` this test reads.
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

        // Stands in for the browser: following the redirects ends at the port, as a person's browser would.
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

    /// The device flow against the real service; only the listener's failure to bind is arranged.
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

        // Stands in for the person at a browser: submits the activation form, then follows the redirect back.
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
