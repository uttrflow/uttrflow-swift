import Testing

@testable import UttrflowCore
@testable import UttrflowSettings
@testable import UttrflowUX

/// The wording of the download failure the tests script, taken from the error itself so
/// that a reworded message is not a failing test.
private let downloadFailure = SpeechEngineError.modelDownloadFailed(description: "offline")

@MainActor
@Suite("Onboarding flow")
struct OnboardingFlowTests {

    // MARK: Getting under way

    @Test("opens on the welcome page, with a dot for every page there will be")
    func opensOnWelcome() async {
        // Signed in already, which is what makes welcome the first page anybody sees.
        let harness = Harness()
        await harness.flow.start()

        #expect(harness.step == .welcome)
        #expect(harness.detail == .reading)
        #expect(harness.page.position == OnboardingStep.welcome.position)
        #expect(harness.page.stepCount == OnboardingStep.allCases.count)
        #expect(harness.buttonTitles == ["Continue"])
    }

    /// What the Account page's Sign In button reaches. Somebody who has used Uttrflow for
    /// a month and signed out does not need telling what it is.
    @Test("resuming opens on sign-in rather than on the pitch")
    func resumeSkipsWelcome() async {
        let harness = Harness(microphone: .granted, accessibility: .granted, signedIn: false)
        await harness.flow.resume()

        #expect(harness.step == .signIn)
        #expect(!harness.published.contains { $0.step == .welcome })
    }

    /// Signing back in and finding the app still mute would be a worse outcome than
    /// being shown one extra page.
    @Test("resuming still walks everything after the pitch, not only sign-in")
    func resumeStillAsksForPermissions() async {
        let harness = Harness(microphone: .notDetermined, accessibility: .granted, signedIn: true)
        await harness.flow.resume()

        #expect(harness.step == .microphone)
    }

    @Test("asks for the microphone before anything else")
    func microphoneComesFirst() async {
        let harness = Harness(microphone: .notDetermined)
        await harness.flow.start()

        #expect(await harness.press("Continue"))
        #expect(harness.step == .microphone)
        #expect(harness.detail == .permission(.notDetermined))
        #expect(harness.buttonTitles == ["Allow Microphone Access"])
    }

    // MARK: A permission that is already granted

    @Test("passes over a permission macOS has already granted rather than agreeing with itself")
    func skipsGrantedPermissions() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()

