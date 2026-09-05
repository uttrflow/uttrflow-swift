import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowAccount

@Suite("Talking to the real backend")
struct HTTPAuthenticationServiceTests {
    private let signedIn = Fixture.profile(
        for: Fixture.entitlement(expiring: 86_400), validator: nil)

    /// The randomness these tests pin, so the state and the PKCE pair are known values
    /// rather than something only the service can see.
    private static let fixedRandomness: @Sendable (Int) -> Data = { Data(repeating: 7, count: $0) }

    /// The state a pinned sign-in produces: base64url of twenty-four 0x07 bytes.
    ///
    /// Written out rather than computed, so a change to how the state is derived shows up
    /// here as a failing test instead of as two functions agreeing with each other.
    private static let pinnedState = "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcH"

    private func service(
        transport: StubTransport,
        tokens: any TokenStore = InMemoryTokenStore(),
        device: (any DeviceIdentifying)? = nil,
        listener: StubLoopbackListener? = nil,
        now: @escaping @Sendable () -> Date = { Fixture.noon }
    ) -> HTTPAuthenticationService {
        let loopback = listener ?? StubLoopbackListener(returning: nil)
        return HTTPAuthenticationService(
            baseURL: Stub.baseURL, transport: transport, tokens: tokens, device: device,
            verifier: Fixture.verifier,
            makeListener: { loopback },
            randomBytes: Self.fixedRandomness,
            now: now)
    }

    /// A listener that answers with the code the browser would carry back.
    private func answering(_ code: String = "the-code", state: String = pinnedState) -> StubLoopbackListener {
        StubLoopbackListener(returning: LoopbackCallback(code: code, state: state))
    }

    /// A transport that answers the two calls a sign-in makes.
    private func signingIn(etag: String? = "\"v1\"") -> StubTransport {
        StubTransport { [signedIn] request, _ in
            switch request.url.path() {
            case let path where path.hasSuffix("/token"), let path where path.hasSuffix("/refresh"):
                return Stub.json(Stub.IssuedSession())
            case let path where path.hasSuffix("/me"):
                return Stub.json(signedIn, etag: etag)
            default:
                return Stub.problem(404, message: "no such endpoint")
            }
        }
    }

    private func happyPath(etag: String? = "\"v1\"") -> StubTransport { signingIn(etag: etag) }

    // MARK: Starting

