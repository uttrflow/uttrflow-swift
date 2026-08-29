import ArgumentParser
import Foundation
import UttrflowAccount
import UttrflowCore

/// Signs in against a real backend, using the same code the app uses.
///
/// The account tests substitute one half of the flow to make the other testable, and the
/// end-to-end suite needs a provider that redirects straight back — which development has
/// and production, by definition, does not. Neither can answer "does signing in work
/// against the deployment people will actually use", because answering that needs a real
/// person at a real browser with a real Google account.
///
/// This is that, minus the app's window: the same `HTTPAuthenticationService`, the same
/// transport, the same loopback listener, the same entitlement verification. It prints the
/// page to open, waits while somebody signs in, and prints what came back.
///
///     swift run uttrflow-dev sign-in --backend https://api.uttrflow.com
///     swift run uttrflow-dev sign-in --backend https://api.uttrflow.com --by-code
///
/// Nothing is written to the Keychain: tokens live in memory and die with the process, so
/// running this never disturbs the signed-in state of the app on this Mac.
struct SignIn: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sign-in",
        abstract: "Sign in against a running backend, with the app's own client code.")

    @Option(help: "The backend to sign in against.")
    var backend: String = "http://127.0.0.1:8787"

    @Flag(help: "Take the device-code path, as a Mac that cannot bind a port would.")
    var byCode = false

    @Option(help: "How long to wait for the browser half, in seconds.")
    var timeout: Int = 180

    func run() async throws {
        // Unbuffered, because the useful thing this prints — the page to open — is printed
        // while the command is still running, and a redirected stdout would hold it until
        // the process exits. Which is after the sign-in it is waiting for.
        setvbuf(stdout, nil, _IONBF, 0)

        guard let baseURL = URL(string: backend) else {
            throw ValidationError("\(backend) is not a URL.")
        }

        // The key this deployment publishes, not the one this build was compiled with. The
        // two matching is the thing worth checking; assuming it would hide exactly the
        // mismatch that makes every entitlement fail to verify on a real Mac.
        let liveKey = try await publishedKey(baseURL)
        let verifier = try makeVerifier(for: liveKey)
        let compiled = Ed25519EntitlementVerifier.releasePublicKeyBase64
        print("backend        \(baseURL.absoluteString)")
        print("deployed key   \(liveKey)")
        print(
            "compiled key   \(compiled) "
                + (liveKey == compiled
                    ? "— same key" : "— DIFFERENT, this build will reject its entitlements"))

        // `--by-code` is the only part of this that is pretended: a Mac whose security
        // software refuses to let an application listen cannot be arranged on demand.
        // Everything the backend sees after that is real.
        let makeListener: @Sendable () -> any LoopbackListening
        if byCode {
            makeListener = { RefusingListener() as any LoopbackListening }
        } else {
            makeListener = { SystemLoopbackListener() as any LoopbackListening }
        }

        let tokens = InMemoryTokenStore()
        let service = HTTPAuthenticationService(
            baseURL: baseURL,
            transport: URLSessionTransport(),
            tokens: tokens,
            device: MacDeviceIdentity.system(),
            verifier: verifier,
            makeListener: makeListener)

        let challenge = try await service.beginSignIn(with: .google)

        switch challenge.method {
        case .browser:
            print("\nOpen this, sign in, and this command will finish on its own:\n")
            print(challenge.authorisationURL.absoluteString)
        case .code(let userCode, let verificationURL):
            print("\nOpen \(verificationURL.absoluteString)")
            print("and enter the code:  \(userCode)")
        }

        print("\nwaiting up to \(timeout)s …")
        let profile = try await withThrowingTaskGroup(of: Profile.self) { group in
            group.addTask { try await service.completeSignIn(challenge) }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw ValidationError("nobody finished signing in within \(timeout)s")
            }
            for try await first in group {
                group.cancelAll()
                return first
            }
            throw ValidationError("the sign-in ended without saying why.")
        }

        print("\nsigned in")
        print("  name         \(profile.account.displayName ?? "—")")
        print("  email        \(profile.account.emailAddress ?? "not shared")")
        print("  provider     \(profile.account.provider)")
        print("  plan         \(profile.entitlement.plan)")
        print("  consistent   \(profile.isInternallyConsistent)")
        print("  validator    \(profile.validator ?? "none")")
        print("  refresh kept \(tokens.refreshToken() != nil)")
        if let current = profile.currentDevice {
            print("  this device  \(current.name) · \(current.platform)")
        } else {
            print("  this device  NOT in the list")
        }

        // The second launch: the same profile re-read, which should cost a 304.
        let again = try await service.currentProfile(ifChangedFrom: profile)
        print("  re-read      \(again == .unchanged ? "unchanged (304)" : "a fresh document")")

        await service.signOut()
        print("  signed out   \(tokens.refreshToken() == nil)")
    }

    /// The key this deployment publishes, read rather than assumed.
    private func publishedKey(_ backend: URL) async throws -> String {
        struct Health: Decodable { let entitlementPublicKey: String }
        let (data, _) = try await URLSession.shared.data(from: backend.appending(path: "v1/health"))
        return try JSONDecoder().decode(Health.self, from: data).entitlementPublicKey
    }

    private func makeVerifier(for base64: String) throws -> Ed25519EntitlementVerifier {
        guard let bytes = Data(base64Encoded: base64) else {
            throw ValidationError("the backend published an entitlement key that is not base64.")
        }
        return Ed25519EntitlementVerifier(publicKeyBytes: bytes)
    }
}

/// A listener that will not bind, standing in for a Mac whose security software refuses.
private struct RefusingListener: LoopbackListening {
    func bind() async throws(AccountError) -> URL { throw .serverUnreachable }
    func awaitCallback() async throws(AccountError) -> LoopbackCallback { throw .serverUnreachable }
    func close() async {}
}
