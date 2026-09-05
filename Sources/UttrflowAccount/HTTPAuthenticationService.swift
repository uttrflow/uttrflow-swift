public import UttrflowCore

public import struct Foundation.Date
public import struct Foundation.URL
public import struct Foundation.URLComponents
public import struct Foundation.URLQueryItem

public import struct Foundation.Data
public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder
public import typealias Foundation.TimeInterval

private import Synchronization

/// The real backend.
///
/// Everything here is one of four HTTP calls — start, claim, refresh, read the profile —
/// and the interesting parts are the three rules it keeps while making them.
///
/// **A missing network is never a refusal.** The transport throws only when the request
/// did not happen; every answer the server gave, including `401` and `502`, comes back as
/// a response. That distinction is the offline promise in one line: a Mac that cannot
/// reach the server keeps its cached profile, and a Mac that has been *told* its session
/// is over does not.
///
/// **The access token is never written down.** It lives an hour and stays in memory; only
/// the ninety-day refresh token reaches the Keychain. A process that ends has nothing to
/// leak but the credential it must keep, and that one is behind the system's own lock.
///
/// **Nothing is believed without a signature.** A profile is refused unless its
/// entitlement verifies against the key compiled into this build, and unless the
/// entitlement names the same account as the document carrying it.
public final class HTTPAuthenticationService: AuthenticationService {
    /// This build's registered client identifier. Public, and not a credential: a native
    /// app cannot keep a secret, which is what PKCE is for.
    public static let defaultClientID = "uttrflow-mac"

    /// Renew this long before the access token actually expires, so a request is never
    /// sent with a token that dies in flight on a slow connection.
    private static let renewalMargin: TimeInterval = 60

    private struct AccessToken: Sendable {
        let value: String
        let expiresAt: Date
    }

    /// A sign-in waiting to finish, in whichever of the two ways it is going to.
    ///
    /// Held here rather than on ``SignInChallenge`` so that no value the interface passes
    /// around carries a secret. The interface holds the challenge; the secret stays with
    /// the only object that needs it.
    private enum Pending {
        /// Waiting on a port: the redirect it will come back to, and the verifier that
        /// will spend the code when it does.
        case browser(state: String, pkce: PKCEPair, redirectURI: URL, listener: any LoopbackListening)

        /// Waiting on a person typing a code somewhere else, and polling until they have.
        case code(state: String, deviceCode: String, interval: Duration, expiresAt: Date)

        var state: String {
            switch self {
            case .browser(let state, _, _, _): state
            case .code(let state, _, _, _): state
            }
        }
    }

    private let baseURL: URL
    private let clientID: String
    private let transport: any BackendTransport
    private let tokens: any TokenStore
    private let device: (any DeviceIdentifying)?
    private let verifier: any EntitlementVerifying
    private let makeListener: @Sendable () -> any LoopbackListening
    private let randomBytes: @Sendable (Int) -> Data
    private let now: @Sendable () -> Date
    /// How the device flow waits between polls. Injected so a test does not.
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The short-lived half of the session. A `Mutex` rather than an actor because the
    /// service is asked questions from wherever a window happens to be running and nothing
    /// it does with this value is slow enough to be worth a suspension.
    private let access = Mutex<AccessToken?>(nil)

    /// The attempt in flight, if there is one. A second sign-in replaces the first, and
    /// closes its port: two listeners waiting for the same browser is a port left open.
    private let pending = Mutex<Pending?>(nil)

    public init(
        baseURL: URL,
        transport: any BackendTransport,
        tokens: any TokenStore,
        device: (any DeviceIdentifying)? = nil,
        clientID: String = defaultClientID,
        verifier: any EntitlementVerifying = Ed25519EntitlementVerifier.release,
        makeListener: @escaping @Sendable () -> any LoopbackListening = { SystemLoopbackListener() },
        randomBytes: @escaping @Sendable (Int) -> Data = HTTPAuthenticationService.systemRandomBytes,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.baseURL = baseURL
        self.clientID = clientID
        self.transport = transport
        self.tokens = tokens
        self.device = device
        self.verifier = verifier
        self.makeListener = makeListener
        self.randomBytes = randomBytes
        self.now = now
        self.sleep = sleep
    }

