public import UttrflowAccount
public import UttrflowCore
public import UttrflowSettings

public import struct Foundation.Date
public import struct Foundation.URL

/// Puts the speech model on disk.
///
/// Narrower than the store the app really uses: onboarding installs one model, once,
/// and nothing on a first run has any business deleting one. Stated here rather than
/// taken from the speech module so that this module stays free of everything but the
/// domain and the user's settings, and so a test can fail a download on demand.
public protocol OnboardingModelInstaller: Sendable {
    /// Whether the model onboarding would fetch is already there.
    var isInstalled: Bool { get }

    /// Fetches it, reporting progress from `0` to `1`.
    func install(onProgress: @escaping @Sendable (Double) -> Void) async throws(SpeechEngineError)
}

/// First-run onboarding, as a machine that can be driven without a screen.
///
/// Holds every decision the pages make, so the window above it only draws. Two rules
/// shape the whole of it. Nothing is ever remembered about the system — a permission is
/// read from its gate at the moment it matters, never carried forward from the click
/// that asked for it — and no page is ever a dead end: whatever the user has refused,
/// there is always a control that moves them on, and what refusing cost them is said
/// plainly on the last page instead of leaving them somewhere broken and quiet.
///
/// One page breaks the offline promise and only one: signing in needs a server, which
/// is why ``NetworkReachability`` is asked before those buttons are drawn live. Whether
/// somebody is *already* signed in is never asked of a server — ``EntitlementGate``
/// answers it from a cached, signed entitlement, so every launch after the first works
/// with the Wi-Fi off. This type holds no second opinion about that rule.
@MainActor
public final class OnboardingFlow {
    public private(set) var state: OnboardingState
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
    /// Where the choice to work without an account is kept. Written by exactly one
    /// intent, and cleared the moment a real sign-in succeeds.
    private let local: any LocalAccountStore
    private let entitlements: EntitlementGate
    private let network: any NetworkReachability

    /// What macOS calls the person at this Mac, for the account they get when they
    /// decline to sign in. A closure rather than `NSFullUserName()` for the reason every
    /// other system reading here is one: a flow that read it directly would behave
    /// differently in a test than in the product, and this is the value under test.
    private let systemName: @Sendable () -> String?

    /// Opens the provider's page in the user's own browser.
    ///
    /// A browser rather than a web view, deliberately: people are asked for a password
    /// here, and the only window in which that is safe to type is one whose address bar
    /// they can see and whose password manager they already trust.
    private let openBrowser: @Sendable (URL) -> Void

    /// Now. Taken as an argument with no default, so that an entitlement expiring is a
    /// line in a test rather than a wait, and so that this module never reads a clock
    /// it did not agree to read.
    private let now: @Sendable () -> Date

    /// Sends the user to a pane of System Settings.
    ///
    /// Injected because ``SystemSettingsPane`` is a symbol rather than a URL: turning
    /// one into somewhere the user can be sent belongs to whatever is drawing, which is
    /// the same reason the rest of the app's recoveries are handled that way.
    private let openSystemSettings: @Sendable (SystemSettingsPane) -> Void

    /// Bumped whenever a download stops mattering, so a cancelled one cannot report
    /// back over the page the user has already moved on to.
    private var installGeneration = 0
    private var installTask: Task<SpeechEngineError?, Never>?

    /// The same guard, for the one other thing that finishes somewhere else: a sign-in
    /// living in a browser tab.
    private var signInGeneration = 0

    /// The sign-in waiting for a browser, so that walking away from it can stop it.
    ///
    /// Sign-in is one awaited call that outlives the click which started it: the app opens
    /// a page, then waits — possibly minutes, while somebody finds a password manager —
    /// for the backend to say the browser half is done. Cancelling this task is what makes
    /// the Cancel button真 rather than cosmetic.
    private var signInTask: Task<Void, Never>?

    /// Set by ``resume(askingToSignIn:)``. Lives as long as this flow, which is as long
    /// as the window: a fresh one is built every time onboarding is opened, so the answer
    /// cannot outlast the request that produced it.
    private var wasAskedToSignIn = false

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

    /// Whether the user has never been all the way through this.
    ///
    /// Asked before the window is ever built, so a returning user pays nothing for a
    /// first run they already had.
    public var isRequired: Bool { !record.hasFinished }

