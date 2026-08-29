import Foundation
import Testing

@testable import UttrflowAccount
@testable import UttrflowCore
@testable import UttrflowSettings
@testable import UttrflowUX

/// What the flow says when a callback answers somebody else's attempt. Taken from the
/// failure itself, so rewording it is not a failing test.
private let mismatch = AccountError.providerRefused(
    description: "the callback does not answer this sign-in")

@MainActor
@Suite("Onboarding sign-in")
struct OnboardingSignInTests {

    // MARK: The first thing anybody sees

    /// Welcome is the very first page, so the product says what it is before it asks
    /// who you are. The page immediately after asks, and the only thing beside the
    /// providers is the one deliberate way past them — working on this Mac, which is a
    /// decision the flow records rather than a page it waves through.
    @Test("opens on welcome, then asks who you are, offering one way past it")
    func signInComesAfterTheWelcome() async {
        let harness = Harness(signedIn: false)
        await harness.flow.start()
        #expect(harness.step == .welcome, "the pitch comes before the price")
        await harness.flow.perform(.advance)

        #expect(harness.step == .signIn)
        #expect(harness.detail == .signIn(.offering))
        #expect(harness.page.providers.map(\.provider) == SignInProvider.offered)
        #expect(harness.liveProviders == SignInProvider.offered)
        #expect(harness.buttonTitles == ["Continue on this Mac"])
        #expect(harness.page.hasSomethingToPress)
    }

    @Test("offers nothing that reads as a way to carry on without an account")
    func thereIsNoWayRoundIt() async {
        let harness = Harness(signedIn: false)
        await harness.startPastWelcome()

        let escapes = ["skip", "not now", "later", "without an account", "continue without"]
        let wording =
            (harness.buttonTitles + [harness.page.title, harness.page.subtitle])
            .joined(separator: " ")
            .lowercased()
        for escape in escapes {
            #expect(!wording.contains(escape), "the sign-in page hints at \(escape)")
        }
        #expect(!harness.page.buttons.contains { $0.intent == .advance })
    }

    // MARK: The way past it

    /// The reason this exists: the one page in the product that needs a network must not
    /// be a wall for somebody whose network will not cooperate. What it records is the
    /// Mac's own name — nothing is invented and nothing is fetched.
    @Test("continuing on this Mac records who is here and moves the flow on")
    func continuingOnThisMac() async {
        let harness = Harness(signedIn: false, systemName: "Naveen Bhatt")
        await harness.startPastWelcome()
        #expect(harness.step == .signIn)

        await harness.flow.perform(.continueOnThisMac)

        #expect(harness.local.load()?.name == "Naveen Bhatt")
        #expect(harness.step != .signIn, "the page it exists to get past is still on screen")
        #expect(harness.profiles.load() == nil, "no session was invented to get past it")
    }

    /// A Mac that will not say who owns it is still a Mac somebody can work on. The
    /// account is recorded with no name rather than with a made-up one.
    @Test("works on a Mac that will not say whose it is")
    func continuingWithNoName() async {
        let harness = Harness(signedIn: false, systemName: nil)
        await harness.startPastWelcome()

        await harness.flow.perform(.continueOnThisMac)

        #expect(harness.local.load() != nil)
        #expect(harness.local.load()?.name == nil)
    }

    /// Offline is the situation this was built for, so it is the one worth asserting on
    /// end to end rather than only in the list of buttons.
    @Test("offline, the Mac account is a way out rather than a wall")
    func continuingWhileOffline() async {
        let harness = Harness(signedIn: false, reachable: false)
        await harness.startPastWelcome()
        #expect(harness.detail == .signIn(.unreachable))

        await harness.flow.perform(.continueOnThisMac)
        #expect(harness.local.load() != nil)
        #expect(harness.step != .signIn)
    }

    /// The same guard `cancelSignIn` keeps, for the same reason: an instruction that
    /// could only have come from a page the user has left must not act on their behalf.
    @Test("cannot be chosen from a page that is not asking who you are")
    func ignoredAwayFromTheSignInPage() async {
        let harness = Harness(microphone: .notDetermined, signedIn: true)
        await harness.startPastWelcome()
        #expect(harness.step != .signIn)

        await harness.flow.perform(.continueOnThisMac)
        #expect(harness.local.load() == nil)
    }

    /// A real account supersedes the Mac one. Both present would be two answers to "who
    /// is here", and every page that draws one would have to pick.
    @Test("signing in for real forgets the Mac account")
    func signingInReplacesTheMacAccount() async {
        let harness = Harness(signedIn: false)
        await harness.startPastWelcome()
        await harness.flow.perform(.continueOnThisMac)
        #expect(harness.local.load() != nil)

        // Back to the sign-in page, the way the Account page's Sign In button gets there.
        await harness.flow.resume(askingToSignIn: true)
        #expect(harness.step == .signIn, "the button that asks to sign in must land on it")
        #expect(await harness.choose(.google))
        await harness.returnFromBrowser()

        #expect(harness.profiles.load() != nil)
        #expect(harness.local.load() == nil)
    }