        #expect(await harness.press("Continue"))
        #expect(harness.step == .ready)
        #expect(harness.detail == .finishing(.ready))
        #expect(!harness.published.contains { $0.step == .microphone })
        #expect(!harness.published.contains { $0.step == .accessibility })
    }

    @Test("moves on the moment the prompt is answered yes")
    func grantingAtThePromptMovesOn() async {
        let harness = Harness(
            microphone: .notDetermined, microphoneAfterAsking: .granted, accessibility: .granted)
        await harness.flow.start()
        #expect(await harness.press("Continue"))

        #expect(await harness.press("Allow Microphone Access"))
        #expect(harness.step == .ready)
        #expect(harness.detail == .finishing(.ready))
    }

    // MARK: A permission that is refused

    @Test("a no at the prompt turns the page into the way back, not a repeat of the prompt")
    func refusingAtThePromptOffersSystemSettings() async {
        let harness = Harness(microphone: .notDetermined, microphoneAfterAsking: .denied)
        await harness.flow.start()
        #expect(await harness.press("Continue"))

        #expect(await harness.press("Allow Microphone Access"))
        #expect(harness.step == .microphone)
        #expect(harness.detail == .permission(.denied))
        #expect(harness.buttonTitles == ["Open System Settings"])
        #expect(harness.page.note != nil)
    }

    @Test("granted in System Settings, and the user comes back")
    func grantedWhileAway() async {
        let harness = Harness(microphone: .notDetermined, microphoneAfterAsking: .denied)
        await harness.flow.start()
        #expect(await harness.press("Continue"))
        #expect(await harness.press("Allow Microphone Access"))

        #expect(await harness.press("Open System Settings"))
        #expect(harness.panes.panes == [.microphone])
        #expect(harness.detail == .awaitingSystemSettings)
        #expect(harness.buttonTitles == ["Open System Settings", "Check Again"])

        await harness.microphone.setStatus(.granted)
        await harness.flow.refresh()
        #expect(harness.step != .microphone)
    }

    /// The microphone is not optional, so coming back without it does not offer a way
    /// on — but it must not offer a loop either. The page says the same thing however
    /// many times it is asked, and both of its answers still do something.
    @Test("still refused on the way back: no loop, and no way past it either")
    func stillRefusedOnReturn() async {
        let harness = Harness(microphone: .notDetermined, microphoneAfterAsking: .denied)
        await harness.flow.start()
        #expect(await harness.press("Continue"))
        #expect(await harness.press("Allow Microphone Access"))
        #expect(await harness.press("Open System Settings"))

        await harness.flow.refresh()
        #expect(harness.detail == .awaitingSystemSettings)
        #expect(await harness.press("Check Again"))
        #expect(harness.step == .microphone)
        #expect(harness.detail == .awaitingSystemSettings)
        #expect(harness.buttonTitles == ["Open System Settings", "Check Again"])

        // The pane is still reachable for somebody who closed the wrong window, and
        // going there does not move them off the step.
        #expect(await harness.press("Open System Settings"))
        #expect(harness.step == .microphone)
        #expect(harness.panes.panes == [.microphone, .microphone])
    }

    @Test("a permission taken away by policy while the user was out offers what is left")
    func blockedWhileAway() async {
        let harness = Harness(microphone: .notDetermined, microphoneAfterAsking: .denied)
        await harness.flow.start()
        #expect(await harness.press("Continue"))
        #expect(await harness.press("Allow Microphone Access"))
        #expect(await harness.press("Open System Settings"))

        await harness.microphone.setStatus(.restricted)
        await harness.flow.refresh()
        #expect(harness.detail == .permission(.restricted))
        #expect(harness.buttonTitles == ["Continue Without It"])
    }

    @Test("a permission blocked by policy never pretends it can be asked for")
    func restrictedFromTheStart() async {
        let harness = Harness(microphone: .restricted, microphoneAfterAsking: nil)
        await harness.flow.start()

        #expect(await harness.press("Continue"))
        #expect(harness.detail == .permission(.restricted))
        #expect(harness.buttonTitles == ["Continue Without It"])
        #expect(harness.page.subtitle.contains("policy"))
    }

    // MARK: Accessibility, which is the one it is reasonable to do without

    @Test("offers to ask for Accessibility when macOS has not been asked yet")
    func accessibilityCanBeAskedFor() async {
        let harness = Harness(
            microphone: .granted, accessibility: .notDetermined,
            accessibilityAfterAsking: .granted)
        await harness.flow.start()

        #expect(await harness.press("Continue"))
        #expect(harness.step == .accessibility)
        #expect(harness.buttonTitles == ["Allow Accessibility Access"])
        #expect(await harness.press("Allow Accessibility Access"))
        #expect(harness.detail == .finishing(.ready))
    }

    @Test("sends the user to the Accessibility pane once macOS has already been told no")
    func accessibilityGoesToItsOwnPane() async {
        let harness = Harness(microphone: .granted, accessibility: .denied)
        await harness.flow.start()
        #expect(await harness.press("Continue"))

        #expect(harness.step == .accessibility)
        #expect(await harness.press("Open System Settings"))
        #expect(harness.panes.panes == [.accessibility])
    }

    @Test("Accessibility granted in System Settings is noticed on the way back too")
    func accessibilityGrantedWhileAway() async {
        let harness = Harness(microphone: .granted, accessibility: .denied)
        await harness.flow.start()
        #expect(await harness.press("Continue"))
        #expect(harness.step == .accessibility)

        await harness.accessibility.setStatus(.granted)
        await harness.flow.refresh()
        #expect(harness.step == .ready)
        #expect(harness.detail == .finishing(.ready))
    }

    /// Accessibility used to be skippable, and the last page had to say what skipping
    /// had cost. It cannot be skipped now, so the rule to hold is the stronger one:
    /// there is nothing on the page that ends the step without the permission.
    @Test("Accessibility cannot be walked past")
    func accessibilityCannotBeSkipped() async {
        let harness = Harness(microphone: .granted, accessibility: .denied)
        await harness.flow.start()
        #expect(await harness.press("Continue"))
        #expect(harness.step == .accessibility)

        #expect(!(await harness.press("Skip")))
        #expect(!(await harness.press("Not now")))
        #expect(!(await harness.press("Continue")))
        #expect(harness.step == .accessibility)

        // Granting it is the only thing that moves, and it does.
        await harness.accessibility.setStatus(.granted)
        await harness.flow.refresh()
        #expect(harness.step == .ready)
        #expect(harness.detail == .finishing(.ready))
    }

    // MARK: Never claiming something it has not just read

    @Test("re-reads the permissions on the last page rather than trusting the clicks")
    func lastPageRereadsEverything() async {
        let harness = Harness(
            microphone: .notDetermined, microphoneAfterAsking: .granted, accessibility: .granted)
        await harness.flow.start()
        #expect(await harness.press("Continue"))
        #expect(await harness.press("Allow Microphone Access"))
        #expect(harness.detail == .finishing(.ready))

        // The user turns the microphone off again with the last page still open.
        await harness.microphone.setStatus(.denied)
        await harness.flow.refresh()
        #expect(harness.detail == .finishing(.needsMicrophone))
        #expect(harness.buttonTitles == ["Open System Settings", "Close"])
    }

    // MARK: The download

    @Test("draws the download as it goes, and moves on when it lands")
    func downloadRunsToTheEnd() async {
        let installer = GatedInstaller()
        let harness = Harness(
            microphone: .granted, accessibility: .granted, installer: installer)
        await harness.flow.start()

        let running = Task { await harness.flow.perform(.advance) }
        await settle(until: { installer.startedDownloads == 1 })
        #expect(harness.step == .setup)
        #expect(harness.detail == .installing(0))
        #expect(harness.page.buttons.contains { $0.title == "Continue" && !$0.isEnabled })
        #expect(await harness.press("Continue") == false)

        // Nothing on this page is waiting on another application, so coming back to
        // the window must not disturb the download.
        await harness.flow.refresh()
        #expect(harness.detail == .installing(0))

        installer.send(.report(0.4))
        await settle(until: { harness.detail == .installing(0.4) })
        #expect(harness.page.progress == 0.4)

        installer.send(.succeed)
        await running.value
        #expect(harness.step == .ready)
        #expect(harness.detail == .finishing(.ready))
    }

    @Test("a download that gives out says so, and can be started again")
    func downloadFailsAndIsRetried() async {
        let installer = GatedInstaller()
        let harness = Harness(
            microphone: .granted, accessibility: .granted, installer: installer)
        await harness.flow.start()

        let running = Task { await harness.flow.perform(.advance) }
        await settle(until: { installer.startedDownloads == 1 })
        installer.send(.fail(downloadFailure))
        await running.value

        #expect(harness.step == .setup)
        #expect(harness.detail == .installFailed(downloadFailure.userMessage))
        #expect(harness.buttonTitles == ["Not now", "Try Again"])

        let retrying = Task { _ = await harness.press("Try Again") }
        await settle(until: { installer.startedDownloads == 2 })
        installer.send(.succeed)
        await retrying.value
        #expect(harness.detail == .finishing(.ready))
    }

    @Test("a download the user gave up on cannot come back and redraw the page")
    func cancellingADownloadIsFinal() async {
        let installer = GatedInstaller()
        let harness = Harness(
            microphone: .granted, accessibility: .granted, installer: installer)
        await harness.flow.start()

        let running = Task { await harness.flow.perform(.advance) }
        await settle(until: { installer.startedDownloads == 1 })
        installer.send(.report(0.4))
        await settle(until: { harness.detail == .installing(0.4) })

        #expect(await harness.press("Cancel"))
        #expect(harness.step == .ready)
        #expect(harness.detail == .finishing(.needsSpeechModel))

        installer.send(.report(0.9))
        await running.value
        #expect(harness.detail == .finishing(.needsSpeechModel))
        #expect(!harness.published.contains { $0.detail == .installing(0.9) })
    }

    @Test("the last page can send the user back to a download they gave up on")
    func lastPageOffersTheDownloadAgain() async {
        let installer = GatedInstaller()
        let harness = Harness(
            microphone: .granted, accessibility: .granted, installer: installer)
        await harness.flow.start()

        let running = Task { await harness.flow.perform(.advance) }
        await settle(until: { installer.startedDownloads == 1 })
        await harness.flow.perform(.cancelInstall)
        await running.value
        #expect(harness.detail == .finishing(.needsSpeechModel))
        #expect(harness.buttonTitles == ["Download Now", "Start Using Uttrflow"])

        let again = Task { _ = await harness.press("Download Now") }
        await settle(until: { installer.startedDownloads == 2 })
        installer.send(.succeed)
        await again.value
        #expect(harness.detail == .finishing(.ready))
    }

    @Test("passes over the download when the model is already there")
    func skipsAnInstalledModel() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted,
            installer: InstantInstaller(isInstalled: true))
        await harness.flow.start()

        #expect(await harness.press("Continue"))
        #expect(!harness.published.contains { $0.step == .setup })
    }

    // MARK: Finishing, and coming back

    @Test("writes down that it is over, and nothing else")
    func finishingIsTheOnlyThingWrittenDown() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
        let before = harness.settingsStore.load()
        await harness.flow.start()
        #expect(await harness.press("Continue"))

        #expect(!harness.record.hasFinished)
        #expect(await harness.press("Start Using Uttrflow"))
        #expect(harness.record.hasFinished)
        #expect(harness.settingsStore.load() == before)
        #expect(harness.flow.isFinished)
        #expect(harness.finishedWith == .ready)
    }

    /// Sequence A. The Account page's Sign In reaches the whole flow, so the last page
    /// is now somewhere a settled user stands — and the switch they turned off months
    /// ago is not onboarding's to turn back on.
    @Test("leaves a login preference the user has turned off turned off")
    func finishingNeverRevivesOpeningAtLogin() async {
        // Somebody who turned the switch off in Settings, then signed out, then pressed
        // Sign In on the Account page and walked the flow to the end.
        let harness = Harness(
            microphone: .granted, accessibility: .granted, settings: Settings(opensAtLogin: false),
            hasFinished: true, signedIn: false)
        await harness.flow.resume()
        #expect(await harness.choose(.google))
        await harness.returnFromBrowser()
        #expect(harness.step == .ready)

        #expect(await harness.press("Start Using Uttrflow"))
        #expect(harness.settingsStore.load().opensAtLogin == false)
    }

    /// Sequence B, and the one that matters: onboarding does not block the app, so the
    /// Settings window can be opened over it and change something while it stands there.
    /// A flow that saved the settings it read when it was built would put that back.
    @Test("does not write back the settings it read when it opened")
    func finishingDoesNotRevertAChangeMadeWhileItStood() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, hasFinished: true)
        await harness.flow.resume()
        #expect(harness.step == .ready)

        // The Settings window, over the top of the open flow, changes the shortcut.
        let chosen = HotkeyBinding(keyCode: 36, modifiers: [.command, .shift])
        var elsewhere = harness.settingsStore.load()
        elsewhere.hotkey = chosen
        harness.settingsStore.save(elsewhere)

        #expect(await harness.press("Start Using Uttrflow"))
        #expect(harness.settingsStore.load().hotkey == chosen)
    }

    /// Reading a snapshot to draw with is fine; the flow simply must not be drawing one
    /// it took minutes ago either.
    @Test("shows the shortcut the settings hold now, not the one they held when it opened")
    func lastPageFollowsAShortcutChangedWhileItStood() async {
        let harness = Harness(
            microphone: .granted, accessibility: .granted, hasFinished: true)
        await harness.flow.resume()

        var elsewhere = harness.settingsStore.load()
        elsewhere.hotkey = HotkeyBinding(keyCode: 36, modifiers: [.command, .shift])
        harness.settingsStore.save(elsewhere)
        await harness.flow.refresh()

        #expect(harness.page.keys == ["⇧", "⌘", "Return"])
    }

    @Test("a user who has finished is never onboarded again")
    func finishedUsersAreLeftAlone() {
        #expect(Harness(hasFinished: true).flow.isRequired == false)
        #expect(Harness(hasFinished: false).flow.isRequired)
    }

    @Test("quitting halfway remembers nothing, so nothing already granted is asked twice")
    func quittingHalfwayAsksOnlyWhatIsStillOutstanding() async {
        // First run: the microphone is granted, and the user quits on the next page.
        let first = Harness(
            microphone: .notDetermined, microphoneAfterAsking: .granted, accessibility: .denied)
        await first.flow.start()
        #expect(await first.press("Continue"))
        #expect(await first.press("Allow Microphone Access"))
        #expect(first.step == .accessibility)
        #expect(!first.record.hasFinished)

        // Second run, with the microphone still granted. Onboarding starts from the
        // beginning, because nothing about where the user got to was worth keeping,
        // but the question macOS has already answered is not put again.
        let second = Harness(microphone: .granted, accessibility: .denied)
        #expect(second.flow.isRequired)
        await second.flow.start()
        #expect(second.step == .welcome)
        #expect(await second.press("Continue"))
        #expect(second.step == .accessibility)
    }

    // MARK: Odds and ends

    @Test("leaves the pages that are waiting on nobody alone")
    func refreshingAPageThatWaitsOnNothing() async {
        let harness = Harness()
        await harness.flow.start()
        let published = harness.published.count

        await harness.flow.refresh()
        #expect(harness.step == .welcome)
        #expect(harness.published.count == published)
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
        let harness = Harness(microphone: .granted, accessibility: .granted)
        await harness.flow.start()
        #expect(harness.step == .welcome)

        for stray: OnboardingIntent in [.cancelSignIn] {
            await harness.flow.perform(stray)
            #expect(harness.step == .welcome, "\(stray) dragged the user off the page")
        }
    }

    @Test("cannot be closed from a page that has not worked out what it is promising")
    func onlyTheLastPageCanClose() async {
        let harness = Harness(microphone: .granted, accessibility: .granted)
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
            settings: Settings(hotkey: HotkeyBinding(keyCode: 36, modifiers: [.command, .shift])))
        await harness.flow.start()

        #expect(await harness.press("Continue"))
        #expect(harness.page.keys == ["⇧", "⌘", "Return"])
    }
}
