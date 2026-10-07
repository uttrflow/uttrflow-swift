// Tests for the onboarding flow: starting, permissions, the download, the first try, finishing, and stray intents.
import Testing
import UttrflowCore

@testable import UttrflowCore
@testable import UttrflowSettings
@testable import UttrflowUX

/// The download failure the tests script, taken from the error so a reworded message is not a failure.
private let downloadFailure = SpeechEngineError.modelDownloadFailed(description: "offline")

/// The keys the last page draws, or none on a page that draws no keys.
private func keys(of page: OnboardingPage) -> [String] {
    guard case .keyboard(let keyboard) = page.picture else { return [] }
    return keyboard.keys
}

@MainActor
@Suite("Onboarding flow")
struct OnboardingFlowTests {

    @Test("saves the usage statistics choice immediately on the onboarding sign-in page")
    func savesUsageStatisticsChoice() async {
        let harness = Harness(signedIn: false)
        await harness.flow.start()

        #expect(harness.step == .signIn)
        #expect(harness.buttonTitles == ["Keep off", "Share"])
        await harness.flow.perform(.setUsageStatistics(true))
        #expect(harness.settingsStore.load().sharesUsageStatistics)

        await harness.flow.perform(.setUsageStatistics(false))
        #expect(!harness.settingsStore.load().sharesUsageStatistics)
    }

    // MARK: Getting under way

    @Test("opens on the first page with something to ask, with a dot for every page there will be")
    func opensOnTheFirstQuestion() async {
        // Signed in already, so the first question left is the microphone.
        let harness = Harness()
        await harness.flow.start()

        #expect(harness.step == .microphone)
        #expect(harness.detail == .permission(.notDetermined))
        #expect(harness.page.position == OnboardingStep.microphone.position)
        #expect(harness.page.stepCount == OnboardingStep.allCases.count)
        #expect(harness.buttonTitles == ["Allow"])
    }

    /// What the Account page's Sign In reaches.
    @Test("opens on sign-in when nobody is signed in, whatever else is granted")
    func resumeOpensOnSignIn() async {
        let harness = Harness(microphone: .granted, accessibility: .granted, signedIn: false)
        await harness.flow.start()

        #expect(harness.step == .signIn)
    }

    /// Signing back in and finding the app still mute would be worse than one extra page.
    @Test("a signed-in start still walks everything after sign-in, not only sign-in")
    func resumeStillAsksForPermissions() async {
        let harness = Harness(microphone: .notDetermined, accessibility: .granted, signedIn: true)
        await harness.flow.start()

        #expect(harness.step == .microphone)
    }

    // MARK: A permission that is already granted

    @Test("passes over a permission macOS has already granted rather than agreeing with itself")
    func skipsGrantedPermissions() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()