    /// Everything the app decides before a browser opens, in one test.
    @Test("binds a port first, then asks for a page carrying the challenge")
    func startingASignIn() async throws {
        let listener = answering()
        let backend = service(transport: signingIn(), listener: listener)

        let challenge = try await backend.beginSignIn(with: .gitHub)
        let query = try #require(
            URLComponents(url: challenge.authorisationURL, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        // The port is bound before the browser is sent anywhere: a Mac that cannot bind
        // one cannot finish this flow, and finding out afterwards would leave somebody
        // with a tab open and nowhere to come back to.
        #expect(listener.wasBound)
        #expect(challenge.authorisationURL.path().hasSuffix("v1/auth/authorize"))
        #expect(value("client_id") == "uttrflow-mac")
        // The provider is spelled as Swift spells it; the backend parses either.
        #expect(value("provider") == "gitHub")
        #expect(value("redirect_uri") == StubLoopbackListener.redirectURI.absoluteString)
        #expect(value("code_challenge_method") == "S256")
        #expect(value("state") == challenge.state)
        #expect(value("code_challenge") == PKCEPair(randomBytes: Data(repeating: 7, count: 32)).challenge)

        // The one value that must never be in a URL the browser can see.
        let verifier = PKCEPair(randomBytes: Data(repeating: 7, count: 32)).verifier
        #expect(!challenge.authorisationURL.absoluteString.contains(verifier))
    }

    /// A Mac that cannot bind a loopback port is not stuck: it signs in by code instead.
    /// The whole of that path is exercised in `DeviceGrantTests`; what matters here is that
    /// failing to bind is not an error the person ever sees.
    @Test("does not fail when no port can be bound")
    func aPortThatCannotBeBound() async throws {
        let transport = StubTransport { request, _ in
            request.url.path().hasSuffix("/device/code")
                ? Stub.json(Stub.StartedDevice())
                : Stub.problem(404, message: "no such endpoint")
        }
        let backend = HTTPAuthenticationService(
            baseURL: Stub.baseURL, transport: transport, tokens: InMemoryTokenStore(),
            verifier: Fixture.verifier,
            makeListener: { StubLoopbackListener(returning: nil, failingToBind: .serverUnreachable) },
            randomBytes: Self.fixedRandomness,
            now: { Fixture.noon })

        let challenge = try await backend.beginSignIn(with: .google)
        #expect(challenge.method.userCode == "BCDF-GHJK")
    }

    // MARK: Completing

    @Test("spends the code with the verifier it kept, and reads the profile")
    func theWholeExchange() async throws {
        let tokens = InMemoryTokenStore()
        let transport = signingIn()
        let backend = service(transport: transport, tokens: tokens, listener: answering())

        let challenge = try await backend.beginSignIn(with: .google)
        let profile = try await backend.completeSignIn(challenge)

        let spent = try #require(transport.requests(to: "/token").last)
        let body = spent.jsonBody
        #expect(body["grant_type"] as? String == "authorization_code")
        #expect(body["client_id"] as? String == "uttrflow-mac")
        #expect(body["code"] as? String == "the-code")
        #expect(body["redirect_uri"] as? String == StubLoopbackListener.redirectURI.absoluteString)

        // The verifier answers the challenge that went to the browser, which is the whole
        // of PKCE: the code is worthless to anybody who did not start this sign-in.
        let pair = PKCEPair(randomBytes: Data(repeating: 7, count: 32))
        #expect(body["code_verifier"] as? String == pair.verifier)

        #expect(profile.account == signedIn.account)
        #expect(profile.validator == "\"v1\"")
        #expect(tokens.refreshToken() == "refresh-token-one")
    }

    /// The browser is a channel anybody can send something down, so an answer that does not
    /// name this attempt is not ours to spend — whatever the server made of it.
    @Test("refuses a callback that answers a different attempt")
    func aCallbackForSomebodyElsesAttempt() async throws {
        let transport = signingIn()
        let backend = service(
            transport: transport, listener: answering(state: "somebody-else's-attempt"))

        let challenge = try await backend.beginSignIn(with: .google)
        await #expect(throws: AccountError.self) { try await backend.completeSignIn(challenge) }
        #expect(transport.requests(to: "/token").isEmpty, "a code was spent for another attempt")
    }

    @Test("refuses to complete a sign-in it never started")
    func completingWithoutAnAttempt() async throws {
        let backend = service(transport: signingIn())
        let orphan = SignInChallenge(
            authorisationURL: safeURL("https://sign-in.invalid/uttrflow"), state: "x")
        await #expect(throws: AccountError.self) { try await backend.completeSignIn(orphan) }
    }

    /// A port left open is a socket on somebody's machine accepting connections for as long
    /// as the app runs.
    @Test("gives the port back when a sign-in ends, however it ends")
    func theListenerIsAlwaysClosed() async throws {
        let refused = answering(state: "will-not-match")
        let backend = service(transport: signingIn(), listener: refused)
        let challenge = try await backend.beginSignIn(with: .google)
        _ = try? await backend.completeSignIn(challenge)
        // The close happens in a detached task, so give it the one turn it needs.
        await Task.yield()
        #expect(refused.wasClosed)
    }

    /// Starting a second sign-in must not leave the first one holding a port.
    @Test("abandons an attempt that is replaced")
    func aReplacedAttemptGivesItsPortBack() async throws {
        let abandoned = StubLoopbackListener(returning: nil)
        let backend = service(transport: signingIn(), listener: abandoned)
        _ = try await backend.beginSignIn(with: .google)
        _ = try await backend.beginSignIn(with: .google)
        #expect(abandoned.wasClosed)
    }

    @Test("sends the machine's own description, when it has one")
    func registersTheDevice() async throws {
        let transport = signingIn()
        let identity = MacDeviceIdentity(
            storage: MemoryStorage(), name: { "Naveen's MacBook Pro" }, appVersion: "0.1.0",
            makeInstallIdentifier: { "install-abcdef123456" })

        let backend = service(transport: transport, device: identity, listener: answering())
        _ = try await backend.completeSignIn(try await backend.beginSignIn(with: .google))

        let spent = try #require(transport.requests(to: "/token").last)
        let registration = try #require(spent.jsonBody["device"] as? [String: Any])
        #expect(registration["installId"] as? String == "install-abcdef123456")
        #expect(registration["platform"] as? String == "macos")
        #expect(registration["name"] as? String == "Naveen's MacBook Pro")
    }

    @Test("signs in a client that has nothing to say about itself")
    func deviceIsOptional() async throws {
        let transport = signingIn()
        let backend = service(transport: transport, listener: answering())
        _ = try await backend.completeSignIn(try await backend.beginSignIn(with: .google))

        let spent = try #require(transport.requests(to: "/token").last)
        #expect(spent.jsonBody["device"] == nil)
    }

    @Test("passes on what the server said when it refuses the code")
    func theCodeIsRefused() async throws {
        let transport = StubTransport { request, _ in
            request.url.path().hasSuffix("/token")
                ? Stub.problem(400, message: "That code is not valid.")
                : Stub.problem(404, message: "no such endpoint")
        }
        let backend = service(transport: transport, listener: answering())
        let challenge = try await backend.beginSignIn(with: .google)

        await #expect(throws: AccountError.providerRefused(description: "That code is not valid.")) {
            try await backend.completeSignIn(challenge)
        }
    }

