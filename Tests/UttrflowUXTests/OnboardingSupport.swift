// Test doubles and the harness that drive an OnboardingFlow without a screen.
import Foundation
import UttrflowTestSupport
import Synchronization

@testable import UttrflowAccount
@testable import UttrflowCore
@testable import UttrflowSettings
@testable import UttrflowUX

// MARK: - Holding a call open

/// One call held open until the test lets it through, so a test can act while a call is in flight.
final class Gate: Sendable {
    private let continuation = Mutex<AsyncStream<Void>.Continuation?>(nil)
    private let entered = Mutex(0)

    /// How many calls have reached the gate, so a test can wait for one to arrive.
    var arrivals: Int { entered.withLock { $0 } }

    /// Blocks until ``open()`` is called.
    func wait() async {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.continuation.withLock { $0 = continuation }
        entered.withLock { $0 += 1 }
        for await _ in stream { break }
    }

    /// Lets the waiting call through.
    func open() {
        continuation.withLock { $0 }?.finish()
    }
}

// MARK: - Doubles

/// A key-value store in memory, so no test writes to the user's real preferences.
final class InMemoryKeyValueStore: KeyValueStore {
    private let contents = Mutex<[String: Data]>([:])

    /// Every key written so far.
    var keys: Set<String> {
        contents.withLock { Set($0.keys) }
    }

    /// Reads a value.
    func data(forKey key: String) -> Data? {
        contents.withLock { $0[key] }
    }

    /// Writes a value, or removes it with `nil`.
    func set(_ data: Data?, forKey key: String) {
        contents.withLock { $0[key] = data }
    }
}

/// The onboarding record, with the launch it survived scripted rather than stored.
final class FakeRecordStore: OnboardingRecordStore {
    private let finished: Mutex<Bool>

    /// Starts finished or not.
    init(hasFinished: Bool = false) {
        finished = Mutex(hasFinished)
    }

    /// Whether onboarding has been completed.
    var hasFinished: Bool { finished.withLock { $0 } }

    /// Marks onboarding complete.
    func recordFinished() {
        finished.withLock { $0 = true }
    }
}

/// A download the test drives one instruction at a time, so mid-download states are reached on purpose.
final class GatedInstaller: OnboardingModelInstaller {
    /// What the download does next.
    enum Instruction: Sendable {
        case report(Double)
        case succeed
        case fail(SpeechEngineError)
    }

    /// The channel for the running download, made afresh each time since a stream has one consumer.
    private let gate = Mutex<AsyncStream<Instruction>.Continuation?>(nil)
    private let installed: Mutex<Bool>
    private let attempts = Mutex(0)

    /// Starts with the model present or not.
    init(isInstalled: Bool = false) {
        installed = Mutex(isInstalled)
    }

    /// Whether the model is on disk.
    var isInstalled: Bool { installed.withLock { $0 } }

    /// How many downloads have started, so a retry can be told from a page that merely redrew.
    var startedDownloads: Int { attempts.withLock { $0 } }

    /// Hands the running download its next instruction.
    func send(_ instruction: Instruction) {
        gate.withLock { $0 }?.yield(instruction)
    }

    /// Runs the download as instructed, reporting progress until told to succeed or fail.
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

/// A download that is over before it is asked about, for every test not about the download itself.
struct InstantInstaller: OnboardingModelInstaller {
    /// Whether the model is on disk.
    let isInstalled: Bool

    /// Reports completion at once.
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

/// The profile on this Mac, in memory, believing whatever it is handed; signatures are tested elsewhere.
final class InMemoryProfileCache: ProfileCache {
    private let held: Mutex<Profile?>
    private let refusesToSave: Bool

    /// Starts holding a profile, and optionally refusing every save.
    init(holding profile: Profile? = nil, refusesToSave: Bool = false) {
        held = Mutex(profile)
        self.refusesToSave = refusesToSave
    }

    /// The profile held.
    func load() -> Profile? { held.withLock { $0 } }

    /// Keeps the profile, or throws when told to refuse.
    func save(_ profile: Profile) throws(AccountError) {
        if refusesToSave { throw .sessionMalformed }
        held.withLock { $0 = profile }
    }

    /// Forgets the profile.
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

    /// Whether a cancelled task stops the exchange; false models a session minted before Cancel.
    private let respectsCancellation: Bool
    /// How this machine is going to finish signing in, which the machine decides.
    private let method: SignInMethod

    /// Scripts the failures, gates and method for one test.
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

    /// Records the provider and answers a challenge, or the scripted failure.
    func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        started.withLock { $0.append(provider) }
        await beginGate?.wait()
        if let beginFailure { throw beginFailure }
        return SignInChallenge(
            authorisationURL: safeSignInURL(provider), state: FakeAuthenticationService.state,
            method: method)
    }

    /// Waits on the gate, then answers a profile or the scripted failure.
    func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile {
        await completeGate?.wait()
        if respectsCancellation, Task.isCancelled {
            throw .providerRefused(description: "that sign-in was abandoned")
        }
        if let completeFailure { throw completeFailure }
        return aProfile()
    }

    /// Onboarding never re-reads the profile, so this answers only what keeps the type honest.
    func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        cached == nil ? .signedOut : .unchanged
    }

    /// Nothing in onboarding draws a picture, so nothing here fetches one.
    func avatar(at path: String) async -> Data? { nil }

    /// Nothing to forget.
    func signOut() async {}
}