    @Test("says on the page itself what a person is agreeing to")
    func theTermsAreOnThePage() async {
        let harness = Harness(signedIn: false)
        await harness.startPastWelcome()

        #expect(harness.page.fineprint?.contains("Terms of Use") == true)
        #expect(harness.page.fineprint?.contains("Privacy Policy") == true)
    }

    // MARK: Signing in

    @Test("opens the provider's page in the browser and waits there")
    func choosingAProviderOpensTheBrowser() async {
        let harness = Harness(signedIn: false)
        await harness.startPastWelcome()

        #expect(await harness.choose(.google))
        #expect(harness.authentication.startedProviders == [.google])
        #expect(harness.browser.urls.count == 1)
        #expect(harness.detail == .signIn(.signingIn(.google)))
        // Waiting on a window somewhere else, so there has to be a way out of waiting.
        #expect(harness.buttonTitles == ["Cancel"])
        #expect(harness.liveProviders.isEmpty)
    }

    @Test("the backend answering signs the user in and moves on")
    func aFinishedSignInMovesOn() async {
        let harness = Harness(microphone: .granted, accessibility: .granted, signedIn: false)
        await harness.startPastWelcome()
        #expect(await harness.choose(.google))

        await harness.returnFromBrowser()
        #expect(harness.profiles.load() != nil)
        // Onwards, not back: welcome is behind us and signing in is the page we just
        // answered, so the next page has to be neither.
        #expect(harness.step != .signIn)
        #expect(harness.step != .welcome)
    }

    /// Nothing is waiting, so nothing can be answered.
    ///
    /// This used to be a real risk: an `uttrflow://` URL carrying a state and a code could
    /// arrive from anywhere on the machine, at any time, and the flow had to refuse the
    /// ones it had not asked for. The app no longer has a way in — it holds the sign-in
    /// open itself — so what is left to check is that an answer nobody asked for changes
    /// nothing. Whether an answer belongs to *this* attempt is now the service's to
    /// decide, and is tested there.
    @Test("does nothing at all when no sign-in is in flight")
    func nothingHappensWithoutAnAttempt() async {
        let harness = Harness(signedIn: false)
        await harness.startPastWelcome()
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
        await harness.startPastWelcome()
        #expect(await harness.choose(.google))

        await harness.returnFromBrowser()
        #expect(harness.detail == .signIn(.refused(refusal.userMessage)))
        #expect(harness.page.subtitle == refusal.userMessage)
        #expect(harness.page.hasSomethingToPress)
    }

    @Test("a profile this build cannot believe is refused at the door")
    func anUnbelievableSessionIsRefused() async {
        let harness = Harness(
            signedIn: false, profiles: InMemoryProfileCache(refusesToSave: true))
        await harness.startPastWelcome()
        #expect(await harness.choose(.google))

        await harness.returnFromBrowser()
        #expect(harness.detail == .signIn(.refused(AccountError.sessionMalformed.userMessage)))
        #expect(harness.profiles.load() == nil)
    }

    @Test("a provider that cannot even be reached lands on the offline page, not an error")
    func anUnreachableProviderLandsOffline() async {
        let harness = Harness(
            signedIn: false,
            authentication: FakeAuthenticationService(beginFailure: .serverUnreachable))
        await harness.startPastWelcome()

        #expect(await harness.choose(.google))
        #expect(harness.detail == .signIn(.unreachable))
        #expect(harness.buttonTitles == ["Try Again", "Continue on this Mac"])
    }

    // MARK: Offline

    @Test("offline, the buttons stay in view and inert and the banner says which step needs a network")
    func offlineIsDrawnRatherThanFailed() async {
        let harness = Harness(signedIn: false, reachable: false)
        await harness.startPastWelcome()

        #expect(harness.detail == .signIn(.unreachable))
        #expect(harness.page.providers.count == SignInProvider.offered.count)
        #expect(harness.liveProviders.isEmpty)
        #expect(harness.page.note?.tone == .warning)
        #expect(harness.page.note?.text.contains("cannot do") == true)
        // Trying again is the prominent one; the Mac account is what a person behind a
        // portal that will never come back reaches for instead.
        #expect(harness.buttonTitles == ["Try Again", "Continue on this Mac"])
        #expect(harness.page.hasSomethingToPress)
    }

    @Test("an inert button cannot be pressed into starting a sign-in")
    func inertMeansInert() async {
        let harness = Harness(signedIn: false, reachable: false)
        await harness.startPastWelcome()

        #expect(await harness.choose(.google) == false)
        // And not even a direct instruction gets past it, because the guard is in the
        // flow rather than in whatever happens to be drawing.
        await harness.flow.perform(.signIn(.google))
        #expect(harness.authentication.startedProviders.isEmpty)
        #expect(harness.detail == .signIn(.unreachable))
    }