    /// The signature is checked where there is somebody to tell. A profile that cannot be
    /// believed must fail the sign-in that produced it rather than surface later as a
    /// mysterious sign-out.
    @Test("refuses a profile this build cannot verify")
    func aForgedProfileFailsTheSignIn() async throws {
        let forged = Fixture.profile(
            for: Fixture.entitlement(expiring: 86_400, signedBy: Fixture.impostor), validator: nil)
        let transport = StubTransport { request, _ in
            request.url.path().hasSuffix("/me")
                ? Stub.json(forged)
                : Stub.json(Stub.IssuedSession())
        }
        let backend = service(transport: transport, listener: answering())

        await #expect(throws: AccountError.sessionMalformed) {
            try await backend.completeSignIn(try await backend.beginSignIn(with: .google))
        }
    }

    /// The signature covers the entitlement and nothing around it, so a document pairing a
    /// genuine free entitlement with a subscription claiming Pro would verify perfectly and
    /// be wrong on every screen drawn from it.
    @Test("refuses a profile whose signed half names somebody else")
    func aMismatchedProfileIsRefused() async throws {
        let mismatched = Profile(
            account: Fixture.account("somebody-else"),
            subscription: signedIn.subscription, devices: [],
            entitlement: signedIn.entitlement, fetchedAt: Fixture.noon, validator: nil)
        let transport = StubTransport { request, _ in
            request.url.path().hasSuffix("/me")
                ? Stub.json(mismatched)
                : Stub.json(Stub.IssuedSession())
        }
        let backend = service(transport: transport, listener: answering())

        await #expect(throws: AccountError.sessionMalformed) {
            try await backend.completeSignIn(try await backend.beginSignIn(with: .google))
        }
    }

    // MARK: Re-reading

    @Test("sends the cached validator and reports 304 as unchanged")
    func conditionalFetch() async throws {
        let transport = StubTransport { request, _ in
            if request.url.path().hasSuffix("/me") { return BackendResponse(status: 304) }
            return Stub.json(Stub.IssuedSession())
        }
        let cached = Fixture.profile(for: Fixture.entitlement(expiring: 86_400), validator: "\"v9\"")

        let service = service(transport: transport, tokens: InMemoryTokenStore(refreshToken: "r"))
        #expect(try await service.currentProfile(ifChangedFrom: cached) == .unchanged)

        let read = try #require(transport.requests(to: "/me").first)
        #expect(read.headers["If-None-Match"] == "\"v9\"")
    }

    @Test("asks unconditionally when it has nothing cached")
    func unconditionalWithoutACache() async throws {
        let transport = happyPath()
        let service = service(transport: transport, tokens: InMemoryTokenStore(refreshToken: "r"))
        #expect(try await service.currentProfile(ifChangedFrom: nil) != .unchanged)
        #expect(transport.requests(to: "/me").first?.headers["If-None-Match"] == nil)
    }

    /// The distinction the launch refresh is built on. A Mac with no refresh token has not
    /// been signed out by anybody — it has nothing to ask with, which is a statement about
    /// this machine's Keychain and not about the account. Answering ``ProfileRefresh/signedOut``
    /// here told ``AccountRefresh`` to delete a perfectly good cached profile, and an
    /// ad-hoc-signed build reaches it on every launch: `SecItemAdd` refuses the data
    /// protection keychain outright without an access group, so the token is never stored.
    @Test("says it has no credential, rather than that the session is over")
    func noCredentialIsNotASignOut() async throws {
        let transport = happyPath()
        let service = service(transport: transport)
        #expect(try await service.currentProfile(ifChangedFrom: nil) == .noCredential)
        // Nothing was asked of the server: there is nothing to ask with.
        #expect(transport.requests.isEmpty)
    }

    /// The whole failure, end to end, with nothing scripted between the empty Keychain and
    /// the cache: a real service, a real ``AccountRefresh``, and a profile that must still
    /// be there afterwards.
    @Test("a Keychain that lost the token does not cost the user their cached profile")
    func anEmptyKeychainKeepsTheProfile() async throws {
        let cache = Fixture.cacheHolding(profile: signedIn)
        let transport = happyPath()

        let outcome = await AccountRefresh(
            service: service(transport: transport), profiles: cache
        ).run()

        #expect(outcome == .noCredential)
        #expect(cache.load() == signedIn, "the launch refresh signed out a Mac the server had not")
        #expect(transport.requests.isEmpty)
    }

    @Test("mints an access token from the refresh token, and then reuses it")
    func accessTokensAreMintedOnceAndKept() async throws {
        let transport = happyPath()
        let service = service(transport: transport, tokens: InMemoryTokenStore(refreshToken: "r"))

        _ = try await service.currentProfile(ifChangedFrom: nil)
        _ = try await service.currentProfile(ifChangedFrom: nil)

        #expect(transport.requests(to: "/refresh").count == 1)
        #expect(transport.requests(to: "/me").count == 2)
        #expect(
            transport.requests(to: "/me").allSatisfy {
                $0.headers["Authorization"] == "Bearer access.token.one"
            })
    }

    /// An access token rejected once is usually one minted just before a rotation. Rejected
    /// twice, with a token that was fresh, and the session itself is gone.
    @Test("retries a rejected access token exactly once")
    func oneRetryAfterA401() async throws {
        let rejections = Mutex(0)
        let transport = StubTransport { [signedIn] request, _ in
            if request.url.path().hasSuffix("/me") {
                let seen = rejections.withLock { count -> Int in
                    count += 1
                    return count
                }
                return seen == 1 ? BackendResponse(status: 401) : Stub.json(signedIn, etag: "\"v2\"")
            }
            return Stub.json(Stub.IssuedSession())
        }

        let service = service(transport: transport, tokens: InMemoryTokenStore(refreshToken: "r"))
        let outcome = try await service.currentProfile(ifChangedFrom: nil)

        #expect(outcome.updatedProfile?.validator == "\"v2\"")
        #expect(transport.requests(to: "/refresh").count == 2)
        #expect(transport.requests(to: "/me").count == 2)
    }

    @Test("stops after the second refusal rather than looping")
    func twoRejectionsMeanSignedOut() async throws {
        let transport = StubTransport { request, _ in
            if request.url.path().hasSuffix("/me") { return BackendResponse(status: 401) }
            return Stub.json(Stub.IssuedSession())
        }
        let service = service(transport: transport, tokens: InMemoryTokenStore(refreshToken: "r"))

        #expect(try await service.currentProfile(ifChangedFrom: nil) == .signedOut)
        #expect(transport.requests(to: "/me").count == 2)
    }

    /// Somebody signed this machine out from another one. The credential is dead and
    /// keeping it would mean asking the server the same rejected question for ever.
    @Test("throws away a refresh token the server has rejected")
    func aRevokedRefreshTokenIsForgotten() async throws {
        let tokens = InMemoryTokenStore(refreshToken: "revoked")
        let transport = StubTransport { request, _ in
            guard request.url.path().hasSuffix("/refresh") else { return nil }
            return BackendResponse(status: 401)
        }

        let service = service(transport: transport, tokens: tokens)
        #expect(try await service.currentProfile(ifChangedFrom: nil) == .signedOut)
        #expect(tokens.refreshToken() == nil)
    }

    @Test("keeps the credential when the server merely cannot be reached")
    func anOutageIsNotASignOut() async throws {
        let tokens = InMemoryTokenStore(refreshToken: "still-good")
        let transport = StubTransport { _, _ in nil }

        let service = service(transport: transport, tokens: tokens)
        await #expect(throws: AccountError.serverUnreachable) {
            try await service.currentProfile(ifChangedFrom: nil)
        }
        #expect(tokens.refreshToken() == "still-good")
    }

    @Test("keeps the rotated refresh token, because the old one is already dead")
    func rotationIsKept() async throws {
        let tokens = InMemoryTokenStore(refreshToken: "first")
        let transport = StubTransport { [signedIn] request, _ in
            if request.url.path().hasSuffix("/refresh") {
                var session = Stub.IssuedSession()
                session.refreshToken = "second"
                return Stub.json(session)
            }
            return Stub.json(signedIn)
        }

        _ = try await service(transport: transport, tokens: tokens).currentProfile(ifChangedFrom: nil)
        #expect(tokens.refreshToken() == "second")
    }

    // MARK: Signing out

    @Test("forgets the credential first and tells the server afterwards")
    func signingOut() async throws {
        let tokens = InMemoryTokenStore(refreshToken: "to-be-revoked")
        let transport = StubTransport { _, _ in BackendResponse(status: 204) }

        await service(transport: transport, tokens: tokens).signOut()

        #expect(tokens.refreshToken() == nil)
        let told = try #require(transport.requests(to: "/sign-out").first)
        #expect(told.jsonBody["refreshToken"] as? String == "to-be-revoked")
    }

    /// Somebody on a train asking to be signed out is entitled to be signed out.
    @Test("signs out locally even when the server cannot be told")
    func signingOutOffline() async throws {
        let tokens = InMemoryTokenStore(refreshToken: "to-be-revoked")
        let transport = StubTransport { _, _ in nil }

        await service(transport: transport, tokens: tokens).signOut()
        #expect(tokens.refreshToken() == nil)
    }

    @Test("says nothing to the server when there was nothing to sign out of")
    func signingOutWithNoSession() async throws {
        let transport = StubTransport { _, _ in BackendResponse(status: 204) }
        await service(transport: transport).signOut()
        #expect(transport.requests.isEmpty)
    }
}

