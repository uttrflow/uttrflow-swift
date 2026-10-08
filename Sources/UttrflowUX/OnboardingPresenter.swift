// Turns onboarding state into the card the window draws, plus permission wording and keycaps.
internal import UttrflowAccount
public import UttrflowCore
public import UttrflowSettings

/// Turns where the user is into what the window draws; the one place the approved designs live.
public enum OnboardingPresenter {
    /// The page for a state, with the shortcut and how it is pressed drawn on the last one.
    public static func page(
        for state: OnboardingState, hotkey: HotkeyBinding, activation: HotkeyActivation = .holdToTalk,
        shortcuts: ShortcutSet = .default,
        signsInAsStandIn: Bool = false, sharesUsageStatistics: Bool = false,
        clipboardEnabled: Bool = true,
        clipboardRetentionDays: Int = Settings.defaultRetentionDays
    ) -> OnboardingPage {
        switch state.step {
        case .signIn: signIn(state, standIn: signsInAsStandIn, sharesUsageStatistics: sharesUsageStatistics)
        case .clipboard: clipboard(state, isEnabled: clipboardEnabled, days: clipboardRetentionDays)
        case .microphone: permission(.microphone, state)
        case .accessibility: permission(.accessibility, state)
        case .setup: setup(state)
        case .ready: ready(state, hotkey: hotkey, activation: activation, shortcuts: shortcuts)
        }
    }

    // MARK: Sign-in

    /// What Uttrflow is for, said on the page that asks who you are.
    static let pitch = """
        Use a shortcut, say what you mean, and Uttrflow writes it into whatever app you’re in — \
        punctuated, tidied, and without the “um”s. Sign in once, and after that it runs \
        entirely on this Mac.
        """

    /// Said under the providers in a development build, whose sign-in asks nobody.
    static let standInHint = "Development build: signs in as a stand-in, no browser"

    /// The sign-in page in its six forms: offering, unreachable, in the browser, entering a code, refused, welcomed.
    private static func signIn(
        _ state: OnboardingState, standIn: Bool = false, sharesUsageStatistics: Bool = false
    ) -> OnboardingPage {
        let signIn = state.detail.signIn
        let providers = SignInProvider.offered.map {
            OnboardingProviderButton(provider: $0, isEnabled: signIn.acceptsAProvider)
        }
        let waiting = [
            OnboardingButton.plain("Reopen", "macwindow", .reopenBrowser),
            .plain("Cancel", "xmark", .cancelSignIn),
        ]
        switch signIn {
        case .offering:
            return page(
                state, mood: .brand, picture: .waveform(.talking, badge: nil), title: "Just talk.",
                providers: providers,
                buttons: [
                    .choice(
                        "Keep off", "hand.raised", .setUsageStatistics(false),
                        isSelected: !sharesUsageStatistics),
                    .choice(
                        "Share", "chart.bar", .setUsageStatistics(true),
                        isSelected: sharesUsageStatistics),
                ],
                hint: standIn ? standInHint : nil, showsTerms: true,
                explanation: pitch + " Usage statistics are off unless you choose to share them.")
        case .refused(let message):
            return page(
                state, mood: .failure, picture: .waveform(.still, badge: .symbol("xmark", .failure)),
                title: "That didn’t work.", providers: providers, hint: message, showsTerms: true,
                explanation: message)
        case .unreachable:
            return page(
                state, mood: .offline,
                picture: .waveform(.still, badge: .symbol("wifi.slash", .neutral)),
                title: "You’re offline.",
                buttons: [.prominent("Try again", "arrow.clockwise", .recover(.retry))],
                explanation: """
                    Signing in is the one thing Uttrflow needs the internet for. Connect and \
                    try again.
                    """)
        case .signingIn(let provider):
            return page(
                state, mood: .waiting, picture: .waveform(.idle, badge: .waitingOn(provider)),
                title: "Check your browser.", buttons: waiting,
                explanation:
                    "Finish signing in with \(AccountPagePresenter.title(for: provider)) in your browser.")
        case .welcomed(let welcome):
            return welcomed(state, welcome)
        case .enterCode(let provider, let code):
            return page(
                state, mood: .waiting, picture: .code(code), title: "Type this code.", buttons: waiting,
                hint: "In your browser, to finish with \(AccountPagePresenter.title(for: provider))",
                explanation: """
                    Your browser is open. Type this code there to finish signing in with \
                    \(AccountPagePresenter.title(for: provider)).
                    """)
        }
    }

