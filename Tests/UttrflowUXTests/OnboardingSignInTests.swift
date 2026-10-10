// Tests for the sign-in page: the way past it, signing in, offline, giving up, and the code fallback.
import Foundation
import Testing

@testable import UttrflowAccount
@testable import UttrflowCore
@testable import UttrflowSettings
@testable import UttrflowUX

/// What the flow says when a callback answers somebody else's attempt, taken from the failure itself.
private let mismatch = AccountError.providerRefused(
    description: "the callback does not answer this sign-in")

@MainActor
@Suite("Onboarding sign-in")
struct OnboardingSignInTests {

    // MARK: The first thing anybody sees

    /// The pitch and the providers share the first page, alongside the usage choice.
    @Test("opens on sign-in with providers and the usage statistics choice")
    func signInComesFirst() async {
        let harness = Harness(signedIn: false)
        await harness.flow.start()

        #expect(harness.step == .signIn)
        #expect(harness.page.position == 1)
        #expect(harness.detail == .signIn(.offering))
        #expect(harness.page.providers.map(\.provider) == SignInProvider.offered)
        #expect(harness.liveProviders == SignInProvider.offered)
        #expect(harness.buttonTitles == ["Keep off", "Share"])
        #expect(harness.page.explanation?.hasPrefix(OnboardingPresenter.pitch) == true)
    }

    @Test("offers nothing that reads as a way to carry on without an account")
    func thereIsNoWayRoundIt() async {
        let harness = Harness(signedIn: false)
        await harness.flow.start()

        let escapes = ["skip", "not now", "later", "without an account", "continue without"]
        let wording =
            (harness.buttonTitles + [harness.page.title, harness.page.explanation ?? ""])
            .joined(separator: " ")
            .lowercased()
        for escape in escapes {
            #expect(!wording.contains(escape), "the sign-in page hints at \(escape)")
        }
        #expect(!harness.page.buttons.contains { $0.intent == .advance })
        await harness.flow.perform(.advance)
        #expect(harness.step == .signIn, "a stray advance walked past sign-in")
    }

    // MARK: Nobody past it without a session