    @Test("Try Again picks up a connection that has come back")
    func tryAgainNoticesTheConnection() async {
        let harness = Harness(signedIn: false, reachable: false)
        await harness.startPastWelcome()

        #expect(await harness.press("Try Again"))
        #expect(harness.detail == .signIn(.unreachable))

        harness.network.set(true)
        #expect(await harness.press("Try Again"))
        #expect(harness.detail == .signIn(.offering))
        #expect(harness.liveProviders == SignInProvider.offered)
    }

    @Test("coming back to the window notices the connection too, but never disturbs an attempt")
    func returningToTheWindowRereadsTheConnection() async {
        let harness = Harness(signedIn: false, reachable: false)
        await harness.startPastWelcome()

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
        await harness.startPastWelcome()
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
        await harness.startPastWelcome()

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
        await harness.startPastWelcome()
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
        await harness.startPastWelcome()
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
        await harness.startPastWelcome()
        #expect(await harness.choose(.google))

        let finishing = Task { await harness.returnFromBrowser() }
        await settle(until: { gate.arrivals == 1 })
        await harness.flow.perform(.cancelSignIn)

        gate.open()
        await finishing.value
        // The answer was already on its way when Cancel was pressed, so it lands. There is
        // a profile on the disk now, and a page asking them to sign in would be the app
        // disagreeing with itself.
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
        #expect(harness.step == .welcome, "welcome is the first page for everybody")
        await harness.flow.perform(.advance)

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
            await harness.startPastWelcome()
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

        // Welcome's own button, then straight to the end: with everything granted and a
        // session already on disk, nothing between here and Ready needs a network.
        #expect(await harness.press("Continue"))
        #expect(harness.detail == .finishing(.ready))
        #expect(await harness.press("Start Using Uttrflow"))
        #expect(harness.finishedWith == .ready)
    }
}

// MARK: A Mac with nowhere for the browser to come back to

/// The fallback, from the page's side.
///
/// A locked-down laptop, an SSH session, a container: the loopback port cannot be bound,
/// and the person is given a code to type instead. It is not a lesser path — it is RFC
/// 8628, the flow a television uses — but it is a *different page*, and getting that wrong
/// means somebody is told to finish in their browser while the code sits unmentioned.
extension OnboardingSignInTests {
    @Test("shows the code when this Mac cannot be redirected back to")
    func aCodeIsShownWhenThereIsNoPort() async {
        let harness = Harness(
            signedIn: false,
            authentication: FakeAuthenticationService(
                completeGate: Gate(),
                method: .code(userCode: "BCDF-GHJK", verificationURL: safeSignInURL(.google))))
        await harness.startPastWelcome()

        #expect(await harness.choose(.google))
        #expect(harness.detail == .signIn(.enterCode(.google, code: "BCDF-GHJK")))
        #expect(harness.page.code == "BCDF-GHJK")
        // The sentence says what to do with it rather than repeating it, and says that
        // the window to do it in is already open — because it is.
        #expect(harness.page.subtitle.contains("Type this code"))
        #expect(harness.page.subtitle.contains("browser is open"))
        #expect(harness.page.subtitle.contains("BCDF-GHJK") == false)
        // The browser is still opened — at the page the code is typed into.
        #expect(harness.browser.urls.count == 1)
        // And the page says why it is asking for a code at all rather than handing the
        // user back. Without it this reads as a second, stranger product.
        #expect(harness.page.note?.text.contains("hands you straight back") == true)
    }

    @Test("waiting on a code is still somewhere a person can leave")
    func aCodeCanBeAbandoned() async {
        let harness = Harness(
            signedIn: false,
            authentication: FakeAuthenticationService(
                completeGate: Gate(),
                method: .code(userCode: "BCDF-GHJK", verificationURL: safeSignInURL(.google))))
        await harness.startPastWelcome()
        #expect(await harness.choose(.google))

        #expect(harness.buttonTitles == ["Cancel"])
        #expect(harness.liveProviders.isEmpty, "a provider could be pressed while a code was waiting")

        #expect(await harness.press("Cancel"))
        #expect(harness.detail == .signIn(.offering))
    }

    @Test("the ordinary path still promises a browser rather than a code")
    func theBrowserPathIsUnchanged() async {
        let harness = Harness(signedIn: false)
        await harness.startPastWelcome()
        #expect(await harness.choose(.google))

        #expect(harness.detail == .signIn(.signingIn(.google)))
        #expect(harness.page.code == nil)
        #expect(harness.page.subtitle.contains("in your browser"))
    }

    @Test("a code sign-in finishes exactly as a browser one does")
    func aCodeSignInFinishes() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, signedIn: false,
            authentication: FakeAuthenticationService(
                completeGate: Gate(),
                method: .code(userCode: "BCDF-GHJK", verificationURL: safeSignInURL(.google))))
        await harness.startPastWelcome()
        #expect(await harness.choose(.google))

        await harness.returnFromBrowser()
        #expect(harness.profiles.load() != nil)
        #expect(harness.step != .signIn)
    }
}
