import Testing

@testable import UttrflowAccount
@testable import UttrflowCore
@testable import UttrflowSettings
@testable import UttrflowUX

/// Every page the flow can ask for, including the combinations no run reaches, so that
/// a page cannot be added without also meeting the rules below.
private let everyState: [OnboardingState] = [
    OnboardingState(step: .signIn, detail: .signIn(.offering)),
    OnboardingState(step: .signIn, detail: .signIn(.unreachable)),
    OnboardingState(step: .signIn, detail: .signIn(.signingIn(.google))),
    OnboardingState(step: .signIn, detail: .signIn(.signingIn(.gitHub))),
    OnboardingState(step: .signIn, detail: .signIn(.signingIn(.apple))),
    OnboardingState(step: .signIn, detail: .signIn(.refused("Nobody answered."))),
    OnboardingState(step: .signIn, detail: .reading),
    OnboardingState(step: .welcome, detail: .reading),
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
    OnboardingState(step: .setup, detail: .installFailed("It stopped.")),
    OnboardingState(step: .setup, detail: .reading),
    OnboardingState(step: .ready, detail: .finishing(.ready)),
    OnboardingState(step: .ready, detail: .finishing(.pastesManually)),
    OnboardingState(step: .ready, detail: .finishing(.needsSpeechModel)),
    OnboardingState(step: .ready, detail: .finishing(.needsMicrophone)),
    OnboardingState(step: .ready, detail: .reading),
]

/// Words that would tell the user which engine is doing the work. §16 forbids every one
/// of them anywhere the user can read.
private let forbiddenWords = [
    "whisper", "whisperkit", "mlx", "qwen", "foundation model", "llm", "coreml",
]

private func page(
    _ state: OnboardingState, hotkey: HotkeyBinding = .optionSpace
) -> OnboardingPage {
    OnboardingPresenter.page(for: state, hotkey: hotkey)
}

@Suite("Onboarding pages")
struct OnboardingPresenterTests {

    // MARK: Rules that hold on every page

    @Test("says something, and offers something, on every page it can be asked for")
    func everyPageIsWhole() {
        for state in everyState {
            let page = page(state)
            #expect(!page.title.isEmpty, "\(state) has no title")
            #expect(!page.subtitle.isEmpty, "\(state) has no subtitle")
            #expect(!page.accessibilityLabel.isEmpty, "\(state) has nothing to read aloud")
            #expect(page.hasSomethingToPress, "\(state) offers nothing")
            #expect(page.position == state.step.position)
            #expect(page.stepCount == OnboardingStep.allCases.count)
        }
    }

    @Test("never leaves the user on a page with nothing they can press")
    func noPageIsADeadEnd() {
        for state in everyState {
            let pressable =
                page(state).buttons.filter(\.isEnabled).map(\.title)
                + page(state).providers.filter(\.isEnabled).map(\.title)
            #expect(!pressable.isEmpty, "\(state) is a dead end")
        }
    }

    @Test("puts the provider stack on the sign-in page and nowhere else")
    func onlySignInOffersProviders() {
        for state in everyState {
            let expected = state.step == .signIn ? SignInProvider.offered.count : 0
            #expect(page(state).providers.count == expected, "\(state) draws the wrong providers")
        }
    }

    @Test("only the page a person is agreeing on carries the terms")
    func onlySignInCarriesTheTerms() {
        for state in everyState {
            #expect((page(state).fineprint != nil) == (state.step == .signIn), "\(state)")
        }
    }

    @Test("warns above what it is explaining, and reassures below")
    func onlyAWarningComesFirst() {
        let offline = page(OnboardingState(step: .signIn, detail: .signIn(.unreachable)))
        #expect(offline.note?.tone == .warning)

        let online = page(OnboardingState(step: .signIn, detail: .signIn(.offering)))
        #expect(online.note?.tone == .quiet)
        #expect(online.note?.text.contains("Wi-Fi off") == true)
    }

    /// The three pages that report a failure, and only those three.
    ///
    /// Written out rather than derived, because the point of the case is that a page is
    /// deliberately marked as reporting a failure — a rule that computed the answer from
    /// the state would be the same mistake the emphasis exists to stop.
    private static let failures: [OnboardingState] = [
        OnboardingState(step: .setup, detail: .installFailed("It stopped.")),
        OnboardingState(step: .ready, detail: .finishing(.needsMicrophone)),
        // A permission a device policy has taken away is the same kind of page: it
        // reports something that has gone wrong rather than asking for something.
        OnboardingState(step: .microphone, detail: .permission(.restricted)),
        OnboardingState(step: .accessibility, detail: .permission(.restricted)),
    ]

