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

    /// Called after onboarding changes a saved setting, so the running app applies it immediately.
    public var onSettingsChange: ((Settings) -> Void)?

    /// Called as soon as a sign-in's profile is kept, so the app opens before the rest of setup.
    public var onSignIn: (() -> Void)?

    private let microphone: any PermissionGate
    private let accessibility: any PermissionGate
    private let installer: any OnboardingModelInstaller
    private let settingsStore: any SettingsStore
    private let record: any OnboardingRecordStore

    // MARK: The account

    private let authentication: any AuthenticationService
    private let profiles: any ProfileCache
    private let entitlements: EntitlementGate
    private let network: any NetworkReachability

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

    /// The provider's page the browser was sent to, so Reopen can send it there again.
    private var authorisationURL: URL?

    /// How far the download in flight has come, so a stopped one is drawn where it stopped.
    private var downloaded = 0.0

    /// Waits before closing on a first try that worked; injected so a test need not wait.
    private let pause: @Sendable (Duration) async -> Void

    /// Wires every gate, store and system hook in; the flow starts on the sign-in page.
    public init(
        microphone: any PermissionGate,
        accessibility: any PermissionGate,
        installer: any OnboardingModelInstaller,
        settingsStore: any SettingsStore,
        record: any OnboardingRecordStore,
        authentication: any AuthenticationService,
        profiles: any ProfileCache,
        network: any NetworkReachability,
        openBrowser: @escaping @Sendable (URL) -> Void,
        openSystemSettings: @escaping @Sendable (SystemSettingsPane) -> Void,
        now: @escaping @Sendable () -> Date,
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.installer = installer
        self.settingsStore = settingsStore
        self.record = record
        self.authentication = authentication
        self.profiles = profiles
        self.entitlements = EntitlementGate(profiles: profiles)
        self.network = network
        self.openBrowser = openBrowser
        self.openSystemSettings = openSystemSettings
        self.now = now
        self.pause = pause
        self.state = OnboardingState(step: .signIn, detail: .signIn(.offering))
    }

    /// Whether the user has never been all the way through this; asked before the window is built.
    public var isRequired: Bool { !record.hasFinished }

    /// What the window draws right now; settings are read at draw time so a changed shortcut shows.
    public var page: OnboardingPage {
        let settings = settingsStore.load()
        return OnboardingPresenter.page(
            for: state, hotkey: settings.hotkey, activation: settings.hotkeyActivation,
            shortcuts: settings.shortcuts,
            signsInAsStandIn: authentication.signsInAsStandIn,
            sharesUsageStatistics: settings.sharesUsageStatistics)
    }

    // MARK: Driving

    /// Opens on the first page that still has something to ask.
    public func start() async {
        if let signInTask {
            await signInTask.value
            return
        }
        await moveOn(past: 0)
    }

    /// Carries out one thing the user did on the page.
    public func perform(_ intent: OnboardingIntent) async {
        switch intent {
        case .advance:
            // Every page but the last is answered before it is left; a stray advance is ignored.
            guard await isAnswered else { return }
            await moveOn(after: state.step)
        case .requestPermission(let kind):
            await ask(kind)
        case .recover(let action):
            await recover(action)
        case .cancelInstall:
            guard state.step == .setup else { return }
            abandonInstall()
            set(detail: .installFailed("You stopped it before it finished.", reached: downloaded))
        case .signIn(let provider):
            beginSignIn(with: provider)
        case .reopenBrowser:
            guard state.step == .signIn, let authorisationURL else { return }
            openBrowser(authorisationURL)
        // Both are guarded on the page offering them: a stale instruction must not drag the user back.
        case .cancelSignIn:
            guard state.step == .signIn else { return }
            abandonSignIn()
            await enter(.signIn)
        case .setUsageStatistics(let enabled):
            guard state.step == .signIn, case .signIn(.offering) = state.detail else { return }
            var settings = settingsStore.load()
            settings.sharesUsageStatistics = enabled
            settingsStore.save(settings)
            onSettingsChange?(settings)
            set(detail: state.detail)
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
        case .ready: set(detail: .finishing(await readiness(), trial: state.detail.trial))
        // The connection can come back while the page shows; a sign-in under way is left alone.
        case .signIn:
            guard state.detail == .signIn(.unreachable) || state.detail == .signIn(.offering)
            else { return }
            await enter(.signIn)
        // The download page is waiting on nothing the user could have changed elsewhere.
        case .setup: break
        }
    }

    /// Goes back to the sign-in page after a sign-out; a download in flight keeps going but stops drawing here.
    public func signedOut() async {
        guard !isFinished else { return }
        abandonSignIn()
        installGeneration += 1
        await enter(.signIn)
    }

    /// Shows how the first try on the last page is going; words that arrive close onboarding after a moment.
    public func tried(_ trial: OnboardingTrial) async {
        guard case .finishing(let readiness, let current) = state.detail,
            readiness == .ready || readiness == .pastesManually
        else { return }
        // Once words have arrived the page is closing, so a later dictation does not redraw it.
        if case .heard = current { return }
        if case .heard(let words) = trial, words.allSatisfy(\.isWhitespace) {
            set(detail: .finishing(readiness, trial: .waiting))
            return
        }
        set(detail: .finishing(readiness, trial: trial))
        guard case .heard = trial else { return }
        await pause(OnboardingPresenter.heardLinger)
        guard !isFinished, state.detail == .finishing(readiness, trial: trial) else { return }
        finish(with: readiness)
    }

    /// Whether the page showing has had its question answered, which is what lets the user leave it.
    private var isAnswered: Bool {
        get async {
            switch (state.step, state.detail) {
            case (.signIn, _):
                return !(await isOutstanding(.signIn))
            case (.microphone, .permission(let status)), (.accessibility, .permission(let status)):
                return status == .granted || status == .restricted
            case (.microphone, _), (.accessibility, _):
                return false
            case (.setup, _):
                return installer.isInstalled
            case (.ready, _):
                return true
            }
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
        case .signIn: !isSignedIn
        case .microphone: await microphone.status() != .granted
        case .accessibility: await accessibility.status() != .granted
        case .setup: !installer.isInstalled
        // Nothing the system does can finish the last page, so it is never passed over.
        case .ready: true
        }
    }

    /// Shows a page in the state the system currently puts it in.
    private func enter(_ step: OnboardingStep) async {
        switch step {
        case .signIn:
            set(step: .signIn, detail: .signIn(network.isReachable ? .offering : .unreachable))
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

    /// Asks macOS for a permission; a yes stays on the page to say so, and Continue moves on.
    private func ask(_ kind: PermissionKind) async {
        let status = await gate(for: kind).request()
        if status.isGranted {
            set(detail: .permission(.granted))
        } else if status == .denied, !kind.reportsNotDetermined {
            // macOS's own Accessibility prompt is the one that opens Settings, so the user is already on the way.
            set(detail: .awaitingSystemSettings)
        } else {
            set(detail: .permission(status))
        }
    }

    /// Re-reads a permission after the user has been elsewhere.
    private func recheck(_ kind: PermissionKind) async {
        switch (await gate(for: kind).status(), state.detail) {
        case (.granted, _):
            set(detail: .permission(.granted))
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
        case .pasteManually, .showHistory, .retryFromRecording, .restoreRecording, .copyTranscript:
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
        downloaded = 0
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
            downloaded = fraction
            set(step: .setup, detail: .installing(fraction))
        }

        let failure = await work.value
        guard generation == installGeneration else { return }
        if let failure {
            set(step: .setup, detail: .installFailed(failure.userMessage, reached: downloaded))
        } else {
            set(step: .setup, detail: .installed)
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
    private func beginSignIn(with provider: SignInProvider) {
        guard case .signIn(let signIn) = state.detail else { return }
        let canStartStandIn: Bool
        switch signIn {
        case .offering, .unreachable:
            canStartStandIn = authentication.signsInAsStandIn && provider == .google
        case .signingIn, .enterCode, .welcomed, .refused:
            canStartStandIn = false
        }
        guard signIn.acceptsAProvider || canStartStandIn else { return }
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
                // A stand-in has no provider page, so nothing opens and Reopen has nowhere to go.
                if challenge.method != .standIn {
                    authorisationURL = challenge.authorisationURL
                    openBrowser(challenge.authorisationURL)
                }

                let profile = try await authentication.completeSignIn(challenge)
                try profiles.save(profile)
                onSignIn?()
                // Not guarded on the generation: a cancelled exchange that finished is still a sign-in.
                await welcome(profile.account)
            } catch {
                // A failure is guarded so it cannot redraw a page the user has walked away from.
                guard generation == signInGeneration else { return }
                report(error)
            }
        }
    }

    /// Greets whoever signed in, then moves on by itself unless Continue already did.
    private func welcome(_ account: Account) async {
        let next = await nextOutstanding(after: .signIn)
        let welcome = OnboardingWelcome(account: account, next: next)
        set(step: .signIn, detail: .signIn(.welcomed(welcome)))
        await pause(OnboardingPresenter.welcomeLinger)
        guard !isFinished, state.detail == .signIn(.welcomed(welcome)) else { return }
        await moveOn(after: .signIn)
    }

    /// The first page after `step` that still has something to ask; the last page always does.
    private func nextOutstanding(after step: OnboardingStep) async -> OnboardingStep {
        for next in OnboardingStep.inOrder where next.position > step.position {
            if await isOutstanding(next) { return next }
        }
        return .ready
    }

    /// Stops waiting for a sign-in in a browser tab; the backend forgets the attempt within ten minutes.
    private func abandonSignIn() {
        signInGeneration += 1
        signInTask?.cancel()
        signInTask = nil
        authorisationURL = nil
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