    /// What the window should draw right now.
    ///
    /// The settings are read here, at the moment of drawing, rather than kept from when
    /// the flow was built. This window no longer belongs only to a first run — the
    /// Account page's Sign In opens it over a working app — so the Settings window can
    /// be opened on top of it and the shortcut changed while it stands there. A page
    /// drawn from a copy taken minutes ago would tell the user to press a key that no
    /// longer starts anything.
    public var page: OnboardingPage {
        OnboardingPresenter.page(for: state, hotkey: settingsStore.load().hotkey)
    }

    // MARK: Driving

    /// Opens on the first page that still has something to ask.
    ///
    /// Not necessarily sign-in: somebody who signed in and then quit before finishing
    /// is not asked to sign in twice, for the same reason a granted permission is not
    /// asked for twice.
    public func start() async {
        await moveOn(past: 0)
    }

    /// Opens on the first page after the pitch that still has something to ask.
    ///
    /// What the Account page's Sign In button reaches. Somebody who has used Uttrflow for
    /// a month and signed out does not need telling what it is, and showing them the
    /// welcome page again would make signing back in feel like starting over. Everything
    /// after welcome is still walked in order, so a person who also revoked a permission
    /// meets that too rather than signing in and finding the app still mute.
    /// - Parameter askingToSignIn: Whether the person pressed Sign In to get here, as
    ///   opposed to a button about a permission. It matters because a ``LocalAccount``
    ///   settles the question "does this run still need somebody to sign in" — which is
    ///   the right answer on a first run and the wrong one for somebody who has just
    ///   asked to. Without it, the Account page's Sign In button would open onboarding
    ///   and walk straight past the sign-in page.
    public func resume(askingToSignIn: Bool = false) async {
        wasAskedToSignIn = askingToSignIn
        await moveOn(past: OnboardingStep.welcome.position)
    }

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
        // The two below are guarded on the page offering them, for the reason
        // ``finish`` is: an instruction that could only have come from a page the user
        // is not looking at must not drag them back to that page.
        case .cancelSignIn:
            guard state.step == .signIn else { return }
            abandonSignIn()
            await enter(.signIn)
        case .continueOnThisMac:
            guard state.step == .signIn else { return }
            await continueOnThisMac()
        case .finish:
            // Only the last page knows what it is promising, and only it offers this.
            // An instruction to close arriving from anywhere else is ignored for the
            // same reason a recovery this flow does not offer is.
            guard let readiness = state.detail.readiness else { return }
            finish(with: readiness)
        }
    }

    /// Re-reads everything macOS owns.
    ///
    /// The window calls this whenever it comes back to the front, because both
    /// permissions are granted in another application entirely and nothing tells us
    /// when that happens. It is also what the "Check Again" button does, so a user
    /// whose Mac did not notice them switching windows still has a way to be heard.
    public func refresh() async {
        switch state.step {
        case .microphone: await recheck(.microphone)
        case .accessibility: await recheck(.accessibility)
        case .ready: set(detail: .finishing(await readiness()))
        // The connection is the one thing here that can come back while the user is
        // looking at the page, and coming back to the window is as good a moment to
        // notice as any. A sign-in already under way is left alone: it is waiting on a
        // browser, not on the network, and redrawing it would lose the attempt.
        case .signIn:
            guard state.detail == .signIn(.unreachable) || state.detail == .signIn(.offering)
            else { return }
            await enter(.signIn)
        // Neither page is waiting on anything the user could have changed elsewhere.
        case .welcome, .setup: break
        }
    }

    // MARK: Steps

    /// Goes to the next page that still has something to ask.
    ///
    /// Any page whose work is already done is passed over rather than shown as a success
    /// the user has to click through, which is also what makes quitting halfway and
    /// coming back cheap: onboarding starts again from the beginning, but every question
    /// already answered stays answered.
    private func moveOn(after step: OnboardingStep) async {
        await moveOn(past: step.position)
    }

    /// The same walk, from before the first page, so that opening onboarding and moving
    /// on within it cannot disagree about which pages are worth showing.
    private func moveOn(past position: Int) async {
        for next in OnboardingStep.allCases where next.position > position {
            guard await isOutstanding(next) else { continue }
            await enter(next)
            return
        }
    }

    private func isOutstanding(_ step: OnboardingStep) async -> Bool {
        switch step {
        // Somebody who pressed Sign In is asking for an Uttrflow account, and a local one
        // is not that. Every other way in is satisfied by either.
        case .signIn: wasAskedToSignIn ? profiles.load() == nil : !isSignedIn
        case .microphone: await microphone.status() != .granted
        case .accessibility: await accessibility.status() != .granted
        case .setup: !installer.isInstalled
        // Neither of these is about something the system can already have done, so
        // there is never a reason to pass over them.
        case .welcome, .ready: true
        }
    }

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

    private func ask(_ kind: PermissionKind) async {
        let status = await gate(for: kind).request()
        if status.isGranted {
            await moveOn(after: state.step)
        } else {
            set(detail: .permission(status))
        }
    }

    private func recheck(_ kind: PermissionKind) async {
        switch (await gate(for: kind).status(), state.detail) {
        case (.granted, _):
            await moveOn(after: state.step)
        case (.denied, .awaitingSystemSettings):
            // Still refused, with the user just back from the settings pane. The page
            // keeps the two answers it already offers rather than inventing a third:
            // look again, or go on without it.
            break
        case (let status, _):
            set(detail: .permission(status))
        }
    }

    private func recover(_ action: RecoveryAction) async {
        switch action {
        case .openSystemSettings(let pane):
            openSystemSettings(pane)
            // Only a page that was asking has anything to wait for. The last page also
            // offers this, and it stays on what it was saying until the user comes
            // back and the readiness is read again.
            guard case .permission = state.detail else { return }
            set(detail: .awaitingSystemSettings)
        case .retry:
            await refresh()
        case .downloadSpeechModel:
            await enter(.setup)
        case .pasteManually, .showRecentDictations, .retryFromRecording:
            // Offered by failures elsewhere in the app, never by a page here. Ignored
            // rather than made impossible, so that onboarding can go on speaking the
            // same vocabulary of recoveries as everything else.
            break
        }
    }

    private func gate(for kind: PermissionKind) -> any PermissionGate {
        switch kind {
        case .microphone: microphone
        case .accessibility: accessibility
        }
    }

    // MARK: The download

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

        // Progress from a run the user has already walked away from is dropped rather
        // than drawn, because the page it belonged to is no longer on screen.
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

    /// Stops caring about the download in flight, and asks it to stop too.
    ///
    /// The ask is best-effort: an installer that ignores cancellation still finishes
    /// its download, but the generation it was started under has moved on, so nothing
    /// it has to say can reach the screen.
    private func abandonInstall() {
        installGeneration += 1
        installTask?.cancel()
    }

    // MARK: The account

    /// Whether this Mac already has somebody signed in.
    ///
    /// Asked of ``EntitlementGate`` rather than of the session store, so that onboarding
    /// holds no second opinion about the product's rules. In particular an entitlement
    /// that has aged out still counts as signed in: it degrades, it does not lock, and a
    /// first-run screen that asked somebody to sign in again because they had been on a
    /// train would be the lock-out that gate exists to prevent.
    private var isSignedIn: Bool {
        entitlements.access(at: now(), networkIsReachable: network.isReachable).permitsDictation
    }

    /// Signs somebody in, from the button to the cached profile.
    ///
    /// The whole exchange is one awaited sequence — start, open the browser, wait for the
    /// backend to say the browser half finished, read the profile — rather than two halves
    /// joined by a URL the operating system delivers. That is possible because no token
    /// ever travels through the browser: the app collects the session over its own
    /// connection, using a claim token the browser never saw.
    ///
    /// What it buys, beyond the security argument: the app is not reachable through a URL
    /// scheme any other program on the Mac can invoke, there is no callback to arrive
    /// after the user has walked away, and the sign-in either completes here or does not
    /// happen at all.
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

                // Which of the two ways this finishes is the machine's answer, not a
                // choice anybody made: a Mac that cannot bind a loopback port is given a
                // code to type instead, and the page has to say so rather than promising
                // a browser that will never come back.
                if case .code(let userCode, _) = challenge.method {
                    set(detail: .signIn(.enterCode(provider, code: userCode)))
                }
                openBrowser(challenge.authorisationURL)

                let profile = try await authentication.completeSignIn(challenge)
                try profiles.save(profile)
                // A real account supersedes the Mac one, and only after the profile has
                // been kept: clearing first and then failing to save would leave somebody
                // who was working happily with neither.
                local.clear()
                // Deliberately not guarded on the generation. A user who pressed Cancel
                // while the exchange was in flight is nonetheless signed in now, and a
                // sign-in page left in front of somebody with a session would be the app
                // disagreeing with its own disk.
                await moveOn(after: .signIn)
            } catch {
                // A failure is guarded, because it must not redraw a page the user has
                // since walked away from.
                guard generation == signInGeneration else { return }
                report(error)
            }
        }
    }

    /// Carries on without an account, as the person at this Mac.
    ///
    /// The one page in the product that could not work offline now has a way through it
    /// that needs nothing. It is offered rather than taken automatically, and it is
    /// offered on the same page as the providers rather than only after a failure: a
    /// choice that appears only once something has gone wrong reads as a consolation
    /// prize, and this is not one — see ``LocalAccount``.
    ///
    /// Any sign-in still waiting in a browser tab is abandoned first. Two answers to the
    /// same question, one of which arrives minutes later from another application, is
    /// exactly how a person ends up signed in as somebody they did not choose.
    private func continueOnThisMac() async {
        abandonSignIn()
        local.save(LocalAccount(name: systemName(), since: now()))
        await moveOn(after: .signIn)
    }

    /// Stops waiting for a sign-in that is somewhere else.
    ///
    /// The browser tab stays open — nothing here can close it — and the backend forgets
    /// the unfinished attempt within ten minutes, which is the same best-effort bargain a
    /// cancelled download makes.
    private func abandonSignIn() {
        signInGeneration += 1
        signInTask?.cancel()
        signInTask = nil
    }

    /// Puts a sign-in failure on the page in the words that failure already has.
    ///
    /// A missing connection becomes the offline page rather than an error, because it is
    /// not one: it is a statement about the network, it has its own screen in the
    /// designs, and that screen's Try Again is a better answer than a red sentence.
    private func report(_ failure: AccountError) {
        switch failure {
        case .serverUnreachable:
            set(detail: .signIn(.unreachable))
        case .providerRefused, .sessionMalformed, .sessionCouldNotBeKept:
            set(detail: .signIn(.refused(failure.userMessage)))
        }
    }

    // MARK: Finishing

    /// What the user can actually do, read from the system rather than remembered.
    ///
    /// Ordered by what stops them: no microphone means nothing runs at all, no model
    /// means nothing can be recognised, and no Accessibility access means the words
    /// arrive on the clipboard instead of at the cursor.
    private func readiness() async -> OnboardingReadiness {
        if await microphone.status() != .granted { return .needsMicrophone }
        if !installer.isInstalled { return .needsSpeechModel }
        if await accessibility.status() != .granted { return .pastesManually }
        return .ready
    }

    /// Closes onboarding, changing nothing about the user's preferences.
    ///
    /// It used to turn `opensAtLogin` on here, so that a menu bar app the user had just
    /// set up would be there at the next login. That is still the right outcome, and it
    /// is already the outcome: ``Settings`` ships with `opensAtLogin` true and
    /// ``SettingsStore/load()`` answers with the shipped value for anything never
    /// written, so somebody who has expressed no view has it on without a line here.
    ///
    /// Which leaves only the case where the stored value is `false` — and false is not
    /// reachable by accident. A missing or unreadable field decodes to the shipped
    /// `true`, and the sole writer of `false` is the switch on the Settings screen. So
    /// `false` on disk means the user turned it off, and writing `true` over it would
    /// be onboarding overruling them. Every write this line could make is therefore
    /// either a no-op or an override, which is why there is no longer a write.
    ///
    /// The last page is reachable by two roads now — a genuine first run, and the
    /// Account page's Sign In months later — but the flow does not have to tell them
    /// apart to get this right, and a rule that held only on one of the two roads would
    /// be the wrong rule anyway: a first-run user who opens Settings mid-onboarding and
    /// turns the switch off has expressed a view just as plainly.
    private func finish(with readiness: OnboardingReadiness) {
        record.recordFinished()
        isFinished = true
        onFinish?(readiness)
    }

    // MARK: Publishing

    private func set(step: OnboardingStep, detail: OnboardingDetail) {
        state = OnboardingState(step: step, detail: detail)
        onChange?(state)
    }

    private func set(detail: OnboardingDetail) {
        set(step: state.step, detail: detail)
    }
}