// MARK: - The device grant, for a Mac with nowhere to be redirected to

/// How long the client was asked to wait between polls, shared by reference with the sleep closure.
private final class Waits: Sendable {
    private let durations = Mutex<[Duration]>([])

    func record(_ duration: Duration) {
        durations.withLock { $0.append(duration) }
    }

    var all: [Duration] { durations.withLock { $0 } }
}

@Suite("Signing in by code")
struct DeviceGrantTests {
    private let signedIn = Fixture.profile(
        for: Fixture.entitlement(expiring: 86_400), validator: nil)

    /// Every response the device grant needs, with the poll answering `pending` until the
    /// test says otherwise.
    private func backend(
        pendingPolls: Int = 0,
        slowDownFirst: Bool = false
    ) -> StubTransport {
        let polls = Mutex(0)
        return StubTransport { [signedIn] request, _ in
            switch request.url.path() {
            case let path where path.hasSuffix("/device/code"):
                return Stub.json(Stub.StartedDevice())
            case let path where path.hasSuffix("/device/token"):
                let seen = polls.withLock { count -> Int in
                    count += 1
                    return count
                }
                if slowDownFirst && seen == 1 {
                    return Stub.oauthProblem("slow_down", "Polling too fast.")
                }
                if seen <= pendingPolls {
                    return Stub.oauthProblem("authorization_pending", "Waiting for approval.")
                }
                return Stub.json(Stub.IssuedSession())
            case let path where path.hasSuffix("/me"):
                return Stub.json(signedIn, etag: "\"v1\"")
            default:
                return Stub.problem(404, message: "no such endpoint")
            }
        }
    }

