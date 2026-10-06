// What one onboarding page draws: its mood, its picture, its buttons, and what pressing them means.
public import UttrflowAccount
public import UttrflowCore

/// What one onboarding page draws; the view renders this and nothing else.
public struct OnboardingPage: Sendable, Equatable {
    /// The colour of the light behind the card, which says how the page is going.
    public let mood: OnboardingMood
    /// What the top of the card shows.
    public let picture: OnboardingPicture
    /// The heading: one short sentence.
    public let title: String
    /// The round provider buttons; empty on every page but sign-in.
    public let providers: [OnboardingProviderButton]
    /// The round buttons, in reading order.
    public let buttons: [OnboardingButton]
    /// The underlined way out under the buttons, where the page has one.
    public let link: OnboardingLink?
    /// The quiet line under the buttons.
    public let hint: String?
    /// Whether the terms a person agrees to are on the page; only sign-in has them.
    public let showsTerms: Bool
    /// The fuller sentence behind the heading, read by VoiceOver and shown on hover.
    public let explanation: String?
    /// 1-based position in the row of dots.
    public let position: Int
    /// How many dots there are.
    public let stepCount: Int
    /// Read aloud by VoiceOver. Never abbreviated, never an icon name.
    public let accessibilityLabel: String
    /// The line under the heading, on the pages whose heading comes first.
    public var subtitle: String? = nil
    /// Who is signed in, drawn as a chip under the heading.
    public var account: OnboardingAccountChip? = nil
    /// The one full-width button, on the pages that have one instead of round buttons.
    public var action: OnboardingAction? = nil
}

extension OnboardingPage {
    /// Whether there is anything on this page the user can press, counting the providers and the link.
    public var hasSomethingToPress: Bool {
        buttons.contains(where: \.isEnabled) || providers.contains(where: \.isEnabled) || link != nil
            || action != nil
    }
}

/// The light behind the card, one per kind of moment.
public enum OnboardingMood: Sendable, Equatable, CaseIterable {
    /// Asking for something, or offering to begin.
    case brand
    /// Something is under way: a download, a dictation.
    case live
    /// Waiting on somewhere else: a browser or System Settings.
    case waiting
    /// Something is off and the user can put it right.
    case warning
    /// Something did not work.
    case failure
    /// There is no connection.
    case offline
    /// A step is done.
    case done
}

/// What the top of the card shows.
public enum OnboardingPicture: Sendable, Equatable {
    /// A waveform, with a badge over its middle or none.
    case waveform(OnboardingWave, badge: OnboardingBadge?)
    /// A waveform over a text field, showing where dictated words land.
    case typing(OnboardingWave, field: OnboardingField)
    /// A ring around how far the speech model's download has come.
    case download(Double, OnboardingDownload)
    /// The shortcut's keys over the field the first try fills; held while the user is talking.
    case keys([String], isHeld: Bool, field: OnboardingField)
    /// A sign-in code to read off this screen and type into the browser.
    case code(String)
    /// The new account's circle over one burst of confetti.
    case welcome(initials: String, provider: SignInProvider)
    /// The bottom-left keys of a keyboard with the shortcut's keys lit, above the field the first try fills.
    case keyboard(OnboardingKeyboard)
}

/// The try-it picture: which keys to hold, whether they are held, and the field the words land in.
public struct OnboardingKeyboard: Sendable, Equatable {
    /// The shortcut's keys lit on the drawn corner, or `nil` when the corner cannot show the shortcut.
    public let lit: Set<OnboardingCornerKey>?
    /// The shortcut as keycaps, drawn instead of the corner when `lit` is `nil`.
    public let keys: [String]
    /// The words on the bracket over the lit keys, or `nil` for no bracket.
    public let bracket: String?
    /// Whether the keys are down right now.
    public let isHeld: Bool
    /// Whether the lit keys press themselves now and then, to show what holding means.
    public let demonstrates: Bool
    /// The field the words land in.
    public let field: OnboardingField
    /// Whether the field is listening: ringed, with a meter and a clock.
    public let isListening: Bool
    /// Whether confetti bursts over the field once.
    public let celebrates: Bool
}

/// The keys at the bottom-left of a Mac keyboard, left to right.
public enum OnboardingCornerKey: Sendable, Equatable, CaseIterable {
    case function, control, option, command
}

/// The account chip: the provider's mark and the address it signed in with.
public struct OnboardingAccountChip: Sendable, Equatable {
    /// Which provider's mark to draw.
    public let provider: SignInProvider
    /// The address, or the provider's name when there is none.
    public let text: String
}

/// A full-width button, with an optional countdown bar and a caption under it.
public struct OnboardingAction: Sendable, Equatable {
    /// The words on the button.
    public let title: String
    /// What pressing it means.
    public let intent: OnboardingIntent
    /// Teal when it is the page's answer, glass when it is a way past the page.
    public let isProminent: Bool
    /// How long until the page moves on by itself, drawn as a shrinking bar; `nil` for none.
    public let countdown: Duration?
    /// The quiet line under it.
    public let caption: String?
}

/// How lively the waveform is.
public enum OnboardingWave: Sendable, Equatable {
    /// Moving like speech.
    case talking
    /// A slow swell, while something is awaited.
    case idle
    /// Flat dots: nothing heard yet.
    case still
}

