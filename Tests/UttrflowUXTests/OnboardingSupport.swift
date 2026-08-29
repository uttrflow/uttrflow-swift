import Foundation
import UttrflowTestSupport
import Synchronization

@testable import UttrflowAccount
@testable import UttrflowCore
@testable import UttrflowSettings
@testable import UttrflowUX

// MARK: - Holding a call open

/// One call, held until the test lets it through.
///
/// The flow guards everything that finishes somewhere else — a browser tab, a
/// microphone — against the user having walked away in the meantime. Proving those
/// guards work means being *inside* the call when the user walks away, which is not
/// something a test can reach by winning a race.
final class Gate: Sendable {
    private let continuation = Mutex<AsyncStream<Void>.Continuation?>(nil)
    private let entered = Mutex(0)

    /// How many calls have reached the gate, so a test can wait for one to arrive.
    var arrivals: Int { entered.withLock { $0 } }

    func wait() async {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.continuation.withLock { $0 = continuation }
        entered.withLock { $0 += 1 }
        for await _ in stream { break }
    }

    func open() {
        continuation.withLock { $0 }?.finish()
    }
}

// MARK: - Doubles

/// A key-value store in memory, so no test writes to the user's real preferences.
final class InMemoryKeyValueStore: KeyValueStore {
    private let contents = Mutex<[String: Data]>([:])

    var keys: Set<String> {
        contents.withLock { Set($0.keys) }
    }

    func data(forKey key: String) -> Data? {
        contents.withLock { $0[key] }
    }

    func set(_ data: Data?, forKey key: String) {
        contents.withLock { $0[key] = data }
    }
}

/// The onboarding record, with the launch it survived scripted rather than stored.
final class FakeRecordStore: OnboardingRecordStore {
    private let finished: Mutex<Bool>

    init(hasFinished: Bool = false) {
        finished = Mutex(hasFinished)
    }

    var hasFinished: Bool { finished.withLock { $0 } }

    func recordFinished() {
        finished.withLock { $0 = true }
    }
}

/// A download the test drives one instruction at a time.
///
/// Held open rather than run to completion so that the states in the middle of a
/// download — progress arriving, the user cancelling, the connection giving out — are
/// reached deliberately instead of by winning a race with a background task.
final class GatedInstaller: OnboardingModelInstaller {
    enum Instruction: Sendable {
        case report(Double)
        case succeed
        case fail(SpeechEngineError)
    }

    /// The instruction channel for the download that is running, if one is.
    ///
    /// Made afresh for each download rather than shared, because a retry is a second
    /// download and an ``AsyncStream`` has only one consumer in it.
    private let gate = Mutex<AsyncStream<Instruction>.Continuation?>(nil)
    private let installed: Mutex<Bool>
    private let attempts = Mutex(0)

    init(isInstalled: Bool = false) {
        installed = Mutex(isInstalled)
    }

    var isInstalled: Bool { installed.withLock { $0 } }

    /// How many times a download has been started, so a retry can be told from a
    /// page that merely redrew.
    var startedDownloads: Int { attempts.withLock { $0 } }

    func send(_ instruction: Instruction) {
        gate.withLock { $0 }?.yield(instruction)
    }

    func install(onProgress: @escaping @Sendable (Double) -> Void) async throws(SpeechEngineError) {
        let (stream, continuation) = AsyncStream<Instruction>.makeStream()
        gate.withLock { $0 = continuation }
        attempts.withLock { $0 += 1 }
        defer { gate.withLock { $0 = nil } }

        for await instruction in stream {
            switch instruction {
            case .report(let fraction):
                onProgress(fraction)
            case .succeed:
                installed.withLock { $0 = true }
                return
            case .fail(let error):
                throw error
            }
        }
    }
}

/// A download that is over before it is asked about.
///
/// Every test that is not about the download itself uses this, so the setup page never
/// becomes an accidental part of some other test's story.
struct InstantInstaller: OnboardingModelInstaller {
    let isInstalled: Bool

    func install(onProgress: @escaping @Sendable (Double) -> Void) async throws(SpeechEngineError) {
        onProgress(1)
    }
}

