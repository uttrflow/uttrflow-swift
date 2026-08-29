import Foundation
import UttrflowAccount
import UttrflowUX

/// The backend, and the cache that believes what it signs.
///
/// One value rather than two independent defaults, because the two have to agree. A
/// profile cache carrying the release public key refuses every entitlement the development
/// service mints, and the user meets that as a sign-in that fails with a signature error
/// nobody can act on. Pairing them here makes the disagreement unrepresentable.
struct OnboardingAccountLayer {
    let authentication: any AuthenticationService
    let profiles: any ProfileCache
    /// Where the choice to work without an account is kept.
    ///
    /// Paired with the other two rather than made where it is needed, for the same reason
    /// they are paired: three windows read it — onboarding writes it, the main window
    /// draws from it, and the gate decides on it — and three separate stores would be
    /// three answers to one question.
    let local: any LocalAccountStore

    /// Re-reads the profile from the server and caches whatever comes back.
    var refresh: AccountRefresh {
        AccountRefresh(service: authentication, profiles: profiles)
    }

    /// The Info.plist key naming the backend. Absent in a development build, which is
    /// what makes a development build one.
    static let endpointKey = "UttrflowBackendURL"

    /// Whichever backend this build is equipped to talk to.
    ///
    /// Two things must be true before the real one is used: an address to reach it at, and
    /// a public key to check what it signs. Either one alone produces a build that can
    /// sign somebody in and then refuse the entitlement it was handed, which is the most
    /// confusing failure this module can produce — so the choice is made once, here, and
    /// the development service is the answer whenever the pair is incomplete.
    static func forThisBuild(bundle: Bundle = .main) -> OnboardingAccountLayer {
        let configured = (bundle.object(forInfoDictionaryKey: endpointKey) as? String)
            .flatMap(URL.init(string:))
        guard let configured, Ed25519EntitlementVerifier.release.isConfigured else {
            return development()
        }
        return production(baseURL: configured)
    }

    /// The real thing: a URL session, the Keychain, and this Mac's own identity.
    static func production(baseURL: URL) -> OnboardingAccountLayer {
        OnboardingAccountLayer(
            authentication: HTTPAuthenticationService(
                baseURL: baseURL,
                transport: URLSessionTransport(),
                tokens: KeychainTokenStore(),
                device: MacDeviceIdentity.system()),
            profiles: UserDefaultsProfileCache(),
            local: UserDefaultsLocalAccountStore())
    }

    /// What the app runs on until a backend has been deployed and a key compiled in.
    ///
    /// The signature check is live, not switched off: the development service holds a real
    /// Ed25519 key and the cache checks against its public half, so the verifying path is
    /// exercised every time somebody signs in rather than meeting its first signature on
    /// release day. The key is generated per process, so a profile cached by one run is not
    /// believed by the next — correct for development, and exactly what the real backend's
    /// stable key fixes.
    static func development() -> OnboardingAccountLayer {
        let service = InMemoryAuthenticationService()
        return OnboardingAccountLayer(
            authentication: service,
            profiles: UserDefaultsProfileCache(verifier: service.verifier),
            local: UserDefaultsLocalAccountStore())
    }
}
