// Turns onboarding state into the page the window draws, plus permission wording and keycaps.
internal import UttrflowAccount
public import UttrflowCore

/// Turns where the user is into what the window draws; the one place the approved designs live.
public enum OnboardingPresenter {
    /// The page for a state, with the shortcut drawn on the last one.
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

    /// What the one online step costs, said only on the sign-in page.
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

    /// The sign-in page in its four forms: offering, unreachable, signing in, and entering a code.
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

    /// Why this Mac is being asked for a code: it cannot listen for the browser's hand-back.
    private static let theCodeIsTheFallback = OnboardingNote(
        symbolName: "arrow.uturn.down",
        text: """
            Uttrflow usually hands you straight back from the browser. This Mac would not \
            let it listen for that, so the code does the same job.
            """)

    /// The banner for a sign-in state.
    private static func note(for signIn: OnboardingSignInState) -> OnboardingNote {
        switch signIn {
        case .unreachable: noConnection
        case .enterCode: theCodeIsTheFallback
        default: onlyThisStepNeedsTheInternet
        }
    }

    /// The sentence under the sign-in title.
    private static func subtitle(for signIn: OnboardingSignInState) -> String {
        switch signIn {
        case .offering, .unreachable:
            """
            Uttrflow keeps your dictionary, your corrections and your snippets under one \
            account. It needs to know which one is yours.
            """
        case .signingIn(let provider):
            "Finish signing in with \(AccountPagePresenter.title(for: provider)) in your browser."
        // The code is the instruction, so the sentence says what to do with it and that the browser is open.
        case .enterCode(let provider, _):
            """
            Your browser is open. Type this code there to finish signing in with \
            \(AccountPagePresenter.title(for: provider)).
            """
        // The provider's own words; the buttons come back live, since another attempt is the remedy.
        case .refused(let message):
            message
        }
    }

    /// The code to read off the screen, on the one page that has one.
    private static func code(for signIn: OnboardingSignInState) -> String? {
        guard case .enterCode(_, let code) = signIn else { return nil }
        return code
    }

    /// The way past this page without an account, plain and second, and present from the start.
    private static let workOnThisMac = OnboardingButton.plain(
        "Continue on this Mac", .continueOnThisMac)

    /// The buttons under the providers.
    private static func buttons(for signIn: OnboardingSignInState) -> [OnboardingButton] {
        switch signIn {
        // The providers are the controls; the only other verb is the way past the page.
        case .offering, .refused:
            [workOnThisMac]
        case .unreachable:
            [.prominent("Try Again", .recover(.retry)), workOnThisMac]
        // Waiting on a browser that may never come back, so giving up stays possible.
        case .signingIn, .enterCode:
            [.plain("Cancel", .cancelSignIn)]
        }
    }

    /// The pitch page.
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

    /// Both permission pages from one shape; the buttons follow the status, and neither page can be skipped.
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

    /// What is not possible until this is granted, shown only once the user has been asked.
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

    /// The download page: in progress, failed, or already done.
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
        // Nothing left to wait for: the model is already on disk, so the user is let past.
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

    /// The last page, which says what the user ended up with, in four endings rather than one.
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

    /// The sentence under a permission page's title.
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

    /// One answer on every form of these pages, always the one that grants the permission.
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
            // Look again, with the settings pane still reachable beside it.
            return [.plain("Open System Settings", pane), .prominent("Check Again", .recover(.retry))]
        case .permission(.restricted):
            // A device policy has decided this, so going on is the only thing left that is true.
            return [.prominent("Continue Without It", .advance)]
        default:
            // Granted, or nothing left to ask for.
            return [.prominent("Continue", .advance)]
        }
    }

    // MARK: Assembly

    /// Fills in everything a page has in common, so each page says only what makes it different.
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
            // Spoken as one sentence, so a screen reader says what the page is and what it wants.
            accessibilityLabel: "\(title). \(subtitle)"
        )
    }
}

// MARK: - Wording

/// Everything that differs between the two permission pages, as data so a third is a row here.
private struct PermissionWording {
    /// The SF Symbol on the page.
    let symbolName: String
    /// The heading.
    let title: String
    /// The sentence under it.
    let subtitle: String
    /// The paragraph explaining why.
    let body: String
    /// The button that asks macOS.
    let allow: String
    /// What Uttrflow cannot do until this is granted: the reason the page will not move on.
    let blocked: OnboardingNote

    /// The wording for a permission.
    static func of(_ kind: PermissionKind) -> PermissionWording {
        switch kind {
        case .microphone: microphone
        case .accessibility: accessibility
        }
    }

    /// The microphone page's words.
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

    /// The Accessibility page's words.
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

    /// The keys a shortcut is realistically bound to; a key code becomes a letter only through the layout.
    private static let names: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
    ]

    /// The key's name, or its code when the name is unknown.
    private static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