    /// How long the welcome shows before onboarding moves on by itself.
    public static let welcomeLinger = Duration.seconds(3)

    /// The moment after signing in: the circle, a greeting, the account, and Continue.
    private static func welcomed(_ state: OnboardingState, _ welcome: OnboardingWelcome) -> OnboardingPage {
        let greeting = welcome.firstName.map { "You’re in, \($0)!" } ?? "You’re in!"
        var page = page(
            state, mood: .done, picture: .welcome(initials: welcome.initials, provider: welcome.provider),
            title: greeting, explanation: "Signed in. Welcome to Uttrflow.")
        page.subtitle = "Welcome to Uttrflow. Let’s get you talking."
        page.account = OnboardingAccountChip(
            provider: welcome.provider,
            text: welcome.emailAddress ?? AccountPagePresenter.title(for: welcome.provider))
        page.action = OnboardingAction(
            title: "Continue", intent: .advance, isProminent: true, countdown: welcomeLinger,
            caption: "Next: \(nextStep(welcome.next))")
        return page
    }

    /// What the page after the welcome asks for, finishing "Next: …".
    static func nextStep(_ step: OnboardingStep) -> String {
        switch step {
        case .clipboard: "choose whether copies are kept"
        case .signIn, .microphone: "allow the microphone"
        case .accessibility: "let Uttrflow type for you"
        case .setup: "download the speech model"
        case .ready: "try your first dictation"
        }
    }

    // MARK: The clipboard

    /// Says that copies are kept, for how long and where, with the choice to keep them or not.
    private static func clipboard(_ state: OnboardingState, isEnabled: Bool, days: Int) -> OnboardingPage {
        let period = days == 1 ? "1 day" : "\(days) days"
        let off = "Copies are not kept while this is off. Turn it on in Settings › General."
        return page(
            state, mood: .brand, picture: .waveform(.still, badge: .symbol("list.clipboard", .neutral)),
            title: "Keep what you copy?",
            buttons: [
                .choice("Keep", "list.clipboard", .setClipboardEnabled(true), isSelected: isEnabled),
                .choice("Turn off", "hand.raised", .setClipboardEnabled(false), isSelected: !isEnabled),
                .prominent("Continue", "arrow.right", .advance),
            ],
            hint: isEnabled
                ? """
                Uttrflow keeps what you copy for up to \(period). It stays on this Mac. \
                Change it in Settings › General.
                """
                : off,
            explanation: isEnabled
                ? """
                Uttrflow keeps what you copy for up to \(period), so you can paste it again from the \
                Clipboard panel. Clips you pin, name or put in a collection have no time limit. Turn it \
                off, or exclude apps, in Settings › General.
                """
                : off)
    }

    // MARK: Permissions

    /// Both permission pages from one shape; neither can be left until it is granted.
    private static func permission(
        _ kind: PermissionKind, _ state: OnboardingState
    ) -> OnboardingPage {
        let wording = PermissionWording.of(kind)
        let pane = OnboardingIntent.recover(.openSystemSettings(kind.settingsPane))
        let settings = OnboardingButton.plain("Settings", "gearshape", pane)
        let allow = OnboardingButton.pointed("Allow", wording.symbolName, .requestPermission(kind))
        switch state.detail {
        case .permission(.granted):
            return page(
                state, mood: .done, picture: wording.picture(.talking, .granted),
                title: wording.grantedTitle, buttons: [.prominent("Continue", "arrow.right", .advance)])
        case .permission(.restricted):
            return page(
                state, mood: .warning, picture: wording.picture(.still, .blocked),
                title: wording.blockedTitle,
                buttons: [.prominent("Continue", "arrow.right", .advance)],
                hint: "A device policy turns this off", explanation: wording.refused)
        case .awaitingSystemSettings:
            return page(
                state, mood: .waiting, picture: wording.picture(.idle, .waiting),
                title: "Flip the switch.",
                buttons: [settings, .prominent("Check", "arrow.clockwise", .recover(.retry))],
                hint: "Privacy & Security › \(wording.paneName)", explanation: wording.refused)
        // Accessibility reads as refused before anyone has been asked, so its first answer is still the ask.
        case .permission(.denied) where kind.reportsNotDetermined:
            return page(
                state, mood: .warning, picture: wording.picture(.still, .refused),
                title: wording.refusedTitle,
                buttons: [.pointed("Settings", "gearshape", pane)], explanation: wording.refused)
        default:
            return page(
                state, mood: .brand, picture: wording.picture(.still, .asking), title: wording.askTitle,
                buttons: [allow], hint: wording.askHint, explanation: wording.why)
        }
    }