    @Test("draws the pages that report a failure differently from the ones that ask")
    func failuresAreMarkedAsFailures() {
        for state in Self.failures {
            #expect(page(state).emphasis == .caution, "\(state) is drawn as an ordinary page")
        }
        for state in everyState where !Self.failures.contains(state) {
            #expect(page(state).emphasis != .caution, "\(state) is drawn as a failure")
        }
    }

    @Test("steers towards at most one answer")
    func atMostOneProminentButton() {
        for state in everyState {
            let prominent = page(state).buttons.filter(\.isProminent)
            #expect(prominent.count <= 1, "\(state) steers towards \(prominent.count) answers")
        }
    }

    @Test("never names an engine, a model or a file")
    func neverNamesTheMachinery() {
        for state in everyState {
            let page = page(state)
            let spoken = [page.title, page.subtitle, page.body ?? "", page.note?.text ?? ""]
                .joined(separator: " ")
                .lowercased()
            for word in forbiddenWords {
                #expect(!spoken.contains(word), "\(state) says \(word)")
            }
        }
    }

    @Test("reads aloud as one sentence that says both what the page is and what it wants")
    func voiceOverGetsTheWholePage() {
        for state in everyState {
            let page = page(state)
            #expect(page.accessibilityLabel.contains(page.title))
            #expect(page.accessibilityLabel.contains(page.subtitle))
        }
    }

    // MARK: The pages themselves

    @Test("opens with the mark rather than an icon")
    func welcomeWearsTheMark() {
        let welcome = page(OnboardingState(step: .welcome, detail: .reading))
        #expect(welcome.symbolName == nil)
        #expect(welcome.emphasis == .brand)
        #expect(welcome.buttons.map(\.intent) == [.advance])
    }

    @Test("holds back what skipping the microphone costs until the user has been asked")
    func theMicrophoneCostArrivesWhenItMatters() {
        let unasked = page(
            OnboardingState(step: .microphone, detail: .permission(.notDetermined)))
        #expect(unasked.note == nil)

        let refused = page(OnboardingState(step: .microphone, detail: .permission(.denied)))
        #expect(refused.note?.text == PermissionError.microphoneDenied.userMessage)
        #expect(refused.note?.tone == .warning)
    }

    /// Neither permission can be passed over any more, so neither page argues before it
    /// has been disagreed with — and once it has, it says what is blocked rather than
    /// what skipping would cost, because skipping is no longer on offer.
    @Test("says what is blocked only once the user has met the question")
    func whatIsBlockedIsSaidAfterAsking() {
        for step in [OnboardingStep.microphone, .accessibility] {
            let unasked = page(OnboardingState(step: step, detail: .permission(.notDetermined)))
            #expect(unasked.note == nil, "\(step) argues before it has been asked")

            let refused = page(OnboardingState(step: step, detail: .permission(.denied)))
            #expect(refused.note?.tone == .warning, "\(step) is quiet about being blocked")
        }
    }