// MARK: - The account

/// An entitlement with nothing interesting about it but its expiry.
func anEntitlement(expiring: Date = .distantFuture) -> Entitlement {
    Entitlement(
        account: Account(
            identifier: "someone", displayName: "Someone", emailAddress: nil, provider: .google),
        plan: .pro, expiresAt: expiring, signature: "signed")
}

/// A whole profile around one entitlement, which is what a sign-in now produces.
func aProfile(expiring: Date = .distantFuture) -> Profile {
    let entitlement = anEntitlement(expiring: expiring)
    return Profile(
        account: entitlement.account,
        subscription: Profile.Subscription(
            plan: .pro, status: .active, currentPeriodEnd: expiring, effectivePlan: .pro,
            limits: Profile.Limits(monthlyMinutes: nil, customDictionaryEntries: nil)),
        devices: [],
        entitlement: entitlement,
        fetchedAt: .distantPast,
        validator: "\"a-validator\"")
}

/// The profile on this Mac, in memory, believing whatever it is handed.
///
/// Signatures are ``UserDefaultsProfileCache``'s business and are tested there. What
/// onboarding needs from a cache is that a saved profile is found again, and that a cache
/// which refuses says so.
final class InMemoryProfileCache: ProfileCache {
    private let held: Mutex<Profile?>
    private let refusesToSave: Bool

    init(holding profile: Profile? = nil, refusesToSave: Bool = false) {
        held = Mutex(profile)
        self.refusesToSave = refusesToSave
    }

    func load() -> Profile? { held.withLock { $0 } }

    func save(_ profile: Profile) throws(AccountError) {
        if refusesToSave { throw .sessionMalformed }
        held.withLock { $0 = profile }
    }

    func clear() {
        held.withLock { $0 = nil }
    }
}

/// A backend the test scripts one answer at a time.
final class FakeAuthenticationService: AuthenticationService, @unchecked Sendable {
    /// The state value every challenge carries, so a test can echo it back — or not.
    static let state = "the-attempt-in-flight"

    private let beginFailure: AccountError?
    private let completeFailure: AccountError?
    /// Held open so a test can cancel while the call is still running.
    let beginGate: Gate?
    let completeGate: Gate?
    private let started = Mutex<[SignInProvider]>([])

    /// Whether a cancelled task stops the exchange.
    ///
    /// True models the real service, whose polling stops when the task is cancelled. False
    /// models the one case where cancelling cannot help: the backend had already minted
    /// the session when the user pressed Cancel, and the answer is on its way.
    private let respectsCancellation: Bool
    /// How this machine is going to finish signing in, which the machine decides.
    private let method: SignInMethod

    init(
        beginFailure: AccountError? = nil,
        completeFailure: AccountError? = nil,
        beginGate: Gate? = nil,
        completeGate: Gate? = nil,
        method: SignInMethod = .browser,
        respectsCancellation: Bool = true
    ) {
        self.method = method
        self.beginFailure = beginFailure
        self.completeFailure = completeFailure
        self.beginGate = beginGate
        self.completeGate = completeGate
        self.respectsCancellation = respectsCancellation
    }

    /// Which providers were asked for, in order.
    var startedProviders: [SignInProvider] { started.withLock { $0 } }

    func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        started.withLock { $0.append(provider) }
        await beginGate?.wait()
        if let beginFailure { throw beginFailure }
        return SignInChallenge(
            authorisationURL: safeSignInURL(provider), state: FakeAuthenticationService.state,
            method: method)
    }

    func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile {
        await completeGate?.wait()
        if respectsCancellation, Task.isCancelled {
            throw .providerRefused(description: "that sign-in was abandoned")
        }
        if let completeFailure { throw completeFailure }
        return aProfile()
    }

    /// Onboarding never re-reads the profile — that is the launch path's job — so this
    /// answers the one thing that keeps the type honest.
    func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        cached == nil ? .signedOut : .unchanged
    }

    /// Nothing in onboarding draws a picture, so nothing here fetches one.
    func avatar(at path: String) async -> Data? { nil }

    func signOut() async {}
}

