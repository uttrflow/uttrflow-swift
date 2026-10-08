// Tests for the onboarding pages: rules that hold on every page, each page's card, keycaps, dots.
import Testing

@testable import UttrflowAccount
@testable import UttrflowCore
@testable import UttrflowSettings
@testable import UttrflowUX

/// Somebody who has just signed in with Google, with microphone access still to ask for.
private let welcome = OnboardingWelcome(
    account: Account(
        identifier: "user-1", displayName: "Alex Doe", emailAddress: "alex@example.com", provider: .google),
    next: .microphone)

/// Every page the flow can ask for, unreachable combinations included, so a new page meets the rules.
private let everyState: [OnboardingState] = [
    OnboardingState(step: .signIn, detail: .signIn(.offering)),
    OnboardingState(step: .signIn, detail: .signIn(.unreachable)),
    OnboardingState(step: .signIn, detail: .signIn(.signingIn(.google))),
    OnboardingState(step: .signIn, detail: .signIn(.signingIn(.gitHub))),
    OnboardingState(step: .signIn, detail: .signIn(.signingIn(.apple))),
    OnboardingState(step: .signIn, detail: .signIn(.enterCode(.google, code: "WDJB-MJHT"))),
    OnboardingState(step: .signIn, detail: .signIn(.refused("Nobody answered."))),
    OnboardingState(step: .signIn, detail: .signIn(.welcomed(welcome))),
    OnboardingState(step: .signIn, detail: .reading),
    OnboardingState(step: .clipboard, detail: .reading),
    OnboardingState(step: .microphone, detail: .permission(.notDetermined)),
    OnboardingState(step: .microphone, detail: .permission(.denied)),
    OnboardingState(step: .microphone, detail: .permission(.restricted)),
    OnboardingState(step: .microphone, detail: .permission(.granted)),
    OnboardingState(step: .microphone, detail: .awaitingSystemSettings),
    OnboardingState(step: .accessibility, detail: .permission(.notDetermined)),
    OnboardingState(step: .accessibility, detail: .permission(.denied)),
    OnboardingState(step: .accessibility, detail: .permission(.restricted)),
    OnboardingState(step: .accessibility, detail: .permission(.granted)),
    OnboardingState(step: .accessibility, detail: .awaitingSystemSettings),
    OnboardingState(step: .setup, detail: .installing(0.5)),
    OnboardingState(step: .setup, detail: .installFailed("It stopped.", reached: 0.4)),
    OnboardingState(step: .setup, detail: .installed),
    OnboardingState(step: .setup, detail: .reading),
    OnboardingState(step: .ready, detail: .finishing(.ready)),
    OnboardingState(step: .ready, detail: .finishing(.ready, trial: .listening)),
    OnboardingState(step: .ready, detail: .finishing(.ready, trial: .heard("Hello there."))),
    OnboardingState(step: .ready, detail: .finishing(.pastesManually)),
    OnboardingState(step: .ready, detail: .finishing(.needsSpeechModel)),
    OnboardingState(step: .ready, detail: .finishing(.needsMicrophone)),
    OnboardingState(step: .ready, detail: .reading),
]

/// Words that would tell the user which engine is doing the work; §16 forbids them anywhere readable.
private let forbiddenWords = [
    "whisper", "whisperkit", "mlx", "qwen", "foundation model", "llm", "coreml",
]

/// The page for a state, with the default shortcut unless given one.
private func page(
    _ state: OnboardingState, hotkey: HotkeyBinding = Settings.default.hotkey,
    activation: HotkeyActivation = .holdToTalk
) -> OnboardingPage {
    OnboardingPresenter.page(for: state, hotkey: hotkey, activation: activation)
}

/// Every intent a page offers, buttons, providers, link and the wide button together.
private func intents(_ page: OnboardingPage) -> [OnboardingIntent] {
    page.providers.filter(\.isEnabled).map { .signIn($0.provider) }
        + page.buttons.filter(\.isEnabled).map(\.intent)
        + [page.link?.intent, page.action?.intent].compactMap(\.self)
}

