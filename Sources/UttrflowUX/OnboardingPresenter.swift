internal import UttrflowAccount
public import UttrflowCore

/// Turns where the user is into what the window draws.
///
/// Pure, and deliberately separate from any view, for the same reason the dictation
/// presenter is: the wording of a page, the buttons on it and the sentence VoiceOver
/// reads all have to agree, and one place deciding is what makes that impossible to get
/// wrong. It is also the only place the approved designs are written down, so a page
/// cannot quietly drift away from the one that was signed off.
public enum OnboardingPresenter {
    public static func page(for state: OnboardingState, hotkey: HotkeyBinding) -> OnboardingPage {
        switch state.step {
        case .signIn: signIn(state)
        case .welcome: welcome(state)
        case .microphone: permission(.microphone, state)
        case .accessibility: permission(.accessibility, state)
        case .setup: setup(state)
        case .ready: ready(state, hotkey: hotkey)
        }
    }

    // MARK: Pages

    /// What the whole product costs the user in exchange for the one online step.
    ///
    /// Said on the sign-in page and nowhere else, because this is the only page where a
    /// person is entitled to wonder whether the offline promise is real.
    private static let onlyThisStepNeedsTheInternet = OnboardingNote(
        symbolName: "globe",
        text: """
            This step needs the internet. After it, Uttrflow runs entirely on this Mac — \
            your speech is transcribed here and works with Wi-Fi off.
            """)

    /// The offline banner, drawn above the buttons it is explaining.
    private static let noConnection = OnboardingNote(
        symbolName: "wifi.slash",
        text: """
            No internet connection. Signing in is the one thing Uttrflow cannot do \
            offline. Connect and try again — nothing else is waiting on this.
            """,
        tone: .warning)

    /// The sign-in page, in its four forms.
    ///
    /// There is no way past it and nothing here pretends otherwise: no "continue without
    /// an account", no skip worded as something else. Signing in is required to dictate,
    /// and a page that hinted at a way round a requirement would be lying about the
    /// product to make one screen feel kinder.
    private static func signIn(_ state: OnboardingState) -> OnboardingPage {
        let signIn = state.detail.signIn
        return page(
            state,
            symbolName: nil,
            emphasis: .brand,
            title: "Sign in to Uttrflow",
            subtitle: subtitle(for: signIn),
            note: note(for: signIn),
            code: code(for: signIn),
            providers: SignInProvider.offered.map {
                OnboardingProviderButton(provider: $0, isEnabled: signIn.acceptsAProvider)
            },
            buttons: buttons(for: signIn),
            fineprint: "By continuing you agree to the Terms of Use and the Privacy Policy."
        )
    }

    /// Why this Mac is being asked for a code, said only on the page that shows one.
    ///
    /// Handing the user straight back from the browser is the ordinary way in and the one
    /// this app tries first; the code is what happens when it cannot listen for that
    /// hand-back — over SSH, in a container, or behind security software that will not let
    /// an application open a port. Without this sentence the page reads as a second,
    /// stranger product deciding to be awkward.
    private static let theCodeIsTheFallback = OnboardingNote(
        symbolName: "arrow.uturn.down",
        text: """
            Uttrflow usually hands you straight back from the browser. This Mac would not \
            let it listen for that, so the code does the same job.
            """)

    private static func note(for signIn: OnboardingSignInState) -> OnboardingNote {
        switch signIn {
        case .unreachable: noConnection
        case .enterCode: theCodeIsTheFallback
        default: onlyThisStepNeedsTheInternet
        }
    }

    private static func subtitle(for signIn: OnboardingSignInState) -> String {
        switch signIn {
        case .offering, .unreachable:
            """
            Uttrflow keeps your dictionary, your corrections and your snippets under one \
            account. It needs to know which one is yours.
            """
        case .signingIn(let provider):
            "Finish signing in with \(AccountPagePresenter.title(for: provider)) in your browser."
        // The code is the instruction, so the sentence says what to do with it rather
        // than repeating it. A person reading "enter ABCD-EFGH" while ABCD-EFGH sits
        // underneath has been told the same thing twice and shown it once.
        //
        // It also says the browser is already open, because it is: this state opens the
        // verification page just as the ordinary path opens the provider's. Somebody who
        // is shown a code with no mention of a window that has just appeared in front of
        // them goes looking for one to type it into.
        case .enterCode(let provider, _):
            """
            Your browser is open. Type this code there to finish signing in with \
            \(AccountPagePresenter.title(for: provider)).
            """
        // The provider's own words, which are the only ones that can say what went
        // wrong. The three buttons come back live underneath, because another attempt
        // or another provider is the whole of the remedy.
        case .refused(let message):
            message
        }
    }