    /// Randomness from the system, for the PKCE verifier and the state.
    ///
    /// `SystemRandomNumberGenerator` is the cryptographically secure one; the arithmetic
    /// generator a test might reach for is not, and a predictable verifier is a verifier
    /// somebody else can produce.
    public static func systemRandomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        var bytes = Data(count: count)
        for index in 0..<count {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return bytes
    }

    // MARK: Signing in

    /// Binds a port, invents a verifier, and returns the page to open.
    ///
    /// The listener is bound *before* the browser is opened, deliberately: it is the one
    /// part that can fail for reasons nothing else in the flow shares, and finding that
    /// out after sending somebody to a sign-in page would waste their time and leave a tab
    /// open with nowhere to return to.
    ///
    /// A Mac that cannot bind one is not stuck. It signs in by code instead — see
    /// ``beginDeviceSignIn(with:)`` — which is the same standard flow a television uses,
    /// and works over SSH, in a container, and on a laptop whose security software refuses
    /// to let an application listen on anything.
    public func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        // Any attempt still waiting is abandoned here rather than left holding a port.
        await abandonPending()

        let listener = makeListener()
        let redirectURI: URL
        do throws(AccountError) {
            redirectURI = try await listener.bind()
        } catch {
            await listener.close()
            return try await beginDeviceSignIn(with: provider)
        }

        let pkce = PKCEPair(randomBytes: randomBytes(32))
        let state = PKCEPair.base64URL(randomBytes(24))