    @Test("offers no way past either permission")
    func neitherPermissionCanBeSkipped() {
        for step in [OnboardingStep.microphone, .accessibility] {
            for status in [PermissionStatus.notDetermined, .denied] {
                let page = page(OnboardingState(step: step, detail: .permission(status)))
                #expect(
                    !page.buttons.contains { $0.intent == .advance },
                    "\(step) at \(status) lets the user walk past a requirement")
            }
            let waiting = page(OnboardingState(step: step, detail: .awaitingSystemSettings))
            #expect(!waiting.buttons.contains { $0.intent == .advance })
        }
    }

    /// The one exception, and the reason it is one: a device policy is not a choice the
    /// user made, and a page they cannot satisfy and cannot leave is a trap.
    @Test("lets a policy-blocked Mac through, and only a policy-blocked one")
    func onlyAPolicyLetsSomebodyPast() {
        for step in [OnboardingStep.microphone, .accessibility] {
            let blocked = page(OnboardingState(step: step, detail: .permission(.restricted)))
            #expect(blocked.buttons.map(\.intent) == [.advance])
        }
    }

    @Test("offers the prompt only where macOS would still show one")
    func promptsOnlyWhereAPromptWouldAppear() {
        let unasked = page(
            OnboardingState(step: .microphone, detail: .permission(.notDetermined)))
        #expect(unasked.buttons.last?.intent == .requestPermission(.microphone))

        let refused = page(OnboardingState(step: .microphone, detail: .permission(.denied)))
        #expect(refused.buttons.last?.intent == .recover(.openSystemSettings(.microphone)))

        let blocked = page(OnboardingState(step: .microphone, detail: .permission(.restricted)))
        #expect(blocked.buttons.map(\.intent) == [.advance])
    }

    @Test("sends each permission to its own pane")
    func eachPermissionHasItsOwnPane() {
        let accessibility = page(
            OnboardingState(step: .accessibility, detail: .permission(.denied)))
        #expect(accessibility.buttons.last?.intent == .recover(.openSystemSettings(.accessibility)))
    }

    @Test("keeps Continue in view while the download runs, and keeps it unpressable")
    func theDownloadPageWaits() {
        let downloading = page(OnboardingState(step: .setup, detail: .installing(0.64)))
        #expect(downloading.progress == 0.64)
        #expect(downloading.buttons.map(\.title) == ["Cancel", "Continue"])
        #expect(downloading.buttons.last?.isEnabled == false)
        #expect(downloading.buttons.first?.intent == .cancelInstall)
    }

    @Test("puts the reason a download stopped in front of the user")
    func aStoppedDownloadExplainsItself() {
        let message = SpeechEngineError.modelDownloadFailed(description: "offline").userMessage
        let stopped = page(OnboardingState(step: .setup, detail: .installFailed(message)))
        #expect(stopped.subtitle == message)
        #expect(stopped.progress == nil)
        #expect(stopped.buttons.last?.intent == .recover(.downloadSpeechModel))
    }

    @Test("only the page that is all set says so")
    func onlyOneEndingIsAllSet() {
        let endings: [OnboardingReadiness: String] = [
            .ready: "You’re all set"
        ]
        for readiness in OnboardingReadiness.allCases {
            let ending = page(OnboardingState(step: .ready, detail: .finishing(readiness)))
            if let expected = endings[readiness] {
                #expect(ending.title == expected)
            } else {
                #expect(ending.title != "You’re all set", "\(readiness) claims to be all set")
            }
        }
    }

    @Test("shows the keys to press only on an ending that can be tried")
    func keycapsOnlyWhereTheyWouldWork() {
        for readiness in OnboardingReadiness.allCases {
            let ending = page(OnboardingState(step: .ready, detail: .finishing(readiness)))
            let worksNow = readiness == .ready || readiness == .pastesManually
            #expect(ending.keys.isEmpty != worksNow, "\(readiness) draws the wrong keycaps")
        }
    }

    @Test("offers the way to put right whatever is not right yet")
    func everyEndingThatCanBeFixedOffersTheFix() {
        let fixes: [OnboardingReadiness: OnboardingIntent] = [
            .pastesManually: .recover(.openSystemSettings(.accessibility)),
            .needsSpeechModel: .recover(.downloadSpeechModel),
            .needsMicrophone: .recover(.openSystemSettings(.microphone)),
        ]
        for (readiness, fix) in fixes {
            let ending = page(OnboardingState(step: .ready, detail: .finishing(readiness)))
            #expect(ending.buttons.map(\.intent).contains(fix), "\(readiness) offers no way back")
            #expect(ending.buttons.last?.intent == .finish)
        }
    }

    @Test("never invites the user to start something that cannot start")
    func theWayOutIsWordedHonestly() {
        let cannot = page(OnboardingState(step: .ready, detail: .finishing(.needsMicrophone)))
        #expect(cannot.buttons.last?.title == "Close")

        let can = page(OnboardingState(step: .ready, detail: .finishing(.ready)))
        #expect(can.buttons.last?.title == "Start Using Uttrflow")
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
        let unusual = HotkeyBinding(keyCode: 7, modifiers: [.command])
        #expect(OnboardingKeys.of(unusual) == ["⌘", "Key 7"])
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

    @Test("numbers the dots once each, from one")
    func theDotsAreNumberedOnce() {
        let positions = OnboardingStep.allCases.map(\.position)
        #expect(positions == Array(1...OnboardingStep.count))
    }
}