@Suite("Onboarding pages")
struct OnboardingPresenterTests {

    @Test("shows the rebound Clipboard shortcut in the onboarding hint")
    func clipboardHintFollowsBinding() {
        let binding = HotkeyBinding(keyCode: 0, modifiers: [.option, .command])
        let shortcuts = ShortcutSet([.clipboard: [binding]])
        let state = OnboardingState(step: .ready, detail: .finishing(.ready))

        let page = OnboardingPresenter.page(
            for: state, hotkey: Settings.default.hotkey, shortcuts: shortcuts)
        var menuState = MenuBarState()
        menuState.shortcuts = shortcuts

        #expect(
            page.hint
                == "Open the Clipboard panel with \(SettingsShortcut.compact(binding)) to browse and paste recent copies."
        )
        #expect(page.explanation?.contains(SettingsShortcut.compact(binding)) == true)
        #expect(
            MenuBarPresenter.present(menuState).command(.openClipboard)?.shortcut
                == MenuBarShortcut(key: "a", modifiers: [.option, .command]))
    }

    @Test("offers telemetry opt-in and opt-out side by side during first-run onboarding")
    func usageStatisticsChoice() {
        let state = OnboardingState(step: .signIn, detail: .signIn(.offering))
        let page = OnboardingPresenter.page(for: state, hotkey: Settings.default.hotkey)

        #expect(page.buttons.map(\.title) == ["Keep off", "Share"])
        #expect(page.buttons.map(\.intent) == [.setUsageStatistics(false), .setUsageStatistics(true)])
        #expect(page.buttons.map(\.isSelected) == [true, false])
    }

    // MARK: Rules that hold on every page

    @Test("says something on every page it can be asked for, and numbers it")
    func everyPageIsWhole() {
        for state in everyState {
            let page = page(state)
            #expect(!page.title.isEmpty, "\(state) has no title")
            #expect(!page.accessibilityLabel.isEmpty, "\(state) has nothing to read aloud")
            #expect(page.position == state.step.position)
            #expect(page.stepCount == OnboardingStep.allCases.count)
        }
    }

    /// Once words have arrived the page counts down to the dashboard, and offers it straight away.
    @Test("never leaves the user on a page with nothing they can press")
    func noPageIsADeadEnd() {
        for state in everyState {
            #expect(page(state).hasSomethingToPress, "\(state) is a dead end")
        }
        let closing = page(OnboardingState(step: .ready, detail: .finishing(.ready, trial: .heard("Hi"))))
        #expect(
            closing.action
                == OnboardingAction(
                    title: "Open dashboard", intent: .finish, isProminent: true,
                    countdown: OnboardingPresenter.heardLinger, caption: nil))
        #expect(closing.subtitle == "That’s all there is to it. Opening your dashboard…")
    }

    @Test("puts the providers on the sign-in page, and only where one can be chosen or chosen again")
    func onlySignInOffersProviders() {
        for state in everyState {
            let offers =
                state.step == .signIn
                && [.offering, .refused("Nobody answered.")].contains(state.detail.signIn)
            let expected = offers ? SignInProvider.offered.count : 0
            #expect(page(state).providers.count == expected, "\(state) draws the wrong providers")
        }
    }

    @Test("only the page a person is agreeing on carries the terms")
    func onlySignInCarriesTheTerms() {
        let agreeing = page(OnboardingState(step: .signIn, detail: .signIn(.offering)))
        #expect(agreeing.showsTerms)
        for state in everyState where state.step != .signIn {
            #expect(!page(state).showsTerms, "\(state)")
        }
    }

    @Test("steers towards at most one answer, and points at none but that one")
    func atMostOneProminentButton() {
        for state in everyState {
            let page = page(state)
            let prominentProviders = page.providers.first.map { _ in 1 } ?? 0
            let prominentButtons = page.buttons.filter(\.isProminent).count
            let prominentAction = page.action?.isProminent == true ? 1 : 0
            #expect(
                prominentProviders + prominentButtons + prominentAction <= 1,
                "\(state) steers towards many answers")
            #expect(page.buttons.filter { $0.isPointedAt && !$0.isProminent }.isEmpty, "\(state)")
        }
    }

    @Test("never names an engine, a model or a file")
    func neverNamesTheMachinery() {
        for state in everyState {
            let page = page(state)
            let spoken = [page.title, page.hint ?? "", page.explanation ?? "", page.accessibilityLabel]
                .joined(separator: " ")
                .lowercased()
            for word in forbiddenWords {
                #expect(!spoken.contains(word), "\(state) says \(word)")
            }
        }
    }

    @Test("reads aloud the heading and the sentence behind it")
    func voiceOverGetsTheWholePage() {
        for state in everyState {
            let page = page(state)
            #expect(page.accessibilityLabel.hasPrefix(page.title))
            if let said = page.explanation ?? page.hint {
                #expect(page.accessibilityLabel.contains(said))
            }
        }
    }

    // MARK: Moods

    /// The problem moods, written out because being marked one is deliberate, not computed.
    private static let troubles: [(OnboardingState, OnboardingMood)] = [
        (OnboardingState(step: .signIn, detail: .signIn(.unreachable)), .offline),
        (OnboardingState(step: .signIn, detail: .signIn(.refused("Nobody answered."))), .failure),
        (OnboardingState(step: .setup, detail: .installFailed("It stopped.", reached: 0.4)), .failure),
        (OnboardingState(step: .microphone, detail: .permission(.denied)), .warning),
        (OnboardingState(step: .microphone, detail: .permission(.restricted)), .warning),
        (OnboardingState(step: .accessibility, detail: .permission(.restricted)), .warning),
        (OnboardingState(step: .ready, detail: .finishing(.needsMicrophone)), .warning),
        (OnboardingState(step: .ready, detail: .finishing(.needsSpeechModel)), .warning),
    ]

    @Test("draws the pages that report a problem in their own light, and no others")
    func troublesAreMarked() {
        let problems: Set<OnboardingMood> = [.warning, .failure, .offline]
        for state in everyState {
            if let mood = Self.troubles.first(where: { $0.0 == state })?.1 {
                #expect(page(state).mood == mood, "\(state) is drawn in the wrong light")
            } else {
                #expect(!problems.contains(page(state).mood), "\(state) is drawn as a problem")
            }
        }
    }

    @Test("lights a finished step as done and a step under way as live")
    func doneAndLive() {
        for step in [OnboardingStep.microphone, .accessibility] {
            #expect(page(OnboardingState(step: step, detail: .permission(.granted))).mood == .done)
            #expect(page(OnboardingState(step: step, detail: .awaitingSystemSettings)).mood == .waiting)
        }
        #expect(page(OnboardingState(step: .setup, detail: .installed)).mood == .done)
        #expect(page(OnboardingState(step: .setup, detail: .installing(0.2))).mood == .live)
        #expect(page(OnboardingState(step: .signIn, detail: .signIn(.signingIn(.google)))).mood == .waiting)
    }

    // MARK: Sign-in

    @Test("says what Uttrflow is for on the page that asks who you are")
    func signInCarriesThePitch() {
        let offering = page(OnboardingState(step: .signIn, detail: .signIn(.offering)))
        #expect(offering.title == "Just talk.")
        #expect(offering.picture == .waveform(.talking, badge: nil))
        #expect(offering.explanation?.hasPrefix(OnboardingPresenter.pitch) == true)
        #expect(offering.explanation?.contains("Use a shortcut") == true)
        #expect(offering.explanation?.contains("one key") == false)
        #expect(offering.providers.first?.label == "Google")
        #expect(offering.providers.first?.title == "Continue with Google")
    }

    @Test("offline, offers only to try again")
    func offlineOffersOnlyTryAgain() {
        let offline = page(OnboardingState(step: .signIn, detail: .signIn(.unreachable)))
        #expect(offline.providers.isEmpty)
        #expect(offline.buttons.map(\.intent) == [.recover(.retry)])
        #expect(offline.picture == .waveform(.still, badge: .symbol("wifi.slash", .neutral)))
    }

    @Test("while the browser has the user, offers to open it again or give up")
    func waitingOnTheBrowser() {
        let waiting = page(OnboardingState(step: .signIn, detail: .signIn(.signingIn(.google))))
        #expect(waiting.buttons.map(\.intent) == [.reopenBrowser, .cancelSignIn])
        #expect(waiting.picture == .waveform(.idle, badge: .waitingOn(.google)))

        let code = page(OnboardingState(step: .signIn, detail: .signIn(.enterCode(.google, code: "AB-CD"))))
        #expect(code.picture == .code("AB-CD"))
        #expect(code.buttons.map(\.intent) == [.reopenBrowser, .cancelSignIn])
    }

    @Test("a refusal says why and offers the providers again")
    func aRefusalSaysWhy() {
        let refused = page(OnboardingState(step: .signIn, detail: .signIn(.refused("Nobody answered."))))
        #expect(refused.hint == "Nobody answered.")
        #expect(refused.providers.filter(\.isEnabled).count == refused.providers.count)
        #expect(refused.picture == .waveform(.still, badge: .symbol("xmark", .failure)))
    }

    @Test("offers no way past sign-in without an account")
    func signInIsMandatory() {
        // The welcome is the one sign-in page shown with an account, and Continue is its way on.
        for state in everyState where state.step == .signIn && state.detail != .signIn(.welcomed(welcome)) {
            #expect(!intents(page(state)).contains(.advance), "\(state)")
        }
    }

    // MARK: Permissions

    @Test("offers no way past a permission until it is granted, bar a device policy")
    func permissionsAreMandatory() {
        for step in [OnboardingStep.microphone, .accessibility] {
            for detail in [
                OnboardingDetail.permission(.notDetermined), .permission(.denied), .awaitingSystemSettings,
            ] {
                #expect(!intents(page(OnboardingState(step: step, detail: detail))).contains(.advance))
            }
            for status in [PermissionStatus.granted, .restricted] {
                let page = page(OnboardingState(step: step, detail: .permission(status)))
                #expect(page.buttons.map(\.intent) == [.advance], "\(step) at \(status)")
            }
        }
    }

    @Test("points at Allow on a first visit, and asks macOS")
    func allowIsPointedAt() {
        for step in [OnboardingStep.microphone, .accessibility] {
            let kind: PermissionKind = step == .microphone ? .microphone : .accessibility
            let first = page(OnboardingState(step: step, detail: .permission(.notDetermined)))
            #expect(first.buttons.count == 1)
            #expect(first.buttons.first?.isPointedAt == true)
            #expect(first.buttons.first?.intent == .requestPermission(kind))
        }
    }

    /// `AXIsProcessTrusted` answers false before anyone has been asked, so this page opens at `.denied`.
    @Test("the Accessibility page opens on the ask, since nobody has refused yet")
    func accessibilityIsQuietOnItsFirstVisit() {
        let first = page(OnboardingState(step: .accessibility, detail: .permission(.denied)))
        #expect(first.buttons.first?.intent == .requestPermission(.accessibility))
        #expect(first.picture == .typing(.still, field: .placeholder("Your words go here")))
    }

    @Test("a refused microphone points at System Settings")
    func aRefusedMicrophonePointsAtSettings() {
        let refused = page(OnboardingState(step: .microphone, detail: .permission(.denied)))
        #expect(refused.buttons.map(\.intent) == [.recover(.openSystemSettings(.microphone))])
        #expect(refused.buttons.first?.isPointedAt == true)
        #expect(refused.explanation == PermissionError.microphoneDenied.userMessage)
    }

    @Test("while System Settings is open, offers the pane and a look again, naming where to look")
    func waitingOnSettings() {
        for (step, pane) in [
            (OnboardingStep.microphone, SystemSettingsPane.microphone), (.accessibility, .accessibility),
        ] {
            let waiting = page(OnboardingState(step: step, detail: .awaitingSystemSettings))
            #expect(waiting.buttons.map(\.intent) == [.recover(.openSystemSettings(pane)), .recover(.retry)])
            #expect(waiting.buttons.last?.isProminent == true)
            #expect(waiting.hint?.hasPrefix("Privacy & Security › ") == true)
        }
    }

    @Test("draws the microphone as a waveform and Accessibility as a field being typed into")
    func eachPermissionHasItsPicture() {
        let heard = page(OnboardingState(step: .microphone, detail: .permission(.granted)))
        #expect(heard.picture == .waveform(.talking, badge: nil))
        let typed = page(OnboardingState(step: .accessibility, detail: .permission(.granted)))
        guard case .typing(.talking, .typing) = typed.picture else {
            Issue.record("Accessibility granted draws \(typed.picture)")
            return
        }
        let blocked = page(OnboardingState(step: .microphone, detail: .permission(.restricted)))
        #expect(blocked.picture == .waveform(.still, badge: .symbol("mic.slash", .caution)))
        let waiting = page(OnboardingState(step: .accessibility, detail: .awaitingSystemSettings))
        #expect(waiting.picture == .typing(.idle, field: .placeholder("Waiting for access…")))
        let off = page(OnboardingState(step: .accessibility, detail: .permission(.restricted)))
        #expect(off.picture == .typing(.still, field: .placeholder("Typing is turned off")))
    }

    // MARK: The download

    @Test("keeps Continue in view while the download runs, and keeps it unpressable")
    func theDownloadPageWaits() {
        let downloading = page(OnboardingState(step: .setup, detail: .installing(0.64)))
        #expect(downloading.picture == .download(0.64, .running))
        #expect(downloading.buttons.map(\.title) == ["Cancel", "Continue"])
        #expect(downloading.buttons.last?.isEnabled == false)
        #expect(downloading.buttons.first?.intent == .cancelInstall)
    }

    @Test("puts the reason a download stopped in front of the user, where it stopped, with no way past")
    func aStoppedDownloadExplainsItself() {
        let message = SpeechEngineError.modelDownloadFailed(description: "offline").userMessage
        let stopped = page(OnboardingState(step: .setup, detail: .installFailed(message, reached: 0.38)))
        #expect(stopped.hint == message)
        #expect(stopped.picture == .download(0.38, .stopped))
        #expect(stopped.buttons.map(\.intent) == [.recover(.downloadSpeechModel)])
    }

    @Test("lets the user on once the model is on disk")
    func aFinishedDownloadLetsThrough() {
        for detail in [OnboardingDetail.installed, .reading] {
            let done = page(OnboardingState(step: .setup, detail: detail))
            #expect(done.picture == .download(1, .finished))
            #expect(done.buttons.map(\.intent) == [.advance])
        }
    }

    // MARK: The welcome

    @Test("greets whoever signed in by first name, shows the account, and counts down to the next page")
    func theWelcome() {
        let greeting = page(OnboardingState(step: .signIn, detail: .signIn(.welcomed(welcome))))
        #expect(greeting.title == "You’re in, Alex!")
        #expect(greeting.subtitle == "Welcome to Uttrflow. Let’s get you talking.")
        #expect(greeting.mood == .done)
        #expect(greeting.picture == .welcome(initials: "A", provider: .google))
        #expect(greeting.account == OnboardingAccountChip(provider: .google, text: "alex@example.com"))
        #expect(greeting.providers.isEmpty && greeting.buttons.isEmpty)
        #expect(
            greeting.action
                == OnboardingAction(
                    title: "Continue", intent: .advance, isProminent: true,
                    countdown: OnboardingPresenter.welcomeLinger, caption: "Next: allow the microphone"))
    }

    @Test("still greets an account with no name or address, by the provider")
    func aWelcomeWithoutAName() {
        let bare = OnboardingWelcome(
            account: Account(identifier: "user-2", displayName: "  ", emailAddress: nil, provider: .gitHub),
            next: .ready)
        #expect(bare.firstName == nil && bare.emailAddress == nil && bare.initials == "?")
        let greeting = page(OnboardingState(step: .signIn, detail: .signIn(.welcomed(bare))))
        #expect(greeting.title == "You’re in!")
        #expect(greeting.account == OnboardingAccountChip(provider: .gitHub, text: "GitHub"))
        #expect(greeting.action?.caption == "Next: try your first dictation")

        let byAddress = OnboardingWelcome(
            account: Account(
                identifier: "user-3", displayName: nil, emailAddress: "sam@example.com", provider: .apple),
            next: .setup)
        #expect(byAddress.initials == "S" && byAddress.firstName == nil)

        let lowerCase = OnboardingWelcome(
            account: Account(
                identifier: "user-4", displayName: "sam rivers", emailAddress: nil, provider: .apple),
            next: .setup)
        #expect(lowerCase.firstName == "Sam")
    }

    @Test("names every page the welcome can lead to")
    func whatComesNext() {
        #expect(OnboardingPresenter.nextStep(.microphone) == "allow the microphone")
        #expect(OnboardingPresenter.nextStep(.accessibility) == "let Uttrflow type for you")
        #expect(OnboardingPresenter.nextStep(.setup) == "download the speech model")
        #expect(OnboardingPresenter.nextStep(.ready) == "try your first dictation")
        #expect(OnboardingPresenter.nextStep(.signIn) == "allow the microphone")
    }

    // MARK: The last page

    @Test("asks a new install for a first try with ⌃⌥ lit on the keyboard, and a way straight to the app")
    func theFirstTry() {
        let trying = page(OnboardingState(step: .ready, detail: .finishing(.ready)))
        #expect(trying.title == "Try it now.")
        #expect(
            trying.subtitle
                == "Click a text field in another app, then hold control and option, say anything, then let go."
        )
        #expect(trying.hint == "Open the Clipboard panel with ⇧⌘V to browse and paste recent copies.")
        #expect(trying.accessibilityLabel.contains("Open the Clipboard panel with ⇧⌘V"))
        #expect(
            trying.picture
                == .keyboard(
                    OnboardingKeyboard(
                        lit: [.control, .option], keys: ["⌃", "⌥"], bracket: "HOLD BOTH", isHeld: false,
                        demonstrates: true, field: .placeholder("Your words appear here"), isListening: false,
                        celebrates: false)))
        #expect(
            trying.action
                == OnboardingAction(
                    title: "Skip to dashboard", intent: .finish, isProminent: false, countdown: nil,
                    caption: nil))
        #expect(trying.link == nil)
        #expect(trying.hint == "Open the Clipboard panel with ⇧⌘V to browse and paste recent copies.")

        let pressed = page(
            OnboardingState(step: .ready, detail: .finishing(.ready)), activation: .pressToToggle)
        #expect(
            pressed.subtitle
                == "Click a text field in another app, then press control and option, say anything, then press again."
        )
        guard case .keyboard(let pressedKeys) = pressed.picture else {
            Issue.record("the try draws \(pressed.picture)")
            return
        }
        #expect(pressedKeys.bracket == "PRESS BOTH")

        let earlier = page(
            OnboardingState(step: .ready, detail: .finishing(.ready)), hotkey: Settings.earlierInstall.hotkey)
        #expect(
            earlier.subtitle
                == "Click a text field in another app, then hold option and Space, say anything, then let go."
        )
        guard case .keyboard(let earlierKeys) = earlier.picture else {
            Issue.record("the try draws \(earlier.picture)")
            return
        }
        #expect(
            earlierKeys.lit == nil, "a shortcut with a letter or Space is drawn as keycaps, not on the corner"
        )
    }

    @Test("shows the Settings keycaps for letter, digit and F-key shortcuts on the ready page")
    func readyPageUsesSettingsKeycaps() {
        let ready = OnboardingState(step: .ready, detail: .finishing(.ready))
        let bindings = [
            HotkeyBinding(keyCode: 2, modifiers: [.option]),
            HotkeyBinding(keyCode: 18, modifiers: [.control, .command]),
            HotkeyBinding(keyCode: 96, modifiers: [.option]),
        ]

        for binding in bindings {
            let readyPage = page(ready, hotkey: binding)
            guard case .keyboard(let keyboard) = readyPage.picture else {
                Issue.record("the ready page draws \(readyPage.picture)")
                continue
            }
            #expect(keyboard.keys == SettingsShortcut.keycaps(for: binding))
        }
    }

    @Test("lights only the corner keys a shortcut uses, and gives up on keys the corner lacks")
    func theCornerKeys() {
        #expect(OnboardingKeys.corner(of: .controlOptionHold) == [.control, .option])
        #expect(OnboardingKeys.corner(of: .functionHold) == [.function])
        #expect(OnboardingKeys.corner(of: HotkeyBinding(keyCode: 55, modifiers: [])) == [.command])
        #expect(OnboardingKeys.corner(of: HotkeyBinding(keyCode: 56, modifiers: [.command])) == nil)
        #expect(OnboardingKeys.corner(of: .optionSpace) == nil)
        #expect(OnboardingKeys.spoken(["⌃"]) == "control")
        #expect(OnboardingKeys.spoken(["⌃", "⌥", "⌘"]) == "control, option and command")
        #expect(OnboardingKeys.spoken([]) == "the shortcut")
    }

    @Test("holds the keys down while listening, and shows the words that came back")
    func theTryGoesOn() {
        let listening = page(OnboardingState(step: .ready, detail: .finishing(.ready, trial: .listening)))
        #expect(listening.title == "Listening…")
        #expect(listening.mood == .live)
        #expect(listening.subtitle == "Keep holding while you talk. Let go when you’re done.")
        guard case .keyboard(let held) = listening.picture, held.isHeld, held.isListening else {
            Issue.record("listening draws \(listening.picture)")
            return
        }
        #expect(held.bracket == "HOLDING")
        let toggled = page(
            OnboardingState(step: .ready, detail: .finishing(.ready, trial: .listening)),
            activation: .pressToToggle)
        #expect(toggled.subtitle == "Press again when you’re done.")
        guard case .keyboard(let toggledKeys) = toggled.picture else {
            Issue.record("listening draws \(toggled.picture)")
            return
        }
        #expect(!toggledKeys.isHeld, "a pressed shortcut is not held down while listening")

        let heard = page(
            OnboardingState(step: .ready, detail: .finishing(.ready, trial: .heard("Hi there."))))
        #expect(heard.title == "It works!")
        #expect(heard.mood == .done)
        guard case .keyboard(let landed) = heard.picture else {
            Issue.record("the words draw \(heard.picture)")
            return
        }
        #expect(landed.field == .filled("Hi there."))
        #expect(landed.celebrates)
        #expect(landed.lit == [] && landed.bracket == nil)
    }

    @Test("says that words will be copied when Accessibility is missing")
    func copyingIsSaid() {
        let state = OnboardingState(step: .ready, detail: .finishing(.pastesManually))
        let copying = page(state)
        #expect(copying.hint?.contains("copied") == true)
        #expect(copying.hint?.contains("Clipboard panel with ⇧⌘V") == true)
        #expect(
            copying.subtitle
                == "Click a text field in another app, then hold control and option, say anything, then let go."
        )

        let pressed = page(state, activation: .pressToToggle)
        #expect(
            pressed.subtitle
                == "Click a text field in another app, then press control and option, say anything, then press again."
        )
        #expect(pressed.subtitle?.contains("let go") == false)
    }

    @Test("offers the way to put right an ending that cannot be tried")
    func everyEndingThatCanBeFixedOffersTheFix() {
        let fixes: [OnboardingReadiness: OnboardingIntent] = [
            .needsSpeechModel: .recover(.downloadSpeechModel),
            .needsMicrophone: .recover(.openSystemSettings(.microphone)),
        ]
        for (readiness, fix) in fixes {
            let ending = page(OnboardingState(step: .ready, detail: .finishing(readiness)))
            #expect(ending.buttons.map(\.intent) == [fix, .finish], "\(readiness) offers no way back")
            #expect(ending.buttons.last?.title == "Close")
        }
    }

    // MARK: Keycaps

    @Test("draws a shortcut in the order macOS draws it")
    func modifiersComeInTheSystemsOrder() {
        let everything = HotkeyBinding(
            keyCode: 49, modifiers: [.command, .shift, .option, .control])
        #expect(OnboardingKeys.of(everything) == ["⌃", "⌥", "⇧", "⌘", "Space"])
        #expect(OnboardingKeys.of(.optionSpace) == ["⌥", "Space"])
    }

    @Test("prints a key it cannot name as a code rather than as the wrong letter")
    func anUnnamedKeyIsNotGuessedAt() {
        let unusual = HotkeyBinding(keyCode: 52, modifiers: [.command])
        #expect(OnboardingKeys.of(unusual) == ["⌘", "Key 52"])
    }

    /// Issue 353: a chord of modifiers drew its key as a raw code, and a held Fn as "Key 63".
    @Test("draws a shortcut made of modifiers, or a held Fn, the way Settings does")
    func heldKeysMatchSettings() {
        let chord = HotkeyBinding(keyCode: 58, modifiers: [.option, .command, .control])
        #expect(OnboardingKeys.of(chord) == ["⌃", "⌥", "⌘"])
        #expect(OnboardingKeys.of(.functionHold) == ["fn"])
    }

    @Test("names the keys a shortcut is realistically bound to")
    func theNamedKeys() {
        let named = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape"]
        for (code, name) in named {
            let binding = HotkeyBinding(keyCode: UInt16(code), modifiers: [.option])
            #expect(OnboardingKeys.of(binding).last == name)
        }
    }

    // MARK: The dots

    @Test("numbers the dots once each, from one to six")
    func theDotsAreNumberedOnce() {
        let positions = OnboardingStep.allCases.map(\.position)
        #expect(positions == Array(1...OnboardingStep.count))
        #expect(OnboardingStep.count == 6)
    }

    // MARK: The clipboard

    @Test("says copies are kept, for how long and where, with Keep chosen and Turn off beside it")
    func clipboardPageWhileOn() {
        let state = OnboardingState(step: .clipboard, detail: .reading)
        let page = OnboardingPresenter.page(for: state, hotkey: Settings.default.hotkey)

        #expect(page.title == "Keep what you copy?")
        #expect(page.position == 2)
        #expect(page.buttons.map(\.title) == ["Keep", "Turn off", "Continue"])
        #expect(
            page.buttons.map(\.intent)
                == [.setClipboardEnabled(true), .setClipboardEnabled(false), .advance])
        #expect(page.buttons.map(\.isSelected) == [true, false, false])
        #expect(
            page.hint
                == "Uttrflow keeps what you copy for up to 7 days. It stays on this Mac. Change it in Settings › General."
        )
        let pinned = "Clips you pin, name or put in a collection have no time limit."
        #expect(page.explanation?.contains(pinned) == true)
        #expect(page.explanation?.contains("exclude apps, in Settings › General.") == true)
    }

    @Test("says the stored period, not the default one")
    func clipboardPageNamesTheStoredPeriod() {
        let state = OnboardingState(step: .clipboard, detail: .reading)
        let hotkey = Settings.default.hotkey
        let three = OnboardingPresenter.page(for: state, hotkey: hotkey, clipboardRetentionDays: 3)
        let one = OnboardingPresenter.page(for: state, hotkey: hotkey, clipboardRetentionDays: 1)

        #expect(three.hint?.hasPrefix("Uttrflow keeps what you copy for up to 3 days.") == true)
        #expect(one.hint?.hasPrefix("Uttrflow keeps what you copy for up to 1 day.") == true)
    }

    @Test("turned off, says nothing is kept and where to turn it back on")
    func clipboardPageWhileOff() {
        let state = OnboardingState(step: .clipboard, detail: .reading)
        let page = OnboardingPresenter.page(
            for: state, hotkey: Settings.default.hotkey, clipboardEnabled: false)

        #expect(page.buttons.map(\.isSelected) == [false, true, false])
        #expect(page.hint == "Copies are not kept while this is off. Turn it on in Settings › General.")
        #expect(page.explanation == page.hint)
    }
}