        var components = URLComponents(url: url("v1/auth/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            // `provider.rawValue` spells GitHub as `gitHub`; the backend parses a provider
            // name in any capitalisation precisely so the app can send its own spelling.
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authorisationURL = components?.url else {
            await listener.close()
            throw .providerRefused(description: "the sign-in address could not be built")
        }

        pending.withLock {
            $0 = .browser(state: state, pkce: pkce, redirectURI: redirectURI, listener: listener)
        }
        return SignInChallenge(authorisationURL: authorisationURL, state: state, method: .browser)
    }

    /// Signs in by code, for a machine with nowhere for a browser to come back to.
    ///
    /// RFC 8628. The backend hands over a short code and an address; the person types the
    /// one into the other, on this machine or on their phone, and this polls until they
    /// have. Nothing here needs a port, a URL scheme, or anything the operating system has
    /// to be asked for.
    private func beginDeviceSignIn(
        with provider: SignInProvider
    ) async throws(AccountError) -> SignInChallenge {
        let response = try await send(post("v1/auth/device/code", DeviceCodeBody(clientID: clientID)))

        guard response.isSuccess else { throw refusal(response) }
        guard let started = decode(StartedDeviceSignIn.self, from: response.body),
            let verificationURL = URL(string: started.verificationUriComplete ?? started.verificationUri)
        else {
            throw .providerRefused(description: "the server started a sign-in we could not read")
        }

        let state = PKCEPair.base64URL(randomBytes(24))
        pending.withLock {
            $0 = .code(
                state: state,
                deviceCode: started.deviceCode,
                interval: .seconds(max(1, started.interval)),
                expiresAt: now().addingTimeInterval(TimeInterval(started.expiresIn)))
        }

        return SignInChallenge(
            authorisationURL: verificationURL,
            state: state,
            method: .code(userCode: started.userCode, verificationURL: verificationURL))
    }

    /// Waits for the browser to come back to the port, then spends the code.
    ///
    /// Returns when the person has signed in, which may be a minute after the call — they
    /// have a password manager to find. Cancelling the surrounding task closes the port
    /// and abandons the attempt; the browser tab stays open, because nothing here can
    /// close it.
    public func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile {
        guard let attempt = pending.take(\.self), attempt.state == challenge.state else {
            throw .providerRefused(description: "that sign-in does not answer this attempt")
        }

        switch attempt {
        case .code(_, let deviceCode, let interval, let expiresAt):
            return try await awaitDeviceApproval(deviceCode, every: interval, until: expiresAt)
        case .browser(_, let pkce, let redirectURI, let listener):
            return try await awaitBrowser(
                challenge, pkce: pkce, redirectURI: redirectURI, listener: listener)
        }
    }

    /// Waits on the port, then spends the code with the verifier this process kept.
    private func awaitBrowser(
        _ challenge: SignInChallenge,
        pkce: PKCEPair,
        redirectURI: URL,
        listener: any LoopbackListening
    ) async throws(AccountError) -> Profile {
        defer { Task { await listener.close() } }

        let callback = try await listener.awaitCallback()

        // The state is compared here as well as by the backend. The browser is a channel
        // anybody can send something down, and an answer that does not name this attempt
        // is not ours to spend — whatever the server thought of it.
        guard callback.state == challenge.state else {
            throw .providerRefused(description: "that sign-in does not answer this attempt")
        }

        let response = try await send(
            post(
                "v1/auth/token",
                TokenBody(
                    grantType: "authorization_code",
                    clientID: clientID,
                    code: callback.code,
                    codeVerifier: pkce.verifier,
                    redirectURI: redirectURI.absoluteString,
                    device: device?.registration())))

        guard response.isSuccess else { throw refusal(response) }
        return try await beginSession(issuedBy: response)
    }

    /// Polls until somebody approves the code, or the window closes.
    ///
    /// `authorization_pending` is the ordinary answer rather than a failure — RFC 8628
    /// spells it as an error because a token endpoint has no other vocabulary. `slow_down`
    /// means we asked too often and the interval has gone up; obeying it is the difference
    /// between a well-behaved client and one a server has to defend itself from.
    private func awaitDeviceApproval(
        _ deviceCode: String, every interval: Duration, until expiresAt: Date
    ) async throws(AccountError) -> Profile {
        var wait = interval

        while true {
            do {
                try await sleep(wait)
            } catch {
                // Cancellation. The person walked away from this attempt; the code expires
                // on its own and nothing here has to tell anybody.
                throw .providerRefused(description: "that sign-in was abandoned")
            }

            let response = try await send(
                post(
                    "v1/auth/device/token",
                    DeviceTokenBody(
                        grantType: "urn:ietf:params:oauth:grant-type:device_code",
                        clientID: clientID,
                        deviceCode: deviceCode,
                        device: device?.registration())))

            if response.isSuccess { return try await beginSession(issuedBy: response) }

            switch decode(ServerError.self, from: response.body)?.error {
            case "authorization_pending":
                break
            case "slow_down":
                wait += .seconds(5)
            default:
                throw refusal(response)
            }

            guard now() < expiresAt else {
                throw .providerRefused(description: "that code expired before it was used")
            }
        }
    }

    /// Stops waiting for a sign-in that is somewhere else, and gives the port back.
    private func abandonPending() async {
        if case .browser(_, _, _, let listener)? = pending.take(\.self) {
            await listener.close()
        }
    }

    // MARK: Staying signed in

    public func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        guard tokens.refreshToken() != nil else { return .noCredential }

        switch try await authorised() {
        case .sessionOver: return .signedOut
        case .noCredential: return .noCredential
        case .token(let token):
            let response = try await send(profileRequest(token, ifNoneMatch: cached?.validator))

            if response.status == 304 { return .unchanged }

            // One retry, and only one. An access token that has just been rejected is
            // usually one minted before a rotation; a second rejection after a fresh token
            // means the session itself is gone, not the token.
            if response.status == 401 {
                switch try await renew() {
                case .sessionOver: return .signedOut
                // The credential went away between the first request and this one, which
                // means another caller met a `401` and cleared it. Reported as nothing
                // rather than as a sign-out: the caller that saw the refusal is the one
                // entitled to act on it, and guessing here would delete a cached profile
                // on the strength of a race.
                case .noCredential: return .noCredential
                case .token(let renewed):
                    let retried = try await send(profileRequest(renewed, ifNoneMatch: cached?.validator))
                    if retried.status == 304 { return .unchanged }
                    if retried.status == 401 { return .signedOut }
                    return .updated(try believe(retried))
                }
            }
            return .updated(try believe(response))
        }
    }