    /// The code to read off the screen, on the one page that has one.
    private static func code(for signIn: OnboardingSignInState) -> String? {
        guard case .enterCode(_, let code) = signIn else { return nil }
        return code
    }

    /// The way past this page for somebody who cannot sign in, or will not.
    ///
    /// Plain rather than prominent, and second: an account is what the product wants and
    /// the providers stay the loudest thing on the page. But it is on the page from the
    /// start rather than only after a failure, because a person behind a captive portal
    /// or a proxy that eats OAuth has no way of discovering an escape hatch that only
    /// appears once they have watched something fail.
    private static let workOnThisMac = OnboardingButton.plain(
        "Continue on this Mac", .continueOnThisMac)

    private static func buttons(for signIn: OnboardingSignInState) -> [OnboardingButton] {
        switch signIn {
        // The providers are the controls. A second row of verbs beside three buttons
        // that already say what they do would only be somewhere else to look — with the
        // one exception of the way past the page, which is not something a provider
        // button says.
        case .offering, .refused:
            [workOnThisMac]
        case .unreachable:
            [.prominent("Try Again", .recover(.retry)), workOnThisMac]
        // Waiting on a browser window that may never come back. Giving up has to stay
        // possible or the page is a trap.
        case .signingIn, .enterCode:
            [.plain("Cancel", .cancelSignIn)]
        }
    }

    private static func welcome(_ state: OnboardingState) -> OnboardingPage {
        page(
            state,
            symbolName: nil,
            emphasis: .brand,
            title: "Speak naturally.",
            subtitle: "Get the words you actually meant.",
            body: """
                Hold one key, say what you mean, and Uttrflow writes it into whatever app \
                you’re in — punctuated, tidied, and without the “um”s.
                """,
            buttons: [.prominent("Continue", .advance)]
        )
    }

    /// Both permission pages, from one shape.
    ///
    /// They differ only in their wording, so they are one function rather than two that
    /// could grow apart. Which buttons appear follows the *status*, never the permission:
    /// macOS will only ever prompt for something it has not been asked about, so a denied
    /// permission needs a page that sends the user to the settings pane rather than one
    /// that offers a prompt which will not appear.
    ///
    /// **Neither page can be passed over.** Uttrflow cannot hear without the microphone
    /// and cannot type without Accessibility, and an onboarding that waved either through
    /// delivered somebody to a menu bar icon that does nothing when they hold the key.
    /// The one exception is a permission a device policy has taken off the table: there
    /// is nothing for that user to press, and a page with nothing to press is a trap
    /// rather than a requirement.
    private static func permission(
        _ kind: PermissionKind, _ state: OnboardingState
    ) -> OnboardingPage {
        let wording = PermissionWording.of(kind)
        let isBlocked = state.detail == .permission(.restricted)
        return page(
            state,
            symbolName: wording.symbolName,
            emphasis: isBlocked ? .caution : .neutral,
            title: wording.title,
            subtitle: subtitle(for: state.detail, asking: wording),
            body: wording.body,
            note: note(for: state.detail, asking: wording),
            buttons: buttons(for: state.detail, asking: kind)
        )
    }

    /// What is not possible until this is granted, said once the user has met the
    /// question — and on the page that is waiting on System Settings, where it is the
    /// only thing explaining why they were sent there.
    ///
    /// Not shown before the user has been asked. A page that leads with what will go
    /// wrong is arguing before anybody has disagreed.
    private static func note(
        for detail: OnboardingDetail, asking wording: PermissionWording
    ) -> OnboardingNote? {
        switch detail {
        case .permission(.notDetermined): nil
        default: wording.blocked
        }
    }

    /// Why the wait is worth it, said on every form of the download page.
    private static let staysOnThisMac = OnboardingNote(
        symbolName: "lock",
        text: """
            Once this finishes, dictation runs on this Mac — it keeps working with \
            Wi-Fi off, on a plane, anywhere.
            """)

