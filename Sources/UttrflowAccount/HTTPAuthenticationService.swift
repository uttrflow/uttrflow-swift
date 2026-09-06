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

/// Signs in and stays signed in against the HTTP backend by the rules in `Docs/account-session.md`.
public final class HTTPAuthenticationService: AuthenticationService {
    /// This build's registered client identifier; not a credential, PKCE covers what an app cannot hide.
    public static let defaultClientID = "uttrflow-mac"

    /// Renews the access token this long before expiry, so no request carries a token that dies in flight.
    private static let renewalMargin: TimeInterval = 60

    /// The in-memory half of the session: the bearer value and when it stops being valid.
    private struct AccessToken: Sendable {
        /// The bearer token sent as `Authorization`.
        let value: String
        /// When the server stops accepting `value`.
        let expiresAt: Date
    }

    /// A sign-in waiting to finish; kept off ``SignInChallenge`` so no public value carries a secret.
    private enum Pending {
        /// Waits on a port for the browser to come back, holding the verifier that spends the code.
        case browser(state: String, pkce: PKCEPair, redirectURI: URL, listener: any LoopbackListening)

        /// Waiting on a person typing a code somewhere else, and polling until they have.
        case code(state: String, deviceCode: String, interval: Duration, expiresAt: Date)

        /// The state the challenge must echo back for this attempt to be the one it answers.
        var state: String {
            switch self {
            case .browser(let state, _, _, _): state
            case .code(let state, _, _, _): state
            }
        }
    }

    /// The API root every path below is appended to.
    private let baseURL: URL
    /// The client identifier sent with every OAuth request.
    private let clientID: String
    /// Performs the HTTP calls; throws only when a request never happened.
    private let transport: any BackendTransport
    /// Where the refresh token lives between launches.
    private let tokens: any TokenStore
    /// This Mac's registration, sent so the server can name the device; `nil` sends none.
    private let device: (any DeviceIdentifying)?
    /// Checks the signature on every entitlement before a profile is believed.
    private let verifier: any EntitlementVerifying
    /// Makes the loopback listener a browser sign-in comes back to.
    private let makeListener: @Sendable () -> any LoopbackListening
    /// The randomness behind the PKCE verifier and the state.
    private let randomBytes: @Sendable (Int) -> Data
    /// The clock, injected so a test can move it.
    private let now: @Sendable () -> Date
    /// How the device flow waits between polls; injected so a test does not wait.
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The short-lived half of the session; a `Mutex`, not an actor, as nothing done with it is slow.
    private let access = Mutex<AccessToken?>(nil)

    /// The attempt in flight; a second sign-in replaces the first and closes its port.
    private let pending = Mutex<Pending?>(nil)

    /// Wires the transport, stores and clocks; every default is the one the shipping app uses.
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