    // MARK: The download

    /// The download page: running, stopped, or done; it cannot be left until the model is on disk.
    private static func setup(_ state: OnboardingState) -> OnboardingPage {
        switch state.detail {
        case .installing(let fraction):
            page(
                state, mood: .live, picture: .download(fraction, .running), title: "Tuning in.",
                buttons: [.plain("Cancel", "xmark", .cancelInstall), .disabled("Continue", "arrow.right")],
                hint: "One-time download · stays on this Mac", explanation: staysOnThisMac)
        case .installFailed(let message, let reached):
            page(
                state, mood: .failure, picture: .download(reached, .stopped), title: "Download stopped.",
                buttons: [.prominent("Try again", "arrow.clockwise", .recover(.downloadSpeechModel))],
                hint: message, explanation: message)
        // Nothing left to wait for: the model is on disk, so the user is let past.
        default:
            page(
                state, mood: .done, picture: .download(1, .finished), title: "Ready to listen.",
                buttons: [.prominent("Continue", "arrow.right", .advance)], explanation: staysOnThisMac)
        }
    }

    /// Why the wait is worth it, said on every form of the download page.
    static let staysOnThisMac = """
        A one-time download. Once it finishes, dictation runs on this Mac — it keeps working \
        with Wi-Fi off, on a plane, anywhere.
        """

    // MARK: The last page

    /// The last page: a first try when dictation can work, else what still stands in the way.
    private static func ready(
        _ state: OnboardingState, hotkey: HotkeyBinding, activation: HotkeyActivation,
        shortcuts: ShortcutSet
    ) -> OnboardingPage {
        switch state.detail.readiness ?? .ready {
        case .ready, .pastesManually:
            trying(state, hotkey: hotkey, activation: activation, shortcuts: shortcuts)
        case .needsSpeechModel:
            page(
                state, mood: .warning, picture: .download(0, .stopped),
                title: "One thing left to download.",
                buttons: [
                    .plain("Download", "arrow.down", .recover(.downloadSpeechModel)),
                    .prominent("Close", "xmark", .finish),
                ],
                hint: "Nothing is recognised until it finishes",
                explanation: SpeechEngineError.modelNotInstalled.userMessage)
        case .needsMicrophone:
            page(
                state, mood: .warning, picture: .waveform(.still, badge: .symbol("mic.slash", .caution)),
                title: "Can’t hear you yet.",
                buttons: [
                    .plain("Settings", "gearshape", .recover(.openSystemSettings(.microphone))),
                    .prominent("Close", "xmark", .finish),
                ],
                hint: "Turn on the microphone to dictate",
                explanation: PermissionError.microphoneDenied.userMessage)
        }
    }

    /// How long the words from the first try show before onboarding closes.
    public static let heardLinger = Duration.seconds(3)