/// The disc over the middle of the waveform.
public enum OnboardingBadge: Sendable, Equatable {
    /// The provider's mark inside a turning arc, while the browser has the user.
    case waitingOn(SignInProvider)
    /// An SF Symbol on a disc drawn in a tone.
    case symbol(String, OnboardingBadgeTone)
}

/// How a badge's disc is drawn.
public enum OnboardingBadgeTone: Sendable, Equatable {
    /// A dark disc with a white symbol.
    case neutral
    /// An amber edge and symbol: something the user can turn on.
    case caution
    /// A red disc that shakes once: something failed.
    case failure
}

/// The white text field drawn in the card, never one the user types into.
public enum OnboardingField: Sendable, Equatable {
    /// Grey text saying what will appear there.
    case placeholder(String)
    /// Words being typed in, one character at a time.
    case typing(String)
    /// Words already there.
    case filled(String)
}

/// How the download ring is drawn.
public enum OnboardingDownload: Sendable, Equatable {
    /// Filling, with the percentage in the middle.
    case running
    /// Stopped where it was, in red.
    case stopped
    /// Full, with the mark in the middle.
    case finished
}

/// One provider's round button; carries the provider, since each mark is drawn to its owner's rules.
public struct OnboardingProviderButton: Sendable, Equatable {
    /// Which provider.
    public let provider: SignInProvider
    /// The provider's name under the button.
    public let label: String
    /// What VoiceOver says, which each provider dictates rather than we choose.
    public let title: String
    /// Whether it can be pressed; a sign-in under way leaves none live.
    public let isEnabled: Bool

    /// Builds the button with the provider's own wording.
    init(provider: SignInProvider, isEnabled: Bool) {
        self.provider = provider
        self.label = AccountPagePresenter.title(for: provider)
        self.title = provider.buttonTitle
        self.isEnabled = isEnabled
    }
}

/// One round button on a page.
public struct OnboardingButton: Sendable, Equatable {
    /// The word under the button.
    public let title: String
    /// The SF Symbol inside it.
    public let symbolName: String
    /// What pressing it means.
    public let intent: OnboardingIntent
    /// The answer the page is steering towards, drawn white. At most one per page.
    public let isProminent: Bool
    /// Drawn but not pressable, so the row keeps its shape while a download runs.
    public let isEnabled: Bool
    /// Whether a hand-drawn arrow points at it, for the one press a page cannot do without.
    public let isPointedAt: Bool
    /// The option currently chosen in a pair of choices, drawn ringed rather than white.
    public var isSelected = false
}

extension OnboardingButton {
    /// The answer the page is steering towards.
    static func prominent(
        _ title: String, _ symbolName: String, _ intent: OnboardingIntent
    ) -> OnboardingButton {
        OnboardingButton(
            title: title, symbolName: symbolName, intent: intent, isProminent: true, isEnabled: true,
            isPointedAt: false)
    }

    /// The answer the page steers towards, with an arrow saying this is the one to press.
    static func pointed(_ title: String, _ symbolName: String, _ intent: OnboardingIntent) -> OnboardingButton
    {
        OnboardingButton(
            title: title, symbolName: symbolName, intent: intent, isProminent: true, isEnabled: true,
            isPointedAt: true)
    }

    /// A quieter answer beside it.
    static func plain(_ title: String, _ symbolName: String, _ intent: OnboardingIntent) -> OnboardingButton {
        OnboardingButton(
            title: title, symbolName: symbolName, intent: intent, isProminent: false, isEnabled: true,
            isPointedAt: false)
    }

    /// One of a pair of choices, ringed when it is the current one; never the page's answer.
    static func choice(
        _ title: String, _ symbolName: String, _ intent: OnboardingIntent, isSelected: Bool
    ) -> OnboardingButton {
        OnboardingButton(
            title: title, symbolName: symbolName, intent: intent, isProminent: false, isEnabled: true,
            isPointedAt: false, isSelected: isSelected)
    }

    /// Somewhere to look while waiting; carries the intent it will have once it comes alive.
    static func disabled(_ title: String, _ symbolName: String) -> OnboardingButton {
        OnboardingButton(
            title: title, symbolName: symbolName, intent: .advance, isProminent: true, isEnabled: false,
            isPointedAt: false)
    }
}

/// The underlined words under the buttons: a way on that is not the page's answer.
public struct OnboardingLink: Sendable, Equatable {
    /// The words.
    public let title: String
    /// What pressing them means.
    public let intent: OnboardingIntent
}

/// What pressing a button means.
public enum OnboardingIntent: Sendable, Equatable {
    /// Leave this page; offered only once the page's question is answered.
    case advance

    /// Ask macOS for a permission it has not been asked about yet.
    case requestPermission(PermissionKind)

    /// One of the recoveries the rest of the app speaks, so onboarding offers the same verbs.
    case recover(RecoveryAction)

    /// Stop the download; the page then offers to start it again.
    case cancelInstall

    /// Sign in with this provider. The only intent that needs a network.
    case signIn(SignInProvider)

    /// Open the provider's page in the browser again, for a tab the user closed.
    case reopenBrowser

    /// Give up on a sign-in that is somewhere else and go back to the providers.
    case cancelSignIn

    /// Choose whether usage statistics are shared.
    case setUsageStatistics(Bool)

    /// Close onboarding. Only ever offered on the last page.
    case finish
}