/// A URL without a force unwrap, which this package forbids.
func safeSignInURL(_ provider: SignInProvider) -> URL {
    URL(string: "https://sign-in.invalid/\(provider.rawValue)") ?? URL(filePath: "/")
}

/// Where the browser was sent.
final class BrowserRecorder: Sendable {
    private let visited = Mutex<[URL]>([])

    /// Every URL opened so far.
    var urls: [URL] { visited.withLock { $0 } }

    /// The hook to hand the flow.
    var open: @Sendable (URL) -> Void {
        { url in self.visited.withLock { $0.append(url) } }
    }
}

/// The connection, as the test says it is.
final class FakeReachability: NetworkReachability {
    private let reachable: Mutex<Bool>

    /// Starts reachable or not.
    init(_ isReachable: Bool) {
        reachable = Mutex(isReachable)
    }

    /// Whether the network is up.
    var isReachable: Bool { reachable.withLock { $0 } }

    /// Changes the connection.
    func set(_ isReachable: Bool) {
        reachable.withLock { $0 = isReachable }
    }
}

/// Where the user was sent, in the order they were sent there.
final class PaneRecorder: Sendable {
    private let opened = Mutex<[SystemSettingsPane]>([])

    /// Every pane opened so far.
    var panes: [SystemSettingsPane] { opened.withLock { $0 } }

    /// The hook to hand the flow.
    var open: @Sendable (SystemSettingsPane) -> Void {
        { pane in self.opened.withLock { $0.append(pane) } }
    }
}

// MARK: - Harness

/// One flow with everything around it substituted, and the states it published.
@MainActor
final class Harness {
    /// The microphone gate.
    let microphone: FakePermissionGate
    /// The Accessibility gate.
    let accessibility: FakePermissionGate
    /// The model installer.
    let installer: any OnboardingModelInstaller
    /// Whether onboarding has finished before.
    let record: FakeRecordStore
    /// The settings, in memory.
    let settingsStore: UserDefaultsSettingsStore
    /// The scripted backend.
    let authentication: FakeAuthenticationService
    /// The profile cache.
    let profiles: InMemoryProfileCache
    /// Where "continue on this Mac" writes, so a test can assert on what the button recorded.
    let local = InMemoryLocalAccountStore()
    /// The connection.
    let network: FakeReachability
    /// Where the browser was sent.
    let browser = BrowserRecorder()
    /// Where System Settings was opened.
    let panes = PaneRecorder()
    /// The flow under test.
    let flow: OnboardingFlow

    /// Every state the flow published, so a test can assert on what the user saw on the way.
    private(set) var published: [OnboardingState] = []
    /// What the flow finished with, once it has.
    private(set) var finishedWith: OnboardingReadiness?

    /// Signed in and installed by default, so a test about a permission is not also about sign-in.
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
        // Gated by default, so `choose` leaves the flow waiting on a browser until `returnFromBrowser`.
        authentication: FakeAuthenticationService = FakeAuthenticationService(completeGate: Gate()),
        reachable: Bool = true,
        /// What macOS would call the person at this Mac, fixed so no test depends on who runs it.
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

    /// Starts and reads past the welcome page, so moving the pitch again is one edit.
    func startPastWelcome() async {
        await flow.start()
        if flow.state.step == .welcome { await flow.perform(.advance) }
    }

    /// Where the flow is.
    var step: OnboardingStep { flow.state.step }
    /// What the page is saying.
    var detail: OnboardingDetail { flow.state.detail }
    /// What the window would draw.
    var page: OnboardingPage { flow.page }
    /// The buttons on the page, by title.
    var buttonTitles: [String] { page.buttons.map(\.title) }

    /// The providers the page will let somebody press, which offline is none of the three.
    var liveProviders: [SignInProvider] { page.providers.filter(\.isEnabled).map(\.provider) }

    /// Presses the button with this title; false when the page is not offering it.
    func press(_ title: String) async -> Bool {
        guard let button = page.buttons.first(where: { $0.title == title && $0.isEnabled })
        else { return false }
        await flow.perform(button.intent)
        return true
    }

    /// Presses a provider's button and waits until the browser is open or the attempt has failed.
    func choose(_ provider: SignInProvider) async -> Bool {
        guard page.providers.contains(where: { $0.provider == provider && $0.isEnabled })
        else { return false }
        await flow.perform(.signIn(provider))
        await settle(until: { !self.authentication.startedProviders.isEmpty })
        // Either the browser is open, or the attempt failed before it got that far.
        await settle(until: { !self.browser.urls.isEmpty || !self.isSigningIn })
        return true
    }

    /// The backend answering the sign-in the app is waiting on, by letting the awaited call return.
    func returnFromBrowser() async {
        if let gate = authentication.completeGate {
            // Waited for, since a gate nothing has reached yet would open for nobody.
            await settle(until: { gate.arrivals >= 1 })
            gate.open()
        }
        await settle(until: { !self.isSigningIn })
    }

    /// Whether an attempt is still in flight; a sign-in showing a code counts as much as one on a redirect.
    var isSigningIn: Bool {
        switch flow.state.detail {
        case .signIn(.signingIn), .signIn(.enterCode): true
        default: false
        }
    }
}

/// Lets the flow's own work run on until `condition` holds, by yielding rather than sleeping.
@MainActor
func settle(until condition: @MainActor () -> Bool) async {
    for _ in 0..<10_000 {
        if condition() { return }
        await Task.yield()
    }
}
