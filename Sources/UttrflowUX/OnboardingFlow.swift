// First-run onboarding: the model-installer contract and the flow that drives every page.
public import UttrflowAccount
public import UttrflowCore
public import UttrflowSettings

public import struct Foundation.Date
public import struct Foundation.URL

/// Puts the speech model on disk; onboarding installs one model once and never deletes one.
public protocol OnboardingModelInstaller: Sendable {
    /// Whether the model onboarding would fetch is already there.
    var isInstalled: Bool { get }

    /// Fetches it, reporting progress from `0` to `1`.
    func install(onProgress: @escaping @Sendable (Double) -> Void) async throws(SpeechEngineError)
}

/// First-run onboarding as a state machine the window only draws. See Docs/ux-onboarding.md.
@MainActor
public final class OnboardingFlow {
    /// Which page is showing and what it is saying.
    public private(set) var state: OnboardingState
    /// Whether the user has closed onboarding.
    public private(set) var isFinished = false

    /// Called after every change, so the window can redraw without polling.
    public var onChange: ((OnboardingState) -> Void)?

    /// Called once, when the user closes onboarding, with what they ended up able to do.
    public var onFinish: ((OnboardingReadiness) -> Void)?

    private let microphone: any PermissionGate
    private let accessibility: any PermissionGate
    private let installer: any OnboardingModelInstaller
    private let settingsStore: any SettingsStore
    private let record: any OnboardingRecordStore

    // MARK: The account

    private let authentication: any AuthenticationService
    private let profiles: any ProfileCache
    /// Where the choice to work without an account is kept; cleared the moment a real sign-in succeeds.
    private let local: any LocalAccountStore
    private let entitlements: EntitlementGate
    private let network: any NetworkReachability

    /// What macOS calls the person at this Mac; injected so a test controls the value.
    private let systemName: @Sendable () -> String?

    /// Opens the provider's page in the user's browser, never a web view, since a password is typed there.
    private let openBrowser: @Sendable (URL) -> Void

    /// Now, injected so a test can expire an entitlement without waiting.
    private let now: @Sendable () -> Date

    /// Sends the user to a pane of System Settings; injected because the pane is a symbol, not a URL.
    private let openSystemSettings: @Sendable (SystemSettingsPane) -> Void

    /// Bumped whenever a download stops mattering, so a cancelled one cannot redraw a page left behind.
    private var installGeneration = 0
    private var installTask: Task<SpeechEngineError?, Never>?

    /// The same guard for a sign-in living in a browser tab.
    private var signInGeneration = 0

    /// The sign-in waiting on a browser; cancelling it is what makes the Cancel button real.
    private var signInTask: Task<Void, Never>?

    /// Set by ``resume(askingToSignIn:)`` and lives as long as this flow.
    private var wasAskedToSignIn = false

    /// Wires every gate, store and system hook in; the flow starts on the sign-in page.
    public init(
        microphone: any PermissionGate,
        accessibility: any PermissionGate,
        installer: any OnboardingModelInstaller,
        settingsStore: any SettingsStore,
        record: any OnboardingRecordStore,
        authentication: any AuthenticationService,
        profiles: any ProfileCache,
        local: any LocalAccountStore,
        network: any NetworkReachability,
        systemName: @escaping @Sendable () -> String?,
        openBrowser: @escaping @Sendable (URL) -> Void,
        openSystemSettings: @escaping @Sendable (SystemSettingsPane) -> Void,
        now: @escaping @Sendable () -> Date
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.installer = installer
        self.settingsStore = settingsStore
        self.record = record
        self.authentication = authentication
        self.profiles = profiles
        self.local = local
        self.entitlements = EntitlementGate(profiles: profiles, local: local)
        self.network = network
        self.systemName = systemName
        self.openBrowser = openBrowser
        self.openSystemSettings = openSystemSettings
        self.now = now
        self.state = OnboardingState(step: .signIn, detail: .signIn(.offering))
    }

    /// Whether the user has never been all the way through this; asked before the window is built.
    public var isRequired: Bool { !record.hasFinished }

    /// What the window draws right now; settings are read at draw time so a changed shortcut shows.
    public var page: OnboardingPage {
        OnboardingPresenter.page(for: state, hotkey: settingsStore.load().hotkey)
    }

    // MARK: Driving

    /// Opens on the first page that still has something to ask.
    public func start() async {
        await moveOn(past: 0)
    }

    /// Opens after the pitch; with `askingToSignIn` a local account does not count as signed in.
    public func resume(askingToSignIn: Bool = false) async {
        wasAskedToSignIn = askingToSignIn
        await moveOn(past: OnboardingStep.welcome.position)
    }

