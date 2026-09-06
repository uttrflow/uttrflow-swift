// What one onboarding page draws: its parts, emphasis, notes, buttons, and what pressing them means.
public import UttrflowAccount
public import UttrflowCore

/// What one onboarding page draws; the view renders this and nothing else.
public struct OnboardingPage: Sendable, Equatable {
    /// SF Symbol for the glyph at the top, or `nil` on the page that shows the mark.
    public let symbolName: String?
    /// How the glyph is drawn.
    public let emphasis: OnboardingEmphasis
    /// The heading.
    public let title: String
    /// The sentence under it.
    public let subtitle: String
    /// The paragraph under the subtitle; absent where the design puts a progress bar there.
    public let body: String?
    /// The quieter caveat under the body, if this page has one.
    public let note: OnboardingNote?
    /// A sign-in code to show when this Mac cannot be redirected back to; typed, unlike ``keys``.
    public let code: String?
    /// Keycaps to draw, for example `["⌥", "Space"]`. Empty on every page but the last.
    public let keys: [String]
    /// Download progress from `0` to `1`, or `nil` when nothing is downloading.
    public let progress: Double?
    /// The stacked provider buttons; empty on every page but sign-in.
    public let providers: [OnboardingProviderButton]
    /// In reading order. The prominent one, where there is one, comes last.
    public let buttons: [OnboardingButton]
    /// The terms a person is agreeing to, on the page itself; only sign-in has one.
    public let fineprint: String?
    /// 1-based position in the row of dots, and how many dots there are.
    public let position: Int
    /// How many dots there are.
    public let stepCount: Int
    /// Read aloud by VoiceOver. Never abbreviated, never an icon name.
    public let accessibilityLabel: String
}

extension OnboardingPage {
    /// Whether there is anything on this page the user can press, counting the provider stack.
    public var hasSomethingToPress: Bool {
        buttons.contains(where: \.isEnabled) || providers.contains(where: \.isEnabled)
    }
}

/// How the glyph at the top of a page is drawn.
public enum OnboardingEmphasis: Sendable, Equatable {
    /// The app's own mark on a lilac wash. The first page only.
    case brand
    /// A plain slab. What a page that is asking for something wears.
    case neutral
    /// Something did not work and the page is about that, drawn unlike a page merely asking.
    case caution
    /// Reserved for the pages that say a piece of the setting up is over.
    case success
}

/// A quieter line under the body, saying what the user is trading away or keeping.
public struct OnboardingNote: Sendable, Equatable {
    /// How loudly the note is drawn, and whether it sits above what it is about or below it.
    public enum Tone: Sendable, Equatable {
        /// Explaining or reassuring. Drawn under the thing it is about.
        case quiet
        /// Something is wrong and the page cannot proceed. Drawn above.
        case warning
    }

    /// The SF Symbol beside the text.
    public let symbolName: String
    /// The sentence.
    public let text: String
    /// How loudly, and where.
    public let tone: Tone

    /// Builds a note; quiet unless said otherwise.
    init(symbolName: String, text: String, tone: Tone = .quiet) {
        self.symbolName = symbolName
        self.text = text
        self.tone = tone
    }
}

/// One provider's button; carries the provider, since each mark is drawn to its owner's rules.
public struct OnboardingProviderButton: Sendable, Equatable {
    /// Which provider.
    public let provider: SignInProvider
    /// What the button says, which each provider dictates rather than we choose.
    public let title: String
    /// Offline, the three stay on screen and inert, which says more than an empty panel.
    public let isEnabled: Bool

    /// Builds the button with the provider's own title.
    init(provider: SignInProvider, isEnabled: Bool) {
        self.provider = provider
        self.title = provider.buttonTitle
        self.isEnabled = isEnabled
    }
}

/// One button on a page.
public struct OnboardingButton: Sendable, Equatable {
    /// The words on the button.
    public let title: String
    /// What pressing it means.
    public let intent: OnboardingIntent
    /// The answer the page is steering towards. At most one per page.
    public let isProminent: Bool
    /// Drawn but not pressable, so the row of buttons keeps its shape while a download runs.
    public let isEnabled: Bool
}

extension OnboardingButton {
    /// The answer the page is steering towards.
    static func prominent(_ title: String, _ intent: OnboardingIntent) -> OnboardingButton {
        OnboardingButton(title: title, intent: intent, isProminent: true, isEnabled: true)
    }

    /// The quieter answer beside it — usually the one that does without something.
    static func plain(_ title: String, _ intent: OnboardingIntent) -> OnboardingButton {
        OnboardingButton(title: title, intent: intent, isProminent: false, isEnabled: true)
    }

    /// Somewhere to look while waiting; carries the intent it will have once it comes alive.
    static func disabled(_ title: String) -> OnboardingButton {
        OnboardingButton(title: title, intent: .advance, isProminent: true, isEnabled: false)
    }
}

/// What pressing a button means.
public enum OnboardingIntent: Sendable, Equatable {
    /// Leave this page, whether as progress or as doing without; the last page reads the consequence.
    case advance

    /// Ask macOS for a permission it has not been asked about yet.
    case requestPermission(PermissionKind)

    /// One of the recoveries the rest of the app speaks, so onboarding offers the same verbs.
    case recover(RecoveryAction)

    /// Stop the download and go on without the model.
    case cancelInstall

    /// Sign in with this provider. The only intent that needs a network.
    case signIn(SignInProvider)

    /// Give up on a sign-in that is somewhere else and go back to the providers.
    case cancelSignIn

    /// Carry on with no account as whoever owns this Mac; records a decision, see ``LocalAccount``.
    case continueOnThisMac

    /// Close onboarding. Only ever offered on the last page.
    case finish
}