    private func service(
        transport: StubTransport,
        tokens: any TokenStore = InMemoryTokenStore(),
        waited: Waits? = nil,
        now: @escaping @Sendable () -> Date = { Fixture.noon }
    ) -> HTTPAuthenticationService {
        HTTPAuthenticationService(
            baseURL: Stub.baseURL, transport: transport, tokens: tokens,
            verifier: Fixture.verifier,
            // A listener that cannot bind is the whole reason this path exists.
            makeListener: { StubLoopbackListener(returning: nil, failingToBind: .serverUnreachable) },
            randomBytes: { count in Data(repeating: 7, count: count) },
            now: now,
            sleep: { duration in waited?.record(duration) })
    }

    /// The fallback is automatic: nobody chooses it, the machine does.
    @Test("falls back to a code when no port can be bound")
    func fallsBackWhenThereIsNoPort() async throws {
        let transport = backend()
        let challenge = try await service(transport: transport).beginSignIn(with: .google)

        guard case .code(let userCode, let verificationURL) = challenge.method else {
            Issue.record("the sign-in did not fall back: \(challenge.method)")
            return
        }
        #expect(userCode == "BCDF-GHJK")
        // The complete address, so the person can follow a link rather than type the code
        // when the browser is on the same machine.
        #expect(verificationURL.absoluteString.contains("user_code=BCDF-GHJK"))
        #expect(challenge.authorisationURL == verificationURL)
        #expect(transport.requests(to: "/device/code").count == 1)
    }