    /// An upgrade from a build that allowed working without an account has finished setup and holds no session.
    @Test("a Mac that finished setup but holds no session opens on sign-in")
    func finishedButSignedOutOpensOnSignIn() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, hasFinished: true, signedIn: false)
        await harness.flow.start()
        #expect(harness.step == .signIn)
        await harness.flow.perform(.advance)
        #expect(harness.step == .signIn, "an advance walked a signed-out Mac past sign-in")
    }

    /// The rest of the app waits on the session, so it is told the moment one is kept.
    @Test("tells the app as soon as a sign-in's profile is kept, and not before")
    func signInIsAnnounced() async {
        let harness = Harness(signedIn: false)
        var announced = 0
        harness.flow.onSignIn = { announced += 1 }
        await harness.flow.start()
        #expect(await harness.choose(.google))
        #expect(announced == 0, "announced before the browser came back")

        await harness.returnFromBrowser()

        #expect(harness.profiles.load() != nil)
        #expect(announced == 1)
    }

    @Test("says on the page itself what a person is agreeing to")
    func theTermsAreOnThePage() async {
        let harness = Harness(signedIn: false)
        await harness.flow.start()

        #expect(harness.page.showsTerms)
    }

    // MARK: Signing in

    @Test("opens the provider's page in the browser and waits there")
    func choosingAProviderOpensTheBrowser() async {
        let harness = Harness(signedIn: false)
        await harness.flow.start()

        #expect(await harness.choose(.google))
        #expect(harness.authentication.startedProviders == [.google])
        #expect(harness.browser.urls.count == 1)
        #expect(harness.detail == .signIn(.signingIn(.google)))
        // Waiting on a window somewhere else, so there has to be a way out of waiting.
        #expect(harness.buttonTitles == ["Reopen", "Cancel"])
        #expect(harness.liveProviders.isEmpty)
    }

    @Test("Reopen sends the browser back to the provider's page, and only while a sign-in waits")
    func reopenOpensTheSamePageAgain() async {
        let harness = Harness(signedIn: false)
        await harness.flow.perform(.reopenBrowser)
        #expect(harness.browser.urls.isEmpty, "nothing was waiting, yet the browser opened")

        await harness.flow.start()
        #expect(await harness.choose(.google))
        #expect(await harness.press("Reopen"))
        #expect(harness.browser.urls.count == 2)
        #expect(harness.browser.urls.first == harness.browser.urls.last)

        #expect(await harness.press("Cancel"))
        await harness.flow.perform(.reopenBrowser)
        #expect(harness.browser.urls.count == 2, "a cancelled sign-in reopened its page")
    }

    @Test("the backend answering signs the user in and moves on")
    func aFinishedSignInMovesOn() async {
        let harness = Harness(microphone: .granted, accessibility: .granted, signedIn: false)
        await harness.flow.start()
        #expect(await harness.choose(.google))

        await harness.returnFromBrowser()
        #expect(harness.profiles.load() != nil)
        // Onwards: sign-in is just answered.
        #expect(harness.step != .signIn)
    }

    /// Nothing is waiting, so an answer nobody asked for changes nothing.
    @Test("does nothing at all when no sign-in is in flight")
    func nothingHappensWithoutAnAttempt() async {
        let harness = Harness(signedIn: false)
        await harness.flow.start()
        let before = harness.flow.state

        await harness.returnFromBrowser()
        #expect(harness.flow.state == before)
        #expect(harness.profiles.load() == nil)
    }

    @Test("a provider that says no leaves the page usable and says why")
    func aRefusedSignInIsSaidPlainly() async {
        let refusal = AccountError.providerRefused(description: "the account is not allowed")
        let harness = Harness(
            signedIn: false,
            authentication: FakeAuthenticationService(completeFailure: refusal))
        await harness.flow.start()
        #expect(await harness.choose(.google))

        await harness.returnFromBrowser()
        #expect(harness.detail == .signIn(.refused(refusal.userMessage)))
        #expect(harness.page.hint == refusal.userMessage)
        #expect(harness.page.hasSomethingToPress)
    }

    @Test("a profile this build cannot believe is refused at the door")
    func anUnbelievableSessionIsRefused() async {
        let harness = Harness(
            signedIn: false, profiles: InMemoryProfileCache(refusesToSave: true))
        await harness.flow.start()
        #expect(await harness.choose(.google))

        await harness.returnFromBrowser()
        #expect(harness.detail == .signIn(.refused(AccountError.sessionMalformed.userMessage)))
        #expect(harness.profiles.load() == nil)
    }

    @Test("a profile this build cannot believe leaves every provider live for a fresh sign-in")
    func anUnbelievableSessionCanBeSignedInAgain() async {
        let harness = Harness(
            signedIn: false, profiles: InMemoryProfileCache(refusesToSave: true))
        await harness.flow.start()
        #expect(await harness.choose(.google))

        await harness.returnFromBrowser()
        #expect(harness.page.hint == AccountError.sessionMalformed.userMessage)
        #expect(harness.liveProviders == SignInProvider.offered)
        #expect(harness.page.hasSomethingToPress)
    }

    @Test("a provider that cannot even be reached lands on the offline page, not an error")
    func anUnreachableProviderLandsOffline() async {
        let harness = Harness(
            signedIn: false,
            authentication: FakeAuthenticationService(beginFailure: .serverUnreachable))
        await harness.flow.start()

        #expect(await harness.choose(.google))
        #expect(harness.detail == .signIn(.unreachable))
        #expect(harness.buttonTitles == ["Try again"])
    }

    // MARK: Offline

    @Test("offline, the page blocks on trying again and says which step needs a network")
    func offlineIsDrawnRatherThanFailed() async {
        let harness = Harness(signedIn: false, reachable: false)
        await harness.flow.start()

        #expect(harness.detail == .signIn(.unreachable))
        #expect(harness.page.providers.isEmpty)
        #expect(harness.page.explanation?.contains("needs the internet") == true)
        #expect(harness.buttonTitles == ["Try again"])
        #expect(harness.page.hasSomethingToPress)
    }

    @Test("an inert button cannot be pressed into starting a sign-in")
    func inertMeansInert() async {
        let harness = Harness(signedIn: false, reachable: false)
        await harness.flow.start()

        #expect(await harness.choose(.google) == false)
        // Not even a direct instruction gets past it, since the guard is in the flow, not the view.
        await harness.flow.perform(.signIn(.google))
        #expect(harness.authentication.startedProviders.isEmpty)
        #expect(harness.detail == .signIn(.unreachable))
    }

    @Test("Try Again picks up a connection that has come back")
    func tryAgainNoticesTheConnection() async {
        let harness = Harness(signedIn: false, reachable: false)
        await harness.flow.start()

        #expect(await harness.press("Try again"))
        #expect(harness.detail == .signIn(.unreachable))

        harness.network.set(true)
        #expect(await harness.press("Try again"))
        #expect(harness.detail == .signIn(.offering))
        #expect(harness.liveProviders == SignInProvider.offered)
    }

    @Test("coming back to the window notices the connection too, but never disturbs an attempt")
    func returningToTheWindowRereadsTheConnection() async {
        let harness = Harness(signedIn: false, reachable: false)
        await harness.flow.start()

        harness.network.set(true)
        await harness.flow.refresh()
        #expect(harness.detail == .signIn(.offering))

        #expect(await harness.choose(.google))
        let waiting = harness.flow.state
        await harness.flow.refresh()
        #expect(harness.flow.state == waiting)
    }

    // MARK: Giving up, and coming back

    @Test("a sign-in the user gave up on cannot finish behind their back")
    func cancellingASignInIsFinal() async {
        let harness = Harness(signedIn: false)
        await harness.flow.start()
        #expect(await harness.choose(.google))

        #expect(await harness.press("Cancel"))
        #expect(harness.detail == .signIn(.offering))

        // The backend answers anyway. The attempt was cancelled, so the answer is dropped.
        await harness.returnFromBrowser()
        #expect(harness.profiles.load() == nil)
        #expect(harness.detail == .signIn(.offering))
    }

    @Test("a sign-in cancelled mid-request never reaches the browser")
    func cancellingBeforeTheChallengeArrives() async {
        let gate = Gate()
        let harness = Harness(
            signedIn: false, authentication: FakeAuthenticationService(beginGate: gate))
        await harness.flow.start()

        let starting = Task { await harness.flow.perform(.signIn(.google)) }
        await settle(until: { gate.arrivals == 1 })
        await harness.flow.perform(.cancelSignIn)

        gate.open()
        await starting.value
        #expect(harness.browser.urls.isEmpty)
        #expect(harness.detail == .signIn(.offering))
    }

    @Test("a request that fails after the user gave up cannot redraw the page")
    func aStaleFailureIsDropped() async {
        let gate = Gate()
        let harness = Harness(
            signedIn: false,
            authentication: FakeAuthenticationService(
                beginFailure: .providerRefused(description: "too late"), beginGate: gate),
            reachable: false)
        await harness.flow.start()
        harness.network.set(true)
        await harness.flow.refresh()

        let starting = Task { await harness.flow.perform(.signIn(.google)) }
        await settle(until: { gate.arrivals == 1 })
        await harness.flow.perform(.cancelSignIn)

        gate.open()
        await starting.value
        #expect(harness.detail == .signIn(.offering))
    }

    @Test("an exchange that fails after the user gave up cannot redraw the page either")
    func aStaleExchangeFailureIsDropped() async {
        let gate = Gate()
        let harness = Harness(
            signedIn: false,
            authentication: FakeAuthenticationService(
                completeFailure: .providerRefused(description: "too late"), completeGate: gate))
        await harness.flow.start()
        #expect(await harness.choose(.google))

        let finishing = Task { await harness.returnFromBrowser() }
        await settle(until: { gate.arrivals == 1 })
        await harness.flow.perform(.cancelSignIn)

        gate.open()
        await finishing.value
        #expect(harness.detail == .signIn(.offering))
    }

    @Test("an exchange that succeeds after the user gave up still signs them in")
    func aLateSuccessIsStillASuccess() async {
        let gate = Gate()
        let harness = Harness(
            microphone: .granted, accessibility: .granted, signedIn: false,
            authentication: FakeAuthenticationService(
                completeGate: gate, respectsCancellation: false))
        await harness.flow.start()
        #expect(await harness.choose(.google))

        let finishing = Task { await harness.returnFromBrowser() }
        await settle(until: { gate.arrivals == 1 })
        await harness.flow.perform(.cancelSignIn)

        gate.open()
        await finishing.value
        // The answer was already on its way when Cancel was pressed, so it lands and the page moves on.
        await settle(until: { harness.profiles.load() != nil })
        #expect(harness.profiles.load() != nil)
        await settle(until: { harness.step != .signIn })
        #expect(harness.step != .signIn)
    }

    // MARK: Every launch after the first

    @Test("a Mac with a session is never asked to sign in again")
    func aSignedInMacIsNotAskedTwice() async {
        let harness = Harness(signedIn: true)
        await harness.flow.start()

        // Straight past sign-in to the first thing actually outstanding.
        #expect(harness.step != .signIn)
        #expect(!harness.published.contains { $0.step == .signIn })
    }

    @Test("an entitlement that has aged out is a degrade, not a second sign-in")
    func anExpiredEntitlementDoesNotLockAnybodyOut() async {
        let past = Date(timeIntervalSince1970: 1_700_000_000)
        for reachable in [true, false] {
            let harness = Harness(
                signedIn: true, entitlementExpiring: past, reachable: reachable)
            await harness.flow.start()
            #expect(
                harness.step != .signIn,
                "reachable: \(reachable) was sent back to sign-in by an expired entitlement")
        }
    }

    @Test("signing in offline is the only thing a missing network stops")
    func nothingElseNeedsTheNetwork() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, signedIn: true, reachable: false)
        await harness.flow.start()

        // Straight to Ready: nothing after sign-in needs a network.
        #expect(harness.detail == .finishing(.ready))
        await harness.flow.perform(.finish)
        #expect(harness.finishedWith == .ready)
    }
}