/// A URL without a force unwrap, which this package forbids.
func safeSignInURL(_ provider: SignInProvider) -> URL {
    URL(string: "https://sign-in.invalid/\(provider.rawValue)") ?? URL(filePath: "/")
}

/// Where the browser was sent.
final class BrowserRecorder: Sendable {
    private let visited = Mutex<[URL]>([])

    var urls: [URL] { visited.withLock { $0 } }

    var open: @Sendable (URL) -> Void {
        { url in self.visited.withLock { $0.append(url) } }
    }
}

/// The connection, as the test says it is.
final class FakeReachability: NetworkReachability {
    private let reachable: Mutex<Bool>

    init(_ isReachable: Bool) {
        reachable = Mutex(isReachable)
    }

    var isReachable: Bool { reachable.withLock { $0 } }

    func set(_ isReachable: Bool) {
        reachable.withLock { $0 = isReachable }
    }
}

/// Where the user was sent, in the order they were sent there.
final class PaneRecorder: Sendable {
    private let opened = Mutex<[SystemSettingsPane]>([])

    var panes: [SystemSettingsPane] { opened.withLock { $0 } }

    var open: @Sendable (SystemSettingsPane) -> Void {
        { pane in self.opened.withLock { $0.append(pane) } }
    }
}

// MARK: - Harness

/// One flow with everything around it substituted, and the states it published.
@MainActor
final class Harness {
    let microphone: FakePermissionGate
    let accessibility: FakePermissionGate
    let installer: any OnboardingModelInstaller
    let record: FakeRecordStore
    let settingsStore: UserDefaultsSettingsStore
    let authentication: FakeAuthenticationService
    let profiles: InMemoryProfileCache
    /// Where "continue on this Mac" writes. Exposed so a test can assert on what the
    /// button actually recorded rather than only on the page it landed the user.
    let local = InMemoryLocalAccountStore()
    let network: FakeReachability
    let browser = BrowserRecorder()
    let panes = PaneRecorder()
    let flow: OnboardingFlow

    /// Every state the flow published, so a test can assert on what the user saw on
    /// the way and not only on where they ended up.
    private(set) var published: [OnboardingState] = []
    private(set) var finishedWith: OnboardingReadiness?

    /// `signedIn` defaults to *yes*, so that a test about a permission is not also a
    /// test about signing in — the same reason the installer defaults to a model that is
    /// already there. `check` defaults to `nil`, which passes the optional microphone
    /// check over entirely, for that same reason.
    init(
        microphone: PermissionStatus = .notDetermined,
        microphoneAfterAsking: PermissionStatus? = .granted,
        accessibility: PermissionStatus = .denied,
        accessibilityAfterAsking: PermissionStatus? = nil,
        installer: any OnboardingModelInstaller = InstantInstaller(isInstalled: true),
        settings: Settings = .default,
        hasFinished: Bool = false,
        signedIn: Bool = true,
        entitlementExpiring: Date = .distantFuture,
        profiles: InMemoryProfileCache? = nil,
        // Gated by default, so that `choose` leaves the flow where the user would see it:
        // waiting on a browser window. A test that wants the sign-in to finish says so, by
        // calling `returnFromBrowser`.
        authentication: FakeAuthenticationService = FakeAuthenticationService(completeGate: Gate()),
        reachable: Bool = true,
        /// What macOS would call the person at this Mac. Named here so a test about the
        /// Mac account is not also a test about whoever is running it.
        systemName: String? = "Naveen Bhatt",
        now: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) {
        self.microphone = FakePermissionGate(
            kind: .microphone, status: microphone, statusAfterRequest: microphoneAfterAsking)
        self.accessibility = FakePermissionGate(
            kind: .accessibility, status: accessibility,
            statusAfterRequest: accessibilityAfterAsking)
        self.installer = installer
        self.record = FakeRecordStore(hasFinished: hasFinished)
        self.settingsStore = UserDefaultsSettingsStore(store: InMemoryKeyValueStore())
        self.settingsStore.save(settings)
        self.authentication = authentication
        self.profiles =
            profiles
            ?? InMemoryProfileCache(
                holding: signedIn ? aProfile(expiring: entitlementExpiring) : nil)
        self.network = FakeReachability(reachable)
        self.flow = OnboardingFlow(
            microphone: self.microphone,
            accessibility: self.accessibility,
            installer: installer,
            settingsStore: settingsStore,
            record: record,
            authentication: authentication,
            profiles: self.profiles,
            local: local,
            network: network,
            systemName: { systemName },
            openBrowser: browser.open,
            openSystemSettings: panes.open,
            now: { now }
        )
        flow.onChange = { [weak self] state in self?.published.append(state) }
        flow.onFinish = { [weak self] readiness in self?.finishedWith = readiness }
    }