    private static func setup(_ state: OnboardingState) -> OnboardingPage {
        switch state.detail {
        case .installing(let fraction):
            settingUp(
                state, progress: fraction,
                buttons: [.plain("Cancel", .cancelInstall), .disabled("Continue")])
        case .installFailed(let message):
            page(
                state,
                symbolName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                emphasis: .caution,
                title: "That download stopped",
                subtitle: message,
                note: staysOnThisMac,
                buttons: [
                    .plain("Not now", .advance),
                    .prominent("Try Again", .recover(.downloadSpeechModel)),
                ]
            )
        // The page has nothing left to wait for, which is only reachable by arriving
        // here with the model already on disk. Letting the user past is the only
        // honest thing left to offer.
        default:
            settingUp(state, progress: nil, buttons: [.prominent("Continue", .advance)])
        }
    }

    /// The download page, mid-download or with the model already on disk; only progress and buttons differ.
    private static func settingUp(
        _ state: OnboardingState, progress: Double?, buttons: [OnboardingButton]
    ) -> OnboardingPage {
        page(
            state,
            symbolName: "arrow.down.circle",
            emphasis: .neutral,
            title: "Setting things up",
            subtitle: "A one-time download, then you can start talking.",
            note: staysOnThisMac,
            progress: progress,
            buttons: buttons
        )
    }

    /// The last page, which says what the user actually ended up with.
    ///
    /// Four endings rather than one, because three of them are not "all set" and
    /// saying so anyway would be the first thing Uttrflow ever lied about. Each one that
    /// can still be fixed offers the way to fix it beside the way out.
    private static func ready(_ state: OnboardingState, hotkey: HotkeyBinding) -> OnboardingPage {
        switch state.detail.readiness ?? .ready {
        case .ready:
            page(
                state,
                symbolName: "checkmark",
                emphasis: .success,
                title: "You’re all set",
                subtitle: "Try it right now, in this window or any other.",
                body: """
                    Hold it, talk, let go. Uttrflow lives in your menu bar whenever you \
                    need it.
                    """,
                keys: OnboardingKeys.of(hotkey),
                buttons: [.prominent("Start Using Uttrflow", .finish)]
            )
        case .pastesManually:
            page(
                state,
                symbolName: "doc.on.clipboard",
                emphasis: .neutral,
                title: "You’re set, with one catch",
                subtitle: "Uttrflow will copy your words rather than type them.",
                body: """
                    Hold the shortcut, talk, let go — then paste. Turn on Accessibility \
                    whenever you like and it will start inserting at your cursor instead.
                    """,
                keys: OnboardingKeys.of(hotkey),
                buttons: [
                    .plain("Open System Settings", .recover(.openSystemSettings(.accessibility))),
                    .prominent("Start Using Uttrflow", .finish),
                ]
            )
        case .needsSpeechModel:
            page(
                state,
                symbolName: "arrow.down.circle",
                emphasis: .neutral,
                title: "One thing still to download",
                subtitle: SpeechEngineError.modelNotInstalled.userMessage,
                body: """
                    You can leave it for now. Uttrflow will not be able to recognise \
                    anything until the download has finished.
                    """,
                buttons: [
                    .plain("Download Now", .recover(.downloadSpeechModel)),
                    .prominent("Start Using Uttrflow", .finish),
                ]
            )
        case .needsMicrophone:
            page(
                state,
                symbolName: "mic.slash",
                emphasis: .caution,
                title: "Uttrflow cannot hear you yet",
                subtitle: PermissionError.microphoneDenied.userMessage,
                body: """
                    Nothing will happen when you hold the shortcut until the microphone \
                    is on. Uttrflow stays in your menu bar until you are ready.
                    """,
                buttons: [
                    .plain("Open System Settings", .recover(.openSystemSettings(.microphone))),
                    .prominent("Close", .finish),
                ]
            )
        }
    }

    // MARK: Permission pieces

    private static func subtitle(
        for detail: OnboardingDetail, asking wording: PermissionWording
    ) -> String {
        switch detail {
        case .awaitingSystemSettings:
            "Waiting for you to allow it in System Settings."
        case .permission(.restricted):
            "A device policy blocks this, so it cannot be turned on here."
        default:
            wording.subtitle
        }
    }