    /// Carries out one thing the user did on the page.
    public func perform(_ intent: OnboardingIntent) async {
        switch intent {
        case .advance:
            await moveOn(after: state.step)
        case .requestPermission(let kind):
            await ask(kind)
        case .recover(let action):
            await recover(action)
        case .cancelInstall:
            abandonInstall()
            await moveOn(after: .setup)
        case .signIn(let provider):
            await beginSignIn(with: provider)
        // Both are guarded on the page offering them: a stale instruction must not drag the user back.
        case .cancelSignIn:
            guard state.step == .signIn else { return }
            abandonSignIn()
            await enter(.signIn)
        case .continueOnThisMac:
            guard state.step == .signIn else { return }
            await continueOnThisMac()
        case .finish:
            // Only the last page offers this, so an instruction to close from anywhere else is ignored.
            guard let readiness = state.detail.readiness else { return }
            finish(with: readiness)
        }
    }

    /// Re-reads everything macOS owns; called when the window comes to the front and by Check Again.
    public func refresh() async {
        switch state.step {
        case .microphone: await recheck(.microphone)
        case .accessibility: await recheck(.accessibility)
        case .ready: set(detail: .finishing(await readiness()))
        // The connection can come back while the page shows; a sign-in under way is left alone.
        case .signIn:
            guard state.detail == .signIn(.unreachable) || state.detail == .signIn(.offering)
            else { return }
            await enter(.signIn)
        // Neither page is waiting on anything the user could have changed elsewhere.
        case .welcome, .setup: break
        }
    }

    // MARK: Steps

    /// Goes to the next page that still has something to ask, passing over any whose work is done.
    private func moveOn(after step: OnboardingStep) async {
        await moveOn(past: step.position)
    }

    /// The same walk from before the first page, so opening and moving on agree about which pages show.
    private func moveOn(past position: Int) async {
        for next in OnboardingStep.allCases where next.position > position {
            guard await isOutstanding(next) else { continue }
            await enter(next)
            return
        }
    }

    /// Whether a page still has a question the system has not already answered.
    private func isOutstanding(_ step: OnboardingStep) async -> Bool {
        switch step {
        // Somebody who pressed Sign In wants an Uttrflow account; a local one satisfies every other way in.
        case .signIn: wasAskedToSignIn ? profiles.load() == nil : !isSignedIn
        case .microphone: await microphone.status() != .granted
        case .accessibility: await accessibility.status() != .granted
        case .setup: !installer.isInstalled
        // Neither can already be done by the system, so neither is ever passed over.
        case .welcome, .ready: true
        }
    }

    /// Shows a page in the state the system currently puts it in.
    private func enter(_ step: OnboardingStep) async {
        switch step {
        case .signIn:
            set(step: .signIn, detail: .signIn(network.isReachable ? .offering : .unreachable))
        case .welcome:
            set(step: .welcome, detail: .reading)
        case .microphone:
            set(step: step, detail: .permission(await microphone.status()))
        case .accessibility:
            set(step: step, detail: .permission(await accessibility.status()))
        case .setup:
            await beginInstall()
        case .ready:
            set(step: .ready, detail: .finishing(await readiness()))
        }
    }

    // MARK: Permissions

    /// Asks macOS for a permission and moves on if it is granted.
    private func ask(_ kind: PermissionKind) async {
        let status = await gate(for: kind).request()
        if status.isGranted {
            await moveOn(after: state.step)
        } else {
            set(detail: .permission(status))
        }
    }

    /// Re-reads a permission after the user has been elsewhere.
    private func recheck(_ kind: PermissionKind) async {
        switch (await gate(for: kind).status(), state.detail) {
        case (.granted, _):
            await moveOn(after: state.step)
        case (.denied, .awaitingSystemSettings):
            // Still refused after the settings pane: the page keeps offering look again or go on without it.
            break
        case (let status, _):
            set(detail: .permission(status))
        }
    }

    /// Carries out a recovery the page offered.
    private func recover(_ action: RecoveryAction) async {
        switch action {
        case .openSystemSettings(let pane):
            openSystemSettings(pane)
            // Only a page that was asking has anything to wait for; the last page stays on what it says.
            guard case .permission = state.detail else { return }
            set(detail: .awaitingSystemSettings)
        case .retry:
            await refresh()
        case .downloadSpeechModel:
            await enter(.setup)
        case .pasteManually, .showRecentDictations, .retryFromRecording:
            // Offered by failures elsewhere in the app, never by a page here; ignored.
            break
        }
    }