    /// Starts, and reads past the welcome page to the one that asks for something.
    ///
    /// Welcome is first so the product says what it is before it asks who you are, which
    /// means every test about a later page has a page of pitch in front of it. Written
    /// once here rather than as a stray `advance` at the top of each test, so moving the
    /// pitch again is one edit.
    func startPastWelcome() async {
        await flow.start()
        if flow.state.step == .welcome { await flow.perform(.advance) }
    }

    var step: OnboardingStep { flow.state.step }
    var detail: OnboardingDetail { flow.state.detail }
    var page: OnboardingPage { flow.page }
    var buttonTitles: [String] { page.buttons.map(\.title) }

    /// The providers the page will actually let somebody press, which offline is none
    /// of the three that are on screen.
    var liveProviders: [SignInProvider] { page.providers.filter(\.isEnabled).map(\.provider) }

    /// Presses the button with this title, failing the caller's expectation if the page
    /// is not offering it.
    func press(_ title: String) async -> Bool {
        guard let button = page.buttons.first(where: { $0.title == title && $0.isEnabled })
        else { return false }
        await flow.perform(button.intent)
        return true
    }

    /// Presses one of the provider buttons, and answers `false` when the page is not
    /// offering it as something that can be pressed.
    /// Presses a provider's button, and waits for the app to get as far as the browser.
    ///
    /// The sign-in runs in a task of its own — it has to, because it stays open until the
    /// person has finished with the browser — so the intent returns long before anything
    /// has been asked of the backend. Settling here rather than in every test keeps the
    /// tests about what the user sees.
    func choose(_ provider: SignInProvider) async -> Bool {
        guard page.providers.contains(where: { $0.provider == provider && $0.isEnabled })
        else { return false }
        await flow.perform(.signIn(provider))
        await settle(until: { !self.authentication.startedProviders.isEmpty })
        // Either the browser is open, or the attempt failed before it got that far.
        await settle(until: { !self.browser.urls.isEmpty || !self.isSigningIn })
        return true
    }

    /// The backend answering the sign-in the app is waiting on.
    ///
    /// There is no callback any more: the app is inside one awaited call from the moment
    /// the browser opens, so "the browser came back" is modelled by letting that call
    /// return — which is what the service's gate is for.
    func returnFromBrowser() async {
        if let gate = authentication.completeGate {
            // Waited for rather than opened straight away: the sign-in runs in a task of
            // its own, so opening a gate nothing has reached yet would open it for nobody
            // and leave the call waiting for ever.
            await settle(until: { gate.arrivals >= 1 })
            gate.open()
        }
        await settle(until: { !self.isSigningIn })
    }

    /// Whether an attempt is still in flight.
    ///
    /// Both waiting states count. A sign-in that shows a code is as much in flight as one
    /// waiting on a redirect, and a helper that only knew about the second would return
    /// the moment a code appeared — before the attempt it was meant to wait for had begun.
    var isSigningIn: Bool {
        switch flow.state.detail {
        case .signIn(.signingIn), .signIn(.enterCode): true
        default: false
        }
    }
}

/// Lets the flow's own work run on until `condition` holds.
///
/// A download lives in a task of its own, so a test that wants to act halfway through
/// one has to let it get halfway first. Yielding rather than sleeping keeps that
/// deterministic: there is no wall clock anywhere in the flow to wait on.
@MainActor
func settle(until condition: @MainActor () -> Bool) async {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
}