// MARK: A Mac with nowhere for the browser to come back to

/// The code fallback from the page's side: a different page, not a lesser path (RFC 8628).
extension OnboardingSignInTests {
    @Test("shows the code when this Mac cannot be redirected back to")
    func aCodeIsShownWhenThereIsNoPort() async {
        let harness = Harness(
            signedIn: false,
            authentication: FakeAuthenticationService(
                completeGate: Gate(),
                method: .code(userCode: "BCDF-GHJK", verificationURL: safeSignInURL(.google))))
        await harness.flow.start()

        #expect(await harness.choose(.google))
        #expect(harness.detail == .signIn(.enterCode(.google, code: "BCDF-GHJK")))
        #expect(harness.page.picture == .code("BCDF-GHJK"))
        // The sentence says what to do with the code, and that the browser is already open.
        #expect(harness.page.explanation?.contains("Type this code") == true)
        #expect(harness.page.explanation?.contains("browser is open") == true)
        #expect(harness.page.explanation?.contains("BCDF-GHJK") == false)
        // The browser is still opened — at the page the code is typed into.
        #expect(harness.browser.urls.count == 1)
    }

    @Test("waiting on a code is still somewhere a person can leave")
    func aCodeCanBeAbandoned() async {
        let harness = Harness(
            signedIn: false,
            authentication: FakeAuthenticationService(
                completeGate: Gate(),
                method: .code(userCode: "BCDF-GHJK", verificationURL: safeSignInURL(.google))))
        await harness.flow.start()
        #expect(await harness.choose(.google))

        #expect(harness.buttonTitles == ["Reopen", "Cancel"])
        #expect(harness.liveProviders.isEmpty, "a provider could be pressed while a code was waiting")

        #expect(await harness.press("Cancel"))
        #expect(harness.detail == .signIn(.offering))
    }