    /// The gate that answers for a permission.
    private func gate(for kind: PermissionKind) -> any PermissionGate {
        switch kind {
        case .microphone: microphone
        case .accessibility: accessibility
        }
    }

    // MARK: The download

    /// Downloads the model, drawing progress until it finishes or fails.
    private func beginInstall() async {
        installGeneration += 1
        let generation = installGeneration
        set(step: .setup, detail: .installing(0))

        let progress = AsyncStream<Double>.makeStream()
        let work = Task { [installer] () -> SpeechEngineError? in
            defer { progress.continuation.finish() }
            do throws(SpeechEngineError) {
                try await installer.install { progress.continuation.yield($0) }
                return nil
            } catch {
                return error
            }
        }
        installTask = work

        // Progress from a run the user has walked away from is dropped, since its page is off screen.
        for await fraction in progress.stream where generation == installGeneration {
            set(step: .setup, detail: .installing(fraction))
        }

        let failure = await work.value
        guard generation == installGeneration else { return }
        if let failure {
            set(step: .setup, detail: .installFailed(failure.userMessage))
        } else {
            await moveOn(after: .setup)
        }
    }

    /// Stops caring about the download in flight and asks it to stop; nothing it says later is drawn.
    private func abandonInstall() {
        installGeneration += 1
        installTask?.cancel()
    }

    // MARK: The account

    /// Whether somebody is signed in, per ``EntitlementGate``: an aged-out entitlement still counts.
    private var isSignedIn: Bool {
        entitlements.access(at: now(), networkIsReachable: network.isReachable).permitsDictation
    }

    /// Signs somebody in as one awaited call; no token crosses the browser. See Docs/ux-onboarding.md.
    private func beginSignIn(with provider: SignInProvider) async {
        guard case .signIn(let signIn) = state.detail, signIn.acceptsAProvider else { return }
        signInGeneration += 1
        let generation = signInGeneration
        set(detail: .signIn(.signingIn(provider)))

        signInTask?.cancel()
        signInTask = Task { [weak self] in
            guard let self else { return }
            do throws(AccountError) {
                let challenge = try await authentication.beginSignIn(with: provider)
                guard generation == signInGeneration else { return }

                // A Mac that cannot bind a loopback port gets a code to type, and the page says so.
                if case .code(let userCode, _) = challenge.method {
                    set(detail: .signIn(.enterCode(provider, code: userCode)))
                }
                openBrowser(challenge.authorisationURL)

                let profile = try await authentication.completeSignIn(challenge)
                try profiles.save(profile)
                // A real account supersedes the Mac one, and only after the profile is safely kept.
                local.clear()
                // Not guarded on the generation: a cancelled exchange that finished is still a sign-in.
                await moveOn(after: .signIn)
            } catch {
                // A failure is guarded so it cannot redraw a page the user has walked away from.
                guard generation == signInGeneration else { return }
                report(error)
            }
        }
    }

    /// Carries on without an account as the person at this Mac, abandoning any sign-in still in a browser.
    private func continueOnThisMac() async {
        abandonSignIn()
        local.save(LocalAccount(name: systemName(), since: now()))
        await moveOn(after: .signIn)
    }

    /// Stops waiting for a sign-in in a browser tab; the backend forgets the attempt within ten minutes.
    private func abandonSignIn() {
        signInGeneration += 1
        signInTask?.cancel()
        signInTask = nil
    }

    /// Puts a sign-in failure on the page; a missing connection becomes the offline page, not an error.
    private func report(_ failure: AccountError) {
        switch failure {
        case .serverUnreachable:
            set(detail: .signIn(.unreachable))
        case .providerRefused, .sessionMalformed, .sessionCouldNotBeKept:
            set(detail: .signIn(.refused(failure.userMessage)))
        }
    }

    // MARK: Finishing

    /// What the user can do, read from the system and ordered by what stops them first.
    private func readiness() async -> OnboardingReadiness {
        if await microphone.status() != .granted { return .needsMicrophone }
        if !installer.isInstalled { return .needsSpeechModel }
        if await accessibility.status() != .granted { return .pastesManually }
        return .ready
    }

    /// Closes onboarding without writing a preference; `opensAtLogin` false on disk is the user's choice.
    private func finish(with readiness: OnboardingReadiness) {
        record.recordFinished()
        isFinished = true
        onFinish?(readiness)
    }

    // MARK: Publishing

    /// Publishes a new page and detail to the window.
    private func set(step: OnboardingStep, detail: OnboardingDetail) {
        state = OnboardingState(step: step, detail: detail)
        onChange?(state)
    }

    /// Publishes a new detail on the current page.
    private func set(detail: OnboardingDetail) {
        set(step: state.step, detail: detail)
    }
}