    /// Fetches the picture the profile named.
    ///
    /// The same authorised-then-renew-once dance as ``currentProfile(ifChangedFrom:)``,
    /// and for the same reason: an access token rejected here is usually one minted before
    /// a rotation. Everything else answers `nil` — a 404 for an account with no picture, a
    /// 502 when the provider is slow, a body that is not an image. None of those is worth
    /// a message to somebody who is looking at their own initials and does not know a
    /// request was made.
    ///
    /// The path is taken from the document rather than composed here, but it is still
    /// checked: it must be a path on this API and not an address of its own, so that a
    /// document from somewhere unexpected cannot point this at another host.
    public func avatar(at path: String) async -> Data? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), URL(string: path)?.host == nil else {
            return nil
        }
        guard let address = URL(string: baseURL.absoluteString + path.dropFirst()) else {
            return nil
        }

        guard let first = try? await authorised(), case .token(let token) = first else {
            return nil
        }
        guard var response = try? await send(get(address, token: token)) else { return nil }

        if response.status == 401 {
            guard let renewed = try? await renew(), case .token(let token) = renewed,
                let retried = try? await send(get(address, token: token))
            else { return nil }
            response = retried
        }

        guard response.isSuccess, !response.body.isEmpty else { return nil }
        return response.body
    }

    /// Signs out here first, and tells the server afterwards.
    ///
    /// The order matters. A person asking to be signed out is signed out whatever the
    /// network is doing; the request that revokes the token at the other end is worth
    /// making and not worth waiting on, and the token expires on its own regardless.
    public func signOut() async {
        let refreshToken = tokens.refreshToken()
        forgetSession()

        guard let refreshToken else { return }
        _ = try? await transport.perform(post("v1/auth/sign-out", SignOutBody(refreshToken: refreshToken)))
    }

    // MARK: The session

    private enum Authorisation {
        case token(String)

        /// The server refused the refresh token: revoked, replayed, or expired.
        case sessionOver

        /// This Mac holds no refresh token, so the server was never asked. Not a refusal,
        /// and not something a caller may treat as one — see ``ProfileRefresh/noCredential``.
        case noCredential
    }

    /// A usable access token, minting one from the refresh token when there is none.
    private func authorised() async throws(AccountError) -> Authorisation {
        let current = access.withLock { $0 }
        if let current, current.expiresAt.timeIntervalSince(now()) > Self.renewalMargin {
            return .token(current.value)
        }
        return try await renew()
    }

    private func renew() async throws(AccountError) -> Authorisation {
        guard let refreshToken = tokens.refreshToken() else { return .noCredential }

        let response = try await send(
            post("v1/auth/refresh", RefreshBody(refreshToken: refreshToken, device: device?.registration())))

        // The refresh token was revoked, replayed, or has expired. All three mean the same
        // thing to this Mac: it is signed out, and it should stop pretending otherwise.
        if response.status == 401 {
            forgetSession()
            return .sessionOver
        }
        guard response.isSuccess, let session = decode(IssuedSession.self, from: response.body) else {
            throw refusal(response)
        }
        try adopt(session)
        return .token(session.accessToken)
    }

    /// Keeps what a session response gave us: the new refresh token to the Keychain, the
    /// access token to memory. Rotation means the old refresh token is already dead, so
    /// storing the new one is not optional housekeeping — it is the session.
    ///
    /// - Throws: ``AccountError/sessionCouldNotBeKept`` when the Keychain refuses it.
    ///   Reporting a sign-in that succeeded everywhere except the one place that makes it
    ///   last is worse than reporting a failure: the account appears, works, and is gone
    ///   at the next launch with nothing to connect the two.
    private func adopt(_ session: IssuedSession) throws(AccountError) {
        try tokens.store(session.refreshToken)
        access.withLock {
            $0 = AccessToken(
                value: session.accessToken,
                expiresAt: Timestamp.date(from: session.accessTokenExpiresAt) ?? now())
        }
    }

    /// Keeps the session a sign-in was answered with, then reads the profile it unlocks.
    private func beginSession(issuedBy response: BackendResponse) async throws(AccountError) -> Profile {
        guard let session = decode(IssuedSession.self, from: response.body) else {
            throw .providerRefused(description: "the server issued a session we could not read")
        }
        try adopt(session)
        return try await readProfile(validator: nil)
    }

    /// Drops both halves of the session, which is what signing out means on this Mac.
    private func forgetSession() {
        tokens.clear()
        access.withLock { $0 = nil }
    }

    // MARK: Reading the profile

    private func readProfile(validator: String?) async throws(AccountError) -> Profile {
        switch try await authorised() {
        case .sessionOver, .noCredential:
            // Reachable only if the session was revoked, or the credential just stored
            // could not be read back, between claiming it and reading it. Both are a
            // refusal of the sign-in that is happening right now, where there is somebody
            // to tell — which is the whole reason this does not fall back to a cache.
            throw .providerRefused(description: "that session was already over")
        case .token(let token):
            let response = try await send(profileRequest(token, ifNoneMatch: validator))
            guard response.isSuccess else { throw refusal(response) }
            return try believe(response)
        }
    }

    /// Decodes a profile and refuses to believe it unless it is signed and self-consistent.
    ///
    /// The signature check is the same one a cached copy gets on the way off the disk. It
    /// happens here as well because a profile that cannot be believed should fail the
    /// sign-in that produced it, where there is somebody to tell, rather than surface as a
    /// mysterious sign-out on a later launch.
    private func believe(_ response: BackendResponse) throws(AccountError) -> Profile {
        guard let profile = decode(Profile.self, from: response.body) else {
            throw .sessionMalformed
        }
        guard verifier.isAuthentic(profile.entitlement), profile.isInternallyConsistent else {
            throw .sessionMalformed
        }
        return profile.remembering(validator: response.header("ETag"))
    }

    // MARK: Plumbing

    private func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    /// A JSON body posted to `path`.
    private func post(_ path: String, _ body: some Encodable) -> BackendRequest {
        BackendRequest(
            method: .post, url: url(path), headers: ["Content-Type": "application/json"],
            body: encode(body))
    }

    /// A bearer-authorised read of `address`, conditional on `validator` when there is one.
    private func get(_ address: URL, token: String, ifNoneMatch validator: String? = nil) -> BackendRequest {
        var headers = ["Authorization": "Bearer \(token)"]
        if let validator { headers["If-None-Match"] = validator }
        return BackendRequest(method: .get, url: address, headers: headers)
    }

    private func profileRequest(_ token: String, ifNoneMatch validator: String?) -> BackendRequest {
        get(url("v1/me"), token: token, ifNoneMatch: validator)
    }

    private func send(_ request: BackendRequest) async throws(AccountError) -> BackendResponse {
        do {
            return try await transport.perform(request)
        } catch {
            throw .serverUnreachable
        }
    }

    /// Turns a refusal into the sentence the server sent, when it sent one.
    ///
    /// A `5xx` is deliberately *not* treated as unreachable. The server was reached and it
    /// failed; calling that "no connection" would tell the user to check their Wi-Fi over
    /// an outage they cannot do anything about, and would hide the outage from us.
    private func refusal(_ response: BackendResponse) -> AccountError {
        let answered = decode(ServerError.self, from: response.body)
        let described = answered?.message ?? answered?.errorDescription
        return .providerRefused(description: described ?? "the server refused that (\(response.status))")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    private func encode(_ value: some Encodable) -> Data {
        // A value of strings and optionals cannot fail to encode, and an empty body would
        // be refused by the server, which is the correct outcome for a bug that cannot
        // happen.
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}

// MARK: - What the backend sends and expects

private struct IssuedSession: Decodable {
    let accessToken: String
    let accessTokenExpiresAt: String
    let refreshToken: String
}

/// What the token endpoint expects. The names are the backend's, which are OAuth's.
private struct TokenBody: Encodable {
    let grantType: String
    let clientID: String
    let code: String
    let codeVerifier: String
    let redirectURI: String
    let device: DeviceRegistration?

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case clientID = "client_id"
        case code
        case codeVerifier = "code_verifier"
        case redirectURI = "redirect_uri"
        case device
    }
}

private struct RefreshBody: Encodable {
    let refreshToken: String
    let device: DeviceRegistration?
}

private struct SignOutBody: Encodable {
    let refreshToken: String
}

private struct ServerError: Decodable {
    let error: String?
    let message: String?
    /// The OAuth spelling. The two names exist because this service answers with
    /// `message` and the RFC-shaped endpoints answer with `error_description`.
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case message
        case errorDescription = "error_description"
    }
}

private struct DeviceCodeBody: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey { case clientID = "client_id" }
}

private struct StartedDeviceSignIn: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let verificationUriComplete: String?
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case verificationUriComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct DeviceTokenBody: Encodable {
    let grantType: String
    let clientID: String
    let deviceCode: String
    let device: DeviceRegistration?

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case clientID = "client_id"
        case deviceCode = "device_code"
        case device
    }
}