    /// The first try: the keyboard's corner with the shortcut lit, the field the words land in, and Skip.
    private static func trying(
        _ state: OnboardingState, hotkey: HotkeyBinding, activation: HotkeyActivation,
        shortcuts: ShortcutSet
    ) -> OnboardingPage {
        let keys = OnboardingKeys.of(hotkey)
        let lit = OnboardingKeys.corner(of: hotkey)
        let holds = activation == .holdToTalk
        let named = OnboardingKeys.spoken(keys)
        let skip = OnboardingAction(
            title: "Skip to dashboard", intent: .finish, isProminent: false, countdown: nil, caption: nil)
        let copies = state.detail.readiness == .pastesManually
        let clipboardHint =
            shortcuts.first(for: .clipboard).map {
                "Open the Clipboard panel with \(SettingsShortcut.compact($0)) to browse and paste recent copies."
            } ?? "Open the Clipboard panel from the menu bar to browse and paste recent copies."
        let bracket = keys.count > 1 ? (holds ? "HOLD BOTH" : "PRESS BOTH") : (holds ? "HOLD" : "PRESS")
        var page: OnboardingPage
        switch state.detail.trial {
        case .waiting:
            page = self.page(
                state, mood: .brand,
                picture: .keyboard(
                    OnboardingKeyboard(
                        lit: lit, keys: keys, bracket: bracket, isHeld: false, demonstrates: true,
                        field: .placeholder("Your words appear here"), isListening: false, celebrates: false)),
                title: "Try it now.",
                hint: copies
                    ? "Without Accessibility, words are copied for you to paste. \(clipboardHint)"
                    : clipboardHint,
                explanation:
                    "Try it now. Uttrflow lives in your menu bar whenever you need it. \(clipboardHint)")
            page.subtitle =
                holds
                ? "Click a text field in another app, then hold \(named), say anything, then let go."
                : "Click a text field in another app, then press \(named), say anything, then press again."
            page.action = skip
        case .listening:
            page = self.page(
                state, mood: .live,
                picture: .keyboard(
                    OnboardingKeyboard(
                        lit: lit, keys: keys, bracket: holds ? "HOLDING" : "LISTENING", isHeld: holds,
                        demonstrates: false, field: .placeholder("Say anything…"), isListening: true,
                        celebrates: false)),
                title: "Listening…")
            page.subtitle =
                holds
                ? "Keep holding while you talk. Let go when you’re done." : "Press again when you’re done."
            page.action = skip
        case .stillLoading:
            page = self.page(
                state, mood: .brand,
                picture: .keyboard(
                    OnboardingKeyboard(
                        lit: lit, keys: keys, bracket: bracket, isHeld: false, demonstrates: true,
                        field: .placeholder("Your words appear here"), isListening: false, celebrates: false)),
                title: "Try it now.", hint: SpeechModelLoad.loading(elapsed: .zero).detail,
                explanation: "Try it now. Uttrflow lives in your menu bar whenever you need it.")
            page.subtitle =
                holds
                ? "Hold \(named), say anything, then let go."
                : "Press \(named), say anything, then press again."
            page.action = skip
        case .heard(let words):
            page = self.page(
                state, mood: .done,
                picture: .keyboard(
                    OnboardingKeyboard(
                        lit: [], keys: keys, bracket: nil, isHeld: false, demonstrates: false,
                        field: .filled(words), isListening: false, celebrates: true)),
                title: "It works!")
            page.subtitle = "That’s all there is to it. Opening your dashboard…"
            page.action = OnboardingAction(
                title: "Open dashboard", intent: .finish, isProminent: true, countdown: heardLinger,
                caption: nil)
        }
        return page
    }

    // MARK: Assembly

    /// Fills in everything a page has in common, so each page says only what makes it different.
    private static func page(
        _ state: OnboardingState,
        mood: OnboardingMood,
        picture: OnboardingPicture,
        title: String,
        providers: [OnboardingProviderButton] = [],
        buttons: [OnboardingButton] = [],
        link: OnboardingLink? = nil,
        hint: String? = nil,
        showsTerms: Bool = false,
        explanation: String? = nil
    ) -> OnboardingPage {
        OnboardingPage(
            mood: mood,
            picture: picture,
            title: title,
            providers: providers,
            buttons: buttons,
            link: link,
            hint: hint,
            showsTerms: showsTerms,
            explanation: explanation,
            position: state.step.position,
            stepCount: OnboardingStep.count,
            // Spoken as one sentence, so a screen reader says what the page is and what it wants.
            accessibilityLabel: [title, explanation ?? hint].compactMap(\.self).joined(separator: " ")
        )
    }
}

// MARK: - Wording

/// Everything that differs between the two permission pages, as data so a third is a row here.
private struct PermissionWording {
    /// Which answer a permission page is drawing.
    enum Moment { case asking, waiting, refused, granted, blocked }