        #expect(harness.step == .ready)
        #expect(harness.detail == .finishing(.ready))
        #expect(!harness.published.contains { $0.step == .microphone })
        #expect(!harness.published.contains { $0.step == .accessibility })
    }

    @Test("finishes manually when Accessibility is denied, and ready when it is granted")
    func finishingReflectsAccessibilityPermission() async {
        let denied = Harness(microphone: .granted, accessibility: .denied)
        await denied.flow.start()
        #expect(denied.step == .accessibility)
        #expect(denied.detail == .permission(.denied))

        // Only a device policy lets the user past Accessibility without granting it.
        await denied.accessibility.setStatus(.restricted)
        await denied.flow.refresh()
        #expect(await denied.press("Continue"))
        #expect(denied.step == .ready)
        #expect(denied.detail == .finishing(.pastesManually))
        await denied.flow.perform(.finish)
        #expect(denied.finishedWith == .pastesManually)

        let granted = Harness(microphone: .granted, accessibility: .granted)
        await granted.flow.start()

        #expect(granted.step == .ready)
        #expect(granted.detail == .finishing(.ready))
        await granted.flow.perform(.finish)
        #expect(granted.finishedWith == .ready)
    }

    @Test("a yes at the prompt says so on the page, and Continue moves on")
    func grantingAtThePromptSaysSo() async {
        let harness = Harness(
            microphone: .notDetermined, microphoneAfterAsking: .granted, accessibility: .granted)
        await harness.flow.start()

        #expect(await harness.press("Allow"))
        #expect(harness.step == .microphone)
        #expect(harness.detail == .permission(.granted))
        #expect(harness.page.mood == .done)
        #expect(await harness.press("Continue"))
        #expect(harness.step == .ready)
        #expect(harness.detail == .finishing(.ready))
    }

    // MARK: A permission that is refused

    @Test("a no at the prompt turns the page into the way to System Settings, and nothing past it")
    func refusingAtThePromptOffersSystemSettings() async {
        let harness = Harness(microphone: .notDetermined, microphoneAfterAsking: .denied)
        await harness.flow.start()

        #expect(await harness.press("Allow"))
        #expect(harness.step == .microphone)
        #expect(harness.detail == .permission(.denied))
        #expect(harness.buttonTitles == ["Settings"])
    }

    @Test("granted in System Settings, and the user comes back to say so")
    func grantedWhileAway() async {
        let harness = Harness(microphone: .notDetermined, microphoneAfterAsking: .denied)
        await harness.flow.start()
        #expect(await harness.press("Allow"))

        #expect(await harness.press("Settings"))
        #expect(harness.panes.panes == [.microphone])
        #expect(harness.detail == .awaitingSystemSettings)
        #expect(harness.buttonTitles == ["Settings", "Check"])

        await harness.microphone.setStatus(.granted)
        await harness.flow.refresh()
        #expect(harness.detail == .permission(.granted))
        #expect(await harness.press("Continue"))
        #expect(harness.step != .microphone)
    }

    /// Checking again must not loop, and the pane stays reachable however many times it is pressed.
    @Test("still refused on the way back: no loop, and no way past")
    func stillRefusedOnReturn() async {
        let harness = Harness(microphone: .notDetermined, microphoneAfterAsking: .denied)
        await harness.flow.start()
        #expect(await harness.press("Allow"))
        #expect(await harness.press("Settings"))

        await harness.flow.refresh()
        #expect(harness.detail == .awaitingSystemSettings)
        #expect(await harness.press("Check"))
        #expect(harness.step == .microphone)
        #expect(harness.detail == .awaitingSystemSettings)
        #expect(harness.buttonTitles == ["Settings", "Check"])

        // A stray advance is refused by the flow itself, not only by the page.
        await harness.flow.perform(.advance)
        #expect(harness.step == .microphone)

        #expect(await harness.press("Settings"))
        #expect(harness.step == .microphone)
        #expect(harness.panes.panes == [.microphone, .microphone])
    }

    @Test("a permission taken away by policy while the user was out lets them on")
    func blockedWhileAway() async {
        let harness = Harness(microphone: .notDetermined, microphoneAfterAsking: .denied)
        await harness.flow.start()
        #expect(await harness.press("Allow"))
        #expect(await harness.press("Settings"))

        await harness.microphone.setStatus(.restricted)
        await harness.flow.refresh()
        #expect(harness.detail == .permission(.restricted))
        #expect(harness.buttonTitles == ["Continue"])
        #expect(await harness.press("Continue"))
        #expect(harness.step != .microphone)
    }

    @Test("a permission blocked by policy never pretends it can be asked for")
    func restrictedFromTheStart() async {
        let harness = Harness(microphone: .restricted, microphoneAfterAsking: nil)
        await harness.flow.start()

        #expect(harness.detail == .permission(.restricted))
        #expect(harness.buttonTitles == ["Continue"])
        #expect(harness.page.hint?.contains("policy") == true)
    }

    // MARK: Accessibility

    @Test("offers to ask for Accessibility when macOS has not been asked yet")
    func accessibilityCanBeAskedFor() async {
        let harness = Harness(
            microphone: .granted, accessibility: .notDetermined,
            accessibilityAfterAsking: .granted)
        await harness.flow.start()

        #expect(harness.step == .accessibility)
        #expect(harness.buttonTitles == ["Allow"])
        #expect(await harness.press("Allow"))
        #expect(harness.detail == .permission(.granted))
        #expect(await harness.press("Continue"))
        #expect(harness.detail == .finishing(.ready))
    }

    /// `AXIsProcessTrusted` cannot say "not asked", so the first visit still asks rather than sending them away.
    @Test("sends the user to the Accessibility pane once the ask has been made")
    func accessibilityGoesToItsOwnPane() async {
        let harness = Harness(microphone: .granted, accessibility: .denied)
        await harness.flow.start()

        #expect(harness.step == .accessibility)
        #expect(await harness.press("Allow"))
        #expect(harness.detail == .awaitingSystemSettings)
        #expect(await harness.press("Settings"))
        #expect(harness.panes.panes == [.accessibility])
    }

    @Test("Accessibility granted in System Settings is noticed on the way back too")
    func accessibilityGrantedWhileAway() async {
        let harness = Harness(microphone: .granted, accessibility: .denied)
        await harness.flow.start()
        #expect(harness.step == .accessibility)

        await harness.accessibility.setStatus(.granted)
        await harness.flow.refresh()
        #expect(harness.detail == .permission(.granted))
        #expect(await harness.press("Continue"))
        #expect(harness.detail == .finishing(.ready))
    }

    @Test("Accessibility cannot be walked past")
    func accessibilityCannotBeSkipped() async {
        let harness = Harness(microphone: .granted, accessibility: .denied)
        await harness.flow.start()
        #expect(harness.step == .accessibility)

        #expect(!(await harness.press("Skip")))
        #expect(!(await harness.press("Not now")))
        #expect(!(await harness.press("Continue")))
        await harness.flow.perform(.advance)
        #expect(harness.step == .accessibility)

        await harness.accessibility.setStatus(.granted)
        await harness.flow.refresh()
        #expect(await harness.press("Continue"))
        #expect(harness.step == .ready)
    }

    @Test("the microphone cannot be walked past either")
    func microphoneCannotBeSkipped() async {
        let harness = Harness(microphone: .notDetermined, microphoneAfterAsking: .denied)
        await harness.flow.start()

        for detail in [OnboardingDetail.permission(.notDetermined), .permission(.denied)] {
            #expect(!harness.page.buttons.contains { $0.intent == .advance }, "\(detail)")
            await harness.flow.perform(.advance)
            #expect(harness.step == .microphone)
            _ = await harness.press("Allow")
        }
    }

    // MARK: Never claiming something it has not just read

    @Test("re-reads the permissions on the last page rather than trusting the clicks")
    func lastPageRereadsEverything() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()
        #expect(harness.detail == .finishing(.ready))

        // The user turns the microphone off again with the last page still open.
        await harness.microphone.setStatus(.denied)
        await harness.flow.refresh()
        #expect(harness.detail == .finishing(.needsMicrophone))
        #expect(harness.buttonTitles == ["Settings", "Close"])
        #expect(await harness.press("Close"))
        #expect(harness.finishedWith == .needsMicrophone)
    }

    // MARK: The download

    @Test("draws the download as it goes, and waits for Continue when it lands")
    func downloadRunsToTheEnd() async {
        let installer = GatedInstaller()
        let harness = Harness(
            microphone: .granted, accessibility: .granted, installer: installer)

        let running = Task { await harness.flow.start() }
        await settle(until: { installer.startedDownloads == 1 })
        #expect(harness.step == .setup)
        #expect(harness.detail == .installing(0))
        #expect(harness.page.buttons.contains { $0.title == "Continue" && !$0.isEnabled })
        #expect(await harness.press("Continue") == false)
        await harness.flow.perform(.advance)
        #expect(harness.step == .setup, "a stray advance left a download running")

        // Nothing on this page waits on another application, so coming back must not disturb the download.
        await harness.flow.refresh()
        #expect(harness.detail == .installing(0))

        installer.send(.report(0.4))
        await settle(until: { harness.detail == .installing(0.4) })
        #expect(harness.page.picture == .download(0.4, .running))

        installer.send(.succeed)
        await running.value
        #expect(harness.detail == .installed)
        #expect(await harness.press("Continue"))
        #expect(harness.detail == .finishing(.ready))
    }

    @Test("a download that gives out says so where it stopped, and can only be started again")
    func downloadFailsAndIsRetried() async {
        let installer = GatedInstaller()
        let harness = Harness(
            microphone: .granted, accessibility: .granted, installer: installer)

        let running = Task { await harness.flow.start() }
        await settle(until: { installer.startedDownloads == 1 })
        installer.send(.report(0.3))
        await settle(until: { harness.detail == .installing(0.3) })
        installer.send(.fail(downloadFailure))
        await running.value

        #expect(harness.step == .setup)
        #expect(harness.detail == .installFailed(downloadFailure.userMessage, reached: 0.3))
        #expect(harness.buttonTitles == ["Try again"])

        let retrying = Task { _ = await harness.press("Try again") }
        await settle(until: { installer.startedDownloads == 2 })
        #expect(harness.detail == .installing(0))
        installer.send(.succeed)
        await retrying.value
        #expect(harness.detail == .installed)
    }

    @Test("a cancelled download stops where it was and cannot come back to redraw the page")
    func cancellingADownloadIsFinal() async {
        let installer = GatedInstaller()
        let harness = Harness(
            microphone: .granted, accessibility: .granted, installer: installer)

        let running = Task { await harness.flow.start() }
        await settle(until: { installer.startedDownloads == 1 })
        installer.send(.report(0.4))
        await settle(until: { harness.detail == .installing(0.4) })

        #expect(await harness.press("Cancel"))
        #expect(harness.step == .setup, "Cancel walked past a mandatory download")
        guard case .installFailed(_, let reached) = harness.detail else {
            Issue.record("cancelling drew \(harness.detail)")
            return
        }
        #expect(reached == 0.4)

        installer.send(.report(0.9))
        await running.value
        #expect(!harness.published.contains { $0.detail == .installing(0.9) })
        #expect(harness.buttonTitles == ["Try again"])
    }

    @Test("a sign-out on the download page goes back to sign-in, and the download stops drawing")
    func signingOutReturnsToSignIn() async {
        let installer = GatedInstaller()
        let harness = Harness(microphone: .granted, accessibility: .granted, installer: installer)
        let running = Task { await harness.flow.start() }
        await settle(until: { installer.startedDownloads == 1 })
        installer.send(.report(0.4))
        await settle(until: { harness.detail == .installing(0.4) })

        harness.profiles.clear()
        await harness.flow.signedOut()
        #expect(harness.step == .signIn)
        #expect(harness.detail == .signIn(.offering))

        installer.send(.report(0.8))
        installer.send(.succeed)
        await running.value
        #expect(harness.step == .signIn, "the download dragged a signed-out user back to setup")
        #expect(!harness.published.contains { $0.detail == .installing(0.8) })
    }

    @Test("a sign-out on a permission page goes back to sign-in")
    func signingOutFromAPermissionPage() async {
        let harness = Harness(microphone: .notDetermined)
        await harness.flow.start()
        #expect(harness.step == .microphone)

        harness.profiles.clear()
        await harness.flow.signedOut()
        #expect(harness.step == .signIn)
        #expect(!harness.liveProviders.isEmpty)
    }

    @Test("Cancel means nothing away from the download page")
    func cancelInstallIsIgnoredElsewhere() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()
        await harness.flow.perform(.cancelInstall)
        #expect(harness.detail == .finishing(.ready))
    }

    @Test("the last page can send the user back to a download that is missing")
    func lastPageOffersTheDownloadAgain() async {
        let installer = GatedInstaller(isInstalled: true)
        let harness = Harness(
            microphone: .granted, accessibility: .granted, installer: installer)
        await harness.flow.start()
        installer.remove()
        await harness.flow.refresh()
        #expect(harness.detail == .finishing(.needsSpeechModel))
        #expect(harness.buttonTitles == ["Download", "Close"])

        let again = Task { _ = await harness.press("Download") }
        await settle(until: { installer.startedDownloads == 1 })
        installer.send(.succeed)
        await again.value
        #expect(harness.detail == .installed)
    }

    @Test("passes over the download when the model is already there")
    func skipsAnInstalledModel() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted,
            installer: InstantInstaller(isInstalled: true))
        await harness.flow.start()

        #expect(!harness.published.contains { $0.step == .setup })
    }

    // MARK: The first try

    @Test("the first try shows listening, then the words, then closes by itself")
    func theFirstTryCloses() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()

        await harness.flow.tried(.listening)
        #expect(harness.detail == .finishing(.ready, trial: .listening))
        #expect(harness.finishedWith == nil)

        await harness.flow.tried(.heard("Hello there."))
        #expect(harness.published.contains { $0.detail == .finishing(.ready, trial: .heard("Hello there.")) })
        #expect(harness.finishedWith == .ready)
        #expect(harness.record.hasFinished)
    }

    @Test("a try that heard nothing goes back to waiting")
    func anEmptyTryWaitsAgain() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()

        await harness.flow.tried(.listening)
        await harness.flow.tried(.heard("  "))
        #expect(harness.detail == .finishing(.ready, trial: .waiting))
        #expect(harness.finishedWith == nil)
    }

    @Test("a dictation refused while the speech model loads shows its detail until the next try")
    func stillLoadingTryShowsDetailAndNextTryWaits() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()

        await harness.flow.tried(.stillLoading)
        #expect(harness.detail == .finishing(.ready, trial: .stillLoading))
        #expect(harness.page.hint == SpeechModelLoad.loading(elapsed: .zero).detail)

        await harness.flow.tried(.listening)
        #expect(harness.detail == .finishing(.ready, trial: .listening))
        #expect(harness.page.hint == nil)
    }

    @Test("a dictation away from the last page, or after the words arrived, changes nothing")
    func triesElsewhereAreIgnored() async {
        let early = Harness(microphone: .notDetermined)
        await early.flow.start()
        await early.flow.tried(.heard("Too soon."))
        #expect(early.step == .microphone)
        #expect(early.finishedWith == nil)

        let gate = Gate()
        let late = Harness(
            microphone: .granted, accessibility: .granted, pause: { _ in await gate.wait() })
        await late.flow.start()
        let closing = Task { await late.flow.tried(.heard("First.")) }
        await settle(until: { gate.arrivals == 1 })
        await late.flow.tried(.heard("Second."))
        await late.flow.tried(.listening)
        #expect(late.detail == .finishing(.ready, trial: .heard("First.")))
        gate.open()
        await closing.value
        #expect(late.finishedWith == .ready)
    }

    @Test("a try is not offered where dictation cannot work")
    func noTryWithoutAMicrophone() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()
        await harness.microphone.setStatus(.denied)
        await harness.flow.refresh()

        await harness.flow.tried(.heard("Nobody heard this."))
        #expect(harness.detail == .finishing(.needsMicrophone))
        #expect(harness.finishedWith == nil)
    }

    @Test("coming back to the window mid-try keeps the try")
    func refreshKeepsTheTry() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()
        await harness.flow.tried(.listening)
        await harness.flow.refresh()
        #expect(harness.detail == .finishing(.ready, trial: .listening))
    }

    @Test("Skip to dashboard closes onboarding")
    func skippingToTheDashboard() async throws {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()
        let skip = try #require(harness.page.action)
        #expect(skip.title == "Skip to dashboard")
        await harness.flow.perform(skip.intent)
        #expect(harness.finishedWith == .ready)
    }

    // MARK: Finishing, and coming back

    @Test("writes down that it is over, and nothing else")
    func finishingIsTheOnlyThingWrittenDown() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        let before = harness.settingsStore.load()
        await harness.flow.start()

        #expect(!harness.record.hasFinished)
        await harness.flow.perform(.finish)
        #expect(harness.record.hasFinished)
        #expect(harness.settingsStore.load() == before)
        #expect(harness.flow.isFinished)
        #expect(harness.finishedWith == .ready)
    }

    /// The last page is somewhere a settled user stands, and a switch they turned off is not onboarding's.
    @Test("leaves a login preference the user has turned off turned off")
    func finishingNeverRevivesOpeningAtLogin() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, settings: Settings(opensAtLogin: false),
            hasFinished: true, signedIn: false)
        await harness.flow.start()
        #expect(await harness.choose(.google))
        await harness.returnFromBrowser()
        #expect(harness.step == .ready)

        await harness.flow.perform(.finish)
        #expect(harness.settingsStore.load().opensAtLogin == false)
    }

    /// Onboarding does not block the app, so Settings can change something while the flow stands there.
    @Test("does not write back the settings it read when it opened")
    func finishingDoesNotRevertAChangeMadeWhileItStood() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, hasFinished: true)
        await harness.flow.start()
        #expect(harness.step == .ready)

        let chosen = HotkeyBinding(keyCode: 36, modifiers: [.command, .shift])
        var elsewhere = harness.settingsStore.load()
        elsewhere.hotkey = chosen
        harness.settingsStore.save(elsewhere)

        await harness.flow.perform(.finish)
        #expect(harness.settingsStore.load().hotkey == chosen)
    }

    /// Reading a snapshot to draw with is fine; drawing one taken minutes ago is not.
    @Test("shows the shortcut the settings hold now, not the one they held when it opened")
    func lastPageFollowsAShortcutChangedWhileItStood() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, hasFinished: true)
        await harness.flow.start()

        var elsewhere = harness.settingsStore.load()
        elsewhere.hotkey = HotkeyBinding(keyCode: 36, modifiers: [.command, .shift])
        elsewhere.hotkeyActivation = .pressToToggle
        harness.settingsStore.save(elsewhere)
        await harness.flow.refresh()

        #expect(keys(of: harness.page) == ["⇧", "⌘", "Return"])
        #expect(harness.page.subtitle?.contains("then press shift, command and Return") == true)
    }

    @Test("a user who has finished is never onboarded again")
    func finishedUsersAreLeftAlone() {
        #expect(Harness(hasFinished: true).flow.isRequired == false)
        #expect(Harness(hasFinished: false).flow.isRequired)
    }

    @Test("quitting halfway remembers nothing, so nothing already granted is asked twice")
    func quittingHalfwayAsksOnlyWhatIsStillOutstanding() async {
        let first = Harness(
            microphone: .notDetermined, microphoneAfterAsking: .granted, accessibility: .denied)
        await first.flow.start()
        #expect(await first.press("Allow"))
        #expect(await first.press("Continue"))
        #expect(first.step == .accessibility)
        #expect(!first.record.hasFinished)

        let second = Harness(microphone: .granted, accessibility: .denied)
        #expect(second.flow.isRequired)
        await second.flow.start()
        #expect(second.step == .accessibility)
    }

    // MARK: Odds and ends

    @Test("leaves the download page alone when the window comes back")
    func refreshingAPageThatWaitsOnNothing() async {
        let installer = GatedInstaller()
        let harness = Harness(microphone: .granted, accessibility: .granted, installer: installer)
        let running = Task { await harness.flow.start() }
        await settle(until: { installer.startedDownloads == 1 })
        let published = harness.published.count

        await harness.flow.refresh()
        #expect(harness.step == .setup)
        #expect(harness.published.count == published)
        installer.send(.succeed)
        await running.value
    }

    @Test("ignores a recovery that belongs to some other part of the app")
    func recoveriesItDoesNotOffer() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()
        let before = harness.flow.state

        await harness.flow.perform(.recover(.pasteManually))
        #expect(harness.flow.state == before)
    }

    @Test("ignores instructions that could only have come from a page the user has left")
    func intentsBelongingToOtherPages() async {
        let harness = Harness(microphone: .notDetermined)
        await harness.flow.start()
        #expect(harness.step == .microphone)

        for stray: OnboardingIntent in [.cancelSignIn, .reopenBrowser, .cancelInstall] {
            await harness.flow.perform(stray)
            #expect(harness.step == .microphone, "\(stray) dragged the user off the page")
        }
    }

    @Test("cannot be closed from a page that has not worked out what it is promising")
    func onlyTheLastPageCanClose() async {
        let harness = Harness(microphone: .notDetermined)
        await harness.flow.start()

        await harness.flow.perform(.finish)
        #expect(!harness.flow.isFinished)
        #expect(!harness.record.hasFinished)
        #expect(harness.finishedWith == nil)
    }

    @Test("shows the shortcut the settings actually hold, not the one it shipped with")
    func lastPageShowsTheChosenShortcut() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted,
            settings: Settings(
                shortcuts: ShortcutSet([
                    .dictate: [HotkeyBinding(keyCode: 36, modifiers: [.command, .shift])]
                ])))
        await harness.flow.start()

        #expect(keys(of: harness.page) == ["⇧", "⌘", "Return"])
    }
}