    /// One answer on every form of these two pages, and it is always the answer that
    /// grants the permission. There is deliberately no second button: the page is a
    /// requirement, and a quiet way past a requirement is a way of not having one.
    private static func buttons(
        for detail: OnboardingDetail, asking kind: PermissionKind
    ) -> [OnboardingButton] {
        let pane = OnboardingIntent.recover(.openSystemSettings(kind.settingsPane))
        switch detail {
        case .permission(.notDetermined):
            return [.prominent(PermissionWording.of(kind).allow, .requestPermission(kind))]
        case .permission(.denied):
            return [.prominent("Open System Settings", pane)]
        case .awaitingSystemSettings:
            // Still true however many times the user comes back without having changed
            // anything: look again. The settings pane stays reachable beside it, because
            // somebody who closed the wrong window needs a way back to the right one.
            return [.plain("Open System Settings", pane), .prominent("Check Again", .recover(.retry))]
        case .permission(.restricted):
            // A device policy has decided this, and no button on this page can undo it.
            // Going on is the only thing left that is true.
            return [.prominent("Continue Without It", .advance)]
        default:
            // Granted, or somehow no longer asking for anything.
            return [.prominent("Continue", .advance)]
        }
    }

    // MARK: Assembly

    /// Fills in everything a page has in common, so a page above says only what makes
    /// it different from the others.
    private static func page(
        _ state: OnboardingState,
        symbolName: String?,
        emphasis: OnboardingEmphasis,
        title: String,
        subtitle: String,
        body: String? = nil,
        note: OnboardingNote? = nil,
        code: String? = nil,
        keys: [String] = [],
        progress: Double? = nil,
        providers: [OnboardingProviderButton] = [],
        buttons: [OnboardingButton],
        fineprint: String? = nil
    ) -> OnboardingPage {
        OnboardingPage(
            symbolName: symbolName,
            emphasis: emphasis,
            title: title,
            subtitle: subtitle,
            body: body,
            note: note,
            code: code,
            keys: keys,
            progress: progress,
            providers: providers,
            buttons: buttons,
            fineprint: fineprint,
            position: state.step.position,
            stepCount: OnboardingStep.count,
            // Spoken as one sentence: a screen reader announcing a page has to say
            // what it is and what it wants without the user hunting for the second
            // half of it.
            accessibilityLabel: "\(title). \(subtitle)"
        )
    }
}

// MARK: - Wording

/// Everything that differs between the two permission pages.
///
/// Held as data rather than as branches inside the presenter so that adding a third
/// permission is a row here, not a third copy of a page.
private struct PermissionWording {
    let symbolName: String
    let title: String
    let subtitle: String
    let body: String
    let allow: String
    /// What Uttrflow cannot do until this is granted.
    ///
    /// Was `cost` — what *skipping* it cost — from when both of these could be skipped.
    /// Neither can now, so the note is no longer a trade being offered; it is the reason
    /// the page will not move until the switch is on.
    let blocked: OnboardingNote

    static func of(_ kind: PermissionKind) -> PermissionWording {
        switch kind {
        case .microphone: microphone
        case .accessibility: accessibility
        }
    }

    private static let microphone = PermissionWording(
        symbolName: "mic",
        title: "Let Uttrflow hear you",
        subtitle: "It needs your microphone to do anything at all.",
        body: "\(SettingsPresenter.recordingsPromise) Nothing you say is uploaded.",
        allow: "Allow Microphone Access",
        blocked: OnboardingNote(
            symbolName: "exclamationmark.triangle",
            text: PermissionError.microphoneDenied.userMessage,
            tone: .warning)
    )

    private static let accessibility = PermissionWording(
        symbolName: "accessibility",
        title: "Let Uttrflow type for you",
        subtitle: "Accessibility access is how text reaches other apps.",
        body: """
            macOS asks for this because Uttrflow types into apps you have open. It only \
            ever inserts at your cursor — it never reads or changes anything else.
            """,
        allow: "Allow Accessibility Access",
        blocked: OnboardingNote(
            symbolName: "exclamationmark.triangle",
            text: """
                Until this is on, Uttrflow has nowhere to put your words: it cannot type \
                into another app, and setting up cannot go on without it.
                """,
            tone: .warning)
    )
}

// MARK: - Keycaps

/// A shortcut as the keys a person actually presses.
enum OnboardingKeys {
    /// Modifiers in the order macOS draws them, then the key itself.
    static func of(_ binding: HotkeyBinding) -> [String] {
        SettingsShortcut.modifierCaps(for: binding) + [name(for: binding.keyCode)]
    }

    /// The keys a shortcut is realistically bound to, named as the keyboard names them.
    ///
    /// Deliberately short: a hardware key code only becomes a letter through the
    /// current layout, and printing the wrong letter on the last page of onboarding
    /// would be worse than printing the code, which at least cannot mislead.
    private static let names: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
    ]

    private static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