    /// Which permission this is.
    let kind: PermissionKind
    /// The SF Symbol on the Allow button and the badge.
    let symbolName: String
    /// The heading before anything is granted.
    let askTitle: String
    /// The heading once it is granted.
    let grantedTitle: String
    /// The heading after a refusal.
    let refusedTitle: String
    /// The heading when a device policy decides.
    let blockedTitle: String
    /// The line under the Allow button.
    let askHint: String
    /// The name of the list it is switched on in, under Privacy & Security.
    let paneName: String
    /// Why it is asked for, read by VoiceOver and shown on hover.
    let why: String
    /// What is not possible until it is granted.
    let refused: String

    /// The wording for a permission.
    static func of(_ kind: PermissionKind) -> PermissionWording {
        switch kind {
        case .microphone: microphone
        case .accessibility: accessibility
        }
    }

    /// The card's picture for one moment: the microphone badges the waveform, Accessibility fills a field.
    func picture(_ wave: OnboardingWave, _ moment: Moment) -> OnboardingPicture {
        guard kind == .microphone else {
            return .typing(wave, field: Self.field(for: moment))
        }
        switch moment {
        case .granted: return .waveform(wave, badge: nil)
        case .asking: return .waveform(wave, badge: .symbol(symbolName, .neutral))
        case .waiting: return .waveform(wave, badge: .symbol("gearshape", .neutral))
        case .refused, .blocked: return .waveform(wave, badge: .symbol("mic.slash", .caution))
        }
    }

    /// What the Accessibility page's field says at each moment.
    private static func field(for moment: Moment) -> OnboardingField {
        switch moment {
        case .asking: .placeholder("Your words go here")
        case .waiting: .placeholder("Waiting for access…")
        case .granted: .typing("See you Thursday at 10.")
        case .refused, .blocked: .placeholder("Typing is turned off")
        }
    }

    /// The microphone page's words.
    private static let microphone = PermissionWording(
        kind: .microphone,
        symbolName: "mic",
        askTitle: "Let me hear you.",
        grantedTitle: "Loud and clear.",
        refusedTitle: "Mic is off.",
        blockedTitle: "Mic is blocked.",
        askHint: "Stays on this Mac",
        paneName: "Microphone",
        why: "\(SettingsPresenter.recordingsPromise) Nothing you say is uploaded.",
        refused: PermissionError.microphoneDenied.userMessage
    )

    /// The Accessibility page's words.
    private static let accessibility = PermissionWording(
        kind: .accessibility,
        symbolName: "accessibility",
        askTitle: "Let me type for you.",
        grantedTitle: "Ready to type.",
        refusedTitle: "Typing is off.",
        blockedTitle: "Typing is blocked.",
        askHint: "Words land where your cursor is",
        paneName: "Accessibility",
        why: """
            macOS asks for this because Uttrflow types into apps you have open. It only ever \
            inserts at your cursor — it never reads or changes anything else.
            """,
        refused: """
            Until this is on, Uttrflow cannot type into another app. It will put your words on \
            the clipboard instead, for you to paste.
            """
    )
}

// MARK: - Keycaps

/// A shortcut as the keys a person actually presses.
enum OnboardingKeys {
    /// Modifiers in the order macOS draws them, then the key itself.
    static func of(_ binding: HotkeyBinding) -> [String] {
        SettingsShortcut.keycaps(for: binding)
    }

    /// The shortcut lit on the keyboard's bottom-left corner, or `nil` when it uses a key the corner lacks.
    static func corner(of binding: HotkeyBinding) -> Set<OnboardingCornerKey>? {
        if binding.keyCode == HotkeyBinding.functionKeyCode, binding.modifiers.isEmpty { return [.function] }
        guard let named = HotkeyBinding.modifier(ofKeyCode: binding.keyCode) else { return nil }
        var lit = Set<OnboardingCornerKey>()
        for modifier in binding.modifiers.union([named]) {
            switch modifier {
            case .control: lit.insert(.control)
            case .option: lit.insert(.option)
            case .command: lit.insert(.command)
            case .shift: return nil
            }
        }
        return lit
    }

    /// The keys as words for a sentence: "control and option".
    static func spoken(_ keys: [String]) -> String {
        let words = keys.map { spokenNames[$0] ?? $0 }
        guard words.count > 1, let last = words.last else { return words.first ?? "the shortcut" }
        return words.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Each modifier's glyph as the word printed on the key.
    private static let spokenNames = [
        "⌃": "control", "⌥": "option", "⇧": "shift", "⌘": "command", "fn": "fn",
    ]

}