    /// Cryptographically secure randomness for the PKCE verifier and the state.
    public static func systemRandomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        var bytes = Data(count: count)
        for index in 0..<count {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        }
        return bytes
    }

    // MARK: Signing in

    /// Binds a port before returning the page to open, and signs in by code instead when no port binds.
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
            // The backend parses a provider name in any capitalisation, so `gitHub` is sent as spelled.
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

    /// Signs in by RFC 8628 device code, for a machine with nowhere for a browser to come back to.
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

    /// Waits however long the person takes to sign in; cancelling the task closes the port and abandons it.
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

        // Checked here as well as by the backend: an answer naming another attempt is not ours to spend.
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

    /// Polls until the code is approved or expires, waiting longer when the server says `slow_down`.
    private func awaitDeviceApproval(
        _ deviceCode: String, every interval: Duration, until expiresAt: Date
    ) async throws(AccountError) -> Profile {
        var wait = interval

        while true {
            do {
                try await sleep(wait)
            } catch {
                // Cancellation: the person walked away, and the code expires on its own.
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

    /// Reads the profile if it changed, renewing a rejected access token once before giving up on it.
    public func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        guard tokens.refreshToken() != nil else { return .noCredential }

        switch try await authorised() {
        case .sessionOver: return .signedOut
        case .noCredential: return .noCredential
        case .token(let token):
            let response = try await send(profileRequest(token, ifNoneMatch: cached?.validator))

            if response.status == 304 { return .unchanged }

            // One retry only: a second 401 after a fresh token means the session is gone, not the token.
            if response.status == 401 {
                switch try await renew() {
                case .sessionOver: return .signedOut
                // Another caller met a 401 and cleared the credential; that caller acts on it, not this one.
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

    /// Fetches the avatar at a path on this API, or `nil` for any failure; none is worth a message.
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

    /// Signs out on this Mac first, whatever the network is doing, then tells the server without waiting.
    public func signOut() async {
        let refreshToken = tokens.refreshToken()
        forgetSession()

        guard let refreshToken else { return }
        _ = try? await transport.perform(post("v1/auth/sign-out", SignOutBody(refreshToken: refreshToken)))
    }

    // MARK: The session

    /// What asking for an access token produces.
    private enum Authorisation {
        /// A usable access token.
        case token(String)

        /// The server refused the refresh token: revoked, replayed, or expired.
        case sessionOver

        /// No refresh token is held, so the server was never asked; not a refusal, see ``ProfileRefresh``.
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

    /// Mints a session from the refresh token; a 401 means this Mac is signed out.
    private func renew() async throws(AccountError) -> Authorisation {
        guard let refreshToken = tokens.refreshToken() else { return .noCredential }

        let response = try await send(
            post("v1/auth/refresh", RefreshBody(refreshToken: refreshToken, device: device?.registration())))

        // Revoked, replayed or expired: all three mean this Mac is signed out.
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

    /// Keeps a session: refresh token to the Keychain, access token to memory; a Keychain refusal throws.
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

    /// Reads the profile a fresh session unlocks, refusing the sign-in rather than falling back to a cache.
    private func readProfile(validator: String?) async throws(AccountError) -> Profile {
        switch try await authorised() {
        case .sessionOver, .noCredential:
            // The session ended between claim and read; a refusal reaches somebody, a cache would not.
            throw .providerRefused(description: "that session was already over")
        case .token(let token):
            let response = try await send(profileRequest(token, ifNoneMatch: validator))
            guard response.isSuccess else { throw refusal(response) }
            return try believe(response)
        }
    }

    /// Decodes a profile and refuses one that is unsigned or inconsistent, failing the sign-in itself.
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

    /// `path` appended to the API root.
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

    /// A conditional read of `v1/me`.
    private func profileRequest(_ token: String, ifNoneMatch validator: String?) -> BackendRequest {
        get(url("v1/me"), token: token, ifNoneMatch: validator)
    }

    /// Performs a request, translating a transport failure into ``AccountError/serverUnreachable``.
    private func send(_ request: BackendRequest) async throws(AccountError) -> BackendResponse {
        do {
            return try await transport.perform(request)
        } catch {
            throw .serverUnreachable
        }
    }

    /// Turns a refusal into the server's own sentence; a `5xx` is a server that failed, not one out of reach.
    private func refusal(_ response: BackendResponse) -> AccountError {
        let answered = decode(ServerError.self, from: response.body)
        let described = answered?.message ?? answered?.errorDescription
        return .providerRefused(description: described ?? "the server refused that (\(response.status))")
    }

    /// Decodes `data` as `type`, or `nil` when it is not that shape.
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    /// Encodes a request body.
    private func encode(_ value: some Encodable) -> Data {
        // Strings and optionals cannot fail to encode, and the server refuses an empty body anyway.
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}

// MARK: - What the backend sends and expects

/// The two tokens a sign-in or refresh answers with.
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

/// What the refresh endpoint expects.
private struct RefreshBody: Encodable {
    let refreshToken: String
    let device: DeviceRegistration?
}

/// What the sign-out endpoint expects.
private struct SignOutBody: Encodable {
    let refreshToken: String
}

/// A refusal's body, in either the service's or OAuth's spelling.
private struct ServerError: Decodable {
    let error: String?
    let message: String?
    /// The OAuth spelling: RFC-shaped endpoints answer with `error_description`, this service with `message`.
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case message
        case errorDescription = "error_description"
    }
}

/// What the device-code endpoint expects.
private struct DeviceCodeBody: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey { case clientID = "client_id" }
}

/// What the device-code endpoint answers with, in RFC 8628's names.
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

/// What the device-token endpoint expects while polling.
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