    @Test("waits for the code to be approved, then reads the profile")
    func waitsForApproval() async throws {
        let tokens = InMemoryTokenStore()
        let transport = backend(pendingPolls: 3)
        let service = service(transport: transport, tokens: tokens)

        let profile = try await service.completeSignIn(try await service.beginSignIn(with: .google))

        // Three answers of "not yet" are the ordinary case, not a failure.
        #expect(transport.requests(to: "/device/token").count == 4)
        #expect(profile.account == signedIn.account)
        #expect(tokens.refreshToken() == "refresh-token-one")
    }

    /// RFC 8628 §3.5. Obeying `slow_down` is the difference between a well-behaved client
    /// and one a server has to defend itself from.
    @Test("waits longer when told to slow down")
    func obeysSlowDown() async throws {
        let waited = Waits()
        let service = service(transport: backend(slowDownFirst: true), waited: waited)

        _ = try await service.completeSignIn(try await service.beginSignIn(with: .google))

        let intervals = waited.all
        #expect(intervals.count >= 2)
        #expect(intervals[0] == .seconds(5), "the first wait was not the interval it was given")
        #expect(intervals[1] > intervals[0], "a slow_down did not lengthen the wait")
    }

    @Test("gives up when the code expires before anybody approves it")
    func expires() async throws {
        let clock = Mutex(Fixture.noon)
        let service = service(
            transport: backend(pendingPolls: 1_000),
            now: {
                clock.withLock { moment -> Date in
                    // Every poll costs a minute, so the fifteen-minute window closes.
                    moment = moment.addingTimeInterval(60)
                    return moment
                }
            })

        await #expect(throws: AccountError.self) {
            try await service.completeSignIn(try await service.beginSignIn(with: .google))
        }
    }

    @Test("passes on a refusal rather than polling through it")
    func aRefusalStopsThePolling() async throws {
        let transport = StubTransport { request, _ in
            request.url.path().hasSuffix("/device/token")
                ? Stub.oauthProblem("access_denied", "That code was declined.")
                : Stub.json(Stub.StartedDevice())
        }
        let service = service(transport: transport)

        await #expect(throws: AccountError.providerRefused(description: "That code was declined.")) {
            try await service.completeSignIn(try await service.beginSignIn(with: .google))
        }
        #expect(transport.requests(to: "/device/token").count == 1)
    }
}