    @Test("the ordinary path still promises a browser rather than a code")
    func theBrowserPathIsUnchanged() async {
        let harness = Harness(signedIn: false)
        await harness.flow.start()
        #expect(await harness.choose(.google))

        #expect(harness.detail == .signIn(.signingIn(.google)))
        #expect(harness.page.picture == .waveform(.idle, badge: .waitingOn(.google)))
        #expect(harness.page.explanation?.contains("in your browser") == true)
    }

    @Test("a code sign-in finishes exactly as a browser one does")
    func aCodeSignInFinishes() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, signedIn: false,
            authentication: FakeAuthenticationService(
                completeGate: Gate(),
                method: .code(userCode: "BCDF-GHJK", verificationURL: safeSignInURL(.google))))
        await harness.flow.start()
        #expect(await harness.choose(.google))

        await harness.returnFromBrowser()
        #expect(harness.profiles.load() != nil)
        #expect(harness.step != .signIn)
    }

    // MARK: A development build's stand-in

    @Test("a no-backend stand-in signs in on launch without network access")
    func aStandInSignsInOnLaunch() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, signedIn: false,
            authentication: FakeAuthenticationService(method: .standIn), reachable: false)
        var announced = 0
        harness.flow.onSignIn = { announced += 1 }

        await harness.flow.perform(.signIn(.google))
        await harness.flow.start()
        await settle(until: { harness.profiles.load() != nil })

        #expect(harness.authentication.startedProviders == [.google])
        #expect(harness.browser.urls.isEmpty)
        #expect(harness.profiles.load() != nil)
        #expect(announced == 1)
        #expect(harness.step != .signIn)
    }

    @Test("a completed setup can reopen with a fresh development stand-in")
    func completedSetupSignsInOnRelaunch() async {
        let harness = Harness(
            hasFinished: true, signedIn: false,
            authentication: FakeAuthenticationService(method: .standIn), reachable: false)

        await harness.flow.perform(.signIn(.google))
        await harness.flow.start()

        #expect(harness.flow.isRequired == false)
        #expect(harness.profiles.load() != nil)
        #expect(harness.authentication.startedProviders == [.google])
        #expect(harness.step != .signIn)
    }

    @Test("a real provider still waits for an explicit sign-in choice")
    func aRealProviderIsNotSignedInOnLaunch() async {
        let harness = Harness(signedIn: false, authentication: FakeAuthenticationService())

        await harness.flow.start()

        #expect(harness.authentication.startedProviders.isEmpty)
        #expect(harness.profiles.load() == nil)
        #expect(harness.step == .signIn)
    }

    @Test("a stand-in sign-in opens no browser and still moves on")
    func aStandInOpensNoBrowser() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, signedIn: false,
            authentication: FakeAuthenticationService(method: .standIn))
        await harness.flow.start()
        #expect(await harness.choose(.google))
        await harness.returnFromBrowser()

        #expect(harness.browser.urls.isEmpty, "a stand-in sent the browser to a page that resolves nowhere")
        #expect(harness.profiles.load() != nil)
        #expect(harness.step != .signIn)
        await harness.flow.perform(.reopenBrowser)
        #expect(harness.browser.urls.isEmpty, "Reopen found a page a stand-in never had")
    }

    @Test("the sign-in page says when it signs in as a stand-in, and only then")
    func aStandInIsLabelled() async {
        let standIn = Harness(signedIn: false, authentication: FakeAuthenticationService(method: .standIn))
        await standIn.flow.start()
        #expect(standIn.page.hint == OnboardingPresenter.standInHint)
        #expect(standIn.page.providers.map(\.provider) == SignInProvider.offered)

        let real = Harness(signedIn: false)
        await real.flow.start()
        #expect(real.page.hint == nil)
    }

    // MARK: The welcome

    /// Signs in with Google and stops on the welcome, whose countdown waits on `countdown`.
    @MainActor
    private func welcomed(countdown: Gate) async throws -> Harness {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, signedIn: false,
            pause: { _ in await countdown.wait() })
        await harness.flow.start()
        #expect(await harness.choose(.google))
        let complete = try #require(harness.authentication.completeGate)
        await settle(until: { complete.arrivals >= 1 })
        complete.open()
        await settle(until: { countdown.arrivals >= 1 })
        return harness
    }

    @Test("a finished sign-in shows the welcome, then moves on by itself when its moment has passed")
    func theWelcomeMovesOnByItself() async throws {
        let countdown = Gate()
        let harness = try await welcomed(countdown: countdown)
        guard case .signIn(.welcomed(let welcome)) = harness.detail else {
            Issue.record("a sign-in landed on \(harness.detail)")
            return
        }
        #expect(welcome.next == .ready, "microphone and Accessibility are granted, so the try comes next")
        #expect(welcome.provider == .google)
        #expect(harness.profiles.load() != nil, "the session is kept before the welcome shows")

        countdown.open()
        await settle(until: { harness.step != .signIn })
        #expect(harness.step == .ready)
    }

    @Test("Continue on the welcome moves on at once, and the countdown ending later changes nothing")
    func continuingFromTheWelcome() async throws {
        let countdown = Gate()
        let harness = try await welcomed(countdown: countdown)
        await harness.flow.perform(.advance)
        #expect(harness.step == .ready)
        let shown = harness.published.count

        countdown.open()
        for _ in 0..<100 { await Task.yield() }
        #expect(harness.step == .ready)
        #expect(harness.published.count == shown, "the countdown redrew a page the user had already left")
    }

    @Test("a sign-out during the welcome keeps its countdown from moving on")
    func signingOutDuringTheWelcome() async throws {
        let countdown = Gate()
        let harness = try await welcomed(countdown: countdown)
        await harness.flow.signedOut()
        #expect(harness.detail == .signIn(.offering))

        countdown.open()
        for _ in 0..<100 { await Task.yield() }
        #expect(harness.detail == .signIn(.offering))
    }
}
